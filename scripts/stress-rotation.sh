#!/usr/bin/env bash
# stress-rotation.sh —— SC4 前半：50 次换片、内存回基线 ±10%。
#
#   bash scripts/stress-rotation.sh
#     → 压测前备份 rotationInterval / playMode 两个键
#     → 1 秒自动轮换跑 90 秒（warmup 15 + 采样窗 75）
#     → 读退出快照 PIC_ROT_ADVANCES_TOTAL 与两次 RSS，算漂移
#     → 恢复两个键的原值 → 全部 STRESS_* 行落 evidence/stress-rotation.log
#
# 四条纪律：
#   ① 所有外部命令套 `perl -e 'alarm N; exec @ARGV'` —— 本机没有 timeout 命令。
#   ② **不用 set -e**：失败原样落日志由人读；清理无条件（trap 与断言同一条路径）。
#   ③ `set -u` + `export LC_ALL=C`。
#   ④ **零转码**：只播放 fixtures 里已有的 mp4，播放是 app 的日常行为。
#      转码二进制的名字一个都不许出现在本文件的非注释行里（禁令判据 grep 那个词）。
#
# ⚠️ 基线口径：RSS0 取自 **warmup 15 秒之后**，不是冷启动。冷启动那一段正在建窗口、
#    装解码器，比的是它等于在测「启动多贵」，不是「换片漏不漏」。

set -u
export LC_ALL=C

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

EV="$ROOT/.planning/phases/07-delivery/evidence"
LOG="$EV/stress-rotation.log"
TMP="$(mktemp -d)"
APP="$ROOT/build/Pic.app/Contents/MacOS/Pic"
DOMAIN="com.local.pic"
FIXTURES="$ROOT/fixtures"
WARMUP=15
WINDOW=75

APP_PID=""

alarm() { perl -e "alarm $1; exec @ARGV" "${@:2}"; }

# ---- 清理：无条件。失败路径也不许留活进程烤桌面。----
cleanup() {
  if [ -n "$APP_PID" ] && kill -0 "$APP_PID" 2>/dev/null; then
    kill "$APP_PID" 2>/dev/null || true
    sleep 1
    kill -9 "$APP_PID" 2>/dev/null || true
  fi
  APP_PID=""
  restore_defaults
  rm -rf "$TMP"
  return 0
}
trap cleanup EXIT INT TERM

mkdir -p "$EV"
: > "$LOG"

log() { printf '%s\n' "$*" >&2; }
emit_line() { printf '%s\n' "$*" >> "$LOG"; }

read_key() { alarm 10 defaults read "$DOMAIN" "$1" 2>/dev/null || echo "__ABSENT__"; }
OLD_RI=""
OLD_PM=""

restore_defaults() {
  [ -n "$OLD_RI" ] || return 0
  if [ "$OLD_RI" = "__ABSENT__" ]; then
    alarm 20 defaults delete "$DOMAIN" rotationInterval >/dev/null 2>&1 || true
  else
    alarm 20 defaults write "$DOMAIN" rotationInterval -float "$OLD_RI" >/dev/null 2>&1 || true
  fi
  if [ "$OLD_PM" = "__ABSENT__" ]; then
    alarm 20 defaults delete "$DOMAIN" playMode >/dev/null 2>&1 || true
  else
    alarm 20 defaults write "$DOMAIN" playMode -string "$OLD_PM" >/dev/null 2>&1 || true
  fi
  return 0
}

# ================= 1. 前置 =================
if [ ! -f "$FIXTURES/clip-a.mp4" ]; then
  log "stress: fixtures 缺失，先跑一次 scripts/make-fixtures.sh"
  alarm 600 bash scripts/make-fixtures.sh > "$TMP/fixtures.log" 2>&1 || true
fi
if [ ! -f "$FIXTURES/clip-a.mp4" ] || [ ! -x "$APP" ]; then
  emit_line "STRESS_BLOCKED reason=fixtures_missing"
  [ -x "$APP" ] || emit_line "STRESS_BLOCKED reason=app_missing"
  log "stress: 前置缺失（fixtures 或 build/Pic.app），BLOCKED 不算失败"
  exit 2
fi
emit_line "STRESS_FIXTURES=$FIXTURES"

# ================= 2. 备份两个键 =================
OLD_RI="$(read_key rotationInterval)"
OLD_PM="$(read_key playMode)"
emit_line "STRESS_BASELINE_RI=$OLD_RI"
emit_line "STRESS_BASELINE_PM=$OLD_PM"

# ================= 3. 写入压测参数 =================
# playMode 的 rawValue 取 loopList —— SettingsStore.PlayMode 的 case 名即 rawValue，
# 与 load 侧 `PlayMode(rawValue:)` 的解析拼法一致。
alarm 20 defaults write "$DOMAIN" rotationInterval -float 1 >/dev/null 2>&1 || true
alarm 20 defaults write "$DOMAIN" playMode -string loopList >/dev/null 2>&1 || true
emit_line "STRESS_ROTATION_INTERVAL=1"
emit_line "STRESS_PLAY_MODE=loopList"

