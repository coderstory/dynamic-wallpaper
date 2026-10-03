#!/usr/bin/env bash
# probe-sys01.sh —— 一次性实测：未签名 app 的开机自启到底走哪条路线。
#
#   bash scripts/probe-sys01.sh
#     → 备份 com.local.pic 偏好域 + 记路线 A/B 的基线读数
#     → 打开 launchAtLogin，起一次 build/Pic.app，读 app 侧 emit 行 + 系统侧读数
#     → 判定 ACTIVE_ROUTE（smappservice / launchagent / none）
#     → **无条件清理**（设 false → 再起一次 app 让 disableBoth 生效 → 兜底 bootout/删 plist
#        → 恢复偏好备份）→ 复查三项是否回基线
#     → 全部 SYS01_* 读数落 evidence/sys01.log
#
# 四条纪律：
#   ① 所有外部命令套 `perl -e 'alarm N; exec @ARGV'` —— 本机没有 timeout 命令，
#      权限弹窗或异常输入会挂死整个采集。
#   ② **不用 set -e**：探针失败不中止脚本，失败原样落日志由人读。
#   ③ 清理路径与断言路径**同一条**（都在函数里 + trap），断言失败也必须清干净：
#      系统登录项与用户偏好是这个脚本唯一会真正改动的东西，留下脏状态就是害人。
#   ④ `set -u` + `export LC_ALL=C`。
#
# ⚠️ **绝不调用 BTM 的整体重置子命令**。它清掉的是**全部**登录项，不只是本 app 的
#    —— 核弹。本脚本剥注释后该命令计数必须 == 0（判据 grep 这个词）。
#    只用现代的 bootstrap / bootout，不出现已废弃的 load / unload 子命令。
#
# ⚠️ **只读计数、不改用户真实开机项配置**：本脚本唯一触碰系统登录项的动作
#    就是「enable → 判路线 → 强制清理 → 恢复偏好」四步，且清理是无条件的。

set -u
export LC_ALL=C

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

EV="$ROOT/.planning/phases/07-delivery/evidence"
LOG="$EV/sys01.log"
TMP="$(mktemp -d)"

APP="$ROOT/build/Pic.app/Contents/MacOS/Pic"
FIXTURES="$ROOT/fixtures"
DOMAIN="com.local.pic"
LABEL="com.local.pic"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
GUI="gui/$(id -u)"
BTM_TIMEOUT=25

APP_PID=""

alarm() { perl -e "alarm $1; exec @ARGV" "${@:2}"; }

# ---- 清理：无条件、与断言路径同一条 ----
cleanup() {
  # ① 先杀掉可能还活着的 app（SIGTERM 走不到 applicationWillTerminate，见 AppDelegate 注释）
  if [ -n "$APP_PID" ]; then kill "$APP_PID" 2>/dev/null || true; APP_PID=""; fi
  # ② 兜底手工清路线 B —— app 没跑起来 / disableBoth 失效时也要收干净
  alarm 20 launchctl bootout "$GUI/$LABEL" >/dev/null 2>&1 || true
  rm -f "$PLIST"
  # ③ 恢复用户偏好（备份不存在 = 本来就没有这个域，保持原样）
  if [ -f "$TMP/prefs.bak" ]; then
    alarm 20 defaults import "$DOMAIN" "$TMP/prefs.bak" >/dev/null 2>&1 || true
  fi
  # ⚠️ `defaults import` 是**合并**不是替换 —— 它只会把备份里的键写回来，
  #    绝不删掉我们新加的键。基线里没有 launchAtLogin 时必须显式 delete，
  #    否则探针跑完给用户域里多出一个它本来没有的偏好。
  if [ "${BASELINE_PREFS_VALUE:-}" = "<absent>" ]; then
    alarm 20 defaults delete "$DOMAIN" launchAtLogin >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP"
  return 0
}
trap cleanup EXIT INT TERM

mkdir -p "$EV"
: > "$LOG"

log() { printf '%s\n' "$*" >&2; }
emit_line() { printf '%s\n' "$*" >> "$LOG"; }

# ---- 路线 A 的系统侧读数。dumpbtm 本机会挂（见 evidence 里的 SYS01_BTM_* 行），
#      故套 alarm；超时按 0 记，但**另打一行可用性** —— 读不到与读到 0 是两件事，
#      合成一个数字就是把差别抹掉。
#
# ⚠️ 必须**直接调用**（不能写成 `X="$(btm_read)"`）：命令替换跑在子 shell 里，
#    函数里的赋值传不回父 shell，`set -u` 下就是 unbound variable。
#    故返回值走全局 BTM_COUNT / BTM_AVAILABLE 两个变量。
btm_read() {
  local out rc
  out="$(alarm "$BTM_TIMEOUT" sfltool dumpbtm 2>/dev/null)"
  rc=$?
  if [ "$rc" -ne 0 ] || [ -z "$out" ]; then
    BTM_AVAILABLE=0
    BTM_COUNT=0
  else
    BTM_AVAILABLE=1
    BTM_COUNT="$(printf '%s' "$out" | grep -c "$LABEL" || true)"
  fi
}

