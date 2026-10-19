import SwiftUI
import AppKit

// MARK: - 小红书鉴权配置弹窗视图
struct XHSAuthSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var authManager = XHSAuthManager.shared

    @State private var inputCookie: String = ""
    @State private var inputToken: String = ""
    @State private var copiedNotice: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            // 顶栏标题
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.12))
                        .frame(width: 38, height: 38)
                    Image(systemName: "key.horizontal.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.red)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("小红书访问鉴权配置")
                        .font(.system(size: 16, weight: .bold))
                    Text("人工补充会话 Cookie 与 xsec_token，突破小红书官方登录拦截与安全风控")
                        .font(.system(size: 12))
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
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // MARK: - 核心说明卡片
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(Color.blue)
                            .font(.system(size: 15))
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("为什么要配置鉴权？")
                                .font(.system(size: 13, weight: .semibold))
                            Text("小红书近期升级了反爬策略，直接访问裸链接会被强制重定向到登录页。配置一次浏览器 Cookie 即可长期稳定下载高清无水印视频。")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineSpacing(2)
                        }
                    }
                    .padding(12)
                    .background(Color.blue.opacity(0.08))
                    .cornerRadius(8)

                    // MARK: - 浏览器一键导出 JS 工具箱
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("浏览器一键导出脚本 (JS)", systemImage: "applescript")
                                .font(.system(size: 13, weight: .bold))
                            Spacer()
                            if let notice = copiedNotice {
                                Text(notice)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.green)
                                    .transition(.opacity)
                            }
                        }

                        Text("在任意电脑浏览器 (Chrome/Edge/Safari) 中打开小红书网页，按 F12 进入「控制台」(Console)，粘贴脚本回车即可一键复制。")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            Button {
                                copyToClipboard(XHSAuthManager.consoleExportScript, label: "控制台导出脚本已复制！请在浏览器控制台执行")
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "doc.on.doc.fill")
                                    Text("复制完整导出脚本 (推荐)")
                                }
                                .font(.system(size: 12, weight: .medium))
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.blue)

                            Button {
                                copyToClipboard(XHSAuthManager.simpleCookieScript, label: "极简 Cookie 脚本已复制！")
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "terminal")
                                    Text("复制极简 Cookie 提取代码")
                                }
                                .font(.system(size: 12))
                            }
                            .buttonStyle(.bordered)

                            Button {
                                copyToClipboard(XHSAuthManager.bookmarkletScript, label: "书签小工具代码已复制！")
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "bookmark")
                                    Text("复制书签工具 (Bookmarklet)")
                                }
                                .font(.system(size: 12))
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(14)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                    )

                    // MARK: - Cookie 输入框
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("小红书网页端 Cookie (推荐)")
                                .font(.system(size: 13, weight: .semibold))
                            Spacer()
                            if !inputCookie.isEmpty {
                                Button("清空") {
                                    inputCookie = ""
                                }
                                .font(.caption)
                                .buttonStyle(.link)
                            }
                            Button("从剪贴板粘贴") {
                                pasteFromClipboard()
                            }
                            .font(.caption)
                            .buttonStyle(.link)
                        }

                        TextEditor(text: $inputCookie)
                            .font(.system(size: 11.5, design: .monospaced))
                            .frame(height: 80)
                            .padding(6)
                            .background(Color(nsColor: .textBackgroundColor))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )

                        Text("可直接粘贴运行导出脚本生成的完整 JSON，或以 `a1=...; web_session=...` 格式的 Cookie 文本。")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    // MARK: - 备用 xsec_token 输入框
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("备用访问令牌 (xsec_token，可选)")
                                .font(.system(size: 13, weight: .semibold))
                            Spacer()
                            if !inputToken.isEmpty {
                                Button("清空") {
                                    inputToken = ""
                                }
                                .font(.caption)
                                .buttonStyle(.link)
                            }
                        }

                        TextField("如 AB3d5VZ3TNxy4atumaMSjagw2t2_hLe6NGqUYHswD-fWI=", text: $inputToken)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))

                        Text("当您输入的链接缺少 xsec_token 时，系统将自动尝试为此链接拼接此访问凭证。")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(22)
            }

            Divider()

            // 底部操作栏
            HStack {
                if authManager.hasConfiguredCookie {
                    Button(role: .destructive) {
                        authManager.clearAuth()
                        inputCookie = ""
                        inputToken = ""
                        showTemporaryNotice("已清除鉴权信息")
                    } label: {
                        Text("清除已保存配置")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                }

                Spacer()

                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("保存鉴权配置") {
                    authManager.saveAuth(cookie: inputCookie, defaultToken: inputToken)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        }
        .frame(width: 580, height: 600)
        .onAppear {
            inputCookie = authManager.cookie
            inputToken = authManager.defaultToken
        }
    }

    private func copyToClipboard(_ text: String, label: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        showTemporaryNotice(label)
    }

    private func pasteFromClipboard() {
        if let str = NSPasteboard.general.string(forType: .string) {
            inputCookie = str
        }
    }

    private func showTemporaryNotice(_ msg: String) {
        withAnimation {
            copiedNotice = msg
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation {
                if copiedNotice == msg {
                    copiedNotice = nil
                }
            }
        }
    }
}
