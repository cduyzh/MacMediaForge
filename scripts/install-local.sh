#!/bin/bash
# 本机只保留 /Applications 作为用户入口；旧副本先压缩备份再移除。
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/app-common.sh"
DRY_RUN=false
KILL_RUNNING=false
RESTART=false
SOURCE_APP="$APP_BUNDLE"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=true; shift ;;
        --kill) KILL_RUNNING=true; shift ;;
        --restart) KILL_RUNNING=true; RESTART=true; shift ;;
        --app) [[ $# -ge 2 ]] || fail "--app 需要应用路径。"; SOURCE_APP="$2"; shift 2 ;;
        --help)
            echo "用法：./scripts/install-local.sh [--dry-run] [--kill] [--restart] [--app 应用路径]"
            echo "安装到 ${INSTALLED_APP}；归档旧 build/、~/Applications 副本，并修正 CLI 链接。"
            echo "选项："
            echo "  --kill      安装前杀掉正在运行的旧版本进程"
            echo "  --restart   杀掉旧进程、完成安装并重启最新应用"
            echo "  --dry-run   仅预演检查，不作实际修改"
            echo "运行中的应用会阻止安装；备份位于 ~/Library/Application Support/cduyzhMediaForge/InstallBackups。"
            exit 0 ;;
        *) fail "未知参数：$1" ;;
    esac
done
SOURCE_APP="$(cd "$(dirname "$SOURCE_APP")" && pwd)/$(basename "$SOURCE_APP")"
[[ "$SOURCE_APP" != "$INSTALLED_APP" ]] || fail "请从构建目录或已解压发布包安装。"
check_bundle "$SOURCE_APP"

LEGACY_APP="$PROJECT_ROOT/build/$APP_NAME.app"
USER_APP="$HOME/Applications/$APP_NAME.app"
DUPLICATES=()
for candidate in "$LEGACY_APP" "$USER_APP"; do
    if [[ -e "$candidate" || -L "$candidate" ]]; then
        [[ ! -L "$candidate" ]] || fail "旧应用是符号链接，请先核对：$candidate"
        [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$candidate/Contents/Info.plist")" == "$BUNDLE_ID" ]] || fail "旧副本标识不符，不会修改：$candidate"
        [[ "$candidate" != "$SOURCE_APP" ]] || fail "请先复制旧路径中的待安装应用到 .build.noindex，再安装。"
        DUPLICATES+=("$candidate")
    fi
done
if [[ -e "$INSTALLED_APP" || -L "$INSTALLED_APP" ]]; then
    [[ ! -L "$INSTALLED_APP" ]] || fail "安装目标是符号链接：$INSTALLED_APP"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INSTALLED_APP/Contents/Info.plist")" == "$BUNDLE_ID" ]] || fail "安装目标属于其他应用，不会覆盖。"
fi
CLI_LINKS=("$PROJECT_ROOT/../cduyzh-media" "$PROJECT_ROOT/../$APP_NAME" "/usr/local/bin/cduyzh-media" "/usr/local/bin/$APP_NAME")
for link in "${CLI_LINKS[@]}"; do
    [[ ! -e "$link" || -L "$link" ]] || fail "CLI 目标是普通文件，不会覆盖：$link"
    [[ -d "$(dirname "$link")" && -w "$(dirname "$link")" ]] || fail "CLI 目录不可写：$(dirname "$link")"
done
[[ -w /Applications ]] || fail "/Applications 不可写，请用具有本机管理员权限的账户安装。"
echo "版本：$APP_VERSION ($APP_BUILD)"
echo "安装：$SOURCE_APP → $INSTALLED_APP"
for candidate in "${DUPLICATES[@]+${DUPLICATES[@]}}"; do
    echo "归档后移除旧副本：$candidate"
done
echo "CLI 将统一指向：$INSTALLED_APP/Contents/MacOS/$EXEC_NAME"
RUNNING="$(running_apps "$INSTALLED_APP" "$LEGACY_APP" "$USER_APP" "$APP_BUNDLE" "$SOURCE_APP")"
if [[ -n "$RUNNING" ]]; then
    if $KILL_RUNNING; then
        kill_running_apps "$INSTALLED_APP" "$LEGACY_APP" "$USER_APP" "$APP_BUNDLE" "$SOURCE_APP"
    else
        echo "$RUNNING"
        if $DRY_RUN; then
            echo "预演完成：以上应用仍在运行，正式安装将拒绝执行。请等待任务完成后正常退出应用，或使用 --kill / --restart。"
            exit 0
        fi
        fail "请等待下载/转换完成并正常退出以上应用，或使用 --kill / --restart 重试；默认脚本不会中断任务。"
    fi
fi
$DRY_RUN && { echo "预演完成，未修改应用、索引或 CLI。"; exit 0; }

