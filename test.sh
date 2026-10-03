#!/usr/bin/env bash
# 能自动化的验证都在这。需要人眼/真机的（全屏暂停、桌面层级、耗电）不在此列。
cd "$(dirname "$0")"

# 本脚本自己把 LC_CTYPE 固定成 C。原因（实测，非推断）：
# 在 UTF-8 locale 下跑本脚本，输出会被**按字节偏移**丢掉 2 字节，且丢点与脚本内容无关 ——
# 同一份脚本在 C locale 下输出逐字节有效。最小复现：33 行中文填充 + 一行
# `ok "…（Button 行数 $MB = ForEach 行数 $MF）"`，UTF-8 locale 下 `1）` 变成 `\xbc\x89`
# （丢了 `31 EF` 两个字节），C locale 下不丢。
# 后果很实际：输出里只要有一个非法字节，`grep` 就会中止整份文件，
# 于是「test.sh 的输出能不能被 grep」这件事变得不可靠 —— 判据会假红。
# 固定 C locale 只影响脚本自身的字节处理，不改变任何一条判据的语义。
export LC_ALL=C

PASS=0; FAIL=0; SKIP=0
ok(){ printf "  ✅ %s\n" "$1"; PASS=$((PASS+1)); }
no(){ printf "  ❌ %s\n     %s\n" "$1" "${2:-}"; FAIL=$((FAIL+1)); }
# 干净 clone 里没有 build/ 与 dist/。这几项不是「不通过」，是「没东西可查」——
# 判成 no 会让一台没跑过 build.sh 的机器永远红，对交付没有任何信息量。
skip(){ printf "  ⏭️ %s\n     %s\n" "$1" "${2:-}"; SKIP=$((SKIP+1)); }
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
echo "── 产品代码 ───────────────────────────"
# Plan 02-02 T3：把「产品代码长成该长的样子」变成每次都自动重验的判据。
#
# ⚠️ 两条纪律，踩过就记住：
#   ① 扫描对象**一律是 Sources/ 或产品源码文件**。判据持有字面量是判据的定义，
#      绝不允许反过来扫 test.sh 自己 —— 那样这条检查会恒红。
#   ② 下面每个 token 在本文件里都以字面量出现（它们就是 grep 模式）。
#      源码侧计数前先剥掉行注释与块注释：把 token 写进注释会让门禁自己作废。

# 剥注释后在指定目录里数某个字面量。目录不存在时返回 -1，让检查项报红而不是读 stdin 挂住。
src_count(){
  local token="$1" dir="${2:-Sources}"
  [ -d "$dir" ] || { echo "-1"; return; }
  find "$dir" -name '*.swift' -exec grep -h -v \
      -e '^[[:space:]]*//' -e '^[[:space:]]*/\*' -e '^[[:space:]]*\*' -e '^[[:space:]]*\*/' {} + \
    | grep -c -F -- "$token" || true
}

if swift build --package-path . > "$TMP/build.log" 2>&1; then
  ok "产品代码 swift build 通过"
else
  no "产品代码 swift build 失败" "$(grep -E 'error:' "$TMP/build.log" | head -2)"
fi

if swift test --package-path . > "$TMP/test.log" 2>&1; then
  TESTN=$(grep -oE 'Executed [0-9]+ tests, with 0 failures' "$TMP/test.log" | tail -1 | grep -oE '[0-9]+' | head -1)
  if [ -n "${TESTN:-}" ]; then
    ok "产品单测全绿（${TESTN} 项）"
  else
    no "产品单测未跑出通过汇总" "$(grep -E 'Executed|error:' "$TMP/test.log" | tail -2)"
  fi
else
  no "产品单测失败" "$(grep -E 'error:|failed' "$TMP/test.log" | head -2)"
fi

N=$(src_count '-21474836')
[ "$N" = "0" ] && ok "Sources/ 无硬编码桌面层级字面量（D-04）" || no "Sources/ 出现硬编码层级字面量" "剥注释后计数 = $N，期望 0"

N=$(src_count 'desktopIconWindow')
[ "$N" = "0" ] && ok "Sources/ 不出现被禁用的图标层级标识符（D-04）" || no "Sources/ 出现图标层级标识符" "剥注释后计数 = $N，期望 0"

N=$(src_count 'import AVFoundation' 'Sources/PicCore/State')
[ "$N" = "0" ] && ok "State/ 零 AVFoundation 依赖（ARCHITECTURE §9）" || no "State/ 依赖了 AVFoundation" "剥注释后计数 = $N，期望 0"

N=$(src_count 'absoluteString')
[ "$N" = "0" ] && ok "Sources/ 不用 URL 的字符串形式做存在性检查（D-14 / Pitfall 5）" || no "Sources/ 出现 URL 字符串形式" "剥注释后计数 = $N，期望 0"

