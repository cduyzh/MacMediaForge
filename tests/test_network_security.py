"""网络解析必须验证证书与主机名，不依赖开发者私人 Python 证书安装。"""

import importlib.util
from pathlib import Path
import ssl
import sys
import unittest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))


class NetworkSecurityTests(unittest.TestCase):
    def test_all_platforms_verify_tls(self):
        for name in ("xhs_downloader", "twitter_downloader", "bilibili_downloader"):
            with self.subTest(platform=name):
                spec = importlib.util.spec_from_file_location(name, ROOT / (name + ".py"))
                module = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(module)
                context = module.SSL_CTX
                self.assertEqual(context.verify_mode, ssl.CERT_REQUIRED)
                self.assertTrue(context.check_hostname)
                self.assertGreater(context.cert_store_stats()["x509_ca"], 0)


if __name__ == "__main__":
    unittest.main()
