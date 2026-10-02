#!/usr/bin/env bash
# dev-seed.sh —— Phase 2 无文件夹选择面板（D-03），设置靠预置。
#
# 两条并行预置路径，因为 swift run 起的进程没有 bundle id、UserDefaults 域取不到
# com.local.pic（打包成 .app 后 bundle id 才是 com.local.pic）：
#   ① UserDefaults：defaults write com.local.pic sourceFolderPath '<repo>/fixtures'  ← 本脚本实际执行
#   ② 环境变量：  export PIC_SOURCE_FOLDER='<repo>/fixtures'                          ← 打印，供运行期 eval
#
# 键名必须与 Sources/PicCore/State/SettingsStore.swift 实际读取的键一致：
#   sourceFolderPath / rate / volume / muted / playMode / rotationInterval
# 不做 NSOpenPanel（Phase 4）、不做沙盒 bookmark（PACK-02 已定不上架、不需要沙盒）。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SEED_FOLDER="$ROOT/fixtures"

DEFAULTS_CMD="defaults write com.local.pic sourceFolderPath '$SEED_FOLDER'"
EXPORT_LINE="export PIC_SOURCE_FOLDER='$SEED_FOLDER'"

echo "==> 已执行（打包成 .app 后 bundle id 生效）"
echo "  $DEFAULTS_CMD"
# shellcheck disable=SC2086
eval "$DEFAULTS_CMD"

echo ""
echo "==> 供运行期 eval 的环境变量路径（swift run 无 bundle id 时用这条）"
echo "$EXPORT_LINE"

echo ""
echo "==> 已写入的键（回读校验）"
defaults read com.local.pic 2>/dev/null || echo "  (回读为空)"
