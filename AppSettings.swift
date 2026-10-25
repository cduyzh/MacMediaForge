import Foundation
import SwiftUI

// MARK: - 文件冲突与去重策略
public enum DuplicatePolicy: String, CaseIterable, Identifiable {
    case overwrite = "overwrite"
    case skip = "skip"
    case rename = "rename"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .overwrite: return "直接覆盖 (推荐)"
        case .skip: return "跳过下载 (已有时跳过)"
        case .rename: return "自动重命名 (添加序号)"
        }
    }

    public var desc: String {
        switch self {
        case .overwrite: return "检测到本地已有同名视频时，重新下载并替换为最新内容"
        case .skip: return "检测到本地已有同名视频时，直接复用本地文件，节省流量与时间"
        case .rename: return "检测到同名文件时保留原文件，新建名称如 video_1.mp4 保存"
        }
    }
}

// MARK: - 全局系统偏好设置管理器
public class AppSettings: ObservableObject {
    public static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    // 键名定义
    private let kDuplicatePolicy = "lpf_duplicate_policy"
    private let kDownloadDir = "lpf_download_dir"
    private let kRemoveWatermark = "lpf_remove_watermark"
    private let kTrimEnding = "lpf_trim_ending"
    private let kLivePhotoFPS = "lpf_live_photo_fps"
    private let kAutoImportPhotos = "lpf_auto_import_photos"
    
    // 新增设置项键名
    private let kMaxConcurrentDownloads = "lpf_max_concurrent_downloads"
    private let kGenerateGIF = "lpf_generate_gif"
    private let kSaveToLocal = "lpf_save_to_local"
    private let kConvertToLivePhoto = "lpf_convert_to_live_photo"
    private let kExportMarkdown = "lpf_export_markdown"
    private let kEnableClassifiedFolders = "lpf_enable_classified_folders"
    private let kAutoCheckUpdates = "lpf_auto_check_updates"
    private let kGitHubToken = "lpf_github_token"
    private let kKeepRunningInMenuBar = "lpf_keep_running_in_menu_bar"
    private let kDefaultVideoQuality = "lpf_default_video_quality"

    /// Keep the workspace alive when its window is closed.
    @Published public var keepRunningInMenuBar: Bool {
        didSet { defaults.set(keepRunningInMenuBar, forKey: kKeepRunningInMenuBar) }
    }

    // MARK: - 清晰度偏好 (支持多清晰度选择，至少包含 3 个清晰度，1080P 为系统最大上限)
    @Published public var defaultVideoQuality: VideoQualityOption {
        didSet { defaults.set(defaultVideoQuality.rawValue, forKey: kDefaultVideoQuality) }
    }

    // MARK: - 存储与基础
    @Published public var duplicatePolicy: DuplicatePolicy {
        didSet { defaults.set(duplicatePolicy.rawValue, forKey: kDuplicatePolicy) }
    }

    @Published public var downloadDirectory: String {
        didSet {
            defaults.set(downloadDirectory, forKey: kDownloadDir)
            try? FileManager.default.createDirectory(atPath: downloadDirectory, withIntermediateDirectories: true, attributes: nil)
        }
    }

    /// 是否开启平台与日期四层分类归类（推特/小红书/默认 -> 26年10月14日 -> 视频/实况/GIF/文档）
    @Published public var enableClassifiedFolders: Bool {
        didSet { defaults.set(enableClassifiedFolders, forKey: kEnableClassifiedFolders) }
    }

    // MARK: - 并发性能控制
    @Published public var maxConcurrentDownloads: Int {
        didSet { defaults.set(maxConcurrentDownloads, forKey: kMaxConcurrentDownloads) }
    }

    // MARK: - 页面提取选项联动 (动态联动管理)
    @Published public var saveToLocal: Bool {
        didSet { defaults.set(saveToLocal, forKey: kSaveToLocal) }
    }

    @Published public var convertToLivePhoto: Bool {
        didSet { defaults.set(convertToLivePhoto, forKey: kConvertToLivePhoto) }
    }

    /// 生成 GIF 动图（用户要求：做成可选项，默认不生成）
    @Published public var generateGIF: Bool {
        didSet { defaults.set(generateGIF, forKey: kGenerateGIF) }
    }

    @Published public var exportMarkdown: Bool {
        didSet { defaults.set(exportMarkdown, forKey: kExportMarkdown) }
    }

    // MARK: - 画质与处理偏好
    @Published public var removeWatermark: Bool {
        didSet { defaults.set(removeWatermark, forKey: kRemoveWatermark) }
    }

    @Published public var trimEnding: Bool {
        didSet { defaults.set(trimEnding, forKey: kTrimEnding) }
    }

    @Published public var livePhotoFPS: Int {
        didSet { defaults.set(livePhotoFPS, forKey: kLivePhotoFPS) }
    }

    @Published public var autoImportPhotos: Bool {
        didSet { defaults.set(autoImportPhotos, forKey: kAutoImportPhotos) }
    }

    // MARK: - 软件更新配置
    /// 是否在启动时自动静默检查更新
    @Published public var autoCheckUpdates: Bool {
        didSet { defaults.set(autoCheckUpdates, forKey: kAutoCheckUpdates) }
    }

