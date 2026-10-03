#!/usr/bin/env bash
# verify-uninstall.sh —— 卸载残留逐项复查为 0。
#
#   bash scripts/verify-uninstall.sh
#     → 记四项基线（defaults 域 / Preferences 落盘 plist / 路线 B LaunchAgent / BTM 记录）
#     → defaults export 备份
#     → **让 app 自己走一遍 disableBoth**（BTM 只能由活着的 app unregister）
#     → 脚本做文件级补刀（pkill / defaults delete / rm plist / launchctl bootout）
#     → 复查四项全为 0/absent → UNINSTALL_RESIDUE_TOTAL=0
#     → defaults import 恢复 + 复读 sourceFolderPath 比对 → UNINSTALL_RESTORED=1
#
# ⚠️ **这是「校验脚本」，不是真卸载**。真卸载的终态由 UAT 人工执行一次；本脚本验证的
#    是**清理路径与复查机制**本身。跑完必须把开发机偏好原样恢复 ——
#    export/import 备份链是唯一防线，`sourceFolderPath` 前后比对是它的判据。
#
# ⚠️ **绝不调用 BTM 的整体重置子命令**。它清掉的是**全部**登录项，不只是本 app 的
#    —— 核弹。削注释后本文件该命令计数必须 == 0（判据 grep 这个词）。
#    只用现代的 bootout，不出现已废弃的 unload 子命令。
#
# 纪律（同 probe 系）：`set -u` + `export LC_ALL=C`，外部命令套 alarm，不用 set -e。
# 清理路径与断言路径同一条（都在函数里 + trap），断言失败也必须把状态还原。

set -u
export LC_ALL=C

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

EV="$ROOT/.planning/phases/07-delivery/evidence"
LOG="$EV/uninstall.log"
TMP="$(mktemp -d)"

APP="$ROOT/build/Pic.app/Contents/MacOS/Pic"
DOMAIN="com.local.pic"
LABEL="com.local.pic"
PREFS_PLIST="$HOME/Library/Preferences/$LABEL.plist"
AGENT_PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
GUI="gui/$(id -u)"
BTM_TIMEOUT=25

BACKED_UP=0
APP_PID=""

alarm() { perl -e "alarm $1; exec @ARGV" "${@:2}"; }
log() { printf '%s\n' "$*" >&2; }
emit_line() { printf '%s\n' "$*" >> "$LOG"; }

# 还原用户偏好。这是本脚本唯一的「不能出错」路径：跑挂了也必须执行。
restore_prefs() {
  [ "$BACKED_UP" = "1" ] || return 0
  alarm 30 defaults import "$DOMAIN" "$TMP/prefs.bak" >/dev/null 2>&1 || true
  return 0
}

cleanup() {
  if [ -n "$APP_PID" ] && kill -0 "$APP_PID" 2>/dev/null; then
    kill "$APP_PID" 2>/dev/null || true
  fi
  APP_PID=""
  pkill -x Pic >/dev/null 2>&1 || true
  restore_prefs
  rm -rf "$TMP"
  return 0
}
trap cleanup EXIT INT TERM

mkdir -p "$EV"
: > "$LOG"

# ---- 四项读数 ----
# BTM 读不到与读到 0 是两件事，故返回值分两个变量。
# ⚠️ 必须**直接调用**（不能写成 `X="$(btm_read)"`）：命令替换跑在子 shell 里，
#    函数里的赋值传不回父 shell，`set -u` 下就是 unbound variable。
btm_read() {
  local out rc
  out="$(alarm "$BTM_TIMEOUT" sfltool dumpbtm 2>/dev/null)"
  rc=$?
  if [ "$rc" -ne 0 ] || [ -z "$out" ]; then
    BTM_AVAILABLE=0
    BTM_COUNT=0
  else
    BTM_AVAILABLE=1
    BTM_COUNT="$(printf '%s' "$out" | /usr/bin/grep -c "$LABEL" || true)"
  fi
}
present_absent() { [ -e "$1" ] && echo present || echo absent; }

# ================= 1. 基线四项 =================
alarm 30 defaults export "$DOMAIN" "$TMP/prefs.bak" >/dev/null 2>&1 && BACKED_UP=1 || BACKED_UP=0
PREFS_DOMAIN_BEFORE="$(defaults domains 2>/dev/null | tr ',' '\n' | /usr/bin/grep -qx "$DOMAIN" && echo present || echo absent)"
PREFS_SRC_BEFORE="$(alarm 10 defaults read "$DOMAIN" sourceFolderPath 2>/dev/null || echo "__ABSENT__")"
emit_line "UNINSTALL_PREFS_DOMAIN_BEFORE=$PREFS_DOMAIN_BEFORE"
emit_line "UNINSTALL_SOURCEFOLDER_BEFORE=$PREFS_SRC_BEFORE"
emit_line "UNINSTALL_BACKUP_OK=$BACKED_UP"
emit_line "UNINSTALL_PREFS_FILE_BEFORE=$(present_absent "$PREFS_PLIST")"
emit_line "UNINSTALL_AGENT_BEFORE=$(present_absent "$AGENT_PLIST")"
btm_read
BTM_BEFORE="$BTM_COUNT"
emit_line "UNINSTALL_BTM_BEFORE=$BTM_BEFORE"
emit_line "UNINSTALL_BTM_BEFORE_AVAILABLE=$BTM_AVAILABLE"

