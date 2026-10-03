#!/usr/bin/env bash
# verify-packaging.sh —— Plan 07-04 T2 的 SC1：重复构建结果一致（锚 .app，不锚 DMG）。
#
#   bash scripts/verify-packaging.sh
#     → 跑两遍 bash build.sh，各取四样读数（二进制 md5 / plist md5 / DMG 清单 / 挂载点二进制 md5）
#     → 三项对比成立 → PACK_REPEAT_CONSISTENT=1
#     → 形态断言（adhoc / not set / spctl rc=3 / hdiutil verify）全部**正向**
#     → 无上架产物（无 .pkg、无 app-sandbox entitlements）→ PACK_NO_APPSTORE_ARTIFACTS=1
#     → 全部 PACK_* 行落 evidence/packaging.log
#
# ⚠️ **锚点纪律（W-2026-10-03-45）**：DMG 的 md5 已实测不可复现 —— 四次独立 build.sh
#    得到四个不同的 md5，而两次 DMG 内的 Pic.app 逐字节相同。差异在 UDIF 容器层。
#    所以「重复执行结果一致」锚 .app 的内容与 DMG 的**文件清单**，**不打 DMG md5 对比**；
#    那条不可复现性以 PACK_DMG_MD5_NOTE 一行显式记录，留给审计看「为什么不断言它」。
#
# ⚠️ **spctl 是正向断言（W-2026-10-03-47）**：未签名未公证的 app **应当**被拒绝，
#    `spctl -a -t exec` 返回 rc=3 是 PACK-02 的形态面成立。把它当失败是把判据方向写反了。
#
# ⚠️ **create-dmg 主路在本机从未成功**（AppleEvent→Finder 自动化授权缺失，
#    -1743），build.sh 每次都走 hdiutil 降级。本脚本对此**不假装**：DMG 生成走哪条路
#    由 build.sh 自己打 DMG_FALLBACK= 行，本脚本只读不判。
#
# 纪律（同 probe 系）：`set -u` + `export LC_ALL=C`，外部命令套 alarm，不用 set -e。

set -u
export LC_ALL=C

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

EV="$ROOT/.planning/phases/07-delivery/evidence"
LOG="$EV/packaging.log"
TMP="$(mktemp -d)"

APP="$ROOT/build/Pic.app"
DMG="$ROOT/dist/Pic-0.1.0.dmg"
FAILURES=""

alarm() { perl -e "alarm $1; exec @ARGV" "${@:2}"; }
cleanup() { rm -rf "$TMP"; return 0; }
trap cleanup EXIT INT TERM

mkdir -p "$EV"
: > "$LOG"
log() { printf '%s\n' "$*" >&2; }
emit_line() { printf '%s\n' "$*" >> "$LOG"; }
fail() { FAILURES="$FAILURES $1"; }

# 一遍构建的四个读数。$1 = 轮次标签（A / B）。
# DMG 挂载后 detach —— 挂载点留着会让第二批 .pkg/清单的 find 看见别人的东西。
collect() {
  local tag="$1" mnt=""
  alarm 1200 bash build.sh > "$TMP/build-$tag.log" 2>&1
  local brc=$?
  emit_line "PACK_BUILD_${tag}_RC=$brc"
  [ "$brc" -ne 0 ] && fail "build_$tag"

  # DMG 走的是哪条路（build.sh 自己的判定，不猜）
  local fb
  fb="$(grep -c '^DMG_FALLBACK=hdiutil' "$TMP/build-$tag.log" 2>/dev/null || true)"
  emit_line "PACK_DMG_ROUTE_$tag=$( [ "${fb:-0}" -gt 0 ] && echo hdiutil_fallback || echo create_dmg )"

  md5 -q "$APP/Contents/MacOS/Pic" > "$TMP/bin-$tag" 2>/dev/null || echo none > "$TMP/bin-$tag"
  md5 -q "$APP/Contents/Info.plist" > "$TMP/plist-$tag" 2>/dev/null || echo none > "$TMP/plist-$tag"

  local out
  out="$(alarm 120 hdiutil attach -nobrowse -readonly "$DMG" 2>/dev/null | grep -oE '/Volumes/.*' | head -1)"
  if [ -n "$out" ]; then
    mnt="$out"
    ( cd "$mnt" && find . -type f | LC_ALL=C sort ) > "$TMP/list-$tag" 2>/dev/null || : > "$TMP/list-$tag"
    if [ -f "$mnt/Pic.app/Contents/MacOS/Pic" ]; then
      md5 -q "$mnt/Pic.app/Contents/MacOS/Pic" > "$TMP/mnt-$tag" 2>/dev/null || echo none > "$TMP/mnt-$tag"
    else
      echo none > "$TMP/mnt-$tag"
    fi
    # 图标三项（挂载点内）
    local ic=0 mv=0 m2=0
    [ -f "$mnt/Pic.app/Contents/Resources/Pic.icns" ] && [ -s "$mnt/Pic.app/Contents/Resources/Pic.icns" ] && ic=1
    [ -f "$mnt/Pic.app/Contents/Resources/menubar-v1Template.png" ] && mv=1
    m2=$(find "$mnt/Pic.app/Contents/Resources" -name 'menubar-v2*' 2>/dev/null | wc -l | tr -d ' ')
    emit_line "PACK_ICON_${tag}_APPICON=$ic"
    emit_line "PACK_ICON_${tag}_MENUBAR=$mv"
    emit_line "PACK_ICON_${tag}_MENUBAR_V2_COUNT=$m2"
    local ac
    ac=$(find "$mnt" -maxdepth 1 -name '*.app' 2>/dev/null | wc -l | tr -d ' ')
    emit_line "PACK_DMG_APP_COUNT=$ac"
    alarm 60 hdiutil detach "$mnt" >/dev/null 2>&1 || true
  else
    : > "$TMP/list-$tag"
    echo none > "$TMP/mnt-$tag"
    fail "dmg_mount_$tag"
  fi
  return 0
}

