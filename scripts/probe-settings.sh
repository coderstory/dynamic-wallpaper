#!/usr/bin/env bash
# 设置窗 tracer 证据采集。一条命令：swift build -c debug → 空临时目录当 source（PIC_SOURCE_FOLDER 指过去，不碰真实素材目录）
# → .build/debug/Pic --open-settings --quit-after 10，stderr 与 PIC_EVIDENCE_FILE 证据文件双落 $LOG → 断言并回写 PIC_SETTINGS_BOOT / PIC_SETTINGS_WINDOW / PROCESS_EXITED。
#
# 纪律：alarm 包装（本机无 timeout）、LC_ALL=C、不用 set -e、mktemp + trap cleanup。
#
# seeding **只能用进程名域，不要改回 argument domain**：`UserDefaults.object(forKey:)` 对 argument domain
#    返回 NSTaggedPointerString，`as? Float` / `as? Bool` 均转不成（SettingsStore 的读法会拿到 seed 默认值）。
#    用 `defaults write Pic rate -float 1.5`（.build/debug/Pic 的进程名即 Pic，回 NSNumber、类型转换成立、
#    优先级与 UserDefaults 一致）。跑前跑后各 defaults delete Pic 一次清场，不碰 com.local.pic（打包域）。
set -u
export LC_ALL=C

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

EV="$ROOT/.planning/phases/05-settings/evidence"
LOG="$EV/settings-tracer.log"
TMP="$(mktemp -d)"

alarm() { perl -e "alarm $1; exec @ARGV" "${@:2}"; }

cleanup() {
  rm -rf "$TMP"
  defaults delete Pic 2>/dev/null
  return 0
}
trap cleanup EXIT INT TERM

mkdir -p "$EV"
# 每次全量重采（入库的就是本脚本的采集读数；下游门禁只读不写）。
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

# 3. seeding（进程名域，见头注释）
defaults delete Pic 2>/dev/null
defaults write Pic rate -float 1.5
defaults write Pic volume -float 0.5
defaults write Pic muted -bool YES

EVFILE="$TMP/evidence.log"
: > "$EVFILE"

# 4. 起产品：10 秒自退（--quit-after），证据桥与 stderr 双落
alarm 60 env PIC_SOURCE_FOLDER="$SRC_DIR" PIC_EVIDENCE_FILE="$EVFILE" \
  ".build/debug/Pic" --open-settings --quit-after 10 > "$TMP/app.out" 2> "$TMP/app.err"
APP_RC=$?

# stderr 是唯一落 $LOG 的原始流（同一行落两遍会让 TICK 等计数读起来翻倍）；
# 证据文件单独断言 —— 它证明的是 PIC_EVIDENCE_FILE 桥本身可用（XCUITest 依赖这条桥），不是第二个数据源。
cat "$TMP/app.err" > "$LOG"

# 5. 断言并回写（每条一行、一个数一次）
PASS=1
if grep -q 'PIC_SETTINGS_BOOT rate=1.5 volume=0.5 muted=1' "$LOG"; then
  echo "PROBE_BOOT=ok" >> "$LOG"
else
  echo "PROBE_BOOT=missing" >> "$LOG"
  PASS=0
fi
if grep -q 'PIC_SETTINGS_WINDOW width=780 minWidth=680' "$LOG"; then
  echo "PROBE_WINDOW=ok" >> "$LOG"
else
  echo "PROBE_WINDOW=missing" >> "$LOG"
  PASS=0
fi
if grep -q 'PIC_SETTINGS_WINDOW width=780 minWidth=680' "$EVFILE"; then
  echo "PROBE_MIRROR=ok" >> "$LOG"
else
  echo "PROBE_MIRROR=missing" >> "$LOG"
  PASS=0
fi
if [ "$APP_RC" -eq 0 ] && grep -q 'PIC_TERMINATED' "$LOG"; then
  echo "PROCESS_EXITED=clean" >> "$LOG"
else
  echo "PROCESS_EXITED=unclean rc=$APP_RC" >> "$LOG"
  PASS=0
fi

if [ "$PASS" -eq 1 ]; then
  echo "SETTINGS_TRACER_PROBE_OK" >> "$LOG"
  echo "PROBE_OK log=$LOG" >&2
  exit 0
fi
echo "PROBE_FAILED —— 见 $LOG" >&2
exit 1
