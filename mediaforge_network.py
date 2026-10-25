"""
MediaSaver 网络传输核心 (mediaforge_network.py)

下载机制移植自 MediaCrawler (github.com/NanmiCoder/MediaCrawler) media_downloader 的工程设计:
- 两级重试: 单地址内指数退避 + full jitter; 429/5xx/网络错误可重试, 4xx 致命状态码短路
- 断点续传: .part 临时文件带 URL 指纹, 带内 Range 续传, 206/200/416 分支处理
- 完整性校验: Content-Range 与 Content-Length 大小核对; text/html 错误页拦截
- 原子落盘: 下载完整后才 os.replace 到目标路径, 失败绝不留半成品
"""

import hashlib
import os
import random
import ssl
import subprocess
import sys
import time
import urllib.error
import urllib.request
from typing import Callable, Dict, List, Optional, Tuple

__all__ = [
    "make_ssl_context", "FetchError", "http_get", "download_file",
    "open_url", "retry_delay", "FATAL_STATUS_CODES",
]

# 重试无意义的状态码: 403 多为签名过期/防盗链, 404/410 资源不存在 (对齐 MediaCrawler FATAL_STATUS_CODES)
FATAL_STATUS_CODES = frozenset({400, 401, 403, 404, 405, 410, 451})


def make_ssl_context():
    context = ssl.create_default_context()
    if sys.platform == "darwin":
        try:
            roots = subprocess.run(
                ["/usr/bin/security", "find-certificate", "-a", "-p",
                 "/System/Library/Keychains/SystemRootCertificates.keychain"],
                capture_output=True, text=True, check=True, timeout=5,
            ).stdout
            if roots:
                context.load_verify_locations(cadata=roots)
        except (OSError, subprocess.SubprocessError, ssl.SSLError):
            # 仍保留 Python 的默认信任配置，绝不降级为跳过证书验证。
            pass
    return context


SSL_CTX = make_ssl_context()


class FetchError(RuntimeError):
    """语义化网络错误: fatal=True 表示重试无意义, 调用方应直接换通道/报错"""

    def __init__(self, message: str, *, fatal: bool = False, status: Optional[int] = None):
        super().__init__(message)
        self.fatal = fatal
        self.status = status


def retry_delay(attempt: int, base: float = 1.0, cap: float = 30.0) -> float:
    """指数退避 + full jitter (对齐 MediaCrawler _retry_delay): 随机区间避免多任务同步重试"""
    ceiling = min(base * (2 ** attempt), cap)
    return random.uniform(0, ceiling)


def build_opener(proxy: Optional[str]):
    handlers = [urllib.request.HTTPSHandler(context=SSL_CTX)]
    if proxy:
        handlers.append(urllib.request.ProxyHandler({
            "http": proxy, "https": proxy,
        }))
    return urllib.request.build_opener(*handlers)


def open_url(req: urllib.request.Request, timeout: float = 25, proxy: Optional[str] = None):
    return build_opener(proxy).open(req, timeout=timeout)


def _classify_http_error(e: urllib.error.HTTPError) -> FetchError:
    if e.code in FATAL_STATUS_CODES:
        return FetchError(f"HTTP {e.code} (不可重试)", fatal=True, status=e.code)
    # 429 限流 / 5xx 服务端波动 → 可重试
    return FetchError(f"HTTP {e.code}", fatal=False, status=e.code)


def http_get(
    url: str,
    headers: Optional[Dict[str, str]] = None,
    timeout: float = 25,
    retries: int = 3,
    proxy_candidates: Tuple[Optional[str], ...] = (None,),
) -> str:
    """GET 请求返回文本; 代理候选依序降级, 单代理内指数退避重试"""
    last_err: Optional[Exception] = None
    for proxy in proxy_candidates:
        for attempt in range(retries + 1):
            try:
                req = urllib.request.Request(url, headers=headers or {})
                with open_url(req, timeout=timeout, proxy=proxy) as resp:
                    return resp.read().decode("utf-8", errors="ignore")
            except urllib.error.HTTPError as e:
                err = _classify_http_error(e)
                if err.fatal:
                    last_err = err
                    break  # 换代理候选也无意义时仍尝试下一候选(不同出口 IP), 但不再退避重试
                last_err = err
            except (urllib.error.URLError, OSError, TimeoutError) as e:
                last_err = e
            if attempt < retries:
                time.sleep(retry_delay(attempt))
    raise last_err or FetchError(f"请求失败: {url}")


def _url_fingerprint(url: str) -> str:
    return hashlib.sha1(url.encode("utf-8")).hexdigest()[:8]