plist_present() { [ -f "$PLIST" ] && echo present || echo absent; }

run_app_once() {   # $1=前缀  $2=等待秒数
  local prefix="$1" waited=0
  # ⚠️ `alarm` 必须在 **外层**：`env VAR=x alarm …` 是错的 —— `env` 只能 exec
  #    真实可执行文件，shell 函数不在 PATH 里，那条写法下 app 根本没起来，
  #    日志会「安静地」少掉所有 SYS01_* 行（空 evidence = 假绿灯）。
  alarm 60 env PIC_SOURCE_FOLDER="$FIXTURES" "$APP" \
    --quit-after "$2" > "$TMP/$prefix.out" 2> "$TMP/$prefix.err" &
  APP_PID=$!
  while kill -0 "$APP_PID" 2>/dev/null && [ "$waited" -lt "$2" ]; do
    sleep 1; waited=$((waited + 1))
  done
  kill "$APP_PID" 2>/dev/null || true
  APP_PID=""
}

# ================= 1. 基线 =================
alarm 20 defaults export "$DOMAIN" "$TMP/prefs.bak" >/dev/null 2>&1 || true
emit_line "SYS01_PROBE_TARGET=build/Pic.app signature=$(alarm 10 codesign -dv "$ROOT/build/Pic.app" 2>&1 | grep -c 'Signature=adhoc')"

btm_read
BASELINE_BTM="$BTM_COUNT"
BASELINE_BTM_AVAILABLE="$BTM_AVAILABLE"
BASELINE_PLIST="$(plist_present)"
alarm 20 launchctl print "$GUI/$LABEL" >/dev/null 2>&1
BASELINE_LAUNCHCTL_RC=$?

# ⚠️ 基线必须在**写 enable 之前**取。晚一步取就变成「跟清理后的自己比」——
#    恒等于、恒绿，判据就废了。
prefs_probe() { alarm 10 defaults read "$DOMAIN" launchAtLogin 2>/dev/null || echo "<absent>"; }
BASELINE_PREFS_VALUE="$(prefs_probe)"
emit_line "SYS01_BASELINE_PREFS=$BASELINE_PREFS_VALUE"

emit_line "SYS01_BASELINE_BTM=$BASELINE_BTM"
emit_line "SYS01_BASELINE_BTM_AVAILABLE=$BASELINE_BTM_AVAILABLE"
emit_line "SYS01_BASELINE_PLIST=$BASELINE_PLIST"
emit_line "SYS01_BASELINE_LAUNCHCTL_RC=$BASELINE_LAUNCHCTL_RC"

# ================= 2. 打开开关，起一次 app =================
alarm 20 defaults write "$DOMAIN" launchAtLogin -bool true >/dev/null 2>&1 || true
emit_line "SYS01_ENABLE_WRITE_RC=$?"

if [ ! -x "$APP" ]; then
  emit_line "SYS01_APP_MISSING=1"
  log "probe: build/Pic.app 不存在，先跑 bash build.sh"
  cleanup; trap - EXIT
  printf '%s\n' "SYS01_ACTIVE_ROUTE=none" >> "$LOG"
  printf '%s\n' "SYS01_PROBE_RC=1" >> "$LOG"
  exit 1
fi

run_app_once enable 6

# ================= 3. 读数 =================
# app 侧：emit 行逐字转记。缺失就缺失，不编。
#
# ⚠️ 「app 一行都没打」与「app 打了但这一行没有」是两件事：前者说明采集链本身断了
#    （起不来 / 起错了二进制 / stderr 没落对地方），继续判路线就是拿空日志编结论。
#    故先立一道可执行的门，把两种情况分开记。
if [ ! -s "$TMP/enable.err" ]; then
  emit_line "SYS01_APP_EMITTED_NOTHING=1"
else
  emit_line "SYS01_APP_EMITTED_LINES=$(grep -c . "$TMP/enable.err")"
fi

SMAPP_STATUS="$(grep -E '^SMAPP_STATUS=' "$TMP/enable.err" 2>/dev/null | head -1 | cut -d= -f2-)"
[ -n "$SMAPP_STATUS" ] && emit_line "SYS01_SMAPP_STATUS=$SMAPP_STATUS"
ROUTE="$(grep -E '^SYS01_ROUTE=' "$TMP/enable.err" 2>/dev/null | head -1 | cut -d= -f2-)"
[ -n "$ROUTE" ] && emit_line "SYS01_ROUTE=$ROUTE"
ROUTE_A_FAILED="$(grep -E '^SYS01_ROUTE_A_FAILED' "$TMP/enable.err" 2>/dev/null | head -1)"
[ -n "$ROUTE_A_FAILED" ] && emit_line "SYS01_ROUTE_A_FAILED_DETAIL=${ROUTE_A_FAILED#*=}"
grep -E '^SYS01_REQUIRES_APPROVAL=' "$TMP/enable.err" 2>/dev/null | head -1 >> "$LOG"

