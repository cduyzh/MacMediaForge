import Foundation
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

enum GIFConversionError: LocalizedError {
    case initializationFailed
    case trackLoadFailed
    case invalidOptions
    case encodingFailed
    
    var errorDescription: String? {
        switch self {
        case .initializationFailed: return "GIF 编码器初始化失败"
        case .trackLoadFailed: return "无法读取视频轨道信息"
        case .invalidOptions: return "GIF 帧率、尺寸或输出时长无效"
        case .encodingFailed: return "GIF 编码失败，未生成有效动图"
        }
    }
}

class GIFConverter {
    /// 将视频转换为优化后的 GIF，适合微信公众号排版
    /// - Parameters:
    ///   - videoURL: 输入的视频 URL
    ///   - outputURL: 输出的 GIF URL
    ///   - frameRate: 帧率 (默认 15)
    ///   - maxWidth: 最大宽度 (默认 480，保持体积小巧)
    static func convertToGIF(videoURL: URL, outputURL: URL, startTime: Double = 0, endTime: Double = 0, speed: Float = 1.0, frameRate: Int = 12, maxWidth: CGFloat = 480) async throws {
        try Task.checkCancellation()
        guard frameRate > 0, maxWidth.isFinite, maxWidth > 0 else { throw GIFConversionError.invalidOptions }
        guard videoURL.resolvingSymlinksInPath().standardizedFileURL != outputURL.resolvingSymlinksInPath().standardizedFileURL else {
            throw GIFConversionError.invalidOptions
        }
        let asset = AVURLAsset(url: videoURL)
        let assetDuration = try await asset.load(.duration)
        let durationSec = CMTimeGetSeconds(assetDuration)
        
        let (st, et) = try ConversionEngine.validatedEditRange(duration: durationSec, startTime: startTime, endTime: endTime, speed: speed)
        
        // 实际上经过变速或裁剪的时间长度
        let actualDuration = (et - st) / Double(speed)
        
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw GIFConversionError.trackLoadFailed
        }
        
        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let applied = size.applying(transform)
        let w = abs(applied.width)
        let h = abs(applied.height)
        guard w.isFinite, h.isFinite, w > 0, h > 0 else { throw GIFConversionError.trackLoadFailed }
        
        let targetWidth = min(maxWidth, w)
        let targetHeight = (targetWidth / w) * h
        
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = CGSize(width: targetWidth, height: targetHeight)
        
        let fileProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFLoopCount as String: 0
            ]
        ]
        
        // 我们需要保持目标帧率，这受到播放速度的影响
        // 原始视频每秒取 frameRate * speed 帧
        // 但 GIF 延迟时间是 1.0 / frameRate
        let delayTime = 1.0 / Double(frameRate)
        let frameProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFDelayTime as String: delayTime
            ]
        ]
        
        let frameEstimate = ceil(actualDuration * Double(frameRate))
        guard frameEstimate.isFinite, frameEstimate > 0, frameEstimate < Double(Int.max) else {
            throw GIFConversionError.invalidOptions
        }
        let totalFrames = max(1, Int(frameEstimate))
        try Task.checkCancellation()
        
        let uti = UTType.gif.identifier as CFString
        guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, uti, totalFrames, nil) else {
            throw GIFConversionError.initializationFailed
        }
        var didFinish = false
        defer { if !didFinish { try? FileManager.default.removeItem(at: outputURL) } }
        
        CGImageDestinationSetProperties(destination, fileProperties as CFDictionary)
        
        // 采样步长 (原视频的时间步长)
        let step = delayTime * Double(speed)
        var currentTime = st
        
        var frameCount = 0
        var encodedFrames = 0
        while currentTime < et && frameCount < totalFrames {
            try Task.checkCancellation()
            let time = CMTime(seconds: currentTime, preferredTimescale: 600)
            do {
                let (image, _) = try await generator.image(at: time)
                try Task.checkCancellation()
                CGImageDestinationAddImage(destination, image, frameProperties as CFDictionary)
                encodedFrames += 1
            } catch {
                if Task.isCancelled || error is CancellationError { throw CancellationError() }
                // 忽略个别帧提取失败
            }
            currentTime += step
            frameCount += 1
        }
        
        try Task.checkCancellation()
        guard encodedFrames > 0, CGImageDestinationFinalize(destination) else { throw GIFConversionError.encodingFailed }
        didFinish = true
    }
}
