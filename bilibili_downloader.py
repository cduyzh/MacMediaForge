#!/usr/bin/env python3
"""
Bilibili (哔哩哔哩) 高画质视频解析与下载引擎 (bilibili_downloader.py)
专为 cduyzh MediaForge 打造：
1. 支持完整 B站视频链接 (bilibili.com/video/BV...)、短链 (b23.tv) 及纯 BV/av 号提取与自动重定向解析
2. 智能读取本地已登录浏览器 (Chrome / Safari / Edge 等) Cookie 或配置文件中的 SESSDATA 鉴权，畅享最高 1080P60 / 1080P 画质
3. 采用 DASH 分离音视频流极速拉取并利用系统 FFmpeg 原生秒级无损合并 (-c copy)
4. 支持未登录或 Cookie 失效时无缝降级到 720P / 480P 公开流
5. 实时向 stdout 输出结构化进度百分比与下载速率，完美对接 macOS Swift 客户端界面
"""

import sys
import os
import re
import json
import time
import ssl
import subprocess
import urllib.request
import urllib.parse
import urllib.error
from typing import Optional, Dict, Any, List, Tuple

# 忽略 SSL 证书验证以兼容各种系统与 Python 环境
from mediaforge_network import make_ssl_context

SSL_CTX = make_ssl_context()

