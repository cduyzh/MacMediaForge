import SwiftUI
import AppKit

// MARK: - 下载并归类的成果条目模型
public struct ExtractedMediaItem: Identifiable, Sendable {
    public let id = UUID()
    public let title: String
    public let url: URL
    public let category: MediaCategory
    public let platform: PlatformCategory
    public let dateString: String

    public var relativeDisplayPath: String {
        "/\(platform.rawValue)/\(dateString)/\(category.rawValue)/\(url.lastPathComponent)"
    }
}

struct NetworkExtractorView: View {
    @ObservedObject var vm: ConversionViewModel
    var onAddToStudio: ((URL) -> Void)? = nil
    @ObservedObject private var appSettings = AppSettings.shared
    @ObservedObject private var xhsAuth = XHSAuthManager.shared
    @ObservedObject private var preParser = NetworkVideoPreParser.shared

    @State private var inputURLsText = ""
    @State private var inputFeedback: String?
    @FocusState private var isInputFocused: Bool
    @State private var isPreviewExpanded = true
    @State private var isDownloading = false
    @State private var isCancelling = false
    @State private var currentProgressText = ""
    @State private var progressPercent: Double = 0
    @State private var errorMessage: String?
    @State private var successBannerMessage: String?
    @State private var downloadHadFailures = false
    @State private var cancelledBannerMessage: String?
    @State private var downloadTask: Task<Void, Never>?
    @State private var isCancelledByUser = false
    @State private var downloadedMediaItems: [ExtractedMediaItem] = []
    @State private var bilibiliCollectionSheetItem: BilibiliCollectionInfo?

    private var detectedURLs: [String] {
        NetworkVideoDownloader.extractAllURLs(from: inputURLsText)
    }

    /// 根据用户勾选情况筛选出真正需要下载的链接列表
    private var selectedURLsToDownload: [String] {
        let all = detectedURLs
        if preParser.items.isEmpty { return all }
        let map = Dictionary(uniqueKeysWithValues: preParser.items.map { ($0.originalURL, $0.isSelectedForDownload) })
        return all.filter { map[$0] ?? true }
    }

    /// 识别当前解析列表中是否包含合集
    private var detectedBilibiliCollection: BilibiliCollectionInfo? {
        preParser.items.compactMap { $0.bilibiliCollection }.first
    }

    private var hasTwitterURLs: Bool {
        detectedURLs.contains { NetworkVideoDownloader.isTwitterURL($0) }
    }

    private var hasXHSURLs: Bool {
        detectedURLs.contains { NetworkVideoDownloader.isXiaohongshuURL($0) }
    }

    private var isOptionSelected: Bool {
        appSettings.saveToLocal || appSettings.convertToLivePhoto || appSettings.generateGIF
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                batchInputCard
                optionsBarCard

                if isDownloading {
                    progressCard
                }
                if let message = errorMessage {
                    ForgeStatusBanner(title: "未能完成下载", message: message, systemImage: "exclamationmark.circle.fill", tint: .red)
                }
                if let message = cancelledBannerMessage, !isCancelling {
                    HStack(alignment: .top, spacing: 8) {
                        ForgeStatusBanner(title: "下载已取消", message: message, systemImage: "stop.circle", tint: .secondary)
                        Button {
                            cancelledBannerMessage = nil
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(ForgeIconButtonStyle())
                        .help("关闭取消提示")
                        .accessibilityLabel("关闭取消提示")
                    }
                }
                if let message = successBannerMessage {
                    ForgeStatusBanner(title: downloadHadFailures ? "部分任务已完成" : "下载完成", message: message, systemImage: downloadHadFailures ? "exclamationmark.circle" : "checkmark.circle.fill", tint: downloadHadFailures ? .orange : .green)
                }
                collectionDetectedBanner
                if !preParser.items.isEmpty {
                    previewsCard
                }
                if !downloadedMediaItems.isEmpty {
                    downloadedListSection
                }
            }
            .frame(maxWidth: 1040)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .sheet(item: $bilibiliCollectionSheetItem) { coll in
            BilibiliCollectionSheetView(
                collection: coll,
                onConfirmAndDownload: { episodes in
                    enrollEpisodesAndStartDownload(episodes)
                },
                onEnrollToInput: { episodes in
                    enrollEpisodesToInput(episodes)
                },
                onDismiss: {
                    bilibiliCollectionSheetItem = nil
                }
            )
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider().opacity(0.5)
                downloadActionBar
                    .padding(.horizontal, 28)
                    .padding(.vertical, 17)
            }
            .background(.regularMaterial)
        }
        .onAppear {
            if inputURLsText.isEmpty, let initialURLs = ProcessInfo.processInfo.environment["INITIAL_INPUT_URLS"], !initialURLs.isEmpty {
                inputURLsText = initialURLs
            }
            preParser.syncURLs(detectedURLs)
        }
        .onReceive(NotificationCenter.default.publisher(for: .cancelActiveWork)) { _ in
            cancelCurrentWork()
        }
        .onChange(of: inputURLsText) { _, _ in
            inputFeedback = nil
            preParser.syncURLs(detectedURLs)
            if !isDownloading {
                errorMessage = nil
                successBannerMessage = nil
                cancelledBannerMessage = nil
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("网络视频")
                .font(.system(size: 24, weight: .semibold))
            Text("粘贴分享链接，批量保存视频，或生成实况照片与 GIF。")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 2)
    }

