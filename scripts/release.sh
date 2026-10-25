#!/bin/bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/app-common.sh"
REPOSITORY="cduyzh/LivePhotoForge"
PUBLISH=false
NOTES_FILE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --publish) PUBLISH=true; shift ;;
        --notes-file) [[ $# -ge 2 ]] || fail "--notes-file 需要文件路径。"; NOTES_FILE="$2"; shift 2 ;;
        --help)
            echo "用法：./scripts/release.sh --notes-file 发布说明.md [--publish]"
            echo "默认仅验证；--publish 使用已存在的 v$APP_VERSION 远端标签创建 Release，复用 dist/v$APP_VERSION 工件。"
            echo "不会创建标签、提交、推送、重建或覆盖已发布 Release。"
            exit 0 ;;
        *) fail "未知参数：$1" ;;
    esac
done
[[ -f "$NOTES_FILE" && -s "$NOTES_FILE" ]] || fail "请提供非空发布说明。"
check_bundle "$APP_BUNDLE"
check_provenance "$APP_BUNDLE"
TAG="v$APP_VERSION"
LOCAL_REVISION="$($GIT_BIN -C "$PROJECT_ROOT" rev-parse HEAD)"
REMOTE_TAG="$($GIT_BIN -C "$PROJECT_ROOT" ls-remote origin "refs/tags/$TAG" "refs/tags/$TAG^{}")"
[[ -n "$REMOTE_TAG" ]] || fail "远端标签 $TAG 不存在；请先完成已授权的提交、推送与打标签。"
REMOTE_REVISION="$(printf '%s\n' "$REMOTE_TAG" | tail -1 | cut -f1)"
[[ "$REMOTE_REVISION" == "$LOCAL_REVISION" ]] || fail "远端标签 $TAG 与当前已构建提交不一致。"
OUTPUT_DIR="$PROJECT_ROOT/dist/$TAG"
[[ -f "$OUTPUT_DIR/SHA256SUMS.txt" && -f "$OUTPUT_DIR/build-info.json" ]] || fail "请先运行 ./scripts/package-release.sh。"
cmp "$APP_BUNDLE/Contents/Resources/build-info.json" "$OUTPUT_DIR/build-info.json" || fail "打包产物与当前构建来源不同。"
(
    cd "$OUTPUT_DIR"
    shasum -a 256 -c SHA256SUMS.txt
)
# 区分不存在与连接失败，避免网络错误时贸然创建。
EXISTING_RELEASES="$(gh api "repos/$REPOSITORY/releases" --paginate --jq '.[].tag_name')"
if printf '%s\n' "$EXISTING_RELEASES" | /usr/bin/grep -Fxq "$TAG"; then
    fail "$TAG 已发布，不会覆盖已有 Release。"
fi
echo "验证完成：$REPOSITORY ${TAG}，提交 ${LOCAL_REVISION}。"
if ! $PUBLISH; then
    echo "预演完成，未修改远端。实际发布加 --publish。"
    exit 0
fi
gh release create "$TAG" --repo "$REPOSITORY" --verify-tag --title "MediaSaver $TAG" \
    --notes-file "$NOTES_FILE" "$OUTPUT_DIR/"*.zip "$OUTPUT_DIR/"*.dmg \
    "$OUTPUT_DIR/SHA256SUMS.txt" "$OUTPUT_DIR/build-info.json"
gh release view "$TAG" --repo "$REPOSITORY" --json url,tagName,assets
