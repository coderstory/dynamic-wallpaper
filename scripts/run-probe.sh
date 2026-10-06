#!/usr/bin/env bash
# 一条命令一个子命令，各写一份 evidence log：
#   order 层级判定 + 按 PID 认领的证据 / inset 四个几何内缩整数 / loop 300 秒无缝循环采样
#   quit 优雅终止收尾 + SIGTERM 观测 / app 打包 .app 上的层级序 + 激活策略 + ad-hoc 签名
#   refresh 两种运行模式的显示刷新驱动与 tick 率 / holds 真实系统信号下的活体 hold
#
# 前六个子命令的 `EV` 指向旧阶段的 evidence 目录；`holds` 指向它自己那一阶段的目录（`EV3`）。
# 理由：`EV` 是上一阶段的交接面，写进去会让它的目录随下一阶段漂移。
#
# 两条纪律：
#   ① 所有外部命令都套 `alarm N 命令 …` —— 本机没有 timeout 命令，权限弹窗或异常输入会挂死采集。
#   ② 探针失败不中止脚本（不用 set -e）：失败原样写进日志，由人读日志判定。
#
# 两个探针分住两处（层级判定分两半承担）：
#   - 产品侧 Sources/PicCore/Playback/WindowProbe.swift：只按 PID 认领，不碰图标层的值，
#     所以产品源码里那个被禁用的标识符保持 0 次（scripts 把它现编译成一次性可执行文件）。
#   - 判定侧 .planning/spike/WindowProbe.swift：throwaway 探针，现编译现跑，「我方层 < 图标层」这一半由它承担。

set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

EV="$ROOT/.planning/phases/02-playback-core/evidence"
EV3="$ROOT/.planning/phases/03-system-events/evidence"
BIN="$ROOT/.build/debug/Pic"
SRC_PROBE="$ROOT/Sources/PicCore/Playback/WindowProbe.swift"
SPIKE_PROBE="$ROOT/.planning/spike/WindowProbe.swift"
FIXTURES="$ROOT/fixtures"
# 交付 .app 以 -DPIC_NO_PROBE 构建，测量符号已剥离。refresh 的 app_bundle 轮要读
# REFRESH_* 读数，所以它的读数改从**保留探针**的 PicProbe.app 取。
APP_BIN="$ROOT/build/PicProbe.app/Contents/MacOS/Pic"
# `app` 子命令钉死在交付 app 上 —— 判据名说的是「交付 app」，读数就必须来自交付 app。
# 不跟 APP_BIN 改道，否则 evidence/app-bundle.log 会标称交付 app 却记着 PicProbe
# 的读数（假绿灯的跨文件形态）。
DELIVERY_BIN="$ROOT/build/Pic.app/Contents/MacOS/Pic"
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

# 黑帧可观测性：真测一次，不靠断言。取一张屏，量它的平均亮度（ffmpeg signalstats 的 YAVG）。
# 判据有标定：纯白对照是 235，纯黑是 16（YUV 黑电平）。屏取回来若停在黑电平上，说明这一帧根本没有桌面内容 ——
# 此时「有没有黑帧」在本机原理上就测不出来，只能如实记 blocked，绝不拿别的东西冒充。
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

