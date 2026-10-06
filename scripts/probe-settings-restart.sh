#!/usr/bin/env bash
# 重启读回探针。一条命令：swift build -c debug → 空临时目录当 source（PIC_SOURCE_FOLDER 指过去，不碰真实素材目录）
# → 三轮起产品，每轮断言 PIC_SETTINGS_BOOT 一行：
#     ① 六值 seeded   → ② 同参数重跑，逐字一致（读回不依赖上一进程的内存）→ ③ 无 seeding → 回 seed 默认值（BOOT 读的是 store 真值）
# → 证据落 evidence/settings-restart.log 与 evidence/settings-apply.log。
#
# 纪律：alarm 包装（本机无 timeout）、LC_ALL=C、不用 set -e、mktemp + trap cleanup。
#
# seeding 机制见 probe-settings.sh 头注（不要改回 argument domain）。由此产生的第三个后果：
#    进程名域是**持久**的，所以第 ③ 轮必须先 `defaults delete Pic` 清场，否则读到的是上一轮留下的值。
#    跑前跑后各清一次，不碰 com.local.pic（打包域）。
set -u
export LC_ALL=C

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

EV="$ROOT/.planning/phases/05-settings/evidence"
LOG="$EV/settings-restart.log"
ALOG="$EV/settings-apply.log"
TMP="$(mktemp -d)"

alarm() { perl -e "alarm $1; exec @ARGV" "${@:2}"; }

cleanup() {
  rm -rf "$TMP"
  defaults delete Pic 2>/dev/null
  return 0
}
trap cleanup EXIT INT TERM

mkdir -p "$EV"
: > "$LOG"

# 1. 编译
if ! alarm 300 swift build -c debug --package-path . > "$TMP/build.log" 2>&1; then
  echo "PROBE_BUILD_RC=1" >> "$LOG"
  grep -E 'error:' "$TMP/build.log" | head -5 >> "$LOG"
  exit 1
fi

# 2. 空临时目录当 source（不碰真实素材目录）
SRC_DIR="$TMP/source-empty"
mkdir -p "$SRC_DIR"

SEED_LINE='rate=1.75 volume=0.35 muted=1 playMode=shuffle rotationInterval=600 pauseOnBattery=1'
DEF_LINE='rate=1.0 volume=1.0 muted=0 playMode=loopSingle rotationInterval=300 pauseOnBattery=0'

seed_six() {
  defaults delete Pic 2>/dev/null
  defaults write Pic rate -float 1.75
  defaults write Pic volume -float 0.35
  defaults write Pic muted -bool YES
  defaults write Pic playMode -string shuffle
  defaults write Pic rotationInterval -float 600
  defaults write Pic pauseOnBattery -bool YES
}

run_round() {   # $1=轮次标签 → stderr 落 $TMP/$1.err
  alarm 60 env PIC_SOURCE_FOLDER="$SRC_DIR" PIC_EVIDENCE_FILE="$TMP/$1.ev" \
    ".build/debug/Pic" --open-settings --quit-after 6 > "$TMP/$1.out" 2> "$TMP/$1.err"
  echo "round=$1 app_rc=$?" >> "$LOG"
}

boot_line() { grep -m1 'PIC_SETTINGS_BOOT' "$TMP/$1.err"; }

PASS=1

# ---- 第 ① 轮：六值 seeded ----
seed_six
run_round r1
echo "SEED_EXPECT=$SEED_LINE" >> "$LOG"
B1=$(boot_line r1)
echo "$B1" >> "$LOG"
if [ -n "$B1" ] && printf '%s' "$B1" | grep -q "PIC_SETTINGS_BOOT $SEED_LINE"; then
  echo "ROUND1_SEEDED=ok" >> "$LOG"
else
  echo "ROUND1_SEEDED=missing" >> "$LOG"
  PASS=0
fi

# 第 ① 轮的运行期 apply 行：由 `wiring()` 里 powerWatcher.start 的同步回调 → recordPowerState → applyBatteryPolicy 驱动，
# 每轮恰好一行，value 随 seeding 的开关变（0|1）。其余五条（rate / volume / muted / playMode / rotationInterval）由设置窗控件事件驱动，
# 没有 UI 交互就不触发，值断言在 SettingsApplierTests。
APPLY1=$(grep -m1 'PIC_SETTINGS_APPLY key=pauseOnBattery' "$TMP/r1.ev")
echo "APPLY_EXPECT=key=pauseOnBattery value=1 applied=1 onBattery=" >> "$LOG"
echo "$APPLY1" >> "$LOG"
if [ -n "$APPLY1" ] && printf '%s' "$APPLY1" | grep -qE 'key=pauseOnBattery value=1 applied=1 onBattery=[01]$'; then
  echo "ROUND1_APPLY_BATTERY=ok" >> "$LOG"
