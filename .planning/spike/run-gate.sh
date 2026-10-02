#!/bin/bash
# run-gate.sh —— Phase 01 门禁 01 的证据采集，一条命令跑完。
#
# 固定流程：编译 → 启动 spike → 探测 → killall Finder → 复探 → 截图
#           → 停 spike → D-08 两条对照路线（硬编码 level / CGSSession 私有框架）
#           → 汇总成 .planning/spike/out/gate-01.log
#
# 只读窗口元数据 + 在自己的窗口里画东西 + 重启 Finder。不改任何系统设置/壁纸/登录项。
# 探针失败不中止（不用 set -e），失败原样写进日志。

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT"

OUT="$ROOT/.planning/spike/out"
mkdir -p "$OUT"

SPIKE_PID=""
VARIANT_PID=""
VARIANT_DIR=""

cleanup() {
  if [ -n "$VARIANT_PID" ]; then kill "$VARIANT_PID" 2>/dev/null || true; fi
  if [ -n "$SPIKE_PID" ]; then kill "$SPIKE_PID" 2>/dev/null || true; fi
  # 硬编码 level 对照变体只活在 TMPDIR，脚本结束即销毁，绝不进仓库
  if [ -n "$VARIANT_DIR" ]; then rm -rf "$VARIANT_DIR"; fi
  return 0
}
trap cleanup EXIT INT TERM

# ---- 1. .gitignore 幂等追加 ----
grep -qxF '.planning/spike/out/' "$ROOT/.gitignore" 2>/dev/null \
  || printf '.planning/spike/out/\n' >> "$ROOT/.gitignore"

# ---- 2. 编译 ----
swiftc -parse-as-library -target arm64-apple-macosx15.0 \
  -o "$OUT/wallpaperspike" "$ROOT/.planning/spike/WallpaperSpike.swift" 2> "$OUT/compile-spike.txt"
RC_SPIKE=$?
swiftc -parse-as-library -target arm64-apple-macosx15.0 \
  -o "$OUT/windowprobe" "$ROOT/.planning/spike/WindowProbe.swift" 2> "$OUT/compile-probe.txt"
RC_PROBE=$?
if [ "$RC_SPIKE" -ne 0 ] || [ "$RC_PROBE" -ne 0 ]; then
  echo "COMPILE_FAILED spike=$RC_SPIKE probe=$RC_PROBE" >&2
  exit 3
fi

# ---- 3. 启动 spike ----
echo "WARN=will_restart_Finder" >&2
"$OUT/wallpaperspike" --mode color > "$OUT/spike-stdout.txt" 2> "$OUT/spike-stderr.txt" &
SPIKE_PID=$!
sleep 3
if ! kill -0 "$SPIKE_PID" 2>/dev/null; then
  echo "SPIKE_ALIVE=0" >&2
  exit 2
fi

# ---- 4. 探测（Finder 仍在） ----
"$OUT/windowprobe" --pid "$SPIKE_PID" > "$OUT/probe-before.txt" 2>&1

# ---- 5. killall Finder（只 kill，launchd 自动拉起） ----
killall Finder 2>/dev/null
KILLALL_RC=$?
sleep 5

# ---- 6. 复探 ----
"$OUT/windowprobe" --pid "$SPIKE_PID" > "$OUT/probe-after.txt" 2>&1

# ---- 7. 截图（本机无 timeout 命令，用 perl alarm 限时 20s 防权限弹窗挂死） ----
rm -f "$OUT/gate-01.png"
perl -e 'alarm 20; exec @ARGV' /usr/sbin/screencapture -x "$OUT/gate-01.png" 2> "$OUT/screencapture-stderr.txt"
SC_RC=$?
SC_BYTES=0
if [ -f "$OUT/gate-01.png" ]; then SC_BYTES=$(stat -f%z "$OUT/gate-01.png"); fi

# ---- 8. 停 spike ----
kill "$SPIKE_PID" 2>/dev/null || true
wait "$SPIKE_PID" 2>/dev/null || true
SPIKE_PID=""

# ---- 8b. 对照截图：spike 已停、屏幕内容必然与刚才不同，再拍一张。
# 两张若逐字节相同，说明这台机器的 screencapture 没有屏幕录制权限（返回固定占位图）——
# 实测 2026-10-03：即使强制一个全屏洋红 normal 层窗口在前，抓图仍与空屏逐字节相同。
# 那种情况下 PNG 不含任何桌面画面信息，绝不能当「画面可见」的证据（D-02 信号③ 未取得）。
sleep 2
rm -f "$OUT/gate-01-control.png"
perl -e 'alarm 20; exec @ARGV' /usr/sbin/screencapture -x "$OUT/gate-01-control.png" 2> "$OUT/screencapture-control-stderr.txt"
SC_CTRL_RC=$?
SCREENSHOT_MD5="none"
SCREENSHOT_CONTROL_MD5="none"
if [ -f "$OUT/gate-01.png" ]; then SCREENSHOT_MD5=$(md5 -q "$OUT/gate-01.png" || true); fi
if [ -f "$OUT/gate-01-control.png" ]; then SCREENSHOT_CONTROL_MD5=$(md5 -q "$OUT/gate-01-control.png" || true); fi
if [ -n "$SCREENSHOT_MD5" ] && [ "$SCREENSHOT_MD5" = "$SCREENSHOT_CONTROL_MD5" ]; then
  SCREENSHOT_EVIDENT=0
  SCREENSHOT_LINE="SCREENSHOT=blocked reason=png_identical_to_control_capture"