# ================= 两遍构建 =================
collect A
collect B

BIN_A="$(cat "$TMP/bin-A")"; BIN_B="$(cat "$TMP/bin-B")"
PLIST_A="$(cat "$TMP/plist-A")"; PLIST_B="$(cat "$TMP/plist-B")"
MNT_A="$(cat "$TMP/mnt-A")"; MNT_B="$(cat "$TMP/mnt-B")"

emit_line "PACK_BIN_MD5_A=$BIN_A"
emit_line "PACK_BIN_MD5_B=$BIN_B"
emit_line "PACK_PLIST_MD5_A=$PLIST_A"
emit_line "PACK_PLIST_MD5_B=$PLIST_B"
emit_line "PACK_MOUNT_BIN_MD5_A=$MNT_A"
emit_line "PACK_MOUNT_BIN_MD5_B=$MNT_B"

REPEAT_OK=1
[ "$BIN_A" = "$BIN_B" ] && [ "$BIN_A" != "none" ] || { REPEAT_OK=0; fail "bin_md5_mismatch"; }
[ "$PLIST_A" = "$PLIST_B" ] && [ "$PLIST_A" != "none" ] || { REPEAT_OK=0; fail "plist_md5_mismatch"; }
LC_ALL=C sort "$TMP/list-A" > "$TMP/listA.s"; LC_ALL=C sort "$TMP/list-B" > "$TMP/listB.s"
cmp -s "$TMP/listA.s" "$TMP/listB.s" || { REPEAT_OK=0; fail "dmg_list_mismatch"; }

if [ "$REPEAT_OK" = "1" ]; then
  emit_line "PACK_REPEAT_CONSISTENT=1"
else
  emit_line "PACK_REPEAT_CONSISTENT=0"
fi
# 不断言 DMG md5 —— 理由显式落一行，别让审计以为漏了。
emit_line "PACK_DMG_MD5_NOTE=anchor_app_not_dmg reason=udif_container_nondeterministic"

# ================= 形态断言（全部正向）=================
SIG="$(alarm 20 codesign -dv --verbose=2 "$APP" 2>&1)"
echo "$SIG" | /usr/bin/grep -q '^Signature=adhoc' \
  && emit_line "PACK_SIGNATURE=adhoc" || { emit_line "PACK_SIGNATURE=$(echo "$SIG" | sed -n 's/^Signature=//p' | head -1)"; fail "signature"; }
echo "$SIG" | /usr/bin/grep -q '^TeamIdentifier=not set' \
  && emit_line "PACK_TEAMIDENTIFIER=not_set" || { emit_line "PACK_TEAMIDENTIFIER=$(echo "$SIG" | sed -n 's/^TeamIdentifier=//p' | head -1)"; fail "team_identifier"; }

# spctl：**预期拒绝** = rc 3（未签名未公证的正常形态）。
alarm 60 spctl -a -t exec -vv "$APP" > "$TMP/spctl.log" 2>&1
SPCTL_RC=$?
emit_line "PACK_SPCTL_RC=$SPCTL_RC"
[ "$SPCTL_RC" -eq 3 ] || fail "spctl_rc_expected_3"

alarm 300 hdiutil verify "$DMG" > "$TMP/verify.log" 2>&1
if [ $? -eq 0 ]; then emit_line "PACK_HDIUTIL_VERIFY=ok"; else emit_line "PACK_HDIUTIL_VERIFY=fail"; fail "hdiutil_verify"; fi

# DMG 里的 app 就是刚构建的那个（逐字节）
if [ "$MNT_B" = "$BIN_B" ] && [ "$MNT_B" != "none" ]; then
  emit_line "PACK_MOUNT_BINARY_MD5_MATCH=1"
else
  emit_line "PACK_MOUNT_BINARY_MD5_MATCH=0"
  fail "mount_binary_mismatch"
fi

# ================= 无上架产物（PACK-02）=================
PKG_COUNT=$(find "$ROOT/dist" -name '*.pkg' 2>/dev/null | wc -l | tr -d ' ')
emit_line "PACK_PKG_COUNT=$PKG_COUNT"
SANDBOX_COUNT=$(alarm 20 codesign -d --entitlements :- "$APP" 2>&1 | /usr/bin/grep -c 'app-sandbox' || true)
emit_line "PACK_APP_SANDBOX_ENTITLEMENTS=$SANDBOX_COUNT"
if [ "$PKG_COUNT" -eq 0 ] && [ "${SANDBOX_COUNT:-0}" -eq 0 ]; then
  emit_line "PACK_NO_APPSTORE_ARTIFACTS=1"
else
  emit_line "PACK_NO_APPSTORE_ARTIFACTS=0"
  fail "appstore_artifacts"
fi

if [ -n "$FAILURES" ]; then
  emit_line "PACK_FAILED=$FAILURES"
  log "packaging: FAILED:$FAILURES —— 详见 $LOG"
  exit 1
fi
emit_line "PACK_FAILED=none"
log "packaging: REPEAT_CONSISTENT=1 spctl_rc=$SPCTL_RC —— 详见 $LOG"
exit 0