# SYS-02（Phase 2 锁定的不变量）：窗口不做 Space 级差异化处理。
# ⚠️ Phase 3 / Plan 03-02 起口径由「token 出现 0 次」改为下面两条排除式判据 ——
# D-02 要求 FullscreenDetector 订阅 activeSpaceDidChangeNotification 作为几何之外的
# 判别信号，那是「订阅通知做检测」，不是「按 Space 做差异化行为」。见
# .planning/WINDOWS.md 的 W-2026-10-03-17 · deviation。

# ⚠️ 下面两条的 `no()` 文案**必须带上 `ok()` 的同一句判据名**：
# 下游 plan（03-05）会在**变异后的红日志**里 `grep -c '❌ 产品代码零 Space 身份读取'`，
# 靠这个字符串确认「是这一条红了」。失败文案写成另一句就查不到 —— 03-01 首跑时正是这个原因。
# （另一侧：绿日志里的 `ok()` 行带 ✅ 而非 ❌，不会自中）
# ① 壁纸窗口仍走系统默认行为：collectionBehavior 四项原样，不加任何 Space 相关位。
N=$(src_count 'fullScreenAuxiliary' 'Sources/PicCore/Render')
[ "$N" -ge 1 ] 2>/dev/null && ok "壁纸窗口仍走系统默认 Space 行为（collectionBehavior 未被加塞）" \
  || no "壁纸窗口仍走系统默认 Space 行为（collectionBehavior 被加塞）" "Sources/PicCore/Render 内 fullScreenAuxiliary 计数 = $N，期望 ≥ 1"

# ② 产品代码里没有任何「按 Space 身份分支」的痕迹：订阅变更通知拿不到、也不需要
#    Space 的**身份**，真要按 Space 做差异化就必须去读 Space 序号。
#    （这条才是 SYS-02「不做差异化处理」的直接代理；订阅动作本身被 ① 与本条共同约束。）
N=$(src_count 'kCGSSpace')
M=$(src_count 'CGSSetActiveSpace')
[ "$N$M" = "00" ] && ok "产品代码零 Space 身份读取（不做差异化处理）" \
  || no "产品代码零 Space 身份读取（不做差异化处理）" "kCGSSpace=$N CGSSetActiveSpace=$M，期望全 0"

N=$(src_count 'kCGWindowName')
[ "$N" = "0" ] && ok "Sources/ 不读窗口标题（T-02-03 隐私）" || no "Sources/ 读了窗口标题键" "剥注释后计数 = $N，期望 0"

# ---- Plan 03-01 T2：System/ 分层 + D-05 事件驱动的判据 ----
# System/ 目录不存在时 src_count 返回 -1，本项报红。这是**故意的**：
# 目录不存在就等于四个 Watcher 一个都没建，D-09 的分层无从谈起。
# ⚠️ 新增判据的 `no()` 文案**必须带上 `ok()` 的同一句判据名**。下游 plan
# （03-05 的 `<automated>`）会在**变异后的红日志**里 `grep -c 'System/ 四个 Watcher 零 AVFoundation'`，
# 靠这个字符串确认「是这一条红了」。失败文案写成另一句话就查不到了。

N=$(src_count 'import AVFoundation' 'Sources/PicCore/System')
[ "$N" = "0" ] && ok "System/ 四个 Watcher 零 AVFoundation（D-09 单向流）" \
  || no "System/ 四个 Watcher 零 AVFoundation —— System/ 依赖了播放框架" "剥注释后计数 = $N，期望 0（目录不存在时为 -1）"

# D-05 的源码侧锚点：0.5 秒轮询已删，事件驱动的观察者在位。
# ⚠️ 这两条是**源码检查，不是 D-05 的行为证明** —— D-05 的行为判据在
# 03-05 的 `run-probe.sh holds`：12 秒零决策变化的窗口里 PIC_HOLD_OBSERVER_TICKS
# 的最大值必须恰好为 1。**不要**拿「12 秒里 PIC_HOLD 行数 == 1」当判据：
# observeHold() 的去重门让它在合规与违规两种实现下结果相同，那是空判（D-07）。
N=$(src_count 'Timer(timeInterval: 0.5' 'Sources/PicApp')
[ "$N" = "0" ] && ok "AppDelegate 零 0.5 秒 hold 轮询（D-05）" \
  || no "AppDelegate 零 0.5 秒 hold 轮询 —— 轮询仍在" "剥注释后计数 = $N，期望 0"

N=$(src_count 'withObservationTracking' 'Sources/PicApp')
[ "$N" -ge 1 ] 2>/dev/null && ok "AppDelegate 用 withObservationTracking 驱动 PIC_HOLD（D-05）" \
  || no "AppDelegate 用 withObservationTracking 驱动 PIC_HOLD —— observeHold 未由观察驱动" "剥注释后计数 = $N，期望 ≥ 1"

