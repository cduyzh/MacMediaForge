#!/usr/bin/env python3
"""
Xiaohongshu (小红书) 视频下载器
支持从小红书分享文本、短链(xhslink.com)、移动端长链及网页链接中解析并下载最高画质视频。

采用四层高可用容错架构：
  1. KuKuTool 协议通道：完整对齐最新版凭证鉴权、AES-GCM 请求加密与 kukudemethod 响应解密
  2. 开源启发式直链提取通道：借鉴开源社区 (wanyi-watermark / XHS-Downloader) 算法，多源提取无水印直链
     - 支持用户自定义/浏览器导出的 Cookie 与 xsec_token 鉴权
  3. 社区高可用短视频去水印/解析微服务聚合通道
  4. yt-dlp 兼容降级通道
"""

import sys
import os
import re
import json
import time
import base64
import random
import hashlib
import ssl
import urllib.request
import urllib.parse
import http.cookiejar
from typing import Optional, Dict, Any, Tuple, List

# 忽略 SSL 证书验证以兼容各种系统环境
from mediaforge_network import make_ssl_context

SSL_CTX = make_ssl_context()

DEFAULT_UA = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/131.0.0.0 Safari/537.36"
)

MOBILE_UA = (
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_2 like Mac OS X) "
    "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
)

def log_progress(msg: str):
    """向标准输出打印进度，供 Swift 调用方捕获"""
    print(msg, flush=True)

# MARK: - 鉴权配置管理
def get_auth_config_paths() -> List[str]:
    """返回鉴权配置文件的可能路径列表"""
    home = os.path.expanduser("~")
    return [
        os.path.join(home, "Library", "Application Support", "cduyzhMediaForge", "xhs_auth.json"),
        os.path.join(home, "Library", "Application Support", "LivePhotoForge", "xhs_auth.json"),
        os.path.join(home, ".cduyzh_mediaforge_xhs_auth.json"),
        os.path.join(home, ".livephotoforge_xhs_auth.json"),
        os.path.join(home, ".config", "cduyzh_mediaforge", "xhs_auth.json")
    ]

