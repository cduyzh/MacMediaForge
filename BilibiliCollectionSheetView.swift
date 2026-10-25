import SwiftUI
import AppKit

// MARK: - Bilibili 合集 / 分P 选集与批量下载弹窗
struct BilibiliCollectionSheetView: View {
    let collection: BilibiliCollectionInfo
    var onConfirmAndDownload: (([BilibiliEpisodeItem]) -> Void)?
    var onEnrollToInput: (([BilibiliEpisodeItem]) -> Void)?
    var onDismiss: () -> Void

    @State private var selectedEpisodeIds: Set<String> = []
    @State private var selectedSectionId: Int? = nil // nil 表示全部
    @State private var searchText: String = ""
    @State private var isIntroExpanded: Bool = false

    private var allEpisodes: [BilibiliEpisodeItem] {
        collection.allEpisodes
    }

    private var filteredEpisodes: [BilibiliEpisodeItem] {
        var list = allEpisodes
        if let sId = selectedSectionId {
            if let sec = collection.sections.first(where: { $0.id == sId }) {
                list = sec.episodes
            }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            list = list.filter {
                $0.title.localizedCaseInsensitiveContains(query) ||
                $0.bvid.localizedCaseInsensitiveContains(query) ||
                $0.sectionTitle.localizedCaseInsensitiveContains(query)
            }
        }
        return list
    }

    private var selectedEpisodes: [BilibiliEpisodeItem] {
        allEpisodes.filter { selectedEpisodeIds.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            toolbarArea
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))

            Divider()

            episodeListView

