import Foundation
import AppKit

// MARK: - 小红书鉴权与凭证管理器
class XHSAuthManager: ObservableObject {
    static let shared = XHSAuthManager()

    private let userDefaultsKeyCookie = "xhs_auth_cookie"
    private let userDefaultsKeyToken = "xhs_auth_default_token"

    @Published var cookie: String = ""
    @Published var defaultToken: String = ""

    var hasConfiguredCookie: Bool {
        !cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private init() {
        self.cookie = UserDefaults.standard.string(forKey: userDefaultsKeyCookie) ?? ""
        self.defaultToken = UserDefaults.standard.string(forKey: userDefaultsKeyToken) ?? ""
        syncToDisk()
    }

    /// 更新并保存鉴权配置
    func saveAuth(cookie: String, defaultToken: String = "") {
        let trimmedCookie = cookie.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = defaultToken.trimmingCharacters(in: .whitespacesAndNewlines)

        // 智能兼容：如果用户粘贴的是导出的完整 JSON，自动解析出 cookie 和 token
        if trimmedCookie.hasPrefix("{") && trimmedCookie.hasSuffix("}") {
            if let data = trimmedCookie.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let parsedCookie = (json["cookie"] as? String) ?? ""
                let parsedToken = (json["xsec_token"] as? String) ?? ""

                self.cookie = parsedCookie
                self.defaultToken = parsedToken.isEmpty ? trimmedToken : parsedToken
                persist()
                return
            }
        }

        self.cookie = trimmedCookie
        self.defaultToken = trimmedToken
        persist()
    }

    /// 清空鉴权信息
    func clearAuth() {
        self.cookie = ""
        self.defaultToken = ""
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(self.cookie, forKey: userDefaultsKeyCookie)
        UserDefaults.standard.set(self.defaultToken, forKey: userDefaultsKeyToken)
        syncToDisk()
    }

    /// 同步写入磁盘 JSON 文件，供 Python 独立脚本直接读取
    private func syncToDisk() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let forgeDir = appSupport.appendingPathComponent("cduyzhMediaForge", isDirectory: true)

        try? FileManager.default.createDirectory(at: forgeDir, withIntermediateDirectories: true)
        let fileURL = forgeDir.appendingPathComponent("xhs_auth.json")

        let dict: [String: Any] = [
            "cookie": self.cookie,
            "xsec_token": self.defaultToken,
            "updated_at": Date().timeIntervalSince1970
        ]

        if let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted) {
            try? data.write(to: fileURL)
        }
    }

    /// 兼容别名
    func updateAuth(cookie: String, token: String) {
        saveAuth(cookie: cookie, defaultToken: token)
    }

    /// 供控制台复制 Cookie
    static let jsExportScriptCookie: String = "copy(document.cookie); alert('✅ 小红书 Cookie 已复制到剪贴板！');"

    /// 供控制台复制 Token
    static let jsExportScriptToken: String = """
    (function(){
        const m = window.location.href.match(/xsec_token=([^&]+)/);
        if (m) {
            copy(decodeURIComponent(m[1]));
            alert('✅ xsec_token 已复制到剪贴板！');
        } else {
            alert('当前页面 URL 未包含 xsec_token');
        }
    })();
    """

    // MARK: - 供用户在浏览器导出的 JS 脚本
    /// 控制台提取脚本 (一键复制到剪贴板)
    static let consoleExportScript: String = """
(function(){
    try {
        const c = document.cookie;
        const u = window.location.href;
        const m = u.match(/xsec_token=([^&]+)/);
        const t = m ? decodeURIComponent(m[1]) : "";
        const data = { cookie: c, url: u, xsec_token: t };
        const text = JSON.stringify(data, null, 2);
        if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(text).then(() => {
                alert("✅ 小红书鉴权信息已成功复制到剪贴板！\\n请返回 MediaSaver 粘贴即可。");
            }).catch(() => { prompt("请全选复制以下鉴权信息：", text); });
        } else {
            prompt("请全选复制以下鉴权信息：", text);
        }
    } catch(e) {
        alert("提取失败：" + e.message);
    }
})();
"""

    /// 书签小工具 (Bookmarklet)
    static var bookmarkletScript: String {
        let compacted = consoleExportScript
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
        return "javascript:" + compacted
    }

    /// 仅提取 Cookie 的极简脚本
    static let simpleCookieScript: String = """
copy(document.cookie); alert("✅ 小红书 Cookie 已复制到剪贴板！");
"""
}