def load_auth_config() -> Dict[str, str]:
    """从本地配置文件或环境变量中读取小红书鉴权信息"""
    cfg = {"cookie": "", "xsec_token": ""}
    
    # 1. 尝试从已知配置文件路径加载
    for p in get_auth_config_paths():
        if os.path.exists(p):
            try:
                with open(p, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    if isinstance(data, dict):
                        if data.get("cookie"):
                            cfg["cookie"] = str(data["cookie"]).strip()
                        if data.get("xsec_token"):
                            cfg["xsec_token"] = str(data["xsec_token"]).strip()
                        break
            except Exception:
                pass

    # 2. 环境变量优先覆盖
    if os.environ.get("XHS_COOKIE"):
        cfg["cookie"] = os.environ["XHS_COOKIE"].strip()
    if os.environ.get("XHS_TOKEN"):
        cfg["xsec_token"] = os.environ["XHS_TOKEN"].strip()

    return cfg

def extract_url_from_text(text: str) -> Optional[str]:
    """从输入的分享文案或链接中提取出有效 URL"""
    match = re.search(r'https?://[^\s]+', text.strip())
    if match:
        url = match.group(0)
        # 去掉结尾可能的多余标点
        url = url.rstrip('，。！？)）"\'>')
        return url
    return None

def extract_note_id(url: str) -> Optional[str]:
    """从 URL 中提取小红书笔记 ID"""
    m = re.search(r'/(?:explore|discovery/item)/([a-zA-Z0-9]+)', url)
    return m.group(1) if m else None

def extract_token_from_url(url: str) -> Optional[str]:
    """从 URL 中提取 xsec_token 参数"""
    m = re.search(r'xsec_token=([^&"\'\s]+)', url)
    return urllib.parse.unquote(m.group(1)) if m else None

def normalize_xhs_quality(value: str) -> str:
    clean = str(value or "1080p").strip().lower()
    if "720" in clean or clean in ("medium", "hd", "高清"):
        return "720p"
    if "480" in clean or clean in ("low", "sd", "标清"):
        return "480p"
    if "360" in clean or clean in ("ld", "流畅"):
        return "360p"
    return "1080p"

def xhs_quality_label(value: str) -> str:
    return {"1080p": "高清 1080P", "720p": "高清 720P", "480p": "清晰 480P", "360p": "流畅 360P"}[
        normalize_xhs_quality(value)
    ]

def build_authed_url(url: str, custom_token: Optional[str] = None) -> str:
    """若 URL 缺少 xsec_token，尝试自动将传入的 custom_token 补充进 URL"""
    if "xsec_token=" in url or not custom_token:
        return url

    sep = "&" if "?" in url else "?"
    encoded_token = urllib.parse.quote(custom_token)
    return f"{url}{sep}xsec_token={encoded_token}&xsec_source=pc_share"

def resolve_redirect(url: str) -> str:
    """追踪重定向（仅针对 xhslink.com 短链解析，长链保持原样避免被重定向至 /login）"""
    if "xhslink.com" not in url and "xhslink.cn" not in url:
        return url
    try:
        req = urllib.request.Request(
            url,
            headers={
                "User-Agent": MOBILE_UA,
                "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
            }
        )
        opener = urllib.request.build_opener(urllib.request.HTTPSHandler(context=SSL_CTX))
        with opener.open(req, timeout=10) as resp:
            return resp.geturl()
    except Exception:
        return url

def generate_uwx_id() -> str:
    """生成符合 KuKuTool 官方规范的设备 ID (uwx_ + 时间戳后6位 + 4位随机 + 2位大写字母)"""
    t_suffix = str(int(time.time() * 1000))[-6:]
    rand_part = ''.join(random.choices('0123456789abcdefghijklmnopqrstuvwxyz', k=4))
    letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    return f"uwx_{t_suffix}{rand_part}{random.choice(letters)}{random.choice(letters)}"

# MARK: - KuKuTool 解密模块
def decrypt_kukutool(encrypted_data: str, iv_str: str, key_str: str = "12345678901234567890123456789013") -> Dict[str, Any]:
    """KuKuTool 前端响应解密 (kukudemethod)"""
    from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

    def c_xor(s: str, t: int = 90) -> str:
        return ''.join(chr(ord(ch) ^ t) for ch in s)

    def o_rev(s: str, t: int = 8) -> str:
        res = []
        for i in range(0, len(s), t):
            res.append(s[i:i+t][::-1])
        return ''.join(res)

    def n_sub(s: str) -> str:
        src = "ZYXABCDEFGHIJKLMNOPQRSTUVWzyxabcdefghijklmnopqrstuvw9876543210-_"
        dst = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
        table = {src[i]: dst[i] for i in range(len(src))}
        return ''.join(table.get(ch, ch) for ch in s)

    d = n_sub(o_rev(c_xor(encrypted_data)))
    p = n_sub(o_rev(c_xor(iv_str)))

    d += '=' * ((4 - len(d) % 4) % 4)
    p += '=' * ((4 - len(p) % 4) % 4)

    ciphertext = base64.b64decode(d)
    iv = base64.b64decode(p)
    key = hashlib.sha256(key_str.encode('utf-8')).digest()

    cipher = Cipher(algorithms.AES(key), modes.CBC(iv))
    decryptor = cipher.decryptor()
    padded = decryptor.update(ciphertext) + decryptor.finalize()

    pad_len = padded[-1]
    plaintext = padded[:-pad_len].decode('utf-8')
    return json.loads(plaintext)

# MARK: - KuKuTool 协议解析（通道一）
def parse_via_kukutool(target_url: str) -> Optional[Tuple[str, str]]:
    """
    通过 KuKuTool 逆向协议解析视频直链与标题
    返回: (video_url, title) 或 None
    """
    try:
        from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    except ImportError:
        return None

    log_progress("正在通过 KuKuTool 协议通道尝试解析…")
    
    cj = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(
        urllib.request.HTTPCookieProcessor(cj),
        urllib.request.HTTPSHandler(context=SSL_CTX)
    )

    uwx_id = generate_uwx_id()
    page_path = "/xiaohongshu"
    headers_base = {
        "User-Agent": DEFAULT_UA,
        "Content-Type": "application/json",
        "Referer": "https://dy.kukutool.com/xiaohongshu",
        "Origin": "https://dy.kukutool.com",
        "Cookie": "NEXT_LOCALE=zh;"
    }

    auth_route = "auth-970b03"
    auth_fields = {"key": "k_970b03", "seed": "s_970b03"}
    parse_fields = {"key": "k_970b03", "payload": "p_970b03", "iv": "i_970b03", "version": "r_970b03"}

    quote_token = None
    try:
        req_ent = urllib.request.Request(
            "https://dy.kukutool.com/api/parse-entitlement-status",
            headers=headers_base,
            data=json.dumps({
                "uwx_id": uwx_id,
                "page_path": page_path,
                "request_url": target_url
            }).encode('utf-8')
        )
        with opener.open(req_ent, timeout=8) as resp:
            ent_json = json.loads(resp.read().decode('utf-8'))
            quote_token = ent_json.get("quoteToken")
    except Exception:
        quote_token = None

    time.sleep(1.0)

    try:
        req_auth = urllib.request.Request(
            f"https://dy.kukutool.com/api/{auth_route}",
            headers=headers_base,
            data=json.dumps({
                "requestURL": target_url,
                "pagePath": page_path,
                "mode": "single"
            }).encode('utf-8')
        )
        with opener.open(req_auth, timeout=8) as resp:
            auth_data = json.loads(resp.read().decode('utf-8'))
            
        k = auth_data.get(auth_fields["key"])
        s = auth_data.get(auth_fields["seed"])
        if not k or not s:
            return None

        key = hashlib.sha256(f"{k}:{s}".encode('utf-8')).digest()
        iv = os.urandom(12)
        aesgcm = AESGCM(key)

        payload = {
            "requestURL": target_url,
            "captchaKey": "",
            "captchaInput": "",
            "totalSuccessCount": "0",
            "successCount": "0",
            "firstSuccessDate": "",
            "pagePath": page_path,
            "uwx_id": uwx_id,
            "isMobile": "false",
            "geoipIp": "",
            "confirmPurchased": False,
            "qualityTier": "hd",
            "quoteToken": quote_token,
            "country_code": None
        }

        plaintext = json.dumps(payload, separators=(',', ':')).encode('utf-8')
        ciphertext = aesgcm.encrypt(iv, plaintext, None)
        payload_b64 = base64.b64encode(ciphertext).decode('utf-8')
        iv_b64 = base64.b64encode(iv).decode('utf-8')

        time.sleep(1.0)

        parse_body = {
            "version": 3,
            parse_fields["key"]: k,
            parse_fields["payload"]: payload_b64,
            parse_fields["iv"]: iv_b64,
            parse_fields["version"]: 1
        }

        req_parse = urllib.request.Request(
            "https://dy.kukutool.com/api/parse",
            headers=headers_base,
            data=json.dumps(parse_body).encode('utf-8')
        )
        with opener.open(req_parse, timeout=12) as resp:
            result = json.loads(resp.read().decode('utf-8'))

        data = result.get("data")
        if result.get("encrypt") and data and result.get("iv"):
            data = decrypt_kukutool(data, result.get("iv"))
        
        if not data and isinstance(result, dict):
            data = result

        if isinstance(data, dict):
            video_url = data.get("url")
            if not video_url and data.get("videos"):
                v_list = data.get("videos")
                if isinstance(v_list, list) and len(v_list) > 0:
                    first = v_list[0]
                    video_url = first.get("url") if isinstance(first, dict) else str(first)

            title = data.get("title") or "Xiaohongshu_Video"
            if video_url:
                log_progress(f"KuKuTool 协议解析成功: 《{title}》")
                return (video_url, title)

    except Exception:
        pass

    return None

# MARK: - 开源启发式直链提取通道（通道二：基于 wanyi-watermark / XHS-Downloader）
def parse_via_open_heuristic(target_url: str, cookie: str = "", quality: str = "medium") -> Optional[Tuple[str, str]]:
    """
    通过开源启发式规则直接提取小红书页面中的无水印视频直链
    支持从 xhslink.com 追踪重定向或带 token 的直链中提取，并自动注入配置的 Cookie
    支持指定清晰度档位：'medium' (默认 720P，节省 75%~85% 资源), 'high' (1080P/原画), 'low' (480P/360P)
    """
    log_progress(f"正在尝试通过开源启发式引擎提取小红书视频媒体源 (清晰度档位: {quality})…")
    resolved_url = resolve_redirect(target_url)

    # 规范化 URL：若为 discovery/item 转换为 explore 以获取完整 SSR state
    note_id = extract_note_id(resolved_url)
    token = extract_token_from_url(resolved_url)
    
    urls_to_try = [resolved_url]
    if note_id:
        if token:
            discovery_url = f"https://www.xiaohongshu.com/discovery/item/{note_id}?source=webshare&xhsshare=pc_web&xsec_token={urllib.parse.quote(token)}&xsec_source=pc_share"
            if discovery_url not in urls_to_try:
                urls_to_try.insert(0, discovery_url)
        explore_url = f"https://www.xiaohongshu.com/explore/{note_id}"
        if token:
            explore_url += f"?xsec_token={urllib.parse.quote(token)}&xsec_source=pc_share"
        if explore_url not in urls_to_try:
            urls_to_try.append(explore_url)

    def score_video_url(u: str, source: str, meta: Optional[Dict[str, Any]] = None) -> int:
        score = 0
        w = meta.get("width", 0) if meta else 0
        h = meta.get("height", 0) if meta else 0
        desc = str(meta.get("streamDesc", "")) if meta else ""
        min_dim = min(w, h) if w and h else 0

        # 根据指定清晰度档位评分 (默认推荐 medium / 720p，节省 75%~85% 资源)
        if quality in ("medium", "720p"):
            if min_dim == 720 or "720" in desc or "259" in desc or "309" in desc:
                score += 160
            elif source == "master_stream":
                score += 100
            elif source == "backup_stream":
                score += 85
            elif source == "video_tag":
                score += 70
            elif source == "og_video":
                score += 60
            elif source == "origin_video":
                score += 40  # 原片体积过大，作为兜底
            elif source == "regex_xhscdn":
                score += 30
        elif quality in ("low", "480p", "360p"):
            if min_dim in (360, 480):
                score += 160
            elif source == "master_stream":
                score += 90
            elif source == "origin_video":
                score += 30
        else: # high / 1080p
            if source == "origin_video":
                score += 160
            elif min_dim == 1080 or "1080" in desc:
                score += 140
            elif source == "master_stream":
                score += 100
            elif source == "video_tag":
                score += 90
            elif source == "og_video":
                score += 80
            elif source == "backup_stream":
                score += 60
            elif source == "regex_xhscdn":
                score += 50

        if u.startswith("https://"): score += 10
        if re.search(r'(?:wm|watermark)', u, re.IGNORECASE):
            score -= 50
        return score

    ua_list = [MOBILE_UA, DEFAULT_UA]

    for req_url in urls_to_try:
        for ua in ua_list:
            headers = {
                "User-Agent": ua,
                "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
                "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
                "Referer": "https://www.xiaohongshu.com/"
            }
            if cookie:
                headers["Cookie"] = cookie

            try:
                req = urllib.request.Request(req_url, headers=headers)
                opener = urllib.request.build_opener(urllib.request.HTTPSHandler(context=SSL_CTX))
                with opener.open(req, timeout=8) as resp:
                    final_url = resp.geturl()
                    html = resp.read().decode('utf-8', errors='ignore')

                # 若被拦截到 /login
                if "/login" in final_url and not cookie:
                    log_progress("提示: 小红书返回登录拦截页面，需要配置 Cookie 或提供有效 xsec_token")
                    continue

                candidates: List[Tuple[str, str, Optional[Dict[str, Any]]]] = []
                extracted_title = "Xiaohongshu_Video"

                # 1. 尝试从 __INITIAL_STATE__ 提取
                m_state = re.search(r'window\.__INITIAL_STATE__\s*=\s*(.+?)(?:</script>|;(?:\s*window|\s*<))', html, re.DOTALL)
                if not m_state:
                    m_state = re.search(r'<script>\s*window\.__INITIAL_STATE__\s*=\s*(.+?)</script>', html)
                if m_state:
                    state_data = None
                    try:
                        clean_json = re.sub(r':\s*undefined\s*([,}])', r': null\1', m_state.group(1).rstrip(';'))
                        state_data = json.loads(clean_json)
                    except (json.JSONDecodeError, TypeError):
                        # 页面脚本来自网络，只接受 JSON 语法；不要把网页内容交给 JS 引擎执行。
                        state_data = None

                    if state_data:
                        try:
                            # A. 检查 PC Web 端的 note.noteDetailMap
                            note_map = state_data.get("note", {}).get("noteDetailMap", {})
                            notes_to_check = [d.get("note", {}) for d in note_map.values() if isinstance(d, dict)]

                            # B. 检查移动端 H5 的 noteData.data.noteData
                            mobile_note = state_data.get("noteData", {}).get("data", {}).get("noteData")
                            if mobile_note and isinstance(mobile_note, dict):
                                notes_to_check.append(mobile_note)

                            for note in notes_to_check:
                                if note:
                                    extracted_title = note.get("title") or note.get("desc") or extracted_title
                                    video_obj = note.get("video", {})
                                    media = video_obj.get("media", {})
                                    stream = media.get("stream", {})
                                    for stream_type, items in stream.items():
                                        if isinstance(items, list):
                                            for item in items:
                                                if isinstance(item, dict):
                                                    if item.get("masterUrl"):
                                                        candidates.append((item["masterUrl"], "master_stream", item))
                                                    for b_url in item.get("backupUrls", []):
                                                        candidates.append((b_url, "backup_stream", item))
                                    # 检查 originVideoKey
                                    origin_key = video_obj.get("consumer", {}).get("originVideoKey")
                                    if origin_key:
                                        candidates.append((f"https://sns-video-bd.xhscdn.com/{origin_key}", "origin_video", None))
                        except Exception:
                            pass

                # 2. 提取 <video src="...">
                for v_src in re.findall(r'<video[^>]+src=["\']([^"\']+)["\']', html, re.IGNORECASE):
                    candidates.append((v_src, "video_tag", None))

                # 3. 提取 <meta property="og:video" content="...">
                for og_v in re.findall(r'<meta[^>]+(?:name|property)=["\']og:video["\'][^>]+content=["\']([^"\']+)["\']', html, re.IGNORECASE):
                    candidates.append((og_v, "og_video", None))

                # 4. 正则捕获 xhscdn.com 上的 mp4 视频流
                for raw_mp4 in re.findall(r'https?://[^\s"\'<>]+\.xhscdn\.com/[^\s"\'<>]+\.mp4[^\s"\'<>]*', html):
                    candidates.append((raw_mp4, "regex_xhscdn", None))

                if candidates:
                    cleaned = []
                    for c_url, c_src, c_meta in candidates:
                        norm = c_url.replace(r'\/', '/').replace('&amp;', '&').strip()
                        if norm.startswith('http://'):
                            norm = norm.replace('http://', 'https://', 1)
                        if norm.startswith('https://') and ('.mp4' in norm or 'sns-video' in norm):
                            cleaned.append((norm, c_src, c_meta))

                    if cleaned:
                        cleaned.sort(key=lambda x: (score_video_url(x[0], x[1], x[2]), len(x[0])), reverse=True)
                        best_url = cleaned[0][0]
                        log_progress(f"开源启发式引擎成功提取视频直链: 《{extracted_title}》 (清晰度: {quality})")
                        return (best_url, extracted_title)

            except Exception:
                continue

    return None

# MARK: - 社区公共 API 解析聚合通道（通道三）
def parse_via_community_apis(target_url: str) -> Optional[Tuple[str, str]]:
    """通过社区高可用短视频去水印/解析微服务聚合通道"""
    log_progress("正在尝试备用视频去水印解析通道…")
    
    note_id = extract_note_id(target_url)

    endpoints = [
        # 接口 1: pearktrue 视频接口
        {
            "url": f"https://api.pearktrue.cn/api/video/?url={urllib.parse.quote(target_url)}",
            "type": "json",
            "url_key": ["data", "url"],
            "title_key": ["data", "title"]
        },
        # 接口 2: tenapi 通用接口
        {
            "url": f"https://tenapi.cn/v2/ylys?url={urllib.parse.quote(target_url)}",
            "type": "json",
            "url_key": ["data", "url"],
            "title_key": ["data", "title"]
        },
        # 接口 3: 鱼七 API (支持完整 URL 或 note_id)
        {
            "url": f"https://api.yujn.cn/api/xhs.php?url={urllib.parse.quote(target_url)}",
            "type": "json",
            "url_key": ["data", "video"],
            "title_key": ["data", "title"]
        }
    ]

    if note_id:
        endpoints.append({
            "url": f"https://api.yujn.cn/api/xhs.php?url={urllib.parse.quote('https://www.xiaohongshu.com/discovery/item/' + note_id)}",
            "type": "json",
            "url_key": ["data", "video"],
            "title_key": ["data", "title"]
        })

    for ep in endpoints:
        try:
            req = urllib.request.Request(ep["url"], headers={"User-Agent": DEFAULT_UA})
            opener = urllib.request.build_opener(urllib.request.HTTPSHandler(context=SSL_CTX))
            with opener.open(req, timeout=6) as resp:
                data = json.loads(resp.read().decode('utf-8'))
                v_url = data
                for k in ep["url_key"]:
                    if isinstance(v_url, dict):
                        v_url = v_url.get(k)
                    else:
                        v_url = None
                        break
                
                t_val = data
                for k in ep["title_key"]:
                    if isinstance(t_val, dict):
                        t_val = t_val.get(k)
                    else:
                        t_val = None
                        break

                if v_url and isinstance(v_url, str) and v_url.startswith("http"):
                    title = t_val if isinstance(t_val, str) else "Xiaohongshu_Video"
                    log_progress(f"备用解析通道成功提取视频: 《{title}》")
                    return (v_url, title)
        except Exception:
            continue

    return None

# MARK: - 下载文件流并保存
def download_file(video_url: str, output_path: str, title: str = ""):
    """下载指定 URL 的视频文件到本地路径，附带实时百分比与进度回调"""
    log_progress(f"开始下载视频流: {os.path.basename(output_path)}…")
    
    headers = {
        "User-Agent": DEFAULT_UA,
        "Referer": "https://www.xiaohongshu.com/"
    }

    req = urllib.request.Request(video_url, headers=headers)
    opener = urllib.request.build_opener(urllib.request.HTTPSHandler(context=SSL_CTX))

    with opener.open(req, timeout=30) as resp, open(output_path, "wb") as out_f:
        total_size = int(resp.headers.get("content-length", 0))
        downloaded = 0
        chunk_size = 64 * 1024

        last_reported_percent = -1
        while True:
            chunk = resp.read(chunk_size)
            if not chunk:
                break
            out_f.write(chunk)
            downloaded += len(chunk)
            if total_size > 0:
                percent = int(downloaded * 100 / total_size)
                if percent != last_reported_percent and percent % 10 == 0:
                    last_reported_percent = percent
                    log_progress(f"下载中: {percent}% ({downloaded // 1024} KB / {total_size // 1024} KB)")

    log_progress("✅ 视频下载完成！")

# MARK: - 主流程
def download_xiaohongshu_video(input_text: str, output_path: str, cookie: str = "", custom_token: str = "", quality: str = "medium") -> bool:
    """主调度函数：支持自定义鉴权与四层容错架构，支持多清晰度档位 (medium/high/low)"""
    url = extract_url_from_text(input_text)
    if not url:
        log_progress("错误: 输入的内容中未找到有效链接")
        return False

    # 1. 尝试从输入文本或 URL 提取 token
    extracted_token = extract_token_from_url(url) or custom_token
    
    # 2. 智能补全 token（若 URL 未带 token 且提供了 token）
    final_input_url = build_authed_url(url, extracted_token)
    log_progress(f"解析到目标链接: {final_input_url} (指定清晰度: {quality})")
    target_url = resolve_redirect(final_input_url)

    result = None

    # 若指定了中间档位 (medium/720p) 或低档位，优先通过开源启发式精准提取指定分辨率码流
    if quality in ("medium", "720p", "low", "480p", "360p"):
        result = parse_via_open_heuristic(target_url, cookie=cookie, quality=quality)
        if not result:
            result = parse_via_kukutool(target_url)
    else:
        # 尝试通道一：KuKuTool
        result = parse_via_kukutool(target_url)
        # 尝试通道二：开源启发式直链提取（注入 Cookie 与 Token）
        if not result:
            result = parse_via_open_heuristic(target_url, cookie=cookie, quality=quality)

    # 尝试通道三：社区高可用去水印微服务聚合
    if not result:
        result = parse_via_community_apis(target_url)

    if result:
        video_url, title = result
        try:
            download_file(video_url, output_path, title)
            return True
        except Exception as e:
            log_progress(f"下载文件流失败: {e}")

    # 尝试通道四：yt-dlp
    log_progress("正在尝试通过 yt-dlp 进行最终提取…")
    import subprocess
    try:
        format_selector = "bestvideo[height<=720]+bestaudio/best[height<=720]/best" if quality in ("medium", "720p") else "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best"
        cmd = [
            "python3", "-m", "yt_dlp",
            "-o", output_path,
            "-f", format_selector,
            "--merge-output-format", "mp4",
            target_url
        ]
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=20)
        if proc.returncode == 0 and os.path.exists(output_path) and os.path.getsize(output_path) > 0:
            log_progress("✅ yt-dlp 下载成功！")
            return True
        else:
            log_progress(f"yt-dlp 执行失败: {proc.stderr[:200]}")
    except Exception as e:
        log_progress(f"yt-dlp 尝试异常: {e}")

    log_progress(
        "❌ 解析失败：小红书要求有效访问令牌或登录会话。\n"
        "💡 解决方案：\n"
        "  1. 在小红书网页端按 F12 运行导出脚本复制 Cookie，在 App【小红书鉴权配置】中粘贴；\n"
        "  2. 或在小红书手机/网页端点击【分享 ➔ 复制链接】，粘贴生成的完整短链接 (xhslink.com)。"
    )
    return False

