import Foundation
import AVFoundation
import Photos
import ImageIO
import AppKit

// MARK: - 错误类型
enum ConversionError: LocalizedError {
    case frameExtractionFailed
    case frameEncodeFailed
    case exportSessionCreationFailed
    case videoConversionFailed(String)
    case photosAccessDenied
    case importFailed(String)
    case invalidVideo
    case invalidEditRange
    case invalidPlaybackSpeed
    case outputMissing

    var errorDescription: String? {
        switch self {
        case .frameExtractionFailed:       return "无法提取视频帧"
        case .frameEncodeFailed:           return "无法编码封面图"
        case .exportSessionCreationFailed: return "无法创建视频导出会话"
        case .videoConversionFailed(let m): return "视频转换失败：\(m)"
        case .photosAccessDenied:          return "未获得照片权限，请在系统设置中授权"
        case .importFailed(let m):         return "导入相册失败：\(m)"
        case .invalidVideo:                return "无法读取有效视频，请重新添加文件"
        case .invalidEditRange:            return "裁剪范围无效，请检查开始、结束和封面时间"
        case .invalidPlaybackSpeed:        return "播放速度必须大于零"
        case .outputMissing:               return "未能生成有效的输出文件"
        }
    }
}

// MARK: - 转换引擎
class ConversionEngine {

    /// 应用专属转换临时目录 (~/tmp/cduyzhMediaForge_Temp)
    static var appTempDirectoryURL: URL {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("cduyzhMediaForge_Temp", isDirectory: true)
        if !FileManager.default.fileExists(atPath: tempDir.path) {
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
        }
        return tempDir
    }

    // ──────── Step 1：提取封面帧 ────────
    static func extractFrame(from videoURL: URL, at seconds: Double = 0, assetIdentifier: String? = nil) async throws -> URL {
        try Task.checkCancellation()
        let asset = AVURLAsset(url: videoURL)
        let duration = CMTimeGetSeconds(try await asset.load(.duration))
        guard duration.isFinite, duration > 0 else { throw ConversionError.invalidVideo }
        guard seconds.isFinite, seconds >= 0, seconds < duration else { throw ConversionError.invalidEditRange }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceAfter  = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)

        let cmTime = CMTime(seconds: seconds, preferredTimescale: 600)
        let (cgImage, _) = try await generator.image(at: cmTime)
        try Task.checkCancellation()

        // 保存为高质量 JPEG 到专属临时目录
        let tmpURL = appTempDirectoryURL
            .appendingPathComponent("frame-\(UUID().uuidString)")
            .appendingPathExtension("jpg")
        var didFinish = false
        defer {
            if !didFinish { try? FileManager.default.removeItem(at: tmpURL) }
        }