DEFAULT_HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept-Language': 'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,application/json,*/*;q=0.8',
    'Referer': 'https://www.bilibili.com/',
}

QUALITY_MAP = {
    127: "8K 超高清",
    126: "杜比视界",
    125: "HDR 真彩",
    120: "4K 超清",
    116: "1080P 60帧",
    112: "1080P 高码率",
    80: "1080P 高清",
    74: "720P 60帧",
    64: "720P 高清",
    32: "480P 清晰",
    16: "360P 流畅"
}

def log_progress(msg: str):
    """向标准输出打印进度信息供 Swift 捕获并更新 UI"""
    print(msg, flush=True)

def sanitize_filename(name: str) -> str:
    """清理文件名中的非法字符"""
    clean = re.sub(r'[\\/*?:"<>|\n\r\t]', '_', name).strip()
    return clean[:120] if len(clean) > 120 else clean

def locate_ffmpeg() -> str:
    """自动探测系统中可用的 ffmpeg 执行程序"""
    candidates = [
        "/Users/hobby/.local/bin/ffmpeg",
        os.path.join(os.path.dirname(os.path.abspath(__file__)), "ffmpeg"),
        os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "ffmpeg"),
        "/opt/homebrew/bin/ffmpeg",
        "/usr/local/bin/ffmpeg",
        "/usr/bin/ffmpeg"
    ]
    for p in candidates:
        if os.path.isfile(p) and os.access(p, os.X_OK):
            return p
            
    try:
        import imageio_ffmpeg
        p = imageio_ffmpeg.get_ffmpeg_exe()
        if p and os.path.isfile(p) and os.access(p, os.X_OK):
            return p
    except Exception:
        pass
        
    return "ffmpeg"

def extract_bvid_and_raw_url(text: str) -> Tuple[Optional[str], Optional[str]]:
    """从可能混有文案的文本中提取 BV号 及完整 URL"""
    # 查找 URL
    url_match = re.search(r'https?://[^\s，。！？)）"\'<>]+', text)
    found_url = url_match.group(0) if url_match else None
    
    # 查找 BV 号
    bv_match = re.search(r'BV[a-zA-Z0-9]{10}', text)
    found_bv = bv_match.group(0) if bv_match else None
    
    # 若是 b23.tv 短链，先重定向解析
    if found_url and "b23.tv" in found_url:
        try:
            req = urllib.request.Request(found_url, headers=DEFAULT_HEADERS)
            with urllib.request.urlopen(req, context=SSL_CTX, timeout=10) as resp:
                real_url = resp.geturl()
                found_url = real_url
                bv_in_real = re.search(r'BV[a-zA-Z0-9]{10}', real_url)
                if bv_in_real:
                    found_bv = bv_in_real.group(0)
        except Exception as e:
            log_progress(f"解析 b23.tv 短链重定向提示: {e}")
            
    return found_bv, found_url

def get_bilibili_cookie() -> str:
    """多级探测读取 B 站 Cookie（配置目录 -> 本地 Chrome / Safari 浏览器）"""
    # 1. 尝试从本地配置文件读取
    home = os.path.expanduser("~")
    cfg_paths = [
        os.path.join(home, "Library", "Application Support", "cduyzhMediaForge", "bilibili_auth.json"),
        os.path.join(home, ".cduyzh_mediaforge_bilibili_auth.json"),
        os.path.join(home, ".config", "cduyzh_mediaforge", "bilibili_auth.json")
    ]
    for cp in cfg_paths:
        if os.path.exists(cp):
            try:
                with open(cp, 'r', encoding='utf-8') as f:
                    cfg = json.load(f)
                    c = cfg.get("cookie") or cfg.get("SESSDATA")
                    if c:
                        if "SESSDATA=" not in c:
                            return f"SESSDATA={c}"
                        return c
            except Exception:
                pass

    # 2. 尝试从系统安装的浏览器中直接读取 B 站 Cookie
    try:
        import rookiepy
        # 优先读取 Chrome，若无尝试 Safari / Edge
        for browser_fn in [rookiepy.chrome, rookiepy.safari, rookiepy.edge, rookiepy.brave]:
            try:
                cookies = browser_fn(["bilibili.com"])
                if cookies:
                    parts = [f"{c['name']}={c['value']}" for c in cookies]
                    sess_found = any(c['name'] == 'SESSDATA' for c in cookies)
                    if sess_found:
                        return "; ".join(parts)
            except Exception:
                continue
    except Exception:
        pass

    return ""

def fetch_bilibili_info(url_or_text: str, custom_cookie: Optional[str] = None) -> Dict[str, Any]:
    """解析 Bilibili 视频基础元数据与最高画质流信息"""
    bvid, full_url = extract_bvid_and_raw_url(url_or_text)
    if not bvid:
        raise ValueError(f"未能在文本或链接中识别出有效的 B站 BV号: {url_or_text}")

    cookie = custom_cookie or get_bilibili_cookie()

    # 1. 请求视频详情 API
    view_api = f"https://api.bilibili.com/x/web-interface/view?bvid={bvid}"
    req_headers = dict(DEFAULT_HEADERS)
    req_headers['Referer'] = f"https://www.bilibili.com/video/{bvid}"
    if cookie:
        req_headers['Cookie'] = cookie

    req = urllib.request.Request(view_api, headers=req_headers)
    with urllib.request.urlopen(req, context=SSL_CTX, timeout=15) as resp:
        resp_data = json.loads(resp.read().decode('utf-8'))

    if resp_data.get('code') != 0:
        msg = resp_data.get('message', '未知错误')
        raise RuntimeError(f"B站接口返回异常 ({resp_data.get('code')}): {msg}")

    # 解析 URL 中的分P参数 (如 ?p=2)
    p_match = re.search(r'[?&]p=(\d+)', url_or_text)
    selected_p = int(p_match.group(1)) if p_match else None

    data = resp_data.get('data', {})
    title = data.get('title', 'B站视频')
    author = data.get('owner', {}).get('name', 'B站创作者')
    cover_url = data.get('pic', '')
    duration = data.get('duration', 0)
    cid = data.get('cid')
    pages = data.get('pages', [])

    if selected_p and pages:
        matching_pages = [p for p in pages if p.get('page') == selected_p]
        if matching_pages:
            target_p = matching_pages[0]
            cid = target_p.get('cid')
            duration = target_p.get('duration') or duration
            p_part = target_p.get('part', '')
            if p_part and p_part not in title:
                title = f"{title} P{selected_p} {p_part}"

    if not cid and pages:
        cid = pages[0].get('cid')

    if not cid:
        raise RuntimeError("未能获取到视频分P的有效 cid")

    # 提取合集 (ugc_season) 或分P (pages) 列表信息
    collection_info = None
    ugc_season = data.get('ugc_season')
    if ugc_season:
        season_sections = []
        raw_sections = ugc_season.get('sections', [])
        total_eps = 0
        for s_idx, sec in enumerate(raw_sections):
            sec_title = sec.get('title', f"分卷 {s_idx + 1}")
            sec_episodes = []
            for ep in sec.get('episodes', []):
                ep_bvid = ep.get('bvid', '')
                ep_cid = ep.get('cid', 0)
                ep_title = ep.get('title', '')
                ep_arc = ep.get('arc', {})
                ep_page = ep.get('page', {})
                ep_cover = ep_arc.get('pic') or ep.get('cover') or cover_url
                ep_dur = ep_arc.get('duration') or ep_page.get('duration') or 0
                ep_author = ep_arc.get('author', {}).get('name') or author

                # 格式化时长为 00:00 或 00:00:00
                m, s = divmod(ep_dur, 60)
                h, m = divmod(m, 60)
                dur_str = f"{h:02d}:{m:02d}:{s:02d}" if h > 0 else f"{m:02d}:{s:02d}"

                sec_episodes.append({
                    "bvid": ep_bvid,
                    "cid": ep_cid,
                    "page": ep_page.get('page', 1),
                    "title": ep_title,
                    "cover_url": ep_cover,
                    "duration": ep_dur,
                    "duration_str": dur_str,
                    "author": ep_author,
                    "section_title": sec_title,
                    "url": f"https://www.bilibili.com/video/{ep_bvid}",
                    "is_current": (ep_bvid == bvid)
                })
                total_eps += 1

            season_sections.append({
                "id": sec.get('id', s_idx),
                "title": sec_title,
                "episodes": sec_episodes
            })

        collection_info = {
            "type": "ugc_season",
            "type_label": "合集",
            "title": ugc_season.get('title', title),
            "cover_url": ugc_season.get('cover') or cover_url,
            "intro": ugc_season.get('intro', ''),
            "ep_count": total_eps or ugc_season.get('ep_count', total_eps),
            "current_bvid": bvid,
            "sections": season_sections
        }

    elif pages and len(pages) > 1:
        # 视频内多P分集
        p_episodes = []
        for p in pages:
            p_num = p.get('page', 1)
            p_cid = p.get('cid', 0)
            p_part = p.get('part') or f"第{p_num}P"
            p_dur = p.get('duration', 0)
            m, s = divmod(p_dur, 60)
            h, m = divmod(m, 60)
            dur_str = f"{h:02d}:{m:02d}:{s:02d}" if h > 0 else f"{m:02d}:{s:02d}"

            p_episodes.append({
                "bvid": bvid,
                "cid": p_cid,
                "page": p_num,
                "title": f"P{p_num} {p_part}",
                "cover_url": cover_url,
                "duration": p_dur,
                "duration_str": dur_str,
                "author": author,
                "section_title": "视频分P",
                "url": f"https://www.bilibili.com/video/{bvid}?p={p_num}",
                "is_current": (p_cid == cid)
            })

        collection_info = {
            "type": "pages",
            "type_label": "分P视频",
            "title": title,
            "cover_url": cover_url,
            "intro": "",
            "ep_count": len(pages),
            "current_bvid": bvid,
            "sections": [{
                "id": 0,
                "title": "视频分P",
                "episodes": p_episodes
            }]
        }

    # 2. 请求播放流 API (优先 DASH 模式以获取 1080P60 / 1080P 高码率)
    playurl_api = f"https://api.bilibili.com/x/player/playurl?bvid={bvid}&cid={cid}&qn=116&fnval=4048&fnver=0&fourk=1"
    req_play = urllib.request.Request(playurl_api, headers=req_headers)
    with urllib.request.urlopen(req_play, context=SSL_CTX, timeout=15) as resp:
        play_data = json.loads(resp.read().decode('utf-8'))

    is_dash = False
    video_url = ""
    audio_url = ""
    quality_name = "高清"
    quality_id = 64
    direct_url = ""

    if play_data.get('code') == 0:
        p_data = play_data.get('data', {})
        dash = p_data.get('dash')
        if dash and dash.get('video'):
            is_dash = True
            dash_videos = dash.get('video', [])
            # 优先选择 avc1 / H.264 编码，确保在 macOS 原生、QuickTime、AVFoundation 及照片图库中完美播放
            avc_videos = [v for v in dash_videos if v.get('codecs', '').startswith('avc1')]
            candidate_videos = avc_videos if avc_videos else dash_videos
            # 挑选最高清晰度且最高码率的轨
            best_video = max(candidate_videos, key=lambda x: (x.get('id', 0), x.get('bandwidth', 0)))
            quality_id = best_video.get('id', 64)
            quality_name = QUALITY_MAP.get(quality_id, f"品质_{quality_id}")
            video_url = best_video.get('baseUrl') or best_video.get('base_url')

            # 挑选最高码率的音频轨
            dash_audios = dash.get('audio', [])
            if dash_audios:
                best_audio = max(dash_audios, key=lambda x: x.get('bandwidth', 0))
                audio_url = best_audio.get('baseUrl') or best_audio.get('base_url')

        elif p_data.get('durl'):
            # 降级模式：单段 MP4 (fnval=0)
            durls = p_data.get('durl', [])
            if durls:
                direct_url = durls[0].get('url', '')
                video_url = direct_url
                quality_id = p_data.get('quality', 64)
                quality_name = QUALITY_MAP.get(quality_id, "高清 720P")

    # 若 DASH 请求失败或未拿到直链，再尝试请求单段 MP4 (fnval=0) 作为备用
    if not video_url:
        durl_api = f"https://api.bilibili.com/x/player/playurl?bvid={bvid}&cid={cid}&qn=64&fnval=0&fnver=0&fourk=1"
        req_durl = urllib.request.Request(durl_api, headers=req_headers)
        with urllib.request.urlopen(req_durl, context=SSL_CTX, timeout=15) as resp:
            d_data = json.loads(resp.read().decode('utf-8'))
            if d_data.get('code') == 0 and d_data.get('data', {}).get('durl'):
                direct_url = d_data['data']['durl'][0].get('url', '')
                video_url = direct_url
                quality_name = "高清 720P"
                is_dash = False

    return {
        "status": "ok",
        "bvid": bvid,
        "cid": cid,
        "title": title,
        "author": author,
        "cover_url": cover_url,
        "duration": duration,
        "quality": quality_name,
        "quality_id": quality_id,
        "is_dash": is_dash,
        "video_url": video_url,
        "audio_url": audio_url,
        "direct_url": direct_url,
        "original_url": full_url or f"https://www.bilibili.com/video/{bvid}",
        "cookie_applied": bool(cookie),
        "collection": collection_info
    }

def download_stream(stream_url: str, output_path: str, label: str, bvid: str):
    """带实时传输进度及速率统计的流文件下载"""
    headers = {
        'User-Agent': DEFAULT_HEADERS['User-Agent'],
        'Referer': f'https://www.bilibili.com/video/{bvid}',
        'Origin': 'https://www.bilibili.com'
    }
    req = urllib.request.Request(stream_url, headers=headers)
    with urllib.request.urlopen(req, context=SSL_CTX, timeout=30) as resp:
        total_size = int(resp.headers.get('content-length', 0))
        downloaded = 0
        chunk_size = 131072 # 128 KB
        start_time = time.time()
        last_log_time = 0.0

        with open(output_path, 'wb') as f:
            while True:
                chunk = resp.read(chunk_size)
                if not chunk:
                    break
                f.write(chunk)
                downloaded += len(chunk)

                now = time.time()
                # 每 0.6 秒输出一次平滑进度
                if now - last_log_time >= 0.6:
                    last_log_time = now
                    elapsed = max(0.001, now - start_time)
                    speed_mb = (downloaded / (1024 * 1024)) / elapsed
                    dl_mb = downloaded / (1024 * 1024)
                    if total_size > 0:
                        tot_mb = total_size / (1024 * 1024)
                        pct = (downloaded / total_size) * 100
                        log_progress(f"{label}: {dl_mb:.1f}MB/{tot_mb:.1f}MB ({pct:.1f}%) {speed_mb:.1f}MB/s")
                    else:
                        log_progress(f"{label}: 已下载 {dl_mb:.1f}MB ({speed_mb:.1f}MB/s)")

        # 下载完成输出最终提示
        dl_mb = downloaded / (1024 * 1024)
        log_progress(f"✅ {label} 下载完成 (共 {dl_mb:.1f}MB)")

def download_bilibili_video(url: str, output_path: str, preparsed_data: Optional[Dict[str, Any]] = None, custom_title: Optional[str] = None, delogo: bool = False) -> Dict[str, Any]:
    """完整执行 B站 视频拉取、流下载与 FFmpeg 无损合并封包（支持水印消除兜底）"""
    info = preparsed_data
    if not info:
        log_progress("🔍 正在连接 B站 解析元数据与音视频流直链…")
        info = fetch_bilibili_info(url)
    else:
        log_progress("⚡️ 命中视频预解析缓存，直接开启极速多轨流拉取！")

    bvid = info.get('bvid', '')
    title = custom_title or info.get('title', 'B站视频')
    author = info.get('author', 'B站创作者')
    quality = info.get('quality', '高清')
    is_dash = info.get('is_dash', False)
    video_url = info.get('video_url', '')
    audio_url = info.get('audio_url', '')

    if not video_url:
        raise RuntimeError("未识别到有效的视频下载流，请检查视频是否为受限或大会员专享内容")

    out_dir = os.path.dirname(output_path)
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)

    log_progress(f"🎬 目标视频: 《{title}》 | UP主: {author} | 画质: {quality}")

    if is_dash and audio_url:
        # DASH 分离音视频模式
        tmp_video = f"{output_path}.tmp_v.m4s"
        tmp_audio = f"{output_path}.tmp_a.m4s"

        try:
            log_progress(f"⬇️ 开始下载高清视频轨 ({quality})…")
            download_stream(video_url, tmp_video, label="[1/2 视频轨]", bvid=bvid)

            log_progress("⬇️ 开始下载原声高品质音频轨…")
            download_stream(audio_url, tmp_audio, label="[2/2 音频轨]", bvid=bvid)

            log_progress("🔄 正在通过 FFmpeg 封装合成标准 MP4…")
            ffmpeg_bin = locate_ffmpeg()
            merge_cmd = [
                ffmpeg_bin,
                "-nostdin",
                "-y",
                "-i", tmp_video,
                "-i", tmp_audio,
                "-c", "copy",
                "-movflags", "+faststart",
                output_path
            ]

            merged_ok = False
            if delogo:
                log_progress("✨ 启用 B站 水印消除与硬件加速编码…")
                # Tier 1: VideoToolbox
                tier1_cmd = [
                    ffmpeg_bin, "-nostdin", "-y",
                    "-i", tmp_video, "-i", tmp_audio,
                    "-vf", "delogo=x=1528:y=26:w=360:h=78:show=0",
                    "-c:v", "h264_videotoolbox", "-b:v", "9500k",
                    "-c:a", "copy",
                    "-movflags", "+faststart",
                    output_path
                ]
                res = subprocess.run(tier1_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, stdin=subprocess.DEVNULL)
                if res.returncode == 0 and os.path.exists(output_path) and os.path.getsize(output_path) > 50000:
                    merged_ok = True
                    log_progress("✅ 水印已通过硬件加速成功消除！")
                else:
                    # Tier 2: libx264 兼容兜底
                    log_progress("⚠️ 硬件加速受限，切换至 CPU libx264 兼容编码兜底…")
                    tier2_cmd = [
                        ffmpeg_bin, "-nostdin", "-y",
                        "-i", tmp_video, "-i", tmp_audio,
                        "-vf", "delogo=x=1528:y=26:w=360:h=78:show=0",
                        "-c:v", "libx264", "-preset", "fast", "-crf", "20",
                        "-c:a", "copy",
                        "-movflags", "+faststart",
                        output_path
                    ]
                    res = subprocess.run(tier2_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, stdin=subprocess.DEVNULL)
                    if res.returncode == 0 and os.path.exists(output_path) and os.path.getsize(output_path) > 50000:
                        merged_ok = True
                        log_progress("✅ 水印已通过兼容编码成功消除！")

            if not merged_ok:
                res = subprocess.run(merge_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, stdin=subprocess.DEVNULL)
                if res.returncode != 0:
                    err_msg = res.stderr.decode('utf-8', errors='ignore')
                    raise RuntimeError(f"FFmpeg 合成失败: {err_msg[:200]}")

            log_progress(f"🎉 视频合成封装完成: {os.path.basename(output_path)}")

        finally:
            if os.path.exists(tmp_video):
                try: os.remove(tmp_video)
                except Exception: pass
            if os.path.exists(tmp_audio):
                try: os.remove(tmp_audio)
                except Exception: pass

    else:
        # 单流 Progressive MP4 模式
        log_progress("⬇️ 开始下载完整 MP4 视频流…")
        download_stream(video_url, output_path, label="[完整视频]", bvid=bvid)
        log_progress(f"🎉 视频下载完成: {os.path.basename(output_path)}")

    return {
        "status": "ok",
        "output_path": output_path,
        "title": title,
        "author": author,
        "bvid": bvid,
        "quality": quality
    }

def main():
    if len(sys.argv) < 2:
        print("用法:")
        print("  python3 bilibili_downloader.py info <url>")
        print("  python3 bilibili_downloader.py <url> <output_path> [--preparsed <json_path>] [--title <title>]")
        sys.exit(1)

    cmd = sys.argv[1]

    if cmd == "info":
        if len(sys.argv) < 3:
            print("错误: 缺少 URL 参数", file=sys.stderr)
            sys.exit(1)
        url = sys.argv[2]
        try:
            info = fetch_bilibili_info(url)
            print("=== JSON_RESULT_START ===")
            print(json.dumps(info, ensure_ascii=False, indent=2))
            print("=== JSON_RESULT_END ===")
        except Exception as e:
            print(f"解析失败: {e}", file=sys.stderr)
            sys.exit(1)

    else:
        # 下载模式: url output_path [options]
        url = sys.argv[1]
        if len(sys.argv) < 3:
            print("错误: 缺少 output_path 参数", file=sys.stderr)
            sys.exit(1)
        output_path = sys.argv[2]

        preparsed_data = None
        custom_title = None
        delogo_opt = False

        idx = 3
        while idx < len(sys.argv):
            if sys.argv[idx] == "--preparsed" and idx + 1 < len(sys.argv):
                p_file = sys.argv[idx + 1]
                if os.path.exists(p_file):
                    try:
                        with open(p_file, 'r', encoding='utf-8') as pf:
                            preparsed_data = json.load(pf)
                    except Exception as e:
                        log_progress(f"读取预解析缓存提示: {e}")
                idx += 2
            elif sys.argv[idx] == "--title" and idx + 1 < len(sys.argv):
                custom_title = sys.argv[idx + 1]
                idx += 2
            elif sys.argv[idx] == "--delogo":
                delogo_opt = True
                idx += 1
            else:
                idx += 1

        try:
            res = download_bilibili_video(url, output_path, preparsed_data=preparsed_data, custom_title=custom_title, delogo=delogo_opt)
            print("\n=== JSON_SUMMARY_START ===")
            summary = {
                "status": "ok",
                "downloaded_files": [output_path],
                "title": res.get("title"),
                "author": res.get("author"),
                "bvid": res.get("bvid"),
                "quality": res.get("quality")
            }
            print(json.dumps(summary, ensure_ascii=False, indent=2))
            print("=== JSON_SUMMARY_END ===")
        except Exception as e:
            log_progress(f"❌ 下载失败: {e}")
            sys.exit(1)

if __name__ == '__main__':
    main()
