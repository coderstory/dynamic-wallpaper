#!/usr/bin/env bash
# 能自动化的验证都在这。需要人眼/真机的（全屏暂停、桌面层级、耗电）不在此列。
#
# ⚠️ 措辞纪律（各段只留一行引用，不重复）：每条 `no()` 的判据名必须**逐字**等于
#    同一条 `ok()` 的判据名，红绿只靠 ✅ / ❌ 前缀区分。下游会在**变异后的红日志**
#    里 `grep -c '❌ <判据名>'` 确认「是这一条红了」—— 失败文案写成另一句就查不到。
#    判据一个都不放宽，只改文案。
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
command -v ffmpeg >/dev/null && ok "ffmpeg 可用（command -v 探测；版本查询已按 ffmpeg 红线移除）" || no "ffmpeg 可用" "ffmpeg 缺失；转码功能会降级；brew install ffmpeg 在 macOS 27 上会失败，用静态二进制"

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
# 把「产品代码长成该长的样子」变成每次都自动重验的判据。
#
# ⚠️ 两条纪律，踩过就记住：
#   ① 扫描对象**一律是 Sources/ 或产品源码文件**。判据持有字面量是判据的定义，
#      绝不允许反过来扫 test.sh 自己 —— 那样这条检查会恒红。
#   ② 下面每个 token 在本文件里都以字面量出现（它们就是 grep 模式）。
#      源码侧计数前先剥掉行注释与块注释：把 token 写进注释会让门禁自己作废。