# PIC_HOLD 的 active=/reason= 必须从 decision.activeReasons 派生。
# 此前 reason 在两个分支里都写死成手动暂停，active=1 reason=screenLocked 结构上打不出来；
# 两个分支合并成一个格式串后，这条字面量在全文件恰好 1 处。
N=$(src_count 'PIC_HOLD active=' 'Sources/PicApp')
[ "$N" = "1" ] && ok "PIC_HOLD active= 恰好一处，active/reason 同源于一个格式串（D-12）" \
  || no "PIC_HOLD active= 恰好一处，active/reason 同源于一个格式串 —— 格式串散落到多处" "剥注释后计数 = $N，期望恰好 1"

N=$(src_count 'reason=manualPause' 'Sources/PicApp')
[ "$N" = "0" ] && ok "PIC_HOLD 的 reason= 不再写死成手动暂停（D-12）" \
  || no "PIC_HOLD 的 reason= 不再写死成手动暂停 —— 仍写死" "剥注释后计数 = $N，期望 0"

# D-05 唯一不空的机器判据本身：它必须留在代码里。删了它，03-05 的行为判据无处可读。
N=$(src_count 'PIC_HOLD_OBSERVER_TICKS=' 'Sources/PicApp')
[ "$N" = "1" ] && ok "PIC_HOLD_OBSERVER_TICKS 恰好一处（D-05 的机器判据）" \
  || no "PIC_HOLD_OBSERVER_TICKS 恰好一处 —— 缺失或多处" "剥注释后计数 = $N，期望恰好 1"

# ---- Plan 02-03 T1/T3 的菜单侧判据 ----
MENU="Sources/PicApp/App/MenuContentView.swift"

# 菜单项必须只由 MenuItemID.allCases 遍历产出。哨兵单测（MenuBarModelTests）能成立
# 全靠这一条 —— 有人「顺手再加一个 Button 显示状态」而不改模型，那条隐私断言就失效了。
if [ -f "$MENU" ]; then
  MB=$(grep -c 'Button(' "$MENU")
  MF=$(grep -c 'ForEach(MenuItemID.allCases' "$MENU")
  if [ "$MF" -eq 1 ] && [ "$MB" -eq "$MF" ]; then
    ok "菜单只由 MenuItemID.allCases 遍历渲染（Button 行数 $MB = ForEach 行数 $MF）"
  else
    no "菜单渲染脱离 MenuItemID.allCases" "Button( 行数=$MB，ForEach(MenuItemID.allCases 行数=$MF，期望 1 且相等"
  fi
else
  no "菜单源文件缺失" "$MENU 不存在"
fi

# 隐私源码判据：菜单结构体内部不得出现任何取文件名的 API。
# 检查范围收窄到 `struct MenuContentView` 的行区间 —— 设置窗骨架
# （SettingsSkeletonView，同文件）要显示源目录路径，那是 MENUBAR-08 允许的例外。
# 刻意**不**把范围缩到「扫不到东西」的形式：sed 区间若为空，下面这条会恒绿。
PN=$(sed -n '/struct MenuContentView/,/^}/p' "$MENU" 2>/dev/null \
  | grep -v -e '^[[:space:]]*//' -e '^[[:space:]]*/\*' -e '^[[:space:]]*\*' -e '^[[:space:]]*\*/' \
  | grep -cE 'lastPathComponent|fileName|absoluteString')
[ "$PN" = "0" ] && ok "菜单结构体内零取文件名 API（MENUBAR-08）" \
  || no "菜单结构体内出现取文件名 API" "剥注释后计数 = $PN，期望 0（检查范围 $MENU 的 MenuContentView 行区间）"

# T-02-08：菜单动作绕过仲裁器直连 AVPlayer 会让 Phase 3 的 veto 集合失效。
# 范围是**菜单文件**，不是 Sources/PicApp/ 整个目录 —— 威胁边界是「菜单动作」这条。
# AppDelegate 的 startWallpaper() 在起播时有一处 player.player.play()：那不是菜单动作，
# 且发生在任何 watcher 存在之前（Phase 3 才接 watcher），所以不归这条判据管。
# （该处另记在 .planning/WINDOWS.md，Phase 3 接 watcher 时要一并复核。）
NP=$({ grep -c 'player.pause()' "$MENU" 2>/dev/null || true; grep -c 'player.play()' "$MENU" 2>/dev/null || true; } | awk '{s+=$1} END{print s+0}')
[ "$NP" = "0" ] && ok "菜单侧零 AVPlayer 直连（D-11 单向流 / T-02-08）" \
  || no "菜单侧直连了播放器" "$MENU 内 player.pause()+player.play() 计数 = $NP，期望 0"

