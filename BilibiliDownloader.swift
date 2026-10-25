import Foundation

// MARK: - Bilibili 合集与单集元数据模型
public struct BilibiliEpisodeItem: Identifiable, Sendable, Equatable, Hashable {
    public var id: String { "\(bvid)_\(cid)_\(page)" }
    public let bvid: String
    public let cid: Int64
    public let page: Int
    public let title: String
    public let coverUrl: String?
    public let duration: Int
    public let durationStr: String
    public let author: String
    public let sectionTitle: String
    public let url: String
    public let isCurrent: Bool

    public init(
        bvid: String,
        cid: Int64,
        page: Int = 1,
        title: String,
        coverUrl: String? = nil,
        duration: Int = 0,
        durationStr: String = "",
        author: String = "",
        sectionTitle: String = "",
        url: String = "",
        isCurrent: Bool = false
    ) {
        self.bvid = bvid
        self.cid = cid
        self.page = page
        self.title = title
        self.coverUrl = coverUrl
        self.duration = duration
        self.durationStr = durationStr
        self.author = author
        self.sectionTitle = sectionTitle
        self.url = url
        self.isCurrent = isCurrent
    }
}

public struct BilibiliSectionItem: Identifiable, Sendable, Equatable {
    public let id: Int
    public let title: String
    public let episodes: [BilibiliEpisodeItem]

    public init(id: Int, title: String, episodes: [BilibiliEpisodeItem]) {
        self.id = id
        self.title = title
        self.episodes = episodes
    }
}

public struct BilibiliCollectionInfo: Identifiable, Sendable, Equatable {
    public var id: String { "\(currentBvid)_\(title)_\(epCount)" }
    public let type: String          // "ugc_season" 或 "pages"
    public let typeLabel: String     // "合集" 或 "分P视频"
    public let title: String
    public let coverUrl: String?
    public let intro: String
    public let epCount: Int
    public let currentBvid: String
    public let sections: [BilibiliSectionItem]

    public var allEpisodes: [BilibiliEpisodeItem] {
        sections.flatMap { $0.episodes }
    }

    public init(
        type: String,
        typeLabel: String,
        title: String,
        coverUrl: String?,
        intro: String,
        epCount: Int,
        currentBvid: String,
        sections: [BilibiliSectionItem]
    ) {
        self.type = type
        self.typeLabel = typeLabel
        self.title = title
        self.coverUrl = coverUrl
        self.intro = intro
        self.epCount = epCount
        self.currentBvid = currentBvid
        self.sections = sections
    }
}

// MARK: - Bilibili 视频元数据模型
public struct BilibiliVideoInfo: Sendable {
    public let bvid: String
    public let cid: Int64
    public let title: String
    public let author: String
    public let coverUrl: String?
    public let duration: Int
    public let quality: String
    public let selectedQuality: String
    public let availableQualities: [String]
    public let isDash: Bool
    public let videoUrl: String?
    public let audioUrl: String?
    public let directUrl: String?
    public let originalUrl: String
    public let collection: BilibiliCollectionInfo?

    public init(
        bvid: String,
        cid: Int64,
        title: String,
        author: String,
        coverUrl: String?,
        duration: Int,
        quality: String,
        selectedQuality: String = "1080p",
        availableQualities: [String] = ["1080p", "720p", "480p", "360p"],
        isDash: Bool,
        videoUrl: String?,
        audioUrl: String?,
        directUrl: String?,
        originalUrl: String,
        collection: BilibiliCollectionInfo? = nil
    ) {
        self.bvid = bvid
        self.cid = cid
        self.title = title
        self.author = author
        self.coverUrl = coverUrl
        self.duration = duration
        self.quality = quality
        self.selectedQuality = selectedQuality
        self.availableQualities = availableQualities
        self.isDash = isDash
        self.videoUrl = videoUrl
        self.audioUrl = audioUrl
        self.directUrl = directUrl
        self.originalUrl = originalUrl
        self.collection = collection
    }

    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "bvid": bvid,
            "cid": cid,
            "title": title,
            "author": author,
            "duration": duration,
            "quality": quality,
            "selected_quality": selectedQuality,
            "available_qualities": availableQualities,
            "is_dash": isDash,
            "original_url": originalUrl
        ]
        if let c = coverUrl { dict["cover_url"] = c }
        if let v = videoUrl { dict["video_url"] = v }
        if let a = audioUrl { dict["audio_url"] = a }
        if let d = directUrl { dict["direct_url"] = d }
        return dict
    }
}

public struct BilibiliDownloadResult: Sendable {
    public let videoURL: URL
    public let title: String
    public let author: String
    public let bvid: String
    public let quality: String
}

// MARK: - Bilibili 专属全功能下载与预解析器
public class BilibiliDownloader {

    public enum DownloadError: LocalizedError {
        case invalidURL
        case scriptNotFound
        case executionError(String)
        case parseError(String)
        case downloadFailed(Int32, String)