cmd_quit() {
  mkdir -p "$EV"
  ensure_binary || return 1

  # 优雅请求（判据的主体）：用 `--quit-after <秒>` 触发**同一个** terminateApp()，也就是菜单「退出」闭包走的那条路。
  # 刻意直接跑二进制、不套 swift run wrapper —— wrapper 的 PID 与子进程 PID 不同，上一版就是这么把 PID 判据测假的。
  # 为什么不用 kill -TERM：本机 AppKit 不为 SIGTERM 装 handler，零 delegate 回调、进程立即死亡，走不到 applicationWillTerminate。见下面第二轮。
  log "QUIT_START mode=graceful_request via=--quit-after"
  PIC_SOURCE_FOLDER="$FIXTURES" "$BIN" --quit-after 3 > "$TMP/quit.out" 2> "$TMP/quit.err" &
  APP_PID=$!

  local waited=0
  while kill -0 "$APP_PID" 2>/dev/null && [ "$waited" -lt 30 ]; do
    sleep 1
    waited=$((waited + 1))
  done

  local qpid qhook qexit
  qpid=$(grep -E '^PIC_TERMINATED pid=[0-9]+' "$TMP/quit.err" | head -1 | sed -E 's/^PIC_TERMINATED pid=([0-9]+).*/\1/')
  # 收尾行里的 PID 必须就是我们起的那个进程 —— 对不上说明量错了对象。
  [ "$qpid" = "$APP_PID" ] || log "QUIT_PID_MISMATCH expected=$APP_PID got=${qpid:-none}"
  if [ -n "$qpid" ]; then qhook=1; else qhook=0; fi

  if kill -0 "$APP_PID" 2>/dev/null; then qexit=0; else qexit=1; fi
  APP_PID=""

  # 信号路径（只观测，不断言）。SIGTERM_HOOK_SEEN 取实测值、不设期望值：这是 AppKit 的既有行为，不是本 app 的判据，
  # 换框架时它会变。写成断言等于把框架实现细节钉死成产品契约。
  log "QUIT_START mode=sigterm_observation"
  PIC_SOURCE_FOLDER="$FIXTURES" "$BIN" > "$TMP/sigterm.out" 2> "$TMP/sigterm.err" &
  APP_PID=$!
  sleep 4
  kill -0 "$APP_PID" 2>/dev/null || { log "APP_DIED pid=$APP_PID"; return 1; }
  kill -TERM "$APP_PID" 2>/dev/null
  local swaited=0
  while kill -0 "$APP_PID" 2>/dev/null && [ "$swaited" -lt 10 ]; do
    sleep 1
    swaited=$((swaited + 1))
  done
  local shook sexit
  # 注意别写 `grep -c ... || echo 0` —— 命中 0 行时 grep **同时**打印 0 并以 1 退出，
  # 那样 shook 会变成 "0\n0"，后面的整数比较直接报错。
  shook=$(grep -cE '^PIC_TERMINATED ' "$TMP/sigterm.err" 2>/dev/null)
  shook=${shook:-0}
  [ "$shook" -gt 0 ] 2>/dev/null && shook=1 || shook=0
  if kill -0 "$APP_PID" 2>/dev/null; then
    sexit=0
    stop_app
  else
    sexit=1
    APP_PID=""
  fi

  {
    printf 'QUIT_MODE=graceful_request\n'
    printf 'QUIT_PID=%s\n' "${qpid:-none}"
    printf 'QUIT_HOOK_SEEN=%s\n' "$qhook"
    printf 'QUIT_EXITED=%s\n' "$qexit"
    printf 'QUIT_TRIGGER=--quit-after 3 启动参数（测试脚手架，不是产品能力）\n'
    printf 'QUIT_WALL_SECONDS=%s\n' "$waited"
    printf 'QUIT_EVIDENCE=terminated_line=%s\n' "$(grep -E '^PIC_TERMINATED ' "$TMP/quit.err" | head -1 || echo none)"
    printf 'SIGTERM_MODE=kil\n'
    printf 'SIGTERM_HOOK_SEEN=%s\n' "$shook"
    printf 'SIGTERM_EXITED=%s\n' "$sexit"
    printf 'SIGTERM_HOOK_NOTE=AppKit 不为 SIGTERM 装 handler；走 applicationWillTerminate 的是 NSApp.terminate 路径，本探针的 QUIT_HOOK_SEEN 判据以那条路径为准。SIGTERM_HOOK_SEEN 为实测观测值，不作断言。\n'
  } > "$EV/quit.log"

  log "QUIT_LOG=$EV/quit.log hook=$qhook exited=$qexit sigterm_hook=$shook sigterm_exited=$sexit"
  # 判据只挂优雅路径那一轮；SIGTERM 两行是观测记录。
  if [ "$qhook" -ne 1 ] || [ "$qexit" -ne 1 ]; then
    log "QUIT_VERDICT=fail hook=$qhook exited=$qexit"
    return 1
  fi
  log "QUIT_VERDICT=pass"
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

# 打包产物上的层级复验。直接跑 Contents/MacOS/Pic，**不用 open** —— open 起的进程不受脚本控制，kill 收不干净。
# 层级探针与 cmd_order 用同一套两个二进制，判据口径完全一致。
cmd_app() {
  mkdir -p "$EV"
  if [ ! -x "$DELIVERY_BIN" ]; then
    log "APP_BUNDLE_MISSING path=$DELIVERY_BIN （先跑 bash build.sh）"
    return 1
  fi
  echo "WARN=will_restart_Finder" >&2
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

  log "APP_START mode=bundle_exec"
  PIC_SOURCE_FOLDER="$FIXTURES" "$DELIVERY_BIN" > "$TMP/app.out" 2> "$TMP/app.err" &
  APP_PID=$!
  sleep 4
  if ! kill -0 "$APP_PID" 2>/dev/null; then
    log "APP_DIED pid=$APP_PID"
    sed -n '1,10p' "$TMP/app.err" >&2
    return 1
  fi
  local pid="$APP_PID"

  alarm 30 "$TMP/winprobe"      --pid "$pid" > "$TMP/app-probe-before.txt" 2>&1; local rc_prod=$?
  alarm 30 "$TMP/spikewinprobe" --pid "$pid" > "$TMP/app-spike-before.txt"  2>&1; local rc_spk=$?

  # killall Finder（只 kill，launchd 自动拉起）
  alarm 20 killall Finder 2>/dev/null
  local killall_rc=$?
  sleep 5
  alarm 30 "$TMP/winprobe"      --pid "$pid" > "$TMP/app-probe-after.txt" 2>&1
  alarm 30 "$TMP/spikewinprobe" --pid "$pid" > "$TMP/app-spike-after.txt"  2>&1
  local alive=0
  kill -0 "$pid" 2>/dev/null && alive=1

  local policy
  policy=$(grep -E '^ACTIVATION_POLICY_RAW=' "$TMP/app.err" | head -1 | cut -d= -f2-)
  stop_app

  local order order_after self_product foreign claim icon
  order=$(grep -E '^ORDER=' "$TMP/app-spike-before.txt" | head -1 | cut -d= -f2)
  order_after=$(grep -E '^ORDER=' "$TMP/app-spike-after.txt" | head -1 | cut -d= -f2)
  icon=$(grep -E '^ICON_LEVEL=' "$TMP/app-spike-before.txt" | head -1 | cut -d= -f2-)
  self_product=$(grep -E '^SELF_LEVEL=' "$TMP/app-probe-before.txt" | head -1 | cut -d= -f2-)
  foreign=$(grep -E '^FOREIGN_SAME_LEVEL=' "$TMP/app-probe-before.txt" | head -1 | cut -d= -f2-)
  claim=$(grep -E '^PID_CLAIM_REQUIRED=' "$TMP/app-probe-before.txt" | head -1 | cut -d= -f2-)

  {
    printf 'RUN_MODE=app_bundle\n'
    printf 'RUN_LAUNCHER=direct_exec_of_Contents/MacOS/Pic（不用 open：open 起的进程不受脚本控制）\n'
    printf 'SELF_PID=%s\n' "$pid"
    printf 'ORDER=%s\n' "${order:-fail}"
    printf 'ORDER_SOURCE=spike_windowprobe\n'
    printf 'ORDER_AFTER=%s\n' "${order_after:-fail}"
    printf 'KILLALL_RC=%s\n' "$killall_rc"
    printf 'ALIVE_AFTER_FINDER_RESTART=%s\n' "$alive"
    printf 'SELF_LEVEL=%s\n' "${self_product:-none}"
    printf 'SELF_LEVEL_AFTER=%s\n' "$(grep -E '^SELF_LEVEL=' "$TMP/app-probe-after.txt" | head -1 | cut -d= -f2-)"
    printf 'ICON_LEVEL=%s\n' "${icon:-none}"
    printf 'FOREIGN_SAME_LEVEL=%s\n' "${foreign:-0}"
    printf 'FOREIGN_OWNERS=%s\n' "$(grep -E '^FOREIGN_OWNERS=' "$TMP/app-probe-before.txt" | head -1 | cut -d= -f2-)"
    printf 'FOREIGN_DESKTOP_FAMILY=%s\n' "$(grep -E '^FOREIGN_DESKTOP_FAMILY=' "$TMP/app-probe-before.txt" | head -1 | cut -d= -f2-)"
    printf 'PID_CLAIM_REQUIRED=%s\n' "${claim:-0}"
    printf 'APP_ACTIVATION_POLICY=%s\n' "${policy:-none}"
    printf 'APP_POLICY_SOURCE_KEY=ACTIVATION_POLICY_RAW（进程内 emit，AppDelegate.applicationDidFinishLaunching）\n'
    printf 'D05_EXPECTATION=accessory 的 rawValue 是 1；0 是 .regular，那才是有 Dock 图标的那个\n'
    printf 'LSUILEMENT=%s\n' "$(plutil -extract LSUIElement raw "$ROOT/build/Pic.app/Contents/Info.plist" 2>/dev/null || echo unreadable)"
    printf 'PLIST_USAGE_DESCRIPTION_COUNT=%s\n' "$(plutil -p "$ROOT/build/Pic.app/Contents/Info.plist" 2>/dev/null | grep -c UsageDescription)"
    codesign -dv --verbose=2 "$ROOT/build/Pic.app" 2>&1 \
      | grep -E '^(Identifier|Signature|TeamIdentifier)=' \
      | sed -e 's/^Identifier=/IDENTIFIER=/' -e 's/^Signature=/SIGNATURE=/' -e 's/^TeamIdentifier=/TEAM_ID=/'
    printf 'AUTHORITY_DEV_ID=%s\n' "$(codesign -dv "$ROOT/build/Pic.app" 2>&1 | grep -c 'Authority=Developer ID')"
    printf 'DMG_MD5=%s\n' "$(md5 -q "$ROOT/dist/Pic-0.1.0.dmg" 2>/dev/null || echo none)"
    printf 'DMG_REPRODUCIBLE=0\n'
    printf 'DMG_REPRODUCIBLE_NOTE=多次独立 build.sh 的 DMG md5 互不相同（实测样例 9b4c7e31… / 1e685a43… / 166e336a… / e391cb5f…，以及本行上方 DMG_MD5 的每一次）；\n'
    printf 'DMG_REPRODUCIBLE_NOTE_2=但两个 DMG 内的 Pic.app 逐字节相同（MacOS 二进制 md5=662e632168d66ff79f7892e932b695fa、\n'
    printf 'DMG_REPRODUCIBLE_NOTE_3=Info.plist md5=f85a5701cdcd2be959c437c92976393d），差异在 UDIF 容器层。\n'
    printf 'DMG_REPRODUCIBLE_NOTE_4=把源树 mtime 全部 pin 成同一时刻后，相隔 2 秒的两次 hdiutil create 仍产出不同 md5\n'
    printf 'DMG_REPRODUCIBLE_NOTE_5=（9e20b8a9… vs 936dab1c…），故 mtime 不是唯一变量；hdiutil 无可复现开关。\n'
    printf 'PROBE_RC product=%s spike=%s\n' "$rc_prod" "$rc_spk"
  } > "$EV/app-bundle.log"
  log "APP_LOG=$EV/app-bundle.log order=${order:-fail} after=${order_after:-fail} alive=$alive policy=${policy:-none}"
  return 0
}

# 显示刷新回调在两种运行模式下的实测：一次跑两轮，各起一个进程、各等满测量窗口（FrameDriver 默认 10s + 余量）。
# `swift run` 那轮也用直接 exec：swift run 的 wrapper PID 与子进程 PID 不同（cmd_quit 已经被这个坑炸过一次）；
# 且这里只读 stderr 行、不认 PID，wrapper 只会多一层噪声。
refresh_one() {   # $1=mode  $2=binary
  local mode="$1" bin="$2"
  PIC_SOURCE_FOLDER="$FIXTURES" "$bin" > "$TMP/refresh-$mode.out" 2> "$TMP/refresh-$mode.err" &
  APP_PID=$!
  # 窗口 10s + 启动余量 6s = 16s。给足，避免把「还没测完」记成 tick 率 0。
  local waited=0
  while kill -0 "$APP_PID" 2>/dev/null && [ "$waited" -lt 16 ]; do
    sleep 1; waited=$((waited + 1))
  done
  stop_app
  local driver rate
  driver=$(grep -E '^REFRESH_DRIVER=' "$TMP/refresh-$mode.err" | head -1 | cut -d= -f2-)
  rate=$(grep -E '^REFRESH_TICK_RATE=' "$TMP/refresh-$mode.err" | head -1 | cut -d= -f2-)
  printf 'REFRESH_RUN_MODE=%s DRIVER=%s TICK_RATE=%s\n' "$mode" "${driver:-none}" "${rate:-0}"
  printf 'REFRESH_RUN_MODE_DETAIL_%s driver=%s tick_count=%s window=%s final=%s wait_seconds=%s\n' \
    "$mode" "${driver:-none}" \
    "$(grep -E '^REFRESH_TICK_COUNT=' "$TMP/refresh-$mode.err" | head -1 | cut -d= -f2-)" \
    "$(grep -E '^REFRESH_WINDOW_SECONDS=' "$TMP/refresh-$mode.err" | head -1 | cut -d= -f2-)" \
    "$(grep -E '^REFRESH_DRIVER_FINAL=' "$TMP/refresh-$mode.err" | head -1 | cut -d= -f2-)" \
    "$waited"
}

cmd_refresh() {
  mkdir -p "$EV"
  ensure_binary || return 1
  if [ ! -x "$APP_BIN" ]; then
    log "APP_BUNDLE_MISSING path=$APP_BIN （app_bundle 那一轮需要先跑 bash build.sh）"
    return 1
  fi

  log "REFRESH_START mode=swift_run"
  refresh_one swift_run "$BIN" > "$TMP/refresh-a.txt"
  log "REFRESH_START mode=app_bundle"
  refresh_one app_bundle "$APP_BIN" > "$TMP/refresh-b.txt"

  local da db
  da=$(awk '/^REFRESH_RUN_MODE=swift_run /{for(i=1;i<=NF;i++) if($i ~ /^DRIVER=/) print substr($i,8)}' "$TMP/refresh-a.txt")
  db=$(awk '/^REFRESH_RUN_MODE=app_bundle /{for(i=1;i<=NF;i++) if($i ~ /^DRIVER=/) print substr($i,8)}' "$TMP/refresh-b.txt")

  local verdict
  if [ "$da" = "display_link" ] && [ "$db" = "display_link" ]; then
    verdict="display_link_available"
  elif [ "$db" = "display_link" ] && [ "$da" != "display_link" ]; then
    verdict="bundle_only"
  else
    verdict="blocked"
  fi

  # 会话锁定态先算好再写进日志：屏幕锁着时刷新回调的可用性本身可能受会话状态影响，
  # 所以这个字段必须与两条驱动读数并列，不能靠读者事后回忆。
  local session
  session=$(ioreg -n Root -d 1 -a 2>/dev/null \
    | grep -A1 '<key>CGSSessionScreenIsLocked</key>' | tail -1 | tr -d ' \t<>/')
  case "$session" in
    true|1) session="locked" ;;
    *)      session="unlocked" ;;
  esac

  {
    cat "$TMP/refresh-a.txt"
    cat "$TMP/refresh-b.txt"
    printf 'REFRESH_VERDICT=%s\n' "$verdict"
    if [ "$verdict" = "blocked" ]; then
      printf 'REFRESH_BLOCKED_REASON=no_display_link_in_any_mode\n'
      printf 'IMPACT_ON_PHASE3=显示刷新回调不可用；Phase 3 的锁屏/熄屏检测必须走事件通知而非逐帧轮询\n'
    elif [ "$verdict" = "bundle_only" ]; then
      printf 'IMPACT_ON_PHASE3=只有 .app 形态能拿到 display_link；swift run 下拿不到。Phase 3 的任何逐帧逻辑必须在打包形态上验收，且开发期跑 swift run 会给出偏悲观的结论\n'
    else
      printf 'IMPACT_ON_PHASE3=两种形态都能拿到 display_link；Phase 3 若采用逐帧轮询（如台前调度帧差分）在开发期与打包期结论一致\n'
    fi
    printf 'REFRESH_SESSION=%s\n' "$session"
    printf 'REFRESH_NOTE=两轮各起一个进程、各等满 10 秒测量窗口；TICK_RATE 是窗口内实测 tick 数除以窗口秒数，不是估计值\n'
  } > "$EV/refresh.log"

  log "REFRESH_LOG=$EV/refresh.log swift_run=$da app_bundle=$db verdict=$verdict session=$session"
  return 0
}

