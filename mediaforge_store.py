#!/usr/bin/env python3
"""
MediaSaver 爬虫数据持久层 (mediaforge_store.py)

存储设计移植自 MediaCrawler (github.com/NanmiCoder/MediaCrawler) 的 store 层:
- 以平台业务 ID (content_id: tweet_id / note_id / bvid 等) 为主键的
  "check-then-write" 去重语义: 已存在则只增量更新 (file_path/file_size/last_modify_ts),
  不存在则插入 (含 add_ts), 重复爬取同一内容不再重复落盘。
- parse_cache: 解析结果缓存 (带 TTL), 应用重启后同链接直接命中, 不再全量重解析。
- 数据层是旁路能力: 任何存储异常只告警不抛出, 绝不中断下载主流程。
- 纯标准库实现 (sqlite3), 与现有一次性子进程架构兼容。

CLI 用法:
  python3 mediaforge_store.py check <platform> <content_id> [quality]   # 查询是否已下载
  python3 mediaforge_store.py recent [limit]                            # 最近下载记录
  python3 mediaforge_store.py prune                                     # 清理过期解析缓存
"""

import hashlib
import json
import os
import shutil
import sqlite3
import sys
import threading
import time
from typing import Any, Dict, Optional

_LOCK = threading.Lock()
_CONN_CACHE: Dict[str, sqlite3.Connection] = {}


def default_db_path() -> str:
    override = os.environ.get("MEDIAFORGE_STORE_DB")
    if override:
        return override
    home = os.path.expanduser("~")
    base = os.path.join(home, "Library", "Application Support", "cduyzhMediaForge")
    return os.path.join(base, "crawler_data.db")


def _warn(msg: str):
    print(f"[mediaforge_store] {msg}", file=sys.stderr, flush=True)


