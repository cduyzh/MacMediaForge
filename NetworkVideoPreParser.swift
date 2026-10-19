import Foundation
import AppKit
import SwiftUI
import AVFoundation

// MARK: - 预解析状态枚举
public enum PreParseStatus: Equatable {
    case pending            // 等待解析
    case parsing            // 正在解析中
    case ready              // 预解析完成（标题、作者、直链及第一帧预览已就绪）
    case failed(String)     // 解析失败

    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    public var isParsing: Bool {
        if case .parsing = self { return true }
        return false
    }

    public var label: String {
        switch self {
        case .pending:
            return "等待预解析"
        case .parsing:
            return "正在提取元数据与首帧…"
        case .ready:
            return "预解析完成 (直链与首帧已就绪)"
        case .failed(let msg):
            return "解析受限: \(msg)"
        }
    }
}

// MARK: - 单个预解析视频项模型
public class PreParsedVideoItem: Identifiable, ObservableObject {
    public let id = UUID()
    public let originalURL: String
    public let platform: PlatformCategory

    @Published public var title: String
    @Published public var author: String
    @Published public var authorUsername: String?
    @Published public var status: PreParseStatus = .pending
    @Published public var previewImage: NSImage?
    @Published public var previewImageURL: String?
    @Published public var localPreviewPath: String?
    @Published public var quality: String = ""
    @Published public var videoCount: Int = 1
    @Published public var videoDirectURLs: [String] = []

    // Bilibili 合集与选集支持
    @Published public var bilibiliCollection: BilibiliCollectionInfo?
    @Published public var isSelectedForDownload: Bool = true
    @Published public var durationStr: String?

    // 缓存解析后的原始全套元数据，供下载时直接复用
    public var twitterPostInfo: TwitterPostInfo?
    public var xhsParsedInfo: XHSPostInfo?
    public var bilibiliParsedInfo: BilibiliVideoInfo?

    public init(originalURL: String) {
        self.originalURL = originalURL
        self.platform = PlatformCategory.detect(from: originalURL)
        self.title = originalURL
        self.author = "连接中…"
        self.status = .pending
        self.isSelectedForDownload = true
    }
}

// MARK: - 网络视频批量预解析管理器 (全局单例 / 统一响应式调度)
@MainActor
public class NetworkVideoPreParser: ObservableObject {
    public static let shared = NetworkVideoPreParser()

    @Published public var items: [PreParsedVideoItem] = []
    @Published public var isAnyParsing: Bool = false

    /// 缓存来自合集解析的单集元数据，避免在展开或录入合集视频时重复调用 Python 脚本
    private var episodeInfoCache: [String: (title: String, author: String, coverUrl: String?, durationStr: String)] = [:]

    private var parseTasks: [String: Task<Void, Never>] = [:]
    private var debounceTask: Task<Void, Never>? = nil

    private init() {}

    /// 缓存合集单集信息
    public func cacheCollectionEpisodes(_ episodes: [BilibiliEpisodeItem]) {
        for ep in episodes {
            episodeInfoCache[ep.url] = (ep.title, ep.author, ep.coverUrl, ep.durationStr)
            if !ep.bvid.isEmpty {
                let canonical = "https://www.bilibili.com/video/\(ep.bvid)"
                episodeInfoCache[canonical] = (ep.title, ep.author, ep.coverUrl, ep.durationStr)
            }
        }
    }

