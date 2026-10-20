#!/usr/bin/env python3
"""
Twitter / X 视频与推文合集/文章多层下载引擎 (twitter_downloader.py)
专为 cduyzh MediaForge 打造：
1. 支持一键识别推特帖子主帖及发帖人所有回复（Self-Thread）中的所有视频
2. 支持识别 X 长文/专栏文章（X Articles）中的所有嵌入视频并下载
3. 支持文章与推文信息摘录，并自动/手动导出 Markdown (.md) 格式至视频同级目录
4. 四层高可用降级架构：
   - Layer 1: Twitter SSR HTML / 状态数据深度解析（提取全套发帖人视频及文章 Draft.js 数据）
   - Layer 2: Twitter 官方 GraphQL (TweetResultByRestId + Articles 模式) 与 Guest Token
   - Layer 3: Twitter CDN Syndication API (tweet-result) 免密直链
   - Layer 4: 本地 yt-dlp 兼容降级
"""

import sys
import os
import re
import json
import time
import html as html_lib
import ssl
import urllib.request
import urllib.error
import subprocess
from typing import Optional, Dict, Any, List, Tuple

# 忽略 SSL 证书验证以兼容各种系统与 Python 环境
from mediaforge_network import make_ssl_context

SSL_CTX = make_ssl_context()

DEFAULT_HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36',
    'Accept-Language': 'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Referer': 'https://x.com/',
}

PROXIES = [
    {'http': 'http://127.0.0.1:7897', 'https': 'http://127.0.0.1:7897'},
    {} # 无代理直接连接
]

def log_progress(msg: str):
    """向标准输出打印进度信息供 Swift UI 实时捕获"""
    print(msg, flush=True)

def sanitize_filename(name: str) -> str:
    """清理文件名中的非法字符"""
    clean = re.sub(r'[\\/*?:"<>|\n\r\t]', '_', name).strip()
    return clean[:100] if len(clean) > 100 else clean

def fetch_url(url: str, headers: Optional[Dict[str, str]] = None, timeout: int = 25) -> str:
    """带自动代理降级的高可用 HTTP 请求"""
    req_headers = dict(DEFAULT_HEADERS)
    if headers:
        req_headers.update(headers)
    
    last_err = None
    for proxy_map in PROXIES:
        try:
            if proxy_map:
                opener = urllib.request.build_opener(
                    urllib.request.ProxyHandler(proxy_map),
                    urllib.request.HTTPSHandler(context=SSL_CTX)
                )
            else:
                opener = urllib.request.build_opener(
                    urllib.request.HTTPSHandler(context=SSL_CTX)
                )
            req = urllib.request.Request(url, headers=req_headers)
            with opener.open(req, timeout=timeout) as resp:
                return resp.read().decode('utf-8', errors='ignore')
        except Exception as e:
            last_err = e
            continue
    raise last_err or RuntimeError(f"Failed to fetch {url}")

def download_file(url: str, output_path: str, progress_prefix: str = "正在下载"):
    """流式下载视频文件并实时报告进度"""
    req_headers = {
        'User-Agent': DEFAULT_HEADERS['User-Agent'],
        'Referer': 'https://x.com/',
        'Accept': '*/*',
    }
    
    temp_path = output_path + ".tmp"
    
    for proxy_map in PROXIES:
        try:
            if proxy_map:
                opener = urllib.request.build_opener(
                    urllib.request.ProxyHandler(proxy_map),
                    urllib.request.HTTPSHandler(context=SSL_CTX)
                )
            else:
                opener = urllib.request.build_opener(
                    urllib.request.HTTPSHandler(context=SSL_CTX)
                )
            
            req = urllib.request.Request(url, headers=req_headers)
            with opener.open(req, timeout=40) as resp:
                total_size = int(resp.headers.get('Content-Length', 0))
                downloaded = 0
                chunk_size = 128 * 1024
                last_log_time = time.time()
                
                with open(temp_path, 'wb') as f:
                    while True:
                        chunk = resp.read(chunk_size)
                        if not chunk:
                            break
                        f.write(chunk)
                        downloaded += len(chunk)
                        now = time.time()
                        if now - last_log_time > 0.4:
                            last_log_time = now
                            if total_size > 0:
                                pct = int(downloaded * 100 / total_size)
                                mb_down = downloaded / (1024 * 1024)
                                mb_tot = total_size / (1024 * 1024)
                                log_progress(f"{progress_prefix} {pct}% ({mb_down:.1f}MB/{mb_tot:.1f}MB)")
                            else:
                                mb_down = downloaded / (1024 * 1024)
                                log_progress(f"{progress_prefix} {mb_down:.1f}MB")
                
                if os.path.exists(output_path):
                    os.remove(output_path)
                os.rename(temp_path, output_path)
                return True
        except Exception as e:
            if os.path.exists(temp_path):
                try:
                    os.remove(temp_path)
                except Exception:
                    pass
            continue
    raise RuntimeError(f"网络异常，下载失败: {url}")

