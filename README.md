# cduyzh MediaForge

> ⚡️ 极速、原生的 macOS 全能媒体工坊：跨平台视频无水印提取 · 实时预解析 · 苹果实况图 (Live Photo) 原生熔炼与相册导入 · 公众号 GIF 转换 · 结构化归档收纳。

[![macOS](https://img.shields.io/badge/macOS-14.0+-000000?style=flat-square&logo=apple)](https://apple.com)
[![Swift](https://img.shields.io/badge/Swift-5.5+-F05138?style=flat-square&logo=swift)](https://swift.org)
[![Author](https://img.shields.io/badge/Author-cduyzh-blue?style=flat-square)](https://github.com/cduyzh)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](https://opensource.org/licenses/MIT)

**cduyzh MediaForge**（原 LivePhotoForge）是开发者 @cduyzh 倾力打造的 macOS 原生桌面与命令行双模全能媒体工作站。它从单纯的实况照片制作器全面进化为集**「网络视频解析提取、无水印与片尾剪除、首帧与海报实时预解析、苹果原生 Live Photo 熔炼导入、微信公众号 GIF 生成、视频微剪辑、推特 Markdown 导出与四层结构化分类存储」**于一体的一站式生产力旗舰。

---

## ✨ 核心特性

- **跨平台网络视频高速提取**：
  - **哔哩哔哩 (Bilibili)**：支持长链、短链 (b23.tv) 与 BV号智能提取，自动读取本地浏览器已登录 Cookie 畅享 1080P60 / 1080P 高码率画质，采用 DASH 独立音视频极速流拉取并经由 FFmpeg 无损秒级封包合成。
  - **小红书 (RED)**：支持探索页、分享短链与口令文本的高清视频解析提取，原生去除水印与结尾品牌帧。
  - **推特 (X/Twitter)**：支持多分辨率视频下载、发帖人合集一键提取，以及图文帖子 Markdown 结构化摘要导出。
- **智能预解析与实时首帧预览**：
  - 粘贴或输入链接即刻触发防抖预解析，实时呈现 16:9 高质感封面卡片、视频标题、发布作者及分辨率规格。
  - **免二次解析的直接极速直下**：点击批量下载直接读取直链，毫秒级即时拉取。
- **苹果原生实况图 (Live Photo) 熔炼**：
  - 基于 Swift、`AVFoundation` 与 `Photos.framework`，通过 ImageIO 注入 Apple MakerNote `AssetIdentifier`（Tag 17）与 QuickTime 元数据。
  - 利用系统底层 `PHAssetCreationRequest` 完美配对并自动存入 Mac 系统照片图库，经由 iCloud 瞬间无缝同步至 iPhone。
- **微信公众号 GIF 动图制作**：
  - 一键将视频片段转换为适合微信公众号文章排版或社交聊天的优化版 GIF。
- **视频微调与去水印**：
  - 可视化裁剪起止时间、挑选封面关键帧、倍速调节与水印滤镜擦除。
- **结构化四层归档存储体系**：
  - 默认工作目录 `~/Downloads/cduyzhMediaForge`，自动按 `[平台 (小红书/推特/哔哩哔哩/默认)] ➔ [日期 (如 26年10月17日)] ➔ [类别 (视频/实况/GIF/文档)]` 井然有序分流归类。
- **多任务并发调度引擎**：
  - 支持 1~10 线程并发下载随心调节，高效调度网络请求与批量处理任务。
- **本地转换与受管缓存清理**：
  - 本地原生转换，不上传隐私数据；受管缓存白名单隔离机制，一键清空绝不误伤用户个人文件。

---

## 📥 下载与安装

### 方式一：下载 macOS 图形界面 App (推荐)

前往 [Releases 页面](https://github.com/cduyzh/LivePhotoForge/releases) 下载最新的 `cduyzhMediaForge.dmg`。
双击打开 DMG，将 `cduyzhMediaForge` 拖入您的 `Applications` (应用程序) 文件夹即可。

### 命令行使用同一个应用

安装后直接运行应用内的命令，不再另装一份二进制：

```bash
/Applications/cduyzhMediaForge.app/Contents/MacOS/cduyzhMediaForge --help
```

从源码升级时，安装脚本会将 `cduyzh-media` 统一指向 `/Applications` 中的应用。
当前发布包面向 Apple 芯片、macOS 14 或更新版本；构建采用 Ad-hoc 签名，尚无 Developer ID 签名及 Apple 公证。网络解析依赖本机 `python3`，哔哩哔哩音视频合并与去水印依赖 `ffmpeg`；这些工具不随 App 内置。本地实况与 GIF 转换使用系统原生框架。

---

## 🚀 快速使用

### 图形界面 (GUI)

1. 打开应用程序中的 `cduyzh MediaForge`。
2. 首次打开时，根据系统提示允许“照片”访问权限。
3. **网络提取**：粘贴小红书笔记或推特推文链接，等待卡片预解析完毕后，按需选择保存本地、转实况、生成 GIF 或导出文档，点击底栏的“下载 N 项”。
4. **本地视频**：将本地视频文件批量拖入窗口进行裁剪、调速、转实况或制作 GIF。
5. 处理完成后，媒体文件将自动规整归档至 `~/Downloads/cduyzhMediaForge/[平台]/[日期]/` 对应的 `视频`、`实况`、`GIF` 与 `文档` 目录下，并可直接在访达中一键定位！

### 命令行 (CLI)

```bash
# 1. 本地视频自动转换为实况图并直接导入相册
cduyzh-media video.mp4

# 2. 从小红书解析下载视频并转换为实况图
cduyzh-media "https://www.xiaohongshu.com/explore/6aae6114000000002700a168"

# 3. 将视频转为公众号优化 GIF
cduyzh-media --gif video.mp4

# 4. 截取第 2.5 秒作为封面帧
cduyzh-media --frame-time 2.5 video.mp4

# 5. 裁剪 2.5s 到 5.0s，2 倍速播放，并导入相册
cduyzh-media --start 2.5 --end 5.0 --speed 2.0 video.mp4

# 6. 输出实况图配对文件 (.jpg + .mov) 到指定目录
cduyzh-media -o ~/Desktop/LivePhotos/ video.mp4

# 7. 查看完整帮助
cduyzh-media --help
```

---

## 🧪 构建与测试

在源码的 `App` 目录下执行构建脚本：

```bash
cd App
./build.sh
```

构建生成的 App 位于 `App/.build.noindex/cduyzhMediaForge.app`，隐藏开发产物不参与 Spotlight 索引。构建不会自动安装应用或改写 CLI 链接。

```bash
./scripts/install-local.sh --dry-run  # 查看版本、目标位置、运行实例与旧副本
./scripts/install-local.sh            # 退出运行中的应用后，安装/升级本机
```

### 开发与热重载流程

每次修改代码后，为避免旧进程驻留内存导致调试旧代码，可使用一键重载（自动结束旧进程、编译最新源码、安装至 `/Applications` 并重启）：

```bash
# 在项目根目录一键重启：
./reload.sh

# 或在 App 目录下构建并重启：
cd App
./build.sh --restart
```

安装脚本只保留 `/Applications/cduyzhMediaForge.app` 作为日常唯一入口，旧的 `build/` 和用户 Applications 副本均会归档并清理，CLI 也统一指向 `/Applications`。备份位于 `~/Library/Application Support/cduyzhMediaForge/InstallBackups/`。可在「设置 → 当前应用」查看实际版本、构建号与路径。

### 界面与交互

本地制作、网络提取、小红书助手与设置采用统一的原生系统配色、轻描边与分组布局。制作与下载的主操作固定在底栏；切换工作区保留已输入内容与任务状态。

本地视频卡片可展开调整片段、倍速与封面。批量制作处理等待和失败项目，已完成项目可单独重新制作。停止操作会等待当前步骤收尾，再恢复控件。

快捷键：`⌘1–4` 切换工作区，`⌘O` 添加本地视频，`⌘Return` 执行当前工作区的主操作，历史页使用 `⌘F` 搜索。

回归测试（在 `App` 目录执行）：

```bash
./tests/run-conversion-state-tests.sh
./tests/run-cache-stats-tests.sh
./tests/run-media-safety-tests.sh
./tests/run-install-release-tests.sh
python3 tests/test_network_security.py
```

本轮实现与验收范围见 [UI 优化验证记录](docs/ui-polish-validation.md)。


---

## 📄 许可证

本项目由 @cduyzh 独立开发维护，采用 MIT 许可证。

## 发布新版本

`Info.plist` 是构建、安装、包名和标签校验的版本来源。更新版本与更新日志，完成回归检查并提交源码后：

```bash
./build.sh
./scripts/package-release.sh
./scripts/release.sh --notes-file docs/releases/v1.9.0.md
./scripts/release.sh --notes-file docs/releases/v1.9.0.md --publish
```

发布前需将已验收源码提交并推送，再创建指向该提交的版本标签。发布脚本复用已验证产物；默认只检查，`--publish` 才发布。具体参数见各脚本 `--help`。GitHub Actions 只验证标签构建并保存工件，避免另一台机器的构建覆盖已发布的本机验证包。