btm_read
AFTER_BTM="$BTM_COUNT"
AFTER_BTM_AVAILABLE="$BTM_AVAILABLE"
emit_line "SYS01_BTM_AFTER=$AFTER_BTM"
emit_line "SYS01_BTM_AFTER_AVAILABLE=$AFTER_BTM_AVAILABLE"
emit_line "SYS01_PLIST_AFTER=$(plist_present)"
alarm 20 launchctl print "$GUI/$LABEL" >/dev/null 2>&1
LAUNCHCTL_RC=$?
emit_line "SYS01_LAUNCHCTL_RC=$LAUNCHCTL_RC"
if [ -f "$PLIST" ]; then
  alarm 20 plutil -lint "$PLIST" >/dev/null 2>&1
  emit_line "SYS01_PLUTIL_RC=$?"
fi

# ================= 4. 判定 =================
ACTIVE_ROUTE=none
if [ "$AFTER_BTM_AVAILABLE" = "1" ] && [ "$AFTER_BTM" -gt "$BASELINE_BTM" ]; then
  ACTIVE_ROUTE=smappservice
elif [ "$SMAPP_STATUS" = "enabled" ] || [ "$SMAPP_STATUS" = "requiresApproval" ]; then
  ACTIVE_ROUTE=smappservice
elif [ "$LAUNCHCTL_RC" -eq 0 ] && [ "$(plist_present)" = "present" ]; then
  ACTIVE_ROUTE=launchagent
fi
emit_line "SYS01_ACTIVE_ROUTE=$ACTIVE_ROUTE"

# ================= 5. 无条件清理 =================
alarm 20 defaults write "$DOMAIN" launchAtLogin -bool false >/dev/null 2>&1 || true
# 再起一次 app：让 disableBoth 真跑一遍（unregister + bootout + 删 plist）
run_app_once disable 4
# 兜底在 trap/cleanup 里再补一遍 bootout + rm

# ⚠️ 偏好复原必须**在第 6 步复查之前**做完：`defaults import` 只合并不替换，
#    基线里没有该键时不会自己消失。放到 trap 里就晚了（trap 在 exit 时才跑，
#    那时第 6 步的比对早就出结果了）。trap 里那份是兜底，不是主路径。
alarm 20 defaults import "$DOMAIN" "$TMP/prefs.bak" >/dev/null 2>&1 || true
if [ "$BASELINE_PREFS_VALUE" = "<absent>" ]; then
  alarm 20 defaults delete "$DOMAIN" launchAtLogin >/dev/null 2>&1 || true
fi

# ================= 6. 复查三项是否回基线 =================
btm_read
CLEANUP_BTM="$BTM_COUNT"
CLEANUP_BTM_AVAILABLE="$BTM_AVAILABLE"
emit_line "SYS01_CLEANUP_BTM=$CLEANUP_BTM"
emit_line "SYS01_CLEANUP_BTM_AVAILABLE=$CLEANUP_BTM_AVAILABLE"
if [ "$(plist_present)" = "$BASELINE_PLIST" ]; then
  emit_line "SYS01_CLEANUP_PLIST=matches_baseline"
else
  emit_line "SYS01_CLEANUP_PLIST=mismatch"
fi

# 偏好复原核对：**与第 1 步记下的 BASELINE_PREFS 比**，不解析备份文件。
#   （早先版本去 grep 备份里的键名，但 `grep -c` 零命中时退出码是 1，
#     `|| echo 0` 会拼成两行、永远不等于 "0" —— 判据自己恒红。）
# 存在性用「能否读出该键」表达，不把「缺失」编成一个布尔值之外的东西。
AFTER_PREFS_VALUE="$(prefs_probe)"
if [ "$AFTER_PREFS_VALUE" = "$BASELINE_PREFS_VALUE" ]; then
  PREFS_RESTORED=1
else
  PREFS_RESTORED=0
  emit_line "SYS01_PREFS_AFTER=$AFTER_PREFS_VALUE"
fi
emit_line "SYS01_PREFS_RESTORED=$PREFS_RESTORED"

# ================= 7. 结论边界 =================
emit_line "SYS01_REBOOT_CONFIRMED=pending_human"
emit_line "SYS01_NOTE=mechanism_verdict_on_build_app; persistence_requires_dmg_install_and_reboot"

RC=0
[ "$ACTIVE_ROUTE" = "none" ] && RC=1
[ "$CLEANUP_BTM" != "$BASELINE_BTM" ] && RC=1
[ "$PREFS_RESTORED" != "1" ] && RC=1
emit_line "SYS01_PROBE_RC=$RC"

log "probe: ACTIVE_ROUTE=$ACTIVE_ROUTE rc=$RC —— 详见 $LOG"
exit "$RC"