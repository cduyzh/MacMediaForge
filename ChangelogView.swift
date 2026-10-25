import SwiftUI
import AppKit

// MARK: - 版本更新单条模型
public struct ReleaseLogItem: Identifiable, Sendable {
    public let id = UUID()
    public let version: String
    public let releaseDate: String
    public let badgeText: String?
    public let summary: String
    public let highlights: [String]
    public let isLatest: Bool

    public init(
        version: String,
        releaseDate: String,
        badgeText: String? = nil,
        summary: String,
        highlights: [String],
        isLatest: Bool = false
    ) {
        self.version = version
        self.releaseDate = releaseDate
        self.badgeText = badgeText
        self.summary = summary
        self.highlights = highlights
        self.isLatest = isLatest
    }
}

// MARK: - 更新日志数据源提供者
public struct ReleaseLogData {
    public static var currentVersion: String {
        "v" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.9.0")
    }

    public static let releases: [ReleaseLogItem] = [
        ReleaseLogItem(
            version: "v1.10.0",
            releaseDate: "2026年10月20日",
            badgeText: "多档清晰度",
            summary: "网络下载新增 1080P、720P、480P 与 360P 选择，并把全局画质上限固定在 1080P。",
            highlights: [
                "可在设置中选择默认下载清晰度，也能直接在预解析视频卡片上调整单项画质。",
                "X/Twitter、哔哩哔哩与小红书解析和下载按所选档位工作；本机可用 FFmpeg 时会将超规格来源按比例缩至目标分辨率。",
                "无法确认或调整视频分辨率时显示失败原因并保留源文件，不再悄悄以错误清晰度完成任务。",
                "只按 JSON 解析远程页面状态，避免执行网页返回的脚本内容。"
            ],
            isLatest: true
        ),
        ReleaseLogItem(
            version: "v1.9.0",
            releaseDate: "2026年10月18日",
            badgeText: "界面与质量更新",
            summary: "统一制作、下载、历史与设置的界面，完善任务反馈，并让版本与安装位置清楚可见。",
            highlights: [
                "统一系统配色、卡片层级与固定底栏；切换工作区保留输入与任务状态。",
                "完善空态、无效输入、失败重试、取消收尾和完成后的文件入口。",
                "修复转换输出冲突、失败退出码与取消清理范围，补齐功能回归测试。",
                "统一应用版本信息；安装到「应用程序」，将旧构建归档，避免搜索出现多个副本。"
            ],
            isLatest: false
        ),
        ReleaseLogItem(
            version: "v1.8.0",
            releaseDate: "2026年10月17日",
            summary: "新增哔哩哔哩视频提取、封面预解析与分类归档。",
            highlights: [
                "识别视频长链、b23.tv 短链与 BV 号；支持音视频分离下载并合并。",
                "预览标题、作者与封面，下载结果按平台和日期归档。"
            ]
        ),
        ReleaseLogItem(
            version: "v1.7.0",
            releaseDate: "2026年10月16日",
            badgeText: "全新品牌升级",
            summary: "产品正式品牌化升级为「MediaSaver (cduyzh 媒体工坊)」，全面涵盖网络视频提取、实况图制作、动图转换与媒体归档。",
            highlights: [
                "✨ 品牌全面升级：正式升级为带有作者专属标识的「MediaSaver」，确立全能跨平台媒体工坊的全新定位。",
                "📂 存储目录无缝过渡：默认工作目录升级为 ~/Downloads/cduyzhMediaForge，支持历史文件安全平滑迁移。",
                "🛡️ 安全白名单双向兼容：全面适配新品牌目录与临时缓存，严格遵循零误伤用户个人文件的安全准则。",
                "📦 旧包与构建清理：彻底卸载清理历史旧产物，带来纯净轻量的高性能体验。"
            ],
            isLatest: false
        ),
        ReleaseLogItem(
            version: "v1.6.0",
            releaseDate: "2026年10月16日",
            badgeText: "历史稳定版",
            summary: "输入链接自动预解析视频元数据与首帧封面图、准备就绪区域实时预览、直接极速批量下载免二次解析。",
            highlights: [
                "🎬 自动预解析与首帧预览：粘贴或输入视频链接后，后台自动提取视频首帧作为预览图，并呈现 16:9 高质感封面卡片。",
                "👤 标题与作者元数据展示：实时展示视频完整标题、发布作者（如 Google Gemini (@GeminiApp)）、清晰度规格及多视频统计。",
                "⚡️ 免二次解析的极速直下：点击开始下载时，直接复用已预解析的视频直链与结构化数据，彻底告别重复解析等待。",
                "🔄 实时解析状态与重试机制：支持清晰展示就绪/解析中/失败状态，并提供单项重试与一键全部重新解析。"
            ],
            isLatest: false
        ),
        ReleaseLogItem(
            version: "v1.5.0",
            releaseDate: "2026年10月14日",
            badgeText: "历史稳定版",
            summary: "产品化专属存储命名、标准四层媒体归类体系、GIF 可选生成、多任务并发调度与系统设置动态联动。",
            highlights: [
                "🗂️ 默认存储路径规范化：正式采用产品专属名称 ~/Downloads/LivePhotoForge，并支持旧目录自动平滑迁移。",
                "📂 结构化四层归类体系：按照「平台 (小红书/推特/默认) ➔ 日期 (yy年M月d日) ➔ 类别 (视频/实况/GIF/文档)」智能归类，告别杂乱混乱。",
                "🖼️ GIF 可选生成与分流：默认不生成 GIF（设为关闭），生成时自动归档至对应所属的 GIF 目录。",
                "⚡️ 自主并发下载调度引擎：支持在 1~10 线程并发范围内随心调节，大幅提升多链接批量下载效率。",
                "🔄 系统设置中心全面联动：本地保存、转实况、生成 GIF、推特 Markdown 导出、去水印与并发等全部收纳并实现双向动态联动。",
                "📜 操作历史记录中心：全生命周期记录本地转换与网络提取，支持快速定位文件、复制原链接与搜索检索。",
                "🚀 原生更新日志查看器：直观掌握各版本演进轨迹与新特性详情。"
            ],
            isLatest: false
        ),
        ReleaseLogItem(
            version: "v1.4.0",
            releaseDate: "2026年10月13日",
            badgeText: "重大功能升级",
            summary: "小红书平台视频解析与无水印下载集成、强制校验保护与双向导出选项。",
            highlights: [
                "📱 小红书解析与去水印：支持小红书探索页、分享短链与口令文本的高清无水印视频提取。",
                "💾 灵活双向选择：提供「保存视频到本地」与「转为实况图」独立选项，按需自由组合。",
                "🛡️ 强制校验保护：必须至少勾选一项保存方式方可执行，防止无意义空耗操作。",
                "💻 CLI 命令行支持：命令行工具全面支持小红书链接传入与自动化流水线处理。"
            ]
        ),
        ReleaseLogItem(
            version: "v1.3.0",
            releaseDate: "2026年10月13日",
            badgeText: "安全与管理",
            summary: "偏好设置面板上线、受管缓存白名单安全隔离与一键清理功能。",
            highlights: [
                "⚙️ 独立偏好设置：支持快捷键 ⌘, 唤起设置面板，支持自定义下载路径。",
                "🧹 受管缓存安全清空：严格受限于 LivePhotoForge 白名单目录，一键清空临时文件绝不误删个人文件。",
                "📊 磁盘占用统计：实时呈现受管缓存文件数量与占用空间。"
            ]
        ),
        ReleaseLogItem(
            version: "v1.2.0",
            releaseDate: "2026年10月13日",
            badgeText: "视觉重构",
            summary: "界面全新重构放大至 980×720、三模分段顶栏与底层元数据配对修复。",
            highlights: [
                "🎨 现代化大视野布局：窗口放大，卡片间距与缩略图尺寸全面升级至 Retina 视网膜规格。",
                "🍎 苹果实况元数据底层修复：正确注入 Apple MakerNote Tag 17 与 QuickTime 元数据，消除 3302 导入相册报错。"
            ]
        ),
        ReleaseLogItem(
            version: "v1.0.0",
            releaseDate: "2026年10月09日",
            badgeText: "首次正式发布",
            summary: "极速、原生的 macOS 视频转苹果实况图 (Live Photo) 桌面与命令行双模工具发布。",
            highlights: [
                "⚡️ 原生 Passthrough 极速封装：H.264 视频 0.04 秒无损转换。",
                "📱 自动配对导入相册：无需数据线，iCloud 自动同步至 iPhone 动态锁屏壁纸。",
                "🎞️ 微信公众号 GIF 优化模式：高画质调色压缩，体积友好适合图文排版。"
            ]
        )
    ]
}