BACKUP_DIR="$HOME/Library/Application Support/$APP_NAME/InstallBackups/$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$BACKUP_DIR"
INSTALL_WORK="$(mktemp -d /Applications/.mediaforge-install.noindex.XXXXXX)"
touch "$INSTALL_WORK/.metadata_never_index"
NEW_INSTALLED=false
INSTALL_COMMITTED=false
cleanup() {
    if ! $INSTALL_COMMITTED; then
        if [[ -d "$INSTALL_WORK/previous.app" ]]; then
            [[ ! -e "$INSTALLED_APP" ]] || rm -rf "$INSTALLED_APP"
            mv "$INSTALL_WORK/previous.app" "$INSTALLED_APP"
            echo "安装未完成，已恢复安装前的应用。备份：$BACKUP_DIR" >&2
        elif $NEW_INSTALLED; then
            [[ ! -e "$INSTALLED_APP" ]] || rm -rf "$INSTALLED_APP"
            echo "安装未完成，已撤销本轮新装应用。备份：$BACKUP_DIR" >&2
        fi
    fi
    rm -rf "$INSTALL_WORK"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ -d "$INSTALLED_APP" ]]; then
    ditto -c -k --sequesterRsrc --keepParent "$INSTALLED_APP" "$BACKUP_DIR/installed-app.zip"
fi
index=0
for candidate in "${DUPLICATES[@]+${DUPLICATES[@]}}"; do
    index=$((index + 1))
    ditto -c -k --sequesterRsrc --keepParent "$candidate" "$BACKUP_DIR/legacy-$index.zip"
    printf '%s\t%s\n' "legacy-$index.zip" "$candidate" >> "$BACKUP_DIR/legacy-paths.txt"
done
for link in "${CLI_LINKS[@]}"; do
    [[ ! -L "$link" ]] || printf '%s\t%s\n' "$link" "$(readlink "$link")" >> "$BACKUP_DIR/cli-links.txt"
done
ditto "$SOURCE_APP" "$INSTALL_WORK/$APP_NAME.app"
check_bundle "$INSTALL_WORK/$APP_NAME.app"
if $KILL_RUNNING; then
    kill_running_apps "$INSTALLED_APP" "$LEGACY_APP" "$USER_APP" "$APP_BUNDLE" "$SOURCE_APP"
else
    require_stopped "$INSTALLED_APP" "$LEGACY_APP" "$USER_APP" "$APP_BUNDLE" "$SOURCE_APP"
fi
if [[ -d "$INSTALLED_APP" ]]; then
    mv "$INSTALLED_APP" "$INSTALL_WORK/previous.app"
fi
NEW_INSTALLED=true
mv "$INSTALL_WORK/$APP_NAME.app" "$INSTALLED_APP"
check_bundle "$INSTALLED_APP"
for link in "${CLI_LINKS[@]}"; do
    ln -sfn "$INSTALLED_APP/Contents/MacOS/$EXEC_NAME" "$link"
done
# ZIP 不作为应用被 Launch Services 或 Spotlight 识别；这里只移除上述已备份的精确路径。
for candidate in "${DUPLICATES[@]+${DUPLICATES[@]}}"; do
    "$LSREGISTER" -u "$candidate" 2>/dev/null || true
    rm -rf "$candidate"
done
if [[ -d "$PROJECT_ROOT/build" ]]; then
    rmdir "$PROJECT_ROOT/build" 2>/dev/null || true
fi
"$LSREGISTER" -u "$SOURCE_APP" 2>/dev/null || true
"$LSREGISTER" -u "$APP_BUNDLE" 2>/dev/null || true
"$LSREGISTER" -f "$INSTALLED_APP"
INSTALL_COMMITTED=true
cat > "$BACKUP_DIR/restore.txt" <<EOF
此目录是本轮安装的可恢复备份。恢复前请等待任务完成并退出应用。
恢复原 /Applications 版本（先移开当前应用，避免新旧文件混合）：
  mkdir -p "$BACKUP_DIR/before-restore.noindex"
  mv "$INSTALLED_APP" "$BACKUP_DIR/before-restore.noindex/"
  ditto -x -k "$BACKUP_DIR/installed-app.zip" /Applications
  codesign --verify --deep --strict "$INSTALLED_APP"
  "$LSREGISTER" -f "$INSTALLED_APP"
旧 build 或用户 Applications 副本的原路径见 legacy-paths.txt；需要时在空目录解压对应 ZIP。
CLI 链接仍指向 /Applications，无需回指 build。
EOF
echo "安装完成：${INSTALLED_APP}（${APP_VERSION}，构建 ${APP_BUILD}）"
echo "旧应用 ZIP 备份：$BACKUP_DIR"
if $RESTART; then
    echo "正在启动新版本应用：$INSTALLED_APP …"
    open "$INSTALLED_APP"
    echo "应用已重新启动！"
else
    echo "启动：open '$INSTALLED_APP'"
fi