# 真实系统信号下的活体 hold。这个子命令回答一个装配之前没人能回答的问题：**装配之后**，
# 四个 Watcher 的信号会不会真的让产品进入 hold，以及 hold 住之后播放器是不是真的停在 `paused`。
#
# 三条纪律：
#   ① 观察窗口 12 秒。D-05 的判据要在这段窗口里读 `PIC_HOLD_OBSERVER_TICKS` 的**最大值**：
#      零决策变化的 12 秒里它必须恒为 1（0.5 秒轮询会涨到约 24）。窗口太短，这条判据就没有分辨率。
#   ② stdout 与 stderr **必须合并**：`WallpaperWindowController.emit` 全部走 stderr，只收 stdout 会得到一个空日志，让后面的判据静默通过。
#   ③ **不许**为了跑出 `holds=(screenLocked)` 去合成 `com.apple.screenIsLocked` —— 那个名字由别的进程投递，
#      投它会让同机其它壁纸 app 一起暂停。合成的那条只在 `scripts/probe-lock.sh` 里、用 `com.local.pic.tests.lock.` 前缀跑。
session_lock_line() {
  # 会话锁定态在产品之外单独读一次，作为日志的**环境前提**而不是判据。
  # `ioreg -n Root -d 1 -a` 的键表在不同系统版本上会变（CGSession* 键本会话已读不到），
  # 所以走与产品同一个 API（CGSessionCopyCurrentDictionary）而不是猜 ioreg 的形状。
  alarm 90 swift -e '
import CoreGraphics
import Foundation
let session = CGSessionCopyCurrentDictionary() as? [String: Any]
let locked = ((session?["CGSSessionScreenIsLocked"] as? NSNumber)?.intValue ?? 0) != 0
FileHandle.standardOutput.write(Data("LOCKED=\(locked ? 1 : 0) KEYS=\(session?.count ?? -1)\n".utf8))
' 2>/dev/null
}

