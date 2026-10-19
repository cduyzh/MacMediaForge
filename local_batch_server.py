#!/usr/bin/env python3
"""
cduyzh MediaForge 本地批量视频接收与下载服务器
监听 127.0.0.1:8765，接收来自浏览器扩展或控制台脚本推送的小红书等平台视频直链，
自动多线程下载至系统下载目录 (~/Downloads/cduyzhMediaForge)，并可配合 cduyzh MediaForge 自动生成实况照片。
"""

import os
import sys
import json
import urllib.request
import threading
from http.server import HTTPServer, BaseHTTPRequestHandler

import datetime

BASE_DOWNLOAD_DIR = os.path.expanduser("~/Downloads/cduyzhMediaForge")

def get_categorized_download_dir(platform="小红书", category="视频"):
    now = datetime.datetime.now()
    # 格式对齐中文 "26年10月14日"
    date_folder = f"{now.strftime('%y')}年{now.month}月{now.day}日"
    target_dir = os.path.join(BASE_DOWNLOAD_DIR, platform, date_folder, category)
    os.makedirs(target_dir, exist_ok=True)
    return target_dir

class BatchDownloadHandler(BaseHTTPRequestHandler):
    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "POST, GET, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_POST(self):
        if self.path == "/api/push_video" or self.path == "/api/download_batch":
            content_length = int(self.headers.get("Content-Length", 0))
            post_data = self.rfile.read(content_length)
            try:
                data = json.loads(post_data.decode("utf-8"))
                tasks = data if isinstance(data, list) else [data]
                
                print(f"\n[cduyzh MediaForge] 📥 接收到 {len(tasks)} 个视频下载任务！", flush=True)
                for item in tasks:
                    title = item.get("title", "xhs_video")
                    url = item.get("url")
                    note_id = item.get("note_id", "")
                    if url:
                        # 异步多线程下载
                        threading.Thread(target=self.download_worker, args=(url, title, note_id)).start()

                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Access-Control-Allow-Origin", "*")
                self.end_headers()
                self.wfile.write(json.dumps({"status": "ok", "received": len(tasks)}).encode("utf-8"))
            except Exception as e:
                self.send_response(500)
                self.send_header("Access-Control-Allow-Origin", "*")
                self.end_headers()
                self.wfile.write(str(e).encode("utf-8"))
        else:
            self.send_response(404)
            self.end_headers()

    def download_worker(self, url: str, title: str, note_id: str):
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
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
            with urllib.request.urlopen(req, timeout=30) as resp, open(filepath, "wb") as f:
                total = int(resp.headers.get("Content-Length", 0))
                downloaded = 0
                while True:
                    chunk = resp.read(1024 * 512)
                    if not chunk:
                        break
                    f.write(chunk)
                    downloaded += len(chunk)
            print(f"[下载引擎] ✅ 下载完成: 《{safe_title}》 (大小: {downloaded / 1024 / 1024:.2f} MB)", flush=True)
        except Exception as e:
            print(f"[下载引擎] ❌ 下载失败 《{safe_title}》: {e}", flush=True)

    def log_message(self, format, *args):
        # 屏蔽多余访问日志保持终端清爽
        pass

def run_server(port=8765):
    server = HTTPServer(("127.0.0.1", port), BatchDownloadHandler)
    print(f"[cduyzh MediaForge] 本地批量下载接收服务器已就绪: http://127.0.0.1:{port}", flush=True)
    server.serve_forever()

if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    run_server(port)
