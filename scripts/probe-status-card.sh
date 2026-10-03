#!/usr/bin/env bash
# probe-status-card.sh —— Plan 05-03 T2 的来源卡 / 运行状态卡 tracer 证据采集。
#
#   bash scripts/probe-status-card.sh
#     → 空临时目录当 source（PIC_SOURCE_FOLDER，不碰真实素材目录，D-22）
#     → .build/debug/Pic --open-settings --quit-after 6，stderr 与 PIC_EVIDENCE_FILE 双落
#     → 断言 PIC_LIBRARY_STATE / PIC_SETTINGS_WINDOW / PIC_FFMPEG 三类行
#     → 锁屏活体观察（SC-5 ③）按 BLOCKED 纪律记账，不阻塞
#
# 纪律照 probe-settings.sh：alarm 包装（本机无 timeout）、LC_ALL=C、不用 set -e、
# mktemp + trap cleanup。
#
# ⚠️ 空态文案的**渲染**不在本探针里 —— 那要 XCUITest（05-04）。本探针只证数据链：
#    库状态行、窗口几何行、ffmpeg 可用性行。零 ffmpeg 执行：ffmpeg 行来自
#    PATH 可执行位判定，本脚本也不调用 ffmpeg 本身。
set -u
export LC_ALL=C

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

EV="$ROOT/.planning/phases/05-settings/evidence"
LOG="$EV/status-card.log"
TMP="$(mktemp -d)"

alarm() { perl -e "alarm $1; exec @ARGV" "${@:2}"; }

cleanup() { rm -rf "$TMP"; return 0; }
trap cleanup EXIT INT TERM

mkdir -p "$EV"
: > "$LOG"

# 1. 编译
if ! alarm 300 swift build -c debug --package-path . > "$TMP/build.log" 2>&1; then
  echo "PROBE_BUILD_RC=1" >> "$LOG"
  grep -E 'error:' "$TMP/build.log" | head -5 >> "$LOG"
  exit 1
fi

# 2. 两轮 source：真空目录（→ no_playable_videos）+ 含两个 mp4 符号链接的目录。
#    符号链接指 fixtures/；语料不存在也照跑 —— 本轮的结构判据不依赖语料。
SRC_EMPTY="$TMP/source-empty"
SRC_LINKS="$TMP/source-links"
mkdir -p "$SRC_EMPTY" "$SRC_LINKS"
for name in clip-a.mp4 clip-b.mp4; do
  ln -s "$ROOT/fixtures/$name" "$SRC_LINKS/$name" 2>/dev/null
done

EVFILE="$TMP/evidence.log"
: > "$EVFILE"

run_round() { # $1=source 目录  $2=输出前缀
  alarm 60 env PIC_SOURCE_FOLDER="$1" PIC_EVIDENCE_FILE="$EVFILE" \
    ".build/debug/Pic" --open-settings --quit-after 6 > "$2.out" 2> "$2.err"
  return $?
}

run_round "$SRC_EMPTY" "$TMP/empty"
run_round "$SRC_LINKS" "$TMP/links"
# stderr 是唯一落 $LOG 的原始流（emit 全走 stderr，D-17：同一行不落两遍）。
# 两轮都进同一份日志 —— 两轮的 PIC_* 行可区分（库状态不同，ffmpeg/几何行各两遍）。
cat "$TMP/empty.err" "$TMP/links.err" > "$LOG"

PASS=1
note() { printf '%s\n' "$1" >> "$LOG"; }

# 3. 断言（每条一行、一个数一次，D-17）
if grep -q 'PIC_LIBRARY_STATE=no_playable_videos' "$EVFILE"; then
  note "LIB_STATE_EMPTY=ok"
else
  note "LIB_STATE_EMPTY=missing"
  PASS=0
fi

if grep -q 'PIC_SETTINGS_WINDOW width=780 minWidth=680' "$EVFILE"; then
  note "WINDOW_GEOMETRY=ok"
