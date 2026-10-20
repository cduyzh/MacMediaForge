import Foundation
import SwiftUI
import AppKit

// MARK: - 远端 Release 信息模型
public struct AppReleaseInfo: Codable, Sendable, Identifiable {
    public var id: String { tagName }
    public let tagName: String
    public let name: String?
    public let body: String?
    public let publishedAt: String?
    public let htmlURL: String
    public let dmgAssetURL: String?
    public let zipAssetURL: String?
    public let assetsCount: Int

    public init(
        tagName: String,
        name: String?,
        body: String?,
        publishedAt: String?,
        htmlURL: String,
        dmgAssetURL: String? = nil,
        zipAssetURL: String? = nil,
        assetsCount: Int = 0
    ) {
        self.tagName = tagName
        self.name = name
        self.body = body
        self.publishedAt = publishedAt
        self.htmlURL = htmlURL
        self.dmgAssetURL = dmgAssetURL
        self.zipAssetURL = zipAssetURL
        self.assetsCount = assetsCount
    }

    public var displayTitle: String {
        if let name = name, !name.trimmingCharacters(in: .whitespaces).isEmpty {
            return name
        }
        return tagName
    }

    public var cleanVersion: String {
        tagName.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^[vV]", with: "", options: .regularExpression)
    }
}

// MARK: - 检查更新结果状态
public enum AppUpdateStatus: Equatable {
    case idle
    case checking
    case updateAvailable(AppReleaseInfo)
    case upToDate(version: String)
    case localVersionAhead(version: String, latestRelease: AppReleaseInfo)
    case failed(reason: String)

    public static func == (lhs: AppUpdateStatus, rhs: AppUpdateStatus) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.checking, .checking):
            return true
        case (.upToDate(let v1), .upToDate(let v2)):
            return v1 == v2
        case (.localVersionAhead(let v1, let r1), .localVersionAhead(let v2, let r2)):
            return v1 == v2 && r1.tagName == r2.tagName
        case (.failed(let r1), .failed(let r2)):
            return r1 == r2
        case (.updateAvailable(let i1), .updateAvailable(let i2)):
            return i1.tagName == i2.tagName
        default:
            return false
        }
    }
}

// MARK: - 全局检查更新管理器
@MainActor
public class UpdateChecker: ObservableObject {
    public static let shared = UpdateChecker()

    public nonisolated static let defaultRepo = "cduyzh/LivePhotoForge"
    public nonisolated static let repoReleasesWebURL = "https://github.com/cduyzh/LivePhotoForge/releases"

    @Published public var status: AppUpdateStatus = .idle
    @Published public var latestRelease: AppReleaseInfo? = nil
    @Published public var lastCheckedDate: Date? = nil
    @Published public var isChecking: Bool = false
    @Published public var showUpdateSheet: Bool = false

    private init() {
        if let date = UserDefaults.standard.object(forKey: "lpf_last_update_check_date") as? Date {
            self.lastCheckedDate = date
        }
    }

    /// 获取当前应用版本（例如 "1.9.0"）
    public nonisolated static var currentAppVersion: String {
        AppMetadata.shortVersion ?? "development"
    }

    /// 获取当前应用构建号（例如 "9"）
    public nonisolated static var currentAppBuild: String {
        AppMetadata.build ?? "unknown"
    }

    // MARK: - 语义化版本解析与比对

    /// 将版本字符串（如 "v1.9.0"、"1.10.1"）拆解为整数数组 [1, 9, 0]
    public nonisolated static func parseVersionNumbers(_ versionStr: String) -> [Int] {
        let clean = versionStr.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^[vV]", with: "", options: .regularExpression)
        let mainPart = clean.components(separatedBy: "-").first ?? clean
        return mainPart.components(separatedBy: ".").compactMap { Int($0) }
    }

    /// 判定远端版本是否高于本地版本
    public nonisolated static func isRemoteVersion(_ remoteStr: String, newerThan localStr: String) -> Bool {
        let rNums = parseVersionNumbers(remoteStr)
        let lNums = parseVersionNumbers(localStr)
        let count = max(rNums.count, lNums.count)
        for i in 0..<count {
            let r = i < rNums.count ? rNums[i] : 0
            let l = i < lNums.count ? lNums[i] : 0
            if r > l { return true }
            if r < l { return false }
        }
        return false
    }

    // MARK: - 执行检查更新

    /// 检查是否有新版本可用
    /// 支持三种模式安全回退：
    /// 1. 本机 gh CLI（针对私有仓库，自动复用本地 GitHub 授权）
    /// 2. AppSettings 中配置的自定义 GitHub Personal Access Token
    /// 3. 公开 GitHub Releases API（无 Token 回退）
    public func checkForUpdates(isUserInitiated: Bool = true) async {
        guard !isChecking else { return }
        isChecking = true
        status = .checking

        defer {
            isChecking = false
            let now = Date()
            lastCheckedDate = now
            UserDefaults.standard.set(now, forKey: "lpf_last_update_check_date")
        }

        do {
            let token = AppSettings.shared.githubToken
            let release = try await Self.fetchLatestRelease(customToken: token)
            self.latestRelease = release

            let current = Self.currentAppVersion
            if Self.isRemoteVersion(release.tagName, newerThan: current) {
                status = .updateAvailable(release)
                if isUserInitiated {
                    showUpdateSheet = true
                }
            } else if Self.isRemoteVersion(current, newerThan: release.tagName) {
                status = .localVersionAhead(version: current, latestRelease: release)
            } else {
                status = .upToDate(version: current)
            }
        } catch {
            let errDesc = error.localizedDescription
            status = .failed(reason: errDesc)
        }
    }

    // MARK: - 远端数据拉取

