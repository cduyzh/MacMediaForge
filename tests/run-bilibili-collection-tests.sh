#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mediaforge-bili-tests.XXXXXX")"
trap 'rm -rf "$TEST_WORK_DIR"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

xcrun swiftc -parse-as-library \
    -module-cache-path "$TEST_WORK_DIR/module-cache" \
    "$PROJECT_DIR/BilibiliDownloader.swift" \
    "$PROJECT_DIR/WorkExecutionManager.swift" \
    "$PROJECT_DIR/DownloadCacheManager.swift" \
    "$PROJECT_DIR/CategorizedStorageManager.swift" \
    "$PROJECT_DIR/AppSettings.swift" \
    "$PROJECT_DIR/tests/BilibiliCollectionTests.swift" \
    -o "$TEST_WORK_DIR/bili-tests"

"$TEST_WORK_DIR/bili-tests"
