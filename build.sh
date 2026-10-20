#!/bin/bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/scripts/app-common.sh"
cd "$PROJECT_ROOT"

INSTALL=false
KILL_RUNNING=false
RESTART=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --install) INSTALL=true; shift ;;
        --kill) KILL_RUNNING=true; shift ;;
        --restart) INSTALL=true; KILL_RUNNING=true; RESTART=true; shift ;;
        --help)
            echo "用法：./build.sh [--install] [--kill] [--restart]"
            echo "默认构建本机架构；MEDIAFORGE_ARCHS='arm64 x86_64' ./build.sh 构建通用版。"
            echo "选项："
            echo "  --install   构建后自动安装到 /Applications"
            echo "  --kill      构建前杀掉运行中的旧进程"
            echo "  --restart   杀掉旧进程、构建、安装并自动重启新应用"
            echo "输出：${APP_BUNDLE}（隐藏且不参与 Spotlight 索引；不会安装或改变 CLI）。"
            exit 0 ;;
        *) fail "未知参数：$1；使用 ./build.sh --help 查看用法。" ;;
    esac
done

mkdir -p "$BUILD_DIR"
touch "$BUILD_DIR/.metadata_never_index"
mkdir "$BUILD_DIR/.build.lock" 2>/dev/null || fail "另一轮构建正在进行；若上次异常退出，请确认无构建进程后清除 .build.noindex/.build.lock。"
WORK_DIR=""
cleanup() {
    [[ -z "$WORK_DIR" ]] || rm -rf "$WORK_DIR"
    rmdir "$BUILD_DIR/.build.lock" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
if $KILL_RUNNING; then
    kill_running_apps "$APP_BUNDLE" "$INSTALLED_APP"
else
    require_stopped "$APP_BUNDLE"
fi
WORK_DIR="$(mktemp -d "$BUILD_DIR/.compile.XXXXXX")"
STAGED_APP="$WORK_DIR/$APP_NAME.app"
CONTENTS="$STAGED_APP/Contents"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

SWIFT_FILES=(
    main.swift MediaForgeApp.swift VideoQualityOption.swift VideoItem.swift WorkExecutionManager.swift
    ConversionEngine.swift CLIHandler.swift ContentView.swift MediaForgeUI.swift
    TwitterDownloader.swift BilibiliDownloader.swift LivePhotoExtractor.swift GIFConverter.swift
    CategorizedStorageManager.swift DownloadCacheManager.swift SettingsView.swift
    NetworkVideoDownloader.swift NetworkVideoPreParser.swift PreParsedVideoCardView.swift
    BilibiliCollectionSheetView.swift
    XHSAuthManager.swift XHSAuthSheetView.swift AppSettings.swift VideoWatermarkRemover.swift
    ConversionViewModel.swift VideoCardView.swift NetworkExtractorView.swift XHSAssistantView.swift
    SettingsTabView.swift OperationHistoryManager.swift OperationHistoryView.swift ChangelogView.swift
    UpdateChecker.swift
)
read -r -a ARCHS <<< "${MEDIAFORGE_ARCHS:-$(uname -m)}"
[[ ${#ARCHS[@]} -gt 0 ]] || fail "缺少目标架构。"
BINARIES=()
for arch in "${ARCHS[@]}"; do
    [[ "$arch" == "arm64" || "$arch" == "x86_64" ]] || fail "不支持的架构：$arch"
    echo "编译 $APP_VERSION ($APP_BUILD)，架构：${arch}…"
    binary="$WORK_DIR/$APP_NAME-$arch"
    xcrun swiftc -sdk "$(xcrun --show-sdk-path)" -target "$arch-apple-macosx$MINIMUM_MACOS" \
        -framework SwiftUI -framework Photos -framework AVFoundation \
        -framework UniformTypeIdentifiers -framework ImageIO -framework CoreImage \
        -O -o "$binary" "${SWIFT_FILES[@]}"
    BINARIES+=("$binary")
done
if [[ ${#BINARIES[@]} -eq 1 ]]; then
    cp "${BINARIES[0]}" "$CONTENTS/MacOS/$APP_NAME"
else
    xcrun lipo -create "${BINARIES[@]}" -output "$CONTENTS/MacOS/$APP_NAME"
fi

cp Info.plist "$CONTENTS/"
cp AppIcon.icns "$CONTENTS/Resources/"
cp AppIcon_1024.png "$CONTENTS/Resources/AppIcon.png"
cp xhs_downloader.py twitter_downloader.py bilibili_downloader.py mediaforge_network.py xhs_browser_batch_helper.js "$CONTENTS/Resources/"
SOURCE_REVISION="$(git rev-parse HEAD)"
SOURCE_DIRTY="$(git status --porcelain)"
/usr/bin/python3 - "$CONTENTS/Resources/build-info.json" "$SOURCE_REVISION" "$SOURCE_DIRTY" "$APP_VERSION" "$APP_BUILD" "${ARCHS[*]}" <<'PY'
import datetime, json, sys
with open(sys.argv[1], "w") as output:
    json.dump({"sourceCommit": sys.argv[2], "sourceDirty": bool(sys.argv[3]),
               "version": sys.argv[4], "build": sys.argv[5], "architectures": sys.argv[6].split(),
               "builtAtUTC": datetime.datetime.now(datetime.timezone.utc).isoformat(),
               "signing": "ad-hoc; not notarized"}, output, indent=2)
    output.write("\n")
PY
echo "执行本地 Ad-hoc 签名并验证…"
codesign --force --deep --sign - "$STAGED_APP"
check_bundle "$STAGED_APP"
# 完成后才替换上次构建；旧 build/ 不在构建时删除，避免影响运行中的旧应用。
if [[ -d "$APP_BUNDLE" ]]; then
    mv "$APP_BUNDLE" "$WORK_DIR/previous.app"
fi
mv "$STAGED_APP" "$APP_BUNDLE"
echo "构建完成：$APP_BUNDLE"
echo "签名：Ad-hoc，未经过 Developer ID 签名或 Apple 公证。"
if $INSTALL; then
    echo "======================================"
    echo "正在执行自动安装升级…"
    local_args=()
    if $KILL_RUNNING; then local_args+=("--kill"); fi
    if $RESTART; then local_args+=("--restart"); fi
    if ((${#local_args[@]} > 0)); then
        "$PROJECT_ROOT/scripts/install-local.sh" "${local_args[@]}"
    else
        "$PROJECT_ROOT/scripts/install-local.sh"
    fi
else
    echo "安装/升级唯一应用入口：./scripts/install-local.sh --dry-run，确认后 ./scripts/install-local.sh"
fi
