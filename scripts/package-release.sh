#!/bin/bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/app-common.sh"
SOURCE_APP="$APP_BUNDLE"
if [[ "${1:-}" == "--help" ]]; then
    echo "用法：./scripts/package-release.sh [--app 应用路径]"
    echo "复用已有构建，生成版本化 ZIP、DMG、校验和与构建来源；不会上传发布。"
    exit 0
fi
if [[ "${1:-}" == "--app" ]]; then
    [[ $# -eq 2 ]] || fail "--app 需要一个应用路径。"
    SOURCE_APP="$2"
elif [[ $# -ne 0 ]]; then
    fail "未知参数。"
fi
check_bundle "$SOURCE_APP"
[[ -f "$SOURCE_APP/Contents/Resources/build-info.json" ]] || fail "应用缺少构建来源，请用当前 build.sh 重新构建。"
ARCH_LABEL="$(lipo -archs "$SOURCE_APP/Contents/MacOS/$APP_NAME" | xargs | tr ' ' '-')"
OUTPUT_DIR="$PROJECT_ROOT/dist/v$APP_VERSION"
[[ ! -e "$OUTPUT_DIR" ]] || fail "输出目录已存在；为避免覆盖已验证产物，请先将其移走：$OUTPUT_DIR"
mkdir -p "$PROJECT_ROOT/dist"
mkdir -p "$BUILD_DIR"
touch "$BUILD_DIR/.metadata_never_index"
PACKAGE_WORK="$(mktemp -d "$BUILD_DIR/.package.XXXXXX")"
cleanup() { rm -rf "$PACKAGE_WORK"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p "$PACKAGE_WORK/files" "$PACKAGE_WORK/image"
BASE_NAME="$APP_NAME-$APP_VERSION-macos-$ARCH_LABEL"
ditto -c -k --sequesterRsrc --keepParent "$SOURCE_APP" "$PACKAGE_WORK/files/$BASE_NAME.zip"
ditto "$SOURCE_APP" "$PACKAGE_WORK/image/$APP_NAME.app"
ln -s /Applications "$PACKAGE_WORK/image/Applications"
hdiutil create -quiet -volname "$APP_NAME $APP_VERSION" -srcfolder "$PACKAGE_WORK/image" \
    -format UDZO "$PACKAGE_WORK/files/$BASE_NAME.dmg"
hdiutil verify -quiet "$PACKAGE_WORK/files/$BASE_NAME.dmg"
cp "$SOURCE_APP/Contents/Resources/build-info.json" "$PACKAGE_WORK/files/build-info.json"
(
    cd "$PACKAGE_WORK/files"
    shasum -a 256 "$BASE_NAME.zip" "$BASE_NAME.dmg" build-info.json > SHA256SUMS.txt
    shasum -a 256 -c SHA256SUMS.txt
)
mv "$PACKAGE_WORK/files" "$OUTPUT_DIR"
echo "发布工件：$OUTPUT_DIR"
echo "签名为 Ad-hoc，未做 Apple 公证；对外发布说明须如实标注。"
