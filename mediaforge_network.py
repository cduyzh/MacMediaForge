"""为网络解析启用证书验证，并兼容 macOS 上未配置 CA 的 Python 安装。"""

import ssl
import subprocess
import sys


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