        public var errorDescription: String? {
            switch self {
            case .invalidURL: return "无效的哔哩哔哩视频链接或未识别到BV号"
            case .scriptNotFound: return "未找到哔哩哔哩解析引擎脚本 (bilibili_downloader.py)"
            case .executionError(let msg): return "执行出错: \(msg)"
            case .parseError(let msg): return "解析B站视频数据失败: \(msg)"
            case .downloadFailed(let code, let msg): return "B站视频下载失败 (状态码: \(code)): \(msg)"
            }
        }
    }

    /// 定位 bilibili_downloader.py 脚本路径
    public static func locateBilibiliDownloaderScript() -> String? {
        // 1. App Bundle 资源目录
        if let bundlePath = Bundle.main.path(forResource: "bilibili_downloader", ofType: "py"),
           FileManager.default.fileExists(atPath: bundlePath) {
            return bundlePath
        }

        let resURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/bilibili_downloader.py")
        if FileManager.default.fileExists(atPath: resURL.path) {
            return resURL.path
        }

        // 2. 可执行程序同级或上级目录
        let execDir = Bundle.main.bundleURL.deletingLastPathComponent().path
        let candidate1 = (execDir as NSString).appendingPathComponent("bilibili_downloader.py")
        if FileManager.default.fileExists(atPath: candidate1) {
            return candidate1
        }

        // 3. 当前运行工作目录
        let currentDir = FileManager.default.currentDirectoryPath
        let candidate2 = (currentDir as NSString).appendingPathComponent("App/bilibili_downloader.py")
        if FileManager.default.fileExists(atPath: candidate2) {
            return candidate2
        }

        let candidate3 = (currentDir as NSString).appendingPathComponent("bilibili_downloader.py")
        if FileManager.default.fileExists(atPath: candidate3) {
            return candidate3
        }

        return nil
    }

    /// 预解析 B站 视频元数据（标题、UP主、封面首帧及音视频轨）
    public static func fetchVideoInfo(url: String, quality: VideoQualityOption = .p1080) async throws -> BilibiliVideoInfo {
        guard let scriptPath = locateBilibiliDownloaderScript() else {
            throw DownloadError.scriptNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-u", scriptPath, "info", url, "--quality", quality.rawValue]

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

                                let bvid = dict["bvid"] as? String ?? ""
                                let cid = (dict["cid"] as? NSNumber)?.int64Value ?? 0
                                let title = dict["title"] as? String ?? "B站精彩视频"
                                let author = dict["author"] as? String ?? "B站创作者"
                                let coverUrl = dict["cover_url"] as? String
                                let duration = dict["duration"] as? Int ?? 0
                                let quality = dict["quality"] as? String ?? "高清 1080P"
                                let selQ = dict["selected_quality"] as? String ?? quality
                                let availQ = dict["available_qualities"] as? [String] ?? ["1080p", "720p", "480p", "360p"]
                                let isDash = dict["is_dash"] as? Bool ?? false
                                let videoUrl = dict["video_url"] as? String
                                let audioUrl = dict["audio_url"] as? String
                                let directUrl = dict["direct_url"] as? String
                                let originalUrl = dict["original_url"] as? String ?? url

                                var collectionInfo: BilibiliCollectionInfo? = nil
                                if let cDict = dict["collection"] as? [String: Any] {
                                    let cType = cDict["type"] as? String ?? "ugc_season"
                                    let cLabel = cDict["type_label"] as? String ?? "合集"
                                    let cTitle = cDict["title"] as? String ?? title
                                    let cCover = cDict["cover_url"] as? String
                                    let cIntro = cDict["intro"] as? String ?? ""
                                    let cEpCount = cDict["ep_count"] as? Int ?? 0
                                    let cCurrBvid = cDict["current_bvid"] as? String ?? bvid

                                    var sectionsList: [BilibiliSectionItem] = []
                                    if let secArr = cDict["sections"] as? [[String: Any]] {
                                        for (sIdx, sec) in secArr.enumerated() {
                                            let sId = sec["id"] as? Int ?? sIdx
                                            let sTitle = sec["title"] as? String ?? "分卷 \(sIdx + 1)"
                                            var epsList: [BilibiliEpisodeItem] = []
                                            if let epArr = sec["episodes"] as? [[String: Any]] {
                                                for ep in epArr {
                                                    let eBvid = ep["bvid"] as? String ?? ""
                                                    let eCid = (ep["cid"] as? NSNumber)?.int64Value ?? 0
                                                    let ePage = ep["page"] as? Int ?? 1
                                                    let eTitle = ep["title"] as? String ?? ""
                                                    let eCover = ep["cover_url"] as? String
                                                    let eDur = ep["duration"] as? Int ?? 0
                                                    let eDurStr = ep["duration_str"] as? String ?? ""
                                                    let eAuthor = ep["author"] as? String ?? author
                                                    let eSecTitle = ep["section_title"] as? String ?? sTitle
                                                    let eUrl = ep["url"] as? String ?? "https://www.bilibili.com/video/\(eBvid)"
                                                    let eIsCurrent = ep["is_current"] as? Bool ?? (eBvid == bvid)

                                                    epsList.append(BilibiliEpisodeItem(
                                                        bvid: eBvid,
                                                        cid: eCid,
                                                        page: ePage,
                                                        title: eTitle,
                                                        coverUrl: eCover,
                                                        duration: eDur,
                                                        durationStr: eDurStr,
                                                        author: eAuthor,
                                                        sectionTitle: eSecTitle,
                                                        url: eUrl,
                                                        isCurrent: eIsCurrent
                                                    ))
                                                }
                                            }
                                            sectionsList.append(BilibiliSectionItem(id: sId, title: sTitle, episodes: epsList))
                                        }
                                    }

                                    collectionInfo = BilibiliCollectionInfo(
                                        type: cType,
                                        typeLabel: cLabel,
                                        title: cTitle,
                                        coverUrl: cCover,
                                        intro: cIntro,
                                        epCount: cEpCount,
                                        currentBvid: cCurrBvid,
                                        sections: sectionsList
                                    )
                                }

                                let info = BilibiliVideoInfo(
                                    bvid: bvid,
                                    cid: cid,
                                    title: title,
                                    author: author,
                                    coverUrl: coverUrl,
                                    duration: duration,
                                    quality: quality,
                                    selectedQuality: selQ,
                                    availableQualities: availQ,
                                    isDash: isDash,
                                    videoUrl: videoUrl,
                                    audioUrl: audioUrl,
                                    directUrl: directUrl,
                                    originalUrl: originalUrl,
                                    collection: collectionInfo
                                )
                                continuation.resume(returning: info)
                                return
                            }
                        }
                        continuation.resume(throwing: DownloadError.parseError("未能从返回中读取 B站 元数据 JSON"))
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

