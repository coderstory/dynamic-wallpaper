#!/usr/bin/env bash
# probe-rotation-wiring.sh —— Plan 04-05 T3 的轮换装配链证据采集。一条命令，无子命令：
#
#   bash scripts/probe-rotation-wiring.sh
#     → 编译 throwaway driver（与产品源码一起编）
#     → 跑 driver，全量 stdout 落 Phase 4 自己的 evidence/rotation-wiring.log
#
# 纪律照 scripts/probe-lock.sh 的全部形状：
#   ① 所有外部命令套 `perl -e 'alarm N; exec @ARGV'` —— 本机没有 timeout 命令；
#   ② 探针失败不中止脚本（不用 set -e）：失败原样写进日志，由人读日志判定；
#   ③ 证据落点可重定向：PIC_EVIDENCE_DIR 指向临时目录时不覆盖已入库证据
#      （04-06 的 test.sh 段靠它把产物写到临时目录）。
#
# ⚠️ 这份 SRC 清单是**手写**的，`swift build` 不会替我们更新它（probe-lock.sh
#    头注记过漏列文件导致空日志的真事故）。RotationController 依赖 `PlayMode`
#    （State/SettingsStore.swift）—— 计划的清单没列它，漏列会编译红；新增/删除
#    Media/ Playback/ State/ 下的文件时必须同步改这里。

set -u
export LC_ALL=C

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

EV="${PIC_EVIDENCE_DIR:-$ROOT/.planning/phases/04-media-library/evidence}"
LOG="$EV/rotation-wiring.log"
TMP="$(mktemp -d)"
BIN="$TMP/rotation-wiring-driver"
OUT="$TMP/driver.out"

SRC="Sources/PicCore/Media/VideoItem.swift \
     Sources/PicCore/State/SettingsStore.swift \
     Sources/PicCore/Playback/RotationController.swift \
     Sources/PicCore/Playback/SystemRotationScheduler.swift \
     Sources/PicCore/Playback/PlaybackRouter.swift \
     .planning/spike/RotationWiringDriver.swift"

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

LINES=$(wc -l < "$LOG" | tr -d ' ')
echo "ROTATION_LOG_LINES=$LINES" >> "$LOG"

log "PROBE_OK rc=$DRIVER_RC log=$LOG"
exit 0
