import Foundation
import Darwin

// MARK: - 小红书视频元数据模型
public struct XHSPostInfo: Sendable {
    public let url: String
    public let noteId: String?
    public let title: String
    public let author: String
    public let coverUrl: String?
    public let videoUrl: String?
}

// MARK: - 网络视频通用下载器 (支持小红书、X/Twitter 及其他网络平台)
class NetworkVideoDownloader {

    enum DownloadError: LocalizedError {
        case invalidURL
        case scriptNotFound
        case downloadFailed(Int32, String)
        case executionError(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "无效的链接格式，请输入有效的小红书或推文视频链接"
            case .scriptNotFound:
                return "未找到小红书解析脚本 (xhs_downloader.py)"
            case .downloadFailed(let code, let msg):
                return "视频下载失败 (状态码: \(code))：\(msg.isEmpty ? "请检查链接是否为公开有效的视频内容" : msg)"
            case .executionError(let msg):
                return "执行出错: \(msg)"
            }
        }
    }

    /// 从输入文本中提取所有有效 URL 列表（支持多行、空格分隔或混合文案）
    static func extractAllURLs(from text: String) -> [String] {
        PlatformCategory.extractURLs(from: text)
    }

    /// 检测是否为小红书链接
    static func isXiaohongshuURL(_ url: String) -> Bool {
        PlatformCategory.detect(from: url) == .xhs
    }

    /// 检测是否为 Twitter / X 链接
    static func isTwitterURL(_ url: String) -> Bool {
        PlatformCategory.detect(from: url) == .twitter
    }

    /// 检测是否为哔哩哔哩链接
    static func isBilibiliURL(_ url: String) -> Bool {
        PlatformCategory.detect(from: url) == .bilibili
    }

    /// Twitter / X 专属全套发帖人视频与文章下载接口（支持多视频识别与 Markdown 导出，支持预解析直连）
    static func downloadTwitterAll(
        url: String,
        outputDir: URL? = nil,
        videoOutputDir: URL? = nil,
        markdownOutputDir: URL? = nil,
        exportMarkdown: Bool = true,
        shouldRemoveWatermark: Bool = true,
        preParsedInfo: TwitterPostInfo? = nil,
        progressHandler: @escaping (String) -> Void
    ) async throws -> TwitterDownloadResult {
        let result = try await TwitterDownloader.downloadAllVideos(
            url: url,
            outputDir: outputDir,
            videoOutputDir: videoOutputDir,
            markdownOutputDir: markdownOutputDir,
            exportMarkdown: exportMarkdown,
            preParsedInfo: preParsedInfo,
            progressHandler: progressHandler
        )
        
        // 视频去水印处理
        if shouldRemoveWatermark && AppSettings.shared.removeWatermark {
            for videoURL in result.videoURLs {
                let delogoName = "delogo_" + videoURL.lastPathComponent
                let delogoURL = videoURL.deletingLastPathComponent().appendingPathComponent(delogoName)
                WorkExecutionManager.shared.registerActiveFile(delogoURL)
                defer {
                    try? FileManager.default.removeItem(at: delogoURL)
                    WorkExecutionManager.shared.unregisterActiveFile(delogoURL)
                }
                let success = await VideoWatermarkRemover.removeWatermark(
                    inputURL: videoURL,
                    outputURL: delogoURL,
                    trimEnding: AppSettings.shared.trimEnding,
                    progressHandler: progressHandler
                )
                try Task.checkCancellation()
                if success {
                    try replaceProcessedVideo(delogoURL, original: videoURL)
                }
            }
        }
        
        return result
    }

    /// 统一入口：根据链接自动分流下载（支持传入已预解析数据直接极速下载）
    static func downloadVideo(
        url: String,
        targetDirectory: URL? = nil,
        videoOutputDir: URL? = nil,
        markdownOutputDir: URL? = nil,
        shouldRemoveWatermark: Bool = true,
        preParsedTwitter: TwitterPostInfo? = nil,
        preParsedXHS: XHSPostInfo? = nil,
        preParsedBilibili: BilibiliVideoInfo? = nil,
        progressHandler: @escaping (String) -> Void
    ) async throws -> URL {
        guard let parsedURL = URLComponents(string: url.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = parsedURL.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = parsedURL.host, !host.isEmpty else {
            throw DownloadError.invalidURL
        }

        var downloadedURL: URL
        if isXiaohongshuURL(url) {
            downloadedURL = try await downloadXiaohongshuVideo(
                url: url,
                targetDirectory: targetDirectory ?? videoOutputDir,
                directVideoURL: preParsedXHS?.videoUrl,
                directTitle: preParsedXHS?.title,
                progressHandler: progressHandler
            )
        } else if isBilibiliURL(url) {
            downloadedURL = try await BilibiliDownloader.downloadVideo(
                url: url,
                targetDirectory: targetDirectory ?? videoOutputDir,
                preParsedInfo: preParsedBilibili,
                progressHandler: progressHandler
            )
        } else if isTwitterURL(url) {
            let res = try await downloadTwitterAll(
                url: url,
                outputDir: targetDirectory,
                videoOutputDir: videoOutputDir,
                markdownOutputDir: markdownOutputDir,
                exportMarkdown: true,
                shouldRemoveWatermark: shouldRemoveWatermark,
                preParsedInfo: preParsedTwitter,
                progressHandler: progressHandler
            )
            guard let first = res.primaryVideoURL else {
                throw DownloadError.downloadFailed(-1, "推特帖子下未找到发帖人视频")
            }
            return first
        } else {
            let res = try await TwitterDownloader.downloadAllVideos(
                url: url,
                outputDir: targetDirectory,
                videoOutputDir: videoOutputDir,
                markdownOutputDir: markdownOutputDir,
                exportMarkdown: false,
                preParsedInfo: preParsedTwitter,
                progressHandler: progressHandler
            )
            guard let first = res.primaryVideoURL else {
                throw DownloadError.downloadFailed(-1, "下载未提取到有效视频")
            }
            downloadedURL = first
        }

        // 视频去水印处理（支持小红书与哔哩哔哩等平台，集成硬件加速与多层容错兜底）
        let isXHS = isXiaohongshuURL(url)
        let isBili = isBilibiliURL(url)
        if shouldRemoveWatermark && AppSettings.shared.removeWatermark && (isXHS || isBili) {
            let platform: PlatformCategory = isBili ? .bilibili : .xhs
            let delogoName = "delogo_" + downloadedURL.lastPathComponent
            let delogoURL = downloadedURL.deletingLastPathComponent().appendingPathComponent(delogoName)
            WorkExecutionManager.shared.registerActiveFile(delogoURL)
            defer {
                try? FileManager.default.removeItem(at: delogoURL)
                WorkExecutionManager.shared.unregisterActiveFile(delogoURL)
            }
            let success = await VideoWatermarkRemover.removeWatermark(
                inputURL: downloadedURL,
                outputURL: delogoURL,
                platform: platform,
                trimEnding: platform == .xhs ? AppSettings.shared.trimEnding : false,
                progressHandler: progressHandler
            )
            try Task.checkCancellation()
            if success {
                try replaceProcessedVideo(delogoURL, original: downloadedURL)
            }
        }

        return downloadedURL
    }

    /// 处理文件与原视频位于同目录；rename 在成功前保留原文件，失败时不会先删源视频。
    private static func replaceProcessedVideo(_ processed: URL, original: URL) throws {
        let values = try processed.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? 0) > 0 else {
            throw DownloadError.executionError("去水印未生成有效视频，已保留原始文件")
        }
        let result = processed.path.withCString { source in
            original.path.withCString { destination in Darwin.rename(source, destination) }
        }
        guard result == 0 else {
            throw DownloadError.executionError("无法保存处理后的视频，已保留原始文件：\(String(cString: strerror(errno)))")
        }
    }

    /// 解析小红书视频元数据（标题、作者、封面与直链）
    static func fetchXHSInfo(url: String) async throws -> XHSPostInfo {
        guard let scriptPath = locateXHSDownloaderScript() else {
            throw DownloadError.scriptNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        var args = [
            "python3",
            scriptPath,
            "info",
            url
        ]

        let cookie = XHSAuthManager.shared.cookie.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cookie.isEmpty {
            args.append("--cookie")
            args.append(cookie)
        }
        let token = XHSAuthManager.shared.defaultToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !token.isEmpty {
            args.append("--token")
            args.append(token)
        }

        process.arguments = args
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
                    WorkExecutionManager.shared.unregisterProcess(id: procToken)
                    let output = collector.fullOutput
                    if let startRange = output.range(of: "=== JSON_RESULT_START ==="),
                       let endRange = output.range(of: "=== JSON_RESULT_END ===") {
                        let jsonStr = String(output[startRange.upperBound..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                        if let jsonData = jsonStr.data(using: .utf8),
                           let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                            let title = dict["title"] as? String ?? "小红书精彩视频"
                            let author = dict["author"] as? String ?? "小红书创作者"
                            let coverUrl = dict["cover_url"] as? String
                            let videoUrl = dict["video_url"] as? String
                            let noteId = dict["note_id"] as? String
                            let info = XHSPostInfo(
                                url: url,
                                noteId: noteId,
                                title: title,
                                author: author,
                                coverUrl: coverUrl,
                                videoUrl: videoUrl
                            )
                            continuation.resume(returning: info)
                            return
                        }
                    }
                    continuation.resume(throwing: DownloadError.downloadFailed(proc.terminationStatus, "未能获取小红书视频信息"))
                }
            } catch {
                WorkExecutionManager.shared.unregisterProcess(id: procToken)
                continuation.resume(throwing: DownloadError.executionError(error.localizedDescription))
            }
        }
    }

    /// 小红书专属下载流（支持预解析直链极速下载）
    static func downloadXiaohongshuVideo(
        url: String,
        targetDirectory: URL? = nil,
        directVideoURL: String? = nil,
        directTitle: String? = nil,
        progressHandler: @escaping (String) -> Void
    ) async throws -> URL {
        guard let scriptPath = locateXHSDownloaderScript() else {
            throw DownloadError.scriptNotFound
        }

        let folder = targetDirectory ?? DownloadCacheManager.shared.currentCacheURL
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: nil)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let shortId = UUID().uuidString.prefix(6)
        let rawFileName = "XHSVideo-\(timestamp)-\(shortId).mp4"

        let (targetURL, shouldSkip) = CategorizedStorageManager.resolveDestination(in: folder, filename: rawFileName)
        let outputPath = targetURL.path

        if shouldSkip {
            progressHandler("本地已存在同名视频，根据设置已跳过下载")
            return targetURL
        }

        WorkExecutionManager.shared.registerActiveFile(targetURL)

        if let dUrl = directVideoURL, !dUrl.isEmpty {
            progressHandler("正在使用预解析直链极速下载…")
        } else {
            progressHandler("正在连接小红书解析通道…")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        var args = [
            "python3",
            scriptPath,
            url,
            outputPath
        ]

        if let dUrl = directVideoURL, !dUrl.isEmpty {
            args.append("--direct-url")
            args.append(dUrl)
        }
        if let dTitle = directTitle, !dTitle.isEmpty {
            args.append("--title")
            args.append(dTitle)
        }

        let cookie = XHSAuthManager.shared.cookie.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cookie.isEmpty {
            args.append("--cookie")
            args.append(cookie)
        }

        let token = XHSAuthManager.shared.defaultToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !token.isEmpty {
            args.append("--token")
            args.append(token)
        }

        process.arguments = args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let procToken = WorkExecutionManager.shared.registerProcess(process)

        return try await withCheckedThrowingContinuation { continuation in
            do {
                try process.run()

                final class OutputBox: @unchecked Sendable {
                    var line: String = ""
                }
                let outputBox = OutputBox()

                let fileHandle = pipe.fileHandleForReading
                fileHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                        let lines = output.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                        if let last = lines.last {
                            outputBox.line = last
                            DispatchQueue.main.async {
                                progressHandler(last)
                            }
                        }
                    }
                }

                process.terminationHandler = { proc in
                    fileHandle.readabilityHandler = nil
                    WorkExecutionManager.shared.unregisterProcess(id: procToken)
                    if proc.terminationStatus == 0 && FileManager.default.fileExists(atPath: outputPath) {
                        WorkExecutionManager.shared.unregisterActiveFile(targetURL)
                        DownloadCacheManager.shared.recordCompletedDownload(sourceURL: url, fileURL: targetURL)
                        continuation.resume(returning: targetURL)
                    } else {
                        continuation.resume(throwing: DownloadError.downloadFailed(proc.terminationStatus, outputBox.line))
                    }
                }

            } catch {
                WorkExecutionManager.shared.unregisterProcess(id: procToken)
                continuation.resume(throwing: DownloadError.executionError(error.localizedDescription))
            }
        }
    }

    /// 定位 xhs_downloader.py 路径
    private static func locateXHSDownloaderScript() -> String? {
        // 1. App Bundle 资源目录
        if let bundlePath = Bundle.main.path(forResource: "xhs_downloader", ofType: "py"),
           FileManager.default.fileExists(atPath: bundlePath) {
            return bundlePath
        }

        let resURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/xhs_downloader.py")
        if FileManager.default.fileExists(atPath: resURL.path) {
            return resURL.path
        }

        // 2. 可执行程序同级或上级目录
        let execDir = Bundle.main.bundleURL.deletingLastPathComponent().path
        let candidate1 = (execDir as NSString).appendingPathComponent("xhs_downloader.py")
        if FileManager.default.fileExists(atPath: candidate1) {
            return candidate1
        }

        // 3. 当前运行工作目录
        let currentDir = FileManager.default.currentDirectoryPath
        let candidate2 = (currentDir as NSString).appendingPathComponent("App/xhs_downloader.py")
        if FileManager.default.fileExists(atPath: candidate2) {
            return candidate2
        }

        let candidate3 = (currentDir as NSString).appendingPathComponent("xhs_downloader.py")
        if FileManager.default.fileExists(atPath: candidate3) {
            return candidate3
        }

        return nil
    }
}
