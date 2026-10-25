import SwiftUI
import AppKit

struct XHSAssistantView: View {
    @ObservedObject private var auth = XHSAuthManager.shared
    @ObservedObject private var appSettings = AppSettings.shared

    @State private var cookieInput = ""
    @State private var tokenInput = ""
    @State private var saveSuccessMessage: String?
    @State private var copyScriptMessage: String?
    @State private var copyScriptFailed = false
    @State private var credentialCopyMessage: String?
    @State private var copiedCookieScript = false
    @State private var copiedTokenScript = false
    @FocusState private var isCookieFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("小红书助手")
                        .font(.system(size: 26, weight: .semibold))
                    Text("使用浏览器辅助提取视频，并管理下载所需的登录信息。")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 2)

                batchScriptCard
                localReceiverCard
                manualCredentialCard
            }
            .frame(maxWidth: 1040)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            cookieInput = auth.cookie
            tokenInput = auth.defaultToken
        }
        .onChange(of: cookieInput) { _, _ in saveSuccessMessage = nil }
        .onChange(of: tokenInput) { _, _ in saveSuccessMessage = nil }
    }

    private var batchScriptCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 16) {
                ForgeSectionHeading(title: "浏览器辅助提取", subtitle: "从博主主页中获取已加载的视频链接。")
                Button(action: copyBatchHelperScript) {
                    Label(copyScriptMessage != nil && !copyScriptFailed ? "已复制" : "复制脚本", systemImage: copyScriptMessage != nil && !copyScriptFailed ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .fixedSize()
                .accessibilityLabel("复制浏览器辅助提取脚本")
            }

            VStack(alignment: .leading, spacing: 16) {
                instructionStep(number: "1", title: "打开博主主页", detail: "在已登录小红书的浏览器中打开主页，加载需要提取的内容。")
                instructionStep(number: "2", title: "打开控制台", detail: "按 ⌘Option + I 打开开发者工具，切换到 Console。")
                instructionStep(number: "3", title: "粘贴并运行脚本", detail: "在控制台中粘贴代码并回车，再在页面面板中开始提取。")
            }

            Text("脚本会尝试将视频发送到本地接收地址，也可使用页面面板中的浏览器下载操作。结果取决于页面内容与登录状态。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let message = copyScriptMessage {
                ForgeStatusBanner(title: copyScriptFailed ? "未能复制脚本" : "脚本已复制", message: message, systemImage: copyScriptFailed ? "exclamationmark.circle" : "checkmark.circle", tint: copyScriptFailed ? .orange : .accentColor)
            }
        }
        .padding(20)
        .forgeSurface(cornerRadius: 16)
    }

    private func instructionStep(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(Color.primary.opacity(0.055), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var localReceiverCard: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.secondary)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("本地接收地址  localhost:8765")
                    .font(.system(size: 13, weight: .medium))
                    .textSelection(.enabled)
                Text((appSettings.downloadDirectory as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(appSettings.downloadDirectory)
            }
            Spacer(minLength: 8)
            Button {
                NSWorkspace.shared.open(appSettings.downloadURL)
            } label: {
                Label("打开目录", systemImage: "folder")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .accessibilityLabel("在访达中打开下载目录")
        }
        .padding(20)
        .forgeSurface(cornerRadius: 16)
    }

    private var manualCredentialCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 16) {
                ForgeSectionHeading(title: "登录信息", subtitle: "供需要登录状态的视频链接使用。")
                Label(auth.hasConfiguredCookie ? "已配置 Cookie" : "未配置 Cookie", systemImage: auth.hasConfiguredCookie ? "checkmark.circle" : "key")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }

            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("Cookie")
                        .font(.system(size: 13, weight: .medium))
                    Text("含 a1、web_session 等")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        copyCredentialScript(XHSAuthManager.jsExportScriptCookie, isCookie: true)
                    } label: {
                        Label(copiedCookieScript ? "已复制" : "复制导出代码", systemImage: copiedCookieScript ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
                    .help("复制后在小红书网页控制台运行，再将导出的 Cookie 粘贴到下方")
                    .accessibilityLabel("复制 Cookie 导出代码")
                }

                TextEditor(text: $cookieInput)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(height: 92)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .focused($isCookieFocused)
                    .overlay {
                        RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(isCookieFocused ? Color.accentColor.opacity(0.65) : Color.primary.opacity(0.10), lineWidth: isCookieFocused ? 1.5 : 1)
                            .allowsHitTesting(false)
                    }
                    .accessibilityLabel("小红书 Cookie")
            }

            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("xsec_token")
                        .font(.system(size: 13, weight: .medium))
                    Text("可选")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        copyCredentialScript(XHSAuthManager.jsExportScriptToken, isCookie: false)
                    } label: {
                        Label(copiedTokenScript ? "已复制" : "复制提取代码", systemImage: copiedTokenScript ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
                    .help("从当前笔记页面 URL 提取 xsec_token")
                    .accessibilityLabel("复制 xsec_token 提取代码")
                }

                TextField("粘贴笔记访问令牌", text: $tokenInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .controlSize(.large)
                    .accessibilityLabel("小红书 xsec_token，可选")
            }

            if let message = credentialCopyMessage {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack(spacing: 14) {
                if let message = saveSuccessMessage {
                    Label(message, systemImage: "checkmark.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    Text("修改后保存以应用到后续下载。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("保存登录信息", action: saveCredentials)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(cookieInput == auth.cookie && tokenInput == auth.defaultToken)
            }
        }
        .padding(20)
        .forgeSurface(cornerRadius: 16)
    }

    private func copyBatchHelperScript() {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("xhs_browser_batch_helper.js")
        let scriptURL = Bundle.main.url(forResource: "xhs_browser_batch_helper", withExtension: "js") ?? sourceURL
        guard let content = try? String(contentsOf: scriptURL, encoding: .utf8), !content.isEmpty else {
            copyScriptFailed = true
            copyScriptMessage = "未找到辅助脚本，请确认应用资源完整。"
            return
        }
        NSPasteboard.general.clearContents()
        copyScriptFailed = !NSPasteboard.general.setString(content, forType: .string)
        copyScriptMessage = copyScriptFailed ? "无法写入剪贴板，请重试。" : "可在小红书网页控制台中粘贴运行。"
    }

    private func copyCredentialScript(_ script: String, isCookie: Bool) {
        NSPasteboard.general.clearContents()
        let copied = NSPasteboard.general.setString(script, forType: .string)
        copiedCookieScript = copied && isCookie
        copiedTokenScript = copied && !isCookie
        credentialCopyMessage = copied ? "代码已复制。在小红书网页控制台运行后，将结果粘贴到对应输入框。" : "无法写入剪贴板，请重试。"
    }

    private func saveCredentials() {
        auth.updateAuth(cookie: cookieInput, token: tokenInput)
        saveSuccessMessage = "登录信息已保存"
    }
}
