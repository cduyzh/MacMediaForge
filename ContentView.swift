import SwiftUI
import UniformTypeIdentifiers
import Photos
import PhotosUI

// MARK: - 导航 Tab 定义
enum NavigationTab: String, CaseIterable, Identifiable {
    case studio = "studio"             // 🌟 实况制作 (本地视频拖拽与转换工作台)
    case extractor = "extractor"       // 🌐 网络视频提取 (小红书/X/网络批量下载与转实况)
    case xhsAssistant = "xhsAssistant" // 📱 小红书助手 (全自动脚本抓取与鉴权中心)
    case settings = "settings"         // ⚙️ 系统偏好设置 (去重/去水印/保存目录)

    var id: String { rawValue }

    var title: String {
        switch self {
        case .studio: return "实况制作"
        case .extractor: return "网络提取"
        case .xhsAssistant: return "小红书助手"
        case .settings: return "设置"
        }
    }

    var icon: String {
        switch self {
        case .studio: return "film.stack"
        case .extractor: return "arrow.down.circle.dotted"
        case .xhsAssistant: return "bolt.shield.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

// MARK: - 转换模式定义
enum ConversionType: String, CaseIterable, Identifiable {
    case livePhoto = "livePhoto"
    case gif = "gif"
    case files = "files"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .livePhoto: return "实况照片"
        case .gif:       return "动图 GIF"
        case .files:     return "配对文件"
        }
    }

    var shortTitle: String {
        switch self {
        case .livePhoto: return "实况图"
        case .gif:       return "动图 GIF"
        case .files:     return "本地文件"
        }
    }

    var icon: String {
        switch self {
        case .livePhoto: return "livephoto"
        case .gif:       return "sparkles"
        case .files:     return "folder"
        }
    }

    var description: String {
        switch self {
        case .livePhoto: return "保存到“照片”。开启 iCloud 照片后，可同步至 iPhone。"
        case .gif:       return "生成适合公众号文章与分享的 GIF，保存到下载目录。"
        case .files:     return "导出 JPG 与 MOV 配对文件，保存到下载目录。"
        }
    }
}

// MARK: - 主工作区
struct ContentView: View {
    @StateObject private var vm = ConversionViewModel()
    @AppStorage("selectedNavigationTab") private var savedTab = NavigationTab.studio.rawValue
    @State private var currentTab: NavigationTab = {
        let value = ProcessInfo.processInfo.environment["DEFAULT_TAB"]
            ?? UserDefaults.standard.string(forKey: "selectedNavigationTab") ?? "studio"
        return NavigationTab(rawValue: value) ?? .studio
    }()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDragging = false
    @State private var selectedLivePhotoItem: PhotosPickerItem?
    @State private var isExtracting = false
    @State private var showHistorySheet = false
    @State private var showChangelogSheet = false
    @State private var importMessage: String?
    @State private var importFailed = false
    @State private var visitedTabs: Set<NavigationTab> = []
    @ObservedObject private var historyManager = OperationHistoryManager.shared

