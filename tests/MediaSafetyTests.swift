import Foundation
import AVFoundation
import ImageIO
import SwiftUI

// 隔离用户设置、历史、下载和相册；下面测试使用真实媒体引擎与临时文件。
enum ConversionType { case livePhoto, gif, files }
enum ConversionStatus: Equatable {
    case pending, extractingFrame, convertingVideo, importingPhotos, completed, failed(String)
    var isWorking: Bool { [.extractingFrame, .convertingVideo, .importingPhotos].contains(self) }
}
@MainActor final class VideoItem {
    let url: URL
    var status: ConversionStatus = .pending
    var completedMode: ConversionType?
    var outputURLs: [URL] = []
    var isLoadingMetadata = false
    var duration: Double = 2
    var startTime: Double = 0
    var endTime: Double = 2
    var playbackSpeed: Float = 1
    var coverTime: Double = 0
    var effectiveCoverTime: Double { coverTime }
    var canConvert: Bool { !status.isWorking }
    init(url: URL) { self.url = url }
}
public enum DuplicatePolicy { case overwrite, skip, rename }
public final class AppSettings {
    public static let shared = AppSettings()
    public var downloadURL = FileManager.default.temporaryDirectory
    var removeWatermark = false
    public var duplicatePolicy: DuplicatePolicy = .rename
}
final class DownloadCacheManager {
    static let shared = DownloadCacheManager()
    func refreshStats() {}
}
public struct AppReleaseInfo {
    public let tagName: String
    public let displayTitle: String
    public let body: String?
    public let dmgAssetURL: String?
    public let htmlURL: String
}
public final class UpdateChecker {
    public static var currentAppVersion: String { "1.9.0" }
    public static func isRemoteVersion(_ r: String, newerThan l: String) -> Bool { false }
    public static func fetchLatestRelease(customToken: String? = nil) async throws -> AppReleaseInfo {
        AppReleaseInfo(tagName: "v1.9.0", displayTitle: "v1.9.0", body: nil, dmgAssetURL: nil, htmlURL: "")
    }
}
enum OperationSource { case localStudio }
enum OperationStatus { case success, failed }
struct HistoryOutputItem {
    let fileName: String, filePath: String, category: String
    let fileSize: Int64
}
@MainActor final class OperationHistoryManager {
    static let shared = OperationHistoryManager()
    func record(source: OperationSource, platform: String, title: String, originalURLOrPath: String?, status: OperationStatus, duration: Double, outputs: [HistoryOutputItem] = [], note: String? = nil) {}
}
enum NetworkVideoDownloader {
    static func downloadVideo(url: String, targetDirectory: URL?, videoOutputDir: URL?, shouldRemoveWatermark: Bool, progressHandler: (String) -> Void) async throws -> URL {
        throw ConversionError.invalidVideo // CLI 回归只允许本地媒体，不访问网络。
    }
}

