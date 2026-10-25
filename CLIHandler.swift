import Foundation
import AVFoundation
import Photos

private final class CLIExitCodeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int32 = 1

    func set(_ newValue: Int32) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    func get() -> Int32 {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

/// CLI 模式处理器
/// 用法:
///   cduyzh-media video1.mp4 video2.mp4              → 直接导入系统相册
///   cduyzh-media -o ./output video1.mp4 video2.mp4   → 输出到指定目录
///   cduyzh-media --frame-time 1.5 video.mp4          → 指定封面帧
///   cduyzh-media -o ./out --import video.mp4          → 同时输出文件 + 导入相册
class CLIHandler {

    static func run(_ rawArgs: [String]) {
        var outputDir: String?
        var frameTime: Double = 0
        var startTime: Double = 0
        var endTime: Double = 0
        var speed: Float = 1.0
        var forceImport = false
        var asGIF = false
        var downloadOnly = false
        var shouldRemoveWatermark = AppSettings.shared.removeWatermark
        var videoQuality: VideoQualityOption = AppSettings.shared.defaultVideoQuality
        var videoFiles: [String] = []

        // ── 解析参数 ──
        var i = 0
        while i < rawArgs.count {
            switch rawArgs[i] {
            case "-o", "--output":
                i += 1
                guard i < rawArgs.count else { die("缺少输出目录参数") }
                outputDir = rawArgs[i]
            case "-q", "--quality", "--resolution":
                i += 1
                guard i < rawArgs.count else { die("缺少清晰度参数，可选: 1080p, 720p, 480p, 360p") }
                guard let q = VideoQualityOption.match(rawArgs[i]) else {
                    die("不支持的清晰度: \(rawArgs[i])，可选: 1080p, 720p, 480p, 360p")
                }
                videoQuality = q
            case "-d", "--download", "--download-only":
                downloadOnly = true
            case "--delogo", "--remove-watermark":
                shouldRemoveWatermark = true
            case "--no-delogo", "--keep-watermark":
                shouldRemoveWatermark = false
            case "--import":
                forceImport = true
            case "--gif":
                asGIF = true
            case "--frame-time":
                i += 1
                guard i < rawArgs.count, let t = Double(rawArgs[i]) else {
                    die("缺少或无效的封面帧时间参数")
                }
                frameTime = t
            case "--start":
                i += 1
                guard i < rawArgs.count, let t = Double(rawArgs[i]) else { die("缺少或无效的 --start 参数") }
                startTime = t
            case "--end":
                i += 1
                guard i < rawArgs.count, let t = Double(rawArgs[i]) else { die("缺少或无效的 --end 参数") }
                endTime = t
            case "--speed":
                i += 1
                guard i < rawArgs.count, let t = Float(rawArgs[i]) else { die("缺少或无效的 --speed 参数") }
                speed = t
            case "-h", "--help":
                printUsage(); exit(0)
            case "-v", "--version":
                print("MediaSaver \(AppMetadata.shortVersion ?? "development") (\(AppMetadata.build ?? "unknown"))")
                exit(0)
            case "-u", "--check-update", "--update":
                print("正在连接 GitHub 检查最新版本…")
                let sema = DispatchSemaphore(value: 0)
                Task {
                    defer { sema.signal() }
                    do {
                        let release = try await UpdateChecker.fetchLatestRelease()
                        let current = UpdateChecker.currentAppVersion
                        if UpdateChecker.isRemoteVersion(release.tagName, newerThan: current) {
                            print("\n🎉 发现新版本：\(release.displayTitle)")
                            if let notes = release.body, !notes.isEmpty {
                                print("\n📝 更新说明:\n\(notes)")
                            }
                            if let dmg = release.dmgAssetURL {
                                print("\n📦 DMG 安装包下载: \(dmg)")
                            }
                            print("🔗 GitHub 地址: \(release.htmlURL)")
                        } else if UpdateChecker.isRemoteVersion(current, newerThan: release.tagName) {
                            print("⚠️ 本机版本 \(current) 高于 GitHub 最新 Release \(release.tagName)，本机版本尚未发布。")
                            print("🔗 GitHub Release: \(release.htmlURL)")
                        } else {
                            print("✅ 当前已是最新版本 (v\(current))")
                        }
                    } catch {
                        print("❌ 检查更新失败: \(error.localizedDescription)")
                    }
                }
                sema.wait()
                exit(0)
            default:
                if rawArgs[i].hasPrefix("-") {
                    die("未知参数: \(rawArgs[i])")
                }
                videoFiles.append(rawArgs[i])
            }
            i += 1
        }

        guard !videoFiles.isEmpty else {
            die("请提供至少一个视频文件路径")
        }
        guard frameTime.isFinite, frameTime >= 0, startTime.isFinite, startTime >= 0,
              endTime.isFinite, endTime >= 0, endTime == 0 || endTime > startTime else {
            die("封面和裁剪时间必须是有效的非负秒数，结束时间必须晚于起点")
        }
        guard speed.isFinite, speed > 0 else { die("--speed 必须为大于零的有效倍数") }
        if let dir = outputDir {
            outputDir = URL(fileURLWithPath: (dir as NSString).expandingTildeInPath).standardizedFileURL.path
        }

        // 未指定 -o 时，且非 GIF 模式，默认导入相册
        let shouldImport = !downloadOnly && (forceImport || (outputDir == nil && !asGIF))

        // Freeze parsed options before handing them to the asynchronous task.
        let inputFiles = videoFiles
        let outputDirectory = outputDir
        let downloadOnlyMode = downloadOnly
        let removeWatermark = shouldRemoveWatermark
        let networkQuality = videoQuality
        let gifMode = asGIF
        let coverFrameTime = frameTime
        let editStartTime = startTime
        let editEndTime = endTime
        let playbackSpeed = speed

        // ── 异步执行 ──
        let sema = DispatchSemaphore(value: 0)
        let exitCode = CLIExitCodeBox()
        Task {
            defer { sema.signal() }

            var successCount = 0
            var failCount = 0

            for input in inputFiles {
                let path = input.range(of: #"^BV[A-Za-z0-9]{10}$"#, options: .regularExpression) != nil
                    ? "https://www.bilibili.com/video/" + input : input
                var url: URL
                
                // 判断是否是网络链接 (以 http 开头)
                if path.lowercased().hasPrefix("http") {
                    print("\n🌐 发现网络链接，准备解析下载: \(path)")
                    do {
                        let platform = PlatformCategory.detect(from: path)
                        let targetDirURL: URL
                        if let dir = outputDirectory {
                            targetDirURL = URL(fileURLWithPath: (dir as NSString).expandingTildeInPath)
                        } else {
                            targetDirURL = CategorizedStorageManager.categoryDirectory(platform: platform, category: .video)
                        }
                        CategorizedStorageManager.ensureDirectory(at: targetDirURL)

                        url = try await NetworkVideoDownloader.downloadVideo(
                            url: path,
                            targetDirectory: targetDirURL,
                            videoOutputDir: targetDirURL,
                            shouldRemoveWatermark: removeWatermark,
                            quality: networkQuality
                        ) { progress in
                            print("  \(progress)")
                        }
                        
                        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
                        print("  ✅ 下载完成: \(url.path) (\(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)))")

                        if downloadOnlyMode {
                            successCount += 1
                            continue
                        }
                    } catch {
                        printErr("下载失败: \(error.localizedDescription)")
                        failCount += 1
                        continue
                    }
                } else {
                    guard !downloadOnlyMode else {
                        printErr("--download 仅适用于网络链接：\(path)")
                        failCount += 1
                        continue
                    }
                    url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
                    guard FileManager.default.fileExists(atPath: url.path) else {
                        printErr("文件不存在: \(path)")
                        failCount += 1
                        continue
                    }
                }

                let base = url.deletingPathExtension().lastPathComponent
                print("\n📹 处理: \(url.lastPathComponent)")

                do {
                    let asset = AVURLAsset(url: url)
                    let duration = CMTimeGetSeconds(try await asset.load(.duration))
                    let (_, end) = try ConversionEngine.validatedEditRange(duration: duration, startTime: editStartTime, endTime: editEndTime, speed: playbackSpeed)
                    if !gifMode && coverFrameTime >= end - editStartTime { throw ConversionError.invalidEditRange }
                    if gifMode {
                        print("  [1/1] 转换为优化版 GIF (start:\(editStartTime) end:\(editEndTime) speed:\(playbackSpeed))…")
                        let outDir = outputDirectory ?? FileManager.default.currentDirectoryPath
                        let fm = FileManager.default
                        if !fm.fileExists(atPath: outDir) {
                            try fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)
                        }
                        let destGIF = CategorizedStorageManager.resolveDestination(in: URL(fileURLWithPath: outDir), filename: base + ".gif", policy: .rename).destinationURL
                        
                        try await GIFConverter.convertToGIF(
                            videoURL: url,
                            outputURL: destGIF,
                            startTime: editStartTime,
                            endTime: editEndTime,
                            speed: playbackSpeed
                        )
                        let gifSize = (try? fm.attributesOfItem(atPath: destGIF.path)[.size] as? Int64) ?? 0
                        print("  ✅ 已输出 GIF: \(destGIF.path) (\(ByteCountFormatter.string(fromByteCount: gifSize, countStyle: .file)))")
                    } else {
                        let assetID = UUID().uuidString
                        var temporaryFiles: [URL] = []
                        defer { for file in temporaryFiles { try? FileManager.default.removeItem(at: file) } }

                        // Step 1: 提取封面帧
                        print("  [1/3] 提取封面帧 (t=\(coverFrameTime)s)…")
                        let frameURL = try await ConversionEngine.extractFrame(from: url, at: editStartTime + coverFrameTime, assetIdentifier: assetID)
                        temporaryFiles.append(frameURL)

                        // Step 2: 转封装/裁剪/变速为 MOV
                        print("  [2/3] 转换为 MOV 容器 (start:\(editStartTime) end:\(editEndTime) speed:\(playbackSpeed))…")
                        let movURL = try await ConversionEngine.convertToMOV(input: url, startTime: editStartTime, endTime: editEndTime, speed: playbackSpeed, assetIdentifier: assetID)
                        temporaryFiles.append(movURL)

                        // Step 3a: 输出到目录
                        if let dir = outputDirectory {
                            let fm = FileManager.default
                            try fm.createDirectory(
                                atPath: dir, withIntermediateDirectories: true, attributes: nil
                            )
                            let destDir = URL(fileURLWithPath: dir)
                            let outputs = try ConversionEngine.exportPair(imageURL: frameURL, videoURL: movURL, to: destDir, basename: base)
                            let destJPG = outputs[0]
                            let destMOV = outputs[1]

                            let jpgSize = (try? fm.attributesOfItem(atPath: destJPG.path)[.size] as? Int64) ?? 0
                            let movSize = (try? fm.attributesOfItem(atPath: destMOV.path)[.size] as? Int64) ?? 0
                            print("  📁 已输出到 \(dir)/")
                            print("     \(destJPG.lastPathComponent)  (\(ByteCountFormatter.string(fromByteCount: jpgSize, countStyle: .file)))")
                            print("     \(destMOV.lastPathComponent)  (\(ByteCountFormatter.string(fromByteCount: movSize, countStyle: .file)))")
                        }

                        // Step 3b: 导入系统相册
                        if shouldImport {
                            print("  [3/3] 导入系统相册…")
                            try await ConversionEngine.importToPhotos(imageURL: frameURL, videoURL: movURL)
                            print("  ✅ 已导入系统相册（iCloud 将自动同步到 iPhone）")
                        } else {
                            print("  ✅ 完成")
                        }

                    }

                    successCount += 1

                } catch {
                    printErr("  ❌ 失败: \(error.localizedDescription)")
                    failCount += 1
                }
            }

            // 汇总
            print("\n══════════════════════════════════")
            print("全部完成！成功 \(successCount) 个，失败 \(failCount) 个")
            if shouldImport && successCount > 0 && !gifMode {
                print("💡 打开「照片」App 即可查看，iCloud 同步后手机上也会出现")
            }
            exitCode.set(failCount == 0 ? 0 : 1)
        }

        sema.wait()
        exit(exitCode.get())
    }

    // MARK: - 帮助信息
    private static func printUsage() {
        let help = """
        
        ╔══════════════════════════════════════════════════════════╗
        ║  MediaSaver — 全能媒体提取·实况制作·动图工坊       ║
        ╚══════════════════════════════════════════════════════════╝

        用法:
          cduyzh-media [选项] <视频文件...>

        选项:
          -o, --output <目录>     输出 .jpg + .mov、.mp4 或 .gif 文件到指定目录
          -q, --quality <清晰度>  指定网络视频下载清晰度 (1080p, 720p, 480p, 360p，默认 1080p，系统封顶 1080p)
          -d, --download          只下载网络视频到本地分类目录或指定目录，不转换为实况图
          --delogo                强制执行智能消除水印 (Mac 硬件加速 + 多层容错兜底)
          --no-delogo             跳过水印消除，完整保留原始流
          --import                导入到系统相册（不指定 -o 时且为实况图模式时为默认行为）
          --gif                   转换为优化版 GIF，适合微信公众号使用
          --frame-time <秒>       封面帧时间点（相对起始时间，默认 0）
          --start <秒>            裁剪视频的起始时间（默认 0）
          --end <秒>              裁剪视频的结束时间（默认 0 即不裁剪）
          --speed <倍数>          视频变速（如 1.5, 2.0，默认 1.0）
          -u, --check-update      检查 GitHub Releases 最新版本与更新说明
          -h, --help              显示本帮助
          -v, --version           显示当前应用版本与构建号

        示例:
          cduyzh-media video.mp4
              → 直接将视频作为实况图导入系统相册

          cduyzh-media -d "https://www.bilibili.com/video/BV1HKaR6zEKh"
              → 解析并下载 B站 1080P60 视频到本地规整分类目录

          cduyzh-media -d -q 720p "https://www.bilibili.com/video/BV1HKaR6zEKh"
              → 指定以 720P 清晰度解析下载 B站视频

          cduyzh-media --gif video.mp4
              → 将视频转换为适合微信公众号的 GIF，输出在当前目录

          cduyzh-media --start 2.5 --end 5.0 --speed 2.0 video.mp4
              → 裁剪 2.5s 到 5.0s，2 倍速播放，并导入系统相册

          cduyzh-media -o ~/Desktop/livephotos video1.mp4 video2.mp4
              → 批量输出实况图组件到桌面
        
        无参数启动则打开图形界面（GUI 模式）。
        """
        print(help)
    }

    private static func die(_ msg: String) -> Never {
        printErr("错误: \(msg)")
        printErr("使用 -h 查看帮助")
        exit(1)
    }

    private static func printErr(_ msg: String) {
        FileHandle.standardError.write(Data("\(msg)\n".utf8))
    }
}
