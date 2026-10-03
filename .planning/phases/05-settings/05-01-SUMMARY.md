---
phase: 05-settings
plan: 01
subsystem: ui
tags: [swift, swiftui, xcodeproj, xcuitest, probe, settings, menu-bar]

# Dependency graph
requires:
  - phase: 04-media-library
    provides: MediaLibrary/MediaCoordinator/RotationController/PlaybackRouter（设置窗的数据面）+ MenuContentView 菜单门 re-scope（04-06）
  - phase: 02-playback-core
    provides: PlayerController 公开面 setRate/setVolume/setMuted（D-13：挂 AVPlayer 不挂 item）+ SettingsStore 7 键冻结（D-03）
  - phase: 03-system-events
    provides: HoldArbiter.decision.shouldPlay（起播门禁 B1 的设置路径延伸）+ WallpaperWindowController.emit（D-12 可观测出口）
provides:
  - SettingsPresentation：窗口常量 780/680 的唯一来源、rateBounds、rateLabel/volumePercent/volumeFromPercent
  - SettingsApplier：「当场生效」唯一落点（applyRate 带 shouldPlay 门 + applyVolume/applyMuted/applyAudioTrio），05-02/05-03 在同一类上接线
  - SettingsComponents + SettingsView：UI-SPEC §7 双列四卡皮肤，速度行真绑定，其余行渲染真值
  - Pic.xcodeproj：手写 pbxproj（app target PicApp 复用 SwiftPM 源 + PicUITests + 共享 scheme），Phase 2 D-01 预告兑现
  - scripts/run-uitests.sh：锁屏 / 屏幕录制双守卫的 XCUITest 运行器（blocked / skipped / passed 三态可区分）
  - 三类可 grep 证据行：PIC_SETTINGS_BOOT / PIC_SETTINGS_APPLY / PIC_SETTINGS_WINDOW
affects: [05-02（模式/轮换/音量/电池接线 + 重启回读探针复用 probe-settings.sh 骨架）, 05-03（空态/运行状态/来源卡接线 + probe-status-card）, 05-04（Phase 5 收口门禁要消费 evidence/uitest.log 与 run-uitests.sh）, 06-transcode（转码窗口入口）, Phase 6/7 的 XCUITest 都建立在 Pic.xcodeproj 上]

actuals:
  tokens: 4390   # chars/4 over the realized diff（1755 行变更）
  tasks: 2
  commits: 8

tech-stack:
  added: []   # 零第三方依赖不变；.xcodeproj 是手写文件非引入依赖
  patterns:
    - 「当场生效」的三段式：UI 只写 store → SettingsApplier（唯一落点，含 shouldPlay 门）→ PlayerController 公开面。UI/applier 都不碰 AVPlayer（D-13）
    - 证据桥：emit 在 PIC_EVIDENCE_FILE 非空时把每行 mirror 进文件，探针与 XCUITest 共用同一个 grep 面；不设变量时逐字节同现状
    - 手写 pbxproj 的两处实测必需项：app target 的 ARCHS 锁 arm64（否则 universal 构建找不到只编 arm64 的包产物）+ 目标名不与 SPM 产品名重名

key-files:
  created:
    - Sources/PicCore/App/SettingsPresentation.swift
    - Sources/PicCore/App/SettingsApplier.swift
    - Sources/PicApp/Settings/SettingsComponents.swift
    - Sources/PicApp/Settings/SettingsView.swift
    - Pic.xcodeproj/project.pbxproj
    - Pic.xcodeproj/xcshareddata/xcschemes/Pic.xcscheme
    - UITests/PicUITests/SettingsWindowUITests.swift
    - scripts/probe-settings.sh
    - scripts/run-uitests.sh
    - Tests/PicCoreTests/SettingsPresentationTests.swift
    - Tests/PicCoreTests/SettingsApplierTests.swift
    - .planning/phases/05-settings/evidence/settings-tracer.log
    - .planning/phases/05-settings/evidence/uitest.log
  modified:
    - Sources/PicApp/PicApp.swift
    - Sources/PicApp/App/MenuContentView.swift
    - Sources/PicApp/AppDelegate.swift
    - Sources/PicCore/App/MenuItem.swift
    - Sources/PicCore/Render/WallpaperWindowController.swift
    - .planning/WINDOWS.md
    - .gitignore

