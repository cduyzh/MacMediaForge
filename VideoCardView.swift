import SwiftUI
import AppKit

struct VideoCardView: View {
    @ObservedObject var item: VideoItem
    @ObservedObject var vm: ConversionViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    @State private var showsEditor = false
    @State private var showsError = false
    @State private var coverPreviewTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 15) {
                thumbnailView
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.filename)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(item.filename)
                    HStack(spacing: 8) {
                        Text(item.durationText)
                        Text("·")
                        Text(item.resolution)
                        Text("·")
                        Text(item.fileSize)
                        if item.isEdited {
                            Text("已调整").foregroundStyle(Color.accentColor)
                        }
                    }
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
                    statusLine
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 6) {
                    if item.status == .completed {
                        Button(action: showResult) {
                            Label(resultTitle, systemImage: item.completedMode == .livePhoto ? "photo.on.rectangle" : "folder")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { showsEditor.toggle() }
                    } label: { Image(systemName: "slider.horizontal.3") }
                    .buttonStyle(ForgeIconButtonStyle())
                    .disabled(vm.isRunning || item.isLoadingMetadata || item.duration <= 0)
                    .help(showsEditor ? "收起视频调整" : "调整片段、速度与封面")
                    .accessibilityLabel(showsEditor ? "收起视频调整" : "调整视频")

                    Button { item.revealInFinder() } label: { Image(systemName: "doc") }
                        .buttonStyle(ForgeIconButtonStyle())
                        .help("在访达中显示原视频")
                        .accessibilityLabel("显示原视频")

                    Button { Task { await vm.convert(item) } } label: {
                        if item.status.isWorking {
                            ProgressView().controlSize(.mini).frame(width: 18, height: 18)
                        } else {
                            Image(systemName: item.status == .completed ? "arrow.clockwise" : "play.fill")
                                .frame(width: 18, height: 18)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(vm.isRunning || vm.isNetworkRunning || !item.canConvert)
                    .help(item.status == .completed ? "按当前格式重新制作" : "制作\(vm.selectedMode.title)")
                    .accessibilityLabel(item.status == .completed ? "重新制作\(item.filename)" : "制作\(item.filename)")

                    Button { vm.items.removeAll { $0.id == item.id } } label: { Image(systemName: "xmark") }
                        .buttonStyle(ForgeIconButtonStyle())
                        .disabled(vm.isRunning)
                        .help("从队列中移除，保留原文件")
                        .accessibilityLabel("从队列移除\(item.filename)")
                }
            }
            .padding(16)

            if showsError, case .failed(let message) = item.status {
                HStack(alignment: .top, spacing: 12) {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("复制") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(message, forType: .string)
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }

            if showsEditor {
                Divider().opacity(0.5)
                editPanel.padding(18)
            }
        }
        .forgeSurface(cornerRadius: 13)
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(isHovering ? Color.primary.opacity(0.1) : Color.clear, lineWidth: 0.5)
                .allowsHitTesting(false)
        }
        .onHover { isHovering = $0 }
        .onDisappear { coverPreviewTask?.cancel() }
    }

    private var thumbnailView: some View {
        ZStack {
            Color.primary.opacity(0.04)
            if let thumbnail = item.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if item.isLoadingMetadata {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "film").font(.system(size: 20, weight: .light)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 92, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityHidden(true)
    }

    @ViewBuilder private var statusLine: some View {
        if item.isLoadingMetadata {
            Text("正在读取视频信息…").font(.system(size: 11)).foregroundStyle(.secondary)
        } else if case .failed = item.status {
            Button { showsError.toggle() } label: {
                Label(showsError ? "转换失败 · 收起详情" : "转换失败 · 查看原因", systemImage: "exclamationmark.circle")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        } else {
            Label(completionLabel, systemImage: item.status.icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(item.status == .completed ? Color.green : (item.status.isWorking ? Color.accentColor : Color.secondary))
        }
    }

    private var completionLabel: String {
        guard item.status == .completed else { return item.status.label }
        switch item.completedMode {
        case .livePhoto: return "已保存到照片"
        case .gif: return "GIF 已生成"
        case .files: return "配对文件已导出"
        case nil: return "已完成"
        }
    }

    private var resultTitle: String {
        switch item.completedMode {
        case .livePhoto: return "查看照片"
        case .gif: return "显示 GIF"
        default: return "显示文件"
        }
    }

    private func showResult() {
        if item.completedMode == .livePhoto { item.openPhotosApp() }
        else { NSWorkspace.shared.activateFileViewerSelecting(item.outputURLs) }
    }

    private var editPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("视频调整").font(.system(size: 12, weight: .semibold))
                Text("输出约 \(String(format: "%.1f", (item.endTime - item.startTime) / Double(item.playbackSpeed))) 秒")
                    .font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                Button("重置") {
                    coverPreviewTask?.cancel()
                    item.resetEdit()
                    markEdited()
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11.5))
                .disabled(!item.isEdited)
            }
            editSlider("起点", value: Binding(get: { item.startTime }, set: {
                item.startTime = min($0, max(0, item.endTime - minimumGap))
                clampCover()
                markEdited()
            }), range: 0...max(0.01, item.duration))
            editSlider("终点", value: Binding(get: { item.endTime }, set: {
                item.endTime = min(item.duration, max($0, item.startTime + minimumGap))
                clampCover()
                markEdited()
            }), range: 0...max(0.01, item.duration))
            HStack(spacing: 16) {
                Text("速度").font(.system(size: 12)).frame(width: 34, alignment: .leading)
                Picker("播放速度", selection: Binding(get: { item.playbackSpeed }, set: { item.playbackSpeed = $0; markEdited() })) {
                    ForEach([Float(0.5), 1, 1.5, 2], id: \.self) { speed in
                        Text("\(String(format: "%g", speed))×").tag(speed)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 340)
                Spacer(minLength: 0)
            }
            if vm.selectedMode != .gif {
                editSlider("封面", value: Binding(get: { item.effectiveCoverTime }, set: {
                    item.coverTime = $0
                    markEdited()
                    scheduleCoverPreview()
                }), range: item.startTime...max(item.startTime + 0.001, item.endTime - 0.001))
                Text("缩略图显示当前选定的封面。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .disabled(vm.isRunning)
    }

    private var minimumGap: Double { min(0.1, item.duration / 2) }

    private func editSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack(spacing: 16) {
            Text(title).font(.system(size: 12)).frame(width: 34, alignment: .leading)
            Slider(value: value, in: range)
                .accessibilityLabel("\(title)时间")
            Text("\(String(format: "%.1f", value.wrappedValue)) 秒")
                .font(.system(size: 11.5).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 65, alignment: .trailing)
        }
    }

    private func markEdited() {
        if item.status == .completed { item.status = .pending }
    }

    private func clampCover() {
        item.coverTime = min(max(item.startTime, item.coverTime), max(item.startTime, item.endTime - 0.001))
        scheduleCoverPreview()
    }

    private func scheduleCoverPreview() {
        coverPreviewTask?.cancel()
        let time = item.effectiveCoverTime
        coverPreviewTask = Task {
            do { try await Task.sleep(nanoseconds: 180_000_000) } catch { return }
            guard !Task.isCancelled else { return }
            await item.generateThumbnail(at: time)
        }
    }
}
