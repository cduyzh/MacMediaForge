import SwiftUI
import AppKit

// 共享的界面层级：系统底色、轻描边和少量强调色，自动适配深浅外观。
private struct ForgeSurface: ViewModifier {
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 0.5)
            }
    }
}

extension View {
    func forgeSurface(cornerRadius: CGFloat = 16) -> some View {
        modifier(ForgeSurface(cornerRadius: cornerRadius))
    }
}

struct ForgeSectionHeading: View {
    var title: String
    var subtitle: String? = nil
    var systemImage: String? = nil
    var isPageTitle = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 26, height: 30)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: isPageTitle ? 24 : 14, weight: .semibold))
                    .tracking(isPageTitle ? -0.4 : 0)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ForgeStatusBanner: View {
    var title: String
    var message: String? = nil
    var systemImage: String
    var tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(tint)
                .padding(.top, 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 12.5, weight: .medium))
                if let message {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct ForgeIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        IconBody(configuration: configuration)
    }

    private struct IconBody: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isEnabled ? Color.secondary : Color.secondary.opacity(0.4))
                .frame(minWidth: 30, minHeight: 30)
                .background(Color.primary.opacity(configuration.isPressed ? 0.1 : (isHovering && isEnabled ? 0.05 : 0)), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .onHover { isHovering = $0 }
        }
    }
}

/// 直接显示正在运行的应用信息与版本检查更新，避免把开发产物误认为安装版本。
struct ForgeInstallationCard: View {
    @ObservedObject private var updater = UpdateChecker.shared
    @ObservedObject private var settings = AppSettings.shared
    @State private var showTokenConfig = false

    private var appURL: URL { Bundle.main.bundleURL.standardizedFileURL }
    private var isInstalled: Bool {
        appURL.deletingLastPathComponent().path == "/Applications"
            || appURL.deletingLastPathComponent().path == NSHomeDirectory() + "/Applications"
    }
    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                ForgeSectionHeading(title: "当前应用", subtitle: "\(ReleaseLogData.currentVersion) · 构建 \(build)", systemImage: "app")
                Text(isInstalled ? "已安装版本" : "开发构建")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isInstalled ? Color.secondary : Color.orange)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.04), in: Capsule())
            }
            Text(appURL.path)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Text(isInstalled ? "从「应用程序」启动此版本。" : "日常使用请安装到「应用程序」，避免误开构建副本。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("在访达中显示") {
                    NSWorkspace.shared.activateFileViewerSelecting([appURL])
                }
                .buttonStyle(.bordered)
            }

            Divider()

            // MARK: - 检查更新控制区
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("版本更新")
                                .font(.system(size: 13, weight: .semibold))
                            if let date = updater.lastCheckedDate {
                                Text("· 上次检查 \(date.formatted(date: .omitted, time: .shortened))")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text("基于 GitHub 仓库 Releases 检测最新发布版本与发布工件。")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        Task {
                            await updater.checkForUpdates(isUserInitiated: true)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if updater.isChecking {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                            Text(updater.isChecking ? "检查中…" : "检查更新")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(updater.isChecking)
                }

                // 更新检测结果状态展示
                switch updater.status {
                case .idle:
                    EmptyView()
                case .checking:
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在连接 GitHub Releases 检查最新版本…")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))

                case .upToDate(let version):
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("当前已是最新版本 (\(version))")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        Button("查看 Release 说明") {
                            updater.openReleaseWebPage()
                        }
                        .buttonStyle(.borderless)
                        .font(.system(size: 11))
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

                case .updateAvailable(let release):
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "sparkles")
                                .foregroundStyle(.blue)
                            Text("发现新版本：\(release.displayTitle)")
                                .font(.system(size: 13, weight: .semibold))
                            Spacer()
                            if let dateStr = release.publishedAt {
                                Text(dateStr.prefix(10))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if let notes = release.body, !notes.isEmpty {
                            Text(notes)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }

                        HStack(spacing: 10) {
                            if let dmg = release.dmgAssetURL {
                                Button("下载 DMG 安装包") {
                                    updater.downloadDMG(url: dmg)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }

                            Button("在 GitHub 查看") {
                                updater.openReleaseWebPage(url: release.htmlURL)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

                case .failed(let reason):
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("检查更新失败")
                                .font(.system(size: 12, weight: .semibold))
                            Text(reason)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("重试") {
                            Task { await updater.checkForUpdates(isUserInitiated: true) }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }

                // 启动自动检查配置与私有仓库 Token 设置
                HStack {
                    Toggle("启动应用时自动静默检查更新", isOn: $settings.autoCheckUpdates)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        withAnimation { showTokenConfig.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Text(showTokenConfig ? "收起 Token 配置" : "私有仓库 Token 配置")
                            Image(systemName: showTokenConfig ? "chevron.up" : "chevron.down")
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                if showTokenConfig {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("GitHub Personal Access Token（可选，本机若已通过 gh 命令行工具登录则自动复用免填）：")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        HStack {
                            SecureField("ghp_xxxxxxxxxxxx", text: $settings.githubToken)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11, design: .monospaced))
                            if !settings.githubToken.isEmpty {
                                Button("清空") { settings.githubToken = "" }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                            }
                        }
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .padding(20)
        .forgeSurface()
    }
}
