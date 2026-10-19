import SwiftUI
import AppKit

// MARK: - 设置面板视图
struct SettingsView: View {
    @ObservedObject private var cacheManager = DownloadCacheManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showClearConfirmAlert = false
    @State private var showSuccessBanner = false
    @State private var successBannerMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            // 顶栏标题
            headerBar
            Divider()

            // 主体滚动内容
            ScrollView {
                VStack(spacing: 20) {
                    if showSuccessBanner {
                        successNotice
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // 1. 缓存存储位置管理
                    cacheDirectorySection

                    // 2. 缓存空间占用与一键清理
                    cacheUsageAndCleanSection

                    // 3. 历史下载文件记录
                    downloadHistorySection
                }
                .padding(24)
            }

            Divider()

            // 底栏操作
            footerBar
        }
        .frame(width: 620, height: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert(isPresented: $showClearConfirmAlert) {
            Alert(
                title: Text("确认清除应用下载缓存？"),
                message: Text("🛡️ 安全隔离保护已生效：\n此操作仅会清除由 cduyzh MediaForge 下载的视频文件与转换临时碎片，并清空下载历史记录。\n\n绝对不会删除或修改您电脑上的任何个人文件、工作文档或日常下载资源，已导入相册的实况图不受任何影响。"),
                primaryButton: .destructive(Text("确认安全清除")) {
                    executeClearAll()
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
        .onAppear {
            cacheManager.refreshStats()
        }
    }

    // MARK: - 顶栏
    private var headerBar: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("偏好设置与缓存管理")
                    .font(.system(size: 16, weight: .bold))
                Text("管理视频下载保存目录，查看存储占用并清理历史缓存")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("关闭设置 (Esc)")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
    }

    // MARK: - 成功提示条
    private var successNotice: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 15))
            Text(successBannerMessage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
            Spacer()
            Button {
                withAnimation { showSuccessBanner = false }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.green.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.green.opacity(0.25), lineWidth: 1)
                )
        )
    }

    // MARK: - 1. 缓存目录设置卡片
    private var cacheDirectorySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.blue)
                Text("视频下载缓存目录")
                    .font(.system(size: 14, weight: .bold))
                Spacer()

                if cacheManager.isCustomDirectory {
                    Text("自定义路径")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.15))
                        .foregroundStyle(Color.blue)
                        .cornerRadius(4)
                } else {
                    Text("默认路径")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .foregroundStyle(.secondary)
                        .cornerRadius(4)
                }
            }

            Text("从网络 (如 X / Twitter) 抓取的视频将暂存在此目录中供处理转换。您可以随时更改保存目录或在访达中查看。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineSpacing(2)

            // 当前路径显示盒
            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.blue)
                    .font(.system(size: 15))

                Text(cacheManager.currentCachePath)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.8))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
            )

            // 安全隔离保护提示
            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 11))
                Text("安全隔离保护：应用仅管理自身生成的视频文件，绝对不会删除同目录下您的其他任何文件。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 2)

            // 目录管理操作按钮
            HStack(spacing: 10) {
                Button {
                    cacheManager.promptChooseDirectory()
                } label: {
                    Label("更改目录…", systemImage: "folder.badge.plus")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button {
                    cacheManager.openCacheInFinder()
                } label: {
                    Label("在访达中打开", systemImage: "arrow.up.right.square")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                if cacheManager.isCustomDirectory {
                    Button {
                        cacheManager.resetToDefaultDirectory()
                    } label: {
                        Text("恢复默认路径")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.link)
                }

                Spacer()
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )
        )
    }

    // MARK: - 2. 缓存空间占用与一键清除卡片
    private var cacheUsageAndCleanSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "internaldrive")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.orange)
                Text("缓存空间占用与清理")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
            }

            // 统计仪表卡片
            HStack(spacing: 16) {
                // 容量展示
                VStack(alignment: .leading, spacing: 4) {
                    Text("当前缓存总容量")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(cacheManager.formattedTotalSize)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(cacheManager.totalCacheBytes > 0 ? Color.primary : Color.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                .cornerRadius(8)

                // 文件数展示
                VStack(alignment: .leading, spacing: 4) {
                    Text("缓存文件数量")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(cacheManager.totalFileCount) 个文件")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(cacheManager.totalFileCount > 0 ? Color.primary : Color.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                .cornerRadius(8)
            }

            Divider()

            // 清理说明与一键清理主按钮
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("安全清除应用缓存与下载历史")
                        .font(.system(size: 13, weight: .semibold))
                    Text("仅删除本应用生成的视频缓存与转换碎片，绝不影响您的个人文件与其他资源。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(role: .destructive) {
                    showClearConfirmAlert = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash.fill")
                        Text("一键清除缓存")
                    }
                    .font(.system(size: 12.5, weight: .semibold))
                    .padding(.horizontal, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.red)
                .controlSize(.regular)
                .disabled(cacheManager.totalCacheBytes == 0 && cacheManager.historyRecords.isEmpty)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )
        )
    }

    // MARK: - 3. 历史下载记录清单
    private var downloadHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.purple)
                    Text("历史下载记录")
                        .font(.system(size: 14, weight: .bold))
                }

                Spacer()

                Text("共 \(cacheManager.historyRecords.count) 条记录")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if cacheManager.historyRecords.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text("暂无下载历史记录")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text("从网络下载的推文视频会自动在此登记并管理")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)
            } else {
                VStack(spacing: 8) {
                    ForEach(cacheManager.historyRecords) { record in
                        recordRow(record)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )
        )
    }

    // 单条历史记录项
    private func recordRow(_ record: DownloadRecord) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "video.fill")
                .font(.system(size: 14))
                .foregroundStyle(record.fileExists ? Color.blue : Color.secondary)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(record.fileName)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if !record.fileExists {
                        Text("文件已移除")
                            .font(.system(size: 9.5))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15))
                            .foregroundStyle(.secondary)
                            .cornerRadius(3)
                    }
                }

                HStack(spacing: 10) {
                    Text(record.formattedDate)
                    Text("•")
                    Text(record.formattedFileSize)
                    if let host = URL(string: record.sourceURL)?.host {
                        Text("•")
                        Text(host)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer()

            // 操作按钮
            HStack(spacing: 6) {
                if record.fileExists {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([record.fileURL])
                    } label: {
                        Image(systemName: "folder")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help("在访达中显示")
                }

                Button {
                    cacheManager.deleteRecord(record)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("删除此记录及文件")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
        .cornerRadius(6)
    }

    // MARK: - 底栏
    private var footerBar: some View {
        HStack {
            Spacer()
            Button("完成") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
    }

    // 执行清理
    private func executeClearAll() {
        let (freed, count) = cacheManager.clearAllCache()
        let freedStr = ByteCountFormatter.string(fromByteCount: freed, countStyle: .file)
        successBannerMessage = "安全清理完成！已清除 \(count) 个应用缓存文件，共释放 \(freedStr) 空间（其他任何外部资源未受影响）。"
        withAnimation {
            showSuccessBanner = true
        }
    }
}