    var body: some View {
        VStack(spacing: 0) {
            topTabBar
            Divider().opacity(0.5)
            ZStack {
                ForEach(NavigationTab.allCases) { tab in
                    if tab == currentTab || visitedTabs.contains(tab) {
                        tabContent(tab)
                            .opacity(currentTab == tab ? 1 : 0)
                            .allowsHitTesting(currentTab == tab)
                            .disabled(currentTab != tab)
                            .accessibilityHidden(currentTab != tab)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showHistorySheet) {
            VStack(spacing: 0) {
                sheetHeader("操作历史", icon: "clock.arrow.circlepath") { showHistorySheet = false }
                Divider()
                OperationHistoryView()
            }
            .frame(minWidth: 720, minHeight: 540)
            .onExitCommand { showHistorySheet = false }
        }
        .sheet(isPresented: $showChangelogSheet) {
            VStack(spacing: 0) {
                sheetHeader("更新日志", icon: "sparkles.rectangle.stack") { showChangelogSheet = false }
                Divider()
                ChangelogView()
            }
            .frame(minWidth: 680, minHeight: 560)
            .onExitCommand { showChangelogSheet = false }
        }
        .onAppear { visitedTabs.insert(currentTab) }
        .onChange(of: currentTab) { _, newValue in
            savedTab = newValue.rawValue
            visitedTabs.insert(newValue)
        }
        .onDrop(of: [.fileURL], isTargeted: $isDragging, perform: handleDrop)
        .onReceive(NotificationCenter.default.publisher(for: .addVideosFromDock)) { note in
            if let urls = note.object as? [URL] { addVideos(urls) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .downloadCacheCleared)) { _ in
            vm.handleCacheCleared()
        }
    }

    @ViewBuilder private func tabContent(_ tab: NavigationTab) -> some View {
        switch tab {
        case .studio: livePhotoStudioTab
        case .extractor: NetworkExtractorView(vm: vm, onAddToStudio: { addVideos([$0]) })
        case .xhsAssistant: XHSAssistantView()
        case .settings: SettingsTabView(isProcessing: vm.isRunning || vm.isNetworkRunning)
        }
    }

    private func sheetHeader(_ title: String, icon: String, close: @escaping () -> Void) -> some View {
        HStack {
            Label(title, systemImage: icon).font(.system(size: 14, weight: .semibold))
            Spacer()
            Button("完成", action: close).keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    private var topTabBar: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                appBrandIcon
                VStack(alignment: .leading, spacing: 2) {
                    Text("MediaForge")
                        .font(.system(size: 17, weight: .semibold))
                        .tracking(-0.3)
                    Text("视频 · 实况 · 动图")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Button(ReleaseLogData.currentVersion) { showChangelogSheet = true }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.04), in: Capsule())
                    .help("查看更新日志")
                    .accessibilityLabel("版本 \(ReleaseLogData.currentVersion)，查看更新日志")
                Spacer()
                Button { showHistorySheet = true } label: {
                    Label("历史记录", systemImage: "clock.arrow.circlepath")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("查看处理记录与输出文件")

                Divider().frame(height: 18).padding(.horizontal, 3)

                PhotosPicker(selection: $selectedLivePhotoItem, matching: .livePhotos) {
                    HStack(spacing: 6) {
                        if isExtracting { ProgressView().controlSize(.mini) }
                        Image(systemName: "arrow.up.right.video")
                        Text(isExtracting ? "提取中…" : "提取实况视频")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(isExtracting || vm.isRunning || vm.isNetworkRunning)
                .help("从“照片”中的实况照片提取视频")
                .onChange(of: selectedLivePhotoItem) { _, value in
                    if let value { extractVideoFromLivePhoto(value) }
                }
            }
            .font(.system(size: 12))

            HStack(spacing: 4) {
                ForEach(Array(NavigationTab.allCases.enumerated()), id: \.element.id) { index, tab in
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) { currentTab = tab }
                    } label: {
                        Label(tab.title, systemImage: tab.icon)
                            .font(.system(size: 12.5, weight: currentTab == tab ? .semibold : .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .contentShape(RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(currentTab == tab ? Color.primary : Color.secondary)
                            .background {
                                if currentTab == tab {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color(nsColor: .controlBackgroundColor))
                                        .shadow(color: .black.opacity(0.07), radius: 2, y: 1)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    .accessibilityAddTraits(currentTab == tab ? .isSelected : [])
                    .help("\(tab.title)（⌘\(index + 1)）")
                }
            }
            .padding(4)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .padding(.horizontal, 28)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .background(.regularMaterial)
    }

    private var livePhotoStudioTab: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForgeSectionHeading(title: "本地制作", subtitle: "将视频变为实况照片、动图，或导出配对文件。", isPageTitle: true)
                    if vm.isNetworkRunning {
                        ForgeStatusBanner(title: "网络下载正在继续", message: "你可以先整理视频，下载结束后即可开始制作。", systemImage: "arrow.down.circle", tint: .accentColor)
                    }
                    if let importMessage {
                        HStack(alignment: .top, spacing: 6) {
                            ForgeStatusBanner(title: importMessage, systemImage: importFailed ? "exclamationmark.circle" : "checkmark.circle", tint: importFailed ? .orange : .accentColor)
                            Button { self.importMessage = nil } label: { Image(systemName: "xmark") }
                                .buttonStyle(ForgeIconButtonStyle())
                                .accessibilityLabel("关闭导入提示")
                        }
                    }
                    dropZoneCard
                    modePickerBar
                    if vm.items.isEmpty {
                        emptyState
                    } else {
                        HStack {
                            Text("制作队列").font(.system(size: 13, weight: .semibold))
                            Text("\(vm.items.count)")
                                .font(.system(size: 11, weight: .medium).monospacedDigit())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("可逐个调整，也可批量制作")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                        LazyVStack(spacing: 10) {
                            ForEach(vm.items) { VideoCardView(item: $0, vm: vm) }
                        }
                    }
                }
                .padding(28)
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            }
            Divider().opacity(0.5)
            bottomBar
        }
    }

    private var dropZoneCard: some View {
        Group {
            if vm.items.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: isDragging ? "plus.circle" : "square.and.arrow.down")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(Color.accentColor)
                        .frame(height: 45)
                        .accessibilityHidden(true)
                    VStack(spacing: 7) {
                        Text(isDragging ? "松开，加入制作队列" : "拖入视频，即刻开始")
                            .font(.system(size: 19, weight: .semibold))
                            .tracking(-0.3)
                        Text("MP4、MOV、M4V、AVI、MKV、WebM")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    browseButton
                        .padding(.top, 6)
                }
                .padding(.vertical, 32)
            } else {
                HStack(spacing: 14) {
                    Image(systemName: "plus.rectangle.on.folder")
                        .font(.system(size: 25, weight: .light))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(isDragging ? "松开以添加视频" : "继续添加视频")
                            .font(.system(size: 13, weight: .semibold))
                        Text("拖入文件，或从访达中选择。")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    browseButton
                }
                .padding(20)
            }
        }
        .frame(maxWidth: .infinity)
        .background(isDragging && !vm.isRunning ? Color.accentColor.opacity(0.06) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isDragging && !vm.isRunning ? Color.accentColor : Color(nsColor: .separatorColor).opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: isDragging)
    }

    private var browseButton: some View {
        Button(action: openFilePicker) { Label("选择视频…", systemImage: "plus") }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .keyboardShortcut("o", modifiers: .command)
            .disabled(vm.isRunning || isExtracting)
    }

    private var modePickerBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 18) {
                Text("输出格式").font(.system(size: 13, weight: .semibold))
                Spacer()
                Picker("输出格式", selection: $vm.selectedMode) {
                    ForEach(ConversionType.allCases) { type in Text(type.title).tag(type) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 390)
                .disabled(vm.isRunning)
            }
            HStack(spacing: 7) {
                Image(systemName: vm.selectedMode.icon).foregroundStyle(Color.accentColor)
                Text(vm.selectedMode.description).foregroundStyle(.secondary)
            }
            .font(.system(size: 12))
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .forgeSurface()
    }

    private var bottomBar: some View {
        HStack(spacing: 14) {
            if vm.isRunning { ProgressView().controlSize(.small) }
            VStack(alignment: .leading, spacing: 3) {
                Text(vm.isRunning ? (vm.isCancelling ? "正在停止…" : "正在制作，请稍候") : queueSummary)
                    .font(.system(size: 12.5, weight: .medium))
                Text(vm.isCancelling ? "当前步骤结束后恢复操作" : (vm.isRunning ? "完成后可直接查看输出" : "所有转换均在本机完成"))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            if vm.isRunning {
                Button("停止转换") { vm.cancelCurrentConversion() }
                    .buttonStyle(.bordered)
                    .disabled(vm.isCancelling)
            } else {
                Button("清空列表") { vm.items.removeAll(); importMessage = nil }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .disabled(vm.items.isEmpty)
            }
            Button { Task { await vm.convertAll() } } label: {
                Label(vm.isRunning ? "制作中…" : conversionButtonTitle, systemImage: vm.selectedMode.icon)
                    .font(.system(size: 12.5, weight: .semibold))
                    .frame(minWidth: 126)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(vm.pendingCount == 0 || vm.isRunning || vm.isNetworkRunning || isExtracting)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 17)
        .background(.regularMaterial)
    }

    private var queueSummary: String {
        if vm.items.isEmpty { return "准备好你的下一段精彩" }
        if vm.items.contains(where: { $0.isLoadingMetadata }) { return "正在读取视频信息…" }
        let failedCount = vm.items.filter { if case .failed = $0.status { return true }; return false }.count
        if vm.pendingCount == 0, failedCount > 0 { return "\(failedCount) 个视频未能处理，请查看原因" }
        if vm.pendingCount == 0 { return "队列已处理完成" }
        return "\(vm.pendingCount) 个视频待制作 · 共 \(vm.items.count) 个"
    }

    private var conversionButtonTitle: String {
        switch vm.selectedMode {
        case .livePhoto: return "制作实况照片"
        case .gif: return "生成 GIF"
        case .files: return "导出配对文件"
        }
    }

    private var emptyState: some View {
        HStack(alignment: .top, spacing: 24) {
            workflowHint("1", title: "添加视频", detail: "支持批量拖入")
            workflowHint("2", title: "选择格式", detail: "按需裁剪与调速")
            workflowHint("3", title: "开始制作", detail: "完成后查看结果")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
    }

    private func workflowHint(_ number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text(number).font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .background(Color.primary.opacity(0.04), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var appBrandIcon: some View {
        Image(systemName: "livephoto")
            .font(.system(size: 25, weight: .light))
            .foregroundStyle(Color.accentColor)
            .frame(width: 40, height: 40)
            .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .accessibilityHidden(true)
    }

    private func addVideos(_ urls: [URL]) {
        guard !vm.isRunning else {
            importMessage = "请等待当前转换结束后再添加视频。"
            importFailed = true
            currentTab = .studio
            return
        }
        let extensions: Set<String> = ["mp4", "mov", "m4v", "avi", "mkv", "webm"]
        var added = 0
        var duplicates = 0
        var rejected = 0
        for url in urls {
            guard url.isFileURL, extensions.contains(url.pathExtension.lowercased()),
                  FileManager.default.isReadableFile(atPath: url.path) else { rejected += 1; continue }
            if vm.items.contains(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) {
                duplicates += 1
            } else {
                vm.addVideo(url: url)
                added += 1
            }
        }
        currentTab = .studio
        var parts: [String] = []
        if added > 0 { parts.append("已添加 \(added) 个视频") }
        if duplicates > 0 { parts.append("\(duplicates) 个重复文件已跳过") }
        if rejected > 0 { parts.append("\(rejected) 个文件不受支持或无法读取") }
        importMessage = parts.joined(separator: "，")
        importFailed = rejected > 0
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !vm.isRunning, !isExtracting else { return false }
        let accepted = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        Task {
            let results = await withTaskGroup(of: URL?.self, returning: [URL?].self) { group in
                for provider in accepted {
                    group.addTask {
                        await withCheckedContinuation { continuation in
                            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                                if let url = item as? URL { continuation.resume(returning: url) }
                                else if let data = item as? Data { continuation.resume(returning: URL(dataRepresentation: data, relativeTo: nil)) }
                                else { continuation.resume(returning: nil) }
                            }
                        }
                    }
                }
                var values: [URL?] = []
                for await value in group { values.append(value) }
                return values
            }
            addVideos(results.compactMap { $0 })
            let unreadable = results.filter { $0 == nil }.count
            if unreadable > 0 {
                let suffix = "\(unreadable) 个文件无法读取，请重新选择"
                importMessage = [importMessage, suffix].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "，")
                importFailed = true
            }
        }
        return !accepted.isEmpty
    }

    private func openFilePicker() {
        guard !vm.isRunning else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.movie, .video, .quickTimeMovie, .mpeg4Movie] + ["mkv", "webm", "avi"].compactMap { UTType(filenameExtension: $0) }
        panel.prompt = "添加视频"
        if panel.runModal() == .OK { addVideos(panel.urls) }
    }

    private func extractVideoFromLivePhoto(_ item: PhotosPickerItem) {
        isExtracting = true
        Task {
            do {
                let videoURL = try await LivePhotoExtractor.extractFromPickerItem(item)
                addVideos([videoURL])
                OperationHistoryManager.shared.record(source: .livePhotoExtract, platform: "相册", title: "提取实况视频：\(videoURL.lastPathComponent)", originalURLOrPath: "Photos Library", status: .success, outputs: [HistoryOutputItem(fileName: videoURL.lastPathComponent, filePath: videoURL.path, category: "视频", fileSize: (try? FileManager.default.attributesOfItem(atPath: videoURL.path)[.size] as? Int64) ?? 0)], note: "已加入制作队列")
            } catch {
                currentTab = .studio
                importMessage = "提取失败：\(error.localizedDescription)"
                importFailed = true
                OperationHistoryManager.shared.record(source: .livePhotoExtract, platform: "相册", title: "提取实况视频失败", status: .failed, note: error.localizedDescription)
            }
            isExtracting = false
            selectedLivePhotoItem = nil
        }
    }
}
