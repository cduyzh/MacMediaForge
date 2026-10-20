import Foundation

// MARK: - Twitter 视频子项目与元数据模型
public struct TwitterVideoItem: Identifiable, Sendable {
    public var id: String { mediaId }
    public let mediaId: String
    public let url: String
    public let title: String
    public let quality: String
    public let selectedQuality: String
    public let variants: [String: String]
    public let availableQualities: [String]
    public let tweetId: String?
    public let tweetUrl: String
    public let tweetText: String
    public let thumbnailUrl: String?
    public let index: Int

    public init(
        mediaId: String,
        url: String,
        title: String,
        quality: String,
        selectedQuality: String = "1080p",
        variants: [String: String] = [:],
        availableQualities: [String] = ["1080p", "720p", "480p", "360p"],
        tweetId: String?,
        tweetUrl: String,
        tweetText: String,
        thumbnailUrl: String?,
        index: Int
    ) {
        self.mediaId = mediaId
        self.url = url
        self.title = title
        self.quality = quality
        self.selectedQuality = selectedQuality
        self.variants = variants
        self.availableQualities = availableQualities
        self.tweetId = tweetId
        self.tweetUrl = tweetUrl
        self.tweetText = tweetText
        self.thumbnailUrl = thumbnailUrl
        self.index = index
    }
}

public struct TwitterPostInfo: Sendable {
    public let url: String
    public let tweetId: String?
    public let authorUsername: String?
    public let authorName: String?
    public let isArticle: Bool
    public let articleTitle: String?
    public let articleMarkdown: String?
    public let rootText: String
    public let coverUrl: String?
    public let videos: [TwitterVideoItem]

    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "url": url,
            "tweet_id": tweetId ?? "",
            "author_username": authorUsername ?? "",
            "author_name": authorName ?? "",
            "is_article": isArticle,
            "root_text": rootText
        ]
        if let articleTitle = articleTitle { dict["article_title"] = articleTitle }
        if let articleMarkdown = articleMarkdown { dict["article_markdown"] = articleMarkdown }
        if let coverUrl = coverUrl { dict["cover_url"] = coverUrl }

        let vList: [[String: Any]] = videos.map { v in
            var vd: [String: Any] = [
                "media_id": v.mediaId,
                "url": v.url,
                "title": v.title,
                "quality": v.quality,
                "selected_quality": v.selectedQuality,
                "variants": v.variants,
                "available_qualities": v.availableQualities,
                "tweet_url": v.tweetUrl,
                "tweet_text": v.tweetText,
                "index": v.index
            ]
            if let tId = v.tweetId { vd["tweet_id"] = tId }
            if let thumb = v.thumbnailUrl { vd["thumbnail_url"] = thumb }
            return vd
        }
        dict["videos"] = vList
        return dict
    }
}

public struct TwitterDownloadResult: Sendable {
    public let videoURLs: [URL]
    public let markdownURL: URL?
    public let title: String
    public let isArticle: Bool
    public let totalVideos: Int
    public let qualityWarnings: [String]

    public init(videoURLs: [URL], markdownURL: URL?, title: String, isArticle: Bool, totalVideos: Int, qualityWarnings: [String] = []) {
        self.videoURLs = videoURLs
        self.markdownURL = markdownURL
        self.title = title
        self.isArticle = isArticle
        self.totalVideos = totalVideos
        self.qualityWarnings = qualityWarnings
    }
    
    public var primaryVideoURL: URL? {
        videoURLs.first
    }
}

// MARK: - Twitter 全功能高可用下载器
class TwitterDownloader {
    
    enum DownloadError: LocalizedError {
        case invalidURL
        case scriptNotFound
        case executionError(String)
        case parseError(String)
        case downloadFailed(Int32, String)
        
        var errorDescription: String? {
            switch self {
            case .invalidURL: return "无效的推特链接格式"
            case .scriptNotFound: return "未找到推特解析引擎脚本 (twitter_downloader.py)"
            case .executionError(let msg): return "执行出错: \(msg)"
            case .parseError(let msg): return "解析推特数据失败: \(msg)"
            case .downloadFailed(let code, let msg): return "下载失败 (状态码: \(code)): \(msg)"
            }
        }
    }
    