// MARK: - 软件更新日志视图
public struct ChangelogView: View {
    @State private var expandedVersions: Set<String> = [ReleaseLogData.currentVersion]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 1. 顶栏产品版本展示卡片
                headerCard
                ForgeInstallationCard()

                // 2. 版本演进时间轴卡片列表
                VStack(spacing: 16) {
                    ForEach(ReleaseLogData.releases) { rel in
                        releaseCard(rel)
                    }
                }

                // 3. 底部版权与链接
                footerLinksCard
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - 顶栏卡片
    private var headerCard: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(LinearGradient(colors: [Color.accentColor, Color.purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 54, height: 54)
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("MediaSaver 版本演进与更新日志")
                        .font(.system(size: 17, weight: .bold))
                    Text(ReleaseLogData.currentVersion)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundStyle(Color.accentColor)
                        .cornerRadius(6)
                }

                Text("持续打磨每一处细节，致力于提供 macOS 平台上最极致顺畅的实况图转换与媒体归类体验。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.12), lineWidth: 1))
    }

    // MARK: - 单版本卡片
    private func releaseCard(_ rel: ReleaseLogItem) -> some View {
        let isExpanded = expandedVersions.contains(rel.version)

        return VStack(alignment: .leading, spacing: 12) {
            // 卡片头部（点击可折叠/展开）
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expandedVersions.remove(rel.version)
                    } else {
                        expandedVersions.insert(rel.version)
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    // 版本号
                    Text(rel.version)
                        .font(.system(size: 16, weight: .bold, design: .rounded))

                    // 徽章
                    if let badge = rel.badgeText {
                        Text(badge)
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(rel.isLatest ? Color.green.opacity(0.15) : Color.blue.opacity(0.12))
                            .foregroundStyle(rel.isLatest ? Color.green : Color.blue)
                            .cornerRadius(5)
                    }

                    // 发布日期
                    Text(rel.releaseDate)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(rel.version)，\(rel.releaseDate)，\(isExpanded ? "收起" : "展开")更新详情")

            // 版本概述
            Text(rel.summary)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.85))

            // 详细亮点列表 (展开时展示)
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                        .padding(.vertical, 2)

                    ForEach(rel.highlights, id: \.self) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Text(item)
                                .font(.system(size: 12.5))
                                .foregroundStyle(.secondary)
                                .lineSpacing(3)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(rel.isLatest ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.12), lineWidth: rel.isLatest ? 1.5 : 1)
        )
    }

    // MARK: - 底部链接与致谢
    private var footerLinksCard: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("MediaSaver 个人产品")
                    .font(.system(size: 12, weight: .semibold))
                Text("基于 MIT 协议开放源码，欢迎提交 Issue 反馈与功能建言。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                if let url = URL(string: "https://github.com/cduyzh/MediaSaver") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "safari")
                    Text("访问 GitHub 仓库")
                }
                .font(.system(size: 12))
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        .cornerRadius(10)
    }
}