def fetch_xiaohongshu_info(input_text: str, cookie: str = "", custom_token: str = "", quality: str = "1080p") -> Optional[Dict[str, Any]]:
    """提取小红书视频元数据（标题、作者、封面第一帧与直链）"""
    url = extract_url_from_text(input_text)
    if not url:
        return None

    extracted_token = extract_token_from_url(url) or custom_token
    final_input_url = build_authed_url(url, extracted_token)
    target_url = resolve_redirect(final_input_url)
    note_id = extract_note_id(target_url) or ""
    selected_quality = normalize_xhs_quality(quality)
    quality_label = xhs_quality_label(selected_quality)

    # 通道一：KuKuTool
    k_res = parse_via_kukutool(target_url)
    if k_res:
        v_url, title = k_res
        return {
            "status": "ok",
            "url": url,
            "note_id": note_id,
            "title": title,
            "author": "小红书创作者",
            "cover_url": None,
            "video_url": v_url,
            "quality": quality_label,
            "selected_quality": selected_quality,
            "available_qualities": ["1080p", "720p", "480p", "360p"]
        }

    # 通道二：开源启发式
    h_res = parse_via_open_heuristic(target_url, cookie=cookie, quality=selected_quality)
    if h_res:
        v_url, title = h_res
        return {
            "status": "ok",
            "url": url,
            "note_id": note_id,
            "title": title,
            "author": "小红书创作者",
            "cover_url": None,
            "video_url": v_url,
            "quality": quality_label,
            "selected_quality": selected_quality,
            "available_qualities": ["1080p", "720p", "480p", "360p"]
        }

    # 通道三：社区公共接口
    c_res = parse_via_community_apis(target_url)
    if c_res:
        v_url, title = c_res
        return {
            "status": "ok",
            "url": url,
            "note_id": note_id,
            "title": title,
            "author": "小红书创作者",
            "cover_url": None,
            "video_url": v_url,
            "quality": quality_label,
            "selected_quality": selected_quality,
            "available_qualities": ["1080p", "720p", "480p", "360p"]
        }

    # 通道四：yt-dlp dump json
    try:
        import subprocess
        format_selector = f"bestvideo[height<={int(selected_quality[:-1])}]+bestaudio/best[height<={int(selected_quality[:-1])}]/best"
        cmd = ["python3", "-m", "yt_dlp", "--dump-json", "--no-warnings", "-f", format_selector, target_url]
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        if proc.returncode == 0 and proc.stdout:
            info = json.loads(proc.stdout)
            return {
                "status": "ok",
                "url": url,
                "note_id": note_id,
                "title": info.get("title") or "小红书视频",
                "author": info.get("uploader") or info.get("creator") or "小红书创作者",
                "cover_url": info.get("thumbnail"),
                "video_url": info.get("url"),
                "quality": quality_label,
                "selected_quality": selected_quality,
                "available_qualities": ["1080p", "720p", "480p", "360p"]
            }
    except Exception:
        pass

    return None

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("用法:")
        print("  python3 xhs_downloader.py info <链接> [--cookie <str>] [--token <str>]")
        print("  python3 xhs_downloader.py <链接> <输出路径.mp4> [--direct-url <str>] [--title <str>] [--cookie <str>] [--token <str>]")
        sys.exit(1)

    # 1. 检查是否为 info 命令
    if sys.argv[1] == "info":
        if len(sys.argv) < 3:
            print("用法: python3 xhs_downloader.py info <链接>")
            sys.exit(1)
        url_arg = sys.argv[2]
        cookie_arg = ""
        token_arg = ""
        quality_arg = "1080p"
        idx = 3
        while idx < len(sys.argv):
            arg = sys.argv[idx]
            if arg == "--cookie" and idx + 1 < len(sys.argv):
                cookie_arg = sys.argv[idx + 1]
                idx += 2
            elif arg == "--token" and idx + 1 < len(sys.argv):
                token_arg = sys.argv[idx + 1]
                idx += 2
            elif arg in ("--quality", "-q") and idx + 1 < len(sys.argv):
                quality_arg = normalize_xhs_quality(sys.argv[idx + 1])
                idx += 2
            else:
                idx += 1

        if not cookie_arg or not token_arg:
            saved_cfg = load_auth_config()
            if not cookie_arg and saved_cfg.get("cookie"):
                cookie_arg = saved_cfg["cookie"]
            if not token_arg and saved_cfg.get("xsec_token"):
                token_arg = saved_cfg["xsec_token"]

        info = fetch_xiaohongshu_info(url_arg, cookie=cookie_arg, custom_token=token_arg, quality=quality_arg)
        print("\n=== JSON_RESULT_START ===")
        if info:
            print(json.dumps(info, ensure_ascii=False, indent=2))
        else:
            print(json.dumps({"status": "error", "message": "未能解析小红书视频信息，可能需要鉴权 Cookie"}, ensure_ascii=False, indent=2))
        print("=== JSON_RESULT_END ===")
        sys.exit(0 if info else 1)

    # 2. 下载命令
    if len(sys.argv) < 3:
        print("用法: python3 xhs_downloader.py <链接或分享文本> <输出路径.mp4> [--direct-url <url>] [--title <title>]")
        sys.exit(1)

    url_arg = sys.argv[1]
    out_arg = sys.argv[2]

    # 解析可选参数
    cookie_arg = ""
    token_arg = ""
    direct_url_arg = ""
    title_arg = ""
    quality_arg = "medium"

    idx = 3
    while idx < len(sys.argv):
        arg = sys.argv[idx]
        if arg == "--cookie" and idx + 1 < len(sys.argv):
            cookie_arg = sys.argv[idx + 1]
            idx += 2
        elif arg == "--token" and idx + 1 < len(sys.argv):
            token_arg = sys.argv[idx + 1]
            idx += 2
        elif arg == "--direct-url" and idx + 1 < len(sys.argv):
            direct_url_arg = sys.argv[idx + 1]
            idx += 2
        elif arg == "--title" and idx + 1 < len(sys.argv):
            title_arg = sys.argv[idx + 1]
            idx += 2
        elif arg in ("--quality", "-q") and idx + 1 < len(sys.argv):
            quality_arg = sys.argv[idx + 1]
            idx += 2
        else:
            idx += 1

    # 若传入了预解析直链，直接跳过解析快速下载
    if direct_url_arg:
        log_progress("⚡️ 使用已预解析的小红书视频直链，跳过重复解析通道，直接下载！")
        try:
            download_file(direct_url_arg, out_arg, title=title_arg)
            sys.exit(0)
        except Exception as e:
            log_progress(f"预解析直链下载异常: {e}，正在尝试自动回退解析…")

    # 若未在命令行传入，尝试从已保存的配置文件中读取
    if not cookie_arg or not token_arg:
        saved_cfg = load_auth_config()
        if not cookie_arg and saved_cfg.get("cookie"):
            cookie_arg = saved_cfg["cookie"]
        if not token_arg and saved_cfg.get("xsec_token"):
            token_arg = saved_cfg["xsec_token"]

    success = download_xiaohongshu_video(url_arg, out_arg, cookie=cookie_arg, custom_token=token_arg, quality=quality_arg)
    sys.exit(0 if success else 1)