    private var batchInputCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                ForgeSectionHeading(title: "添加链接", subtitle: "支持多条链接，也可直接粘贴分享文字。")
                Spacer(minLength: 12)
                Button(action: pasteFromClipboard) {
                    Label("粘贴", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(isDownloading)

                Menu {
                    Button("X / Twitter 示例", action: loadDemoTwitterURLs)
                    Button("小红书示例", action: loadDemo30URLs)
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 16, height: 16)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("载入示例链接")
                .accessibilityLabel("载入示例链接")
                .disabled(isDownloading)
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $inputURLsText)
                    .font(.system(size: 13, design: .monospaced))
                    .lineSpacing(5)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 132, maxHeight: 180)
                    .focused($isInputFocused)
                    .disabled(isDownloading)
                    .accessibilityLabel("视频链接或分享文字")
                    .accessibilityHint("支持多条链接，使用空格或换行分隔")

                if inputURLsText.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("将视频链接粘贴到这里")
                            .foregroundStyle(.secondary)
                        Text("小红书 · X / Twitter · 哔哩哔哩 · 视频直链")
                            .foregroundStyle(.tertiary)
                    }
                    .font(.system(size: 13))
                    .padding(14)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isInputFocused ? Color.accentColor.opacity(0.65) : Color.primary.opacity(0.10), lineWidth: isInputFocused ? 1.5 : 1)
                    .allowsHitTesting(false)
            }

            HStack(spacing: 8) {
                Image(systemName: detectedURLs.isEmpty ? "link" : "checkmark.circle")
                    .foregroundStyle(detectedURLs.isEmpty ? Color.secondary : Color.accentColor)
                    .accessibilityHidden(true)
                Text(inputStatusText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                if !inputURLsText.isEmpty {
                    Button("清空") {
                        inputURLsText = ""
                        isInputFocused = true
                    }
                    .buttonStyle(.borderless)
                    .disabled(isDownloading)
                    .accessibilityLabel("清空全部链接")
                }
            }

            if hasTwitterURLs {
                Text("X / Twitter 链接会一并提取发帖人的回复视频；可选择导出 Markdown 摘要。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if hasXHSURLs && !xhsAuth.hasConfiguredCookie {
                Label("部分小红书链接需要登录信息，可在小红书助手中配置。", systemImage: "info.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .forgeSurface(cornerRadius: 16)
    }

    private var inputStatusText: String {
        if let feedback = inputFeedback { return feedback }
        if !detectedURLs.isEmpty { return "已识别 \(detectedURLs.count) 条链接" }
        return inputURLsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "等待添加链接" : "未识别到链接，请检查输入内容"
    }

    private var optionsBarCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForgeSectionHeading(title: "下载与处理", subtitle: "选择需要保存的内容。")

            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 16) {
                Toggle("保存视频", isOn: $appSettings.saveToLocal)
                Toggle("转换为实况照片", isOn: $appSettings.convertToLivePhoto)
                    .help("保存实况照片配对文件，并按设置决定是否导入照片图库")
                Toggle("生成 GIF", isOn: $appSettings.generateGIF)
                    .help("下载后额外生成 GIF 动图")
                Toggle("去除水印", isOn: $appSettings.removeWatermark)
                    .help("使用 FFmpeg 处理视频水印")
                Toggle("导出 X / Twitter 摘要", isOn: $appSettings.exportMarkdown)
                    .help("将帖子摘要保存为 Markdown 文档")
                HStack(spacing: 8) {
                    Text("同时下载")
                    Text("\(appSettings.maxConcurrentDownloads) 项")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Stepper("同时下载数量", value: $appSettings.maxConcurrentDownloads, in: 1...10)
                        .labelsHidden()
                        .accessibilityValue("\(appSettings.maxConcurrentDownloads) 项")
                }
            }
            .font(.system(size: 13))
            .toggleStyle(.checkbox)
            .disabled(isDownloading)

            Divider()

            HStack(spacing: 12) {
                Label("清晰度", systemImage: "sparkles.tv")
                    .font(.system(size: 13, weight: .medium))

                Picker("", selection: $appSettings.defaultVideoQuality) {
                    ForEach(VideoQualityOption.allCases) { opt in
                        Text(opt.label).tag(opt)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)

                Text("最高 1080P")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
            }
            .disabled(isDownloading)

            Divider()

            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "folder")
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text((appSettings.downloadDirectory as NSString).abbreviatingWithTildeInPath)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(appSettings.downloadDirectory)
                    Text("按平台、日期与文件类型归档 · \(appSettings.duplicatePolicy.title)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Button("更改…") {
                    appSettings.promptChooseDownloadDirectory()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isDownloading)
                .accessibilityLabel("更改下载保存目录")
            }

        }
        .padding(20)
        .forgeSurface(cornerRadius: 16)
    }

    private var downloadActionBar: some View {
        HStack(spacing: 16) {
            Text(actionStatusText)
                .font(.system(size: 12))
                .foregroundStyle(!isOptionSelected ? Color.orange : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            if isDownloading {
                Button(isCancelling ? "正在取消…" : "取消下载", role: .cancel, action: cancelCurrentWork)
                    .buttonStyle(.bordered)
                    .disabled(isCancelling)
                    .help("停止当前任务并清理未完成的临时文件")
            } else {
                Button(action: handleDownloadAction) {
                    Label(downloadButtonText, systemImage: "arrow.down")
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(selectedURLsToDownload.isEmpty || !isOptionSelected || vm.isRunning)
                .help("开始下载选中的视频（⌘Return）")
            }
        }
    }

    private var downloadButtonText: String {
        if detectedURLs.isEmpty { return "开始下载" }
        let count = selectedURLsToDownload.count
        if count == detectedURLs.count {
            return "下载全部 \(count) 项"
        } else {
            return "下载选中 \(count) 项"
        }
    }

    private func handleDownloadAction() {
        // 如果输入框只有一个链接，且检测到该链接包含未展开的合集，且合集有多集，点击下载优先弹出合集选集器
        if detectedURLs.count == 1,
           let firstItem = preParser.items.first,
           let coll = firstItem.bilibiliCollection,
           coll.epCount > 1 {
            bilibiliCollectionSheetItem = coll
            return
        }
        startBatchDownload()
    }

    private var actionStatusText: String {
        if vm.isRunning { return "本地视频正在制作，完成后可开始下载。" }
        if isCancelling { return "正在停止任务并清理临时文件。" }
        if isDownloading { return "下载进行中，完成的文件将显示在下方。" }
        if !isOptionSelected { return "请至少选择保存视频、实况照片或 GIF。" }
        if detectedURLs.isEmpty { return "添加链接后即可开始。" }
        let selectedCount = selectedURLsToDownload.count
        if selectedCount < detectedURLs.count {
            return "共识别 \(detectedURLs.count) 项，已勾选 \(selectedCount) 项，最多同时下载 \(appSettings.maxConcurrentDownloads) 项。"
        }
        return "共 \(detectedURLs.count) 项任务，最多同时下载 \(appSettings.maxConcurrentDownloads) 项。"
    }

    @ViewBuilder
    private var collectionDetectedBanner: some View {
        if let coll = detectedBilibiliCollection, detectedURLs.count == 1 {
            HStack(spacing: 14) {
                Image(systemName: "film.stack.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("发现\(coll.typeLabel)")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 3))

                        Text(coll.title)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                    }

                    Text("包含 \(coll.sections.count) 个分卷、共 \(coll.epCount) 个视频。已全部录入合集视频库，支持人工选择下载。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Button {
                    enrollEpisodesToInput(coll.allEpisodes)
                } label: {
                    Label("全部录入 (\(coll.epCount))", systemImage: "plus.square.on.square")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(isDownloading)
                .help("将合集中的全部 \(coll.epCount) 个视频链接录入输入框")

                Button {
                    bilibiliCollectionSheetItem = coll
                } label: {
                    Label("选集并下载…", systemImage: "checklist")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(isDownloading)
                .help("打开合集选集器，手动挑选需要下载的集数")
            }
            .padding(16)
            .background(Color.accentColor.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.accentColor.opacity(0.2), lineWidth: 1)
            )
        }
    }

    private var previewsCard: some View {
        DisclosureGroup(isExpanded: $isPreviewExpanded) {
            VStack(spacing: 10) {
                if preParser.items.count > 1 {
                    HStack(spacing: 8) {
                        Button("全选") {
                            for it in preParser.items { it.isSelectedForDownload = true }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isDownloading)

                        Button("取消全选") {
                            for it in preParser.items { it.isSelectedForDownload = false }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isDownloading)

                        Button("反选") {
                            for it in preParser.items { it.isSelectedForDownload.toggle() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isDownloading)

                        Spacer()

                        let selectedCount = preParser.items.filter { $0.isSelectedForDownload }.count
                        Text("已勾选 \(selectedCount) / \(preParser.items.count) 项")
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .foregroundStyle(selectedCount == 0 ? Color.orange : Color.secondary)
                    }
                    .padding(.bottom, 4)
                }

                ForEach(preParser.items) { item in
                    PreParsedVideoCardView(
                        item: item,
                        isInteractionEnabled: !isDownloading,
                        onOpenCollectionSheet: { coll in
                            bilibiliCollectionSheetItem = coll
                        },
                        onEnrollAllEpisodes: { coll in
                            enrollEpisodesToInput(coll.allEpisodes)
                        }
                    )
                }
            }
            .padding(.top, 14)
        } label: {
            HStack(spacing: 10) {
                Text("链接预览")
                    .font(.system(size: 14, weight: .semibold))
                Text("\(preParser.items.count)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                if preParser.isAnyParsing {
                    ProgressView().controlSize(.small)
                    Text("正在解析…")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Button {
                    preParser.refreshAll()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(ForgeIconButtonStyle())
                .disabled(preParser.isAnyParsing || isDownloading)
                .help("重新解析全部链接")
                .accessibilityLabel("重新解析全部链接")
            }
            .padding(.leading, 4)
        }
        .padding(20)
        .forgeSurface(cornerRadius: 16)
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(isCancelling ? "正在取消下载" : "正在下载与处理")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(Int(progressPercent * 100))%")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            ProgressView(value: progressPercent, total: 1)
                .progressViewStyle(.linear)
                .accessibilityLabel("批量下载进度")
            Text(currentProgressText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .help(currentProgressText)
                .textSelection(.enabled)
        }
        .padding(20)
        .forgeSurface(cornerRadius: 16)
    }

    private var downloadedListSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                ForgeSectionHeading(title: "已保存", subtitle: "\(downloadedMediaItems.count) 个文件")
                Spacer()
                Menu {
                    Button("打开保存目录") {
                        NSWorkspace.shared.open(appSettings.downloadURL)
                    }
                    Divider()
                    Button("小红书今日目录") { CategorizedStorageManager.openInFinder(platform: .xhs) }
                    Button("哔哩哔哩今日目录") { CategorizedStorageManager.openInFinder(platform: .bilibili) }
                    Button("X / Twitter 今日目录") { CategorizedStorageManager.openInFinder(platform: .twitter) }
                } label: {
                    Label("在访达中打开", systemImage: "folder")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            LazyVStack(spacing: 0) {
                ForEach(downloadedMediaItems) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.category.icon)
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                            .frame(width: 28)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.title)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                                .help(item.title)
                            Text("\(item.platform.rawValue) · \(item.category.rawValue) · \(item.dateString)")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        if item.category == .video {
                            Button("加入制作") {
                                if let onAddToStudio { onAddToStudio(item.url) }
                                else { vm.addVideo(url: item.url) }
                            }
                            .disabled(vm.isRunning)
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([item.url])
                        } label: {
                            Image(systemName: "arrow.up.forward.square")
                        }
                        .buttonStyle(ForgeIconButtonStyle())
                        .help("在访达中显示 \(item.title)")
                        .accessibilityLabel("在访达中显示 \(item.title)")
                    }
                    .padding(.vertical, 13)
                    if item.id != downloadedMediaItems.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding(20)
        .forgeSurface(cornerRadius: 16)
    }

    // MARK: - 业务逻辑
    private func pasteFromClipboard() {
        guard !isDownloading else { return }
        guard let clip = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !clip.isEmpty else {
            inputFeedback = "剪贴板中没有可粘贴的文字"
            isInputFocused = true
            return
        }
        inputURLsText = inputURLsText.isEmpty ? clip : inputURLsText + "\n" + clip
        isInputFocused = true
    }

    private func loadDemoTwitterURLs() {
        let demo = [
            "https://x.com/GeminiApp/status/2110039322229649783",
            "https://x.com/EianLu/status/2110150526654656736"
        ]
        inputURLsText = demo.joined(separator: "\n")
    }

    private func loadDemo30URLs() {
        let demoURLs = [
            "https://www.xiaohongshu.com/explore/6a86d598000000000c027bdf",
            "https://www.xiaohongshu.com/explore/6a81a52e0000000026036052",
            "https://www.xiaohongshu.com/explore/6a803e4e0000000033019a65",
            "https://www.xiaohongshu.com/explore/6a7d9eba0000000026034feb",
            "https://www.xiaohongshu.com/explore/6a7af6bf0000000025002671",
            "https://www.xiaohongshu.com/explore/6a786871000000002c0027b9",
            "https://www.xiaohongshu.com/explore/6a7319560000000022015262",
            "https://www.xiaohongshu.com/explore/6a6de0180000000022015301",
            "https://www.xiaohongshu.com/explore/6a6c88d500000000320305cb",
            "https://www.xiaohongshu.com/explore/6a672021000000001102d38d",
            "https://www.xiaohongshu.com/explore/6a65fc97000000000f028640",
            "https://www.xiaohongshu.com/explore/6a609b35000000001101f081",
            "https://www.xiaohongshu.com/explore/6a5b5bbb000000000f032100",
            "https://www.xiaohongshu.com/explore/6a50ca0d000000000f006a34",
            "https://www.xiaohongshu.com/explore/6a4cd479000000000f0179f8",
            "https://www.xiaohongshu.com/explore/6a4a4175000000001101536d",
            "https://www.xiaohongshu.com/explore/6a4343cc000000001101320f",
            "https://www.xiaohongshu.com/explore/6a3f9487000000001102d526",
            "https://www.xiaohongshu.com/explore/6a3a63f6000000001102c963",
            "https://www.xiaohongshu.com/explore/6a37c0da0000000011015927"
        ]
        inputURLsText = demoURLs.joined(separator: "\n")
    }

    // MARK: - 强行打断并清理垃圾文件
    private func cancelCurrentWork() {
        guard isDownloading, !isCancelling else { return }
        isCancelledByUser = true
        isCancelling = true

        downloadTask?.cancel()

        let cleaned = WorkExecutionManager.shared.cancelAndCleanup(targetDirectory: appSettings.downloadURL)

        currentProgressText = "正在停止后台任务并清理未完成的文件…"
        MenuBarState.shared.updateNetwork(detail: currentProgressText, progress: progressPercent)
        errorMessage = nil
        successBannerMessage = nil
        downloadHadFailures = false

        let tip = cleaned > 0 ? "已停止当前任务，清理了 \(cleaned) 个临时文件。已完成的文件仍保留在保存目录。" : "已停止当前任务。已完成的文件仍保留在保存目录。"
        cancelledBannerMessage = tip
    }

    // MARK: - 合集选集接入逻辑
    private func enrollEpisodesToInput(_ episodes: [BilibiliEpisodeItem]) {
        guard !episodes.isEmpty else { return }
        NetworkVideoPreParser.shared.cacheCollectionEpisodes(episodes)
        let newUrls = episodes.map { $0.url }
        inputURLsText = newUrls.joined(separator: "\n")
        inputFeedback = "已成功录入合集 \(episodes.count) 个视频"
    }

    private func enrollEpisodesAndStartDownload(_ episodes: [BilibiliEpisodeItem]) {
        guard !episodes.isEmpty else { return }
        enrollEpisodesToInput(episodes)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.startBatchDownload()
        }
    }

    // MARK: - 并发批量下载主调度器
    private func startBatchDownload() {
        guard !isDownloading, !vm.isRunning, isOptionSelected else { return }
        let urls = selectedURLsToDownload
        guard !urls.isEmpty else { return }

        isDownloading = true
        vm.isNetworkRunning = true
        isCancelling = false
        isInputFocused = false
        isCancelledByUser = false
        errorMessage = nil
        successBannerMessage = nil
        downloadHadFailures = false
        cancelledBannerMessage = nil
        progressPercent = 0.0

        let total = urls.count
        let concurrency = max(1, min(10, appSettings.maxConcurrentDownloads))
        currentProgressText = "正在准备 \(total) 项任务，最多同时下载 \(concurrency) 项…"
        MenuBarState.shared.updateNetwork(detail: currentProgressText, progress: 0)

        downloadTask = Task {
            let semaphore = AsyncSemaphore(permits: concurrency)
            let baseDir = appSettings.downloadURL
            let shouldGenerateGIF = appSettings.generateGIF
            let shouldConvertToLivePhoto = appSettings.convertToLivePhoto
            let shouldSaveVideo = appSettings.saveToLocal
            let shouldExportMarkdown = appSettings.exportMarkdown
            let shouldRemoveWatermark = appSettings.removeWatermark
            let shouldAutoImportPhotos = appSettings.autoImportPhotos
            let tracker = NetworkExtractorView_Tracker()
            var savedFileCount = 0

            await withTaskGroup(of: (outputs: [ExtractedMediaItem], source: String, failure: String?).self) { group in
                for (index, u) in urls.enumerated() {
                    let taskIdx = index + 1
                    group.addTask {
                        await semaphore.wait()
                        defer { Task { await semaphore.signal() } }

                        if Task.isCancelled { return ([], u, nil) }
                        if await tracker.getIsCancelled() { return ([], u, nil) }

                        let platform = PlatformCategory.detect(from: u)
                        let dateStr = CategorizedStorageManager.dateFolderName()

                        let temporarySourceDirectory = shouldSaveVideo ? nil : ConversionEngine.appTempDirectoryURL.appendingPathComponent("download-\(UUID().uuidString)", isDirectory: true)
                        let videoDir = temporarySourceDirectory ?? CategorizedStorageManager.categoryDirectory(baseDir: baseDir, platform: platform, category: .video)
                        defer {
                            if let temporarySourceDirectory {
                                try? FileManager.default.removeItem(at: temporarySourceDirectory)
                            }
                        }
                        let docDir = CategorizedStorageManager.categoryDirectory(baseDir: baseDir, platform: platform, category: .document)
                        let gifDir = CategorizedStorageManager.categoryDirectory(baseDir: baseDir, platform: platform, category: .gif)
                        let livePhotoDir = CategorizedStorageManager.categoryDirectory(baseDir: baseDir, platform: platform, category: .livePhoto)

                        let preItem = await MainActor.run { NetworkVideoPreParser.shared.getItem(for: u) }
                        let itemQuality = await MainActor.run { preItem?.selectedQuality ?? appSettings.defaultVideoQuality }
                        let hasPre = preItem?.status.isReady == true
                        await tracker.updateDescription(id: taskIdx, desc: "[\(platform.rawValue)] \(hasPre ? "正在下载…" : "正在连接解析…")")
                        await self.updateProgress(tracker: tracker, total: total)

                        var generated: [ExtractedMediaItem] = []
                        var failureMessage: String?

                        do {
                            try FileManager.default.createDirectory(at: videoDir, withIntermediateDirectories: true)
                            if platform == .twitter {
                                let result = try await NetworkVideoDownloader.downloadTwitterAll(
                                    url: u,
                                    videoOutputDir: videoDir,
                                    markdownOutputDir: docDir,
                                    exportMarkdown: shouldExportMarkdown,
                                    shouldRemoveWatermark: shouldRemoveWatermark,
                                    quality: itemQuality,
                                    preParsedInfo: preItem?.twitterPostInfo
                                ) { line in
                                    Task {
                                        await tracker.updateDescription(id: taskIdx, desc: "[\(platform.rawValue)] \(line)")
                                        await self.updateProgress(tracker: tracker, total: total)
                                    }
                                }

                                if Task.isCancelled { return ([], u, nil) }
                                if await tracker.getIsCancelled() { return ([], u, nil) }

                                if let mdURL = result.markdownURL {
                                    generated.append(ExtractedMediaItem(
                                        title: mdURL.lastPathComponent,
                                        url: mdURL,
                                        category: .document,
                                        platform: platform,
                                        dateString: dateStr
                                    ))
                                }

                                if shouldSaveVideo {
                                    generated += result.videoURLs.map {
                                        ExtractedMediaItem(title: $0.lastPathComponent, url: $0, category: .video, platform: platform, dateString: dateStr)
                                    }
                                }
                                var derivativeFailures = result.qualityWarnings
                                for videoURL in result.videoURLs {
                                    do {
                                        try await Self.generateDerivedMedia(
                                            from: videoURL, gifDirectory: gifDir, livePhotoDirectory: livePhotoDir,
                                            platform: platform, dateString: dateStr,
                                            generateGIF: shouldGenerateGIF, convertToLivePhoto: shouldConvertToLivePhoto,
                                            autoImportPhotos: shouldAutoImportPhotos, outputs: &generated
                                        )
                                    } catch {
                                        if Task.isCancelled || error is CancellationError { throw CancellationError() }
                                        derivativeFailures.append("\(videoURL.lastPathComponent)：\(error.localizedDescription)")
                                    }
                                }
                                if !derivativeFailures.isEmpty {
                                    throw NetworkVideoDownloader.DownloadError.executionError(derivativeFailures.joined(separator: "；"))
                                }

                            } else {
                                // 小红书或通用网络视频
                                let downloadedFileURL = try await NetworkVideoDownloader.downloadVideo(
                                    url: u,
                                    targetDirectory: videoDir,
                                    videoOutputDir: videoDir,
                                    markdownOutputDir: docDir,
                                    shouldRemoveWatermark: shouldRemoveWatermark,
                                    quality: itemQuality,
                                    preParsedTwitter: preItem?.twitterPostInfo,
                                    preParsedXHS: preItem?.xhsParsedInfo,
                                    preParsedBilibili: preItem?.bilibiliParsedInfo
                                ) { line in
                                    Task {
                                        await tracker.updateDescription(id: taskIdx, desc: "[\(platform.rawValue)] \(line)")
                                        await self.updateProgress(tracker: tracker, total: total)
                                    }
                                }

                                if Task.isCancelled { return ([], u, nil) }
                                if await tracker.getIsCancelled() { return ([], u, nil) }

                                if shouldSaveVideo {
                                    generated.append(ExtractedMediaItem(title: downloadedFileURL.lastPathComponent, url: downloadedFileURL, category: .video, platform: platform, dateString: dateStr))
                                }
                                try await Self.generateDerivedMedia(
                                    from: downloadedFileURL, gifDirectory: gifDir, livePhotoDirectory: livePhotoDir,
                                    platform: platform, dateString: dateStr,
                                    generateGIF: shouldGenerateGIF, convertToLivePhoto: shouldConvertToLivePhoto,
                                    autoImportPhotos: shouldAutoImportPhotos, outputs: &generated
                                )
                            }

                            guard !generated.isEmpty else {
                                throw NetworkVideoDownloader.DownloadError.executionError("未提取到有效成果，请检查链接内容或选择其他输出格式。")
                            }
                            await tracker.markSuccess(id: taskIdx)

                        } catch {
                            failureMessage = error.localizedDescription
                            await tracker.markFailure(id: taskIdx, message: error.localizedDescription)
                        }

                        await self.updateProgress(tracker: tracker, total: total)
                        return (generated, u, failureMessage)
                    }
                }

                for await result in group {
                    let items = result.outputs
                    savedFileCount += items.count
                    if !items.isEmpty {
                        await MainActor.run {
                            for it in items {
                                self.downloadedMediaItems.insert(it, at: 0)
                                if it.category == .video {
                                    DownloadCacheManager.shared.recordCompletedDownload(sourceURL: result.source, fileURL: it.url)
                                }
                            }

                            if let first = items.first {
                                let historyOutputs: [HistoryOutputItem] = items.map { it in
                                    let size = (try? FileManager.default.attributesOfItem(atPath: it.url.path)[.size] as? Int64) ?? 0
                                    return HistoryOutputItem(
                                        fileName: it.url.lastPathComponent,
                                        filePath: it.url.path,
                                        category: it.category.rawValue,
                                        fileSize: size
                                    )
                                }
                                OperationHistoryManager.shared.record(
                                    source: .networkExtractor,
                                    platform: first.platform.rawValue,
                                    title: "[\(first.platform.rawValue)] \(result.failure == nil ? "提取完成" : "部分成果已保存"): \(first.title)",
                                    originalURLOrPath: result.source,
                                    status: result.failure == nil ? .success : .failed,
                                    outputs: historyOutputs,
                                    note: result.failure ?? "已自动分类归档至 \(first.relativeDisplayPath)"
                                )
                            }
                        }
                    }
                }
            }

            if self.isCancelledByUser || Task.isCancelled {
                WorkExecutionManager.shared.cancelAndCleanup(targetDirectory: appSettings.downloadURL)
                await MainActor.run {
                    self.isDownloading = false
                    self.vm.isNetworkRunning = false
                    self.isCancelling = false
                    self.downloadTask = nil
                    self.progressPercent = 0
                    self.currentProgressText = ""
                    MenuBarState.shared.finishNetwork(detail: "已完成的文件仍保留在保存目录", failed: false, cancelled: true)
                    OperationHistoryManager.shared.record(
                        source: .networkExtractor,
                        platform: "网络",
                        title: "网络视频批量提取 (用户取消)",
                        status: .cancelled,
                        note: "任务已被用户主动打断并清理未完成碎片"
                    )
                }
                return
            }

            let counts = await tracker.getSuccessAndFail()
            let successCount = counts.success
            let failCount = counts.fail

            await MainActor.run {
                self.isDownloading = false
                self.vm.isNetworkRunning = false
                self.isCancelling = false
                self.downloadTask = nil
                self.progressPercent = 1.0
                MenuBarState.shared.finishNetwork(detail: "完成 \(successCount) 项 · 未全部完成 \(failCount) 项 · 已保存 \(savedFileCount) 个成果", failed: failCount > 0 || successCount == 0)

                if successCount > 0 || savedFileCount > 0 {
                    var banner = "完整完成 \(successCount) 项任务\(failCount > 0 ? "，\(failCount) 项未全部完成" : "")，已保存 \(savedFileCount) 个成果。"
                    banner += "可在下方查看文件，未完成项目可检查原因后重试。"
                    if failCount > 0, let message = counts.firstFailure {
                        banner += " 失败原因：\(message)"
                    }
                    self.downloadHadFailures = failCount > 0
                    self.successBannerMessage = banner
                } else {
                    self.errorMessage = counts.firstFailure ?? "请检查链接是否公开有效，以及网络和登录信息是否可用。"
                    OperationHistoryManager.shared.record(
                        source: .networkExtractor,
                        platform: "网络",
                        title: "批量网络视频提取失败",
                        status: .failed,
                        note: "未能成功提取有效媒体，请检查网络或Cookie状态"
                    )
                }
            }
        }
    }

    /// 每个阶段都传播失败；已完成成果保留并显示，避免失败被误报为全部成功。
    private static func generateDerivedMedia(
        from videoURL: URL, gifDirectory: URL, livePhotoDirectory: URL,
        platform: PlatformCategory, dateString: String,
        generateGIF: Bool, convertToLivePhoto: Bool, autoImportPhotos: Bool,
        outputs: inout [ExtractedMediaItem]
    ) async throws {
        try Task.checkCancellation()
        let basename = videoURL.deletingPathExtension().lastPathComponent
        if generateGIF {
            let temporaryGIF = ConversionEngine.appTempDirectoryURL.appendingPathComponent("gif-\(UUID().uuidString).gif")
            defer { try? FileManager.default.removeItem(at: temporaryGIF) }
            try await GIFConverter.convertToGIF(videoURL: videoURL, outputURL: temporaryGIF)
            try Task.checkCancellation()
            let destination = CategorizedStorageManager.resolveDestination(in: gifDirectory, filename: basename + ".gif", policy: .rename).destinationURL
            try FileManager.default.moveItem(at: temporaryGIF, to: destination)
            outputs.append(ExtractedMediaItem(title: destination.lastPathComponent, url: destination, category: .gif, platform: platform, dateString: dateString))
        }
        if convertToLivePhoto {
            let assetID = UUID().uuidString
            let frame = try await ConversionEngine.extractFrame(from: videoURL, at: 0, assetIdentifier: assetID)
            defer { try? FileManager.default.removeItem(at: frame) }
            let movie = try await ConversionEngine.convertToMOV(input: videoURL, assetIdentifier: assetID)
            defer { try? FileManager.default.removeItem(at: movie) }
            try Task.checkCancellation()
            let pair = try ConversionEngine.exportPair(imageURL: frame, videoURL: movie, to: livePhotoDirectory, basename: basename)
            for url in pair {
                outputs.append(ExtractedMediaItem(title: url.lastPathComponent, url: url, category: .livePhoto, platform: platform, dateString: dateString))
            }
            if autoImportPhotos {
                try await ConversionEngine.importToPhotos(imageURL: pair[0], videoURL: pair[1])
            }
        }
    }

    @MainActor
    private func updateProgress(tracker: NetworkExtractorView_Tracker, total: Int) async {
        let snapshot = await tracker.snapshot()
        guard isDownloading, !isCancelledByUser else { return }
        let finished = snapshot.finished
        let activeDescs = snapshot.active

        self.progressPercent = Double(finished) / Double(max(1, total))
        if activeDescs.isEmpty {
            self.currentProgressText = "已完成 \(finished) / \(total) 项，正在处理…"
        } else {
            self.currentProgressText = "已完成 \(finished) / \(total) 项 · \(activeDescs)"
        }
        MenuBarState.shared.updateNetwork(detail: currentProgressText, progress: progressPercent)
    }
}

// 供多线程传递状态的轻量级并发 actor
private actor NetworkExtractorView_Tracker {
    var finishedCount = 0
    var successCount = 0
    var failCount = 0
    var isCancelled = false
    var activeDescriptions: [Int: String] = [:]
    var failureDescriptions: [Int: String] = [:]

    func updateDescription(id: Int, desc: String) {
        activeDescriptions[id] = desc
    }

    func markSuccess(id: Int) {
        finishedCount += 1
        successCount += 1
        activeDescriptions.removeValue(forKey: id)
    }

    func markFailure(id: Int, message: String) {
        finishedCount += 1
        failCount += 1
        failureDescriptions[id] = message
        activeDescriptions.removeValue(forKey: id)
    }

    func cancel() {
        isCancelled = true
    }

    func getIsCancelled() -> Bool {
        isCancelled
    }

    func getSuccessAndFail() -> (success: Int, fail: Int, firstFailure: String?) {
        let firstFailure = failureDescriptions.keys.sorted().first.flatMap { failureDescriptions[$0] }
        return (successCount, failCount, firstFailure)
    }

    func snapshot() -> (finished: Int, active: String) {
        let active = activeDescriptions.values.prefix(2).joined(separator: " | ")
        return (finishedCount, active)
    }
}