@main struct MediaSafetyTests {
    static func main() async throws {
        if CommandLine.arguments.dropFirst().first == "--cli" {
            CLIHandler.run(Array(CommandLine.arguments.dropFirst(2)))
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let source = root.appendingPathComponent("source.mov")
        let fm = FileManager.default
        let sourceData = try Data(contentsOf: source)

        // 本地视频的文件名与输出名称相同时，不可覆盖或删除源视频。
        let image = root.appendingPathComponent("cover.jpg")
        try Data([1, 2, 3]).write(to: image)
        let pair = try ConversionEngine.exportPair(imageURL: image, videoURL: source, to: root, basename: "source")
        precondition(pair.map(\.lastPathComponent) == ["source_1.jpg", "source_1.mov"])
        let preservedSource = try Data(contentsOf: source)
        precondition(preservedSource == sourceData)
        let conflict = root.appendingPathComponent("pair.jpg")
        try Data([4]).write(to: conflict)
        let renamed = try ConversionEngine.exportPair(imageURL: image, videoURL: source, to: root, basename: "pair")
        precondition(renamed.map(\.lastPathComponent) == ["pair_1.jpg", "pair_1.mov"])
        do {
            _ = try ConversionEngine.exportPair(imageURL: image, videoURL: root.appendingPathComponent("missing.mov"), to: root, basename: "failed")
            preconditionFailure("第二个文件复制失败必须抛错")
        } catch {}
        precondition(!fm.fileExists(atPath: root.appendingPathComponent("failed.jpg").path))

        // 取消只能清理明确登记的本轮半成品，不可按文件名猜测个人文件。
        let owned = root.appendingPathComponent("owned.part")
        let personal = ["notes.tmp", "personal.part", "resume.ytdl", "delogo_personal.mp4", "empty.txt"].map { root.appendingPathComponent($0) }
        for file in personal + [owned] { try Data().write(to: file) }
        WorkExecutionManager.shared.registerActiveFile(owned)
        precondition(WorkExecutionManager.shared.cancelAndCleanup(targetDirectory: root) == 1)
        precondition(personal.allSatisfy { fm.fileExists(atPath: $0.path) })
        precondition(!fm.fileExists(atPath: owned.path))

        // 域名匹配不得被相似域名、路径、查询参数和非 HTTP 协议误导。
        precondition(PlatformCategory.detect(from: "https://www.bilibili.com/video/BV123") == .bilibili)
        precondition(PlatformCategory.detect(from: "https://M.X.COM/user/status/1") == .twitter)
        precondition(PlatformCategory.detect(from: "https://x.com.evil.example/bv?site=xiaohongshu.com") == .defaultCategory)
        precondition(PlatformCategory.detect(from: "file://x.com/video") == .defaultCategory)
        precondition(PlatformCategory.extractURLs(from: "推荐 BV1xx411c7mD 和 https://x.com/user/status/1 BV1xx411c7mD") == ["https://www.bilibili.com/video/BV1xx411c7mD", "https://x.com/user/status/1"])
        precondition(PlatformCategory.extractURLs(from: "https://www.bilibili.com/video/BV1xx411c7mD") == ["https://www.bilibili.com/video/BV1xx411c7mD"])

        for values: (Double, Double, Double, Float) in [(2, -.infinity, 1, 1), (2, 1, 0.5, 1), (2, 0, 3, 1), (2, 0, 1, 0), (2, 0, 1, .nan), (.nan, 0, 1, 1)] {
            do {
                _ = try ConversionEngine.validatedEditRange(duration: values.0, startTime: values.1, endTime: values.2, speed: values.3)
                preconditionFailure("无效参数必须被拒绝")
            } catch {}
        }

        // 小于一个 GIF 帧间隔的短裁剪仍生成有效图片；真正编码后可读取。
        let gif = root.appendingPathComponent("short.gif")
        try await GIFConverter.convertToGIF(videoURL: source, outputURL: gif, startTime: 0, endTime: 0.04)
        let imageSource = CGImageSourceCreateWithURL(gif as CFURL, nil)
        precondition(imageSource != nil && CGImageSourceGetCount(imageSource!) == 1)
        let cancelledOutput = root.appendingPathComponent("cancelled.gif")
        let cancelledTask = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await GIFConverter.convertToGIF(videoURL: source, outputURL: cancelledOutput)
        }
        do { try await cancelledTask.value; preconditionFailure("已取消任务必须抛错") }
        catch is CancellationError {}
        precondition(!fm.fileExists(atPath: cancelledOutput.path))

        let cropped = try await ConversionEngine.convertToMOV(input: source, startTime: 0.2, endTime: 1.7, speed: 1.5)
        defer { try? fm.removeItem(at: cropped) }
        let duration = CMTimeGetSeconds(try await AVURLAsset(url: cropped).load(.duration))
        precondition(abs(duration - 1) < 0.1, "裁剪变速后的输出时长应接近 1 秒")
        let tinyCrop = try await ConversionEngine.convertToMOV(input: source, startTime: 0.3, endTime: 0.35)
        defer { try? fm.removeItem(at: tinyCrop) }
        let shortDuration = CMTimeGetSeconds(try await AVURLAsset(url: tinyCrop).load(.duration))
        precondition(shortDuration < 0.09, "短裁剪不得被强制延长为 0.1 秒")
        let finalSource = try Data(contentsOf: source)
        precondition(finalSource == sourceData)
        print("PASS: 配对输出保留原文件与回滚、取消只清本轮文件、平台主机校验、参数拒绝、短 GIF、GIF 取消、真实 MOV 裁剪变速")
    }
}
