import SwiftUI
import AppKit

public enum SettingsSubTab: String, CaseIterable, Identifiable {
    case general = "通用"
    case downloads = "下载与存储"
    case media = "媒体处理"
    case storage = "缓存与空间"
    case history = "操作历史"
    case changelog = "关于与更新"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .general: return "gearshape"
        case .downloads: return "arrow.down.circle"
        case .media: return "film.stack"
        case .storage: return "internaldrive"
        case .history: return "clock.arrow.circlepath"
        case .changelog: return "info.circle"
        }
    }

    public var detail: String {
        switch self {
        case .general: return "安排菜单栏与窗口的使用方式。"
        case .downloads: return "选择保存位置、默认画质与下载方式。"
        case .media: return "设置网络提取的输出与媒体制作偏好。"
        case .storage: return "查看受管文件占用，按需释放磁盘空间。"
        case .history: return "查找制作、提取与下载的操作记录。"
        case .changelog: return "查看当前版本、检查更新与阅读版本记录。"
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
        GeometryReader { geometry in
            let usesSidebar = geometry.size.width >= 920
            VStack(spacing: 0) {
                settingsHeaderBar(usesSidebar: usesSidebar)
                Divider()

                HStack(spacing: 0) {
                    if usesSidebar {
                        settingsSidebar
                        Divider()
                    }

                    VStack(spacing: 0) {
                        if isProcessing {
                            ForgeStatusBanner(
                                title: "任务进行中",
                                message: "下载、媒体处理与缓存设置将在任务结束后恢复编辑。",
                                systemImage: "info.circle",
                                tint: .secondary
                            )
                            .padding(.horizontal, 24)
                            .padding(.top, 18)
                        }

                        if let message = toastMessage {
                            ForgeStatusBanner(
                                title: message,
                                systemImage: toastIsWarning ? "exclamationmark.circle" : "checkmark.circle",
                                tint: toastIsWarning ? .orange : .green
                            )
                            .padding(.horizontal, 24)
                            .padding(.top, 18)
                        }

                        selectedTabContent
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
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

    private func settingsHeaderBar(usesSidebar: Bool) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("设置")
                    .font(.system(size: 22, weight: .semibold))
                Text("MediaForge · \(ReleaseLogData.currentVersion)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()

            if !usesSidebar {
                Picker("设置分类", selection: $currentSubTab) {
                    ForEach(SettingsSubTab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 180)
                .accessibilityLabel("设置分类")
            } else {
                Label("更改会自动保存", systemImage: "checkmark.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 5) {
            sidebarHeading("偏好设置")
            ForEach([SettingsSubTab.general, .downloads, .media, .storage]) { tab in
                sidebarButton(tab)
            }

            sidebarHeading("记录与信息")
                .padding(.top, 20)
            ForEach([SettingsSubTab.history, .changelog]) { tab in
                sidebarButton(tab)
            }
            Spacer(minLength: 24)
        }
        .padding(14)
        .frame(width: 184)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
    }

    private func sidebarHeading(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
            .padding(.top, 5)
    }

    private func sidebarButton(_ tab: SettingsSubTab) -> some View {
        let selected = currentSubTab == tab
        return Button {
            currentSubTab = tab
        } label: {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .frame(width: 18)
                Text(tab.rawValue)
                    .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                Spacer(minLength: 0)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(selected ? Color.accentColor.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("settings.category.\(tab.id)")
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        switch currentSubTab {
        case .history:
            OperationHistoryView()
        case .changelog:
            ChangelogView()
        default:
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(currentSubTab.rawValue)
                            .font(.system(size: 20, weight: .semibold))
                        Text(currentSubTab.detail)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 2)

                    switch currentSubTab {
                    case .general:
                        menuBarPreferencesSection
                        settingsShortcutsSection
                    case .downloads:
                        classifiedStorageSection.disabled(isProcessing)
                        videoQualitySection.disabled(isProcessing)
                        concurrencyPerformanceSection.disabled(isProcessing)
                        duplicatePolicySection.disabled(isProcessing)
                    case .media:
                        extractorOptionsDynamicSection.disabled(isProcessing)
                        watermarkSection.disabled(isProcessing)
                        livePhotoPreferencesSection.disabled(isProcessing)
                    case .storage:
                        storageAndCacheSection.disabled(isProcessing)
                    case .history, .changelog:
                        EmptyView()
                    }
                }
                .frame(maxWidth: 820)
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .id(currentSubTab)
        }
    }

    // MARK: - 通用

    private var menuBarPreferencesSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsSectionHeading(
                title: "菜单栏与窗口",
                subtitle: "在 macOS 菜单栏随时查看任务与打开工作台。",
                systemImage: "menubar.rectangle"
            )

            preferenceToggle(
                "关闭主窗口后继续在菜单栏运行",
                detail: "窗口关闭后，下载与制作任务可以继续。",
                isOn: $settings.keepRunningInMenuBar
            )
            .accessibilityIdentifier("settings.keepRunningInMenuBar")

            Divider()

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "cursorarrow.click")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 7) {
                    Text("左键查看状态面板，右键打开快捷菜单。")
                        .font(.system(size: 12, weight: .medium))
                    Text(settings.keepRunningInMenuBar
                         ? "从状态面板可重新打开窗口；使用「退出 MediaForge」结束应用。"
                         : "菜单栏图标在应用运行时始终显示；关闭主窗口会退出应用。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(20)
        .forgeSurface()
    }

    private var settingsShortcutsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsSectionHeading(title: "常用设置", systemImage: "slider.horizontal.3")
            VStack(spacing: 0) {
                settingsShortcut(.downloads, detail: "\(settings.defaultVideoQuality.shortLabel) · 同时下载 \(settings.maxConcurrentDownloads) 个任务")
                Divider().padding(.leading, 40)
                settingsShortcut(.media, detail: "实况 \(settings.livePhotoFPS) FPS · \(settings.autoImportPhotos ? "自动导入照片" : "手动导入照片")")
                Divider().padding(.leading, 40)
                settingsShortcut(.storage, detail: "查看文件占用与清理范围")
            }
        }
        .padding(20)
        .forgeSurface()
    }

    private func settingsShortcut(_ tab: SettingsSubTab, detail: String) -> some View {
        Button {
            currentSubTab = tab
        } label: {
            HStack(spacing: 12) {
                Image(systemName: tab.icon)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(tab.rawValue)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
            settingsSectionHeading(title: "默认输出", subtitle: "与网络提取页面的选项实时同步。", systemImage: "square.and.arrow.down")

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

    private var videoQualitySection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 20) {
                settingsSectionHeading(title: "默认清晰度", systemImage: "tv")
                Spacer(minLength: 12)
                Picker("下载清晰度", selection: $settings.defaultVideoQuality) {
                    ForEach(VideoQualityOption.allCases) { q in
                        Text(q.title).tag(q)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 190)
            }

            Text("最高下载 1080P，4K / 8K 原片也按此上限处理。所选画质不可用时，自动匹配最接近的清晰度；每条视频仍可在网络提取页单独调整。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .forgeSurface()
    }

    private var duplicatePolicySection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 20) {
                settingsSectionHeading(title: "遇到同名文件时", systemImage: "doc.on.doc")
                Spacer(minLength: 12)
                Picker("同名文件处理方式", selection: $settings.duplicatePolicy) {
                    ForEach(DuplicatePolicy.allCases) { policy in
                        Text(duplicatePolicyTitle(policy)).tag(policy)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 210)
            }

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
        .accessibilityLabel(title)
        .accessibilityHint(detail)
    }

    // MARK: - 存储维护

    private var storageAndCacheSection: some View {
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

                HStack(alignment: .firstTextBaseline, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(cacheManager.isRefreshing ? "正在统计…" : cacheManager.formattedTotalSize)
                            .font(.system(size: 32, weight: .light, design: .rounded))
                            .monospacedDigit()
                        Text("受管文件占用")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(cacheManager.isRefreshing ? "—" : "\(cacheManager.totalFileCount)")
                            .font(.system(size: 27, weight: .light, design: .rounded))
                            .monospacedDigit()
                        Text("个受管文件")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                if cacheManager.statsReadIsSlow {
                    Text("目录读取耗时较长，你可以继续使用其他页面。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .forgeSurface()

            VStack(alignment: .leading, spacing: 18) {
                settingsSectionHeading(title: "清理受管文件", systemImage: "trash")
                Text("包含受管下载目录、历史下载记录中的文件与转换临时文件。已导入「照片」的实况不受影响。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                HStack(spacing: 16) {
                    Text("清理前，请先保留仍需使用的下载文件。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 12)
                    Button("清除受管文件…", role: .destructive) {
                        showClearAlert = true
                    }
                    .buttonStyle(.bordered)
                    .disabled(cacheManager.totalFileCount == 0 || cacheManager.isRefreshing)
                }
            }
            .padding(20)
            .forgeSurface()
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