key-decisions:
  - "SettingsApplier 的 @Environment 注入不需要 PlayerController：PlayerController 不是 @Observable，.environment() 编译不过；速度路径本来就是 store → applier → player，视图侧从不碰 player（D-13 的正确形态）。故 plan 的「注入 player」一行删除"
  - "emitBootSettings() 放在 bootstrapAfterWiring 末尾（startWallpaper 的调用点），不是 applicationDidFinishLaunching —— 计划原文写的是后者，但 startWallpaper 实际由 bootstrap Task 调用（04-05 的异步化），语义「startWallpaper 之后」只有放这里成立"
  - "MenuShortcut 的应用入口放 PicApp.swift 的 View 扩展，不放 MenuContentView：计数门锁 MenuContentView 内 MenuShortcut 字面量恰好 1 次，结构体声明已占满，行内再写一次应用必是 2（这是计划判据与计划实现形状的自相矛盾，见 Deviations 4）"
  - "SwiftUI Window 的 frame 会被自动存进 bundle-id 域（NSWindow Frame settings）→ 「打开即 780」依赖机器历史状态。清理放 runner（起测前删 + 轮询确认 cfprefsd 落地），不放测试内：实测测试内的 defaults 清理被 cfprefsd 缓存吃掉，连续三轮 2 绿 1 红"
  - "⌘, 的 XCUITest 断言改为「点菜单栏图标 → 断言菜单项逐字是「打开设置 ⌘,」→ 点它开窗」。不发真实系统按键：本 app 是 .accessory，无 key window 时 ⌘, 被系统接管去开「系统设置」（实测连续三轮误开，且那三轮的绿是假绿）。键盘等价键的实际按键响应未证明，登记 W-2026-10-03-49"

patterns-established:
  - "Plan 判据与本机实测冲突时的三个既成先例（04-01/04-03 已各踩过一次，本次照抄）：① 单文件过 src_count 要加文件分支；② 变异红日志的 error: 计数改判编译器诊断独有形态；③ <automated> 里的绝对路径重锚到本 worktree"
  - "手写 pbxproj 的最小可用集实测：ARCHS 必须锁单架构（destination 泛化时 app 编 universal、包只编 arm64 → 「Unable to resolve module dependency」）；target 名不能与 SPM 产品名同名（test runner 会解析到裸二进制而不是 .app）"

requirements-completed: [UI-01, MENUBAR-02]