    /// 输入链接变化时自动触发同步与预解析（自带 300ms 防抖）
    public func syncURLs(_ urls: [String]) {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            self.applyURLs(urls)
        }
    }

    /// 应用 URL 列表并调度增量解析
    private func applyURLs(_ urls: [String]) {
        let currentMap = Dictionary(uniqueKeysWithValues: items.map { ($0.originalURL, $0) })
        var newItems: [PreParsedVideoItem] = []

        // 取消不再存在于输入框的解析任务
        for (url, task) in parseTasks {
            if !urls.contains(url) {
                task.cancel()
                parseTasks.removeValue(forKey: url)
            }
        }

        for u in urls {
            if let existing = currentMap[u] {
                newItems.append(existing)
            } else {
                let newItem = PreParsedVideoItem(originalURL: u)
                newItems.append(newItem)
                startParsing(newItem)
            }
        }

        self.items = newItems
        self.isAnyParsing = newItems.contains { $0.status.isParsing }
    }

    /// 单个项目重试解析
    public func retryItem(_ item: PreParsedVideoItem) {
        startParsing(item)
    }

    /// 重新全部解析
    public func refreshAll() {
        for it in items {
            startParsing(it)
        }
    }

    /// 获取某链接的预解析结果
    public func getItem(for url: String) -> PreParsedVideoItem? {
        items.first { $0.originalURL == url }
    }

    /// 启动单个任务的异步后台解析
    private func startParsing(_ item: PreParsedVideoItem) {
        let url = item.originalURL
        parseTasks[url]?.cancel()

        item.status = .parsing
        self.isAnyParsing = true

        let task = Task { @MainActor in
            await self.executeParse(for: item)
            self.parseTasks.removeValue(forKey: url)
            self.isAnyParsing = self.items.contains { $0.status.isParsing }
        }
        parseTasks[url] = task
    }

    /// 执行多平台针对性解析与首帧提取
    private func executeParse(for item: PreParsedVideoItem) async {
        let url = item.originalURL

        do {
            if item.platform == .twitter {
                let postInfo = try await TwitterDownloader.fetchPostInfo(url: url)
                if Task.isCancelled { return }

                item.twitterPostInfo = postInfo

                // 提取标题
                if postInfo.isArticle, let artTitle = postInfo.articleTitle, !artTitle.isEmpty {
                    item.title = artTitle
                } else if !postInfo.rootText.isEmpty {
                    item.title = postInfo.rootText
                } else if let firstV = postInfo.videos.first {
                    item.title = firstV.title
                } else {
                    item.title = "Twitter / X 视频帖"
                }

                // 提取作者
                let name = postInfo.authorName ?? ""
                let username = postInfo.authorUsername ?? ""
                if !name.isEmpty && !username.isEmpty {
                    item.author = "\(name) (@\(username))"
                } else if !name.isEmpty {
                    item.author = name
                } else if !username.isEmpty {
                    item.author = "@\(username)"
                } else {
                    item.author = "Twitter 创作者"
                }
                item.authorUsername = username

                item.videoCount = max(1, postInfo.videos.count)
                item.videoDirectURLs = postInfo.videos.map { $0.url }
                if let firstV = postInfo.videos.first {
                    item.quality = firstV.quality
                }

                // 提取封面图 / 第一帧
                let coverCandidate = postInfo.coverUrl ?? postInfo.videos.first?.thumbnailUrl
                let videoCandidate = postInfo.videos.first?.url
                await self.loadThumbnail(for: item, remoteImageURL: coverCandidate, directVideoURL: videoCandidate)

                item.status = .ready

            } else if item.platform == .xhs {
                let xhsInfo = try await NetworkVideoDownloader.fetchXHSInfo(url: url)
                if Task.isCancelled { return }

                item.xhsParsedInfo = xhsInfo
                item.title = xhsInfo.title.isEmpty ? "小红书精彩视频" : xhsInfo.title
                item.author = xhsInfo.author.isEmpty ? "小红书创作者" : xhsInfo.author
                if let vUrl = xhsInfo.videoUrl {
                    item.videoDirectURLs = [vUrl]
                }
                item.videoCount = 1
                item.quality = "高清无水印"

                await self.loadThumbnail(for: item, remoteImageURL: xhsInfo.coverUrl, directVideoURL: xhsInfo.videoUrl)
                item.status = .ready

            } else if item.platform == .bilibili {
                // 先检查是否已在合集单集缓存中
                if let cached = episodeInfoCache[url] {
                    item.title = cached.title
                    item.author = cached.author
                    item.durationStr = cached.durationStr
                    item.quality = "高清"
                    item.videoCount = 1
                    await self.loadThumbnail(for: item, remoteImageURL: cached.coverUrl, directVideoURL: nil)
                    item.status = .ready
                    return
                }

                let biliInfo = try await BilibiliDownloader.fetchVideoInfo(url: url)
                if Task.isCancelled { return }

                item.bilibiliParsedInfo = biliInfo
                item.bilibiliCollection = biliInfo.collection
                item.title = biliInfo.title.isEmpty ? "哔哩哔哩精彩视频" : biliInfo.title
                item.author = biliInfo.author.isEmpty ? "B站UP主" : biliInfo.author
                if let vUrl = biliInfo.videoUrl {
                    item.videoDirectURLs = [vUrl]
                }
                item.videoCount = biliInfo.collection?.epCount ?? 1
                item.quality = biliInfo.quality

                // 如果包含合集或多P，将所有单集注入快速缓存
                if let coll = biliInfo.collection {
                    self.cacheCollectionEpisodes(coll.allEpisodes)
                }

                await self.loadThumbnail(for: item, remoteImageURL: biliInfo.coverUrl, directVideoURL: biliInfo.videoUrl)
                item.status = .ready

            } else {
                // 通用网络视频直链
                item.title = URL(string: url)?.lastPathComponent ?? "网络媒体"
                item.author = URL(string: url)?.host ?? "网络视频"
                item.videoCount = 1
                item.videoDirectURLs = [url]
                item.quality = "原画"

                await self.loadThumbnail(for: item, remoteImageURL: nil, directVideoURL: url)
                item.status = .ready
            }

        } catch {
            if Task.isCancelled { return }
            item.status = .failed(error.localizedDescription)
        }
    }

    /// 下载远程封面或通过本地视频首帧提取器生成高质量预览图
    private func loadThumbnail(for item: PreParsedVideoItem, remoteImageURL: String?, directVideoURL: String?) async {
        let previewsDir = DownloadCacheManager.shared.appTempDirectoryURL.appendingPathComponent("previews", isDirectory: true)
        try? FileManager.default.createDirectory(at: previewsDir, withIntermediateDirectories: true, attributes: nil)

        // 策略 1: 若服务商直接提供了视频首帧/海报图直链 (如 Twitter 的 amplify_video_thumb 或小红书封面图)
        if let imgUrlStr = remoteImageURL, let imgURL = URL(string: imgUrlStr) {
            let fileExt = (imgURL.pathExtension.isEmpty ? "jpg" : imgURL.pathExtension)
            let dest = previewsDir.appendingPathComponent("thumb-\(UUID().uuidString).\(fileExt)")

            var req = URLRequest(url: imgURL, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 12)
            req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
            if imgUrlStr.contains("twimg.com") {
                req.setValue("https://x.com/", forHTTPHeaderField: "Referer")
            } else if imgUrlStr.contains("xhscdn.com") {
                req.setValue("https://www.xiaohongshu.com/", forHTTPHeaderField: "Referer")
            } else if imgUrlStr.contains("hdslb.com") || imgUrlStr.contains("bilibili.com") {
                req.setValue("https://www.bilibili.com/", forHTTPHeaderField: "Referer")
            }

            if let (data, resp) = try? await URLSession.shared.data(for: req),
               let httpResp = resp as? HTTPURLResponse, (200...299).contains(httpResp.statusCode),
               let nsImg = NSImage(data: data) {
                try? data.write(to: dest)
                item.previewImage = nsImg
                item.previewImageURL = imgUrlStr
                item.localPreviewPath = dest.path
                return
            }
        }

        // 策略 2: 若未提供封面图或下载失败，利用 AVAssetImageGenerator 从视频第 0 秒精确提取首帧
        if let vUrlStr = directVideoURL, let vURL = URL(string: vUrlStr) {
            do {
                let asset = AVURLAsset(url: vURL)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
                generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
                let (cgImage, _) = try await generator.image(at: CMTime.zero)
                let nsImg = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                let dest = previewsDir.appendingPathComponent("avframe-\(UUID().uuidString).jpg")

                if let tiff = nsImg.tiffRepresentation,
                   let rep = NSBitmapImageRep(data: tiff),
                   let jpgData = rep.representation(using: .jpeg, properties: [:]) {
                    try? jpgData.write(to: dest)
                }
                item.previewImage = nsImg
                item.localPreviewPath = dest.path
                return
            } catch {
                // AVAssetImageGenerator 对远程流不兼容时回退到策略 3
            }

            // 策略 3: 使用 ffmpeg 提取首帧图片
            let dest = previewsDir.appendingPathComponent("ffframe-\(UUID().uuidString).jpg")
            if let ffmpeg = locateFFmpeg() {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: ffmpeg)
                process.arguments = [
                    "-ss", "00:00:00.1",
                    "-i", vUrlStr,
                    "-vframes", "1",
                    "-q:v", "2",
                    "-y",
                    dest.path
                ]
                try? process.run()
                process.waitUntilExit()

                if FileManager.default.fileExists(atPath: dest.path),
                   let data = try? Data(contentsOf: dest),
                   let nsImg = NSImage(data: data) {
                    item.previewImage = nsImg
                    item.localPreviewPath = dest.path
                    return
                }
            }
        }
    }

    /// 寻找可用的 ffmpeg 执行路径
    private func locateFFmpeg() -> String? {
        let candidates = [
            "/Users/hobby/gitlab-source/videoToLivephoto/ffmpeg",
            "/Users/hobby/.local/bin/ffmpeg",
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }
}