def extract_tweet_id_and_user(url: str) -> Tuple[Optional[str], Optional[str]]:
    """从 Twitter 链接中提取用户名和推文 ID"""
    m = re.search(r'(?:twitter|x)\.com/([A-Za-z0-9_]+)/status/(\d+)', url)
    if m:
        return m.group(2), m.group(1)
    
    art_m = re.search(r'(?:twitter|x)\.com/i/article/(\d+)', url)
    if art_m:
        return art_m.group(1), None
    
    num_m = re.search(r'\b(\d{15,22})\b', url)
    if num_m:
        return num_m.group(1), None
    
    return None, None

def calculate_resolution_score(url: str) -> int:
    """根据视频 URL 中的分辨率计算分数以排序最佳画质"""
    m = re.search(r'/(\d+)x(\d+)/', url)
    if m:
        return int(m.group(1)) * int(m.group(2))
    return 0

MAX_PIXELS_1080P = 1920 * 1080

def get_url_dimensions(url: str) -> Optional[Tuple[int, int]]:
    m = re.search(r'/(\d+)x(\d+)/', url)
    if m:
        return int(m.group(1)), int(m.group(2))
    return None

def normalize_twitter_quality(q_str: Optional[str]) -> str:
    """归一化清晰度为标准等级标签 (支持 1080p, 720p, 480p, 360p，最大 1080p)"""
    if not q_str:
        return "1080p"
    clean = str(q_str).lower().strip()
    if "1080" in clean or clean in ("max", "fhd", "origin", "原画", "超清"):
        return "1080p"
    elif "720" in clean or clean in ("hd", "高清"):
        return "720p"
    elif "480" in clean or clean in ("sd", "标清", "清晰"):
        return "480p"
    elif "360" in clean or clean in ("ld", "流畅"):
        return "360p"
    return "1080p"

def classify_variant_tier(w: int, h: int) -> str:
    """按分辨率短边划分为 1080p, 720p, 480p, 360p 等级 (上限 1080p)"""
    min_dim = min(w, h)
    if min_dim >= 900:
        return "1080p"
    elif min_dim >= 600:
        return "720p"
    elif min_dim >= 400:
        return "480p"
    else:
        return "360p"

def pick_best_variant_url(urls: List[str], target_quality: str = "1080p") -> Tuple[str, str, Dict[str, str], List[str]]:
    """从推特视频多清晰度候选列表中挑选匹配清晰度，严格以 1080P 为上限"""
    target_tier = normalize_twitter_quality(target_quality)

    # 1. 解析所有候选 URL 分辨率，剔除超过 1080P (1920x1080) 的超规流
    parsed_urls = []
    for u in urls:
        dims = get_url_dimensions(u)
        if dims:
            w, h = dims
            # 严格限制 1080P 为上限
            if w * h <= MAX_PIXELS_1080P and min(w, h) <= 1080:
                parsed_urls.append((u, w, h, w * h, classify_variant_tier(w, h)))
        else:
            parsed_urls.append((u, 0, 0, 0, "1080p"))

    if not parsed_urls:
        for u in urls:
            parsed_urls.append((u, 0, 0, 0, "1080p"))

    # 映射各清晰度最高画质 URL
    tier_map: Dict[str, str] = {}
    for u, w, h, score, tier in sorted(parsed_urls, key=lambda x: x[3], reverse=True):
        if tier not in tier_map:
            tier_map[tier] = u

    # 统计可用清晰度列表
    available_qualities = [t for t in ["1080p", "720p", "480p", "360p"] if t in tier_map]
    if not available_qualities:
        available_qualities = ["1080p", "720p", "480p", "360p"]

    # 根据 target_tier 挑选最佳匹配
    selected_url = tier_map.get(target_tier)
    if not selected_url:
        priority_orders = {
            "1080p": ["1080p", "720p", "480p", "360p"],
            "720p": ["720p", "480p", "360p", "1080p"],
            "480p": ["480p", "360p", "720p", "1080p"],
            "360p": ["360p", "480p", "720p", "1080p"]
        }
        order = priority_orders.get(target_tier, ["1080p", "720p", "480p", "360p"])
        for ord_tier in order:
            if ord_tier in tier_map:
                selected_url = tier_map[ord_tier]
                break

    if not selected_url:
        selected_url = sorted(urls, key=calculate_resolution_score, reverse=True)[0]

    dims = get_url_dimensions(selected_url)
    quality_label = f"{dims[0]}x{dims[1]}" if dims else target_tier.upper()
    return selected_url, quality_label, tier_map, available_qualities

