#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mediaforge-media-tests.XXXXXX")"
trap 'rm -rf "$TEST_WORK_DIR"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
FFMPEG_BIN="$(command -v ffmpeg)"
"$FFMPEG_BIN" -hide_banner -loglevel error -f lavfi -i 'color=c=blue:s=160x120:r=30:d=2' -c:v libx264 -pix_fmt yuv420p "$TEST_WORK_DIR/source.mov"
xcrun swiftc -parse-as-library \
    -module-cache-path "$TEST_WORK_DIR/module-cache" \
    "$PROJECT_DIR/ConversionEngine.swift" "$PROJECT_DIR/GIFConverter.swift" \
    "$PROJECT_DIR/WorkExecutionManager.swift" "$PROJECT_DIR/CategorizedStorageManager.swift" \
    "$PROJECT_DIR/CLIHandler.swift" "$PROJECT_DIR/tests/MediaSafetyTests.swift" \
    -o "$TEST_WORK_DIR/media-tests"
"$TEST_WORK_DIR/media-tests" "$TEST_WORK_DIR"
"$TEST_WORK_DIR/media-tests" --cli --version | grep -E '^cduyzh MediaForge .+ \(.+\)$'
SOURCE_HASH="$(shasum -a 256 "$TEST_WORK_DIR/source.mov" | cut -d ' ' -f1)"
"$TEST_WORK_DIR/media-tests" --cli -o "$TEST_WORK_DIR" --start 0.2 --end 1.7 --speed 1.5 "$TEST_WORK_DIR/source.mov"
test "$SOURCE_HASH" = "$(shasum -a 256 "$TEST_WORK_DIR/source.mov" | cut -d ' ' -f1)"
test -s "$TEST_WORK_DIR/source_2.jpg"
test -s "$TEST_WORK_DIR/source_2.mov"
if "$TEST_WORK_DIR/media-tests" --cli -o "$TEST_WORK_DIR" "$TEST_WORK_DIR/missing.mov"; then
    echo 'FAIL: CLI 对缺失输入返回成功'; exit 1
fi
if "$TEST_WORK_DIR/media-tests" --cli -o "$TEST_WORK_DIR" --speed nan "$TEST_WORK_DIR/source.mov"; then
    echo 'FAIL: CLI 接受 NaN 速度'; exit 1
fi
if "$TEST_WORK_DIR/media-tests" --cli -o "$TEST_WORK_DIR" --end 20 "$TEST_WORK_DIR/source.mov"; then
    echo 'FAIL: CLI 接受越界裁剪'; exit 1
fi
echo 'PASS: CLI 同目录导出保留源视频、无效输入/参数返回非零退出码'
