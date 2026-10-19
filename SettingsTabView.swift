import SwiftUI
import AppKit

public enum SettingsSubTab: String, CaseIterable, Identifiable {
    case general = "偏好设置"
    case history = "操作历史"
    case changelog = "更新日志"
    case storage = "缓存与空间"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .history: return "clock.arrow.circlepath"
        case .changelog: return "rectangle.stack"
        case .storage: return "internaldrive"
        }
    }
}

public struct SettingsTabView: View {
    var isProcessing = false
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var cacheManager = DownloadCacheManager.shared

    @State private var currentSubTab: SettingsSubTab = .general
    @State private var showClearAlert = false
    @State private var toastMessage: String?
    @State private var toastIsWarning = false
    @State private var toastID = UUID()

    public init(isProcessing: Bool = false) { self.isProcessing = isProcessing }

    public var body: some View {
        VStack(spacing: 0) {
            settingsHeaderBar
            Divider()

            if isProcessing {
                ForgeStatusBanner(title: "任务进行中", message: "完成后可修改处理偏好或清理缓存。", systemImage: "info.circle", tint: .secondary)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
            }

            if let message = toastMessage {
                ForgeStatusBanner(
                    title: message,
                    systemImage: toastIsWarning ? "exclamationmark.circle" : "checkmark.circle",
                    tint: toastIsWarning ? .orange : .green
                )
                .padding(.horizontal, 24)
                .padding(.top, 16)
            }

            Group {
                switch currentSubTab {
                case .general:
                    generalPreferencesTab
                        .disabled(isProcessing)
                case .history:
                    OperationHistoryView()
                case .changelog:
                    ChangelogView()
                case .storage:
                    storageAndCacheTab
                        .disabled(isProcessing)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .alert(isPresented: $showClearAlert) {
            Alert(
                title: Text("清除受管文件与缓存？"),
                message: Text("将删除应用受管的下载文件、历史下载文件和转换临时文件，已导入「照片」的实况不受影响。此操作无法撤销，请先保留需要的文件。"),
                primaryButton: .destructive(Text("清除受管文件")) {
                    let result = cacheManager.clearAllCache()
                    let freed = ByteCountFormatter.string(fromByteCount: result.freedBytes, countStyle: .file)
                    if cacheManager.lastCleanupFailureCount > 0 {
                        showToast("已清除 \(result.deletedCount) 个文件，另有 \(cacheManager.lastCleanupFailureCount) 个文件未能清除。", warning: true)
                    } else {
                        showToast("已清除 \(result.deletedCount) 个文件，释放 \(freed)。")
                    }
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
    }

    private var settingsHeaderBar: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("设置")
                        .font(.system(size: 24, weight: .semibold))
                    Text("按你的习惯，安排每一次制作与下载。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(ReleaseLogData.currentVersion)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Picker("设置分类", selection: $currentSubTab) {
                ForEach(SettingsSubTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 540)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
    }

    private var generalPreferencesTab: some View {
        ScrollView {
            VStack(spacing: 20) {
                ForgeInstallationCard()
                classifiedStorageSection
                concurrencyPerformanceSection
                extractorOptionsDynamicSection
                duplicatePolicySection
                watermarkSection
                livePhotoPreferencesSection
            }
            .frame(maxWidth: 900)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - 下载与文件

    private var classifiedStorageSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsSectionHeading(
                title: "下载位置",
                subtitle: "按平台、日期与媒体类型归类保存。",
                systemImage: "folder"
            )

            HStack(spacing: 12) {
                Image(systemName: "folder")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(URL(fileURLWithPath: settings.downloadDirectory).lastPathComponent)
                        .font(.system(size: 13, weight: .medium))
                    Text(settings.downloadDirectory)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(settings.downloadDirectory)
                }
                Spacer(minLength: 12)
                Button("更改…") {
                    settings.promptChooseDownloadDirectory()
                }
                .buttonStyle(.bordered)
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: settings.downloadDirectory)])
                } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(ForgeIconButtonStyle())
                .help("在访达中显示下载目录")
                .accessibilityLabel("在访达中显示下载目录")
            }

            Divider()

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: 16)], alignment: .leading, spacing: 14) {
                categoryDescription(.video, detail: "MP4 视频")
                categoryDescription(.livePhoto, detail: "JPG 与 MOV 配对文件")
                categoryDescription(.gif, detail: "GIF 动图")
                categoryDescription(.document, detail: "Markdown 文档")
            }