    /// 执行 B站 视频完整下载并保存到指定分类存储目录
    public static func downloadVideo(
        url: String,
        targetDirectory: URL? = nil,
        quality: VideoQualityOption = .p1080,
        preParsedInfo: BilibiliVideoInfo? = nil,
        progressHandler: @escaping (String) -> Void
    ) async throws -> URL {
        guard let scriptPath = locateBilibiliDownloaderScript() else {
            throw DownloadError.scriptNotFound
        }

        let folder = targetDirectory ?? CategorizedStorageManager.categoryDirectory(platform: .bilibili, category: .video)
        CategorizedStorageManager.ensureDirectory(at: folder)

        var activeInfo = preParsedInfo
        if activeInfo == nil {
            progressHandler("正在预解析视频标题与UP主信息…")
            activeInfo = try? await fetchVideoInfo(url: url, quality: quality)
        }

        // 确定保存文件名：优先使用UP主和标题，若已预解析则生成优雅友好的文件名
        let baseTitle: String
        if let info = activeInfo, !info.title.isEmpty {
            baseTitle = "\(info.author) - \(info.title)"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let timestamp = formatter.string(from: Date())
            baseTitle = "BiliVideo-\(timestamp)"
        }

        // 清理文件名非法字符
        let sanitized = baseTitle.replacingOccurrences(of: "[/\\\\:*?\"<>|]", with: "_", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let filename = "\(sanitized.prefix(120)).mp4"

        let (targetURL, shouldSkip) = CategorizedStorageManager.resolveDestination(in: folder, filename: filename)
        if shouldSkip {
            progressHandler("本地已存在同名视频，根据设置已跳过下载")
            return targetURL
        }

        WorkExecutionManager.shared.registerActiveFile(targetURL)

        var args = [
            scriptPath,
            url,
            targetURL.path,
            "--quality",
            quality.rawValue
        ]

        if let info = activeInfo {
            args.append("--title")
            args.append(info.title)

            let tempJsonURL = DownloadCacheManager.shared.appTempDirectoryURL.appendingPathComponent("bili-preparsed-\(UUID().uuidString).json")
            if let data = try? JSONSerialization.data(withJSONObject: info.toDictionary(), options: []) {
                try? data.write(to: tempJsonURL)
                args.append("--preparsed")
                args.append(tempJsonURL.path)
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-u"] + args

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
                    WorkExecutionManager.shared.unregisterActiveFile(targetURL)

                    if proc.terminationStatus == 0 && FileManager.default.fileExists(atPath: targetURL.path) {
                        DownloadCacheManager.shared.recordCompletedDownload(sourceURL: url, fileURL: targetURL)
                        continuation.resume(returning: targetURL)
                    } else {
                        continuation.resume(throwing: DownloadError.downloadFailed(proc.terminationStatus, collector.lastLine.isEmpty ? collector.fullOutput : collector.lastLine))
                    }
                }
            } catch {
                WorkExecutionManager.shared.unregisterProcess(id: procToken)
                WorkExecutionManager.shared.unregisterActiveFile(targetURL)
                continuation.resume(throwing: DownloadError.executionError(error.localizedDescription))
            }
        }
    }
}