# Coverage metadata (#1602)
coverage:
  - id: D1
    description: "SettingsPresentation：窗口常量 780/680（SC-1 唯一来源）、rateBounds 0.5–2.0、rateLabel/volumePercent/volumeFromPercent"
    verification:
      - kind: unit
        ref: "Tests/PicCoreTests/SettingsPresentationTests.swift#SettingsPresentationTests — Executed 6 tests, with 0 failures"
        status: pass
    human_judgment: false
  - id: D2
    description: "SettingsApplier.applyRate 的 shouldPlay 门：playing 当场生效 / held 不拉起 / 解除后重落位；音量静音无门"
    verification:
      - kind: unit
        ref: "Tests/PicCoreTests/SettingsApplierTests.swift — Executed 4 tests, with 0 failures"
        status: pass
      - kind: other
        ref: "变异 MUT-P5-RATE-GATE（let gated = true）：MUTATED_RC=1，失败列表含 testHeldPlayerDoesNotGetRateApplied，XCTAssert 计数 2，编译器诊断形态 error: 计数 0，恢复后 cmp -s 逐字节一致"
        status: pass
    human_judgment: false
  - id: D3
    description: "设置窗按 B1/L4 双列皮肤打开：780 宽 / contentMinSize 680 / 无侧边栏 / 标准标题栏「Pic 设置」；关窗进程不退"
    verification:
      - kind: other
        ref: "bash scripts/probe-settings.sh → PROBE_WINDOW=ok（PIC_SETTINGS_WINDOW width=780 minWidth=680）+ PROCESS_EXITED=clean + SETTINGS_TRACER_PROBE_OK"
        status: pass
      - kind: e2e
        ref: "XCUITest testClosingWindowKeepsProcessAlive（evidence/uitest.log 中 passed，4.6s）—— 关窗后 app.state != .notRunning 且设置窗消失"
        status: pass
    human_judgment: false
  - id: D4
    description: "设置项 7 键在启动时回读并打一行 PIC_SETTINGS_BOOT（TEST-04 的重启回读锚点）"
    verification:
      - kind: other
        ref: "probe-settings.sh → PIC_SETTINGS_BOOT rate=1.5 volume=0.5 muted=1（进程名域 seeded 值逐字回读）+ PROBE_BOOT=ok"
        status: pass
    human_judgment: false
  - id: D5
    description: "菜单「打开设置 ⌘,」：文案渲染 + 点击开窗（XCUITest 改写后用例）"
    verification:
      - kind: e2e
        ref: "UITests/PicUITests/SettingsWindowUITests.swift#testSettingsMenuItemRendersShortcutAndOpensWindow —— **未跑**：改写提交在 ffd0777，本 plan 未重跑 UI 测试"
        status: unknown
    human_judgment: true
    rationale: "改写后的用例从未执行；且 ⌘, 的键盘等价键实际按键响应在 XCUITest 里无法在不污染系统的前提下证明（W-2026-10-03-49）。菜单文案渲染的契约由全仓唯一 keyboardShortcut(",", modifiers: .command) 单点产出，但视觉/交互面仍需人眼确认"
  - id: D6
    description: "UI 皮肤与双列布局的视觉形态（字号层级、发光、卡片描边、呼吸动画）"
    verification: []
    human_judgment: true
    rationale: "组件照搬 spike 已渲染基线 + 三处合同覆盖（pSep 0.16 / tileGap 12 / 11.5pt 字号），但未经本 plan 的截图或人眼比对；除速度行外各行的真数据接线属 05-02/05-03"
  - id: D7
    description: "速度行 UI 拖动 → store → applier → AVPlayer.rate 的端到端链路"
    verification:
      - kind: unit
        ref: "机制层：SettingsApplierTests 四条证明 store → applier → PlayerController.setRate 的落位与门控"
        status: pass
    human_judgment: true
    rationale: "UI 侧「拖动滑杆」这一步没有任何自动化覆盖 —— 没有 XCUITest 拖 slider，也没有探针驱动 UI。GlowSlider 的 onChanged/onEnded 接线目前只有代码形态，无行为证据；需 05-02 的接线条目或人工拖一次确认"

# Metrics
duration: 96min
completed: 2026-10-03
status: halted
---

# Phase 5 Plan 01: 设置窗 tracer Summary

**一条纵向切片打通「菜单 ⌘, → 780pt B1 设置窗 → 拖速度滑杆 → AVPlayer.rate 当场变 → 关窗进程不退」**，附交付手写 `Pic.xcodeproj` 与三条 XCUITest —— **但 XCUITest 未达绿，plan 停在 halted**（见「Issues Encountered」）。

## Performance

- **Duration:** 96 min
- **Started:** 2026-10-03T12:48:00Z
- **Completed:** 2026-10-03T14:24:17Z
- **Tasks:** 2
- **Files modified:** 20（+1755 / -25）

## Accomplishments

- **速度当场生效 + shouldPlay 门**：变异反向验证通过 —— 拿掉门后 `testHeldPlayerDoesNotGetRateApplied` 转红，红光来自断言（XCTAssert 计数 2、编译器诊断形态 error: 计数 0），恢复后逐字节一致。这条是 W-2026-10-03-21 起播门禁在设置路径上的延伸，有牙齿。
- **窗口几何由探针证明**：`PIC_SETTINGS_WINDOW width=780 minWidth=680`（780 只从 `SettingsPresentation` 读，视图与探针同源）+ `PROCESS_EXITED=clean`。
- **7 键回读锚点**：`PIC_SETTINGS_BOOT rate=1.5 volume=0.5 muted=1` —— seeding 值逐字回读（TEST-04 的探针半边）。
- **`Pic.xcodeproj` 手写成功**：app target 复用 SwiftPM 同一份 `Sources/PicApp`，`xcodebuild build` 与 `swift build` 零漂移；交付路径 `Package.swift`/`build.sh`/`test.sh` 零改动（D-01）。
- **两个 UI 测试真实缺陷被挖出并修掉**（详见 Issues）：⌘, 用例往系统发按键导致**误开系统设置**污染用户机器；宽度断言被 SwiftUI 的窗口 frame 记忆污染。