            HStack(spacing: 10) {
                Text("今日文件夹")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Button("小红书") { CategorizedStorageManager.openInFinder(platform: .xhs) }
                Button("哔哩哔哩") { CategorizedStorageManager.openInFinder(platform: .bilibili) }
                Button("推特") { CategorizedStorageManager.openInFinder(platform: .twitter) }
                Button("默认分类") { CategorizedStorageManager.openInFinder(platform: .defaultCategory) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(20)
        .forgeSurface()
    }

    private func categoryDescription(_ category: MediaCategory, detail: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: category.icon)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 4) {
                Text(category.rawValue)
                    .font(.system(size: 12, weight: .medium))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var concurrencyPerformanceSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsSectionHeading(title: "下载并发", subtitle: "设置同时下载的任务数量。", systemImage: "arrow.down.circle")

            HStack(spacing: 16) {
                Text("同时下载")
                    .font(.system(size: 13))
                Slider(
                    value: Binding(
                        get: { Double(settings.maxConcurrentDownloads) },
                        set: { settings.maxConcurrentDownloads = Int($0) }
                    ),
                    in: 1...10,
                    step: 1
                )
                .accessibilityLabel("同时下载任务数")
                .accessibilityValue("\(settings.maxConcurrentDownloads) 个任务")
                Text("\(settings.maxConcurrentDownloads)")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .frame(width: 22)
                Stepper("同时下载任务数", value: $settings.maxConcurrentDownloads, in: 1...10)
                    .labelsHidden()
            }

            Text("建议选择 3–5 个任务。网络不稳定时，可降低并发数。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .forgeSurface()
    }

    private var extractorOptionsDynamicSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsSectionHeading(title: "网络提取", subtitle: "与网络提取页面的选项实时同步。", systemImage: "slider.horizontal.3")

            preferenceToggle("保存视频", detail: "下载原视频，保存至「视频」文件夹。", isOn: $settings.saveToLocal)
            Divider()
            preferenceToggle("转换为实况照片", detail: "生成配对的 JPG 封面与 MOV 视频。", isOn: $settings.convertToLivePhoto)
            Divider()
            preferenceToggle("生成 GIF", detail: "额外生成适合微信公众号使用的 GIF 动图。", isOn: $settings.generateGIF)
            Divider()
            preferenceToggle("导出推特 Markdown 摘要", detail: "保存帖子正文、作者、互动数据与视频列表。", isOn: $settings.exportMarkdown)
        }
        .padding(20)
        .forgeSurface()
    }

    private var duplicatePolicySection: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsSectionHeading(title: "同名文件", subtitle: "目标文件夹中已有同名文件时的处理方式。", systemImage: "doc.on.doc")

            Picker("处理方式", selection: $settings.duplicatePolicy) {
                ForEach(DuplicatePolicy.allCases) { policy in
                    Text(duplicatePolicyTitle(policy)).tag(policy)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            Text(settings.duplicatePolicy.desc)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .forgeSurface()
    }

    private func duplicatePolicyTitle(_ policy: DuplicatePolicy) -> String {
        switch policy {
        case .overwrite: return "替换已有文件"
        case .skip: return "跳过已有文件"
        case .rename: return "保留两者，自动重命名"
        }
    }

    private var watermarkSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsSectionHeading(title: "视频处理", systemImage: "wand.and.stars")
            preferenceToggle("淡化平台水印", detail: "使用 FFmpeg 处理视频角落的水印区域，效果取决于原始画面。", isOn: $settings.removeWatermark)
            Divider()
            preferenceToggle("裁剪小红书片尾", detail: "移除视频末尾 1.5 秒，请根据原始视频内容选择。", isOn: $settings.trimEnding)
        }
        .padding(20)
        .forgeSurface()
    }

    private var livePhotoPreferencesSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsSectionHeading(title: "实况照片", systemImage: "livephoto")
            HStack {
                Text("导出帧率")
                    .font(.system(size: 13))
                Spacer()
                Picker("导出帧率", selection: $settings.livePhotoFPS) {
                    Text("30 FPS").tag(30)
                    Text("60 FPS").tag(60)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 190)
            }
            Divider()
            preferenceToggle("自动导入「照片」", detail: "制作完成后导入 macOS 照片图库，方便查看与隔空投送。", isOn: $settings.autoImportPhotos)
        }
        .padding(20)
        .forgeSurface()
    }

    private func settingsSectionHeading(title: String, subtitle: String? = nil, systemImage: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 19)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func preferenceToggle(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    // MARK: - 存储维护

    private var storageAndCacheTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        settingsSectionHeading(title: "存储空间", subtitle: "应用管理的下载文件与转换缓存。", systemImage: "internaldrive")
                        Spacer()
                        Button {
                            cacheManager.refreshStats()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(ForgeIconButtonStyle())
                        .help("刷新存储统计")
                        .accessibilityLabel("刷新存储统计")
                        .disabled(cacheManager.isRefreshing)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(cacheManager.isRefreshing ? "正在统计…" : cacheManager.formattedTotalSize)
                            .font(.system(size: 34, weight: .light, design: .rounded))
                            .monospacedDigit()
                        Text(cacheManager.isRefreshing ? "正在读取受管目录" : "\(cacheManager.totalFileCount) 个受管文件")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    if cacheManager.statsReadIsSlow {
                        Text("目录读取耗时较长，你可以继续使用其他页面。")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("清理范围")
                            .font(.system(size: 13, weight: .medium))
                        Text("包含受管下载目录、历史下载记录中的文件与转换临时文件。已导入「照片」的实况不受影响。")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack {
                        Text("清理前，请先保留仍需使用的下载文件。")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("清除受管文件…", role: .destructive) {
                            showClearAlert = true
                        }
                        .buttonStyle(.bordered)
                        .disabled(cacheManager.totalFileCount == 0 || cacheManager.isRefreshing)
                    }
                }
                .padding(22)
                .forgeSurface()
            }
            .frame(maxWidth: 900)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .onAppear { cacheManager.refreshStats() }
    }

    private func showToast(_ message: String, warning: Bool = false) {
        let id = UUID()
        toastID = id
        toastIsWarning = warning
        toastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if toastID == id { toastMessage = nil }
        }
    }
}