        guard let dest = CGImageDestinationCreateWithURL(
            tmpURL as CFURL, "public.jpeg" as CFString, 1, nil
        ) else {
            throw ConversionError.frameEncodeFailed
        }
        var opts: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.92]
        if let assetID = assetIdentifier {
            let makerApple: [String: Any] = ["17": assetID]
            opts[kCGImagePropertyMakerAppleDictionary] = makerApple
        }
        CGImageDestinationAddImage(dest, cgImage, opts as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw ConversionError.frameEncodeFailed
        }
        try Task.checkCancellation()
        didFinish = true
        return tmpURL
    }

    // ──────── Step 2：转封装或重编码处理裁剪/变速 ────────
    static func convertToMOV(input: URL, startTime: Double = 0, endTime: Double = 0, speed: Float = 1.0, assetIdentifier: String? = nil) async throws -> URL {
        try Task.checkCancellation()
        let asset = AVURLAsset(url: input)
        let outputURL = appTempDirectoryURL
            .appendingPathComponent("mov-\(UUID().uuidString)")
            .appendingPathExtension("mov")
        var didFinish = false
        defer {
            if !didFinish { try? FileManager.default.removeItem(at: outputURL) }
        }

        var metadataItems: [AVMetadataItem] = []
        if let assetID = assetIdentifier {
            let item = AVMutableMetadataItem()
            item.key = "com.apple.quicktime.content.identifier" as (NSCopying & NSObjectProtocol)
            item.keySpace = AVMetadataKeySpace.quickTimeMetadata
            item.value = assetID as (NSCopying & NSObjectProtocol)
            item.dataType = "com.apple.metadata.datatype.UTF-8"
            metadataItems.append(item)
        }

        let assetDuration = try await asset.load(.duration)
        let durationSec = CMTimeGetSeconds(assetDuration)
        let (st, et) = try validatedEditRange(duration: durationSec, startTime: startTime, endTime: endTime, speed: speed)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw ConversionError.invalidVideo
        }
        
        // 优先尝试 Passthrough（直接复制流，零损耗）- 仅当不需要裁剪或变速时
        let isFullRange = st == 0 && et == durationSec
        let isNormalSpeed = speed == 1
        
        if isFullRange && isNormalSpeed {
            let presetName = AVAssetExportPresetPassthrough
            guard let session = AVAssetExportSession(asset: asset, presetName: presetName) else {
                throw ConversionError.exportSessionCreationFailed
            }

            session.outputURL = outputURL
            session.outputFileType = .mov
            if !metadataItems.isEmpty {
                session.metadata = metadataItems
            }

            await withTaskCancellationHandler {
                await session.export()
            } onCancel: {
                session.cancelExport()
            }
            try Task.checkCancellation()

            guard session.status == .completed else {
                let msg = session.error?.localizedDescription ?? "未知错误"
                throw ConversionError.videoConversionFailed(msg)
            }
            didFinish = true
            return outputURL
        }
        
        // 需要裁剪或变速，使用 AVMutableComposition
        let comp = AVMutableComposition()
        let timeRange = CMTimeRange(start: CMTime(seconds: st, preferredTimescale: 600), duration: CMTime(seconds: et - st, preferredTimescale: 600))
        
        // 视频轨道
        if let compVideoTrack = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try compVideoTrack.insertTimeRange(timeRange, of: videoTrack, at: .zero)
            
            if !isNormalSpeed {
                let newDuration = CMTime(seconds: (et - st) / Double(speed), preferredTimescale: 600)
                compVideoTrack.scaleTimeRange(CMTimeRange(start: .zero, duration: timeRange.duration), toDuration: newDuration)
            }
            compVideoTrack.preferredTransform = try await videoTrack.load(.preferredTransform)
        }
        
        // 音频轨道 (由于静音实况图有时也需要，我们保留音频)
        if let audioTrack = try await asset.loadTracks(withMediaType: .audio).first,
           let compAudioTrack = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try compAudioTrack.insertTimeRange(timeRange, of: audioTrack, at: .zero)
            if !isNormalSpeed {
                let newDuration = CMTime(seconds: (et - st) / Double(speed), preferredTimescale: 600)
                compAudioTrack.scaleTimeRange(CMTimeRange(start: .zero, duration: timeRange.duration), toDuration: newDuration)
            }
        }
        
        // 使用 HighestQuality 预设，因为变速/裁剪后 Passthrough 可能无法正常工作或需要重排时间戳
        guard let session = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetHighestQuality) else {
            throw ConversionError.exportSessionCreationFailed
        }
        session.outputURL = outputURL
        session.outputFileType = .mov
        if !metadataItems.isEmpty {
            session.metadata = metadataItems
        }
        await withTaskCancellationHandler {
            await session.export()
        } onCancel: {
            session.cancelExport()
        }
        try Task.checkCancellation()

        guard session.status == .completed else {
            let msg = session.error?.localizedDescription ?? "未知错误"
            throw ConversionError.videoConversionFailed(msg)
        }
        didFinish = true
        return outputURL
    }

    // ──────── Step 3：导入系统相册（核心） ────────
    /// 使用 PHAssetCreationRequest 的 .photo + .pairedVideo 接口，
    /// 系统会自动完成 UUID 配对，生成原生 Live Photo。
    static func importToPhotos(imageURL: URL, videoURL: URL) async throws {
        try Task.checkCancellation()
        // 请求权限
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        try Task.checkCancellation()
        guard status == .authorized || status == .limited else {
            throw ConversionError.photosAccessDenied
        }

        // 执行导入
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()

            let photoOpts = PHAssetResourceCreationOptions()
            photoOpts.shouldMoveFile = false          // 不移动源文件

            let videoOpts = PHAssetResourceCreationOptions()
            videoOpts.shouldMoveFile = false

            request.addResource(with: .photo, fileURL: imageURL, options: photoOpts)
            request.addResource(with: .pairedVideo, fileURL: videoURL, options: videoOpts)
        }
    }

    // ──────── 完整流水线 ────────
    @MainActor
    static func processVideo(_ item: VideoItem, type: ConversionType = .livePhoto) async {
        guard !item.status.isWorking else { return }
        let startTime = Date()
        let base = item.url.deletingPathExtension().lastPathComponent
        do {
            try Task.checkCancellation()
            try validateInput(item)
        } catch {
            item.status = Task.isCancelled ? .pending : .failed(error.localizedDescription)
            return
        }
        item.completedMode = nil
        item.outputURLs = []

        if type == .gif {
            var gifURL: URL?
            do {
                item.status = .convertingVideo
                let targetDir = CategorizedStorageManager.categoryDirectory(
                    baseDir: AppSettings.shared.downloadURL,
                    platform: .defaultCategory,
                    category: .gif
                )
                let outputURL = targetDir.appendingPathComponent("\(base)_WeChat_\(UUID().uuidString.prefix(4)).gif")
                gifURL = outputURL
                
                try await GIFConverter.convertToGIF(
                    videoURL: item.url,
                    outputURL: outputURL,
                    startTime: item.startTime,
                    endTime: item.endTime,
                    speed: item.playbackSpeed
                )
                try Task.checkCancellation()
                let size = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int64) ?? 0
                guard size > 0 else { throw ConversionError.outputMissing }
                item.completedMode = type
                item.outputURLs = [outputURL]
                item.status = .completed

                OperationHistoryManager.shared.record(
                    source: .localStudio,
                    platform: "本地",
                    title: "本地视频转微信 GIF: \(base)",
                    originalURLOrPath: item.url.path,
                    status: .success,
                    duration: Date().timeIntervalSince(startTime),
                    outputs: [
                        HistoryOutputItem(fileName: outputURL.lastPathComponent, filePath: outputURL.path, category: "GIF", fileSize: size)
                    ],
                    note: "已保存至默认分类 GIF 目录"
                )
            } catch {
                if let outputURL = gifURL { try? FileManager.default.removeItem(at: outputURL) }
                if Task.isCancelled || error is CancellationError {
                    item.status = .pending
                    return
                }
                item.status = .failed(error.localizedDescription)
                OperationHistoryManager.shared.record(
                    source: .localStudio,
                    platform: "本地",
                    title: "本地视频转 GIF 失败: \(base)",
                    originalURLOrPath: item.url.path,
                    status: .failed,
                    duration: Date().timeIntervalSince(startTime),
                    note: error.localizedDescription
                )
            }
            return
        }

        var frameURL: URL?
        var movURL: URL?
        defer {
            if let f = frameURL { try? FileManager.default.removeItem(at: f) }
            if let m = movURL { try? FileManager.default.removeItem(at: m) }
        }

        if type == .files {
            do {
                let assetID = UUID().uuidString
                item.status = .extractingFrame
                frameURL = try await extractFrame(from: item.url, at: item.effectiveCoverTime, assetIdentifier: assetID)
                try Task.checkCancellation()

                item.status = .convertingVideo
                movURL = try await convertToMOV(input: item.url, startTime: item.startTime, endTime: item.endTime, speed: item.playbackSpeed, assetIdentifier: assetID)
                try Task.checkCancellation()

                let targetDir = CategorizedStorageManager.categoryDirectory(
                    baseDir: AppSettings.shared.downloadURL,
                    platform: .defaultCategory,
                    category: .livePhoto
                )
                let outputs = try exportPair(imageURL: frameURL!, videoURL: movURL!, to: targetDir, basename: base)
                let destJPG = outputs[0]
                let destMOV = outputs[1]

                item.completedMode = type
                item.outputURLs = [destJPG, destMOV]
                item.status = .completed

                let jpgSize = (try? FileManager.default.attributesOfItem(atPath: destJPG.path)[.size] as? Int64) ?? 0
                let movSize = (try? FileManager.default.attributesOfItem(atPath: destMOV.path)[.size] as? Int64) ?? 0
                OperationHistoryManager.shared.record(
                    source: .localStudio,
                    platform: "本地",
                    title: "本地视频导出实况配对文件: \(base)",
                    originalURLOrPath: item.url.path,
                    status: .success,
                    duration: Date().timeIntervalSince(startTime),
                    outputs: [
                        HistoryOutputItem(fileName: destJPG.lastPathComponent, filePath: destJPG.path, category: "实况", fileSize: jpgSize),
                        HistoryOutputItem(fileName: destMOV.lastPathComponent, filePath: destMOV.path, category: "实况", fileSize: movSize)
                    ],
                    note: "生成 .jpg + .mov 配对文件并存入实况目录"
                )
            } catch {
                if Task.isCancelled || error is CancellationError {
                    item.status = .pending
                    return
                }
                item.status = .failed(error.localizedDescription)
                OperationHistoryManager.shared.record(
                    source: .localStudio,
                    platform: "本地",
                    title: "本地导出实况配对失败: \(base)",
                    originalURLOrPath: item.url.path,
                    status: .failed,
                    duration: Date().timeIntervalSince(startTime),
                    note: error.localizedDescription
                )
            }

            return
        }

        do {
            let assetID = UUID().uuidString

            // 1. 提取封面帧 (以用户选取的封面关键帧为准)
            item.status = .extractingFrame
            frameURL = try await extractFrame(from: item.url, at: item.effectiveCoverTime, assetIdentifier: assetID)
            try Task.checkCancellation()

            // 2. 转封装/重编码为 MOV
            item.status = .convertingVideo
            movURL = try await convertToMOV(input: item.url, startTime: item.startTime, endTime: item.endTime, speed: item.playbackSpeed, assetIdentifier: assetID)
            try Task.checkCancellation()

            // 3. 导入系统相册
            item.status = .importingPhotos
            try await importToPhotos(imageURL: frameURL!, videoURL: movURL!)

            // 相册写入已成功时保留完成结果；取消不会撤销系统已经保存的资源。
            item.completedMode = type
            item.outputURLs = []
            item.status = .completed

            OperationHistoryManager.shared.record(
                source: .localStudio,
                platform: "本地",
                title: "实况照片制作并导入相册: \(base)",
                originalURLOrPath: item.url.path,
                status: .success,
                duration: Date().timeIntervalSince(startTime),
                note: "已成功熔合并保存至 macOS 照片图库 (可 iCloud 同步)"
            )

        } catch {
            if Task.isCancelled || error is CancellationError {
                item.status = .pending
                return
            }
            item.status = .failed(error.localizedDescription)
            OperationHistoryManager.shared.record(
                source: .localStudio,
                platform: "本地",
                title: "制作实况图导入相册失败: \(base)",
                originalURLOrPath: item.url.path,
                status: .failed,
                duration: Date().timeIntervalSince(startTime),
                note: error.localizedDescription
            )
        }
    }

    @MainActor
    private static func validateInput(_ item: VideoItem) throws {
        guard !item.isLoadingMetadata, item.duration.isFinite, item.duration > 0,
              FileManager.default.isReadableFile(atPath: item.url.path) else {
            throw ConversionError.invalidVideo
        }
        _ = try validatedEditRange(duration: item.duration, startTime: item.startTime, endTime: item.endTime, speed: item.playbackSpeed)
        guard item.startTime.isFinite, item.endTime.isFinite, item.coverTime.isFinite,
              item.startTime >= 0, item.endTime > item.startTime,
              item.endTime <= item.duration,
              item.coverTime >= item.startTime, item.coverTime < item.endTime else {
            throw ConversionError.invalidEditRange
        }
    }

    /// GUI、CLI 与 GIF 共用参数校验，避免无效数值进入媒体框架或转换为整数时崩溃。
    static func validatedEditRange(duration: Double, startTime: Double, endTime: Double, speed: Float) throws -> (Double, Double) {
        guard duration.isFinite, duration > 0 else { throw ConversionError.invalidVideo }
        guard speed.isFinite, speed > 0 else { throw ConversionError.invalidPlaybackSpeed }
        let end = endTime == 0 ? duration : endTime
        guard startTime.isFinite, end.isFinite, startTime >= 0,
              end > startTime, end <= duration else { throw ConversionError.invalidEditRange }
        return (startTime, end)
    }

    /// 始终保留已有文件和原视频；同名输出使用成对的编号。
    static func exportPair(imageURL: URL, videoURL: URL, to directory: URL, basename: String) throws -> [URL] {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        var counter = 0
        var outputs: [URL]
        repeat {
            let name = counter == 0 ? basename : "\(basename)_\(counter)"
            outputs = [directory.appendingPathComponent(name + ".jpg"), directory.appendingPathComponent(name + ".mov")]
            counter += 1
        } while outputs.contains(where: { fm.fileExists(atPath: $0.path) })
        var created: [URL] = []
        do {
            for (source, destination) in zip([imageURL, videoURL], outputs) {
                try fm.copyItem(at: source, to: destination)
                created.append(destination)
                let size = (try fm.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value ?? 0
                guard size > 0 else { throw ConversionError.outputMissing }
            }
            return outputs
        } catch {
            for url in created { try? fm.removeItem(at: url) }
            throw error
        }
    }

    // ──────── 批量处理 ────────
    @MainActor
    static func processBatch(_ items: [VideoItem], type: ConversionType = .livePhoto) async {
        for item in items where item.canConvert {
            if Task.isCancelled { break }
            guard item.status != .completed else { continue }
            await processVideo(item, type: type)
        }
    }
}
