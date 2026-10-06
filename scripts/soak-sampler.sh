#!/usr/bin/env bash
# 长跑的**单次**采样：读一次系统状态，往 soak.log 追加一行。用法 `SOAK_DIR=<dir> SOAK_PID=<pid> bash scripts/soak-sampler.sh`。
#
# 调度不归本脚本 —— 「每小时」是 launchd 的 StartInterval（见 scripts/soak-agent.sh）。脚本自己再睡一小时就变成常驻循环：
# 进程一死采样就停，而「进程还活着」恰好是长跑最需要证明的事 —— 把它交给 launchd 比自己保活更可信。
#
# 行形状（键名与顺序）是 soak-analyze.sh 的输入契约，一处漂移全部判据失明：
#   ts rss vsz fd crashes sleeps wakes alive locked batt missing
# 所以读数按顺序逐个 emit，不做拼接。

set -u
export LC_ALL=C

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; return 0; }
trap cleanup EXIT INT TERM

# 本机没有 timeout 命令：权限弹窗或异常输入会把无人值守的采样挂死。
alarm() { perl -e "alarm $1; exec @ARGV" "${@:2}"; }

# ps 的 `-o rss=` 带前导空格、macOS 的 `wc -l` 带右对齐补白 —— 不剥净就拼出
# `rss= 1234` 这种两个 token 的行，分析器按空格切字段就切错位了。
num() {
  local v
  v="$(printf '%s' "${1:-}" | tr -cd '0-9')"
  printf '%s' "${v:-0}"
}

SOAK_DIR="${SOAK_DIR:-$ROOT/.planning/phases/07-delivery/evidence/soak}"
# 采样期间只盯一个 Pic 进程；同时跑第二个（开发期另一个 build、或用户手开一个）
# 会让 pgrep 采错对象，7 天序列从此对着另一个进程。
SOAK_PID="${SOAK_PID:-$(pgrep -x Pic 2>/dev/null | head -1)}"
LOG="$SOAK_DIR/soak.log"

mkdir -p "$SOAK_DIR" 2>/dev/null || exit 1

TS="$(num "$(alarm 10 date +%s)")"

# 崩溃计数与睡眠/唤醒计数是全局计数器，与 Pic 在不在场无关 —— 缺失样本里照常读，
# 填 0 等于往日志里写一个假的零测量（CRASH_DELTA 会据此判出一个并不存在的崩溃）。
CRASHES="$(num "$(alarm 30 ls "$HOME/Library/Logs/DiagnosticReports/" 2>/dev/null | grep -c '^Pic-')")"

alarm 90 pmset -g log > "$TMP/pmset.log" 2>/dev/null || : > "$TMP/pmset.log"
SLEEPS="$(num "$(grep -cE 'Entering Sleep' "$TMP/pmset.log")")"
WAKES="$(num "$(grep -cE 'Wake from' "$TMP/pmset.log")")"

if alarm 20 pmset -g batt 2>/dev/null | head -1 | grep -q 'AC Power'; then
  BATT="ac"
else
  BATT="battery"
fi

# 锁屏时 alive=0 是预期而非故障 —— locked 字段就是给分析器区分这两种 0 用的。
LOCKRAW="$(alarm 20 ioreg -n Root -d 1 -a 2>/dev/null \
  | grep -A1 '<key>CGSSessionScreenIsLocked</key>' | tail -1 | tr -d ' \t<>/')"
case "$LOCKRAW" in
  true|1) LOCKED=1 ;;
  *)      LOCKED=0 ;;
esac

if [ -n "$SOAK_PID" ] && alarm 10 ps -p "$SOAK_PID" > /dev/null 2>&1; then
  MISSING=0
  # `-o rss=` 的等号去表头；不去的话读数里会混进一行 "RSS VSZ"。
  read -r _rss _vsz <<< "$(alarm 20 ps -o rss= -o vsz= -p "$SOAK_PID" 2>/dev/null | head -1)"
  RSS="$(num "${_rss:-}")"
  VSZ="$(num "${_vsz:-}")"
  FD="$(num "$(alarm 60 lsof -p "$SOAK_PID" 2>/dev/null | wc -l)")"
  alarm 20 screencapture -x "$TMP/shot-a.png" > /dev/null 2>&1
  alarm 20 sleep 3
  alarm 20 screencapture -x "$TMP/shot-b.png" > /dev/null 2>&1
  # 截图缺失（锁屏 / 无屏幕录制授权）一律记 0，不拿「没截到」冒充「没在动」。
  ALIVE=0
  if [ -s "$TMP/shot-a.png" ] && [ -s "$TMP/shot-b.png" ]; then
    A="$(alarm 20 md5 -q "$TMP/shot-a.png" 2>/dev/null || echo x)"
    B="$(alarm 20 md5 -q "$TMP/shot-b.png" 2>/dev/null || echo x)"
    [ "$A" != "$B" ] && ALIVE=1
  fi
else
  # PID 作用域的读数（内存/句柄/活性）在 app 缺席时无法测得：填 0 并以 missing=1
  # 标记 —— 分析器据此判 fail，7 天里 app 死掉的事实必须留痕，不许静默跳过。
  MISSING=1
  RSS=0; VSZ=0; FD=0; ALIVE=0
fi

printf 'ts=%s rss=%s vsz=%s fd=%s crashes=%s sleeps=%s wakes=%s alive=%s locked=%s batt=%s missing=%s\n' \
  "$TS" "$RSS" "$VSZ" "$FD" "$CRASHES" "$SLEEPS" "$WAKES" "$ALIVE" "$LOCKED" "$BATT" "$MISSING" >> "$LOG"

exit 0