    /// 定位 twitter_downloader.py 路径
    static func locateTwitterDownloaderScript() -> String? {
        // 1. App Bundle 资源目录
        if let bundlePath = Bundle.main.path(forResource: "twitter_downloader", ofType: "py"),
           FileManager.default.fileExists(atPath: bundlePath) {
            return bundlePath
        }
        
        let resURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/twitter_downloader.py")
        if FileManager.default.fileExists(atPath: resURL.path) {
            return resURL.path
        }
        
        // 2. 可执行程序同级或上级目录
        let execDir = Bundle.main.bundleURL.deletingLastPathComponent().path
        let candidate1 = (execDir as NSString).appendingPathComponent("twitter_downloader.py")
        if FileManager.default.fileExists(atPath: candidate1) {
            return candidate1
        }
        
        // 3. 当前运行工作目录
        let currentDir = FileManager.default.currentDirectoryPath
        let candidate2 = (currentDir as NSString).appendingPathComponent("App/twitter_downloader.py")
        if FileManager.default.fileExists(atPath: candidate2) {
            return candidate2
        }
        
        let candidate3 = (currentDir as NSString).appendingPathComponent("twitter_downloader.py")
        if FileManager.default.fileExists(atPath: candidate3) {
            return candidate3
        }
        
        return nil
    }
    