## Task Commits

1. **Task 1 RED: SettingsPresentation/SettingsApplier 测试 + 可编译桩** — `a5b9226` (test)
2. **Task 1 GREEN: 两个新类的真实现** — `090c022` (feat)
3. **Task 1: 设置窗 UI 接线（双列 SettingsView + 菜单 ⌘, + 证据桥）** — `a8edc4b` (feat)
4. **Task 1: 探针脚本 + 通知桥修正 + evidence** — `ff4c335` (feat)
5. **Task 1: evidence 复采（SETTINGS_TRACER_OK 那轮）** — `36b9ce8` (test)
6. **Task 2: 手写 Pic.xcodeproj + 首批 XCUITest + run-uitests.sh** — `c0ee480` (feat)
7. **Task 2: XCUITest 缺陷修（⌘, 改写 + 屏幕录制预检 + frame 清理确定化）** — `ffd0777` (fix)
8. **Task 2: evidence/uitest.log（如实的末次读数）** — `c0a9439` (test)

**Plan metadata:** 本文件（`docs(05-01)`）。

## Files Created/Modified

- `Sources/PicCore/App/SettingsPresentation.swift` — 纯显示映射；窗口常量 780/680 的唯一来源；只 import Foundation
- `Sources/PicCore/App/SettingsApplier.swift` — 当场生效唯一落点；applyRate 带 shouldPlay 门（变异靶点）+ applyVolume/applyMuted/applyAudioTrio；零 AVFoundation import
- `Sources/PicApp/Settings/SettingsComponents.swift` — spike 组件照搬 + 三处合同覆盖（pSep 0.16 / tileGap 12 / 11.5pt）
- `Sources/PicApp/Settings/SettingsView.swift` — UI-SPEC §7 双列四卡；速度行真绑定（onChanged→applyRate / onEnded→persist 恰一次）；几何探针；呼吸动画挂 reduceMotion
- `Sources/PicApp/PicApp.swift` — Window 内容换 SettingsView、defaultSize 780、注入 settingsApplier、`settingsShortcut(for:)` 扩展
- `Sources/PicApp/App/MenuContentView.swift` — MenuShortcut ViewModifier（仅 openSettings 挂 ⌘,）；SettingsSkeletonView 删除
- `Sources/PicCore/App/MenuItem.swift` — openSettings 文案「打开设置窗口」→「打开设置」
- `Sources/PicApp/AppDelegate.swift` — settingsApplier 装配（lazy）、emitBootSettings、`--open-settings` 脚手架（纯加法，startWallpaper 尾段与 wiring() 未动）
- `Sources/PicCore/Render/WallpaperWindowController.swift` — emit 的 PIC_EVIDENCE_FILE 追加 mirror（签名不变、未设变量时逐字节同现状）
- `Pic.xcodeproj/` + `UITests/PicUITests/SettingsWindowUITests.swift` + `scripts/run-uitests.sh` — T2 交付物

## Decisions Made

见 frontmatter `key-decisions`（6 条）。最影响后续 plan 的三条：

1. **UI 不碰 player**：`SettingsApplier` 封装了 player，视图侧只 `@Environment(SettingsApplier.self)`。05-02/05-03 往同一类上加 applyMode/applyInterval/applyBattery 即可，不要在视图里回退成直接调 player。
2. **emitBootSettings 的位置**在 `bootstrapAfterWiring` 末尾 —— 05-02 的重启探针读同一行。
3. **⌘, 不再用 `typeKey` 验证**（会打开系统设置）；05-04 的收口门禁若要碰快捷键，只能走菜单项渲染这条路。

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `.environment(appDelegate.player)` 编译不过 —— 删除该注入**
- **Found during:** Task 1 首次 `swift build`
- **Issue**：`PlayerController` 不是 `@Observable`，SwiftUI 的 `.environment(_:)` 不接受；plan 要求注入 player。
- **Fix**：SettingsView 不注入 player（速度路径本就 store → applier → player，视图从不碰 player，正是 D-13 要的形态）。
- **Verification**：`swift build` 0 error；applier 单测与探针全绿。
- **Committed in:** `a8edc4b`

