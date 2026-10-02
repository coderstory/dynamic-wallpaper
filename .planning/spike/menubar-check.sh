#!/bin/bash
# menubar-check.sh —— Phase 01 plan 01-02 证据采集：MenuBarExtra 主路线 + NSStatusItem 退路各跑 4 秒。
#
# 每个变体采集三个字段：
#   alive=<0|1>    启动后 sleep 4 仍然存活
#   policy=<n>     setActivationPolicy(.accessory) 之后的生效策略 rawValue
#   layer0=<n>     本进程 kCGWindowLayer==0 的窗口数（按 kCGWindowOwnerPID 认领）
#
# 「无 Dock 图标」的口径：由 policy 与 layer0 两个可自动核对字段表达，**不是肉眼确认**。
# 本机 screencapture 无录屏权限（plan 01-01 实测返回占位图），本脚本不做任何截图断言。
# 引用结论时必须连同日志里 NOTE= 那一行一起引用。
#
# policy 的期望值不是写死的 0：0 是 NSApplication.ActivationPolicy.regular（有 Dock 图标）。
# accessory 的 rawValue 由探针当场实测出来写进 ACTIVATION_POLICY_RAW，再作为 EXPECT_POLICY 使用。
#
# 本机没有 timeout 命令（编排器实测 command not found），限时统一用 perl -e 'alarm N; exec @ARGV'。
# 只读窗口元数据 + 在菜单栏插入常驻项；不改系统设置/壁纸/登录项。探针失败不中止（不用 set -e）。

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT"

OUT="$ROOT/.planning/spike/out"
LOG="$OUT/menubar.log"
mkdir -p "$OUT"

TMP="$(mktemp -d)"
RUN_PID=""

cleanup() {
  if [ -n "$RUN_PID" ]; then kill "$RUN_PID" 2>/dev/null || true; fi
  rm -rf "$TMP"
  return 0
}
trap cleanup EXIT INT TERM

# ---- 1. 编译两个变体 ----
swiftc -parse-as-library -target arm64-apple-macosx15.0 \
  -o "$OUT/menubarspike" "$ROOT/.planning/spike/MenuBarSpike.swift" 2> "$OUT/compile-menubarspike.txt"
RC_SPIKE=$?
swiftc -parse-as-library -target arm64-apple-macosx15.0 \
  -o "$OUT/menubarfallback" "$ROOT/.planning/spike/MenuBarFallback.swift" 2> "$OUT/compile-menubarfallback.txt"
RC_FALLBACK=$?
if [ "$RC_SPIKE" -ne 0 ] || [ "$RC_FALLBACK" -ne 0 ]; then
  echo "COMPILE spike=$RC_SPIKE fallback=$RC_FALLBACK" >&2
  echo "NOTE=layer0_windows_zero_is_the_automatable_proxy_for_no_dock_icon" > "$LOG"
  echo "MENUBAR_VERDICT=failed" >> "$LOG"
  exit 1
fi

# ---- 2. 内联 layer-0 窗口探针（只数本 pid 的 layer 0 窗口，不认 layer 数值也不认 owner 名）----
# 本机常驻另外 4 个同类动态壁纸 app，其中至少一个停在同一桌面层级，用 owner 名筛选会认错窗口。
cat > "$TMP/layer0.swift" <<'SW'
import AppKit
import CoreGraphics

var target = 0
var i = 1
let args = CommandLine.arguments
while i < args.count {
    if args[i] == "--pid", i + 1 < args.count, let parsed = Int(args[i + 1]) {
        target = parsed
        i += 2
    } else {
        i += 1
    }
}

let raw = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
var layer0 = 0
for entry in raw {
    guard let layer = entry[kCGWindowLayer as String] as? NSNumber,
          let pid = entry[kCGWindowOwnerPID as String] as? NSNumber else { continue }
    if pid.intValue == target && layer.intValue == 0 { layer0 += 1 }
}

print("LAYER0_WINDOWS=\(layer0)")
print("POLICY_REGULAR=\(NSApplication.ActivationPolicy.regular.rawValue)")
print("POLICY_ACCESSORY=\(NSApplication.ActivationPolicy.accessory.rawValue)")
print("POLICY_PROHIBITED=\(NSApplication.ActivationPolicy.prohibited.rawValue)")
SW

swiftc -target arm64-apple-macosx15.0 -o "$TMP/layer0" "$TMP/layer0.swift" 2> "$OUT/compile-layer0.txt"
RC_PROBE=$?
if [ "$RC_PROBE" -ne 0 ]; then
  echo "PROBE_COMPILE_FAILED rc=$RC_PROBE" >&2
  echo "NOTE=layer0_windows_zero_is_the_automatable_proxy_for_no_dock_icon" > "$LOG"
  echo "MENUBAR_VERDICT=failed" >> "$LOG"
  exit 1
fi

# ---- 2b. 探针阳性对照：同一个探针必须能看见「本进程自建的 layer 0 窗口」 ----
# 没有这一步，layer0=0 可能只是探针瞎了而不是事实。
# 对照进程同样用 .accessory 策略，不会在 Dock 留任何东西（只多一扇 60x60 无边框窗口 3 秒）。
cat > "$TMP/control.swift" <<'SW'
import AppKit

@main
final class ControlMain: NSObject {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        _ = app.setActivationPolicy(.accessory)
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 60, height: 60),
                         styleMask: .borderless, backing: .buffered, defer: false)
        w.level = .normal
        w.orderFrontRegardless()
        app.run()
    }
}
SW

