import Foundation
import AppKit

// MARK: - 媒体分类类型 (四分类体系)
public enum MediaCategory: String, CaseIterable, Identifiable, Sendable {
    case video = "视频"
    case livePhoto = "实况"
    case gif = "GIF"
    case document = "文档"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .video: return "video.fill"
        case .livePhoto: return "livephoto"
        case .gif: return "sparkles"
        case .document: return "doc.text.fill"
        }
    }

    public var description: String {
        switch self {
        case .video: return "下载的原始与去水印视频 (.mp4 / .mov)"
        case .livePhoto: return "生成的实况照片配对文件 (.jpg + .mov / .pvt)"
        case .gif: return "公众号动图与表情包 (.gif)"
        case .document: return "推特长文、合集及笔记 Markdown 摘要 (.md)"
        }
    }
}

// MARK: - 平台来源分类
public enum PlatformCategory: String, CaseIterable, Identifiable, Sendable {
    case xhs = "小红书"
    case twitter = "推特"
    case bilibili = "哔哩哔哩"
    case defaultCategory = "默认"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .xhs: return "note.text"
        case .twitter: return "bird.fill"
        case .bilibili: return "play.tv.fill"
        case .defaultCategory: return "folder.fill"
        }
    }

    /// 根据 URL 智能识别平台
    public static func detect(from urlString: String) -> PlatformCategory {
        if matchesHost(urlString, domains: ["xiaohongshu.com", "xhslink.com", "rednote.com"]) {
            return .xhs
        } else if matchesHost(urlString, domains: ["twitter.com", "x.com"]) {
            return .twitter
        } else if matchesHost(urlString, domains: ["bilibili.com", "b23.tv"]) {
            return .bilibili
        } else {
            return .defaultCategory
        }
    }

    /// 只按 HTTP(S) 主机名识别平台，避免路径、查询参数或相似域名误触发专用下载器。
    public static func matchesHost(_ urlString: String, domains: [String]) -> Bool {
        guard let parts = URLComponents(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = parts.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = parts.host?.lowercased() else { return false }
        return domains.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// 分享文案中的链接和独立 BV 号按原顺序提取；链接内的 BV 号不重复入队。
    public static func extractURLs(from text: String) -> [String] {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let urlRegex = try! NSRegularExpression(pattern: #"https?://[^\s，。！？)）"'>]+"#)
        let bvRegex = try! NSRegularExpression(pattern: #"(?<![A-Za-z0-9])BV[A-Za-z0-9]{10}(?![A-Za-z0-9])"#)
        let urlMatches = urlRegex.matches(in: text, range: range)
        var found = urlMatches.compactMap { match -> (Int, String)? in
            guard let part = Range(match.range, in: text) else { return nil }
            return (match.range.location, String(text[part]))
        }
        for match in bvRegex.matches(in: text, range: range) {
            guard !urlMatches.contains(where: { NSIntersectionRange($0.range, match.range).length > 0 }),
                  let part = Range(match.range, in: text) else { continue }
            found.append((match.range.location, "https://www.bilibili.com/video/" + text[part]))
        }
        var seen = Set<String>()
        return found.sorted { $0.0 < $1.0 }.map(\.1).filter { seen.insert($0).inserted }
    }
}

// MARK: - 结构化分层归类存储管理器
public struct CategorizedStorageManager {

    /// 生成当前日期的中文目录名，例如 "26年10月14日"
    public static func dateFolderName(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yy年M月d日"
        return formatter.string(from: date)
    }

    /// 获取特定平台、指定日期的根目录，例如：`~/Downloads/cduyzhMediaForge/小红书/26年10月14日/`
    public static func platformDateDirectory(
        baseDir: URL = AppSettings.shared.downloadURL,
        platform: PlatformCategory,
        date: Date = Date()
    ) -> URL {
        let dateFolder = dateFolderName(for: date)
        let dir = baseDir
            .appendingPathComponent(platform.rawValue, isDirectory: true)
            .appendingPathComponent(dateFolder, isDirectory: true)
        ensureDirectory(at: dir)
        return dir
    }

    /// 获取特定平台、指定日期、特定媒体类型的分类存储目录
    /// 路径结构：`[根目录]/[平台]/[日期]/[视频|实况|GIF|文档]/`
    /// 例如：`~/Downloads/cduyzhMediaForge/推特/26年10月14日/视频/`
    public static func categoryDirectory(
        baseDir: URL = AppSettings.shared.downloadURL,
        platform: PlatformCategory,
        category: MediaCategory,
        date: Date = Date()
    ) -> URL {
        let basePlatformDate = platformDateDirectory(baseDir: baseDir, platform: platform, date: date)
        let catDir = basePlatformDate.appendingPathComponent(category.rawValue, isDirectory: true)
        ensureDirectory(at: catDir)
        return catDir
    }

    /// 确保目录存在
    public static func ensureDirectory(at url: URL) {
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        }
    }

    /// 在访达中打开某平台当天的根归类目录
    public static func openInFinder(platform: PlatformCategory, date: Date = Date(), baseDir: URL = AppSettings.shared.downloadURL) {
        let dir = platformDateDirectory(baseDir: baseDir, platform: platform, date: date)
        NSWorkspace.shared.activateFileViewerSelecting([dir])
    }

    /// 在访达中打开某特定分类目录
    public static func openCategoryInFinder(platform: PlatformCategory, category: MediaCategory, date: Date = Date(), baseDir: URL = AppSettings.shared.downloadURL) {
        let dir = categoryDirectory(baseDir: baseDir, platform: platform, category: category, date: date)
        NSWorkspace.shared.activateFileViewerSelecting([dir])
    }

    /// 处理同名文件冲突（根据 AppSettings 去重策略）
    /// 返回最终的目标 URL 和是否应该跳过保存
    public static func resolveDestination(
        in directory: URL,
        filename: String,
        policy: DuplicatePolicy = AppSettings.shared.duplicatePolicy
    ) -> (destinationURL: URL, shouldSkip: Bool) {
        let dest = directory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: dest.path) else {
            return (dest, false)
        }

        switch policy {
        case .skip:
            return (dest, true)
        case .overwrite:
            try? FileManager.default.removeItem(at: dest)
            return (dest, false)
        case .rename:
            let ext = (filename as NSString).pathExtension
            let base = (filename as NSString).deletingPathExtension
            var counter = 1
            while true {
                let candidateName = ext.isEmpty ? "\(base)_\(counter)" : "\(base)_\(counter).\(ext)"
                let candidateURL = directory.appendingPathComponent(candidateName)
                if !FileManager.default.fileExists(atPath: candidateURL.path) {
                    return (candidateURL, false)
                }
                counter += 1
            }
        }
    }
}

// MARK: - 异步并发信号量
public actor AsyncSemaphore {
    private var permits: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init(permits: Int) {
        self.permits = max(1, permits)
    }

    public func wait() async {
        if permits > 0 {
            permits -= 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    public func signal() {
        if !waiters.isEmpty {
            let next = waiters.removeFirst()
            next.resume()
        } else {
            permits += 1
        }
    }
}
