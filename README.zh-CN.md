# MediaSaver（媒体收藏家）

> 极速、原生的 macOS 全能媒体工坊：跨平台视频无水印提取 · 实况图 (Live Photo) 熔炼导入 · 公众号 GIF 转换 · 结构化归档收纳。

[![macOS](https://img.shields.io/badge/macOS-14.0%2B-000000?style=flat-square&logo=apple)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-F05138?style=flat-square&logo=swift)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](https://opensource.org/licenses/MIT)
[![Author](https://img.shields.io/badge/Author-cduyzh-blue?style=flat-square)](https://github.com/cduyzh)

[English](README.md) · **简体中文**

**MediaSaver** 是开发者 @cduyzh 打造的 macOS 原生桌面与命令行双模全能媒体工作站。它集**「网络视频解析提取、无水印与片尾剪除、首帧与封面实时预解析、苹果原生 Live Photo 熔炼导入、微信公众号 GIF 生成、视频微剪辑、推特 Markdown 导出与四层结构化分类存储」**于一体，全部处理均在本机完成。

## 功能特性

- **跨平台网络视频高速提取**
  - **哔哩哔哩 (Bilibili)**：支持长链、短链 (b23.tv) 与 BV 号智能提取；可自动读取本地浏览器已登录 Cookie，畅享 1080P60 / 1080P 高码率画质；采用 DASH 独立音视频流极速拉取，并经 FFmpeg 秒级无损封包合成。
  - **小红书 (RED)**：支持探索页、分享短链与口令文本的高清视频解析提取，原生去除水印与结尾品牌帧。
  - **推特 (X/Twitter)**：支持多分辨率视频下载、发帖人合集一键批量提取，以及图文帖子 Markdown 结构化摘要导出。
- **智能预解析与实时首帧预览**：粘贴或输入链接即刻触发防抖预解析，实时呈现 16:9 高质感封面卡片、视频标题、发布作者及分辨率规格；点击批量下载直接读取已缓存的直链，免二次解析、极速直下。
- **苹果原生实况图 (Live Photo) 熔炼**：基于 Swift、`AVFoundation` 与 `Photos.framework`，通过 ImageIO 注入 Apple MakerNote `AssetIdentifier`（Tag 17）与 QuickTime 元数据；利用系统底层 `PHAssetCreationRequest` 完美配对并自动存入 Mac 系统照片图库，经由 iCloud 无缝同步至 iPhone。
- **微信公众号 GIF 动图制作**：一键将视频片段转换为适合微信公众号文章排版或社交聊天的优化版 GIF。
- **视频微调与去水印**：可视化裁剪起止时间、挑选封面关键帧、倍速调节与水印滤镜擦除。
- **结构化四层归档存储体系**：默认工作目录 `~/Downloads/cduyzhMediaForge`，自动按 `[平台] → [日期] → [类别（视频 / 实况 / GIF / 文档）]` 井然有序分流归类，并支持在访达中一键定位。
- **多任务并发调度引擎**：支持 1~10 线程并发下载随心调节，高效调度网络请求与批量处理任务。
- **多档下载清晰度**：网络提取支持 1080P、720P、480P 与 360P，可设置默认档位或逐条调整；下载超过所选规格时按比例缩放，绝不放大低分辨率来源。
- **本地转换与受管缓存清理**：本地原生转换，不上传隐私数据；受管缓存白名单隔离机制，一键清空绝不误伤用户个人文件。
- **CLI 命令行与无界面模式**：同一二进制兼作命令行工具，方便脚本化与自动化。
- **菜单栏常驻**：单色播放环图标区分就绪、处理中、完成与需关注状态；关闭主窗口后仍可在菜单栏继续运行任务。
- **更新检查**：在应用内或命令行检查 GitHub 最新 Release。
- **操作历史**：可搜索的历史记录，支持文件定位。

## 支持平台

| 平台 | 支持链接 | 亮点 |
| --- | --- | --- |
| 哔哩哔哩 | 网页长链、b23.tv 短链、纯 BV 号 | 复用本地浏览器已登录 Cookie 解锁 1080P60 / 1080P 高码率；DASH 音视频流经 FFmpeg 无损合并 |
| 小红书 (RED) | 探索页链接、分享短链、口令分享文本 | 高清视频下载，原生去除水印与结尾品牌帧 |
| 推特 (X/Twitter) | 推文链接 | 多分辨率视频、发帖人合集批量提取、图文帖 Markdown 导出 |

## 命令行 (CLI)

同一应用二进制兼作命令行工具：带参数启动即进入 CLI 模式，`--help` 会打印完整选项列表（下载清晰度、仅下载模式、GIF 输出、裁剪、倍速、去水印、检查更新等）。

```bash
/Applications/cduyzhMediaForge.app/Contents/MacOS/cduyzhMediaForge --help
```

示例：

```bash
cduyzh-media video.mp4                                    # 制作实况图并导入系统相册
cduyzh-media --gif video.mp4                              # 转换为公众号优化 GIF
cduyzh-media -d "https://www.bilibili.com/video/BV..."    # 下载网络视频
cduyzh-media --start 2.5 --end 5.0 --speed 2.0 video.mp4  # 裁剪 + 变速后导入
```

使用源码安装脚本安装应用后，即可使用 `cduyzh-media` 短命令——脚本会将其统一指向 `/Applications` 中的应用，GUI 与 CLI 始终运行同一构建。

## 下载与安装

1. 前往 [Releases 页面](https://github.com/cduyzh/MediaSaver/releases) 下载最新的 `.dmg`。
2. 双击打开 DMG，将 `cduyzhMediaForge` 拖入您的 `Applications`（应用程序）文件夹。
3. 首次打开时，根据系统提示允许「照片」访问权限。

说明：

- 需要 macOS 14.0 或更高版本（Apple Silicon / Intel）。
- 发布包采用 Ad-hoc 签名且未经 Apple 公证；若首次打开出现 Gatekeeper 提示，请右键点击应用并选择「打开」。
- 网络解析依赖本机 `python3`；哔哩哔哩音视频合并、去水印与分辨率缩放依赖 `ffmpeg`（例如 `brew install ffmpeg`），二者均不随 App 内置。实况图与 GIF 转换使用系统原生框架。

## 从源码构建

环境要求：macOS 14+，Xcode 或 Xcode Command Line Tools（Swift 5.9+）。

```bash
git clone https://github.com/cduyzh/MediaSaver.git
cd MediaSaver/App
./build.sh
```

- `./build.sh` 按本机架构编译应用，产物放入隐藏构建目录，不参与 Spotlight 索引。
- `./build.sh --install` 构建后自动安装到 `/Applications`；`--restart` 额外结束运行中的旧进程并重启新构建。
- 使用 `MEDIAFORGE_ARCHS='arm64 x86_64' ./build.sh` 构建通用二进制。
- `./scripts/install-local.sh --dry-run` 预览安装；不带参数执行即安装或升级。

## 版本历史

当前版本：**1.10.0**（构建号 10）。完整历史见 [CHANGELOG.md](CHANGELOG.md)。

## 隐私

- 所有转换与处理均在本机完成；应用本身不会向第三方服务上传您的媒体或隐私数据。
- 使用 Cookie 辅助功能时，应用仅在本机读取本地浏览器 Cookie，且仅用于您选择的平台——只为向对应平台请求更高码率的视频流。
- 网络提取只会访问您粘贴链接所属的平台。

## 许可证

以 [MIT License](https://opensource.org/licenses/MIT) 开源。见仓库根目录的 `LICENSE` 文件。

## 作者

**cduyzh**

- GitHub：<https://github.com/cduyzh>
- 个人网站：<https://www.cduyzh.top>
- Goal：<https://www.cduyzh.top/goal>