**2. [Rule 1 - Plan 事实错误] `emitBootSettings()` 的调用点**
- **Found during:** Task 1
- **Issue**：plan 写「applicationDidFinishLaunching 里 startWallpaper() 之后」，但 04-05 已把 startWallpaper 改成由 `bootstrapAfterWiring` 的 Task 调用。
- **Fix**：放在 `bootstrapAfterWiring` 末尾（`await startWallpaper()` 之后），语义「startWallpaper 之后」只有这里成立。
- **Committed in:** `a8edc4b`

**3. [Rule 3 - Blocking] `let settingsApplier = SettingsApplier(store: player: arbiter:)` 编译不过**
- **Issue**：属性初始化器里不能引用 self 的其它实例成员。
- **Fix**：改 `lazy var`（与既有 `coordinator`/`router` 同一形态，D-10 装配点不动）。
- **Committed in:** `a8edc4b`

**4. [Rule 1 - 计划判据自相矛盾] MenuShortcut 计数门与计划实现形状冲突**
- **Found during:** Task 1 门禁首跑（`shortcut_mod=2`）
- **Issue**：plan 要求 MenuContentView 内 `MenuShortcut` 字面量恰好 1 次，同时要求「独立 private struct MenuShortcut + 挂在 Button 之后」。声明与用法在同一文件必然 ≥ 2 行。
- **Fix**：语义完全保留（仍是独立 ViewModifier、仍只有一个 Button 字面量），把**应用入口**（`View.settingsShortcut(for:)`）放到 PicApp.swift；`keyboardShortcut` 仍在 MenuContentView 内恰好 1 次。判据一个数字都没放宽。
- **Verification**：`button=1 foreach=1 shortcut_mod=1 shortcut=1`，`bash test.sh` 菜单门全绿。
- **Committed in:** `a8edc4b`

**5. [Rule 1 - 判据环境适配] 计划的 `src_count` 传单文件返回 -1**
- **Issue**：plan 的 verify 把 `Sources/.../SettingsPresentation.swift` 这类**文件**路径传给 test.sh 的 `src_count`，而后者有 `[ -d "$dir" ]` 守卫 → 返回 -1，A1~A6/M1~M4 全部判红。
- **Fix**：verify 脚本加文件分支（单文件直接剥注释计数），目录分支逐字不变。04-03 同款先例。
- **Committed in:** 不适用（verify 脚本不入库）

**6. [Rule 1 - 判据环境适配] 变异红日志的 `error:` 计数恒 ≥ 1**
- **Issue**：XCTest 的断言失败行自带 `error: -[...] : XCTAssert...` 前缀，裸 `grep -c 'error:'` 对断言型红光恒 ≥ 1（实测 2 条全是断言行）。04-01/04-03 已各自记过同款。
- **Fix**：改为编译器诊断独有形态（`:line:col: error:` / `error: SwiftCompile` / `EmitSwiftModule` / `link`），实测 0。D-16 意图（红来自断言而非编译失败）完整保留。
- **Committed in:** 不适用（verify 脚本不入库）

**7. [Rule 1 - Plan 事实错误] 探针 seeding 机制不可用**
- **Found during:** Task 1 探针首跑
- **Issue**：plan 写「argument domain（`-rate 1.5` 参数域）」。实测 `UserDefaults.object(forKey:)` 对 argument domain 返回 `NSTaggedPointerString`，`as? Float` / `as? Bool` 均转不成（返回 nil）→ store 读到的是 seed 默认值，BOOT 断言必然红。
- **Fix**：改用进程名域 `defaults write Pic rate -float 1.5`（`.build/debug/Pic` 的进程名即 Pic；实测回 NSNumber、三处类型转换全部成立）。跑前跑后 `defaults delete Pic` 清场，不碰 com.local.pic（打包域）。实测 `PIC_SETTINGS_BOOT rate=1.5 volume=0.5 muted=1` 逐字回读。
- **Committed in:** `ff4c335`

**8. [Rule 3 - Blocking] `PicOpenSettings` 通知桥在启动期收不到**
- **Found during:** Task 1 探针首跑（`PROBE_WINDOW=missing`，窗口从未打开）
- **Issue**：`MenuBarExtra` 的菜单内容是**打开菜单时才构建**的，放 `.onReceive` 的 MenuContentView 在 `--open-settings` 触发时根本不存在。
- **Fix**：订阅移到常驻的 MenuBarExtra label 视图（`MenuBarLabel`），仍调用户路径的两个函数（presentSettingsWindow + openWindow），不开第二个入口。
- **Verification**：`PIC_SETTINGS_WINDOW width=780 minWidth=680` 实测出现。
- **Committed in:** `ff4c335`