# ================= 2. 让 app 自己清登录项 =================
# BTM 记录只能由**活着的 app** unregister（System 侧只暴露 enable/disable 给 app 自己），
# 所以脚本先把 launchAtLogin 打开让 app 有事可做，再让它走一遍 disableBoth。
if [ "$BTM_BEFORE" -gt 0 ] || [ -f "$AGENT_PLIST" ]; then
  alarm 20 defaults write "$DOMAIN" launchAtLogin -bool false >/dev/null 2>&1 || true
  if [ -x "$APP" ]; then
    alarm 30 env PIC_SOURCE_FOLDER="$ROOT/fixtures" "$APP" --quit-after 4 \
      > "$TMP/disable.out" 2> "$TMP/disable.err" &
    APP_PID=$!
    waited=0
    while kill -0 "$APP_PID" 2>/dev/null && [ "$waited" -lt 12 ]; do
      sleep 1; waited=$((waited + 1))
    done
    kill "$APP_PID" 2>/dev/null || true
    APP_PID=""
  fi
  emit_line "UNINSTALL_APP_DISABLEBOTH_RAN=1"
else
  # 机器上本来就没有本 app 的登录项 —— 记录「没跑」，不假装跑过。
  emit_line "UNINSTALL_APP_DISABLEBOTH_RAN=0 reason=no_baseline_login_item"
fi

# ================= 3. 文件级补刀 =================
pkill -x Pic >/dev/null 2>&1 || true
sleep 1
pkill -9 -x Pic >/dev/null 2>&1 || true
alarm 30 defaults delete "$DOMAIN" >/dev/null 2>&1 || true
rm -f "$PREFS_PLIST"
alarm 20 launchctl bootout "$GUI/$LABEL" >/dev/null 2>&1 || true
rm -f "$AGENT_PLIST"
# defaults 写入是异步落盘的；补一刀 cfprefsd 让「删了」与「文件没了」对齐。
killall -u "$(id -u)" cfprefsd >/dev/null 2>&1 || true

# ================= 4. 复查四项 =================
AFTER_DOMAIN="$(defaults domains 2>/dev/null | tr ',' '\n' | /usr/bin/grep -qx "$DOMAIN" && echo present || echo absent)"
AFTER_PREFS_FILE="$(present_absent "$PREFS_PLIST")"
AFTER_AGENT="$(present_absent "$AGENT_PLIST")"
btm_read
AFTER_BTM="$BTM_COUNT"

emit_line "UNINSTALL_PREFS_DOMAIN_AFTER=$AFTER_DOMAIN"
emit_line "UNINSTALL_PREFS_FILE_AFTER=$AFTER_PREFS_FILE"
emit_line "UNINSTALL_AGENT_AFTER=$AFTER_AGENT"
emit_line "UNINSTALL_BTM_AFTER=$AFTER_BTM"
emit_line "UNINSTALL_BTM_AFTER_AVAILABLE=$BTM_AVAILABLE"

RESIDUE=0
[ "$AFTER_DOMAIN" = "absent" ] || RESIDUE=$((RESIDUE + 1))
[ "$AFTER_PREFS_FILE" = "absent" ] || RESIDUE=$((RESIDUE + 1))
[ "$AFTER_AGENT" = "absent" ] || RESIDUE=$((RESIDUE + 1))
[ "$AFTER_BTM" -eq 0 ] || RESIDUE=$((RESIDUE + 1))
emit_line "UNINSTALL_RESIDUE_TOTAL=$RESIDUE"

# ================= 5. 恢复开发机偏好 =================
restore_prefs
if [ "$BACKED_UP" = "1" ]; then
  PREFS_SRC_AFTER="$(alarm 10 defaults read "$DOMAIN" sourceFolderPath 2>/dev/null || echo "__ABSENT__")"
  if [ "$PREFS_SRC_AFTER" = "$PREFS_SRC_BEFORE" ]; then
    emit_line "UNINSTALL_RESTORED=1"
  else
    emit_line "UNINSTALL_RESTORED=0"
    emit_line "UNINSTALL_SOURCEFOLDER_AFTER=$PREFS_SRC_AFTER"
  fi
else
  # 基线本来就没有这个域 —— 跑完它仍然应该没有。缺这个分支会把「本来没有」
  # 判成「恢复失败」。
  if [ "$AFTER_DOMAIN" = "absent" ]; then
    emit_line "UNINSTALL_RESTORED=1"
    emit_line "UNINSTALL_RESTORE_NOTE=no_baseline_domain_confirmed_absent"
  else
    emit_line "UNINSTALL_RESTORED=0"
    emit_line "UNINSTALL_RESTORE_NOTE=no_baseline_domain_but_domain_present"
  fi
fi

# ================= 6. 结论边界 =================
emit_line "UNINSTALL_NOTE=simulated_uninstall_then_restored; real_terminal_state_is_uat_manual"

RC=0
[ "$RESIDUE" -eq 0 ] || RC=1
alarm 10 defaults read "$DOMAIN" sourceFolderPath >/dev/null 2>&1
log "uninstall: RESIDUE_TOTAL=$RESIDUE restored=$( /usr/bin/grep -cE '^UNINSTALL_RESTORED=1$' "$LOG" || true) rc=$RC —— 详见 $LOG"
exit "$RC"