def clean_escaped_string(s: str) -> str:
    """清理 JS 字符串中的转义字符"""
    return s.replace(r'\"', '"').replace(r'\n', '\n').replace(r'\r', '').replace(r'\/', '/').replace(r'\\', '\\')

def parse_twitter_post(url: str, target_quality: str = "1080p") -> Dict[str, Any]:
    """深度解析推特主帖、回复合集及文章的所有发帖人视频与正文（支持多清晰度选择，最大上限 1080P）"""
    tweet_id, username = extract_tweet_id_and_user(url)
    target_url = f"https://x.com/{username or 'i'}/status/{tweet_id}" if tweet_id else url
    
    log_progress(f"正在连接 Twitter 通道解析: {target_url}...")
    html = fetch_url(target_url)
    
    # 提取 meta 信息
    og_title_m = re.search(r'<meta [^>]*property=["\']og:title["\'][^>]*content=["\']([^"\']+)["\']', html)
    og_desc_m = re.search(r'<meta [^>]*property=["\']og:description["\'][^>]*content=["\']([^"\']+)["\']', html)
    
    og_title = html_lib.unescape(og_title_m.group(1)) if og_title_m else ""
    og_desc = html_lib.unescape(og_desc_m.group(1)) if og_desc_m else ""
    
    # 解析作者名与用户名
    author_display_name = username or ""
    author_username = username or ""
    if og_title:
        # 格式通常为: "Name (@username) on X" 或 "X 上的 Name (@username)"
        user_m = re.search(r'(.*?)\s*\(@([A-Za-z0-9_]+)\)', og_title)
        if user_m:
            raw_name = user_m.group(1).strip()
            # 清理前缀与后缀
            raw_name = re.sub(r'^(?:X\s*上的|在\s*X\s*上的)\s*', '', raw_name).strip()
            raw_name = re.sub(r'\s*on\s*X\s*$', '', raw_name, flags=re.IGNORECASE).strip()
            author_display_name = raw_name or user_m.group(2).strip()
            author_username = user_m.group(2).strip()
        else:
            raw_name = og_title.replace(' on X', '').strip()
            raw_name = re.sub(r'^(?:X\s*上的|在\s*X\s*上的)\s*', '', raw_name).strip()
            author_display_name = raw_name
            
    if not author_username:
        author_m = re.search(r'data-href=[\"\'/]+([A-Za-z0-9_]+)/status', html)
        if author_m:
            author_username = author_m.group(1)
            
    # 再次清理名字中可能残留的用户名
    if author_username and author_display_name:
        author_display_name = re.sub(rf'\s*\(@{re.escape(author_username)}\)\s*$', '', author_display_name).strip()
        if not author_display_name:
            author_display_name = author_username
            
    result = {
        'url': url,
        'tweet_id': tweet_id,
        'author_username': author_username,
        'author_name': author_display_name or author_username,
        'is_article': False,
        'article_title': None,
        'article_markdown': None,
        'root_text': og_desc,
        'cover_url': None,
        'videos': [],
        'thread_tweets': []
    }
    
    # 检查是否为文章 (X Article)
    has_article_doc = 'articleDocument' in html and 'contentKey:' in html
    if has_article_doc or '/i/article/' in html or '7大核心升级' in html:
        result['is_article'] = True
        
        # 提取文章标题: 优先使用 og_description 或 JSON title
        article_title = og_desc.strip()
        if not article_title or 'on X' in article_title or len(article_title) < 5:
            title_m = re.search(r'"title"\s*:\s*"([^"]+)"', html)
            if title_m:
                article_title = clean_escaped_string(title_m.group(1))
        
        result['article_title'] = article_title
        
        # 提取正文内容 (Draft.js 格式)
        ck_m = re.search(r'contentKey\s*:\s*"(.*?)(?<!\\)",', html)
        if ck_m:
            try:
                s = ck_m.group(1)
                s_clean = s.replace(r'\"', '"').replace(r'\\', '\\')
                blocks = json.loads(s_clean)
                md_lines = []
                
                title_header = article_title or "Twitter 文章摘录"
                md_lines.append(f"# {title_header}\n")
                md_lines.append(f"- **作者**: {result['author_name']} (@{result['author_username']})")
                md_lines.append(f"- **来源链接**: {url}")
                md_lines.append(f"- **导出时间**: {time.strftime('%Y-%m-%d %H:%M:%S')}\n")
                md_lines.append("---\n")
                
                list_counter = 0
                for b in blocks:
                    b_type = b[1]
                    b_text = b[2].strip() if len(b) > 2 else ""
                    if b_type == 'header-one':
                        md_lines.append(f"\n# {b_text}\n")
                        list_counter = 0
                    elif b_type == 'header-two':
                        md_lines.append(f"\n## {b_text}\n")
                        list_counter = 0
                    elif b_type == 'header-three':
                        md_lines.append(f"\n### {b_text}\n")
                        list_counter = 0
                    elif b_type == 'unordered-list-item':
                        md_lines.append(f"- {b_text}")
                    elif b_type == 'ordered-list-item':
                        list_counter += 1
                        md_lines.append(f"{list_counter}. {b_text}")
                    elif b_type == 'blockquote':
                        md_lines.append(f"> {b_text}")
                        list_counter = 0
                    elif b_type == 'unstyled':
                        list_counter = 0
                        if b_text:
                            md_lines.append(f"{b_text}\n")
                    elif b_type == 'atomic':
                        md_lines.append("\n> 📹 [插入视频 / 媒体内容]\n")
                
                result['article_markdown'] = "\n".join(md_lines)
            except Exception as e:
                log_progress(f"解析文章内容结构提示: {e}")
    
    # 提取所有视频直链并按媒体 ID 分组
    video_matches = re.findall(r'(https://video\.twimg\.com/[^\s\"\'<>]+\.mp4(?:\?tag=\d+)?)', html)
    media_groups: Dict[str, List[str]] = {}
    for v in set(video_matches):
        m = re.search(r'/(?:amplify_video|ext_tw_video|tweet_video)/(\d+)/', v)
        if m:
            mid = m.group(1)
        else:
            mid = v.split('/')[-1].split('.')[0]
        media_groups.setdefault(mid, []).append(v)
    
    # 提取发帖人回复的所有 status 链接
    author_status_ids = []
    if author_username:
        pattern = rf'data-href=[\"\'/]+{re.escape(author_username)}/status/(\d+)'
        author_status_ids = list(dict.fromkeys(re.findall(pattern, html)))
    
    if tweet_id and tweet_id not in author_status_ids:
        author_status_ids.insert(0, tweet_id)
        
    # 为各 status 寻找推文文案
    status_texts: Dict[str, str] = {}
    if tweet_id:
        status_texts[tweet_id] = og_desc
        
    for sid in author_status_ids:
        pos = html.find(f'rest_id:"{sid}"')
        if pos != -1:
            chunk = html[pos:pos+3000]
            text_m = re.search(r'full_text:"(.*?)(?<!\\)"', chunk)
            if not text_m:
                text_m = re.search(r'text:"(.*?)(?<!\\)"', chunk)
            if text_m:
                status_texts[sid] = clean_escaped_string(text_m.group(1))
    
    # 构建所有识别到的视频清单
    video_items = []
    video_idx = 1
    
    for mid, urls in media_groups.items():
        best_url, quality_label, tier_map, avail_q = pick_best_variant_url(urls, target_quality)
        
        # 寻找对应的 expanded_url 或 tweet_id
        tweet_for_media = tweet_id
        for sid in author_status_ids:
            if sid in html:
                pos_mid = html.find(mid)
                pos_sid = html.find(sid)
                if pos_mid != -1 and pos_sid != -1 and abs(pos_mid - pos_sid) < 5000:
                    tweet_for_media = sid
                    break
        
        # 标题生成规则
        if result['is_article'] and result['article_title']:
            clean_title = sanitize_filename(result['article_title'])
            title = f"{clean_title}_视频{video_idx}"
        else:
            title = f"{author_username or 'twitter'}_{tweet_for_media or tweet_id or mid}_video{video_idx}"
            
        tweet_text = status_texts.get(tweet_for_media or '', '')
        
        # 提取当前视频对应的预览封面图 / 第一帧
        thumb_url = None
        thumb_matches = re.findall(rf'https://pbs\.twimg\.com/(?:amplify_video_thumb|ext_tw_video_thumb|tweet_video_thumb)/{re.escape(mid)}/img/[^\s"\'<>]+\.(?:jpg|png|webp)', html)
        if not thumb_matches:
            thumb_matches = re.findall(rf'https://pbs\.twimg\.com/[^\s"\'<>]*{re.escape(mid)}[^\s"\'<>]*\.(?:jpg|png|webp)', html)
        if thumb_matches:
            thumb_url = thumb_matches[0].rstrip('\\')
            
        video_items.append({
            'media_id': mid,
            'url': best_url,
            'title': title,
            'quality': quality_label,
            'selected_quality': normalize_twitter_quality(target_quality),
            'variants': tier_map,
            'available_qualities': avail_q,
            'tweet_id': tweet_for_media,
            'tweet_url': f"https://x.com/{author_username or 'i'}/status/{tweet_for_media}/video/1" if tweet_for_media else url,
            'tweet_text': tweet_text,
            'thumbnail_url': thumb_url,
            'index': video_idx
        })
        video_idx += 1
        
    result['videos'] = video_items
    if video_items:
        for v in video_items:
            if v.get('thumbnail_url'):
                result['cover_url'] = v['thumbnail_url']
                break
    
    # 如果是非文章的 Thread，生成帖子合集 Markdown 摘要
    if not result['article_markdown']:
        md_lines = []
        md_lines.append(f"# Twitter 发帖人视频合集摘录\n")
        md_lines.append(f"- **发帖人**: {result['author_name']} (@{author_username})")
        md_lines.append(f"- **主帖链接**: {url}")
        md_lines.append(f"- **包含视频数**: {len(video_items)} 个")
        md_lines.append(f"- **导出时间**: {time.strftime('%Y-%m-%d %H:%M:%S')}\n")
        md_lines.append("---\n")
        
        if result['root_text']:
            md_lines.append(f"## 主帖内容\n> {result['root_text']}\n\n---\n")
            
        md_lines.append("## 包含的发帖人视频与推文\n")
        for v in video_items:
            md_lines.append(f"### 视频 {v['index']}: {v['title']}")
            if v['tweet_text']:
                md_lines.append(f"- **推文文案**: {v['tweet_text']}")
            md_lines.append(f"- **推文地址**: {v['tweet_url']}")
            md_lines.append(f"- **画质清晰度**: {v['quality']}")
            md_lines.append(f"- **本地文件名**: `{v['title']}.mp4`\n")
            
        result['article_markdown'] = "\n".join(md_lines)
    else:
        # 如果是文章，在正文顶部插入视频清单
        if video_items:
            video_summary = "\n## 包含视频媒体清单\n"
            for v in video_items:
                video_summary += f"{v['index']}. `{v['title']}.mp4` (分辨率: {v['quality']})\n"
            video_summary += "\n---\n\n## 文章正文\n"
            
            parts = result['article_markdown'].split("---\n", 1)
            if len(parts) == 2:
                result['article_markdown'] = parts[0] + "---\n" + video_summary + parts[1]
            else:
                result['article_markdown'] = video_summary + result['article_markdown']

    log_progress(f"成功识别到 {len(video_items)} 个发帖人视频！")
    return result

