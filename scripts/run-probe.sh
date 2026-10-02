#!/usr/bin/env bash
# run-probe.sh —— Plan 02-02 的三项证据采集，一条命令一个子命令：
#
#   bash scripts/run-probe.sh order   → evidence/order.log   （层级判定 + 按 PID 认领的证据）
#   bash scripts/run-probe.sh inset   → evidence/inset.log   （D-08 四个几何内缩整数）
#   bash scripts/run-probe.sh loop    → evidence/loop.log    （300 秒无缝循环采样）
#
# 两条纪律：
#   ① 所有外部命令都套 `perl -e 'alarm N; exec @ARGV'` —— 本机没有 timeout 命令，
#      权限弹窗或异常输入会挂死采集（Phase 1 已踩过）。
#   ② 探针失败不中止脚本（不用 set -e）：失败原样写进日志，由人读日志判定。
#
# 两个探针分住两处，理由是 D-04：
#   - 产品侧 Sources/PicCore/Playback/WindowProbe.swift：只按 PID 认领，不碰图标层的值，
#     所以产品源码里那个被禁用的标识符保持 0 次（scripts 把它现编译成一次性可执行文件）。
#   - 判定侧 .planning/spike/WindowProbe.swift：Phase 1 已验证的 throwaway 探针，现编译现跑，
#     「我方层 < 图标层」这一半由它承担。

set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

EV="$ROOT/.planning/phases/02-playback-core/evidence"
BIN="$ROOT/.build/debug/Pic"
SRC_PROBE="$ROOT/Sources/PicCore/Playback/WindowProbe.swift"
SPIKE_PROBE="$ROOT/.planning/spike/WindowProbe.swift"
FIXTURES="$ROOT/fixtures"
TMP="$(mktemp -d)"
APP_PID=""

log()  { printf '%s\n' "$*" >&2; }
alarm() { perl -e "alarm $1; exec @ARGV" "${@:2}"; }

cleanup() {
  if [ -n "$APP_PID" ]; then kill "$APP_PID" 2>/dev/null || true; fi
  rm -rf "$TMP"
  return 0
}
trap cleanup EXIT INT TERM

ensure_binary() {
  if [ ! -x "$BIN" ]; then
    log "PROBE_NOTE=product_binary_missing building"
    swift build --package-path "$ROOT" > "$TMP/build.log" 2>&1
    local rc=$?
    if [ "$rc" -ne 0 ]; then
      log "BUILD_FAILED rc=$rc"
      grep -E 'error:' "$TMP/build.log" | head -3 >&2
      return 1
    fi
  fi
  return 0
}

start_app() {   # $1=日志前缀  $2..=额外环境赋值 KEY=VALUE
  local prefix="$1"; shift
  local -a envs=("PIC_SOURCE_FOLDER=$FIXTURES")
  envs+=("$@")
  env "${envs[@]}" "$BIN" > "$TMP/$prefix.out" 2> "$TMP/$prefix.err" &
  APP_PID=$!
  sleep 4
  if ! kill -0 "$APP_PID" 2>/dev/null; then
    log "APP_DIED pid=$APP_PID"
    sed -n '1,10p' "$TMP/$prefix.err" >&2
    return 1
  fi
  return 0
}

stop_app() {
  if [ -n "$APP_PID" ]; then kill "$APP_PID" 2>/dev/null || true; APP_PID=""; fi
}

# ---- 黑帧可观测性：真测一次，不靠断言 ----
# 取一张屏，量它的平均亮度（ffmpeg signalstats 的 YAVG）。
# 判据有标定：纯白对照是 235，纯黑是 16（YUV 黑电平）。屏取回来若停在黑电平上，
# 说明这一帧根本没有桌面内容 —— 此时「有没有黑帧」在本机原理上就测不出来，
# 只能如实记 blocked，绝不拿别的东西冒充。
yavg_of() {
  perl -e 'alarm 30; exec @ARGV' ffmpeg -hide_banner -i "$1" \
    -vf signalstats,metadata=print:key=lavfi.signalstats.YAVG -f null - 2>&1 \
    | grep -oE 'signalstats\.YAVG=[0-9.]+' | head -1 | cut -d= -f2
}