    public nonisolated static func fetchLatestRelease(customToken: String? = nil) async throws -> AppReleaseInfo {
        // 策略 1: 如果本机安装了 gh 命令行且登录了账号，直接调用 gh CLI（支持私有仓库）
        if let release = try? await fetchViaGhCLI() {
            return release
        }

        // 策略 2: 使用 URLSession 通过 REST API 获取（带 Token 或公开访问）
        return try await fetchViaHTTP(customToken: customToken)
    }

    /// 通过本地 gh 命令行读取 release（对私有仓库最可靠）
    public nonisolated static func fetchViaGhCLI() async throws -> AppReleaseInfo {
        let candidatePaths = [
            "/opt/homebrew/bin/gh",
            "/usr/local/bin/gh",
            "/usr/bin/gh"
        ]

        guard let ghBin = candidatePaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw NSError(domain: "UpdateChecker", code: 404, userInfo: [NSLocalizedDescriptionKey: "未找到 gh 命令行"])
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: ghBin)
                process.arguments = [
                    "release", "view",
                    "--repo", Self.defaultRepo,
                    "--json", "tagName,name,body,publishedAt,url,assets"
                ]

                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    if process.terminationStatus == 0 {
                        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let tagName = json["tagName"] as? String,
                           let url = json["url"] as? String {

                            let name = json["name"] as? String
                            let body = json["body"] as? String
                            let publishedAt = json["publishedAt"] as? String

                            var dmgURL: String? = nil
                            var zipURL: String? = nil
                            var assetCount = 0

                            if let assets = json["assets"] as? [[String: Any]] {
                                assetCount = assets.count
                                for asset in assets {
                                    if let aName = asset["name"] as? String, let aUrl = asset["url"] as? String {
                                        if aName.hasSuffix(".dmg") && dmgURL == nil { dmgURL = aUrl }
                                        if aName.hasSuffix(".zip") && zipURL == nil { zipURL = aUrl }
                                    }
                                }
                            }

                            let info = AppReleaseInfo(
                                tagName: tagName,
                                name: name,
                                body: body,
                                publishedAt: publishedAt,
                                htmlURL: url,
                                dmgAssetURL: dmgURL,
                                zipAssetURL: zipURL,
                                assetsCount: assetCount
                            )
                            continuation.resume(returning: info)
                            return
                        }
                    }

                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    let errMsg = String(data: errData, encoding: .utf8) ?? "gh 命令执行异常"
                    continuation.resume(throwing: NSError(domain: "UpdateChecker", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: errMsg]))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// 通过 GitHub HTTP REST API 拉取
    public nonisolated static func fetchViaHTTP(customToken: String? = nil) async throws -> AppReleaseInfo {
        let endpoint = "https://api.github.com/repos/\(Self.defaultRepo)/releases/latest"
        guard let url = URL(string: endpoint) else {
            throw NSError(domain: "UpdateChecker", code: 400, userInfo: [NSLocalizedDescriptionKey: "无效的更新地址"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("cduyzhMediaForge/\(Self.currentAppVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 12.0

        // 注入配置的 GitHub Token 或环境变量 Token
        let token = (customToken ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let envToken = ProcessInfo.processInfo.environment["GITHUB_TOKEN"] ?? ProcessInfo.processInfo.environment["GH_TOKEN"]
        let effectiveToken = !token.isEmpty ? token : envToken

        if let auth = effectiveToken, !auth.isEmpty {
            request.setValue("Bearer \(auth)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "UpdateChecker", code: 500, userInfo: [NSLocalizedDescriptionKey: "网络通信错误"])
        }

        if httpResponse.statusCode == 404 {
            throw NSError(domain: "UpdateChecker", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "未能读取版本信息（仓库可能为私有，请在偏好设置配置 GitHub Token 或在本机登录 gh 工具）"
            ])
        }

        guard httpResponse.statusCode == 200 else {
            throw NSError(domain: "UpdateChecker", code: httpResponse.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "GitHub API 响应失败 (HTTP \(httpResponse.statusCode))"
            ])
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tagName = json["tag_name"] as? String,
              let htmlURL = json["html_url"] as? String else {
            throw NSError(domain: "UpdateChecker", code: 500, userInfo: [NSLocalizedDescriptionKey: "未能解析版本元数据"])
        }

        let name = json["name"] as? String
        let body = json["body"] as? String
        let publishedAt = json["published_at"] as? String

        var dmgURL: String? = nil
        var zipURL: String? = nil
        var assetCount = 0

        if let assets = json["assets"] as? [[String: Any]] {
            assetCount = assets.count
            for asset in assets {
                if let aName = asset["name"] as? String, let aUrl = asset["browser_download_url"] as? String {
                    if aName.hasSuffix(".dmg") && dmgURL == nil { dmgURL = aUrl }
                    if aName.hasSuffix(".zip") && zipURL == nil { zipURL = aUrl }
                }
            }
        }

        return AppReleaseInfo(
            tagName: tagName,
            name: name,
            body: body,
            publishedAt: publishedAt,
            htmlURL: htmlURL,
            dmgAssetURL: dmgURL,
            zipAssetURL: zipURL,
            assetsCount: assetCount
        )
    }

    /// 在默认浏览器中打开指定 Release 网页或仓库 Releases 页面
    public func openReleaseWebPage(url: String? = nil) {
        let target = url ?? Self.repoReleasesWebURL
        if let u = URL(string: target) {
            NSWorkspace.shared.open(u)
        }
    }

    /// 在浏览器中直接下载 DMG
    public func downloadDMG(url: String?) {
        guard let urlStr = url, let u = URL(string: urlStr) else { return }
        NSWorkspace.shared.open(u)
    }
}