elif [ "$SC_RC" -ne 0 ]; then
  SCREENSHOT_EVIDENT=0
  SCREENSHOT_LINE="SCREENSHOT=blocked reason=screencapture_timeout_or_denied rc=$SC_RC"
elif [ ! -f "$OUT/gate-01.png" ]; then
  SCREENSHOT_EVIDENT=0
  SCREENSHOT_LINE="SCREENSHOT=blocked reason=file_missing rc=$SC_RC"
elif [ "$SC_BYTES" -eq 0 ]; then
  SCREENSHOT_EVIDENT=0
  SCREENSHOT_LINE="SCREENSHOT=blocked reason=zero_bytes rc=$SC_RC"
else
  SCREENSHOT_EVIDENT=1
  SCREENSHOT_LINE="SCREENSHOT=ok bytes=$SC_BYTES"
fi

# ---- 9. D-08 路线 D：硬编码 WindowServer level 数字（一次性对照，不进仓库） ----
VARIANT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/picd08.XXXXXX")"
cat > "$VARIANT_DIR/HardcodedLevelVariant.swift" <<'VARIANT_SRC'
import AppKit
// D-08 路线 D 对照件：唯一与产品代码的差别就是把层级写成字面量。
@main struct HardcodedLevelVariant {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        guard let s = NSScreen.main else { exit(4) }
        let w = NSWindow(contentRect: s.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        w.contentView = NSView(frame: s.frame)
        w.level = NSWindow.Level(rawValue: -2147483623)
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        w.isOpaque = true
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.backgroundColor = .red
        w.orderFrontRegardless()
        print("VARIANT_PID=\(ProcessInfo.processInfo.processIdentifier)")
        fflush(stdout)
        app.run()
    }
}
VARIANT_SRC
swiftc -parse-as-library -target arm64-apple-macosx15.0 \
  -o "$VARIANT_DIR/variant" "$VARIANT_DIR/HardcodedLevelVariant.swift" 2> "$VARIANT_DIR/compile.txt"
RC_VARIANT=$?
D08_D_LEVEL="none"
if [ "$RC_VARIANT" -eq 0 ]; then
  "$VARIANT_DIR/variant" > "$VARIANT_DIR/variant-stdout.txt" 2>&1 &
  VARIANT_PID=$!
  sleep 3
  "$OUT/windowprobe" --pid "$VARIANT_PID" > "$VARIANT_DIR/variant-probe.txt" 2>&1
  D08_D_LEVEL=$(grep -m1 '^SELF_LEVEL=' "$VARIANT_DIR/variant-probe.txt" | sed 's/^SELF_LEVEL=//' || true)
  kill "$VARIANT_PID" 2>/dev/null || true
  VARIANT_PID=""
  if [ -z "$D08_D_LEVEL" ]; then D08_D_LEVEL="none"; fi
fi

# ---- 10. D-08 路线 C：CGSSession 私有框架（静态证据：链接了哪些 framework） ----
# 「私有」按路径判定：只有 /System/Library/Frameworks/ 下的才算公开系统框架，
# 其余（PrivateFrameworks / @rpath / /usr/local / /opt / /Library）一律计入私有。
FW_SPIKE=$(otool -L "$OUT/wallpaperspike" | awk '$1 ~ /\.framework\// {print $1}')
FW_PROBE=$(otool -L "$OUT/windowprobe" | awk '$1 ~ /\.framework\// {print $1}')
N_SPIKE=$(printf '%s\n' "$FW_SPIKE" | grep -c . || true)
N_PROBE=$(printf '%s\n' "$FW_PROBE" | grep -c . || true)
if [ "$N_PROBE" -gt "$N_SPIKE" ]; then
  D08_C_BIN="windowprobe"; D08_C_LIST="$FW_PROBE"; D08_C_TOTAL="$N_PROBE"
else
  D08_C_BIN="wallpaperspike"; D08_C_LIST="$FW_SPIKE"; D08_C_TOTAL="$N_SPIKE"
fi
D08_C_PRIVATE=$(printf '%s\n' "$D08_C_LIST" | grep -v '^/System/Library/Frameworks/' | grep -c . || true)
D08_C_CGSS=$(printf '%s\n' "$D08_C_LIST" | grep -c 'CGSSession' || true)
D08_C_PATHS=$(printf '%s\n' "$D08_C_LIST" | tr '\n' ' ')