else
  echo "ROUND1_APPLY_BATTERY=missing" >> "$LOG"
  PASS=0
fi

# ---- 第 ② 轮：同参数重跑，读回必须逐字一致（不依赖上一进程的内存）----
seed_six
run_round r2
B2=$(boot_line r2)
echo "$B2" >> "$LOG"
if [ -n "$B2" ] && [ "$B1" = "$B2" ]; then
  echo "ROUND2_IDEMPOTENT=ok" >> "$LOG"
else
  echo "ROUND2_IDEMPOTENT=missing" >> "$LOG"
  PASS=0
fi

# ---- 第 ③ 轮：清场后无 seeding → 回 seed 默认值（证明 BOOT 读的是 store 真值）----
defaults delete Pic 2>/dev/null
run_round r3
B3=$(boot_line r3)
echo "DEFAULT_EXPECT=$DEF_LINE" >> "$LOG"
echo "$B3" >> "$LOG"
if [ -n "$B3" ] && printf '%s' "$B3" | grep -q "PIC_SETTINGS_BOOT $DEF_LINE"; then
  echo "ROUND3_DEFAULTS=ok" >> "$LOG"
else
  echo "ROUND3_DEFAULTS=missing" >> "$LOG"
  PASS=0
fi

# 每轮恰好一行：出现第二行就说明 `.battery` 又多了一个 set 落点（竞态双写）。三轮跑完后统一数 ——
# 这一段放在第 ① 轮后面会读到还没生成的 r2/r3 证据文件。
APPLY_N=$(grep -c 'PIC_SETTINGS_APPLY key=pauseOnBattery' "$TMP/r1.ev" "$TMP/r2.ev" "$TMP/r3.ev" | awk -F: '{s+=$2} END{print s+0}')
echo "APPLY_BATTERY_LINES_3ROUNDS=$APPLY_N" >> "$LOG"
if [ "$APPLY_N" -eq 3 ]; then
  echo "APPLY_BATTERY_SINGLE_SITE=ok" >> "$LOG"
else
  echo "APPLY_BATTERY_SINGLE_SITE=missing" >> "$LOG"
  PASS=0
fi

if [ "$PASS" -eq 1 ]; then
  echo "SETTINGS_RESTART_PROBE_OK" >> "$LOG"
fi

# ---- settings-apply.log：apply 层的记账 ----
# 「当场生效」的**值**断言在单测层（SettingsApplierTests 四条），不在探针层。运行期能 grep 到的只有电池那一条：
# 它由 `wiring()` 的同步回调驱动，开窗即有；另五条由设置窗控件事件驱动，没有 UI 交互就不触发 —— 如实记 0，不拿 emit 落点数冒充运行期证据。
APPLIER=Sources/PicCore/App/SettingsApplier.swift
SITES=$(grep -v -e '^[[:space:]]*//' -e '^[[:space:]]*/\*' -e '^[[:space:]]*\*' -e '^[[:space:]]*\*/' "$APPLIER" | grep -c -F 'PIC_SETTINGS_APPLY')
RUNTIME=$(cat "$TMP"/r1.ev "$TMP"/r2.ev "$TMP"/r3.ev 2>/dev/null | grep -c 'PIC_SETTINGS_APPLY')
{
  echo "=== probe-settings-restart.sh · apply 层记账 ==="
  cat "$TMP/r1.err"
  echo "APPLY_EMIT_SITES=$SITES"
  echo "APPLY_RUNTIME_LINES=$RUNTIME"
  echo "APPLY_RUNTIME_NOTE=电池行由 wiring() 同步回调产出（开窗即有，每轮恰好一行）；其余五条由设置窗控件事件驱动，无 UI 交互即不触发，值断言在 SettingsApplierTests，交互半边未自动验证（W-2026-10-03-28）"
} > "$ALOG"

if [ "$PASS" -eq 1 ]; then
  echo "PROBE_OK log=$LOG apply=$ALOG" >&2
  exit 0
fi
echo "PROBE_FAILED —— 见 $LOG" >&2
exit 1