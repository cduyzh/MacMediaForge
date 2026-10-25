import Foundation
import AVFoundation
import AppKit

// MARK: - 转换状态
enum ConversionStatus: Equatable {
    case pending
    case extractingFrame
    case convertingVideo
    case importingPhotos
    case completed
    case failed(String)

    var label: String {
        switch self {
        case .pending:            return "等待中"
        case .extractingFrame:    return "提取封面帧…"
        case .convertingVideo:    return "转换视频…"
        case .importingPhotos:    return "导入相册…"
        case .completed:          return "已完成"
        case .failed(let msg):    return msg
        }
    }

    var icon: String {
        switch self {
        case .pending:         return "clock"
        case .extractingFrame: return "photo.on.rectangle"
        case .convertingVideo: return "film"
        case .importingPhotos: return "square.and.arrow.down"
        case .completed:       return "checkmark.circle.fill"
        case .failed:          return "xmark.circle.fill"
        }
    }

    var isWorking: Bool {
        switch self {
        case .extractingFrame, .convertingVideo, .importingPhotos: return true
        default: return false
        }
    }
}

// MARK: - 视频条目模型
@MainActor
class VideoItem: Identifiable, ObservableObject {
    let id = UUID()
    let url: URL

    @Published var status: ConversionStatus = .pending
    @Published var thumbnail: NSImage?
    @Published var completedMode: ConversionType?
    @Published var outputURLs: [URL] = []
    
    // 裁剪与变速控制
    @Published var startTime: Double = 0
    @Published var endTime: Double = 0
    @Published var playbackSpeed: Float = 1.0
    @Published var coverTime: Double = 0

    // 元信息
    let filename: String
    @Published var duration: Double = 0
    @Published var resolution: String = "—"
    @Published var fileSize: String = "—"
    @Published private(set) var isLoadingMetadata = true
    private var thumbnailRequest = UUID()

    var canConvert: Bool {
        !isLoadingMetadata && duration.isFinite && duration > 0 && !status.isWorking
    }

    init(url: URL) {
        self.url = url
        self.filename = url.lastPathComponent
        loadMetadata()
    }

    // MARK: 读取视频基本信息
    private func loadMetadata() {
        // 文件大小
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let bytes = attrs[.size] as? Int64 {
            fileSize = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        }

        // 时长 & 分辨率 & 缩略图
        let asset = AVURLAsset(url: url)
        Task {
            defer { self.isLoadingMetadata = false }
            do {
                let dur = try await asset.load(.duration)
                let secs = CMTimeGetSeconds(dur)
                guard secs.isFinite, secs > 0,
                      let track = try await asset.loadTracks(withMediaType: .video).first else {
                    self.status = .failed("无法读取有效视频，请选择其他文件")
                    return
                }
                self.duration = secs
                self.endTime = secs
                let size = try? await track.load(.naturalSize)
                let transform = try? await track.load(.preferredTransform)
                if let size = size, let transform = transform {
                    let applied = size.applying(transform)
                    let w = Int(abs(applied.width))
                    let h = Int(abs(applied.height))
                    self.resolution = "\(w)×\(h)"
                }
                // 生成高清缩略图；失败不影响有效视频的转换。
                await self.generateThumbnail(at: 0)
            } catch {
                self.status = .failed("视频读取失败：\(error.localizedDescription)")
            }
        }
    }

    func generateThumbnail(at timeSec: Double) async {
        let request = UUID()
        thumbnailRequest = request
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        gen.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
        gen.maximumSize = CGSize(width: 320, height: 240)
        let cmTime = CMTime(seconds: timeSec, preferredTimescale: 600)
        if let (cgImg, _) = try? await gen.image(at: cmTime) {
            guard !Task.isCancelled, thumbnailRequest == request else { return }
            let nsImg = NSImage(cgImage: cgImg, size: NSSize(width: cgImg.width, height: cgImg.height))
            self.thumbnail = nsImg
        }
    }

    var effectiveCoverTime: Double {
        if coverTime >= startTime && coverTime <= max(startTime, endTime) {
            return coverTime
        }
        return startTime
    }

    var isEdited: Bool {
        startTime > 0.05 || (duration > 0.1 && abs(endTime - duration) > 0.1) || abs(playbackSpeed - 1.0) > 0.05 || coverTime > 0.05
    }

    func resetEdit() {
        startTime = 0
        endTime = duration
        playbackSpeed = 1.0
        coverTime = 0
        Task { await generateThumbnail(at: 0) }
    }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openPhotosApp() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Photos.app"))
    }

    var durationText: String {
        guard duration > 0 else { return "—" }
        let m = Int(duration) / 60
        let s = Int(duration) % 60
        let ms = Int((duration - Double(Int(duration))) * 10)
        return m > 0 ? String(format: "%d:%02d.%d", m, s, ms) : String(format: "%d.%ds", s, ms)
    }
}
