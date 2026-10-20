#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mediaforge-update-tests.XXXXXX")"
trap 'rm -rf "$TEST_WORK_DIR"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

xcrun swiftc -parse-as-library \
    -module-cache-path "$TEST_WORK_DIR/module-cache" \
    "$PROJECT_DIR/VideoQualityOption.swift" \
    "$PROJECT_DIR/AppSettings.swift" \
    "$PROJECT_DIR/UpdateChecker.swift" \
    "$PROJECT_DIR/tests/UpdateCheckerTests.swift" \
    -o "$TEST_WORK_DIR/update-tests"

"$TEST_WORK_DIR/update-tests"