blackframe_line() {
  # 标定对照：纯白图的平均亮度。用它把「黑」这件事变成一个可复现的阈值。
  perl -e 'alarm 30; exec @ARGV' ffmpeg -hide_banner -loglevel quiet \
    -f lavfi -i color=c=white:s=64x64:d=1 -frames:v 1 "$TMP/white.png" -y
  local white
  white=$(yavg_of "$TMP/white.png")

  alarm 25 /usr/sbin/screencapture -x "$TMP/bf-a.png" >/dev/null 2>&1
  sleep 2
  alarm 25 /usr/sbin/screencapture -x "$TMP/bf-b.png" >/dev/null 2>&1

  local a b ya yb
  a=$(md5 -q "$TMP/bf-a.png" 2>/dev/null || echo missing)
  b=$(md5 -q "$TMP/bf-b.png" 2>/dev/null || echo missing)
  ya=$(yavg_of "$TMP/bf-a.png" 2>/dev/null || echo missing)
  yb=$(yavg_of "$TMP/bf-b.png" 2>/dev/null || echo missing)

  # 阈值 = 白对照的 10%。白对照 235 → 23.5；实测黑电平 16 稳稳在下面。
  local thresh
  thavg=$(awk -v w="${white:-0}" 'BEGIN{printf "%.1f", w*0.10}' 2>/dev/null || echo 23)
  if [ "$ya" = "missing" ] || [ "$yb" = "missing" ]; then
    printf 'BLACKFRAME=blocked reason=capture_tool_unavailable\n'
    printf 'BLACKFRAME_EVIDENCE=capture_a_md5=%s capture_b_md5=%s\n' "$a" "$b"
  elif awk -v a="$ya" -v b="$yb" -v t="$thavg" 'BEGIN{exit !(a<t && b<t)}'; then
    printf 'BLACKFRAME=blocked reason=no_screen_recording_permission\n'
    printf 'BLACKFRAME_EVIDENCE=capture_a_md5=%s capture_b_md5=%s capture_a_yavg=%s capture_b_yavg=%s white_control_yavg=%s threshold=%s\n' \
      "$a" "$b" "$ya" "$yb" "$white" "$thavg"
  else
    printf 'BLACKFRAME=blocked reason=detector_not_implemented_in_phase_02\n'
    printf 'BLACKFRAME_EVIDENCE=capture_a_md5=%s capture_b_md5=%s capture_a_yavg=%s capture_b_yavg=%s white_control_yavg=%s\n' \
      "$a" "$b" "$ya" "$yb" "$white"
  fi
}

# ---- 子命令 ----

cmd_order() {
  mkdir -p "$EV"
  ensure_binary || return 1
  alarm 90 swiftc -DPIC_WINDOW_PROBE_MAIN -parse-as-library -target arm64-apple-macosx15.0 \
    -o "$TMP/winprobe" "$SRC_PROBE" 2> "$TMP/compile-src.log"
  local rc_src=$?
  alarm 90 swiftc -parse-as-library -target arm64-apple-macosx15.0 \
    -o "$TMP/spikewinprobe" "$SPIKE_PROBE" 2> "$TMP/compile-spike.log"
  local rc_spike=$?
  if [ "$rc_src" -ne 0 ] || [ "$rc_spike" -ne 0 ]; then
    log "PROBE_COMPILE_FAILED product=$rc_src spike=$rc_spike"
    return 1
  fi

  start_app order || return 1
  local pid="$APP_PID"
  alarm 30 "$TMP/winprobe"      --pid "$pid" > "$TMP/product-probe.txt" 2>&1; local rc_prod=$?
  alarm 30 "$TMP/spikewinprobe" --pid "$pid" > "$TMP/spike-probe.txt"   2>&1; local rc_spk=$?
  stop_app

  local order reason self_product foreign claim icon
  order=$(grep -E '^ORDER=' "$TMP/spike-probe.txt" | head -1 | cut -d= -f2)
  # spike 探针在四条判据全过时打的是空的 REASON=，这与「探针没跑出来」不是一回事。
  reason=$(grep -E '^REASON=' "$TMP/spike-probe.txt" | head -1 | sed 's/^REASON=//')
  [ -z "$reason" ] && reason="none_all_four_criteria_met"
  icon=$(grep -E '^ICON_LEVEL=' "$TMP/spike-probe.txt" | head -1 | cut -d= -f2-)
  self_product=$(grep -E '^SELF_LEVEL=' "$TMP/product-probe.txt" | head -1 | cut -d= -f2-)
  foreign=$(grep -E '^FOREIGN_SAME_LEVEL=' "$TMP/product-probe.txt" | head -1 | cut -d= -f2-)
  claim=$(grep -E '^PID_CLAIM_REQUIRED=' "$TMP/product-probe.txt" | head -1 | cut -d= -f2-)

  {
    printf 'ORDER=%s\n' "${order:-fail}"
    printf 'ORDER_SOURCE=spike_windowprobe\n'
    printf 'REASON=%s\n' "${reason:-probe_failed}"
    printf 'SELF_LEVEL=%s\n' "${self_product:-none}"
    printf 'FOREIGN_SAME_LEVEL=%s\n' "${foreign:-0}"
    printf 'PID_CLAIM_REQUIRED=%s\n' "${claim:-0}"
    printf 'ICON_LEVEL=%s\n' "${icon:-none}"
    printf 'SELF_LEVEL_SPIKE=%s\n' "$(grep -E '^SELF_LEVEL=' "$TMP/spike-probe.txt" | head -1 | cut -d= -f2-)"
    grep -E '^(FOREIGN_DESKTOP_FAMILY|PID_CLAIM_REQUIRED_BAND|WINDOWS_TOTAL|OWNED_WINDOW_COUNT|FOREIGN_OWNERS|D09_NOTE|SELF_PID)=' "$TMP/product-probe.txt"
    printf 'SELF_LEVEL_CROSSCHECK=%s\n' \
      "$( [ "$(grep -E '^SELF_LEVEL=' "$TMP/spike-probe.txt" | head -1 | cut -d= -f2-)" = "$self_product" ] \
          && echo agree || echo disagree )"
    printf 'PROBE_RC product=%s spike=%s\n' "$rc_prod" "$rc_spk"
  } > "$EV/order.log"
  log "ORDER_LOG=$EV/order.log order=${order:-fail}"
  return 0
}

