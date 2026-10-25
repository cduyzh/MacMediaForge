#!/usr/bin/env python3
"""
MediaSaver 本地批量视频接收与下载服务器
监听 127.0.0.1:8765，接收来自浏览器控制台脚本推送的小红书等平台视频直链，
多线程下载至系统下载目录 (~/Downloads/cduyzhMediaForge)。

安全与数据机制 (对齐主下载引擎):
- Origin/Referer 白名单: 只接受小红书页面与 localhost 的推送, 阻止任意网页滥用本机下载器
- 可选令牌: 设置环境变量 MEDIAFORGE_BATCH_TOKEN 后, 请求必须携带 X-MediaForge-Token 头
- 下载走 mediaforge_network 健壮内核 (重试/续传/校验/原子落盘), 携带平台 Referer 避免 CDN 403
- 按 note_id 去重: 已下载过的笔记直接跳过, 成功后记入 mediaforge_store 持久层
"""

import os
import sys
import json
import threading
import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse

from mediaforge_network import download_file as robust_download, FetchError
import mediaforge_store as store

BASE_DOWNLOAD_DIR = os.path.expanduser("~/Downloads/cduyzhMediaForge")

# 允许发起推送的页面来源 (浏览器无法伪造跨域 Origin, 该校验可阻止任意恶意网页驱动本机下载)
ALLOWED_ORIGIN_HOSTS = {
    "www.xiaohongshu.com", "xiaohongshu.com", "creator.xiaohongshu.com",
    "localhost", "127.0.0.1",
}

BATCH_TOKEN = os.environ.get("MEDIAFORGE_BATCH_TOKEN", "").strip()

def get_categorized_download_dir(platform="小红书", category="视频"):
    now = datetime.datetime.now()
    # 格式对齐中文 "26年10月14日"
    date_folder = f"{now.strftime('%y')}年{now.month}月{now.day}日"
    target_dir = os.path.join(BASE_DOWNLOAD_DIR, platform, date_folder, category)
    os.makedirs(target_dir, exist_ok=True)
    return target_dir

class BatchDownloadHandler(BaseHTTPRequestHandler):
    def _origin_allowed(self) -> bool:
        origin = (self.headers.get("Origin") or "").strip()
        referer = (self.headers.get("Referer") or "").strip()
        for candidate in (origin, referer):
            if not candidate:
                continue
            try:
                host = urlparse(candidate if "//" in candidate else f"https://{candidate}").hostname or ""
                if host.lower() in ALLOWED_ORIGIN_HOSTS:
                    return True
            except ValueError:
                continue
        # 无 Origin/Referer (如 curl) 时要求令牌; 有来源但不命中白名单则拒绝
        return not origin and not referer

    def _authorized(self) -> bool:
        if BATCH_TOKEN and self.headers.get("X-MediaForge-Token", "").strip() != BATCH_TOKEN:
            return False
        return self._origin_allowed()

    def _cors_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "POST, GET, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, X-MediaForge-Token")

    def do_OPTIONS(self):
        self.send_response(200)
        self._cors_headers()
        self.end_headers()

    def do_POST(self):
        if self.path == "/api/push_video" or self.path == "/api/download_batch":
            if not self._authorized():
                self.send_response(403)
                self._cors_headers()
                self.end_headers()
                self.wfile.write(b'{"error": "forbidden origin"}')
                return
            content_length = int(self.headers.get("Content-Length", 0))
            post_data = self.rfile.read(content_length)
            try:
                data = json.loads(post_data.decode("utf-8"))
                tasks = data if isinstance(data, list) else [data]

                print(f"\n[MediaSaver] 📥 接收到 {len(tasks)} 个视频下载任务！", flush=True)
                for item in tasks:
                    title = item.get("title", "xhs_video")
                    url = item.get("url")
                    note_id = item.get("note_id", "")
                    if url:
                        # 异步多线程下载
                        threading.Thread(target=self.download_worker, args=(url, title, note_id), daemon=True).start()

                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self._cors_headers()
                self.end_headers()
                self.wfile.write(json.dumps({"status": "ok", "received": len(tasks)}).encode("utf-8"))
            except Exception as e:
                self.send_response(500)
                self._cors_headers()
                self.end_headers()
                self.wfile.write(str(e).encode("utf-8"))
        else:
            self.send_response(404)
            self.end_headers()

    def download_worker(self, url: str, title: str, note_id: str):
        content_key = note_id or store.content_key(url)

        # 去重门: 已下载过的笔记直接跳过
        if store.find_download("xhs", content_key, ""):
            print(f"[下载引擎] ♻️ 已下载过, 跳过: 《{title}》", flush=True)
            return

        target_dir = get_categorized_download_dir(platform="小红书", category="视频")
        safe_title = "".join(c for c in title if c not in r'\/:*?"<>|').strip()[:60]
        if not safe_title:
            safe_title = note_id or "video"
        filename = f"{safe_title}.mp4"
        filepath = os.path.join(target_dir, filename)

        # 避免重名覆盖
        counter = 1
        base_name = safe_title
        while os.path.exists(filepath):
            filename = f"{base_name}_{counter}.mp4"
            filepath = os.path.join(target_dir, filename)
            counter += 1

        print(f"[下载引擎] 🚀 开始下载: 《{safe_title}》 -> {filepath}", flush=True)
        try:
            robust_download(
                url, filepath,
                headers={
                    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
                    "Referer": "https://www.xiaohongshu.com/",
                },
                timeout=30,
            )
            size_mb = os.path.getsize(filepath) / 1024 / 1024
            store.record_download("xhs", content_key, filepath, source_url=url, title=title)
            print(f"[下载引擎] ✅ 下载完成: 《{safe_title}》 (大小: {size_mb:.2f} MB)", flush=True)
        except FetchError as e:
            store.record_failure("xhs", content_key, url, "", str(e))
            print(f"[下载引擎] ❌ 下载失败 《{safe_title}》: {e}", flush=True)
        except Exception as e:
            print(f"[下载引擎] ❌ 下载失败 《{safe_title}》: {e}", flush=True)

    def log_message(self, format, *args):
        # 屏蔽多余访问日志保持终端清爽
        pass

def run_server(port=8765):
    server = HTTPServer(("127.0.0.1", port), BatchDownloadHandler)
    token_hint = " (已启用令牌校验)" if BATCH_TOKEN else ""
    print(f"[MediaSaver] 本地批量下载接收服务器已就绪: http://127.0.0.1:{port}{token_hint}", flush=True)
    server.serve_forever()

if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    run_server(port)
