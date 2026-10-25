#!/usr/bin/env python3
"""
Unit tests for Bilibili collection and multi-P video extraction.
Tested against live Bilibili API for BV18c8Z6XEMS and mock structures.
"""
import unittest
import sys
import os
import json

# Add parent directory to path so we can import bilibili_downloader
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import bilibili_downloader

class TestBilibiliCollection(unittest.TestCase):

    def test_bv18c8z6xems_collection(self):
        """测试用户指定样例视频 BV18c8Z6XEMS 的合集提取"""
        url = "https://www.bilibili.com/video/BV18c8Z6XEMS"
        info = bilibili_downloader.fetch_bilibili_info(url)
        
        self.assertEqual(info.get("status"), "ok")
        self.assertEqual(info.get("bvid"), "BV18c8Z6XEMS")
        self.assertIn("崩铁", info.get("title", ""))
        
        # 校验合集元数据
        collection = info.get("collection")
        self.assertIsNotNone(collection, "BV18c8Z6XEMS 必须包含合集信息")
        self.assertEqual(collection.get("type"), "ugc_season")
        self.assertEqual(collection.get("type_label"), "合集")
        self.assertIn("星铁精彩剧情", collection.get("title", ""))
        self.assertGreaterEqual(collection.get("ep_count", 0), 200, "合集集数应不少于 200 集")
        
        sections = collection.get("sections", [])
        self.assertGreaterEqual(len(sections), 5, "合集应包含至少 5 个分卷")
        
        # 统计总集数
        total_episodes = sum(len(s.get("episodes", [])) for s in sections)
        self.assertEqual(total_episodes, collection.get("ep_count"))
        
        # 检查第一个视频的结构完整性
        first_ep = sections[0].get("episodes", [])[0]
        self.assertTrue(first_ep.get("bvid", "").startswith("BV"))
        self.assertGreater(first_ep.get("cid", 0), 0)
        self.assertTrue(len(first_ep.get("title", "")) > 0)
        self.assertTrue(first_ep.get("url", "").startswith("https://www.bilibili.com/video/BV"))
        self.assertTrue(":" in first_ep.get("duration_str", ""))
        self.assertTrue(first_ep.get("cover_url", "").startswith("http"))
        
        # 检查当前视频是否被正确标记
        found_current = False
        for sec in sections:
            for ep in sec.get("episodes", []):
                if ep.get("bvid") == "BV18c8Z6XEMS":
                    self.assertTrue(ep.get("is_current"))
                    found_current = True
                else:
                    self.assertFalse(ep.get("is_current"))
        self.assertTrue(found_current, "合集中必须包含且标记当前视频 BV18c8Z6XEMS")

    def test_page_p_param_handling(self):
        """测试 ?p= 参数的分P定向选择功能"""
        # 测试 p=1 和无 p 参数
        info_default = bilibili_downloader.fetch_bilibili_info("https://www.bilibili.com/video/BV18c8Z6XEMS")
        info_p1 = bilibili_downloader.fetch_bilibili_info("https://www.bilibili.com/video/BV18c8Z6XEMS?p=1")
        self.assertEqual(info_default["cid"], info_p1["cid"])

if __name__ == '__main__':
    unittest.main()
