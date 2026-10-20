#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mediaforge-quality-tests.XXXXXX")"
trap 'rm -rf "$TEST_WORK_DIR"' EXIT

xcrun swiftc -parse-as-library \
    -module-cache-path "$TEST_WORK_DIR/module-cache" \
    "$PROJECT_DIR/VideoQualityOption.swift" \
    "$PROJECT_DIR/tests/VideoQualityTests.swift" \
    -o "$TEST_WORK_DIR/quality-tests"

"$TEST_WORK_DIR/quality-tests"
