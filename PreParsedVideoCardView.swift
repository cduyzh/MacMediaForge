import SwiftUI
import AppKit

struct PreParsedVideoCardView: View {
    @ObservedObject var item: PreParsedVideoItem
    var isInteractionEnabled = true
    var onOpenCollectionSheet: ((BilibiliCollectionInfo) -> Void)? = nil
    var onEnrollAllEpisodes: ((BilibiliCollectionInfo) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Toggle("", isOn: $item.isSelectedForDownload)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .disabled(!isInteractionEnabled)
                    .help(item.isSelectedForDownload ? "取消勾选此视频（不下载）" : "勾选此视频以加入下载")
                    .padding(.top, 24)

                thumbnailSection

                VStack(alignment: .leading, spacing: 7) {
                    Text(displayTitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(item.isSelectedForDownload ? .primary : .secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .help(item.title)

                    HStack(spacing: 6) {
                        Text(item.platform.rawValue)
                        if item.status.isReady {
                            Text("·")
                            Text(item.author)
                                .lineLimit(1)
                            if item.videoCount > 1 {
                                Text("· \(item.videoCount) 个视频")
                                    .fixedSize()
                            }
                        }
                        if let dur = item.durationStr, !dur.isEmpty {
                            Text("· \(dur)")
                        }
                        if !item.quality.isEmpty {
                            Text("· \(item.quality)")
                                .lineLimit(1)
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                    if let url = URL(string: item.originalURL) {
                        Link(destination: url) {
                            Text(item.originalURL)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .help("打开原始链接：\(item.originalURL)")
                        .accessibilityLabel("打开 \(item.platform.rawValue) 原始链接")
                    }

                    if case .failed(let message) = item.status {
                        Text(message)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .help(message)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                VStack(alignment: .trailing, spacing: 10) {
                    statusView
                        .font(.system(size: 11))
                    if case .failed = item.status {
                        Button {
                            NetworkVideoPreParser.shared.retryItem(item)
                        } label: {
                            Label("重试", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!isInteractionEnabled)
                        .help("重新解析这条链接；也可直接尝试下载")
                        .accessibilityLabel("重新解析 \(item.originalURL)")
                    }
                }
                .padding(.top, 2)
            }

            // 合集专属快捷操作横幅
            if let coll = item.bilibiliCollection {
                collectionBanner(coll)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(item.isSelectedForDownload ? Color.primary.opacity(0.025) : Color.primary.opacity(0.01))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(item.isSelectedForDownload ? Color.primary.opacity(0.06) : Color.primary.opacity(0.03), lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    private func collectionBanner(_ coll: BilibiliCollectionInfo) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "film.stack.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(coll.typeLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.12))
                        .foregroundStyle(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 3))

                    Text(coll.title)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                }

                Text("\(coll.sections.count) 个分卷 · 共 \(coll.epCount) 个视频")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button {
                if let onEnrollAllEpisodes {
                    onEnrollAllEpisodes(coll)
                }
            } label: {
                Label("全部录入 (\(coll.epCount))", systemImage: "plus.square.on.square")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!isInteractionEnabled)
            .help("将合集中的全部 \(coll.epCount) 个视频全部填入下载队列")

            Button {
                if let onOpenCollectionSheet {
                    onOpenCollectionSheet(coll)
                }
            } label: {
                Label("选集下载…", systemImage: "checklist")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!isInteractionEnabled)
            .help("打开合集选集器，手动挑选需要下载的集数")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.accentColor.opacity(0.18), lineWidth: 1)
        )
    }

    private var displayTitle: String {
        if item.title == item.originalURL {
            switch item.status {
            case .pending: return "等待获取视频信息"
            case .parsing: return "正在获取视频信息…"
            case .failed: return "未能获取视频信息"
            case .ready: return "网络视频"
            }
        }
        return item.title
    }

    private var thumbnailSection: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.045))
            if let image = item.previewImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 104, height: 68)
                    .clipped()
            } else if item.status.isParsing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "film")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 104, height: 68)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var statusView: some View {
        switch item.status {
        case .ready:
            Label("已解析", systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
                .help("下载时将优先使用已获取的视频信息")
        case .parsing:
            Text("解析中…")
                .foregroundStyle(.secondary)
        case .pending:
            Label("等待中", systemImage: "clock")
                .foregroundStyle(.secondary)
        case .failed:
            Label("预览失败", systemImage: "exclamationmark.circle")
                .foregroundStyle(.orange)
        }
    }
}
