import SwiftUI
import AppKit

public struct OperationHistoryView: View {
    @ObservedObject private var historyManager = OperationHistoryManager.shared
    @State private var showClearConfirmAlert = false
    @State private var copiedItemId: UUID?
    @State private var copyFeedbackID = UUID()
    @State private var feedbackMessage: String?
    @State private var feedbackID = UUID()
    @FocusState private var searchIsFocused: Bool

    public init() {}

    private var hasActiveFilters: Bool {
        !historyManager.searchText.isEmpty || historyManager.filterSource != nil
            || historyManager.filterStatus != nil || historyManager.filterPlatform != nil
    }

    public var body: some View {
        VStack(spacing: 18) {
            statsOverviewCard
            filterAndSearchBar

            if let message = feedbackMessage {
                ForgeStatusBanner(title: message, systemImage: "checkmark.circle", tint: .green)
            }

            if historyManager.filteredItems.isEmpty {
                emptyStateView
            } else {
                historyList
            }
        }
        .padding(24)
        .background(Color(nsColor: .windowBackgroundColor))
        .background {
            Button("搜索历史记录") { searchIsFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()
                .accessibilityHidden(true)
        }
        .alert(isPresented: $showClearConfirmAlert) {
            Alert(
                title: Text("清空所有历史记录？"),
                message: Text("操作记录与文件明细将被清除，磁盘上的媒体文件会保留。此操作无法撤销。"),
                primaryButton: .destructive(Text("清空记录")) {
                    historyManager.clearAll()
                    resetFilters()
                    showFeedback("历史记录已清空。")
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
    }

    private var statsOverviewCard: some View {
        HStack(spacing: 28) {
            statValue("全部记录", value: historyManager.totalCount)
            Divider().frame(height: 32)
            statValue("成功完成", value: historyManager.successCount)
            Divider().frame(height: 32)
            statValue("输出文件", value: historyManager.totalOutputsCount)
            Spacer()

            Button("清空历史…", role: .destructive) {
                showClearConfirmAlert = true
            }
            .buttonStyle(.bordered)
            .disabled(historyManager.historyItems.isEmpty)
            .help("清空所有操作记录，保留媒体文件")
        }
        .padding(18)
        .forgeSurface()
    }

    private func statValue(_ title: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value.formatted())
                .font(.system(size: 23, weight: .medium, design: .rounded))
                .monospacedDigit()
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var filterAndSearchBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索标题、链接或文件名", text: $historyManager.searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .focused($searchIsFocused)
                        .onExitCommand {
                            if historyManager.searchText.isEmpty {
                                searchIsFocused = false
                            } else {
                                historyManager.searchText = ""
                            }
                        }
                        .accessibilityLabel("搜索操作历史")
                    if !historyManager.searchText.isEmpty {
                        Button {
                            historyManager.searchText = ""
                            searchIsFocused = true
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("清除搜索")
                        .accessibilityLabel("清除搜索")
                    }
                }
                .padding(.horizontal, 11)
                .frame(height: 34)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(searchIsFocused ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.08), lineWidth: 1)
                }

                Picker("来源", selection: $historyManager.filterSource) {
                    Text("全部来源").tag(nil as OperationSource?)
                    ForEach(OperationSource.allCases, id: \.self) { source in
                        Text(source.rawValue).tag(source as OperationSource?)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 115)
                .accessibilityLabel("筛选操作来源")

                Picker("状态", selection: $historyManager.filterStatus) {
                    Text("全部状态").tag(nil as OperationStatus?)
                    ForEach(OperationStatus.allCases, id: \.self) { status in
                        Text(status.rawValue).tag(status as OperationStatus?)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 105)
                .accessibilityLabel("筛选操作状态")
            }

            HStack {
                Text(hasActiveFilters ? "找到 \(historyManager.filteredItems.count) 条记录" : "最近的记录显示在前")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                if hasActiveFilters {
                    Button("重置筛选") { resetFilters() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    private var historyList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(historyManager.filteredItems) { item in
                    historyItemCard(item)
                }
            }
            .padding(.bottom, 8)
        }
    }

    private func historyItemCard(_ item: OperationHistoryItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Label(item.source.rawValue, systemImage: item.source.icon)
                    .foregroundStyle(.secondary)
                if !item.platform.isEmpty && item.platform != "本地" {
                    Text("·").foregroundStyle(.tertiary)
                    Text(item.platform).foregroundStyle(.secondary)
                }
                Spacer()
                Label(item.status.rawValue, systemImage: item.status.icon)
                    .foregroundStyle(item.status.color)
                Text(item.timeAgo)
                    .foregroundStyle(.secondary)
                    .help(item.formattedDate)
                Button {
                    historyManager.removeItem(id: item.id)
                    showFeedback("记录已移除，媒体文件已保留。")
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(ForgeIconButtonStyle())
                .help("移除此条记录，保留媒体文件")
                .accessibilityLabel("移除记录：\(item.title)")
            }
            .font(.system(size: 11))

            Text(item.title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(2)
                .textSelection(.enabled)

            if let source = item.originalURLOrPath, !source.isEmpty {
                sourceRow(source, item: item)
            }

            if !item.outputs.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Divider()
                    Text("输出文件 · \(item.outputs.count)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    ForEach(item.outputs) { output in
                        outputRow(output)
                    }
                }
            }

            if let note = item.note, !note.isEmpty {
                Label {
                    Text(note).textSelection(.enabled)
                } icon: {
                    Image(systemName: item.status == .failed ? "exclamationmark.circle" : "info.circle")
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .forgeSurface()
    }

    private func sourceRow(_ source: String, item: OperationHistoryItem) -> some View {
        let isWebLink = source.hasPrefix("https://") || source.hasPrefix("http://")
        return HStack(spacing: 8) {
            Image(systemName: isWebLink ? "link" : "folder")
                .foregroundStyle(.secondary)
            Text(source)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(source)
            Spacer(minLength: 8)
            Button {
                NSPasteboard.general.clearContents()
                let didCopy = NSPasteboard.general.setString(source, forType: .string)
                guard didCopy else { return }
                let copyID = UUID()
                copyFeedbackID = copyID
                copiedItemId = item.id
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    if copyFeedbackID == copyID { copiedItemId = nil }
                }
            } label: {
                Label(copiedItemId == item.id ? "已复制" : (isWebLink ? "复制链接" : "复制路径"), systemImage: copiedItemId == item.id ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11))
                    .foregroundStyle(copiedItemId == item.id ? Color.green : Color.accentColor)
                    .frame(minWidth: 64, alignment: .trailing)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
    }

    private func outputRow(_ output: HistoryOutputItem) -> some View {
        HStack(spacing: 9) {
            Image(systemName: outputIcon(output.category))
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .help(output.category)
                .accessibilityLabel(output.category)
            Text(output.fileName)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
                .help(output.filePath)
            if !output.formattedSize.isEmpty {
                Text(output.formattedSize)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if output.exists {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([output.fileURL])
                } label: {
                    Label("在访达中显示", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(output.filePath)
            } else {
                Text("文件不可用")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .help("文件可能已移动或清理")
            }
        }
    }

    private func outputIcon(_ category: String) -> String {
        switch category {
        case "视频": return "video"
        case "实况": return "livephoto"
        case "GIF": return "photo.on.rectangle.angled"
        case "文档": return "doc.text"
        default: return "doc"
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 24)
            Image(systemName: hasActiveFilters ? "magnifyingglass" : "clock.arrow.circlepath")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.tertiary)
            Text(hasActiveFilters ? "没有匹配的记录" : "还没有操作记录")
                .font(.system(size: 17, weight: .semibold))
            Text(hasActiveFilters ? "试试其他关键词，或重置筛选条件。" : "完成制作或网络提取后，可在这里查看结果、复制来源与查找文件。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
            if hasActiveFilters {
                Button("重置筛选") { resetFilters() }
                    .buttonStyle(.bordered)
            }
            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func resetFilters() {
        historyManager.searchText = ""
        historyManager.filterSource = nil
        historyManager.filterStatus = nil
        historyManager.filterPlatform = nil
    }

    private func showFeedback(_ message: String) {
        let id = UUID()
        feedbackID = id
        feedbackMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            if feedbackID == id { feedbackMessage = nil }
        }
    }
}