            Divider()
            bottomActionBar
        }
        .frame(minWidth: 840, idealWidth: 880, maxWidth: 960, minHeight: 600, idealHeight: 680, maxHeight: 800)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            initDefaultSelection()
        }
    }

    // 默认全选合集内所有视频
    private func initDefaultSelection() {
        if selectedEpisodeIds.isEmpty {
            selectedEpisodeIds = Set(allEpisodes.map { $0.id })
        }
    }

    // MARK: - 顶部标题与合集概览
    private var headerBar: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 80, height: 80)

                if let coverStr = collection.coverUrl, let url = URL(string: coverStr) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure(_), .empty:
                            Image(systemName: "film.stack")
                                .font(.system(size: 28))
                                .foregroundStyle(.secondary)
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    Image(systemName: "film.stack")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(collection.typeLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundStyle(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    Text(collection.title)
                        .font(.system(size: 16, weight: .bold))
                        .lineLimit(2)
                        .help(collection.title)
                }

                HStack(spacing: 12) {
                    Label("\(collection.sections.count) 个分卷", systemImage: "folder")
                    Label("共 \(collection.epCount) 个视频", systemImage: "play.circle")
                    if !allEpisodes.isEmpty {
                        let totalSec = allEpisodes.reduce(0) { $0 + $1.duration }
                        let h = totalSec / 3600
                        let m = (totalSec % 3600) / 60
                        let durDesc = h > 0 ? "\(h)小时\(m)分钟" : "\(m)分钟"
                        Label("总时长约 \(durDesc)", systemImage: "clock")
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

                if !collection.intro.isEmpty {
                    Text(collection.intro)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(isIntroExpanded ? 4 : 1)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isIntroExpanded.toggle()
                            }
                        }
                        .help("点击展开或收起简介")
                }
            }

            Spacer(minLength: 16)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("关闭 (Esc)")
            .accessibilityLabel("关闭合集选集")
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    // MARK: - 工具栏：分卷筛选、搜索与全选控制
    private var toolbarArea: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                // 搜索框
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    TextField("搜索本合集视频标题或 BV 号…", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )
                .frame(maxWidth: 320)

                Spacer()

                // 快捷选择按钮组
                HStack(spacing: 6) {
                    Button("全选") {
                        selectAllFiltered()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("取消全选") {
                        deselectAllFiltered()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("反选") {
                        invertSelectionFiltered()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    if let curr = allEpisodes.first(where: { $0.isCurrent }) {
                        Button("仅选当前单集") {
                            selectOnlyCurrent(curr)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("只选择当前打开的这 1 集")
                    }
                }

                Text("已选 \(selectedEpisodeIds.count) / \(allEpisodes.count) 项")
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(selectedEpisodeIds.isEmpty ? Color.orange : Color.secondary)
                    .padding(.leading, 4)
            }

            // 分卷标签横向滚动条 (若分卷数大于 1)
            if collection.sections.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        sectionPill(title: "全部 (\(allEpisodes.count))", isSelected: selectedSectionId == nil) {
                            selectedSectionId = nil
                        }

                        ForEach(collection.sections) { sec in
                            sectionPill(
                                title: "\(sec.title) (\(sec.episodes.count))",
                                isSelected: selectedSectionId == sec.id
                            ) {
                                selectedSectionId = sec.id
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func sectionPill(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isSelected ? Color.accentColor : Color.primary.opacity(0.06))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 视频单集列表
    private var episodeListView: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                if filteredEpisodes.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 28))
                            .foregroundStyle(.tertiary)
                        Text("未找到匹配的视频")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                } else {
                    ForEach(Array(filteredEpisodes.enumerated()), id: \.element.id) { index, ep in
                        episodeRow(index: index + 1, episode: ep)
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
        }
    }

    private func episodeRow(index: Int, episode: BilibiliEpisodeItem) -> some View {
        let isSelected = selectedEpisodeIds.contains(episode.id)

        return HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { isSelected },
                set: { val in
                    if val {
                        selectedEpisodeIds.insert(episode.id)
                    } else {
                        selectedEpisodeIds.remove(episode.id)
                    }
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            Text("#\(index)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 34, alignment: .trailing)

            // 封面图
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.04))
                    .frame(width: 88, height: 50)

                if let cover = episode.coverUrl, let url = URL(string: cover) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure(_), .empty:
                            Color.primary.opacity(0.06)
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(width: 88, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                if !episode.durationStr.isEmpty {
                    Text(episode.durationStr)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.black.opacity(0.72))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .padding(3)
                }
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if episode.isCurrent {
                        Text("当前链接")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.18))
                            .foregroundStyle(Color.green)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }

                    if !episode.sectionTitle.isEmpty && episode.sectionTitle != "视频分P" {
                        Text(episode.sectionTitle)
                            .font(.system(size: 10))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.primary.opacity(0.06))
                            .foregroundStyle(.secondary)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }

                    Text(episode.title)
                        .font(.system(size: 12, weight: episode.isCurrent ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .lineLimit(1)
                        .help(episode.title)
                }

                HStack(spacing: 10) {
                    Text(episode.bvid)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)

                    if !episode.author.isEmpty {
                        Text("UP: \(episode.author)")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            Button("仅选此集") {
                selectOnlySingle(episode)
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 6)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.06) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelected {
                selectedEpisodeIds.remove(episode.id)
            } else {
                selectedEpisodeIds.insert(episode.id)
            }
        }
    }

    // MARK: - 底部操作栏
    private var bottomActionBar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("已勾选 \(selectedEpisodeIds.count) 个视频")
                    .font(.system(size: 13, weight: .semibold))
                Text("将提取原画质/1080P多轨音视频，无损封装为 MP4 并按合集归档。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("取消") {
                onDismiss()
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.cancelAction)

            if let onEnrollToInput {
                Button {
                    onEnrollToInput(selectedEpisodes)
                    onDismiss()
                } label: {
                    Label("录入到输入框 (\(selectedEpisodeIds.count))", systemImage: "text.badge.plus")
                }
                .buttonStyle(.bordered)
                .disabled(selectedEpisodeIds.isEmpty)
                .help("将选中的视频链接填入主界面输入框，方便后续检查与组合")
            }

            Button {
                let eps = selectedEpisodes
                onDismiss()
                if let onConfirmAndDownload {
                    onConfirmAndDownload(eps)
                }
            } label: {
                Label("立即开始下载 (\(selectedEpisodeIds.count) 项)", systemImage: "arrow.down.circle.fill")
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(selectedEpisodeIds.isEmpty)
            .keyboardShortcut(.defaultAction)
            .help("立即下载勾选的全部视频（Return）")
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(.regularMaterial)
    }

    // MARK: - 批处理逻辑
    private func selectAllFiltered() {
        for ep in filteredEpisodes {
            selectedEpisodeIds.insert(ep.id)
        }
    }

    private func deselectAllFiltered() {
        for ep in filteredEpisodes {
            selectedEpisodeIds.remove(ep.id)
        }
    }

    private func invertSelectionFiltered() {
        for ep in filteredEpisodes {
            if selectedEpisodeIds.contains(ep.id) {
                selectedEpisodeIds.remove(ep.id)
            } else {
                selectedEpisodeIds.insert(ep.id)
            }
        }
    }

    private func selectOnlyCurrent(_ curr: BilibiliEpisodeItem) {
        selectedEpisodeIds = [curr.id]
    }

    private func selectOnlySingle(_ ep: BilibiliEpisodeItem) {
        selectedEpisodeIds = [ep.id]
    }
}