def _connect(db_path: Optional[str] = None) -> sqlite3.Connection:
    path = db_path or default_db_path()
    with _LOCK:
        conn = _CONN_CACHE.get(path)
        if conn is not None:
            return conn
    os.makedirs(os.path.dirname(path), exist_ok=True)
    conn = sqlite3.connect(path, timeout=5, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("""
        CREATE TABLE IF NOT EXISTS download_record (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            platform TEXT NOT NULL,
            content_id TEXT NOT NULL,
            source_url TEXT DEFAULT '',
            title TEXT DEFAULT '',
            author TEXT DEFAULT '',
            quality TEXT DEFAULT '',
            file_path TEXT NOT NULL,
            file_size INTEGER DEFAULT 0,
            status TEXT DEFAULT 'downloaded',
            error_message TEXT DEFAULT '',
            add_ts INTEGER DEFAULT 0,
            last_modify_ts INTEGER DEFAULT 0,
            UNIQUE(platform, content_id, quality)
        )
    """)
    conn.execute("""
        CREATE INDEX IF NOT EXISTS idx_record_platform_cid
        ON download_record(platform, content_id)
    """)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS parse_cache (
            cache_key TEXT PRIMARY KEY,
            platform TEXT DEFAULT '',
            url TEXT DEFAULT '',
            payload TEXT DEFAULT '',
            created_ts INTEGER DEFAULT 0
        )
    """)
    conn.commit()
    with _LOCK:
        _CONN_CACHE[path] = conn
    return conn


def _now() -> int:
    return int(time.time())


def content_key(url: str) -> str:
    """无平台业务 ID 时的兜底内容键: URL 指纹"""
    return "url_" + hashlib.sha1(url.encode("utf-8")).hexdigest()[:16]


# MARK: - 下载记录 (check-then-write 去重)

def find_download(platform: str, content_id: str, quality: str = "") -> Optional[Dict[str, Any]]:
    """查询某平台内容的最近成功下载记录; 未下载或文件已丢失返回 None"""
    if not platform or not content_id:
        return None
    try:
        conn = _connect()
        row = conn.execute(
            "SELECT * FROM download_record WHERE platform=? AND content_id=? AND quality=? AND status='downloaded' "
            "ORDER BY last_modify_ts DESC LIMIT 1",
            (platform, content_id, quality or ""),
        ).fetchone()
        if row is None:
            return None
        record = dict(row)
        if record.get("file_path") and not os.path.exists(record["file_path"]):
            return None
        return record
    except Exception as e:
        _warn(f"find_download 异常(忽略): {e}")
        return None


def record_download(
    platform: str,
    content_id: str,
    file_path: str,
    source_url: str = "",
    title: str = "",
    author: str = "",
    quality: str = "",
) -> None:
    """记录一次成功下载; 已有同键记录时只增量更新路径/大小/时间戳"""
    if not platform or not content_id or not file_path or not os.path.exists(file_path):
        return
    try:
        size = os.path.getsize(file_path)
        conn = _connect()
        with _LOCK:
            existing = conn.execute(
                "SELECT id FROM download_record WHERE platform=? AND content_id=? AND quality=?",
                (platform, content_id, quality or ""),
            ).fetchone()
            now = _now()
            if existing:
                conn.execute(
                    "UPDATE download_record SET file_path=?, file_size=?, status='downloaded', "
                    "error_message='', source_url=COALESCE(NULLIF(?,''), source_url), "
                    "title=COALESCE(NULLIF(?,''), title), author=COALESCE(NULLIF(?,''), author), "
                    "last_modify_ts=? WHERE id=?",
                    (file_path, size, source_url, title, author, now, existing["id"]),
                )
            else:
                conn.execute(
                    "INSERT INTO download_record (platform, content_id, source_url, title, author, quality, "
                    "file_path, file_size, status, add_ts, last_modify_ts) VALUES (?,?,?,?,?,?,?,?,'downloaded',?,?)",
                    (platform, content_id, source_url, title, author, quality or "", file_path, size, now, now),
                )
            conn.commit()
    except Exception as e:
        _warn(f"record_download 异常(忽略): {e}")


def record_failure(platform: str, content_id: str, source_url: str = "", quality: str = "", error: str = "") -> None:
    """记录失败原因, 便于排障; 失败记录不参与 find_download 命中"""
    if not platform or not content_id:
        return
    try:
        conn = _connect()
        with _LOCK:
            existing = conn.execute(
                "SELECT id FROM download_record WHERE platform=? AND content_id=? AND quality=?",
                (platform, content_id, quality or ""),
            ).fetchone()
            now = _now()
            if existing:
                conn.execute(
                    "UPDATE download_record SET status='failed', error_message=?, last_modify_ts=? WHERE id=?",
                    (error[:500], now, existing["id"]),
                )
            else:
                conn.execute(
                    "INSERT INTO download_record (platform, content_id, source_url, quality, file_path, "
                    "status, error_message, add_ts, last_modify_ts) VALUES (?,?,?,?,?,'failed',?,?,?)",
                    (platform, content_id, source_url, quality or "", "", error[:500], now, now),
                )
            conn.commit()
    except Exception as e:
        _warn(f"record_failure 异常(忽略): {e}")


# MARK: - 解析结果缓存 (带 TTL)

def _parse_cache_key(platform: str, url: str, quality: str = "") -> str:
    raw = f"{platform}|{quality}|{url}"
    return hashlib.sha1(raw.encode("utf-8")).hexdigest()


def get_parse(platform: str, url: str, quality: str = "", ttl_sec: int = 1800) -> Optional[Dict[str, Any]]:
    """读取解析缓存; 超过 TTL 或损坏返回 None"""
    try:
        conn = _connect()
        row = conn.execute(
            "SELECT payload, created_ts FROM parse_cache WHERE cache_key=?",
            (_parse_cache_key(platform, url, quality),),
        ).fetchone()
        if row is None:
            return None
        if _now() - int(row["created_ts"]) >= ttl_sec:
            return None
        payload = json.loads(row["payload"])
        if isinstance(payload, dict):
            return payload
        return None
    except Exception as e:
        _warn(f"get_parse 异常(忽略): {e}")
        return None


def put_parse(platform: str, url: str, payload: Dict[str, Any], quality: str = "") -> None:
    """写入解析缓存 (覆盖旧值)"""
    if not isinstance(payload, dict) or not payload:
        return
    try:
        conn = _connect()
        with _LOCK:
            conn.execute(
                "INSERT INTO parse_cache (cache_key, platform, url, payload, created_ts) VALUES (?,?,?,?,?) "
                "ON CONFLICT(cache_key) DO UPDATE SET payload=excluded.payload, created_ts=excluded.created_ts",
                (_parse_cache_key(platform, url, quality), platform, url, json.dumps(payload, ensure_ascii=False), _now()),
            )
            conn.commit()
    except Exception as e:
        _warn(f"put_parse 异常(忽略): {e}")


def invalidate_parse(platform: str, url: str, quality: str = "") -> None:
    """缓存直链失效 (下载失败) 时主动作废, 下次强制在线解析"""
    try:
        conn = _connect()
        with _LOCK:
            conn.execute("DELETE FROM parse_cache WHERE cache_key=?", (_parse_cache_key(platform, url, quality),))
            conn.commit()
    except Exception as e:
        _warn(f"invalidate_parse 异常(忽略): {e}")


def prune_parse_cache(max_age_sec: int = 86400) -> int:
    """清理过期解析缓存, 返回清理条数"""
    try:
        conn = _connect()
        with _LOCK:
            cur = conn.execute("DELETE FROM parse_cache WHERE created_ts < ?", (_now() - max_age_sec,))
            conn.commit()
            return cur.rowcount
    except Exception as e:
        _warn(f"prune_parse_cache 异常(忽略): {e}")
        return 0


# MARK: - 去重复用工具

def link_or_copy(src: str, dst: str) -> bool:
    """优先硬链接 (零额外磁盘占用) 复用已下载文件, 跨卷时退化为拷贝"""
    if not os.path.exists(src):
        return False
    os.makedirs(os.path.dirname(dst) or ".", exist_ok=True)
    if os.path.exists(dst):
        return os.path.getsize(dst) == os.path.getsize(src)
    try:
        os.link(src, dst)
        return True
    except OSError:
        try:
            shutil.copy2(src, dst)
            return True
        except Exception as e:
            _warn(f"link_or_copy 失败: {e}")
            return False


def reuse_downloaded(platform: str, content_id: str, quality: str, dest_path: str) -> Optional[str]:
    """去重门: 命中且本地文件仍存在时, 硬链接复用到 dest_path 并返回原路径, 否则 None"""
    record = find_download(platform, content_id, quality)
    if not record:
        return None
    src = record.get("file_path", "")
    if link_or_copy(src, dest_path):
        return src
    return None


if __name__ == "__main__":
    if len(sys.argv) >= 4 and sys.argv[1] == "check":
        rec = find_download(sys.argv[2], sys.argv[3], sys.argv[4] if len(sys.argv) > 4 else "")
        print(json.dumps({"found": bool(rec), "record": rec}, ensure_ascii=False, indent=2))
    elif len(sys.argv) >= 2 and sys.argv[1] == "recent":
        limit = int(sys.argv[2]) if len(sys.argv) > 2 else 20
        try:
            rows = _connect().execute(
                "SELECT * FROM download_record ORDER BY last_modify_ts DESC LIMIT ?", (limit,)
            ).fetchall()
            print(json.dumps([dict(r) for r in rows], ensure_ascii=False, indent=2))
        except Exception as e:
            _warn(f"recent 异常: {e}")
    elif len(sys.argv) >= 2 and sys.argv[1] == "prune":
        print(json.dumps({"pruned": prune_parse_cache()}))
    else:
        print(__doc__)
