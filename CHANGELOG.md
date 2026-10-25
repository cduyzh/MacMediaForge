# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Added a crawler data persistence layer `mediaforge_store.py` (SQLite at `~/Library/Application Support/cduyzhMediaForge/crawler_data.db`): records the title, author, quality and file path of every download, keyed by platform business ID (tweet_id / note_id / BV id), and preserves them across restarts; provides `check` / `recent` / `prune` command-line queries.
- Content-level deduplication: re-downloading the same tweet / note / BV video at the same quality now hard-links and reuses the local file (zero extra disk usage) instead of pulling the stream again; this eliminates the guaranteed duplicate files caused by Xiaohongshu's timestamp+UUID filenames.
- Parse-result cache with TTL: pasting the same link again after a restart hits the local cache and displays instantly — 30 minutes for Xiaohongshu/Bilibili and 6 hours for Twitter; when a cached direct link expires, it is invalidated automatically and one online re-parse round is performed.

### Changed
- Download core rewritten (`mediaforge_network.py`): exponential backoff with full-jitter retries; 429/5xx are retryable while 400/401/403/404/410/451 fail fast; `.part` resumable downloads (with URL fingerprinting); dual Content-Range and size verification; interception of `text/html` hotlink-protection error pages; atomic `os.replace` finalization — failed downloads no longer leave partial files behind.
- When a Bilibili playback direct link expires, it is automatically fetched again with one retry round; download failures now record their reason in the persistence layer.
- Xiaohongshu authentication cookies are now passed to the Python script via environment variables and no longer appear in command-line arguments (avoiding observation via `ps`).
- Download history deduplicated (the same source + file updates in place instead of inserting duplicates) and capped at 500 entries, fixing double records and unbounded UserDefaults growth.

### Fixed
- Security hardening for the local batch receiver server (`local_batch_server.py`): only accepts pushes originating from Xiaohongshu pages and localhost (preventing arbitrary web pages from driving local downloads); supports optional token verification (`MEDIAFORGE_BATCH_TOKEN`); sends the Xiaohongshu Referer with download requests to avoid CDN 403s; deduplicates by note ID before recording.

## [1.10.0] - 2026-10-20

### Added
- Added four download-quality preferences — 1080P, 720P, 480P and 360P — selectable in Settings, on each pre-parsed card, and in the CLI.
- Bilibili parsing requests the DASH/MP4 quality matching the selected tier; Twitter parsing selects the matching variant stream; Xiaohongshu parsing prefers the selected quality.
- Videos above the selected tier are scaled down proportionally; the system ceiling is 1080P. When FFmpeg is missing or scaling fails, the reason is shown and the source video is kept.

### Fixed
- Network scripts no longer pass JavaScript from web responses to Node for execution; script status is parsed safely as JSON only.
- Kept the warning shown when Twitter multi-video quality adjustment fails; failed videos skip watermark removal, so files that do not match the selected quality are never treated as successful output.
- The Bilibili single-segment MP4 fallback now follows the user's selected quality instead of always requesting 720P.
- When the local version is newer than the latest GitHub release, the update page and CLI now report that the local version has not been released yet instead of falsely claiming it is the latest.
- When the CLI queries its version through a PATH symlink, it reads the actual version and build number of the app that the link points to.

## [1.9.0] - 2026-10-18

### UI & Interactions
- Local crafting, network extraction, the Xiaohongshu assistant, Settings and History now use a unified system color scheme, grouping and spacing; primary actions are pinned to the bottom bar.
- Switching workspaces preserves inputs and in-flight tasks; empty states, file-import feedback, error details, partial success, failure retry and cancel-termination states are all covered.
- Settings and the changelog show the actual version, build number and app location; History supports search, filter reset and file reveal.
- Cache statistics moved to the background with merged duplicate refreshes, so slow directories no longer block the interface.

### Features & Security Fixes
- Same-name paired outputs are numbered pairwise, protecting source videos and existing results; failed exports roll back the files produced in that round.
- GIF and MOV output validate trim, speed and duration; cancellation is supported, and encoding failures no longer report success.
- The CLI validates invalid arguments and returns a non-zero exit code when a task fails.
- Network crafting propagates GIF, paired-export and Photos-import failures while keeping and showing completed results; when saving the original video is disabled, only the chosen outputs are kept.
- Cancellation cleans up only the files registered in the current round, avoiding deleting private files by extension.
- Network parsing enables certificate and hostname verification and reads the macOS system root certificates; removed a hard-coded path fallback for the developer's machine.

### Build, Install & Release
- Unified the version source and explicitly build for macOS 14+; development artifacts go into a hidden build directory that does not participate in Spotlight indexing, so build copies no longer appear in Spotlight.
- Before installing, running tasks are checked; old copies are ZIP-backed up first, then `/Applications` and the CLI entry point are unified.
- Added signature verification, DMG/ZIP packaging, checksums and traceable release scripts; currently Ad-hoc signed and not notarized by Apple.
- Website fixes for download links, the command-line entry point, copy feedback and keyboard interactions.

