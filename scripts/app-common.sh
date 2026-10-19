#!/bin/bash
# 仅由同目录脚本加载；Info.plist 是版本号与构建号的唯一来源。
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="cduyzhMediaForge"
BUNDLE_ID="com.cduyzh.MediaForge"
BUILD_DIR="$PROJECT_ROOT/.build.noindex"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
INSTALLED_APP="/Applications/$APP_NAME.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_ROOT/Info.plist")"
APP_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PROJECT_ROOT/Info.plist")"
MINIMUM_MACOS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$PROJECT_ROOT/Info.plist")"
if [[ ! "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || ! "$APP_BUILD" =~ ^[0-9]+$ ]]; then
    echo "错误：Info.plist 中的版本或构建号格式无效。" >&2
    exit 1
fi
[[ "$MINIMUM_MACOS" =~ ^[0-9]+\.[0-9]+$ ]] || { echo "错误：最低 macOS 版本格式无效。" >&2; exit 1; }

fail() { echo "错误：$*" >&2; exit 1; }

check_bundle() {
    local bundle="$1"
    [[ -d "$bundle" && ! -L "$bundle" ]] || fail "应用不存在或是符号链接：$bundle"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bundle/Contents/Info.plist")" == "$BUNDLE_ID" ]] || fail "应用标识不符：$bundle"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$bundle/Contents/Info.plist")" == "$APP_VERSION" ]] || fail "应用版本与 Info.plist 不符：$bundle"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$bundle/Contents/Info.plist")" == "$APP_BUILD" ]] || fail "应用构建号与 Info.plist 不符：$bundle"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$bundle/Contents/Info.plist")" == "$APP_NAME" ]] || fail "应用启动文件声明不符：$bundle"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$bundle/Contents/Info.plist")" == "$MINIMUM_MACOS" ]] || fail "应用最低系统版本与 Info.plist 不符：$bundle"
    [[ -x "$bundle/Contents/MacOS/$APP_NAME" ]] || fail "应用缺少可执行文件：$bundle"
    codesign --verify --deep --strict "$bundle"
}

# 只匹配这些应用自身的可执行文件；不会停止应用或子进程。
running_apps() {
    /bin/ps -axo pid=,command= | /usr/bin/python3 -c '
import ctypes, os, sys
executables = [os.path.join(p, "Contents/MacOS/cduyzhMediaForge") for p in sys.argv[1:]]
resolved = {os.path.realpath(path) for path in executables}
libproc = ctypes.CDLL("/usr/lib/libproc.dylib")
libproc.proc_pidpath.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32]
libproc.proc_pidpath.restype = ctypes.c_int
for line in sys.stdin:
    row = line.strip().split(None, 1)
    if len(row) != 2:
        continue
    # CLI 经符号链接启动时 argv[0] 可能是别名，实际可执行文件路径才是可靠依据。
    buffer = ctypes.create_string_buffer(4096)
    size = libproc.proc_pidpath(int(row[0]), buffer, len(buffer))
    actual = os.path.realpath(os.fsdecode(buffer.value)) if size > 0 else None
    if actual in resolved or any(row[1] == exe or row[1].startswith(exe + " ") for exe in executables):
        print("PID " + row[0] + "  " + row[1])
' "$@"
}

require_stopped() {
    local running
    running="$(running_apps "$@")"
    if [[ -n "$running" ]]; then
        echo "$running" >&2
        fail "请等待下载/转换完成并正常退出以上应用，再重试；本脚本不会中断任务。"
    fi
}

kill_running_apps() {
    local targets=("$@")
    if [[ ${#targets[@]} -eq 0 ]]; then
        targets=("$INSTALLED_APP" "$PROJECT_ROOT/build/$APP_NAME.app" "$HOME/Applications/$APP_NAME.app" "$APP_BUNDLE")
    fi
    local running pids
    running="$(running_apps "${targets[@]}")"
    if [[ -z "$running" ]]; then
        return 0
    fi
    pids=($(printf '%s\n' "$running" | awk '{print $2}'))
    echo "发现正在运行的旧版本应用实例（PID: ${pids[*]}），正在终止以释放旧进程内存…"
    for pid in "${pids[@]}"; do
        kill -TERM "$pid" 2>/dev/null || true
    done
    local waited=0
    while [[ $waited -lt 30 ]]; do
        local still_running=0
        for pid in "${pids[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                still_running=1
                break
            fi
        done
        if [[ $still_running -eq 0 ]]; then
            break
        fi
        sleep 0.1
        waited=$((waited + 1))
    done
    for pid in "${pids[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            echo "进程 $pid 未响应退出，强制终止 (SIGKILL)…"
            kill -KILL "$pid" 2>/dev/null || true
        fi
    done
    echo "旧进程已全部退出清理。"
}

check_provenance() {
    local bundle="$1" revision
    revision="$(git -C "$PROJECT_ROOT" rev-parse HEAD)"
    [[ -z "$(git -C "$PROJECT_ROOT" status --porcelain)" ]] || fail "发布需要干净的 Git 工作区，请先提交待发布源码。"
    /usr/bin/python3 - "$bundle/Contents/Resources/build-info.json" "$revision" <<'PY'
import json, sys
try:
    info = json.load(open(sys.argv[1]))
except (OSError, ValueError) as error:
    raise SystemExit("无法读取构建来源，请重新构建：" + str(error))
if info.get("sourceCommit") != sys.argv[2] or info.get("sourceDirty") is not False:
    raise SystemExit("构建并非来自当前已提交源码，请在提交完成后重新构建。")
PY
}