# 剥注释后在指定目录（或单个 .swift 文件）里数某个字面量。
# 路径不存在时返回 -1，让检查项报红而不是读 stdin 挂住。
src_count(){
  local token="$1" dir="${2:-Sources}"
  [ -e "$dir" ] || { echo "-1"; return; }
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

# 已锁定的不变量：窗口不做 Space 级差异化处理。
# ⚠️ 口径由「token 出现 0 次」改为下面两条排除式判据 ——
# FullscreenDetector 订阅 activeSpaceDidChangeNotification 作为几何之外的
# 判别信号，那是「订阅通知做检测」，不是「按 Space 做差异化行为」。见
# .planning/WINDOWS.md 的 deviation 条目。

# ⚠️ 下面两条的措辞纪律见文件头（判据名逐字相同，红绿靠 ✅ / ❌ 区分）。
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

# ---- System/ 分层 + 事件驱动的判据 ----
# System/ 目录不存在时 src_count 返回 -1，本项报红。这是**故意的**：
# 目录不存在就等于四个 Watcher 一个都没建，分层无从谈起。
# ⚠️ 措辞纪律见文件头。

N=$(src_count 'import AVFoundation' 'Sources/PicCore/System')
[ "$N" = "0" ] && ok "System/ 四个 Watcher 零 AVFoundation（D-09 单向流）" \
  || no "System/ 四个 Watcher 零 AVFoundation —— System/ 依赖了播放框架" "剥注释后计数 = $N，期望 0（目录不存在时为 -1）"

# 事件驱动的源码侧锚点：0.5 秒轮询已删，观察者在位。
# ⚠️ 这两条是**源码检查，不是行为证明** —— 行为判据在 `run-probe.sh holds`：
# 12 秒零决策变化的窗口里 PIC_HOLD_OBSERVER_TICKS 的最大值必须恰好为 1。
# **不要**拿「12 秒里 PIC_HOLD 行数 == 1」当判据：observeHold() 的去重门让它在
# 合规与违规两种实现下结果相同，那是空判。
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

# 唯一不空的机器判据本身：它必须留在代码里。删了它，行为判据无处可读。
N=$(src_count 'PIC_HOLD_OBSERVER_TICKS=' 'Sources/PicApp')
[ "$N" = "1" ] && ok "PIC_HOLD_OBSERVER_TICKS 恰好一处（D-05 的机器判据）" \
  || no "PIC_HOLD_OBSERVER_TICKS 恰好一处 —— 缺失或多处" "剥注释后计数 = $N，期望恰好 1"

# ---- 菜单侧判据 ----
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

# 菜单动作绕过仲裁器直连 AVPlayer 会让 veto 集合失效。
# 范围是**菜单文件**，不是 Sources/PicApp/ 整个目录 —— 威胁边界是「菜单动作」这条。
# AppDelegate 的 startWallpaper() 在起播时有一处 player.player.play()：那不是菜单动作，
# 且发生在任何 watcher 存在之前（watcher 是后来才接的），所以不归这条判据管。
# （该处另记在 .planning/WINDOWS.md，接 watcher 时要一并复核。）
NP=$({ grep -c 'player.pause()' "$MENU" 2>/dev/null || true; grep -c 'player.play()' "$MENU" 2>/dev/null || true; } | awk '{s+=$1} END{print s+0}')
[ "$NP" = "0" ] && ok "菜单侧零 AVPlayer 直连（D-11 单向流 / T-02-08）" \
  || no "菜单侧直连了播放器" "$MENU 内 player.pause()+player.play() 计数 = $NP，期望 0"

# 结束进程的全局调用必须只有一个落点，否则两处将来必然会漂移。
NT=$(src_count 'NSApp.terminate')
[ "$NT" = "1" ] && ok "结束进程的全局调用全仓唯一落点（AppDelegate）" \
  || no "结束进程的调用散落到多处" "剥注释后 Sources/ 内计数 = $NT，期望恰好 1"

# ---- 幂集与 veto 的行为判据 ----
# 不扫源码，直接跑用例：幂集恰 64 组 + 「锁屏中退出全屏不恢复播放」的反例。
# 上一条已经跑过全量 `swift test`，这里再单跑一次是为了失败时能把这一族的名字指出来。
if swift test --package-path . --filter HoldArbiterTests > "$TMP/arbiter.log" 2>&1; then
  AN=$(grep -oE 'Executed [0-9]+ tests, with 0 failures' "$TMP/arbiter.log" | tail -1 | grep -oE '^[A-Za-z]* [0-9]+' | grep -oE '[0-9]+')
  ok "仲裁器用例全绿（幂集 64 组 + 锁屏中退出全屏不恢复，${AN:-?} 项）"
else
  no "仲裁器用例失败" "$(grep -E "error:|XCTAssert.*failed|failed -" "$TMP/arbiter.log" | head -2)"
fi

# ---- 四条源码判据 + 两条行为判据 + 四条探针判据 ----
# ⚠️ 措辞纪律见文件头（连续踩过三次：判据转红了但 `grep -c '❌ …'` 命中 0，
#   查不到是哪一条。判据一个都不放宽，只改文案）。
# ⚠️ 覆盖数声明：本段只有第 ① 条做了插桩反向验证（往 LockWatcher.swift 插
#   `import AVFoundation` → 该条必须转红 → 恢复 → cmp -s）。第 ② 条在锁屏那段验过、
#   第 ③ 条是既有判据、第 ④ 条与 SYS-02 判据同形且已验。
#   **不许**把这段写成「四条源码判据都做过反向验证」。

# ① 分层（本段唯一做反向验证的那条）
N=$(src_count 'import SwiftUI' 'Sources/PicCore/State')
[ "$N" = "0" ] && ok "State/ 零 SwiftUI 依赖（D-12 只产数据不渲染）" \
  || no "State/ 零 SwiftUI 依赖（D-12 只产数据不渲染）" "剥注释后 Sources/PicCore/State 内计数 = $N，期望 0"

N=$(src_count 'import AppKit' 'Sources/PicCore/State')
[ "$N" = "0" ] && ok "State/ 零 AppKit 依赖（D-12 只产数据不渲染）" \
  || no "State/ 零 AppKit 依赖（D-12 只产数据不渲染）" "剥注释后 Sources/PicCore/State 内计数 = $N，期望 0"

# ② 起播路径零播放器直连。门控另由 HoldStatusTests 的变异测试承担。
N=$(src_count 'player.player.play()' 'Sources/PicApp')
M=$(src_count 'player.player.pause()' 'Sources/PicApp')
[ "$N$M" = "00" ] && ok "起播路径零播放器直连（D-06 / W-2026-10-03-10 已收口）" \
  || no "起播路径零播放器直连（D-06 / W-2026-10-03-10 已收口）" "play()=$N pause()=$M，期望全 0"

# ③ B1：setRate 必须被 `if arbiter.decision.shouldPlay {` 包住（行号序判据，不是文本计数）。
#    只数「出现了门控」不够 —— 门控可以写在 setRate 之后而不起作用。
GATE_LINE=$(grep -n 'if arbiter.decision.shouldPlay {' Sources/PicApp/AppDelegate.swift | cut -d: -f1 | head -1)
RATE_LINE=$(grep -n 'player.setRate(store.rate)' Sources/PicApp/AppDelegate.swift | cut -d: -f1 | head -1)
if [ -n "$GATE_LINE" ] && [ -n "$RATE_LINE" ] && [ "$GATE_LINE" -lt "$RATE_LINE" ]; then
  ok "起播路径的 setRate 门在 shouldPlay 之后（W-2026-10-03-21 / B1）"
else
  no "起播路径的 setRate 门在 shouldPlay 之后（W-2026-10-03-21 / B1）" \
     "GATE_LINE=${GATE_LINE:-none} RATE_LINE=${RATE_LINE:-none}，要求 GATE_LINE < RATE_LINE；setRate 的实现就是 player.rate = r，无条件调用会把已 hold 的播放器重新拉起"
fi

# ④ PIC_HOLD_SUMMARY 恰好一处（AppDelegate 的可观测出口）。
N=$(src_count 'PIC_HOLD_SUMMARY summary=' 'Sources/PicApp')
[ "$N" = "1" ] && ok "PIC_HOLD_SUMMARY 恰好一处（D-12 数据落点的可观测出口）" \
  || no "PIC_HOLD_SUMMARY 恰好一处（D-12 数据落点的可观测出口）" "剥注释后计数 = $N，期望恰好 1"

# ---- 行为判据（不扫源码）----
if swift test --package-path . --filter HoldStatusTests > "$TMP/holdstatus.log" 2>&1; then
  HN=$(grep -oE 'Executed [0-9]+ tests, with 0 failures' "$TMP/holdstatus.log" | tail -1 | grep -oE '^[A-Za-z]* [0-9]+' | grep -oE '[0-9]+')
  ok "HoldStatus 用例全绿（D-12 派生量 + B1 门控，${HN:-?} 项）"
else
  no "HoldStatus 用例失败（D-12 派生量 + B1 门控）" "$(grep -E "error:|XCTAssert.*failed|failed -" "$TMP/holdstatus.log" | head -2)"
fi

# ---- 四条探针脚本的关键行（行为判据）----
# 4 条脚本约 30 秒。它们各自写自己那一层的 evidence，本段跑一遍再读那一条关键行。
# ⚠️ 读的是 **evidence 文件**而不是脚本的 stdout —— 这些脚本把 driver 的输出
#    写进日志文件，只往 stderr 打一行 `PROBE_OK`。只收 stdout 会恒红。
#
# ⚠️ 这些脚本默认**就地覆盖** evidence 文件。若会话锁定态与当初采集时不同，覆盖掉的
#    就是上一个 plan 的读数（实测踩到：复跑 `probe-fullscreen.sh` 时会话已解锁，
#    `COVERAGE` 从 1.000 变 0.000，入库的日志被覆盖）。
#    → 故本段把产物重定向到 `$TMP/ev`（探针脚本读 PIC_EVIDENCE_DIR 环境变量），
#      仓库内已入库的证据**一律不写**；旧入库版本只**只读**拷到 `$TMP` 供比对，
#      若本次读数与入库版本不同就提示，**不**替别的 plan 改判据或改产物值。
EV_TMP="$TMP/ev"; mkdir -p "$EV_TMP"
export PIC_EVIDENCE_DIR="$EV_TMP"
probe_line() {   # $1=脚本  $2=evidence 文件名  $3=关键行的正则  $4=判据名
  local rel=".planning/phases/03-system-events/evidence/$2"
  local f="$EV_TMP/$2"
  [ -f "$rel" ] && cp "$rel" "$TMP/$2.committed"
  perl -e 'alarm 120; exec @ARGV' bash "scripts/$1" > "$TMP/$1.log" 2>&1
  if [ ! -f "$f" ]; then
    no "$4" "跑 scripts/$1 后 $rel 不存在"
  elif grep -qE "$3" "$f"; then
    if [ -f "$TMP/$2.committed" ] && ! cmp -s "$f" "$TMP/$2.committed"; then
      ok "$4"
      printf "     ⚠️ 该 evidence 的读数与入库版本不同（多半是会话锁定态变了）；旧值留在 git 里\n"
    else
      ok "$4"
    fi
  else
    no "$4" "$rel 里没有匹配 /$3/ 的行"
  fi
}
probe_line probe-lock.sh      lock-wiring.log           '^LOCK_TRANSITION='              "锁屏跃迁观测已采集（03-01 探针，关键行存在）"
probe_line probe-fullscreen.sh fullscreen-signals.log    '^FULLSCREEN_VERDICT='           "全屏判定读数已采集（03-02 探针，verdict 行存在）"
probe_line probe-display.sh    display-sleep-signals.log '^DISPLAY_SLEEP_TRANSITION='     "熄屏/睡眠跃迁观测已采集（03-03 探针，关键行存在）"
probe_line probe-power.sh      power-signals.log         '^POWER_TRANSITION='             "电池跃迁观测已采集（03-04 探针，关键行存在）"

# ---- 源码层门禁（媒体库与轮换）----
# ⚠️ 措辞纪律见文件头。
# ⚠️ 本段只读源码计数（全部经 src_count），不跑探针脚本、不跑 swift build、
#   不碰任何转码命令。编译与单测由本脚本既有段承担。
echo ""
echo "── Phase 4：媒体库与轮换（源码层）────"

# ① Media/ 分层：只做文件系统与探针，不引渲染层。目录不存在时 src_count 返回 -1，
#    本项报红 —— 本层门禁要求本层的产物在，这是有意的。
N=$(src_count 'import AppKit' 'Sources/PicCore/Media')
[ "$N" = "0" ] && ok "Media/ 零 AppKit 依赖（只做文件系统与探针）" \
  || no "Media/ 零 AppKit 依赖（只做文件系统与探针）" "剥注释后 Sources/PicCore/Media 内计数 = $N，期望 0（目录不存在时为 -1）"

N=$(src_count 'import SwiftUI' 'Sources/PicCore/Media')
[ "$N" = "0" ] && ok "Media/ 零 SwiftUI 依赖（只做文件系统与探针）" \
  || no "Media/ 零 SwiftUI 依赖（只做文件系统与探针）" "剥注释后 Sources/PicCore/Media 内计数 = $N，期望 0（目录不存在时为 -1）"

# ② 面板唯一落点：token 带括号数「构造调用」—— 冻结类名 NSOpenPanelFolderPicker
#    自带无括号子串，裸 token 会被它恒撑到 2。等于 0 说明没实现，大于 1 说明出现了
#    第二处落点。
N=$(src_count 'NSOpenPanel(' 'Sources')
[ "$N" = "1" ] && ok "文件夹选择面板全仓唯一落点（FolderPicker）" \
  || no "文件夹选择面板全仓唯一落点（FolderPicker）" "构造调用 NSOpenPanel( 剥注释后全仓计数 = $N，期望恰好 1：等于 0 说明 SYS-03 没实现，大于 1 说明出现了第二处落点"

# ③ 轮换器零播放进度读取（「到点就切 ≠ 播完才切」的常驻代理）。
#    单文件计数：先拷进临时目录再对该目录 src_count。
#    四个标识符是判据的定义，必须逐字出现在判据名里 —— 只要轮换器能读到其中
#    任何一个，一个「等播完再换」的实现就能悄悄混进来。
RC="$TMP/rotation-src"; mkdir -p "$RC"
cp Sources/PicCore/Playback/RotationController.swift "$RC/" 2>/dev/null
if [ -f "$RC/RotationController.swift" ]; then
  N=$(src_count 'AVPlayer' "$RC")
  [ "$N" = "0" ] && ok "轮换器零播放进度读取（AVPlayer）" \
    || no "轮换器零播放进度读取（AVPlayer）" "剥注释后 RotationController.swift 内计数 = $N，期望 0"
  N=$(src_count 'arbiterCurrentPosition' "$RC")
  [ "$N" = "0" ] && ok "轮换器零播放进度读取（arbiterCurrentPosition）" \
    || no "轮换器零播放进度读取（arbiterCurrentPosition）" "剥注释后 RotationController.swift 内计数 = $N，期望 0"
  N=$(src_count 'currentTime' "$RC")
  [ "$N" = "0" ] && ok "轮换器零播放进度读取（currentTime）" \
    || no "轮换器零播放进度读取（currentTime）" "剥注释后 RotationController.swift 内计数 = $N，期望 0"
  N=$(src_count 'AVPlayerItemDidPlayToEndTime' "$RC")
  [ "$N" = "0" ] && ok "轮换器零播放进度读取（AVPlayerItemDidPlayToEndTime）" \
    || no "轮换器零播放进度读取（AVPlayerItemDidPlayToEndTime）" "剥注释后 RotationController.swift 内计数 = $N，期望 0"
else
  no "轮换器零播放进度读取（AVPlayer）" "文件缺失：Sources/PicCore/Playback/RotationController.swift 不在（04-02 未执行）"
  no "轮换器零播放进度读取（arbiterCurrentPosition）" "文件缺失：Sources/PicCore/Playback/RotationController.swift 不在（04-02 未执行）"
  no "轮换器零播放进度读取（currentTime）" "文件缺失：Sources/PicCore/Playback/RotationController.swift 不在（04-02 未执行）"
  no "轮换器零播放进度读取（AVPlayerItemDidPlayToEndTime）" "文件缺失：Sources/PicCore/Playback/RotationController.swift 不在（04-02 未执行）"
fi

# ---- 探针 evidence 门禁 ----
# 刻意的取舍（照实说，不美化）：本段**不重跑**这两个探针脚本，只读
# **已入库**的 evidence 文件。理由两条：
#   1. 媒体库探针的 driver 会建一个桌面级 NSWindow（tracer 要证窗口 attach 后
#      可见）—— 在本脚本里反复起 GUI 进程与既有「打包段不起 GUI 进程」的纪律冲突；
#   2. fixture 树脚本会在工作树里建/删 .planning/spike/media-fixture/ 并做一次
#      权限收紧 + 复原，每次跑本脚本都让工作树反复变脏。
# 行为侧的等价覆盖由本脚本既有的全量 swift test 承担（MediaLibraryTests /
# PlaybackRouterTests / RotationControllerTests / RotationTests 都在其中）。
# ⚠️ 真实目录的一次性抽样计时行（informational=1 那行）**不进任何判据** ——
#    读数随会话浮动，拿它当门禁会变成 flaky 判据，故本段的正则一律不碰它。
# ⚠️ 本段不重跑探针，也就不需要 evidence 重定向的环境变量；不跑 swift build /
#    swift test / 任何探针脚本 / 任何转码命令 —— 只读文件。
echo ""
echo "── Phase 4：探针 evidence ────────────"

p4_line() {   # $1=evidence 文件名  $2=关键行正则  $3=判据名
  local f=".planning/phases/04-media-library/evidence/$1"
  if [ ! -f "$f" ]; then
    no "$3" "$f 不存在（Phase 4 的探针未执行或 evidence 未入库）"
    return
  fi
  if grep -qE "$2" "$f"; then ok "$3"; else no "$3" "$f 里没有匹配 /$2/ 的行"; fi
}

p4_line media-library.log '^MEDIA_TRACER_PLAN=playing$' "媒体库 tracer 判定行存在（MEDIA_TRACER_PLAN=playing）"
p4_line media-library.log '^MEDIA_TRACER_PLAYER_ITEMS=[1-9][0-9]*$' "媒体库 tracer 播放队列已入队（MEDIA_TRACER_PLAYER_ITEMS ≥ 1）"
p4_line media-library.log '^MEDIA_TRACER_WINDOW_VISIBLE_AFTER_ATTACH=1$' "媒体库 tracer 窗口 attach 后可见（MEDIA_TRACER_WINDOW_VISIBLE_AFTER_ATTACH=1）"
p4_line media-library.log '^MEDIA_TRACER_WINDOW_VISIBLE_AFTER_TEARDOWN=0$' "媒体库 tracer 窗口 teardown 后不可见（MEDIA_TRACER_WINDOW_VISIBLE_AFTER_TEARDOWN=0）"
p4_line media-library.log '^MEDIA_TRACER_SCAN_COUNT=1$' "媒体库 tracer 缓存生效（MEDIA_TRACER_SCAN_COUNT=1）"

p4_line rotation-wiring.log '^PIC_ROT_LOOPLIST_ORDER=ok$' "轮换装配装载顺序正确（PIC_ROT_LOOPLIST_ORDER=ok）"
p4_line rotation-wiring.log '^PIC_ROT_SHUFFLE_ROUND_UNIQUE=3$' "轮换装配一轮内无重复（PIC_ROT_SHUFFLE_ROUND_UNIQUE=3）"
p4_line rotation-wiring.log '^PIC_ROT_EMPTY_LOADS=0$' "轮换装配空列表零装载（PIC_ROT_EMPTY_LOADS=0）"
p4_line rotation-wiring.log '^PIC_ROT_MODE=(loopSingle|loopList|shuffle)$' "轮换装配模式 token 已打（PIC_ROT_MODE）"
p4_line rotation-wiring.log '^PIC_ROT_APP_LAUNCH informational=1 scope=piccore-chain reason=app-launch-blocked-by-locked-screen$' "轮换装配范围声明已打（PIC_ROT_APP_LAUNCH informational=1）"

# 两份日志的媒体文件名零泄漏：数三个扩展名的出现行数，各要求 0。
MLFN=$(grep -cE '\.mp4|\.mov|\.m4v' .planning/phases/04-media-library/evidence/media-library.log 2>/dev/null || true)
[ "$MLFN" = "0" ] && ok "媒体库 evidence 零媒体文件名（T-03-02）" \
  || no "媒体库 evidence 零媒体文件名（T-03-02）" "media-library.log 内 .mp4/.mov/.m4v 行计数 = ${MLFN:-<文件缺失>}，期望 0"
RWFN=$(grep -cE '\.mp4|\.mov|\.m4v' .planning/phases/04-media-library/evidence/rotation-wiring.log 2>/dev/null || true)
[ "$RWFN" = "0" ] && ok "轮换 evidence 零媒体文件名（T-03-02）" \
  || no "轮换 evidence 零媒体文件名（T-03-02）" "rotation-wiring.log 内 .mp4/.mov/.m4v 行计数 = ${RWFN:-<文件缺失>}，期望 0"

echo ""
echo "── Phase 5：设置窗与运行层（源码层）──"
# ⚠️ 措辞纪律见文件头。
# ⚠️ 七个数字全部先数现状再写死（实测：0 / 0 / 0 / 1 文件 / 1 / 1 / 0 / 0）。

N=$(src_count 'import AVFoundation' 'Sources/PicApp/Settings')
[ "$N" = "0" ] && ok "设置窗视图零 AVFoundation 依赖（05-01 分层）" \
  || no "设置窗视图零 AVFoundation 依赖（05-01 分层）" "剥注释后 Sources/PicApp/Settings 内计数 = $N，期望 0"

# 展示层只做值 ↔ 显示形态的换算：碰框架就没法在无头环境单测它。
N=$(src_count 'import SwiftUI' 'Sources/PicCore/App')
M=$(src_count 'import AppKit' 'Sources/PicCore/App')
[ "$N$M" = "00" ] && ok "PicCore 展示层零 UI 框架依赖（05-01 分层）" \
  || no "PicCore 展示层零 UI 框架依赖（05-01 分层）" "SwiftUI=$N AppKit=$M，期望全 0"

# token 带括号：裸 token 会被 NSOpenPanelFolderPicker 这类无括号类型名撑成 2。
# `-r` 不能省：BSD grep 不带 -r 时给目录不递归，静默返回 0 个文件（看起来像「没实现」）。
N=$(grep -l -r -F 'NSOpenPanel(' Sources/PicApp 2>/dev/null | wc -l | tr -d ' ')
[ "$N" = "1" ] && ok "NSOpenPanel 只存在于 FolderPicker" \
  || no "NSOpenPanel 只存在于 FolderPicker" "构造调用 NSOpenPanel( 落在 $N 个文件里，期望恰好 1"

# 电源跃迁与设置窗 toggle 走同一个方法；两处 set 会双写。
N=$(src_count 'arbiter.set(.battery')
M=$(src_count 'BatteryHoldPolicy.shouldHold')
[ "$N" = "1" ] && [ "$M" = "1" ] && ok "电池 hold 单一落点（05-02 / T-05-06）" \
  || no "电池 hold 单一落点（05-02 / T-05-06）" "arbiter.set(.battery=$N shouldHold=$M，期望各恰好 1"

# 主会话硬红线：ffmpeg 类调用绝不进自动路径，且本机无 timeout 机制。
N=$(src_count 'Process(' 'Sources/PicCore/App/FFmpegAvailability.swift')
M=$(src_count 'NSTask' 'Sources/PicCore/App/FFmpegAvailability.swift')
[ "$N$M" = "00" ] && ok "ffmpeg 探测零执行（05-03）" \
  || no "ffmpeg 探测零执行（05-03）" "Process(=$N NSTask=$M，期望全 0"

N=$(src_count 'MUT-P5-')
[ "$N" = "0" ] && ok "变异插桩零残留" \
  || no "变异插桩零残留" "剥注释后 Sources/ 内 MUT-P5- 计数 = $N，期望 0"

# 按条目标题行计。正文里的交叉引用不占号 —— 同一号在正文出现十几次是正常的。
WD=$(grep -E '^### W-' .planning/WINDOWS.md | sort | uniq -d | wc -l | tr -d ' ')
[ "$WD" = "0" ] && ok "W 编号全库唯一" \
  || no "W 编号全库唯一" "重复的条目标题：$(grep -E '^### W-' .planning/WINDOWS.md | sort | uniq -d | tr '\n' ' ')"

echo "── Phase 6：转码（纯逻辑 + 红线门）──────"
# ⚠️ 措辞纪律见文件头。
# ⚠️ 本段**零 ffmpeg 进程调用**：只跑 swift 单测（转码侧全部是替身）+ 读源码计数 +
#   读已入库 evidence。转码执行只存在于手动 bench 脚本里（红线，见下）。
# ⚠️ 编译与全量单测由本脚本既有的「产品代码」段承担，本段不重跑。
# ⚠️ 本段**不重跑** transcode 探针（照上面 p4_line 纪律：探针重跑会覆盖
#   已入库 evidence；tracer 用例同在下面那条单测里）。

# ① Transcode/ 分层：只有文件系统与子进程执行，不引渲染/UI/响应式框架。
#    目录不存在时 src_count 返回 -1 → 报红（本层产物必须在，这是有意的）。
N=$(src_count 'import AppKit' 'Sources/PicCore/Transcode')
[ "$N" = "0" ] && ok "Transcode/ 零 AppKit 依赖（只做文件系统与子进程）" \
  || no "Transcode/ 零 AppKit 依赖（只做文件系统与子进程）" "剥注释后计数 = $N，期望 0（目录不存在时为 -1）"

N=$(src_count 'import SwiftUI' 'Sources/PicCore/Transcode')
[ "$N" = "0" ] && ok "Transcode/ 零 SwiftUI 依赖（执行侧不渲染）" \
  || no "Transcode/ 零 SwiftUI 依赖（执行侧不渲染）" "剥注释后计数 = $N，期望 0"

N=$(src_count 'import Combine' 'Sources/PicCore/Transcode')
[ "$N" = "0" ] && ok "Transcode/ 零 Combine 依赖（UI 观察走回调）" \
  || no "Transcode/ 零 Combine 依赖（UI 观察走回调）" "剥注释后计数 = $N，期望 0"

# 执行侧的路径纪律：不自己 contentsOfDirectory 绕开扫描器。
# ⚠️ 同族里的 `absoluteString` == 0 已在「产品代码」段对全 Sources/ 判过一次，
#    这里不重复 —— 判据一个数读两个真相源，只会让它不再变红。
N=$(src_count 'contentsOfDirectory' 'Sources/PicCore/Transcode')
[ "$N" = "0" ] && ok "Transcode/ 不自己列目录（枚举统一走 MediaLibrary / ConvertedLibrary）" \
  || no "Transcode/ 不自己列目录（枚举统一走 MediaLibrary / ConvertedLibrary）" "剥注释后计数 = $N，期望 0"

# ② 子进程执行侧的两个承重形状：降载前缀（不得裸 spawn 抢 CPU）与
#    只认退出码判成败（管道退出码不作数，C10）。
TR="$TMP/trc-src"; mkdir -p "$TR"
cp Sources/PicCore/Transcode/ProcessTranscodeRunner.swift "$TR/" 2>/dev/null
if [ -f "$TR/ProcessTranscodeRunner.swift" ]; then
  N=$(src_count '/usr/bin/nice' "$TR")
  [ "$N" -ge 1 ] 2>/dev/null && ok "转码子进程降载执行（nice 前缀在 argv 里）" \
    || no "转码子进程降载执行（nice 前缀在 argv 里）" "剥注释后 ProcessTranscodeRunner.swift 内计数 = $N，期望 ≥ 1"
  N=$(src_count 'terminationStatus' "$TR")
  [ "$N" -ge 1 ] 2>/dev/null && ok "转码成败只认进程退出码" \
    || no "转码成败只认进程退出码" "剥注释后 ProcessTranscodeRunner.swift 内计数 = $N，期望 ≥ 1"
else
  no "转码子进程降载执行（nice 前缀在 argv 里）" "文件缺失：Sources/PicCore/Transcode/ProcessTranscodeRunner.swift 不在（06-03 未执行）"
  no "转码成败只认进程退出码" "文件缺失：Sources/PicCore/Transcode/ProcessTranscodeRunner.swift 不在（06-03 未执行）"
fi

# ③ 三途径安装说明的外显两条。`pathway:` 标识符的完整性由 FFmpeg 单测锁。
N=$(src_count 'xattr -dr com.apple.quarantine' 'Sources/PicApp/Transcode')
[ "$N" -ge 1 ] 2>/dev/null && ok "安装说明含静态二进制的去隔离命令" \
  || no "安装说明含静态二进制的去隔离命令" "剥注释后 Sources/PicApp/Transcode 内计数 = $N，期望 ≥ 1"

N=$(src_count 'brew install ffmpeg' 'Sources/PicApp/Transcode')
[ "$N" -ge 1 ] 2>/dev/null && ok "安装说明含 Homebrew 途径" \
  || no "安装说明含 Homebrew 途径" "剥注释后 Sources/PicApp/Transcode 内计数 = $N，期望 ≥ 1"

# ④ 装配侧（SC#5 的 app 级）：`router.start` 的每个调用点都必须吃合并清单，
#    且转码排空后要失效缓存再重扫 —— 少了 invalidateCache，MediaLibrary 的缓存
#    会让新产物永远看不见（静默失效）。
N=$(src_count 'mergedPlaybackItems' 'Sources/PicApp')
[ "$N" -ge 2 ] 2>/dev/null && ok "播放清单走 Converted 合并入口（SC#5）" \
  || no "播放清单走 Converted 合并入口（SC#5）" "剥注释后 Sources/PicApp 内计数 = $N，期望 ≥ 2（定义 + 至少一个调用点）"

N=$(src_count 'onBatchFinished' 'Sources/PicApp')
[ "$N" -ge 1 ] 2>/dev/null && ok "转码排空钩子已装配" \
  || no "转码排空钩子已装配" "剥注释后 Sources/PicApp 内计数 = $N，期望 ≥ 1"

N=$(src_count 'invalidateCache' 'Sources/PicApp')
[ "$N" -ge 1 ] 2>/dev/null && ok "排空后显式失效扫描缓存" \
  || no "排空后显式失效扫描缓存" "剥注释后 Sources/PicApp 内计数 = $N，期望 ≥ 1"

# ⑤ 转码侧纯逻辑单测。转码执行侧全部是替身（FakeRunner 进程外零调用），
#    所以这条是**零 ffmpeg** 的。队列单列一条 —— 它是执行路径的行为中枢。
TRC_N=41
if swift test --package-path . --filter 'Transcode|ConvertedLibrary|ExternalToolLocator|ProgressParser' > "$TMP/trc.log" 2>&1 \
   && grep -qE "Executed ${TRC_N} tests, with 0 failures" "$TMP/trc.log"; then
  ok "Phase6 转码纯逻辑单测全绿"
else
  no "Phase6 转码纯逻辑单测全绿" "$(grep -E 'error:|XCTAssert.*failed' "$TMP/trc.log" | head -2)"
fi

TQ_N=6
if swift test --package-path . --filter TranscodeQueueTests > "$TMP/trcqueue.log" 2>&1 \
   && grep -qE "Executed ${TQ_N} tests, with 0 failures" "$TMP/trcqueue.log"; then
  ok "Phase6 转码队列单测全绿"
else
  no "Phase6 转码队列单测全绿" "$(grep -E 'error:|XCTAssert.*failed' "$TMP/trcqueue.log" | head -2)"
fi

# 🔴 主 actor 冻结回归门（跨 phase 集成检查抓出的 BLOCKER）。判据：真
#    ProcessTranscodeRunner + /bin/sh 慢桩（sleep 0.9s）跑进真队列，
#    run 尚未返回时 percent 必须已被观察到非 nil。老七道门全用瞬时替身
#    （FakeRunner / /bin/sh printf），同步 waitUntilExit 冻主 actor 全部躲过去
#    —— 实测老形状这条读数恒 0，修好后约 130~170。N>0 即「run 期间送达」。
FR_N=1
FR_GATE="转码期间主 actor 未冻结（run 期间收到进度 N 条，非排空后补收）"
if swift test --package-path . --filter TranscodeMainActorFreezeTests > "$TMP/trcfreeze.log" 2>&1 \
   && grep -qE "Executed ${FR_N} tests?, with 0 failures" "$TMP/trcfreeze.log"; then
  FR_RUN=$(grep -oE 'PIC_TRC_PROGRESS_DURING_RUN=[0-9]+' "$TMP/trcfreeze.log" | tail -1 | cut -d= -f2)
  if [ "${FR_RUN:-0}" -ge 1 ] 2>/dev/null; then
    ok "$FR_GATE" ; printf "     run 期间收到进度 %s 条\n" "$FR_RUN"
  else
    no "$FR_GATE" "run 期间进度读数 = ${FR_RUN:-<无读数>}，期望 ≥ 1（同步 waitUntilExit 的老形状实测 0）"
  fi
else
  no "$FR_GATE" "$(grep -E 'error:|XCTAssert.*failed' "$TMP/trcfreeze.log" | head -2)"
fi

# ⑥ tracer 的活体 evidence（**只读**，不重跑探针）。
#    四行分别锁：不回流（候选集零 Converted 条目）、产物可播、重复批次幂等跳过、
#    全程 runner 只被调用一次（防重复烤机）。
p6_log=".planning/phases/06-transcode/evidence/transcode-tracer.log"
P6_TOKENS='PIC_TRC_REFILTER_CANDIDATES=0
PIC_TRC_CONVERTED_PLAYABLE=1
PIC_TRC_SECOND_PASS_SKIPPED=1
PIC_TRC_RUNNER_CALLS_TOTAL=1'
P6_MISSING=""
if [ ! -f "$p6_log" ]; then
  P6_MISSING="$p6_log 不存在（06-03 探针未执行或 evidence 未入库）"
else
  while IFS= read -r tok; do
    grep -qxF "$tok" "$p6_log" || P6_MISSING="$P6_MISSING $tok"
  done <<< "$P6_TOKENS"
fi
if [ -z "$P6_MISSING" ]; then
  ok "Phase6 探针四行闭环（不回流可播幂等零重复spawn）"
  grep -xE "$P6_TOKENS" "$p6_log" | sed 's/^/     /'
else
  no "Phase6 探针四行闭环（不回流可播幂等零重复spawn）" "缺：$P6_MISSING"
fi

# ⑦ 🔴 ffmpeg 红线（STATE.md 拍板）：本脚本全程零 ffmpeg 进程调用，
#    转码 bench 只能人工手动跑（scripts 下的手动脚本）。一次 libvmaf 实测跑出过
#    779.9% CPU，挂进常规校验等于每次校验烤一次机。
#
#    ⚠️ 判据**自身**用拆串构造：模式在文件里以 `"a""b"` 两段字面存在，bash 拼接
#    后才成为目标串。写成 joined 字面会让这条判据 grep 到自己、恒红。
#    剥 bash 注释行后再计数 —— 注释里的提醒字样不算调用。
BB="transcode""-bench"
EP1="ffmpeg"" -i"
EP2="libx""264"
EP3="ffmpeg"" -version"
RB=$(grep -v -E '^[[:space:]]*#' test.sh | grep -c "$BB")
RE=$(grep -v -E '^[[:space:]]*#' test.sh | grep -cE "$EP1|$EP2|$EP3")
if [ "$RB" -eq 0 ] && [ "$RE" -eq 0 ]; then
  ok "Phase6 红线 test.sh 零 ffmpeg 调用与零 bench 引用"
else
  no "Phase6 红线 test.sh 零 ffmpeg 调用与零 bench 引用" \
     "剥注释后 bench 引用计数=$RB 编码形态调用计数=$RE，期望全 0"
fi

echo ""
echo "── Phase 7 交付：产物形态 + evidence ──"
# ⚠️ 措辞纪律见文件头。
# ⚠️ 本段**不重跑任何探针**，只读本段自己已入库的 evidence（照 Phase 4 的
#   p4_line 纪律：重跑会覆盖已入库证据）。
# ⚠️ 本段**不复用** Phase 3 的 probe 读法 —— 那个 helper 把 evidence 路径硬编码在
#   Phase 3 的目录下，读不到本段的目录，复用会假红。这里另起一套读法。
# ⚠️ 干净 clone 里没有 build/ 与 evidence/ —— 走 skip 不走红。

P7EV=".planning/phases/07-delivery/evidence"

# ---- 产物形态（build/ 在时才查）----
if [ ! -d build ]; then
  skip "交付二进制零探针符号（07-01 成对判据）"  "build/ 不存在，跑 bash build.sh 后再验"
  skip "PicProbe 保留探针（成对正控）"           "build/ 不存在，跑 bash build.sh 后再验"
  skip "交付二进制零探针符号 —— spctl 拒绝 rc=3（未签名未公证的正向断言）" "build/ 不存在"
  skip "app 图标 CFBundleIconFile=Pic 且 Pic.icns 非空" "build/ 不存在"
  skip "菜单栏图标用 v1（menubar-v1 在位、v2 零残留）"   "build/ 不存在"
else
  P7APP="build/Pic.app/Contents/MacOS/Pic"
  P7PROBE="build/PicProbe.app/Contents/MacOS/Pic"

  # 成对判据：只有 == 0 一条就是 grep 模式空集的假绿灯 —— 正控侧必须 ≥ 1。
  # ⚠️ 必须 `grep -cE`：裸 grep 的 '|' 是字面量，恒 0 假绿灯（build.sh 同一教训）。
  NS=$(nm "$P7APP" 2>/dev/null | grep -cE 'LoopProbe|WindowProbe|FrameDriver')
  NP=$(nm "$P7PROBE" 2>/dev/null | grep -cE 'LoopProbe|WindowProbe|FrameDriver')
  [ "$NS" = "0" ] && ok "交付二进制零探针符号（07-01 成对判据）" \
    || no "交付二进制零探针符号（07-01 成对判据）" "剥符号后计数 = $NS，期望 0"
  [ "${NP:-0}" -ge 1 ] 2>/dev/null && ok "PicProbe 保留探针（成对正控）" \
    || no "PicProbe 保留探针（成对正控）" "剥符号后计数 = ${NP:-<无此产物>}，期望 ≥ 1（正控缺失则上一条的 0 无意义）"

  # spctl 是**正向**断言：未签名未公证的 app 就该被拒，rc=3 才是形态面成立。
  # 把它当失败就是把判据方向写反。
  # ⚠️ 变量名不能叫 SRC —— 上面的 SRC 是**渲染段的源文件清单**，
  #    这里覆盖它会让「设置窗渲染」段编译一个空列表而恒红。
  spctl -a -t exec -vv build/Pic.app >/dev/null 2>&1
  SPCTL_RC=$?
  [ "$SPCTL_RC" -eq 3 ] && ok "交付二进制零探针符号 —— spctl 拒绝 rc=3（未签名未公证的正向断言）" \
    || no "交付二进制零探针符号 —— spctl 拒绝 rc=3（未签名未公证的正向断言）" \
       "spctl -a -t exec 返回 rc=$SPCTL_RC，期望 3（预期拒绝；0 反而说明被认可了）"

  P7RES="build/Pic.app/Contents/Resources"
  if [ "$(plutil -extract CFBundleIconFile raw build/Pic.app/Contents/Info.plist 2>/dev/null)" = "Pic" ] \
     && [ -s "$P7RES/Pic.icns" ]; then
    ok "app 图标 CFBundleIconFile=Pic 且 Pic.icns 非空"
  else
    no "app 图标 CFBundleIconFile=Pic 且 Pic.icns 非空" \
       "CFBundleIconFile=$(plutil -extract CFBundleIconFile raw build/Pic.app/Contents/Info.plist 2>/dev/null) Pic.icns=$( [ -s "$P7RES/Pic.icns" ] && echo nonempty || echo missing)"
  fi
  MV2=$(find "$P7RES" -name 'menubar-v2*' 2>/dev/null | wc -l | tr -d ' ')
  if [ -f "$P7RES/menubar-v1Template.png" ] && [ "$MV2" = "0" ]; then
    ok "菜单栏图标用 v1（menubar-v1 在位、v2 零残留）"
  else
    no "菜单栏图标用 v1（menubar-v1 在位、v2 零残留）" "menubar-v1Template.png 在位=$([ -f "$P7RES/menubar-v1Template.png" ] && echo yes || echo no) v2 残留=$MV2，期望 v1 在位且 v2 为 0"
  fi
fi

# ---- evidence 关键行（只读已入库证据；文件不存在走 skip）----
p7_line() {   # $1=evidence 文件名  $2=关键行正则  $3=判据名
  local f="$P7EV/$1"
  if [ ! -f "$f" ]; then
    skip "$3" "$f 不存在（Phase 7 的对应采集脚本未跑或证据未入库）"
    return
  fi
  if grep -qE "$2" "$f"; then ok "$3"; else no "$3" "$f 里没有匹配 /$2/ 的行"; fi
}

p7_line sys01.log '^SYS01_ACTIVE_ROUTE=(smappservice|launchagent)$' \
  "SYS-01 实测路线已判定（ACTIVE_ROUTE 非 none）"
p7_line probe-strip.log '^PROBE_STRIP_DELIVERY_SYMBOLS=0$' \
  "交付二进制零探针符号 —— 探针剥离证据已入库"
p7_line stress-rotation.log '^STRESS_VERDICT=pass$' \
  "50 换片压测通过（≥50 次且内存回基线 ±10%）"
p7_line packaging.log '^PACK_REPEAT_CONSISTENT=1$' \
  "重复构建结果一致（SC1，锚 .app 而非 DMG）"
p7_line packaging.log '^PACK_SPCTL_RC=3$' \
  "重复构建结果一致 —— DMG 形态 spctl rc=3 已入库"
p7_line uninstall.log '^UNINSTALL_RESIDUE_TOTAL=0$' \
  "卸载残留复查为 0（域 / plist / LaunchAgent / BTM 四项）"

# ---- 7 天长跑：**skip 分支**。人工周期不许被自动判据卡死，也不许被算成已通过 ----
SOAKLOG="$P7EV/soak/soak.log"
if [ ! -f "$SOAKLOG" ]; then
  skip "7 天长跑（人工周期，SOAK_VERDICT 未收口）" "尚无 $SOAKLOG；按 UAT-SOAK.md 跑满 7 天后才有结论"
elif grep -qE '^SOAK_VERDICT=' "$SOAKLOG"; then
  ok "7 天长跑（人工周期，SOAK_VERDICT=$(grep -oE '^SOAK_VERDICT=.*' "$SOAKLOG" | tail -1 | cut -d= -f2)）"
else
  skip "7 天长跑（人工周期，SOAK_VERDICT 未收口）" "$SOAKLOG 里没有 SOAK_VERDICT= 行（采样未落或未跑分析器）"
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
# build.sh 的产出本身也要被验，不能只验源码。
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
