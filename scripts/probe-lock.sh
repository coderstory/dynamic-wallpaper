#!/usr/bin/env bash
# probe-lock.sh —— Plan 03-01 T1 的锁屏接线证据采集。一条命令，无子命令：
#
#   bash scripts/probe-lock.sh
#     → 编译 throwaway driver（与产品源码一起编）
#     → 跑 6 秒，投 2 次合成通知
#     → 全量 stdout 落 evidence/lock-wiring.log，末尾追加两行汇总
#
# 两条纪律（照 scripts/run-probe.sh 已跑通的那两条）：
#   ① 所有外部命令套 `perl -e 'alarm N; exec @ARGV'` —— 本机没有 timeout 命令，
#      权限弹窗或异常输入会挂死采集（Phase 1 已踩过）。
#   ② 探针失败不中止脚本（不用 set -e）：失败原样写进日志，由人读日志判定。
#
# ⚠️ 合成通知一律用 `com.local.pic.tests.lock.` 前缀，绝不投 `com.apple.screenIsLocked`
#    —— 那个名字由别的进程投递，投它会让同机的其它壁纸 app 一起暂停。

set -u
export LC_ALL=C

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

EV="$ROOT/.planning/phases/03-system-events/evidence"
LOG="$EV/lock-wiring.log"
TMP="$(mktemp -d)"
BIN="$TMP/lockwatcher-driver"
OUT="$TMP/driver.out"

# driver + 产品源码一起编 —— 证据跑的是产品代码，不是探针里重写一遍的逻辑。
# ⚠️ 这份清单是**手写**的，`swift build` 不会替我们更新它。03-05 给 `HoldArbiter`
# 加了 `holdStatus`（它返回 `HoldStatus`）之后，本脚本因漏列 `State/HoldStatus.swift`
# 而编译失败 —— `PROBE_COMPILE_RC=1` 且日志被清空。**新增/删除 State/ 下的文件时，
# 必须同步改这里**，否则 03-01 的证据采集会静默变成空文件（判据会假绿）。
SRC="Sources/PicCore/State/HoldReason.swift \
     Sources/PicCore/State/PlaybackDecision.swift \
     Sources/PicCore/State/HoldStatus.swift \
     Sources/PicCore/State/HoldArbiter.swift \
     Sources/PicCore/System/LockWatcher.swift \
     .planning/spike/LockWatcherDriver.swift"

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

SIGNALS=$(grep -cE '^LOCK_SIGNAL_COUNT=' "$LOG")
SIGNALS_ON_THE_WIRE=$(grep -cE '^LOCK_SIGNAL_INJECTED ' "$LOG")
LINES=$(wc -l < "$LOG" | tr -d ' ')

# 末尾两行汇总：合成通知投递次数 + 日志行数。
echo "LOCK_SIGNAL_INJECTED_COUNT=$SIGNALS_ON_THE_WIRE" >> "$LOG"
echo "LOCK_LOG_LINES=$LINES" >> "$LOG"

log "PROBE_OK rc=$DRIVER_RC signals_injected=$SIGNALS_ON_THE_WIRE log=$LOG"
exit 0