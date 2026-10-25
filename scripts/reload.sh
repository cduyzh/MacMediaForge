#!/bin/bash
# cduyzhMediaForge 一键构建、杀旧进程、安装并重启脚本
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec "$PROJECT_ROOT/build.sh" --restart "$@"