# 结束进程的全局调用必须只有一个落点，否则两处将来必然会漂移（T-02-09 的同类纪律）。
NT=$(src_count 'NSApp.terminate')
[ "$NT" = "1" ] && ok "结束进程的全局调用全仓唯一落点（AppDelegate）" \
  || no "结束进程的调用散落到多处" "剥注释后 Sources/ 内计数 = $NT，期望恰好 1"

# ---- Plan 03-01 T2：TEST-01 的行为判据 ----
# 不扫源码，直接跑用例：幂集恰 64 组 + 「锁屏中退出全屏不恢复播放」的反例。
# 上一条已经跑过全量 `swift test`，这里再单跑一次是为了失败时能把这一族的名字指出来。
if swift test --package-path . --filter HoldArbiterTests > "$TMP/arbiter.log" 2>&1; then
  AN=$(grep -oE 'Executed [0-9]+ tests, with 0 failures' "$TMP/arbiter.log" | tail -1 | grep -oE '^[A-Za-z]* [0-9]+' | grep -oE '[0-9]+')
  ok "仲裁器用例全绿（幂集 64 组 + 锁屏中退出全屏不恢复，${AN:-?} 项）"
else
  no "仲裁器用例失败" "$(grep -E "error:|XCTAssert.*failed|failed -" "$TMP/arbiter.log" | head -2)"
fi

echo ""
echo "── 渲染 ───────────────────────────────"
swiftc -O -parse-as-library -target arm64-apple-macosx15.0 -o "$TMP/render" $SRC 2>/dev/null \
  && "$TMP/render" "$TMP/out.png" >/dev/null 2>&1 \
  && [ -s "$TMP/out.png" ] \
  && ok "设置窗渲染成功 ($(stat -f%z "$TMP/out.png") bytes)" \
  || no "设置窗渲染失败" ""

echo ""
echo "── 打包产物 ───────────────────────────"
# Plan 02-04 T3：build.sh 的产出本身也要被验，不能只验源码。
# 五项全是本地命令，不起 GUI 进程。干净 clone 下走 skip 分支（跳过 N 项），
# 退出码仍是 0 —— test.sh 必须能在没打过包的机器上跑完。
if [ ! -d build ]; then
  skip ".app 二进制非空（build/ 不存在）"      "跑 bash build.sh 后再验"
  skip ".dmg 非空（dist/ 不存在）"             "跑 bash build.sh 后再验"
  skip "Info.plist 的 LSUIElement 为 true"     "build/Pic.app 不存在"
  skip "Info.plist 无任何 UsageDescription"    "build/Pic.app 不存在"
  skip "ad-hoc 签名且非 Developer ID"          "build/Pic.app 不存在"
else
  APPB="build/Pic.app"
  test -s "$APPB/Contents/MacOS/Pic" \
    && ok ".app 二进制非空（$(stat -f%z "$APPB/Contents/MacOS/Pic") bytes）" \
    || no ".app 二进制缺失或为空" "$APPB/Contents/MacOS/Pic"
  ls dist/Pic-*.dmg >/dev/null 2>&1 && test -s "$(ls dist/Pic-*.dmg | head -1)" \
    && ok ".dmg 非空（$(stat -f%z "$(ls dist/Pic-*.dmg | head -1)") bytes）" \
    || no "DMG 缺失或为空" "dist/Pic-*.dmg"
  # plist 布尔在 plutil 里渲染成 true 不是 1；写成 1 会把正确值判成失败。
  [ "$(plutil -extract LSUIElement raw "$APPB/Contents/Info.plist" 2>/dev/null)" = "true" ] \
    && ok "Info.plist 的 LSUIElement 为 true（Dock 无图标的打包期落点）" \
    || no "LSUIElement 不是 true" "得到 [$(plutil -extract LSUIElement raw "$APPB/Contents/Info.plist" 2>/dev/null)]，plist 布尔读出来是字面量 true"
  NU=$(plutil -p "$APPB/Contents/Info.plist" 2>/dev/null | grep -c UsageDescription)
  [ "$NU" = "0" ] && ok "Info.plist 无任何 UsageDescription（T-02-11）" \
    || no "Info.plist 出现权限声明" "UsageDescription 计数 = $NU，期望 0"
  CS=$(codesign -dv "$APPB" 2>&1)
  if echo "$CS" | grep -q 'Signature=adhoc' && ! echo "$CS" | grep -q 'Authority=Developer ID'; then
    ok "ad-hoc 签名且无 Developer ID 授权"
  else
    no "签名形态不符" "$(echo "$CS" | grep -E 'Signature=|Authority=' | tr '\n' ' ')"
  fi
fi

echo ""
echo "───────────────────────────────────────"
printf "  通过 %d  失败 %d  跳过 %d\n" "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ] && echo "  ✅ 全绿" || echo "  ❌ 有失败项"
exit "$FAIL"
