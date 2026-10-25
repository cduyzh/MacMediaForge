# MediaSaver

> A fast, native macOS media workshop: watermark-free web video extraction, Apple Live Photo crafting, WeChat-ready GIF conversion, and structured archiving — in one app.

[![macOS](https://img.shields.io/badge/macOS-14.0%2B-000000?style=flat-square&logo=apple)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-F05138?style=flat-square&logo=swift)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](https://opensource.org/licenses/MIT)
[![Author](https://img.shields.io/badge/Author-cduyzh-blue?style=flat-square)](https://github.com/cduyzh)

**English** · [简体中文](README.zh-CN.md)

**MediaSaver** is a native macOS media workshop that works both as a polished desktop app and as a command-line tool. It extracts videos from Bilibili, Xiaohongshu (RED) and Twitter/X without watermarks, crafts real Apple Live Photos from any clip, produces WeChat-official-account-ready GIFs, and files every result into a tidy four-layer archive — all locally on your Mac.

## Features

- **Cross-platform network video extraction**
  - **Bilibili**: paste web links, `b23.tv` short links, or plain BV ids. The app can reuse the logged-in cookies of your local browser to unlock high-bitrate 1080P60 / 1080P quality, fetches DASH's separate audio and video streams at full speed, and merges them losslessly in seconds with FFmpeg.
  - **Xiaohongshu (RED)**: supports explore-page links, share short links, and copied passcode share text; downloads HD video and natively removes the watermark and trailing brand frame.
  - **Twitter / X**: multi-resolution video downloads, one-click batch extraction of a poster's entire collection, and structured Markdown export of photo posts.
- **Smart pre-parse with live first-frame previews**: pasting or typing a link immediately triggers a debounced pre-parse that shows a refined 16:9 cover card with the video title, author, and resolution. Hitting batch download reads the cached direct links directly — a fast start with no re-parsing.
- **Native Apple Live Photo crafting**: built on Swift, `AVFoundation`, and `Photos.framework`. ImageIO injects the Apple MakerNote `AssetIdentifier` (Tag 17) and QuickTime metadata; `PHAssetCreationRequest` pairs the still image and video and saves them into the Mac Photos library, where iCloud syncs them seamlessly to your iPhone.
- **WeChat-official-account-ready GIF conversion**: turn any video clip into an optimized GIF with one click, sized for WeChat official-account article layouts or chat.
- **Micro-editing**: visually trim start/end points, pick the cover keyframe, adjust playback speed, and erase watermarks with a filter.
- **Structured four-layer archiving**: by default everything lands under `~/Downloads/cduyzhMediaForge`, automatically sorted as `[platform] → [date] → [category (video / Live Photo / GIF / docs)]`, with one-click reveal in Finder.
- **Concurrent download scheduling**: adjust between 1–10 download threads to balance network load and batch throughput.
- **Quality tiers**: choose 1080P, 720P, 480P, or 360P as a default or per item. Sources larger than the selected tier are scaled down proportionally; lower-resolution sources are never upscaled.
- **Local conversion with managed cache cleanup**: all conversion runs locally and uploads no private data; cache cleanup uses a managed whitelist, so it never touches your personal files.
- **CLI mode and headless operation**: the same binary doubles as a command-line tool, ready for scripts and automation.
- **Menu bar app**: a monochrome status-ring icon shows ready / working / done / needs-attention states; the app keeps running in the menu bar after you close the window.
- **Update checker**: check the latest GitHub Release from the app or the CLI.
- **Operation history**: a searchable history of past operations with file locations.

## Supported Sites

| Platform | Accepted links | Highlights |
| --- | --- | --- |
| Bilibili | Web links, `b23.tv` short links, plain BV ids | High-bitrate 1080P60 / 1080P via your local browser's logged-in cookies; DASH audio + video streams merged losslessly with FFmpeg |
| Xiaohongshu (RED) | Explore-page links, share short links, passcode share text | HD video download with watermark and trailing brand-frame removal |
| Twitter / X | Tweet links | Multi-resolution video, poster's-collection batch extraction, Markdown export of photo posts |

## CLI

The same app binary doubles as a command-line tool: launching it with any arguments enters CLI mode, and `--help` prints the full option list (download quality, download-only mode, GIF output, trim, speed, watermark removal, update check, and more).

```bash
/Applications/cduyzhMediaForge.app/Contents/MacOS/cduyzhMediaForge --help
```

Examples:

```bash
cduyzh-media video.mp4                                    # craft a Live Photo and import it into Photos
cduyzh-media --gif video.mp4                              # WeChat-optimized GIF
cduyzh-media -d "https://www.bilibili.com/video/BV..."    # download a network video
cduyzh-media --start 2.5 --end 5.0 --speed 2.0 video.mp4  # trim + speed change, then import
```

The short `cduyzh-media` command is available when the app is installed with the install script from a source checkout — it points the command at the app in `/Applications` so GUI and CLI always run the same build.

## Download and Install

1. Go to the [Releases](https://github.com/cduyzh/MediaSaver/releases) page and download the latest `.dmg`.
2. Open the DMG and drag `cduyzhMediaForge` into your `Applications` folder.
3. On first launch, allow access to your Photos library when prompted.

Notes:

- Requires macOS 14.0 or later (Apple Silicon / Intel).
- Releases are Ad-hoc signed and not notarized; if Gatekeeper warns on first launch, right-click the app and choose **Open**.
- Network extraction relies on your local `python3`; Bilibili audio/video merging, watermark removal, and resolution scaling rely on `ffmpeg` (for example `brew install ffmpeg`). Neither is bundled with the app. Live Photo and GIF conversion use built-in system frameworks.

## Build from Source

Requirements: macOS 14+, Xcode or the Xcode Command Line Tools (Swift 5.9+).

```bash
git clone https://github.com/cduyzh/MediaSaver.git
cd MediaSaver/App
./build.sh
```

- `./build.sh` compiles the app for your Mac's architecture into a hidden build directory that stays out of Spotlight.
- `./build.sh --install` additionally installs the app into `/Applications`; `--restart` also quits a running copy and relaunches the new build.
- Build a universal binary with `MEDIAFORGE_ARCHS='arm64 x86_64' ./build.sh`.
- `./scripts/install-local.sh --dry-run` previews an install; run it without arguments to install or upgrade.

## Version History

Current version: **1.10.0** (build 10). See [CHANGELOG.md](CHANGELOG.md) for the full history.

## Privacy

- All conversion and processing happen locally on your Mac; the app itself never uploads your media or private data to third-party services.
- When you use cookie-assisted features, the app reads cookies from your local browser on this Mac only, and only for the sites you choose — solely to request higher-bitrate streams from those platforms.
- Network extraction only contacts the platforms whose links you paste.

## License

Released under the [MIT License](https://opensource.org/licenses/MIT). See the `LICENSE` file at the repository root.

## Author

**cduyzh**

- GitHub: <https://github.com/cduyzh>
- Website: <https://www.cduyzh.top>
- Goal: <https://www.cduyzh.top/goal>
