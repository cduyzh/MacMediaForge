#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mediaforge-menu-icon-tests.XXXXXX")"
trap 'rm -rf "$TEST_WORK_DIR"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
xcrun swiftc -parse-as-library \
    -module-cache-path "$TEST_WORK_DIR/module-cache" \
    "$PROJECT_DIR/MenuBarState.swift" \
    "$PROJECT_DIR/MenuBarIcon.swift" \
    "$PROJECT_DIR/tests/MenuBarIconTests.swift" \
    -o "$TEST_WORK_DIR/menu-icon-tests"
mkdir -p "$PROJECT_DIR/.build.noindex"
"$TEST_WORK_DIR/menu-icon-tests" "$PROJECT_DIR/.build.noindex/menu-bar-icons.png"