    /// 解析推特帖子信息（包括发帖人全部视频列表、长文文章数据与 Markdown）
    static func fetchPostInfo(url: String, quality: VideoQualityOption = .p1080) async throws -> TwitterPostInfo {
        guard let scriptPath = locateTwitterDownloaderScript() else {
            throw DownloadError.scriptNotFound
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", scriptPath, "info", url, "--quality", quality.rawValue]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        let procToken = WorkExecutionManager.shared.registerProcess(process)
        
        return try await withCheckedThrowingContinuation { continuation in
            do {
                try process.run()
                
                final class OutputCollector: @unchecked Sendable {
                    var fullOutput = ""
                }
                let collector = OutputCollector()
                
                let fileHandle = pipe.fileHandleForReading
                fileHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    if let str = String(data: data, encoding: .utf8) {
                        collector.fullOutput += str
                    }
                }
                
                process.terminationHandler = { proc in
                    fileHandle.readabilityHandler = nil
                    let remaining = fileHandle.readDataToEndOfFile()
                    if let remStr = String(data: remaining, encoding: .utf8) {
                        collector.fullOutput += remStr
                    }
                    WorkExecutionManager.shared.unregisterProcess(id: procToken)
                    let output = collector.fullOutput
                    if proc.terminationStatus == 0 {
                        if let startRange = output.range(of: "=== JSON_RESULT_START ==="),
                           let endRange = output.range(of: "=== JSON_RESULT_END ===") {
                            let jsonStr = String(output[startRange.upperBound..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                            if let jsonData = jsonStr.data(using: .utf8),
                               let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                                
                                let authorUsername = dict["author_username"] as? String
                                let authorName = dict["author_name"] as? String
                                let isArticle = dict["is_article"] as? Bool ?? false
                                let articleTitle = dict["article_title"] as? String
                                let articleMarkdown = dict["article_markdown"] as? String
                                let rootText = dict["root_text"] as? String ?? ""
                                let tweetId = dict["tweet_id"] as? String
                                let coverUrl = dict["cover_url"] as? String
                                
                                var videoItems: [TwitterVideoItem] = []
                                if let videosRaw = dict["videos"] as? [[String: Any]] {
                                    for v in videosRaw {
                                        let mediaId = v["media_id"] as? String ?? UUID().uuidString
                                        let vUrl = v["url"] as? String ?? ""
                                        let title = v["title"] as? String ?? "video"
                                        let quality = v["quality"] as? String ?? "原画"
                                        let selQ = v["selected_quality"] as? String ?? quality
                                        let variants = v["variants"] as? [String: String] ?? [:]
                                        let availQ = v["available_qualities"] as? [String] ?? ["1080p", "720p", "480p", "360p"]
                                        let vTweetId = v["tweet_id"] as? String
                                        let vTweetUrl = v["tweet_url"] as? String ?? url
                                        let vTweetText = v["tweet_text"] as? String ?? ""
                                        let vThumb = v["thumbnail_url"] as? String
                                        let vIndex = v["index"] as? Int ?? (videoItems.count + 1)
                                        
                                        videoItems.append(TwitterVideoItem(
                                            mediaId: mediaId,
                                            url: vUrl,
                                            title: title,
                                            quality: quality,
                                            selectedQuality: selQ,
                                            variants: variants,
                                            availableQualities: availQ,
                                            tweetId: vTweetId,
                                            tweetUrl: vTweetUrl,
                                            tweetText: vTweetText,
                                            thumbnailUrl: vThumb,
                                            index: vIndex
                                        ))
                                    }
                                }
                                
                                let postInfo = TwitterPostInfo(
                                    url: url,
                                    tweetId: tweetId,
                                    authorUsername: authorUsername,
                                    authorName: authorName,
                                    isArticle: isArticle,
                                    articleTitle: articleTitle,
                                    articleMarkdown: articleMarkdown,
                                    rootText: rootText,
                                    coverUrl: coverUrl,
                                    videos: videoItems
                                )
                                continuation.resume(returning: postInfo)
                                return
                            }
                        }
                        continuation.resume(throwing: DownloadError.parseError("无法解析推特元数据 JSON"))
                    } else {
                        continuation.resume(throwing: DownloadError.downloadFailed(proc.terminationStatus, output))
                    }
                }
            } catch {
                WorkExecutionManager.shared.unregisterProcess(id: procToken)
                continuation.resume(throwing: DownloadError.executionError(error.localizedDescription))
            }
        }
    }
    
    /// 下载推特发帖人的全部视频并支持同步导出 Markdown 摘要至专属文档子目录
    static func downloadAllVideos(
        url: String,
        outputDir: URL? = nil,
        videoOutputDir: URL? = nil,
        markdownOutputDir: URL? = nil,
        exportMarkdown: Bool = true,
        quality: VideoQualityOption = .p1080,
        preParsedInfo: TwitterPostInfo? = nil,
        progressHandler: @escaping (String) -> Void
    ) async throws -> TwitterDownloadResult {
        guard let scriptPath = locateTwitterDownloaderScript() else {
            throw DownloadError.scriptNotFound
        }
        
        let targetDir = outputDir ?? AppSettings.shared.downloadURL
        let targetVideoDir = videoOutputDir ?? targetDir
        let targetMdDir = markdownOutputDir ?? targetDir
        
        try? FileManager.default.createDirectory(at: targetVideoDir, withIntermediateDirectories: true, attributes: nil)
        if exportMarkdown {
            try? FileManager.default.createDirectory(at: targetMdDir, withIntermediateDirectories: true, attributes: nil)
        }
        
        var args = [
            scriptPath,
            "download",
            url,
            targetDir.path,
            "--video-dir",
            targetVideoDir.path,
            "--md-dir",
            targetMdDir.path,
            "--quality",
            quality.rawValue
        ]
        if exportMarkdown {
            args.append("--export-md")
        } else {
            args.append("--no-export-md")
        }
        
        var tempJsonPath: String? = nil
        if let info = preParsedInfo {
            let tempJsonURL = DownloadCacheManager.shared.appTempDirectoryURL.appendingPathComponent("preparsed-\(UUID().uuidString).json")
            if let data = try? JSONSerialization.data(withJSONObject: info.toDictionary(), options: []) {
                try? data.write(to: tempJsonURL)
                args.append("--preparsed")
                args.append(tempJsonURL.path)
                tempJsonPath = tempJsonURL.path
            }
        }
        
        defer {
            if let p = tempJsonPath {
                try? FileManager.default.removeItem(atPath: p)
            }
        }
        
        progressHandler("正在连接推特全套视频解析与下载通道…")
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3"] + args
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        let procToken = WorkExecutionManager.shared.registerProcess(process)
        
        return try await withCheckedThrowingContinuation { continuation in
            do {
                try process.run()
                
                final class OutputCollector: @unchecked Sendable {
                    var fullOutput = ""
                    var lastLine = ""
                }
                let collector = OutputCollector()
                
                let fileHandle = pipe.fileHandleForReading
                fileHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                        collector.fullOutput += output
                        let lines = output.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                        if let last = lines.last {
                            collector.lastLine = last
                            DispatchQueue.main.async {
                                progressHandler(last)
                            }
                        }
                    }
                }
                
                process.terminationHandler = { proc in
                    fileHandle.readabilityHandler = nil
                    let remaining = fileHandle.readDataToEndOfFile()
                    if let remStr = String(data: remaining, encoding: .utf8) {
                        collector.fullOutput += remStr
                    }
                    WorkExecutionManager.shared.unregisterProcess(id: procToken)
                    let output = collector.fullOutput
                    if proc.terminationStatus == 0 {
                        var videoFiles: [URL] = []
                        var mdURL: URL? = nil
                        var title = "推特视频合集"
                        var isArticle = false
                        var totalVideos = 0
                        
                        if let startRange = output.range(of: "=== JSON_SUMMARY_START ==="),
                           let endRange = output.range(of: "=== JSON_SUMMARY_END ===") {
                            let jsonStr = String(output[startRange.upperBound..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                            if let jsonData = jsonStr.data(using: .utf8),
                               let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                                
                                if let files = dict["downloaded_files"] as? [String] {
                                    for f in files {
                                        let u = URL(fileURLWithPath: f)
                                        if FileManager.default.fileExists(atPath: u.path) {
                                            videoFiles.append(u)
                                            DownloadCacheManager.shared.recordCompletedDownload(sourceURL: url, fileURL: u)
                                        }
                                    }
                                }
                                if let mdPath = dict["markdown_file"] as? String, !mdPath.isEmpty {
                                    let u = URL(fileURLWithPath: mdPath)
                                    if FileManager.default.fileExists(atPath: u.path) {
                                        mdURL = u
                                    }
                                }
                                title = dict["title"] as? String ?? title
                                isArticle = dict["is_article"] as? Bool ?? false
                                totalVideos = dict["total_videos"] as? Int ?? videoFiles.count
                            }
                        }
                        
                        // 兜底扫描：若 JSON 没有解析到，直接在目标目录扫描近期创建的文件
                        if videoFiles.isEmpty {
                            if let files = try? FileManager.default.contentsOfDirectory(at: targetDir, includingPropertiesForKeys: [.contentModificationDateKey]) {
                                for f in files where f.pathExtension.lowercased() == "mp4" {
                                    videoFiles.append(f)
                                }
                            }
                        }
                        
                        let result = TwitterDownloadResult(
                            videoURLs: videoFiles,
                            markdownURL: mdURL,
                            title: title,
                            isArticle: isArticle,
                            totalVideos: totalVideos
                        )
                        continuation.resume(returning: result)
                    } else {
                        continuation.resume(throwing: DownloadError.downloadFailed(proc.terminationStatus, collector.lastLine))
                    }
                }
            } catch {
                WorkExecutionManager.shared.unregisterProcess(id: procToken)
                continuation.resume(throwing: DownloadError.executionError(error.localizedDescription))
            }
        }
    }
    
    /// 单视频兼容接口（供通用调用方直接复用）
    static func downloadVideo(url: String, progressHandler: @escaping (String) -> Void) async throws -> URL {
        guard URL(string: url) != nil else {
            throw DownloadError.invalidURL
        }
        
        let result = try await downloadAllVideos(url: url, exportMarkdown: true, progressHandler: progressHandler)
        guard let first = result.primaryVideoURL else {
            throw DownloadError.downloadFailed(-1, "未在推特帖子中提取到有效视频")
        }
        return first
    }
}
