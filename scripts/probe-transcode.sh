#!/usr/bin/env bash
# probe-transcode.sh —— 执行 tracer 活体证据采集。一条命令，无参数：
#
#   bash scripts/probe-transcode.sh
#     → 编译 throwaway driver（与产品源码一起编 —— 证据跑的是产品代码）
#     → 跑 driver（FakeRunner，零真实转码调用），stdout 落 evidence/transcode-tracer.log
#
# 纪律：
#   ① 所有外部命令套 perl -e 'alarm N; exec @ARGV' —— 本机没有 timeout 命令。
#   ② 探针失败不中止脚本（不用 set -e）：失败原样写进日志，由人读日志判定。
#   ③ evidence 支持 PIC_EVIDENCE_DIR 重定向，不覆盖入库证据。
#   ④ 编译失败也要落日志（空 evidence 会让后续判据静默通过）。
#
# ⚠️ SRC 清单是**手写**的（probe-lock.sh 头注的真事故：漏列一个文件 → 编译失败
#    且日志被清空）。Transcode/ 或 Media/ 下新增文件必须同步改这里。
#    MediaLibrary.swift 是 ConvertedLibrary / TranscodeOutputNaming /
#    TranscodeCandidateFilter 引用 excludedDirectoryName / allowedExtensions 的宿主。

set -u
export LC_ALL=C

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

EV="${PIC_EVIDENCE_DIR:-$ROOT/.planning/phases/06-transcode/evidence}"
LOG="$EV/transcode-tracer.log"
TMP="$(mktemp -d)"
BIN="$TMP/transcode-tracer-driver"
OUT="$TMP/driver.out"

alarm() { perl -e "alarm $1; exec @ARGV" "${@:2}"; }

cleanup() { rm -rf "$TMP"; return 0; }
trap cleanup EXIT INT TERM

mkdir -p "$EV"

SRC="Sources/PicCore/Media/VideoItem.swift \
     Sources/PicCore/Media/VideoAssetProbe.swift \
     Sources/PicCore/Media/MediaLibrary.swift \
     Sources/PicCore/Transcode/TranscodeCommand.swift \
     Sources/PicCore/Transcode/TranscodeOutputNaming.swift \
     Sources/PicCore/Transcode/TranscodeCandidateFilter.swift \
     Sources/PicCore/Transcode/ConvertedLibrary.swift \
     Sources/PicCore/Transcode/ExternalToolLocator.swift \
     Sources/PicCore/Transcode/ProgressParser.swift \
     Sources/PicCore/Transcode/TranscodeQueue.swift \
     Sources/PicCore/Transcode/ProcessTranscodeRunner.swift \
     .planning/spike/TranscodeTracerDriver.swift"

if ! alarm 180 swiftc -parse-as-library -swift-version 5 -target arm64-apple-macosx15.0 -o "$BIN" $SRC > "$TMP/build.log" 2>&1; then
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
echo "PROBE_LOG_LINES=$LINES" >> "$LOG"

printf 'PROBE_OK rc=%s log=%s\n' "$DRIVER_RC" "$LOG" >&2
exit 0