def _parse_content_range(value: Optional[str]) -> Optional[Tuple[int, int, int]]:
    """解析 'bytes start-end/total'; total 为 '*' 或缺失时返回 None (无法校验完整性)"""
    if not value or not value.startswith("bytes "):
        return None
    try:
        rng, _, total_raw = value[len("bytes "):].partition("/")
        start_s, _, end_s = rng.partition("-")
        if total_raw in ("", "*"):
            return None
        return int(start_s), int(end_s), int(total_raw)
    except ValueError:
        return None


def download_file(
    url: str,
    output_path: str,
    headers: Optional[Dict[str, str]] = None,
    timeout: float = 40,
    retries: int = 3,
    proxy_candidates: Tuple[Optional[str], ...] = (None,),
    progress_cb: Optional[Callable[[int, int], None]] = None,
    progress_interval_sec: float = 0.5,
    fatal_status_codes: frozenset = FATAL_STATUS_CODES,
) -> str:
    """
    健壮下载核心: 断点续传 + 大小校验 + 错误页拦截 + 原子落盘。
    成功返回最终路径 (output_path); 抛 FetchError (fatal 标记语义)。
    """
    os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)
    part_path = f"{output_path}.{_url_fingerprint(url)}.part"

    base_headers = dict(headers or {})
    base_headers.setdefault("Accept-Encoding", "identity")  # 禁压缩: 保证字节数与 Content-Length 可核对

    last_err: Optional[Exception] = None
    try:
        for proxy in proxy_candidates:
            for attempt in range(retries + 1):
                try:
                    resume_from = os.path.getsize(part_path) if os.path.exists(part_path) else 0
                    req_headers = dict(base_headers)
                    mode = "wb"
                    if resume_from > 0:
                        req_headers["Range"] = f"bytes={resume_from}-"

                    req = urllib.request.Request(url, headers=req_headers)
                    with open_url(req, timeout=timeout, proxy=proxy) as resp:
                        status = getattr(resp, "status", 200) or 200
                        content_type = (resp.headers.get("Content-Type") or "").lower()

                        if status == 416:
                            # 本地片段已失效, 丢弃后重下
                            try:
                                os.remove(part_path)
                            except OSError:
                                pass
                            raise FetchError("416 本地续传片段失效, 已重置", fatal=False, status=416)

                        if "text/html" in content_type:
                            # 防盗链/限流错误页: 若已写入的字节是此前合法前缀则保留, 本轮不写入
                            raise FetchError("服务端返回 text/html 错误页 (疑似防盗链或限流)",
                                             fatal=False)

                        if status == 206:
                            rng = _parse_content_range(resp.headers.get("Content-Range"))
                            if rng is None or rng[0] != resume_from:
                                try:
                                    os.remove(part_path)
                                except OSError:
                                    pass
                                raise FetchError("Content-Range 异常, 已重置续传", fatal=False, status=206)
                            total_size = rng[2]
                            mode = "ab"
                        else:
                            # 服务端无视 Range, 从头完整返回
                            resume_from = 0
                            total_size = int(resp.headers.get("Content-Length") or 0)
                            mode = "wb"

                        downloaded = resume_from
                        chunk_size = 128 * 1024
                        last_report = 0.0
                        with open(part_path, mode) as f:
                            while True:
                                chunk = resp.read(chunk_size)
                                if not chunk:
                                    break
                                f.write(chunk)
                                downloaded += len(chunk)
                                now = time.time()
                                if progress_cb and now - last_report >= progress_interval_sec:
                                    last_report = now
                                    try:
                                        progress_cb(downloaded, total_size)
                                    except Exception:
                                        pass

                    if total_size > 0 and downloaded != total_size:
                        raise FetchError(f"大小不符: 实际 {downloaded} 字节, 期望 {total_size} 字节", fatal=False)

                    os.replace(part_path, output_path)  # 原子落盘: 不完整文件绝不以最终名出现
                    return output_path

                except urllib.error.HTTPError as e:
                    err = _classify_http_error(e)
                    last_err = err
                    if e.code in fatal_status_codes:
                        break  # 致命状态码: 本候选地址放弃, 换下一代理/通道
                except FetchError as e:
                    last_err = e
                except (urllib.error.URLError, OSError, TimeoutError) as e:
                    last_err = e
                if attempt < retries:
                    time.sleep(retry_delay(attempt))
    finally:
        # 可重试失败保留 .part 供续传; 致命失败时清掉 (直链签名失效后残片无复用价值)
        if isinstance(last_err, FetchError) and getattr(last_err, "fatal", False):
            try:
                os.remove(part_path)
            except OSError:
                pass

    raise last_err if isinstance(last_err, FetchError) else FetchError(f"下载失败: {url}: {last_err}")
