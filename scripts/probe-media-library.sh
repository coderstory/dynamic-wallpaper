#!/usr/bin/env bash
# probe-media-library.sh —— tracer 活体证据采集。一条命令，无参数：
#
#   bash scripts/probe-media-library.sh
#     → 先跑 scripts/make-media-fixture-tree.sh 建树（保证 driver 有输入）
#     → 编译 throwaway driver（与产品源码一起编）
#     → 跑 driver，全量 stdout 落 evidence/media-library.log
#     → 末尾追加真实目录的一次一层抽样计时（标 informational=1，不进任何判据）
#
# 纪律：
#   ① 所有外部命令套 `perl -e 'alarm N; exec @ARGV'` —— 本机没有 timeout 命令。
#   ② 探针失败不中止脚本（不用 set -e）：失败原样写进日志，由人读日志判定。
#   ③ evidence 支持 PIC_EVIDENCE_DIR 重定向；绝不能写进别人的 evidence 目录。
#   ④ 编译失败也要落日志（`: > "$LOG"` + PROBE_COMPILE_RC=1）—— 空 evidence 会
#      让后续判据静默通过。
#
# ⚠️ SRC 清单是**手写**的（probe-lock.sh 记过真事故：给 HoldArbiter 加 holdStatus 后
#    漏列 State/HoldStatus.swift，编译失败且日志被清空）。新增/删除 State/ 或 Media/
#    下的文件时必须同步改这里。

set -u
export LC_ALL=C

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

EV="$ROOT/.planning/phases/04-media-library/evidence"
LOG="$EV/media-library.log"
TMP="$(mktemp -d)"
BIN="$TMP/media-tracer-driver"
OUT="$TMP/driver.out"
MEDIA_ROOT="$ROOT/.planning/spike/media-fixture"

alarm() { perl -e "alarm $1; exec @ARGV" "${@:2}"; }

cleanup() { rm -rf "$TMP"; return 0; }
trap cleanup EXIT INT TERM

mkdir -p "$EV"

# ① 建树（保证 driver 有输入；树里视频文件是真字节，见脚本头注）。
alarm 120 bash "$ROOT/scripts/make-media-fixture-tree.sh" > "$TMP/tree.log" 2>&1
TREE_RC=$?

MEDIA_VALUE=$(grep -oE '^MEDIA_TREE_MEDIA=(present|absent)$' "$TMP/tree.log" | head -1 | cut -d= -f2)
[ -n "$MEDIA_VALUE" ] || MEDIA_VALUE="absent"

# ② driver + 产品源码一起编 —— 证据跑的是产品代码，不是探针里重写一遍的逻辑。
SRC="Sources/PicCore/Media/VideoItem.swift \
     Sources/PicCore/Media/VideoAssetProbe.swift \
     Sources/PicCore/Media/MediaLibrary.swift \
     Sources/PicCore/State/PlaybackDecision.swift \
     Sources/PicCore/State/HoldReason.swift \
     Sources/PicCore/State/HoldStatus.swift \
     Sources/PicCore/State/HoldArbiter.swift \
     Sources/PicCore/Playback/PlayerController.swift \
     Sources/PicCore/Render/WallpaperWindow.swift \
     Sources/PicCore/Render/WallpaperWindowController.swift \
     .planning/spike/MediaLibraryDriver.swift"

if ! alarm 180 swiftc -parse-as-library -swift-version 5 -target arm64-apple-macosx15.0 -o "$BIN" $SRC > "$TMP/build.log" 2>&1; then
  grep -E 'error:' "$TMP/build.log" | head -5 >&2
  # 编译失败也要落日志：空文件会让后续判据静默通过，掩盖失败。
  : > "$LOG"
  echo "PROBE_COMPILE_RC=1" >> "$LOG"
  exit 1
fi

# ③ 跑 driver。第二个参数是 MEDIA 值，决定真探针还是假探针。
alarm 60 "$BIN" "$MEDIA_ROOT" "$MEDIA_VALUE" > "$OUT" 2>&1
DRIVER_RC=$?
echo "PROBE_DRIVER_RC=$DRIVER_RC tree_rc=$TREE_RC" >> "$OUT"

cp "$OUT" "$LOG"

LINES=$(wc -l < "$LOG" | tr -d ' ')
echo "PROBE_LOG_LINES=$LINES" >> "$LOG"

# ④ 真实目录的一次一层抽样计时：只做非递归的一层计数 + 计时，打一行
#    informational=1。这一行不带任何判据。真实目录的递归计时**不做**（那正是要防的
#    慢操作）。
REALDIR="$HOME/Movies/视频壁纸"
ENTRIES=0
SECONDS_T=0
if [ -d "$REALDIR" ]; then
  T0=$(date +%s)
  ENTRIES=$(ls -1 "$REALDIR" 2>/dev/null | wc -l | tr -d ' ')
  T1=$(date +%s)
  SECONDS_T=$((T1 - T0))
fi
echo "MEDIA_REALDIR_SAMPLE informational=1 entries=$ENTRIES seconds=$SECONDS_T.0 recursion=disabled reason=D-22" >> "$LOG"

printf 'PROBE_OK rc=%s media=%s log=%s\n' "$DRIVER_RC" "$MEDIA_VALUE" "$LOG" >&2
exit 0