CONTROL_LAYER0="skipped"
CONTROL_NOTE="control_not_run"
if swiftc -parse-as-library -target arm64-apple-macosx15.0 -o "$TMP/control" "$TMP/control.swift" 2> "$OUT/compile-control.txt"; then
  perl -e 'alarm 20; exec @ARGV' "$TMP/control" > /dev/null 2>&1 &
  RUN_PID=$!
  sleep 3
  if kill -0 "$RUN_PID" 2>/dev/null; then
    perl -e 'alarm 20; exec @ARGV' "$TMP/layer0" --pid "$RUN_PID" > "$TMP/probe-control.txt" 2>&1
    CONTROL_LAYER0=$(sed -n 's/^LAYER0_WINDOWS=//p' "$TMP/probe-control.txt" | head -1)
    [ -n "$CONTROL_LAYER0" ] || CONTROL_LAYER0="none"
    if [ "$CONTROL_LAYER0" = "0" ]; then
      CONTROL_NOTE="control_saw_no_layer0_window_probe_discounted"
    else
      CONTROL_NOTE="control_ok_probe_sees_layer0_windows"
    fi
  else
    CONTROL_NOTE="control_process_died"
  fi
  kill "$RUN_PID" 2>/dev/null
  wait "$RUN_PID" 2>/dev/null
  RUN_PID=""
else
  CONTROL_NOTE="control_compile_failed"
fi

# ---- 3. 跑一个变体：启动 → sleep 4 → 探针 → kill ----
# 输出：ALIVE / LAYER0 / PIC 三个变量由调用方按变体名取值（bash 无局部变量）
ALIVE=""; LAYER0=""; PIC=""
run_variant() {
  V="$1"
  MLOG="$OUT/menu-$V.log"
  : > "$MLOG"
  perl -e 'alarm 30; exec @ARGV' "$OUT/$V" > "$MLOG" 2>&1 &
  RUN_PID=$!
  sleep 4
  if kill -0 "$RUN_PID" 2>/dev/null; then A=1; else A=0; fi
  L="none"
  if [ "$A" = "1" ]; then
    perl -e 'alarm 20; exec @ARGV' "$TMP/layer0" --pid "$RUN_PID" > "$TMP/probe-$V.txt" 2>&1
    L=$(sed -n 's/^LAYER0_WINDOWS=//p' "$TMP/probe-$V.txt" | head -1)
    [ -n "$L" ] || L="none"
  else
    : > "$TMP/probe-$V.txt"
  fi
  kill "$RUN_PID" 2>/dev/null
  wait "$RUN_PID" 2>/dev/null
  RUN_PID=""
  P=$(grep -m1 '^PIC_MENU ' "$MLOG" 2>/dev/null)
  [ -n "$P" ] || P="PIC_MENU_absent"
  ALIVE="$A"; LAYER0="$L"; PIC="$P"
}

run_variant menubarspike
ALIVE_SPIKE="$ALIVE"; LAYER0_SPIKE="$LAYER0"; PIC_SPIKE="$PIC"
run_variant menubarfallback
ALIVE_FALLBACK="$ALIVE"; LAYER0_FALLBACK="$LAYER0"; PIC_FALLBACK="$PIC"

# ---- 4. 判定口径 ----
POL_REG=$(sed -n 's/^POLICY_REGULAR=//p' "$TMP/probe-menubarspike.txt" | head -1)
POL_ACC=$(sed -n 's/^POLICY_ACCESSORY=//p' "$TMP/probe-menubarspike.txt" | head -1)
POL_PRO=$(sed -n 's/^POLICY_PROHIBITED=//p' "$TMP/probe-menubarspike.txt" | head -1)
EXPECT_POLICY="$POL_ACC"
[ -n "$EXPECT_POLICY" ] || EXPECT_POLICY=1

# 变体通过 = 存活 且 layer0==0 且 PIC_MENU 行带 policy=<实测 accessory rawValue> 与 ok=true
variant_pass() {
  [ "$1" = "1" ] || return 1
  [ "$2" = "0" ] || return 1
  case "$3" in
    *"policy=$EXPECT_POLICY ok=true"*) return 0 ;;
    *) return 1 ;;
  esac
}

if variant_pass "$ALIVE_SPIKE" "$LAYER0_SPIKE" "$PIC_SPIKE"; then
  VERDICT="ok"
elif variant_pass "$ALIVE_FALLBACK" "$LAYER0_FALLBACK" "$PIC_FALLBACK"; then
  VERDICT="fallback"
else
  VERDICT="failed"
fi

# ---- 5. 落日志 ----
{
  echo "MACHINE=$(sw_vers -productVersion) $(uname -m)"
  echo "ACTIVATION_POLICY_RAW regular=$POL_REG accessory=$POL_ACC prohibited=$POL_PRO"
  echo "EXPECT_POLICY=$EXPECT_POLICY"
  echo "NOTE=layer0_windows_zero_is_the_automatable_proxy_for_no_dock_icon"
  echo "NOTE2=dock_absence_is_not_visually_confirmed_this_spike_makes_no_screenshot_claim"
  echo "PLAN_DEVIATION=policy_expected_value_is_measured_accessory_rawvalue_not_the_0_written_in_the_plan"
  echo "CONTROL_REGULARWINDOW layer0=$CONTROL_LAYER0"
  echo "CONTROL_NOTE=$CONTROL_NOTE"
  echo "VARIANT=menubarspike alive=$ALIVE_SPIKE layer0=$LAYER0_SPIKE"
  echo "VARIANT_PIC_MENU=menubarspike $PIC_SPIKE"
  echo "VARIANT=menubarfallback alive=$ALIVE_FALLBACK layer0=$LAYER0_FALLBACK"
  echo "VARIANT_PIC_MENU=menubarfallback $PIC_FALLBACK"
  echo "MENUBAR_VERDICT=$VERDICT"
} | tee "$LOG"

# ---- 6. 退出码 ----
if [ "$VERDICT" = "failed" ]; then exit 1; fi
exit 0