## [1.8.0] - 2026-10-17

### Added & Optimized
- **Full Bilibili video parsing and 1080P60 HD download support**:
  - **Smart link extraction across the whole chain**: fully supports web links (`bilibili.com/video/BV...`), share short links (`b23.tv/...`) and plain BV ids, recognized and resolved through redirects.
  - **Smart browser cookie detection**: automatically reads the logged-in Bilibili cookies of mainstream local browsers such as Chrome, Safari and Edge to activate the top 1080P 60fps / high-bitrate 1080P quality.
  - **DASH split audio/video fast fetching with native lossless merging**: DASH's separate audio and video streams are fetched in parallel at full speed and merged in seconds into a standard MP4 container with FFmpeg `-c copy` — fully compatible with macOS native players, AVFoundation, the Photos library and Live Photo crafting.
  - **Real-time first-frame and poster pre-parse**: pasting a link instantly fetches the HD cover image and video metadata (uploader, title, quality), enabling instant direct downloads.
  - **Structured four-layer archiving**: files are automatically archived under `~/Downloads/cduyzhMediaForge/Bilibili/<date>/Videos/`, with a one-click shortcut to today's directory.
  - **Comprehensive CLI enhancements**: added the `-d, --download` standalone download mode for pulling high-quality videos from Bilibili and other platforms straight from the terminal.

## [1.7.0] - 2026-10-16

### Changed & Rebranded
- **Full rebrand and rename to "MediaSaver"**:
  - Reflects the product's all-in-one positioning across social-media video extraction, watermark and trailing-frame removal, real-time first-frame and cover pre-parsing, Apple Live Photo crafting and import, official-account GIF conversion, light editing and layered archiving.
  - Injects the developer's personal brand `cduyzh`, establishing the flagship positioning of an all-round cross-platform desktop media workshop.
- **Smooth storage architecture transition**:
  - The default working storage directory was normalized to `~/Downloads/cduyzhMediaForge`.
  - Existing downloads in the old directory are detected and migrated losslessly and automatically, keeping users' personal data safely continuous.
- **Security whitelist and cleanup isolation upgrade**:
  - Whitelist rules now also manage the `cduyzhMediaForge` identity, remaining two-way compatible with historical temporary caches under a strict zero-collateral-damage principle.
- **Old package cleanup and lightweight build**:
  - Thoroughly cleaned up historical old binary packages and obsolete archive files; the build now produces a clean `cduyzhMediaForge.app`.

## [1.6.0] - 2026-10-16

### Added & Optimized
- **Automatic link-paste pre-parse with real-time first-frame/cover preview**:
  - Pasting or typing a link automatically triggers a debounced asynchronous pre-parse — no need to wait for a download click.
  - The ready area displays a dedicated card for each video, including:
    - **First-frame preview**: automatically uses the official poster cover, or precisely decodes the frame at second 0 via AVFoundation/FFmpeg, presented as a refined 16:9 rounded card.
    - **Title and author information**: the full video/post title, author nickname and username (e.g. `Google Gemini (@GeminiApp)`), the resolution (e.g. `1080P`) and the multi-video count.
    - **Live status and retry**: clear states such as "Pre-parsing…", "Pre-parse complete (direct links and first frame cached)" and a retry entry on failure.
- **Direct fast-download engine that skips re-parsing**:
  - Clicking "Start direct batch download" reads the pre-parsed direct links and structured data directly, completely skipping repeated web requests and a second parse, for millisecond-level instant fetching.
  - Twitter full poster video collections, long-post Markdown summaries and Xiaohongshu videos all download seamlessly at full speed.

## [1.5.0] - 2026-10-14

### Added & Optimized
- **Product naming, default directory and the four-layer category system**:
  - The default download directory was renamed to match the product name, and the old directory migrates automatically and smoothly.
  - Established standard layered management: `[platform (Xiaohongshu/Twitter/default)] → [date (e.g. Oct 14, 2026)] → [category (Videos/Live Photos/GIFs/Docs)]`.
  - During Twitter parsing, videos and post Markdown summaries are written directly into the `Videos` and `Docs` directories under the matching platform and date.
  - Added the `CategorizedStorageManager` architecture: directories created on demand, automatic anti-overwrite incrementing for name collisions, and one-click categorized reveal in Finder.
- **Optional GIF generation and categorized storage**:
  - GIF generation became an option and is off (`false`) by default, avoiding unnecessary conversions that occupy storage.
  - Generated GIFs are stored automatically in the `GIF` subdirectory under the matching platform and date, managed alongside videos and Live Photos from the same source.
