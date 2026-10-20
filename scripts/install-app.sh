#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# 构建串行化：并发构建会踩坏 XCBuild 增量库（详见 scripts/build-guard.sh 头注释）。
source scripts/build-guard.sh

APP_NAME="壁纸儿"
INSTALL_DIR="/Applications"
BIN="${INSTALL_DIR}/${APP_NAME}.app/Contents/MacOS/${APP_NAME}"
START_EPOCH=$(date +%s)

command -v trash >/dev/null 2>&1 || { echo "错误：未找到 trash 命令（本仓删文件只用 trash，不回退 rm）" >&2; exit 1; }

echo "==> 构建"
./build.sh

echo "==> 杀旧实例"
# 无实例时 pkill 返回非零属正常路径，必须 || true 否则 set -e 直接退。
pkill -f "/${APP_NAME}.app/Contents/MacOS/${APP_NAME}" || true

echo "==> 清旧包"
if [ -e "${INSTALL_DIR}/${APP_NAME}.app" ]; then
  trash "${INSTALL_DIR}/${APP_NAME}.app"
fi

echo "==> 安装"
cp -R "build/${APP_NAME}.app" "${INSTALL_DIR}/"

echo "==> 启动"
open "${INSTALL_DIR}/${APP_NAME}.app"
sleep 2

echo "==> 验证"
PIDS=$(pgrep -f "${INSTALL_DIR}/${APP_NAME}.app/Contents/MacOS") || true
if [ -z "$PIDS" ]; then
  echo "错误：启动后未检测到运行实例" >&2
  exit 1
fi
BIN_MTIME=$(stat -f %m "$BIN")
if [ "$BIN_MTIME" -lt "$START_EPOCH" ]; then
  echo "错误：二进制 mtime 早于脚本启动时刻，/Applications 装的不是新包" >&2
  exit 1
fi

echo ""
echo "✅ 安装完成"
echo "   PID   : $PIDS"
echo "   二进制: $BIN"
echo "   mtime : $(date -r "$BIN_MTIME" '+%Y-%m-%d %H:%M:%S')"