    /// 自定义 GitHub 个人访问令牌（用于直接访问私有仓库 Release，本机若有 gh 工具可留空）
    @Published public var githubToken: String {
        didSet { defaults.set(githubToken, forKey: kGitHubToken) }
    }

    private init() {
        self.keepRunningInMenuBar = defaults.object(forKey: kKeepRunningInMenuBar) == nil
            ? true : defaults.bool(forKey: kKeepRunningInMenuBar)

        // 1. 去重策略：默认直接覆盖 (overwrite)
        let savedPolicyStr = defaults.string(forKey: kDuplicatePolicy) ?? DuplicatePolicy.overwrite.rawValue
        self.duplicatePolicy = DuplicatePolicy(rawValue: savedPolicyStr) ?? .overwrite

        // 2. 默认下载目录：与产品名称对应，默认为 ~/Downloads/cduyzhMediaForge
        let productDefaultPath = (NSHomeDirectory() as NSString).appendingPathComponent("Downloads/cduyzhMediaForge")
        let legacyLivePhotoForgePath = (NSHomeDirectory() as NSString).appendingPathComponent("Downloads/LivePhotoForge")

        // 若存在旧的 ~/Downloads/LivePhotoForge 且新目录尚不存在，平滑重命名迁移
        if FileManager.default.fileExists(atPath: legacyLivePhotoForgePath) && !FileManager.default.fileExists(atPath: productDefaultPath) {
            try? FileManager.default.moveItem(atPath: legacyLivePhotoForgePath, toPath: productDefaultPath)
        }

        var savedPath = defaults.string(forKey: kDownloadDir) ?? productDefaultPath
        // 自动从旧的 XHS_Videos 或 LivePhotoForge 路径平滑升级迁移到与产品名称一致的 cduyzhMediaForge
        if savedPath.hasSuffix("Downloads/XHS_Videos") || savedPath.hasSuffix("Downloads/LivePhotoForge") {
            savedPath = productDefaultPath
        }
        self.downloadDirectory = savedPath
        try? FileManager.default.createDirectory(atPath: savedPath, withIntermediateDirectories: true, attributes: nil)

        // 3. 结构化四分类：默认开启
        if defaults.object(forKey: kEnableClassifiedFolders) == nil {
            self.enableClassifiedFolders = true
        } else {
            self.enableClassifiedFolders = defaults.bool(forKey: kEnableClassifiedFolders)
        }

        // 4. 并发下载数：默认 3 (范围 1~10)
        let savedConcurrency = defaults.integer(forKey: kMaxConcurrentDownloads)
        self.maxConcurrentDownloads = savedConcurrency > 0 ? min(10, max(1, savedConcurrency)) : 3

        // 5. 保存视频到本地：默认开启
        if defaults.object(forKey: kSaveToLocal) == nil {
            self.saveToLocal = true
        } else {
            self.saveToLocal = defaults.bool(forKey: kSaveToLocal)
        }

        // 6. 自动转为实况图：默认关闭
        self.convertToLivePhoto = defaults.bool(forKey: kConvertToLivePhoto)

        // 7. 生成 GIF 动图：核心需求，默认不生成 (false)
        self.generateGIF = defaults.bool(forKey: kGenerateGIF)

        // 8. 导出推特/长文 Markdown 摘要：默认开启
        if defaults.object(forKey: kExportMarkdown) == nil {
            self.exportMarkdown = true
        } else {
            self.exportMarkdown = defaults.bool(forKey: kExportMarkdown)
        }

        // 9. 去水印默认开启
        if defaults.object(forKey: kRemoveWatermark) == nil {
            self.removeWatermark = true
        } else {
            self.removeWatermark = defaults.bool(forKey: kRemoveWatermark)
        }

        // 10. 去片尾默认关闭
        self.trimEnding = defaults.bool(forKey: kTrimEnding)

        // 11. 实况帧率默认 30
        let savedFPS = defaults.integer(forKey: kLivePhotoFPS)
        self.livePhotoFPS = savedFPS > 0 ? savedFPS : 30

        // 12. 默认导入相册
        if defaults.object(forKey: kAutoImportPhotos) == nil {
            self.autoImportPhotos = true
        } else {
            self.autoImportPhotos = defaults.bool(forKey: kAutoImportPhotos)
        }

        // 13. 启动自动检查更新：默认开启
        if defaults.object(forKey: kAutoCheckUpdates) == nil {
            self.autoCheckUpdates = true
        } else {
            self.autoCheckUpdates = defaults.bool(forKey: kAutoCheckUpdates)
        }

        // 14. GitHub 访问令牌（默认为空）
        self.githubToken = defaults.string(forKey: kGitHubToken) ?? ""

        // 15. 默认下载清晰度：默认为 1080P (最大清晰度)
        let savedQualityStr = defaults.string(forKey: kDefaultVideoQuality) ?? VideoQualityOption.defaultQuality.rawValue
        self.defaultVideoQuality = VideoQualityOption(rawValue: savedQualityStr) ?? .p1080
    }

    public var downloadURL: URL {
        URL(fileURLWithPath: downloadDirectory)
    }

    /// 弹出面板选择自定义保存目录
    public func promptChooseDownloadDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择保存目录"
        panel.directoryURL = downloadURL

        if panel.runModal() == .OK, let url = panel.url {
            self.downloadDirectory = url.path
        }
    }
}
