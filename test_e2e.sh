#!/bin/bash
set -e
cd "$(dirname "$0")"

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo "======================================"
echo "    MediaSaver E2E 测试开始   "
echo "======================================"

# 1. 构建最新的 CLI
echo -e "\n${GREEN}[1/3] 正在构建最新版本...${NC}"
./build.sh > /dev/null
CLI_APP="./.build.noindex/cduyzhMediaForge.app/Contents/MacOS/cduyzhMediaForge"

if [ ! -f "$CLI_APP" ]; then
    echo -e "${RED}构建失败，未找到可执行文件！${NC}"
    exit 1
fi
echo "✅ 构建成功"

# 2. 设置测试资源
TEST_OUTPUT_DIR="./test_output_$$"
mkdir -p "$TEST_OUTPUT_DIR"

# 确保在退出时无论成功与否都清理资源（满足：“删除相关资源文件，保留执行脚本”）
trap 'echo -e "\n${GREEN}[3/3] 清理测试资源...${NC}"; rm -rf "$TEST_OUTPUT_DIR"; echo "✅ 测试资源已清理"' EXIT

# 3. 运行下载和转换测试 (指定不导入相册并输出到本地目录)
echo -e "\n${GREEN}[2/3] 运行网络下载和转换实况测试...${NC}"
TEST_URL="https://x.com/OpenAI/status/2107895000642294250/video/1"
echo "测试链接: $TEST_URL"

# 运行测试，只输出文件，不导入相册 (-o) 避免触发相册弹窗打断自动化
$CLI_APP -o "$TEST_OUTPUT_DIR" "$TEST_URL"

# 检查结果产物是否正确生成
JPG_COUNT=$(ls -1 "$TEST_OUTPUT_DIR"/*.jpg 2>/dev/null | wc -l)
MOV_COUNT=$(ls -1 "$TEST_OUTPUT_DIR"/*.mov 2>/dev/null | wc -l)

if [ "$JPG_COUNT" -gt 0 ] && [ "$MOV_COUNT" -gt 0 ]; then
    echo -e "\n✅ 测试成功！实况图组件生成完毕 (JPG: $JPG_COUNT, MOV: $MOV_COUNT)"
else
    echo -e "\n${RED}❌ 测试失败！未能在输出目录找到生成的 JPG 或 MOV 文件。${NC}"
    exit 1
fi
