#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mediaforge-cache-tests.XXXXXX")"
trap 'rm -rf "$TEST_WORK_DIR"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p "$TEST_WORK_DIR/fixtures"
xcrun swiftc -parse-as-library \
    -module-cache-path "$TEST_WORK_DIR/module-cache" \
    "$PROJECT_DIR/DownloadCacheManager.swift" \
    "$PROJECT_DIR/tests/CacheStatsTests.swift" \
    -o "$TEST_WORK_DIR/cache-tests"
"$TEST_WORK_DIR/cache-tests" "$TEST_WORK_DIR/fixtures"