# ================= 4. 起 app → warmup → 采样 =================
# SIGTERM 走不到 applicationWillTerminate（AppKit 不为 SIGTERM 装信号处理函数，
# 见 AppDelegate 的 --quit-after 注释），故用 --quit-after 让 app 走 terminateApp()
# → NSApp.terminate → applicationWillTerminate，退出快照才拿得到。
alarm 200 env PIC_SOURCE_FOLDER="$FIXTURES" "$APP" \
  --quit-after "$((WARMUP + WINDOW + 10))" > "$TMP/app.out" 2> "$TMP/app.err" &
LAUNCH_PID=$!

# ⚠️ `$!` 是**跑 alarm 函数的子 shell** 的 PID（comm=bash），不是 app 的。
#    拿它读 RSS 会读到那个壳进程的常数（实测 1.7MB，两次读数完全相同 → 漂移恒 0，
#    判据变成空判）。必须按 app 二进制路径反查真实 PID。
resolve_app_pid() {
  /usr/bin/pgrep -f "$APP" 2>/dev/null | head -1
}
sleep 3
APP_PID="$(resolve_app_pid)"
emit_line "STRESS_LAUNCH_SUBPID=$LAUNCH_PID"
emit_line "STRESS_APP_PID=${APP_PID:-none}"

sleep "$((WARMUP - 3))"
if ! kill -0 "$APP_PID" 2>/dev/null; then
  emit_line "STRESS_BLOCKED reason=app_exited_early"
  log "stress: app 在 warmup 内就退出了，看 $TMP/app.err"
  exit 1
fi

RSS0="$(alarm 10 ps -o rss= -p "$APP_PID" 2>/dev/null | tr -d ' ')"
emit_line "STRESS_RSS_START_KB=${RSS0:-0}"
# RSS 明显偏小 = 读的不是 app（多半又是壳进程）。这种读数会让漂移恒为 0，
# 判据变空判 —— 宁可报 blocked，也不拿一个假绿交差。app 稳态在 100MB 量级。
if [ "${RSS0:-0}" -lt 20000 ]; then
  emit_line "STRESS_BLOCKED reason=rss_reading_implausible value=${RSS0:-0}"
  log "stress: RSS 读数 ${RSS0:-0}KB 不像 app 进程（稳态约 100MB+），BLOCKED"
  exit 2
fi

sleep "$WINDOW"
RSS1="$(alarm 10 ps -o rss= -p "$APP_PID" 2>/dev/null | tr -d ' ')"
emit_line "STRESS_RSS_END_KB=${RSS1:-0}"

# 等 app 自己走完 --quit-after 的退出路径（terminateApp → applicationWillTerminate）
waited=0
while kill -0 "$APP_PID" 2>/dev/null && [ "$waited" -lt 25 ]; do
  sleep 1; waited=$((waited + 1))
done
kill "$APP_PID" 2>/dev/null || true
kill "$LAUNCH_PID" 2>/dev/null || true
APP_PID=""

# ================= 5. 读数 =================
ADVANCES="$(grep -oE '^PIC_ROT_ADVANCES_TOTAL=[0-9]+' "$TMP/app.err" 2>/dev/null | tail -1 | cut -d= -f2)"
emit_line "STRESS_ADVANCES=${ADVANCES:-0}"

if grep -qE '^PIC_TERMINATED ' "$TMP/app.err" 2>/dev/null; then
  emit_line "STRESS_TERMINATE_PATH=applicationWillTerminate"
else
  emit_line "STRESS_TERMINATE_PATH=absent"
fi

DRIFT="$(awk -v a="${RSS1:-0}" -v b="${RSS0:-0}" 'BEGIN{ if (b>0) printf "%.1f", (a-b)*100.0/b; else print "0.0" }')"
emit_line "STRESS_RSS_DRIFT_PCT=$DRIFT"

# ================= 6. 恢复 + 判定 =================
restore_defaults
NEW_RI="$(read_key rotationInterval)"
NEW_PM="$(read_key playMode)"
if [ "$NEW_RI" = "$OLD_RI" ] && [ "$NEW_PM" = "$OLD_PM" ]; then
  emit_line "STRESS_DEFAULTS_RESTORED=1"
else
  emit_line "STRESS_DEFAULTS_RESTORED=0"
  emit_line "STRESS_DEFAULTS_AFTER_RI=$NEW_RI"
  emit_line "STRESS_DEFAULTS_AFTER_PM=$NEW_PM"
fi

ADV_OK="$(awk -v a="${ADVANCES:-0}" 'BEGIN{print (a>=50)?1:0}')"
DRIFT_OK="$(awk -v d="$DRIFT" 'BEGIN{ d=(d<0)?-d:d; print (d<=10.0)?1:0 }')"
TERM_OK="$(grep -cE '^STRESS_TERMINATE_PATH=applicationWillTerminate$' "$LOG" || true)"
REST_OK="$(grep -cE '^STRESS_DEFAULTS_RESTORED=1$' "$LOG" || true)"

if [ "$ADV_OK" = "1" ] && [ "$DRIFT_OK" = "1" ] && [ "$TERM_OK" = "1" ] && [ "$REST_OK" = "1" ]; then
  emit_line "STRESS_VERDICT=pass"
  RC=0
else
  emit_line "STRESS_VERDICT=fail"
  RC=1
fi

log "stress: ADVANCES=${ADVANCES:-0} DRIFT=${DRIFT}% rc=$RC —— 详见 $LOG"
exit "$RC"