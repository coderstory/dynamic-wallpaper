#!/usr/bin/env bash
# probe-display.sh —— Plan 03-03 T2 的熄屏 / 睡眠信号证据采集。一条命令，无子命令：
#
#   bash scripts/probe-display.sh
#     → 编译 throwaway driver（与产品源码一起编）
#     → 跑 4 秒，只观察不制造事件
#     → 全量 stdout 落 evidence/display-sleep-signals.log，末尾追加汇总行
#
# 三条纪律（照 scripts/probe-lock.sh 已跑通的那三条）：
#   ① 所有外部命令套 `perl -e 'alarm N; exec @ARGV'` —— 本机没有 timeout 命令，
#      权限弹窗或异常输入会挂死采集（Phase 1 已踩过）。
#   ② `export LC_ALL=C` —— W-2026-10-03-13：UTF-8 locale 下脚本输出会按字节偏移丢 2 字节，
#      之后任何 grep 都会中止整份文件，判据假红。
#   ③ 探针失败不中止脚本（不用 set -e）：失败原样写进日志，由人读日志判定。
#
# ⚠️ 本脚本**不复用** scripts/run-probe.sh —— 那归 03-05（装配层）。本 plan 与 03-02 / 03-04
#    在 wave 2 并行（W9），各自独占一个脚本文件，避免同文件写冲突。
#
# ⚠️ driver **一次合成通知都不投**：熄屏跃迁与睡眠跃迁在本会话观测不到，
#    就记 `unobservable` + 原因，不拿合成事件冒充（LockWatcherDriver 的 ①③）。

set -u
export LC_ALL=C

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# 证据落点可重定向：test.sh 传 PIC_EVIDENCE_DIR 指向临时目录，避免跑一次门禁
# 就把已入库的 Phase 3 证据覆盖掉。默认值与原行为逐字一致。
EV="${PIC_EVIDENCE_DIR:-$ROOT/.planning/phases/03-system-events/evidence}"
LOG="$EV/display-sleep-signals.log"
TMP="$(mktemp -d)"
BIN="$TMP/displaywatcher-driver"
OUT="$TMP/driver.out"

# driver + 产品源码一起编 —— 证据跑的是产品代码，不是探针里重写一遍的逻辑。
SRC="Sources/PicCore/System/DisplayWatcher.swift \
     .planning/spike/DisplayWatcherDriver.swift"

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

RECONFIG_LINE=$(grep -cE '^DISPLAY_RECONFIG_CALLBACKS_FIRED=' "$LOG")
LINES=$(wc -l < "$LOG" | tr -d ' ')

# 末尾两行汇总：命中该行的**行数** + 日志行数。
# 及：真实的回调次数写在上一行（DISPLAY_RECONFIG_CALLBACKS_FIRED=），两者是不同的两个数。
echo "DISPLAY_RECONFIG_FIRED_LINE_COUNT=$RECONFIG_LINE" >> "$LOG"
echo "DISPLAY_LOG_LINES=$LINES" >> "$LOG"

log "PROBE_OK rc=$DRIVER_RC reconfig_line=$RECONFIG_LINE log=$LOG"
exit 0