**9. [Rule 3 - Blocking] pbxproj：app 目标 universal 构建找不到包产物**
- **Found during:** Task 2 首跑（`Unable to resolve module dependency: 'PicCore'`）
- **Issue**：`destination 'platform=macOS'` 泛化 → app target 编 x86_64+arm64，而包产物只编了 arm64，x86_64 那条腿找不到 `PicCore.swiftmodule`。
- **Fix**：两个 target 的四个构建设置显式 `ARCHS = arm64`。
- **Committed in:** `c0ee480`

**10. [Rule 3 - Blocking] 目标名与 SPM 产品名冲突**
- **Found during:** Task 2（`The bundle identifier for PicApp couldn't be read. No such file or directory: …/Debug/PicApp`）
- **Issue**：app target 名与包的可执行产品同名时，测试 runner 解析到的是裸二进制路径而非 `.app`。
- **Fix**：target 名改 `PicApp`（**产物不变**：`Pic.app` / `com.local.pic` / 可执行名 `Pic`），`TEST_TARGET_NAME` 与 scheme BlueprintName 同步。
- **Committed in:** `c0ee480`

**11. [Rule 3 - SDK API 变更] 两条 XCUITest API 在 SDK 27 改了名字**
- **Issue**：`XCUIApplication.State.running`（SDK 27 起 case 改名，`.notRunning` 现为大写开头）与 `typeKey(_:modifiers:)` → `typeKey(_:modifierFlags:)`。
- **Fix**：进程活断言改为 `XCTAssertNotEqual(app.state, .notRunning)`（等价且不依赖具体 case 名）；`modifierFlags:` 改名。
- **Committed in:** `c0ee480`（typeKey 那一处随后随 Deviation 14 整条改写）

**12. [Rule 1 - 竞态] 单个 `xcodebuild test` 间歇失败**
- **Issue**：实测「The bundle identifier for PicApp couldn't be read」间歇复现，同源码重跑即过（边建边测时的产物解析竞态）。
- **Fix**：runner 拆成 `build-for-testing` + `test-without-building`，由生成的 `.xctestrun` 带 `UITargetAppPath` 再跑。
- **Committed in:** `ffd0777`

**13. [Rule 1 - 环境状态污染] 宽度断言依赖 SwiftUI 的窗口 frame 记忆**
- **Issue**：SwiftUI `Window(id:)` 把 frame 自动存进 bundle-id 域（实测 `NSWindow Frame settings = … 680 …`），任何一次历史改宽都会让「打开即 780」失真。且测试内的 `defaults delete` 被 cfprefsd 缓存吃掉（连续三轮：2 绿 1 红）。
- **Fix**：清理放 runner（起测前删 + 轮询确认 cfprefsd 落地，落地读数 `FRAME_STATE_CLEAR=ok`），不放测试内。
- **Committed in:** `ffd0777`

**14. [Rule 3 - UAT 反馈] ⌘, 用例向系统发真实按键、误开「系统设置」**
- **Found during:** UAT 反馈「跑 XCUITest 时宿主反复弹打开系统设置」+ 我方自查确认
- **Issue**：`app.typeKey(",", .command)` 发的是**系统级**按键。本 app 是 `.accessory`（菜单栏）app，`activate()` 后无 key window，该键被系统接管去打开「系统设置」。这既证不了产品，又反复污染用户机器；而且那三轮「通过」开的是系统设置不是产品窗口，**那三轮的绿不成立**。
- **Fix**：用例改写为 `testSettingsMenuItemRendersShortcutAndOpensWindow`（点菜单栏图标 → 断言菜单项逐字是「打开设置 ⌘,」→ 点它开窗），零系统级按键。⌘, 的实际按键响应登记 `W-2026-10-03-49`（含「恢复 typeKey 前必须先能不发系统按键地证明它」的解开条件）。
- **Committed in:** `ffd0777`

