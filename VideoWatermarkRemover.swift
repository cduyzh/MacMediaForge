import Foundation
import AVFoundation

// MARK: - 视频去水印引擎 (基于 FFmpeg Delogo 滤镜、多平台自适应与全链路多层容错兜底)
public class VideoWatermarkRemover {

    /// 水印矩形几何区域
    public struct DelogoRect: Sendable {
        public let x: Int
        public let y: Int
        public let w: Int
        public let h: Int

        public var filterString: String {
            "delogo=x=\(x):y=\(y):w=\(w):h=\(h)"
        }
    }

    /// 查找系统中可用的 ffmpeg 与 ffprobe 路径
    public static func locateTool(name: String) -> String? {
        let candidates = [
            NSHomeDirectory() + "/.local/bin/\(name)",
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)"
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    /// 获取视频宽度与高度（优先使用系统原生 AVURLAsset，失败回退到 ffprobe）
    public static func getVideoDimensions(url: URL) async -> (width: Int, height: Int)? {
        // 策略 1: 基于系统底层 AVFoundation（秒级响应且无需外部进程）
        let asset = AVURLAsset(url: url)
        if let tracks = try? await asset.loadTracks(withMediaType: .video),
           let track = tracks.first,
           let naturalSize = try? await track.load(.naturalSize),
           let transform = try? await track.load(.preferredTransform) {
            let transformedSize = naturalSize.applying(transform)
            let w = Int(abs(transformedSize.width))
            let h = Int(abs(transformedSize.height))
            if w > 0 && h > 0 {
                return (w, h)
            }
        }

        // 策略 2: ffprobe 备用解析
        guard let ffprobe = locateTool(name: "ffprobe") else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffprobe)
        process.arguments = [
            "-v", "error",
            "-select_streams", "v:0",
            "-show_entries", "stream=width,height",
            "-of", "csv=p=0",
            url.path
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                let parts = output.components(separatedBy: ",")
                if parts.count >= 2, let w = Int(parts[0]), let h = Int(parts[1]) {
                    return (w, h)
                }
            }
        } catch {
            return nil
        }
        return nil
    }

    /// 获取视频精确时长（秒）
    public static func getVideoDuration(url: URL) async -> Double? {
        let asset = AVURLAsset(url: url)
        if let dur = try? await asset.load(.duration) {
            let s = dur.seconds
            if s > 0 && !s.isNaN && !s.isInfinite {
                return s
            }
        }

        guard let ffprobe = locateTool(name: "ffprobe") else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffprobe)
        process.arguments = [
            "-v", "error",
            "-show_entries", "format=duration",
            "-of", "csv=p=0",
            url.path
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               let val = Double(str) {
                return val
            }
        } catch {
            return nil
        }
        return nil
    }

    /// 根据视频分辨率自适应估算目标视频码率 (kbps)
    public static func estimateBitrate(width: Int, height: Int) -> Int {
        let pixels = Double(width * height)
        let estimated = Int(pixels * 0.005)
        return max(2000, min(35000, estimated))
    }

    /// 根据视频分辨率与平台类型智能计算水印位置与尺寸
    public static func calculateDelogoRect(width: Int, height: Int, platform: PlatformCategory) -> DelogoRect {
        switch platform {
        case .bilibili:
            let isVertical = width < height
            if isVertical {
                // 竖屏 B站 短视频：右上角
                let w = max(32, min(width - 32, Int(Double(width) * 0.32)))
                let h = max(24, min(height - 24, Int(Double(height) * 0.05)))
                let x = max(0, min(width - w, width - w - Int(Double(width) * 0.03)))
                let y = max(0, min(height - h, Int(Double(height) * 0.03)))
                return DelogoRect(x: x, y: y, w: w, h: h)
            } else {
                // 横屏 B站 视频 (如 1920x1080)：右上角 UP主昵称 + bilibili 标志
                // 标定值：1920x1080 下覆盖 x=1528..1888, y=26..104 (w=360, h=78)
                // 预留充分背景采样缓冲区，防止边缘白字污染插值；精准避开右侧菜单按钮与上方网络信号
                let w = max(32, min(width - 32, Int(Double(width) * 0.188)))
                let h = max(24, min(height - 24, Int(Double(height) * 0.073)))
                let x = max(0, min(width - w, width - w - Int(Double(width) * 0.017)))
                let y = max(0, min(height - h, Int(Double(height) * 0.024)))
                return DelogoRect(x: x, y: y, w: w, h: h)
            }

        case .xhs:
            // 小红书常见水印位置：右下角
            let w = max(32, min(width - 32, Int(Double(width) * 0.28)))
            let h = max(24, min(height - 24, Int(Double(height) * 0.08)))
            let x = max(0, width - w - Int(Double(width) * 0.03))
            let y = max(0, height - h - Int(Double(height) * 0.05))
            return DelogoRect(x: x, y: y, w: w, h: h)

        default:
            // 默认右下角
            let w = max(32, min(width - 32, Int(Double(width) * 0.25)))
            let h = max(24, min(height - 24, Int(Double(height) * 0.07)))
            let x = max(0, width - w - Int(Double(width) * 0.03))
            let y = max(0, height - h - Int(Double(height) * 0.04))
            return DelogoRect(x: x, y: y, w: w, h: h)
        }
    }

    /// 校验输出视频文件有效性与完整性
    public static func validateOutputFile(url: URL, minExpectedSize: Int64) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else { return false }
        // 文件大小必须达到基本阈值且不为截断文件
        return size > 50000 && size >= minExpectedSize
    }

    /// 对视频执行智能消除水印（包含硬件加速与多层容错兜底）
    /// - Parameters:
    ///   - inputURL: 输入视频路径
    ///   - outputURL: 输出视频路径
    ///   - platform: 来源平台（决定水印几何区域）
    ///   - trimEnding: 是否截断片尾（如小红书 1.5 秒红薯片尾动画）
    ///   - progressHandler: 进度与状态回调
    /// - Returns: 是否消除成功且输出完整视频
    public static func removeWatermark(
        inputURL: URL,
        outputURL: URL,
        platform: PlatformCategory = .defaultCategory,
        trimEnding: Bool = false,
        progressHandler: ((String) -> Void)? = nil
    ) async -> Bool {
        // 1. 输入文件与工具预检
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            progressHandler?("⚠️ 输入视频文件不存在，跳过去水印处理")
            return false
        }

        let inputAttributes = try? FileManager.default.attributesOfItem(atPath: inputURL.path)
        let inputSize = (inputAttributes?[.size] as? Int64) ?? 0
        guard inputSize > 10240 else {
            progressHandler?("⚠️ 输入视频数据过小或无效，跳过去水印处理")
            return false
        }

        guard let ffmpeg = locateTool(name: "ffmpeg") else {
            progressHandler?("⚠️ 未找到 FFmpeg，跳过高级去水印处理（保留原始高清视频）")
            return false
        }

        guard let (width, height) = await getVideoDimensions(url: inputURL) else {
            progressHandler?("⚠️ 无法解析视频分辨率规格，跳过去水印（保留原始高清视频）")
            return false
        }

        let rect = calculateDelogoRect(width: width, height: height, platform: platform)

        // 2. 片尾截断防护校验：仅当视频总时长 > 4.0 秒时方允许截除，防止短视频内容被误削
        var durationArgs: [String] = []
        if trimEnding {
            if let dur = await getVideoDuration(url: inputURL), dur > 4.0 {
                let targetDur = String(format: "%.2f", dur - 1.5)
                durationArgs = ["-t", targetDur]
                progressHandler?("✂️ 检测到平台片尾，已配置剪除尾部 1.5 秒动画…")
            }
        }

        let minExpectedSize = max(50000, Int64(Double(inputSize) * 0.20))
        let tempOutputURL = outputURL.deletingLastPathComponent().appendingPathComponent("tmp_delogo_\(UUID().uuidString).mp4")
        WorkExecutionManager.shared.registerActiveFile(tempOutputURL)

        defer {
            WorkExecutionManager.shared.unregisterActiveFile(tempOutputURL)
            if FileManager.default.fileExists(atPath: tempOutputURL.path) {
                try? FileManager.default.removeItem(at: tempOutputURL)
            }
        }

        // 3. 执行 Tier 1：Apple Silicon VideoToolbox 硬件加速编码 (极速、低发热、码率自适应)
        progressHandler?("🚀 正在启用 Mac 硬件加速 (VideoToolbox) 消除 [\(platform.rawValue)] 水印 (\(width)x\(height))…")
        let targetBitrate = estimateBitrate(width: width, height: height)

        let tier1Args = [
            "-nostdin",
            "-y",
            "-i", inputURL.path,
            "-vf", rect.filterString
        ] + durationArgs + [
            "-c:v", "h264_videotoolbox",
            "-b:v", "\(targetBitrate)k",
            "-c:a", "copy",
            "-movflags", "+faststart",
            tempOutputURL.path
        ]

        var success = await runFFmpegProcess(executable: ffmpeg, args: tier1Args)
        if success && validateOutputFile(url: tempOutputURL, minExpectedSize: minExpectedSize) {
            try? FileManager.default.removeItem(at: outputURL)
            do {
                try FileManager.default.moveItem(at: tempOutputURL, to: outputURL)
                progressHandler?("✅ [\(platform.rawValue)] 视频水印已通过硬件加速平滑消除！")
                return true
            } catch {
                progressHandler?("⚠️ 替换文件时出错: \(error.localizedDescription)")
            }
        }

        // 4. 执行 Tier 2 兜底：CPU libx264 兼容编码 (高保真 CRF 20)
        progressHandler?("⚠️ 硬件加速处理受限，自动无缝切换至 CPU libx264 兼容编码兜底…")
        try? FileManager.default.removeItem(at: tempOutputURL)

        let tier2Args = [
            "-nostdin",
            "-y",
            "-i", inputURL.path,
            "-vf", rect.filterString
        ] + durationArgs + [
            "-c:v", "libx264",
            "-preset", "fast",
            "-crf", "20",
            "-c:a", "copy",
            "-movflags", "+faststart",
            tempOutputURL.path
        ]

        success = await runFFmpegProcess(executable: ffmpeg, args: tier2Args)
        if success && validateOutputFile(url: tempOutputURL, minExpectedSize: minExpectedSize) {
            try? FileManager.default.removeItem(at: outputURL)
            do {
                try FileManager.default.moveItem(at: tempOutputURL, to: outputURL)
                progressHandler?("✅ [\(platform.rawValue)] 视频水印已通过兼容编码平滑消除！")
                return true
            } catch {
                progressHandler?("⚠️ 替换文件时出错: \(error.localizedDescription)")
            }
        }

        // 5. 执行 Tier 3 兜底：音视频全轨安全重编码（解决偶发音频流直接拷贝不兼容的问题）
        progressHandler?("⚠️ 音频流直拷遇阻，自动切换至音画全轨安全重编码兜底…")
        try? FileManager.default.removeItem(at: tempOutputURL)

        let tier3Args = [
            "-nostdin",
            "-y",
            "-i", inputURL.path,
            "-vf", rect.filterString
        ] + durationArgs + [
            "-c:v", "libx264",
            "-preset", "veryfast",
            "-crf", "22",
            "-c:a", "aac",
            "-b:a", "192k",
            "-movflags", "+faststart",
            tempOutputURL.path
        ]

        success = await runFFmpegProcess(executable: ffmpeg, args: tier3Args)
        if success && validateOutputFile(url: tempOutputURL, minExpectedSize: minExpectedSize) {
            try? FileManager.default.removeItem(at: outputURL)
            do {
                try FileManager.default.moveItem(at: tempOutputURL, to: outputURL)
                progressHandler?("✅ [\(platform.rawValue)] 视频水印已通过全轨安全编码消除！")
                return true
            } catch {
                progressHandler?("⚠️ 替换文件时出错: \(error.localizedDescription)")
            }
        }

        // 6. 终极保护兜底：若所有去水印通道均失败，完整保留原始文件，绝不截断或损坏用户视频
        progressHandler?("⚠️ 水印消除未能完成，已启用零损坏兜底机制，完整保留原始高质量视频")
        return false
    }

    /// 封装 Process 调用与进程托管，杜绝后台任务挂起
    private static func runFFmpegProcess(executable: String, args: [String]) async -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args

        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = Pipe()
        process.standardInput = Pipe() // 明确重定向标准输入，杜绝 SIGTTIN 挂起

        let procToken = WorkExecutionManager.shared.registerProcess(process)

        return await withCheckedContinuation { continuation in
            do {
                try process.run()
                process.waitUntilExit()
                WorkExecutionManager.shared.unregisterProcess(id: procToken)
                continuation.resume(returning: process.terminationStatus == 0)
            } catch {
                WorkExecutionManager.shared.unregisterProcess(id: procToken)
                continuation.resume(returning: false)
            }
        }
    }
}
