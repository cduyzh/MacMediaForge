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
    public let selectedQuality: VideoQualityOption
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

    /// Twitter / X 专属全套发帖人视频与文章下载接口（支持多视频识别与 Markdown 导出，支持预解析直连与清晰度选择）
    static func downloadTwitterAll(
        url: String,
        outputDir: URL? = nil,
        videoOutputDir: URL? = nil,
        markdownOutputDir: URL? = nil,
        exportMarkdown: Bool = true,
        shouldRemoveWatermark: Bool = true,
        quality: VideoQualityOption = .p1080,
        preParsedInfo: TwitterPostInfo? = nil,
        progressHandler: @escaping (String) -> Void
    ) async throws -> TwitterDownloadResult {
        let result = try await TwitterDownloader.downloadAllVideos(
            url: url,
            outputDir: outputDir,
            videoOutputDir: videoOutputDir,
            markdownOutputDir: markdownOutputDir,
            exportMarkdown: exportMarkdown,
            quality: quality,
            preParsedInfo: preParsedInfo,
            progressHandler: progressHandler
        )
        
        // 视频画质与清晰度规整（上限严格限制为 1080P）
        var qualityWarnings: [String] = []
        var qualityFailures = Set<URL>()
        for videoURL in result.videoURLs {
            do {
                try await enforceQualityConstraint(videoURL: videoURL, quality: quality, progressHandler: progressHandler)
            } catch {
                qualityFailures.insert(videoURL)
                qualityWarnings.append("\(videoURL.lastPathComponent)：\(error.localizedDescription)")
            }
        }

        // 视频去水印处理
        if shouldRemoveWatermark && AppSettings.shared.removeWatermark {
            for videoURL in result.videoURLs where !qualityFailures.contains(videoURL) {
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
        
        return TwitterDownloadResult(
            videoURLs: result.videoURLs,
            markdownURL: result.markdownURL,
            title: result.title,
            isArticle: result.isArticle,
            totalVideos: result.totalVideos,
            qualityWarnings: qualityWarnings
        )
    }

    /// 统一入口：根据链接自动分流下载（支持传入已预解析数据直接极速下载，支持多清晰度选择）
    static func downloadVideo(
        url: String,
        targetDirectory: URL? = nil,
        videoOutputDir: URL? = nil,
        markdownOutputDir: URL? = nil,
        shouldRemoveWatermark: Bool = true,
        quality: VideoQualityOption = .p1080,
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
                directVideoURL: preParsedXHS?.selectedQuality == quality ? preParsedXHS?.videoUrl : nil,
                directTitle: preParsedXHS?.title,
                quality: quality,
                progressHandler: progressHandler
            )
        } else if isBilibiliURL(url) {
            downloadedURL = try await BilibiliDownloader.downloadVideo(
                url: url,
                targetDirectory: targetDirectory ?? videoOutputDir,
                quality: quality,
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
                quality: quality,
                preParsedInfo: preParsedTwitter,
                progressHandler: progressHandler
            )
            guard let first = res.primaryVideoURL else {
                throw DownloadError.downloadFailed(-1, "推特帖子下未找到发帖人视频")
            }
            if !res.qualityWarnings.isEmpty {
                throw DownloadError.executionError(res.qualityWarnings.joined(separator: "；"))
            }
            return first
        } else {
            let res = try await TwitterDownloader.downloadAllVideos(
                url: url,
                outputDir: targetDirectory,
                videoOutputDir: videoOutputDir,
                markdownOutputDir: markdownOutputDir,
                exportMarkdown: false,
                quality: quality,
                preParsedInfo: preParsedTwitter,
                progressHandler: progressHandler
            )
            guard let first = res.primaryVideoURL else {
                throw DownloadError.downloadFailed(-1, "下载未提取到有效视频")
            }
            if !res.qualityWarnings.isEmpty {
                throw DownloadError.executionError(res.qualityWarnings.joined(separator: "；"))
            }
            downloadedURL = first
        }

        // 严格执行清晰度规格与 1080P 上限校验
        downloadedURL = try await enforceQualityConstraint(videoURL: downloadedURL, quality: quality, progressHandler: progressHandler)

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

    /// 确保视频分辨率严格满足用户选择的清晰度规格，并且 1080P 为全系统最大画质上限
    /// 如果视频原生已小于或等于目标清晰度，直接返回原文件（0 转码开销，保持无损）
    /// 如果视频超出目标清晰度或超出 1080P 上限（如 4K/2K），利用系统硬件加速 (VideoToolbox) 平滑缩放至目标分辨率
    @discardableResult
    static func enforceQualityConstraint(
        videoURL: URL,
        quality: VideoQualityOption,
        progressHandler: @escaping (String) -> Void
    ) async throws -> URL {
        guard FileManager.default.fileExists(atPath: videoURL.path) else { return videoURL }

        // 获取视频真实分辨率
        guard let (width, height) = await VideoWatermarkRemover.getVideoDimensions(url: videoURL) else {
            throw DownloadError.executionError("无法读取下载视频的分辨率，无法确认是否符合所选清晰度。原视频已保留。")
        }

        let maxShort = quality.maxDimension
        let maxLong = quality.maxLongDimension

        let currentShort = min(width, height)
        let currentLong = max(width, height)

        // 若分辨率未超过所选规格（且未超过 1080p 上限），无需转码缩放
        if currentShort <= maxShort && currentLong <= maxLong {
            return videoURL
        }

        // 计算等比例缩放后的尺寸（保证宽高均为偶数，符合 H.264 规范）
        let scaleFactor = min(Double(maxLong) / Double(currentLong), Double(maxShort) / Double(currentShort))
        var targetW = Int(round(Double(width) * scaleFactor / 2.0)) * 2
        var targetH = Int(round(Double(height) * scaleFactor / 2.0)) * 2
        targetW = max(2, targetW)
        targetH = max(2, targetH)

        progressHandler("📐 调整视频清晰度至 \(quality.shortLabel) (\(targetW)x\(targetH))…")

        guard let ffmpeg = VideoWatermarkRemover.locateTool(name: "ffmpeg") else {
            throw DownloadError.executionError("调整到所选清晰度需要 FFmpeg。原视频已保留；安装 FFmpeg 后可重试。")
        }

        let tempURL = videoURL.deletingLastPathComponent().appendingPathComponent("tmp_scaled_\(UUID().uuidString).mp4")
        WorkExecutionManager.shared.registerActiveFile(tempURL)
        defer {
            WorkExecutionManager.shared.unregisterActiveFile(tempURL)
            if FileManager.default.fileExists(atPath: tempURL.path) {
                try? FileManager.default.removeItem(at: tempURL)
            }
        }

        let bitrate = VideoWatermarkRemover.estimateBitrate(width: targetW, height: targetH)

        // 尝试 Tier 1: VideoToolbox
        let tier1Args = [
            "-nostdin", "-y",
            "-i", videoURL.path,
            "-vf", "scale=\(targetW):\(targetH)",
            "-c:v", "h264_videotoolbox",
            "-b:v", "\(bitrate)k",
            "-c:a", "copy",
            "-movflags", "+faststart",
            tempURL.path
        ]

        var success = false
        let p1 = Process()
        p1.executableURL = URL(fileURLWithPath: ffmpeg)
        p1.arguments = tier1Args
        let token1 = WorkExecutionManager.shared.registerProcess(p1)
        do {
            try p1.run()
            p1.waitUntilExit()
            WorkExecutionManager.shared.unregisterProcess(id: token1)
            if p1.terminationStatus == 0 && VideoWatermarkRemover.validateOutputFile(url: tempURL, minExpectedSize: 20000) {
                success = true
            }
        } catch {
            WorkExecutionManager.shared.unregisterProcess(id: token1)
        }

        // 兜底 Tier 2: CPU libx264
        if !success {
            let tier2Args = [
                "-nostdin", "-y",
                "-i", videoURL.path,
                "-vf", "scale=\(targetW):\(targetH)",
                "-c:v", "libx264",
                "-preset", "fast",
                "-crf", "22",
                "-c:a", "copy",
                "-movflags", "+faststart",
                tempURL.path
            ]
            let p2 = Process()
            p2.executableURL = URL(fileURLWithPath: ffmpeg)
            p2.arguments = tier2Args
            let token2 = WorkExecutionManager.shared.registerProcess(p2)
            do {
                try p2.run()
                p2.waitUntilExit()
                WorkExecutionManager.shared.unregisterProcess(id: token2)
                if p2.terminationStatus == 0 && VideoWatermarkRemover.validateOutputFile(url: tempURL, minExpectedSize: 20000) {
                    success = true
                }
            } catch {
                WorkExecutionManager.shared.unregisterProcess(id: token2)
            }
        }

        if success {
            try replaceProcessedVideo(tempURL, original: videoURL)
            progressHandler("✅ 已成功调整画质为 \(quality.shortLabel) (\(targetW)x\(targetH))")
        } else {
            throw DownloadError.executionError("未能将视频调整到 \(quality.shortLabel)。原视频已保留。")
        }

        return videoURL
    }

    /// 解析小红书视频元数据（标题、作者、封面与直链）
    static func fetchXHSInfo(url: String, quality: VideoQualityOption = .p1080) async throws -> XHSPostInfo {
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
        args.append(contentsOf: ["--quality", quality.rawValue])

        process.arguments = args
        // 鉴权信息经环境变量传递 (Python 侧 XHS_COOKIE/XHS_TOKEN 优先级高于配置文件)，避免出现在 argv 中被 ps 观测
        var environment = ProcessInfo.processInfo.environment
        let cookie = XHSAuthManager.shared.cookie.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cookie.isEmpty {
            environment["XHS_COOKIE"] = cookie
        }
        let token = XHSAuthManager.shared.defaultToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !token.isEmpty {
            environment["XHS_TOKEN"] = token
        }
        process.environment = environment
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
                    let remainder = fileHandle.readDataToEndOfFile()
                    if let str = String(data: remainder, encoding: .utf8), !str.isEmpty {
                        collector.fullOutput += str
                    }
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
                            let selectedQuality = VideoQualityOption.from(string: dict["selected_quality"] as? String ?? quality.rawValue)
                            let info = XHSPostInfo(
                                url: url,
                                noteId: noteId,
                                title: title,
                                author: author,
                                coverUrl: coverUrl,
                                videoUrl: videoUrl,
                                selectedQuality: selectedQuality
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

    /// 小红书专属下载流（支持预解析直链极速下载，支持清晰度选择与 1080P 上限控制）
    static func downloadXiaohongshuVideo(
        url: String,
        targetDirectory: URL? = nil,
        directVideoURL: String? = nil,
        directTitle: String? = nil,
        quality: VideoQualityOption = .p1080,
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
        args.append("--quality")
        args.append(quality.rawValue)

        // 鉴权信息经环境变量传递 (Python 侧 XHS_COOKIE/XHS_TOKEN 优先级高于配置文件)，避免出现在 argv 中被 ps 观测
        var environment = ProcessInfo.processInfo.environment
        let cookie = XHSAuthManager.shared.cookie.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cookie.isEmpty {
            environment["XHS_COOKIE"] = cookie
        }
        let token = XHSAuthManager.shared.defaultToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !token.isEmpty {
            environment["XHS_TOKEN"] = token
        }
        process.environment = environment
        process.arguments = args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let procToken = WorkExecutionManager.shared.registerProcess(process)

        let downloadedURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
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

        return try await enforceQualityConstraint(videoURL: downloadedURL, quality: quality, progressHandler: progressHandler)
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

        let resolvedResURL = Bundle.main.bundleURL.resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/xhs_downloader.py")
        if FileManager.default.fileExists(atPath: resolvedResURL.path) {
            return resolvedResURL.path
        }

        let standardAppPath = "/Applications/cduyzhMediaForge.app/Contents/Resources/xhs_downloader.py"
        if FileManager.default.fileExists(atPath: standardAppPath) {
            return standardAppPath
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
