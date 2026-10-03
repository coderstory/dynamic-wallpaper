#!/usr/bin/env bash
# probe-fullscreen.sh —— Plan 03-02 T2 的全屏信号证据采集。一条命令，无子命令：
#
#   bash scripts/probe-fullscreen.sh
#     → 编译 throwaway driver（与产品源码一起编）
#     → 跑一次（瞬时，无等待 —— 本会话没有跃迁可等）
#     → 全量 stdout 落 evidence/fullscreen-signals.log，末尾追加两行汇总
#
# 三条纪律（照 scripts/probe-lock.sh 已跑通的那三条）：
#   ① 所有外部命令套 `perl -e 'alarm N; exec @ARGV'` —— 本机没有 timeout 命令，
#      权限弹窗或异常输入会挂死采集（Phase 1 已踩过）。
#   ② `export LC_ALL=C` —— W-2026-10-03-13：UTF-8 locale 下脚本输出会按字节偏移丢 2 字节，
#      之后任何 grep 都会中止整份文件，判据假红。
#   ③ 探针失败不中止脚本（不用 set -e）：失败原样写进日志，由人读日志判定。

set -u
export LC_ALL=C

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# 证据落点可重定向：test.sh 传 PIC_EVIDENCE_DIR 指向临时目录，避免跑一次门禁
# 就把已入库的 Phase 3 证据覆盖掉。默认值与原行为逐字一致。
EV="${PIC_EVIDENCE_DIR:-$ROOT/.planning/phases/03-system-events/evidence}"
LOG="$EV/fullscreen-signals.log"
TMP="$(mktemp -d)"
BIN="$TMP/fullscreendriver"
OUT="$TMP/driver.out"

# driver + 产品源码一起编 —— 证据跑的是产品代码，不是探针里重写一遍的逻辑。
SRC="Sources/PicCore/System/FullscreenGeometry.swift \
     Sources/PicCore/System/FullscreenDetector.swift \
     .planning/spike/FullscreenDetectorDriver.swift"

alarm() { perl -e "alarm $1; exec @ARGV" "${@:2}"; }

cleanup() { rm -rf "$TMP"; return 0; }
trap cleanup EXIT INT TERM

mkdir -p "$EV"

log() { printf '%s\n' "$*" >&2; }

if ! alarm 180 swiftc -parse-as-library -target arm64-apple-macosx15.0 -o "$BIN" $SRC > "$TMP/build.log" 2>&1; then
  log "PROBE_COMPILE_FAILED rc=1"
  grep -E 'error:' "$TMP/build.log" | head -5 >&2
  # 编译失败也要落日志：空文件会让后续判据静默通过，掩盖失败。
  : > "$LOG"
  echo "PROBE_COMPILE_RC=1" >> "$LOG"
  exit 1
fi

alarm 60 "$BIN" > "$OUT" 2>&1
DRIVER_RC=$?
echo "PROBE_DRIVER_RC=$DRIVER_RC" >> "$OUT"

cp "$OUT" "$LOG"

DICT_KEYS=$(grep -cE '^WINDOW_DICT_KEY=' "$LOG")
STYLE_KEYS=$(grep -iE '^WINDOW_DICT_KEY=.*(tyle|ullscreen)' "$LOG" | wc -l | tr -d ' ')
LINES=$(wc -l < "$LOG" | tr -d ' ')

# 末尾两行汇总：字典键总数 + 含 style/fullscreen 字样的键数。
# STYLE_KEYS 必须为 0 —— 非 0 意味着「公开 API 读不到别的进程的 styleMask」这条结构结论是错的。
echo "WINDOW_DICT_KEY_COUNT=$DICT_KEYS" >> "$LOG"
echo "WINDOW_DICT_STYLE_KEY_COUNT=$STYLE_KEYS" >> "$LOG"
echo "FULLSCREEN_LOG_LINES=$LINES" >> "$LOG"

log "PROBE_OK rc=$DRIVER_RC dict_keys=$DICT_KEYS style_keys=$STYLE_KEYS log=$LOG"
exit 0