- **Custom concurrent download scheduler**:
  - Added `AsyncSemaphore` concurrency control and task scheduling based on Swift Actors.
  - Adjustable concurrency in the 1–10 thread range greatly improves multi-link batch download efficiency.
- **Consolidated Settings center with two-way dynamic sync**:
  - All core options (save locally, convert to Live Photo, generate GIF, Twitter Markdown export, delogo watermark removal, automatic trailing-frame trim, concurrency, etc.) moved into the Settings center.
  - The main extraction panel and system settings sync bidirectionally in real time; configuration changes apply, persist and take effect immediately.
- **Cache safety upgrade**:
  - `DownloadCacheManager` gained recursive scanning to precisely measure and safely clean the managed caches under the product's categorized directories, never overstepping into personal files.

## [1.4.0] - 2026-10-13

### Added
- **Xiaohongshu video parsing and watermark-free download integration**:
  - Integrated multi-channel Xiaohongshu parsing and a watermark-free download engine, fully replacing the manual copy-and-parse web flow.
  - Supports pasting Xiaohongshu note/explore links (e.g. `https://www.xiaohongshu.com/explore/6aae6114000000002700a168`), share short links (`xhslink.com`) and copied share text; HD videos are extracted and downloaded automatically.
  - A standalone **"Save video locally"** option saves the original video to the system Downloads folder (`~/Downloads`) by default, with one-click switching to any custom location.
  - A standalone **"Convert to Live Photo"** option losslessly packages the finished download and injects it into the macOS Photos library (with real-time iCloud sync to iPhone).
  - **Mandatory validation**: at least one of "Save video locally" or "Convert to Live Photo" must be selected; with neither selected, the button is intelligently disabled with a highlighted hint.
  - CLI mode fully supports passing Xiaohongshu links with the fully automatic pipeline.

## [1.3.0] - 2026-10-13

### Added
- **Preferences and video download cache management**:
  - New dedicated preferences panel (openable via the top-bar Settings button or the `⌘,` shortcut).
  - Custom network-video download cache directory: choose any folder, reveal it in Finder with one click, or restore the default path with one click.
  - Live statistics of the disk space and file count used by the current download cache.
  - **One-click cache clearing**: thoroughly removes historical download data caches and source video files to reclaim disk space quickly.
  - New download history list: filename, size, download date and original link, with per-entry reveal and precise deletion.
  - Queue and cache cleanup are linked: after clearing the cache, the pending queue state syncs automatically to avoid errors converting invalid files.

## [1.2.0] - 2026-10-13

### Changed & Improved
- **Brand-new interface rebuild and larger layout**:
  - Window size expanded to 980×720 (minimum 860×620), saying goodbye to crowding with an open, modern desktop view.
  - The top navigation bar gained a three-mode segmented switch: Live Photo (import to library), WeChat official-account GIF, and paired-files-only export.
  - The drag-and-drop zone enlarged to 165px with drag glow micro-interactions and rich format hint tags.
  - Video list cards redesigned: thumbnails enlarged to 128×78 (Retina class) with duration badges and a clean metadata layout.
  - The video adjustment panel (trim, cover frame selection, speed) enlarged to 340px with live preview and quick presets.
  - Compliant modern SF Symbols used throughout, eliminating system runtime assertions caused by invalid icons.
- **Live Photo metadata pairing fix**:
  - The cover image now writes the Apple MakerNote `AssetIdentifier` (Tag 17) and the MOV container writes `com.apple.quicktime.content.identifier`, completely fixing Photos library import failures with `PHPhotosErrorDomain Code=3302 (invalidResource)`.

## [1.0.0] - 2026-10-09

### Added
- **Video to GIF**: added conversion into optimized GIFs suitable for WeChat official-account article layouts. In the GUI, choose it at "Start Conversion"; the CLI supports the `--gif` flag.
- **Video editing (trim & speed)**: a visual trim and speed panel for each pending video in the GUI; the CLI tool gained `--start`, `--end` and `--speed` parameters.
- **Live Photo to video**: pick a Live Photo from the library and save its video component directly to the Downloads folder.
- **GUI mode**: a minimal SwiftUI drag-and-drop interface supporting batch import and processing.
- **CLI mode**: a command-line tool built into the same binary, supporting `--import`, the `-o` output directory, `--frame-time` cover frame selection and more.
- **Native engine**: fully rebuilt on pure Swift with `AVFoundation` + `PHPhotoLibrary`, free of third-party dependencies.
- **Lossless conversion**: H.264 videos use Passthrough mode for millisecond-level, zero-quality-loss repackaging.
- **Automatic Photos import**: after processing, the perfectly paired result is saved into the system Photos library via low-level macOS APIs for seamless iCloud sync with iPhone.
- **Static website**: added an SEO-optimized static project homepage with one-click install instructions and download links.