else
  note "WINDOW_GEOMETRY=missing"
  PASS=0
fi

# ffmpeg 行：available 与 label 必须自洽（1 ⇔ 可用）。本机有无 ffmpeg 都绿。
FF_AVAIL=$(grep -oE 'PIC_FFMPEG available=[01]' "$EVFILE" | head -1 | sed 's/.*available=//')
FF_LINE_N=$(grep -c 'PIC_FFMPEG available=' "$EVFILE")
if [ -n "$FF_AVAIL" ]; then
  if grep -qF 'label=可用' "$EVFILE" && [ "$FF_AVAIL" = "1" ]; then
    note "FFMPEG_SELF_CONSISTENT=ok available=1 label=可用"
  elif grep -qF 'label=未安装' "$EVFILE" && [ "$FF_AVAIL" = "0" ]; then
    note "FFMPEG_SELF_CONSISTENT=ok available=0 label=未安装"
  else
    note "FFMPEG_SELF_CONSISTENT=inconsistent available=${FF_AVAIL:-none}"
    PASS=0
  fi
else
  note "FFMPEG_SELF_CONSISTENT=missing"
  PASS=0
fi
# informational（不作硬门）：干净 clone 上 PATH 里可能没有 ffmpeg。
note "FFMPEG_LOCAL_BASELINE=$(command -v ffmpeg >/dev/null 2>&1 && echo present || echo absent)"
note "FFMPEG_EMIT_LINES=$FF_LINE_N"

# 4. 第二轮（双片目录）只作信息：fixtures 未生成时扫到 0 属预期。
LINK_TOK=$(grep -c 'PIC_LIBRARY_STATE=playing' "$EVFILE" || true)
note "LIB_STATE_WITH_LINKS=$([ "${LINK_TOK:-0}" -ge 1 ] && echo playing || echo not_playing)"

# 5. 活体观察（SC-5 ③）：锁屏态开设置窗看「屏幕已锁定」副标签。
LOCK_RAW=$(alarm 90 swift -e '
import CoreGraphics
import Foundation
let s = CGSessionCopyCurrentDictionary() as? [String: Any]
let locked = ((s?["CGSSessionScreenIsLocked"] as? NSNumber)?.intValue ?? 0) != 0
FileHandle.standardOutput.write(Data("LOCKED=\(locked ? 1 : 0)\n".utf8))
' 2>/dev/null)
LOCKED=$(printf '%s' "$LOCK_RAW" | sed -n 's/^LOCKED=\([01]\)$/\1/p')
note "LOCK_STATE_AT_PROBE=${LOCKED:-unknown}"
if [ "${LOCKED:-0}" = "1" ]; then
  note "LIVE_LOCK_OBSERVATION=blocked reason=screen_locked"
  note "LIVE_LOCK_UNLOCK_CONDITION=解锁会话里开设置窗目视，或 05-04 用 XCUITest 注入合成锁事件复跑"
  # blocked 分支先查条目在册 —— 静默跳过的缺陷比缺陷本身更坏（照 W-2026-10-03-25）。
  if ! grep -q 'W-2026-10-03-29' .planning/WINDOWS.md; then
    note "LIVE_LOCK_W_ENTRY_MISSING"
    PASS=0
  fi
else
  # 解锁会话：数据链已由本脚本证明，肉眼目视仍需真人/05-04，诚实记 attempted。
  note "LIVE_LOCK_OBSERVATION=attempted"
  note "LIVE_LOCK_NOTE=解锁会话下「屏幕已锁定」副标签的活体目视未由自动化完成，见 W-2026-10-03-29"
fi

note "STATUS_CARD_PROBE=$([ "$PASS" -eq 1 ] && echo PASS || echo FAIL)"
if [ "$PASS" -eq 1 ]; then
  echo "STATUS_CARD_PROBE_OK log=$LOG" >&2
  exit 0
fi
echo "STATUS_CARD_PROBE_FAILED —— 见 $LOG" >&2
exit 1