cmd_inset() {
  mkdir -p "$EV"
  ensure_binary || return 1
  alarm 90 swiftc -DPIC_WINDOW_PROBE_MAIN -parse-as-library -target arm64-apple-macosx15.0 \
    -o "$TMP/winprobe" "$SRC_PROBE" 2> "$TMP/compile-src.log" || { log "PROBE_COMPILE_FAILED"; return 1; }

  start_app inset || return 1
  local pid="$APP_PID"
  alarm 30 "$TMP/winprobe" --inset --pid "$pid" > "$EV/inset.log" 2>&1
  local rc=$?
  stop_app
  printf 'PROBE_RC=%s\n' "$rc" >> "$EV/inset.log"
  log "INSET_LOG=$EV/inset.log rc=$rc"
  [ "$rc" -eq 0 ] || return 1
  grep -qE '^INSET_RECORDED=1$' "$EV/inset.log" || { log "INSET_NOT_RECORDED"; return 1; }
  return 0
}

cmd_loop() {
  mkdir -p "$EV"
  ensure_binary || return 1
  local seconds="${PIC_LOOP_SECONDS:-300}"

  log "LOOP_START seconds=$seconds （本命令会跑满这段时间）"
  PIC_SOURCE_FOLDER="$FIXTURES" PIC_LOOP_SECONDS="$seconds" \
    "$BIN" > "$TMP/loop.out" 2> "$TMP/loop.err" &
  APP_PID=$!

  local waited=0
  local limit=$((seconds + 120))
  while kill -0 "$APP_PID" 2>/dev/null && [ "$waited" -lt "$limit" ]; do
    sleep 3
    waited=$((waited + 3))
  done
  stop_app

  cp "$TMP/loop.err" "$EV/loop.log"
  blackframe_line >> "$EV/loop.log"
  printf 'LOOP_PROBE_WALL_SECONDS=%s\n' "$waited" >> "$EV/loop.log"

  local n verdict
  n=$(grep -cE '^LOOP_SAMPLE ' "$EV/loop.log")
  verdict=$(grep -E '^LOOP_VERDICT=' "$EV/loop.log" | head -1 | cut -d= -f2)
  log "LOOP_LOG=$EV/loop.log samples=$n verdict=${verdict:-none}"
  return 0
}

case "${1:-}" in
  order) cmd_order ;;
  inset) cmd_inset ;;
  loop)  cmd_loop ;;
  *) log "usage: bash scripts/run-probe.sh {order|inset|loop}"; exit 2 ;;
esac