# ---- 11. 汇总 ----
ORDER=$(grep -m1 '^ORDER=' "$OUT/probe-before.txt" | sed 's/^ORDER=//' || true)
REASON=$(grep -m1 '^REASON=' "$OUT/probe-before.txt" | sed 's/^REASON=//' || true)
SELF_B=$(grep -m1 '^SELF_LEVEL=' "$OUT/probe-before.txt" | sed 's/^SELF_LEVEL=//' || true)
ICON_B=$(grep -m1 '^ICON_LEVEL=' "$OUT/probe-before.txt" | sed 's/^ICON_LEVEL=//' || true)
SELF_A=$(grep -m1 '^SELF_LEVEL=' "$OUT/probe-after.txt" | sed 's/^SELF_LEVEL=//' || true)
ICON_A=$(grep -m1 '^ICON_LEVEL=' "$OUT/probe-after.txt" | sed 's/^ICON_LEVEL=//' || true)
ORDER_A=$(grep -m1 '^ORDER=' "$OUT/probe-after.txt" | sed 's/^ORDER=//' || true)

# Finder 重启存活 = 我方窗口仍在桌面层 且 Finder 图标层窗口仍被枚举到
if [ "$SELF_A" = "-2147483623" ] && [ -n "$ICON_A" ] && [ "$ICON_A" != "none" ]; then
  FINDER_RESTART_ALIVE=1
else
  FINDER_RESTART_ALIVE=0
fi

# 画面在动的客观证据：帧号每 tick 递增（stdout 只打一次 PIC_GATE，故取 stderr 的 TICK 流）
FRAME_FIRST=$(grep -o 'frame=[0-9][0-9]*' "$OUT/spike-stderr.txt" | head -1 | sed 's/frame=//' || true)
FRAME_LAST=$(grep -o 'frame=[0-9][0-9]*' "$OUT/spike-stderr.txt" | tail -1 | sed 's/frame=//' || true)
if [ -n "$FRAME_FIRST" ] && [ -n "$FRAME_LAST" ] && [ "$FRAME_LAST" -gt "$FRAME_FIRST" ]; then
  FRAME_ADVANCED=1
else
  FRAME_ADVANCED=0
fi
FRAME_DRIVER=$(grep -m1 '^DRIVER=' "$OUT/spike-stderr.txt" | sed 's/^DRIVER=//' || true)
if [ -z "$FRAME_DRIVER" ]; then FRAME_DRIVER="displaylink"; fi
GATE_LEVEL=$(grep -m1 '^PIC_GATE' "$OUT/spike-stdout.txt" | sed -n 's/.*level=\(-*[0-9][0-9]*\).*/\1/p' || true)
if [ -z "$GATE_LEVEL" ]; then GATE_LEVEL="none"; fi

[ -z "$ORDER" ] && ORDER="none"
[ -z "$REASON" ] && REASON="none"
[ -z "$SELF_B" ] && SELF_B="none"
[ -z "$ICON_B" ] && ICON_B="none"
[ -z "$SELF_A" ] && SELF_A="none"
[ -z "$ICON_A" ] && ICON_A="none"
[ -z "$ORDER_A" ] && ORDER_A="none"
[ -z "$FRAME_FIRST" ] && FRAME_FIRST="none"
[ -z "$FRAME_LAST" ] && FRAME_LAST="none"

{
  echo "GATE=01"
  echo "ORDER=$ORDER"
  echo "ORDER_REASON=$REASON"
  echo "ORDER_AFTER=$ORDER_A"
  echo "SELF_LEVEL=$SELF_B"
  echo "ICON_LEVEL=$ICON_B"
  echo "SELF_LEVEL_AFTER=$SELF_A"
  echo "ICON_LEVEL_AFTER=$ICON_A"
  echo "WINDOW_LEVEL_REPORTED=$GATE_LEVEL"
  echo "KILLALL_RC=$KILLALL_RC"
  echo "SPIKE_ALIVE=1"
  echo "$SCREENSHOT_LINE"
  echo "SCREENSHOT_BYTES=$SC_BYTES"
  echo "SCREENSHOT_EVIDENT=$SCREENSHOT_EVIDENT"
  echo "SCREENSHOT_MD5=$SCREENSHOT_MD5"
  echo "SCREENSHOT_CONTROL_MD5=$SCREENSHOT_CONTROL_MD5"
  echo "FINDER_RESTART_ALIVE=$FINDER_RESTART_ALIVE"
  echo "FRAME_ADVANCED=$FRAME_ADVANCED"
  echo "FRAME_FIRST=$FRAME_FIRST"
  echo "FRAME_LAST=$FRAME_LAST"
  echo "FRAME_DRIVER=$FRAME_DRIVER"
  echo "D08_ROUTE_D_HARDCODED_LEVEL=$D08_D_LEVEL"
  echo "D08_ROUTE_C_BINARY=$D08_C_BIN"
  echo "D08_ROUTE_C_FRAMEWORK_TOTAL=$D08_C_TOTAL"
  echo "D08_ROUTE_C_PRIVATE_FRAMEWORK_COUNT=$D08_C_PRIVATE"
  echo "D08_ROUTE_C_CGSSESSION_LINKED=$D08_C_CGSS"
  echo "D08_ROUTE_C_FRAMEWORK_PATHS=${D08_C_PATHS% }"
} | tee "$OUT/gate-01.log"

if [ "$ORDER" = "ok" ] && [ "$FINDER_RESTART_ALIVE" = "1" ]; then
  exit 0
fi
exit 1