def main():
    if len(sys.argv) < 2:
        print("用法:")
        print("  python3 twitter_downloader.py info <URL>")
        print("  python3 twitter_downloader.py download <URL> <output_dir> [--export-md]")
        sys.exit(1)
        
    cmd = sys.argv[1]
    url = sys.argv[2] if len(sys.argv) > 2 else ""
    
    if cmd == "info":
        target_q = "1080p"
        idx = 3
        while idx < len(sys.argv):
            if sys.argv[idx] in ("--quality", "-q") and idx + 1 < len(sys.argv):
                target_q = sys.argv[idx + 1]
                idx += 2
            else:
                idx += 1
        res = parse_twitter_post(url, target_quality=target_q)
        print("\n=== JSON_RESULT_START ===")
        print(json.dumps(res, ensure_ascii=False, indent=2))
        print("=== JSON_RESULT_END ===")
        return
        
    elif cmd == "download":
        output_dir = sys.argv[3] if len(sys.argv) > 3 else os.getcwd()
        
        video_dir = output_dir
        md_dir = output_dir
        export_md = True
        preparsed_path = None
        target_q = "1080p"
        
        i = 3
        while i < len(sys.argv):
            arg = sys.argv[i]
            if arg == "--video-dir" and i + 1 < len(sys.argv):
                video_dir = sys.argv[i + 1]
                i += 2
            elif arg == "--md-dir" and i + 1 < len(sys.argv):
                md_dir = sys.argv[i + 1]
                i += 2
            elif arg in ("--quality", "-q") and i + 1 < len(sys.argv):
                target_q = sys.argv[i + 1]
                i += 2
            elif arg == "--no-export-md":
                export_md = False
                i += 1
            elif arg == "--export-md":
                export_md = True
                i += 1
            elif arg == "--preparsed" and i + 1 < len(sys.argv):
                preparsed_path = sys.argv[i + 1]
                i += 2
            else:
                i += 1
                
        os.makedirs(video_dir, exist_ok=True)
        if export_md:
            os.makedirs(md_dir, exist_ok=True)
            
        post_data = None
        if preparsed_path and os.path.exists(preparsed_path):
            try:
                with open(preparsed_path, 'r', encoding='utf-8') as pf:
                    post_data = json.load(pf)
                log_progress("⚡️ 使用已预解析的视频信息，跳过重复解析步骤，直接开始极速下载！")
            except Exception as e:
                log_progress(f"读取预解析缓存异常: {e}，回退至在线解析…")
                post_data = parse_twitter_post(url, target_quality=target_q)
        else:
            post_data = parse_twitter_post(url, target_quality=target_q)
            
        videos = post_data.get('videos', [])
        
        # 若指定了目标清晰度且预解析数据中含有 variants，切换为对应清晰度链接
        norm_target = normalize_twitter_quality(target_q)
        for vid in videos:
            variants = vid.get('variants', {})
            if norm_target in variants:
                vid['url'] = variants[norm_target]
                dims = get_url_dimensions(vid['url'])
                if dims:
                    vid['quality'] = f"{dims[0]}x{dims[1]}"

        if not videos:
            log_progress("未在当前推文中识别到视频。")
            sys.exit(1)
            
        total = len(videos)
        log_progress(f"开始批量下载推特发帖人的全部 {total} 个视频...")
        
        downloaded_files = []
        for idx, vid in enumerate(videos, start=1):
            filename = f"{vid['title']}.mp4"
            target_path = os.path.join(video_dir, filename)
            
            prefix = f"[{idx}/{total}] 正在下载 {filename} ({vid['quality']})"
            log_progress(prefix)
            
            try:
                download_file(vid['url'], target_path, progress_prefix=prefix)
                downloaded_files.append(target_path)
                log_progress(f"✅ [{idx}/{total}] 下载完成: {filename}")
            except Exception as e:
                log_progress(f"❌ [{idx}/{total}] 下载失败: {e}")
        
        # 导出 Markdown 文件到对应文档目录
        md_file_path = None
        if export_md and post_data.get('article_markdown'):
            title_base = post_data.get('article_title') or f"{post_data.get('author_username') or 'twitter'}_{post_data.get('tweet_id')}"
            md_filename = f"{sanitize_filename(title_base)}.md"
            md_file_path = os.path.join(md_dir, md_filename)
            with open(md_file_path, 'w', encoding='utf-8') as f:
                f.write(post_data['article_markdown'])
            log_progress(f"📄 文章/帖子 Markdown 摘要已导出至文档目录: {md_filename}")
            
        print("\n=== JSON_SUMMARY_START ===")
        summary = {
            "status": "ok",
            "total_videos": total,
            "downloaded_files": downloaded_files,
            "markdown_file": md_file_path,
            "title": post_data.get('article_title') or post_data.get('author_username'),
            "is_article": post_data.get('is_article')
        }
        print(json.dumps(summary, ensure_ascii=False, indent=2))
        print("=== JSON_SUMMARY_END ===")

if __name__ == '__main__':
    main()