**15. [Rule 1 - 编号纪律] 屏幕录制 SKIPPED 分支的 W 号取 -48 而非协调员给的 -27**
- **Issue**：05-02 已把 `-27` 标记为 **moot（不回收）**（原 IBM Plex Mono 回退场景，2026-10-03 拍板用系统默认后该场景不存在）。重用它会让一个号有两种含义，破坏 D-18（全 Phase 唯一 + `uniq -d` 为 0）。
- **Fix**：改用第一个空号 `-48`，并在脚本头写明为什么不用 -27。`uniq -d` 实测 0。
- **Committed in:** `ffd0777`

**16. [Rule 1 - D-17] 探针日志不落两遍**
- **Issue**：初版把 stderr 与证据文件 `cat` 一起进 `$LOG`，emit 的 mirror 让每一行出现两遍（TICK 计数读起来翻倍）。
- **Fix**：`$LOG` 只落 stderr（唯一原始流），证据文件单独断言（`PROBE_MIRROR=ok`）—— 证明的是桥可用，不是第二个数据源。
- **Committed in:** `ff4c335`

---

**Total deviations:** 16 auto-fixed（2 × Rule 1 计划事实错误 / 5 × Rule 3 阻塞 / 5 × Rule 1 判据与状态污染 / 2 × Rule 3 SDK·环境适配 / 1 × Rule 1 编号纪律 / 1 × Rule 1 D-17）
**Impact on plan:** 全部为让判据**本身**可达成或让产品代码**编得过**而修，**无一放宽读数、无一改产物值凑判据**。两处改变了产品代码的形状（MenuShortcut 应用入口移出菜单文件、通知桥移到 MenuBarLabel），均为等价迁移且各有探针/测试读数兜底。

## Issues Encountered

- **XCUITest 未达绿 —— 这是本 plan 停在 `halted` 的唯一原因。** 末次 `evidence/uitest.log` 记的是**修复前**用例集的读数：3 条里 2 条 passed（关窗进程不退、⌘, 开窗 —— 后者的绿已判无效）、`testWindowOpensAt780WideViaDebugSwitch` 以 680 红。改写后的用例集（`ffd0777`）**从未重跑**。我没有拿旧证据冒充新绿，也没有在用户反馈「反复弹系统设置 / 重复跑同一个测试」后继续跑 —— 一个会污染用户机器的测试循环，停掉比跑完更重要。
  - 一次命令即可解除：`bash scripts/run-uitests.sh`（当前会话解锁且屏幕录制已授权 → 走 passed 分支；两条守卫分支会各自要求 W 条目在册，均已登记）。
- **探针证据里的人为痕迹**：某次采集的 log 里出现 `PIC_MENU_ACTION=next_video`（采集期间有人点了菜单栏）。不影响任何断言（该判据不数菜单动作），已在 `36b9ce8` 的复采中消失。

## User Setup Required

None —— 无外部服务配置。

## Next Phase Readiness

- **给 05-02/05-03 的直接接口**：`SettingsApplier.applyVolume/applyMuted/applyAudioTrio` 已就位待接线；`SettingsSessionState`/空态/运行状态/来源卡仍归 05-03；模式与轮换的当场生效点（`RotationController.mode`）尚未接。
- **给 05-04 的两条硬提醒**：
  1. `evidence/uitest.log` 是**过期读数**（修复前），05-04 的收口门禁若直接消费它会拿到误导性的 `UITEST_STATUS=failed`；先重跑 `run-uitests.sh` 再判定。
  2. `run-uitests.sh` 现有**三条**状态分支：`passed` / `blocked`（锁屏，需 W-25）/ `skipped`（屏幕录制未授权，需 W-48），05-04 的门禁要能区分三者，别把 skipped 当 passed。
- **未证明的三项**（都进了 `W-2026-10-03-49` 或 coverage 的 `human_judgment: true`）：⌘, 的实际按键响应、UI 视觉形态、速度滑杆的 UI 拖动链路（机制层已由单测证明，拖动这一步无自动化证据）。
- **本 worktree 的 globals**：`com.local.pic` 域的 `NSWindow Frame settings` 由 runner 反复清理；`.build/debug/Pic` 进程名域 `Pic` 由 probe 用完即删。

---

*Phase: 05-settings*
*Completed: 2026-10-03（Task 1 全绿；Task 2 的 xcodeproj/运行器已交付，XCUITest 未达绿 → halted）*