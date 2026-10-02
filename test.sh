#!/usr/bin/env bash
# 能自动化的验证都在这。需要人眼/真机的（全屏暂停、桌面层级、耗电）不在此列。
cd "$(dirname "$0")"
PASS=0; FAIL=0
ok(){ printf "  ✅ %s\n" "$1"; PASS=$((PASS+1)); }
no(){ printf "  ❌ %s\n     %s\n" "$1" "${2:-}"; FAIL=$((FAIL+1)); }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

echo "── 工具链 ─────────────────────────────"
xcode-select -p | grep -q Xcode.app && ok "Xcode 已选中" || no "Xcode 未选中" "跑 sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
command -v create-dmg >/dev/null && ok "create-dmg 可用 ($(create-dmg --version 2>&1|head -1))" || no "create-dmg 缺失" "brew install create-dmg"
command -v ffmpeg >/dev/null && ok "ffmpeg 可用 ($(ffmpeg -version 2>&1|head -1|cut -d' ' -f1-3))" || no "ffmpeg 缺失" "转码功能会降级；brew install ffmpeg 在 macOS 27 上会失败，用静态二进制"

echo ""
echo "── 编译 ───────────────────────────────"
SRC=".planning/spike/SettingsSpike.swift .planning/spike/Render.swift"
if swiftc -typecheck -target arm64-apple-macosx15.0 $SRC 2>"$TMP/tc.log"; then
  ok "spike 编译通过"
else
  no "spike 编译失败" "$(grep error: "$TMP/tc.log" | head -2)"
fi

echo ""
echo "── 关键 API 可用性（编译期验证）─────────"
probe(){ # $1=名称 $2=源码
  echo "$2" > "$TMP/p.swift"
  swiftc -typecheck -target arm64-apple-macosx15.0 "$TMP/p.swift" >/dev/null 2>&1 \
    && ok "$1" || no "$1" "编译不过"
}
probe "CGWindowLevelForKey(.desktopWindow) 可编译" 'import AppKit
let _ = CGWindowLevelForKey(.desktopWindow)'
probe "NSWindow.level 可赋值" 'import AppKit
let w = NSWindow(contentRect: .init(x:0,y:0,width:1,height:1), styleMask: .borderless, backing: .buffered, defer: false)
w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))'
probe "AVQueuePlayer + AVPlayerLooper 可用" 'import AVFoundation
let it = AVPlayerItem(url: URL(fileURLWithPath: "/dev/null"))
let q = AVQueuePlayer()
let _ = AVPlayerLooper(player: q, templateItem: it)'
probe "SMAppService 可用（开机自启）" 'import ServiceManagement
let _ = try? SMAppService.mainApp.register()'
probe "自定义 ToggleStyle 可用" 'import SwiftUI
struct T: ToggleStyle { func makeBody(configuration: Configuration) -> some View { configuration.label } }'

echo ""
echo "── 运行时值 ───────────────────────────"
cat > "$TMP/v.swift" <<'SW'
import AppKit
let lvl = CGWindowLevelForKey(.desktopWindow)
let icon = CGWindowLevelForKey(.desktopIconWindow)
let saver = CGWindowLevelForKey(.screenSaverWindow)
print("\(lvl)|\(icon)|\(icon - lvl)|\(saver)")
SW
swiftc -target arm64-apple-macosx15.0 -o "$TMP/v" "$TMP/v.swift" 2>/dev/null \
  && { RES=$("$TMP/v"); IFS='|' read -r L I D S <<< "$RES"
       [ "$L" = "-2147483623" ] && ok "desktopWindow = $L" || no "desktopWindow 值不符" "得到 $L，期望 -2147483623"
       [ "$D" = "20" ] && ok "与图标层差 $D 级" || no "层级差不符" "得到 $D，期望 20"
       [ "$S" = "1000" ] && ok "screenSaverWindow = $S" || no "screenSaverWindow 值不符" "得到 $S，期望 1000"; } \
  || no "运行时探针编译失败" ""

echo ""
echo "── spike 门禁探针 ─────────────────────"
# 锁住 .planning/phases/01-spike/01-VERDICT.md「层级写法定案」段里最容易写错的三条：
#   ① MenuBarExtra 不可用时的退路仍可编译  ② 桌面层 borderless 窗口可挂 AVPlayerLayer
#   ③ 桌面层级实测值 CGWindowLevelForKey(.desktopWindow)（上面运行时值段已锁）
# 全部无 GUI、无提权、无副作用（只 swiftc -typecheck）。
probe "NSStatusItem 退路可编译" 'import AppKit
let i = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
_ = i'
probe "isOpaque=true 的 borderless NSWindow 可挂 AVPlayerLayer" 'import AppKit
import AVFoundation
let w = NSWindow(contentRect: .init(x: 0, y: 0, width: 1, height: 1), styleMask: [.borderless], backing: .buffered, defer: false)
w.isOpaque = true
w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
w.contentView!.layer?.addSublayer(AVPlayerLayer())'

echo ""
echo "── 渲染 ───────────────────────────────"
swiftc -O -parse-as-library -target arm64-apple-macosx15.0 -o "$TMP/render" $SRC 2>/dev/null \
  && "$TMP/render" "$TMP/out.png" >/dev/null 2>&1 \
  && [ -s "$TMP/out.png" ] \
  && ok "设置窗渲染成功 ($(stat -f%z "$TMP/out.png") bytes)" \
  || no "设置窗渲染失败" ""

echo ""
echo "───────────────────────────────────────"
printf "  通过 %d  失败 %d\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] && echo "  ✅ 全绿" || echo "  ❌ 有失败项"
exit "$FAIL"
