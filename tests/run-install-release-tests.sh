#!/bin/bash
# 精确进程保护与版本读取测试；不触碰 /Applications、索引或 CLI。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/app-common.sh"
for script in "$ROOT/build.sh" "$ROOT/scripts/"*.sh; do
    bash -n "$script"
done
[[ "$APP_VERSION" == "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Info.plist")" ]]
[[ "$APP_BUNDLE" == "$ROOT/.build.noindex/cduyzhMediaForge.app" ]]
[[ "$INSTALLED_APP" == "/Applications/cduyzhMediaForge.app" ]]

TEST_WORK="$(mktemp -d "${TMPDIR:-/tmp}/mediaforge-install-tests.XXXXXX")"
TEST_PID=""
cleanup() {
    if [[ -n "$TEST_PID" ]]; then
        kill "$TEST_PID" 2>/dev/null || true
        wait "$TEST_PID" 2>/dev/null || true
    fi
    rm -rf "$TEST_WORK"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
TEST_APP="$TEST_WORK/path with spaces/cduyzhMediaForge.app"
mkdir -p "$TEST_APP/Contents/MacOS"
ln -s /bin/sleep "$TEST_APP/Contents/MacOS/cduyzhMediaForge"
"$TEST_APP/Contents/MacOS/cduyzhMediaForge" 60 &
TEST_PID=$!
RUNNING="$(running_apps "$TEST_APP")"
[[ "$RUNNING" == *"PID $TEST_PID "* ]]
[[ -z "$(running_apps "$TEST_WORK/unrelated.app")" ]]
if (require_stopped "$TEST_APP") > "$TEST_WORK/refusal.txt" 2>&1; then
    echo "失败：运行中应用未阻止替换。" >&2
    exit 1
fi
kill -0 "$TEST_PID" # 检查保护逻辑没有停止进程。
kill "$TEST_PID"
wait "$TEST_PID" 2>/dev/null || true
TEST_PID=""
[[ -z "$(running_apps "$TEST_APP")" ]]
/bin/bash -c 'exec -a mediaforge-test-cli-alias "$1" 60' _ "$TEST_APP/Contents/MacOS/cduyzhMediaForge" &
TEST_PID=$!
RUNNING="$(running_apps "$TEST_APP")"
[[ "$RUNNING" == *"PID $TEST_PID "* ]]
[[ "$RUNNING" == *"mediaforge-test-cli-alias"* ]]
kill_running_apps "$TEST_APP"
[[ -z "$(running_apps "$TEST_APP")" ]]
echo "安装/发布保护测试通过：统一版本、隐藏构建路径、含空格路径、CLI 别名、拒绝运行中替换且支持主动杀进程清理内存。"