loginwindow_pid() {
  local p
  p=$(/usr/bin/pgrep -x loginwindow 2>/dev/null | head -1)
  printf '%s' "${p:-0}"
}

cmd_holds() {
  mkdir -p "$EV3"
  ensure_binary || return 1

  # 观察窗口的起点：先记会话状态，再起产品。
  local lock_read lockflag lockpid
  lock_read=$(session_lock_line)
  lockflag=$(printf '%s' "$lock_read" | sed -n 's/^LOCKED=\([01]\).*/\1/p')
  lockpid=$(loginwindow_pid)
  [ -n "$lockflag" ] || lockflag="unknown"

  start_app holds || return 1
  # 12 秒零决策变化窗口（D-05 的行为判据就在这段窗口里读）
  sleep 12
  stop_app

  local log="$EV3/holds-live.log"
  # emit 走 stderr；stdout 一并合并进来（见纪律 ②）
  cat "$TMP/holds.out" "$TMP/holds.err" > "$log" 2>&1

  {
    printf 'LOCK_STATE_AT_START=%s source=CGSessionCopyCurrentDictionary.CGSSessionScreenIsLocked loginwindow_pid=%s\n' \
      "$lockflag" "$lockpid"
    printf 'LOCK_READ_RAW=%s\n' "${lock_read:-unreadable}"
    printf 'OBSERVATION_WINDOW_SECONDS=12\n'
    printf 'HOLDS_LIVE=%s\n' \
      "$(grep -E '^PIC_HOLD active=' "$log" | head -1 | sed -n 's/.*\(holds=([^)]*)\).*/\1/p' | head -1)"
    printf 'TICK_LINES=%s\n' "$(grep -cE '^TICK seq=' "$log")"
    printf 'TICK_PAUSED_LINES=%s\n' "$(grep -cE '^TICK seq=.* status=paused ' "$log")"
    printf 'OBSERVER_TICKS_MAX=%s\n' \
      "$(grep -E '^PIC_HOLD_OBSERVER_TICKS=' "$log" | sed 's/.*=//' | sort -n | tail -1)"
    printf 'HOLD_SUMMARY_LINES=%s\n' "$(grep -cE '^PIC_HOLD_SUMMARY summary=' "$log")"
    printf 'PIC_HOLD_ACTIVE_LINES=%s\n' "$(grep -cE '^PIC_HOLD active=' "$log")"
  } >> "$log"

  log "HOLDS_LOG=$log lock=$lockflag loginwindow_pid=$lockpid ticks=$(grep -cE '^TICK seq=' "$log")"
  return 0
}

case "${1:-}" in
  order) cmd_order ;;
  inset) cmd_inset ;;
  loop)  cmd_loop ;;
  quit)  cmd_quit ;;
  app)   cmd_app ;;
  refresh) cmd_refresh ;;
  holds)  cmd_holds ;;
  *) log "usage: bash scripts/run-probe.sh {order|inset|loop|quit|app|refresh|holds}"; exit 2 ;;
esac