---
phase: 05-settings
plan: 02
subsystem: ui
tags: [swift, swiftui, settings, binding, hold-arbiter, rotation, probe, evidence, uitests]

# Dependency graph
requires:
  - phase: 04-media-library
    provides: RotationController.mode（可直写即生效）/ setInterval（04-02 为 Phase 5 预留的「当场重排程」落点）/ PlayMode.allCases 锁序
  - phase: 02-playback-core
    provides: PlayerController.setRate/setVolume/setMuted（D-13）+ SettingsStore 7 键冻结（D-03）
  - phase: 03-system-events
    provides: BatteryHoldPolicy.shouldHold 纯函数 + PowerWatcher 的同步起始回调契约 + HoldArbiter.set
provides:
  - SettingsPresentation：轮换值表 [5,10,15,30,60,120]、秒↔分钟换算（就近吸附）、rotationLabel、playModeLabel
  - SettingsPresentation 的两条置灰联动纯函数（rotationControlsEnabled / volumeControlsEnabled）—— UI-03 单测与变异靶点
  - SettingsApplier：attach(rotation:) + applyMode / applyInterval / applyBatteryPolicy（**全仓唯一一处 arbiter.set(.battery**）
  - AppDelegate：recordPowerState + reapplyBatteryHold（电源跃迁与设置窗 toggle 共用同一映射）
  - SettingsView：六个可调项全真绑定，窗口内零「渲染假数据」@State；7 个 accessibilityIdentifier
  - GlowSlider 读 @Environment(\.isEnabled) —— 自绘手势从此认 `.disabled`
  - scripts/probe-settings-restart.sh：三轮重启读回探针（锁屏可跑）
  - W-2026-10-03-28（UI 交互半边未自动验证的记账）
affects: [05-03（空态/运行状态/来源卡接线；playableCount @State 仍在等真数据）, 05-04（收口门禁要消费 settings-restart.log；uitest.log 仍是过期读数）, 06-transcode（转码窗口接线）, Phase 7 SYS-01（开机自启行为接线）, 04 轮换（可选择性把 rescanAndApply 的直写改走 applier —— 本 plan 未动，见 Deviations 5）]

actuals:
  tokens: 144    # chars/4 over the realized diff（577+49 行）
  tasks: 2
  commits: 3

tech-stack:
  added: []
  patterns:
    - 「当场生效」五段式闭环：控件事件 → store.<键> 写入 → `SettingsApplier.apply*`（唯一落点）→ 播放内核公开面 → `store.persist()`（toggle 立即；滑杆仅拖动结束一次）
    - `Binding(get:set:)` 当注入面：SwiftUI 组件的 `@Binding` 换成 store 直通的 Binding，窗口内因此不需要任何「渲染真值的 @State」副本
    - 自绘手势控件必须自己读 `@Environment(\.isEnabled)`：`.disabled(true)` 对原生控件生效，对 `DragGesture` 不生效 —— UI-03「禁的是交互不是视力」在自造成本上要补这一行

key-files:
  created:
    - scripts/probe-settings-restart.sh
    - .planning/phases/05-settings/evidence/settings-restart.log
    - .planning/phases/05-settings/evidence/settings-apply.log
  modified:
    - Sources/PicCore/App/SettingsPresentation.swift
    - Sources/PicCore/App/SettingsApplier.swift
    - Sources/PicApp/Settings/SettingsView.swift
    - Sources/PicApp/Settings/SettingsComponents.swift
    - Sources/PicApp/AppDelegate.swift
    - Sources/PicApp/PicApp.swift
    - Tests/PicCoreTests/SettingsPresentationTests.swift
    - Tests/PicCoreTests/SettingsApplierTests.swift
    - .planning/WINDOWS.md

key-decisions:
  - "「当场生效」的第五项（模式/轮换/电池）也走 SettingsApplier，而不是让视图直写 RotationController/arbiter —— 与 rate/volume/muted 同型，避免 SettingsView 长出第二个落点"
  - "`.battery` 的 set 从 AppDelegate 的 powerWatcher 闭包**搬**进 SettingsApplier.applyBatteryPolicy，AppDelegate 侧只留 `recordPowerState`（记 lastIsOnBattery）与 `reapplyBatteryHold`（读 lastIsOnBattery 重估）两个薄壳。搬家不复制：两处 set 会在电源跃迁与用户 toggle 之间产生竞态双写（T-05-06）"
  - "设置窗不持有 AppDelegate：电池重估经 PicApp 注入的 `reapplyBatteryHold` 闭包，与 terminate/presentSettings 同型"
  - "开机自启保留本地 @State（7 键冻结），行内注释按 UI-SPEC §12 原文登记 `// 行为接线：Phase 7 SYS-01`；可 grep 代理门：`launchAtLogin` 在 Sources/PicCore 计数 == 0"
  - "自启状态**不入 store**，但行内的 accessibilityIdentifier 与两条联动一起加齐（7 个 id），让 05-04 的 XCUITest 有稳定的定位锚点"
  - "字体零改动即达标：05-01 已把 mono 落成系统等宽，本 plan 只验不动（ttf/FontLoader/CTFontManager/NSFont(name: 四门全 0），Package.swift / build.sh / .xcodeproj 零改动"
  - "探针第 ③ 轮必须先 `defaults delete Pic`：进程名域是**持久**的（05-01 的 seeding 修正），不清场就会读到上一轮的值，「回默认值」这一轮就没了"

patterns-established:
  - "`src_count` 的单文件分支（05-01 Deviation 5 的第 ④ 次沿用）：判据里出现文件路径时先 `dirname` 再走目录分支，否则 `[ -d ]` 守卫返回 -1 让全部判据假红"
  - "变异红日志的编译器诊断计数仍用 `:line:col: error:` 形态（05-01 Deviation 6 的第 ② 次沿用）；注意 XCTest 的失败行是 `… : XCTAssert… failed`，必须先剥 ANSI（`sed 's/\x1b\[[0-9;]*m//g'`）再 grep，否则 0 命中"
  - "「判据数字对不上」先数现状：本 plan 的 `SettingsApplierTests` 目标 9 条，实到 8 条（计划点名的第 5 条 held-volume 已被 05-01 的 `testVolumeAndMutedApplyWithoutGate` 覆盖，不重复写）"

requirements-completed: [PLAY-08, PLAY-09, PLAY-10, TEST-04, UI-03]

# Coverage metadata (#1602)
coverage:
  - id: D1
    description: "六个可调项（模式/轮换/速度/音量/声音/电池）全部读写 SettingsStore、经 SettingsApplier 当场生效、改完 persist —— 窗口内零「渲染假数据」@State"
    verification:
      - kind: unit
        ref: "Tests/PicCoreTests/SettingsApplierTests.swift — Executed 8 tests, with 0 failures（其中 applyMode/applyInterval/applyBatteryPolicy 两条方向共 4 条为本次新增）"
        status: pass
      - kind: other
        ref: "src_count 门：SettingsView 内 launchAtLogin=2 / disabled(=3 / NSOpenPanel=0；Sources/PicCore 内 launchAtLogin=0；SettingsStore.swift 零 diff"
        status: pass
    human_judgment: false
  - id: D2
    description: "两条置灰联动（loopSingle→轮换整行 / isMuted→音量滑杆）既置灰又禁交互"
    verification:
      - kind: unit
        ref: "Tests/PicCoreTests/SettingsPresentationTests.swift#testRotationControlsDisabledOnlyForLoopSingle / #testVolumeControlsDisabledOnlyWhenMuted — Executed 12 tests, with 0 failures"
        status: pass
      - kind: other
        ref: "变异 MUT-P5-LINK-ROT：MUT=1，RC=1，失败恰为 testRotationControlsDisabledOnlyForLoopSingle（XCTAssertFalse failed），编译器诊断形态 0，恢复后 cmp -s 一致；变异 MUT-P5-LINK-VOL 同型（失败恰为 testVolumeControlsDisabledOnlyWhenMuted）"
        status: pass
    human_judgment: true
    rationale: "纯函数与 `.disabled(true)` 调用已证明；**「点不动」在真实指针交互下不生效**这一跳只到代码形态 —— `.disabled` 对自绘 DragGesture 不生效是我们自己补的 `@Environment(\.isEnabled)`，XCUITest 的 isEnabled 断言归 05-04"
  - id: D3
    description: "电池 toggle 当场重估，且 arbiter.set(.battery 在全仓仍是唯一落点"
    verification:
      - kind: unit
        ref: "Tests/PicCoreTests/SettingsApplierTests.swift#testBatteryPolicyReappliesWithSameMapping / #testBatteryPolicyClearsHoldIdempotently"
        status: pass
      - kind: other
        ref: "src_count：Sources 内 arbiter.set(.battery=1、BatteryHoldPolicy.shouldHold=1；探针运行期证据 evidence/settings-restart.log 的 APPLY_BATTERY_LINES_3ROUNDS=3（三轮各恰好一行，APPLY_BATTERY_SINGLE_SITE=ok）"
        status: pass
    human_judgment: false
  - id: D4
    description: "重启保留（TEST-04 可自动化半边）：改值 → 重启 → 回读一致；无 seeding 时回默认值"
    verification:
      - kind: other
        ref: "bash scripts/probe-settings-restart.sh → PROBE_RC=0；evidence/settings-restart.log 的 ROUND1_SEEDED=ok / ROUND2_IDEMPOTENT=ok / ROUND3_DEFAULTS=ok"
        status: pass
    human_judgment: false
  - id: D5
    description: "字体走系统默认、零打包（2026-10-03 拍板）：零字体文件、零注册代码、mono 无散落分支"
    verification:
      - kind: other
        ref: "FONT_GATES ttf=0 loader=0 ctfontmgr=0 nsfont=0；RESOURCE_DIFF_LINES=0（Package.swift / build.sh / Pic.xcodeproj/project.pbxproj 自 f7743d7 起零改动）"
        status: pass
    human_judgment: false
  - id: D6
    description: "UI 事件 → apply 的运行期证据行（PIC_SETTINGS_APPLY 除电池外的那五条）"
    verification: []
    human_judgment: true
    rationale: "探针只驱动到 wiring()，控件事件无人触发；evidence/settings-apply.log 如实记 APPLY_RUNTIME_LINES=3（三条全是电池那一条）而不是省略。已登记 W-2026-10-03-28，解开条件是 05-04 的 XCUITest 或人工拖一次"
  - id: D7
    description: "设置窗六行的视觉形态与两条联动的观感（置灰透明度在 B1 深海背景上是否还读得清）"
    verification: []
    human_judgment: true
    rationale: "opacity 0.34 与 UI-SPEC §8 的数值逐字一致，但没有任何截图或人眼比对；且本轮把原来「模式行 index 0 → 置灰」的手写判断换成纯函数后，视觉读数未复核"

# Metrics
duration: 58min
completed: 2026-10-03
status: complete
---

# Phase 5 Plan 02: 六项绑定当场生效 + 两条置灰联动 Summary

**把 05-01 的「一条路」铺成六项全绑定 —— 模式/轮换/速度/音量/声音/电池时播放改完当场生效 + persist + 重启回读，外加两条真正禁交互的置灰联动；字体按 2026-10-03 拍板零打包走系统默认。**

## Performance

- **Duration:** 58 min
- **Started:** 2026-10-03T14:10:00Z
- **Completed:** 2026-10-03T15:07:57Z
- **Tasks:** 2
- **Files modified:** 13（+577 / -49）

## Accomplishments

- **两条置灰联动有牙齿**：变异 `MUT-P5-LINK-ROT` / `MUT-P5-LINK-VOL` 各恰好 1 处标记，红光来自断言（编译器诊断形态 0，恢复后逐字节一致），失败用例恰好是对应那一条。判据不是新写的措辞，是会被它打红的东西。
- **`.battery` 的单一 set 落点在运行期被证明**：闭包从 AppDelegate 搬进 `SettingsApplier.applyBatteryPolicy`，源计数 == 1，探针里**三轮各恰好一行** `PIC_SETTINGS_APPLY key=pauseOnBattery …` —— 搬家不复制这条不是只有静态计数撑着。
- **重启保留三轮全绿**：seeding 六值逐字回读 → 同参数重跑逐字一致 → 清场后回 seed 默认值。这比计划的 argument domain 更强：进程名域是持久的，等价于真的「改值→重启→回读」。
- **发现并补上一条真缺口**：`.disabled(true)` 对 `GlowSlider` 的自绘 `DragGesture` **不生效** —— UI-03 明写「禁用交互不是只调透明度」，所以 `GlowSlider` 现在自己读 `@Environment(\.isEnabled)`。没有这条，两条联动在 UI 上只是变淡，照样能拖。
- **`arbiter.set(.battery` 与 `BatteryHoldPolicy.shouldHold` 全仓各 1 处**；`SettingsStore` 七键零 diff；`Package.swift`/`build.sh`/`.xcodeproj` 零 diff。

## Task Commits

1. **Task 1 RED: 六项绑定与两条联动的判据** — `af18e84` (test)
2. **Task 1 GREEN: 实现面（Presentation/Applier/View/Components/AppDelegate/PicApp）** — `23a8c65` (feat)
3. **Task 2: 重启保留探针 + 两份 evidence + W-28 登记** — `0e0d918` (feat)

_Task 1 是 `tdd="true"`：RED 必须真红（实现前 build failed），GREEN 后 REFACTOR 无改动故无 refactor 提交。_

## Files Created/Modified

- `Sources/PicCore/App/SettingsPresentation.swift` — 轮换值表/换算（就近吸附）/rotationLabel/playModeLabel + 两条联动纯函数（变异靶点，判据字面量只在 return 行，D-15）
- `Sources/PicCore/App/SettingsApplier.swift` — `attach(rotation:)` + `applyMode`/`applyInterval`/`applyBatteryPolicy`；`.battery` 的全仓唯一 set 落点；仍零 AVFoundation/SwiftUI/AppKit import
- `Sources/PicApp/AppDelegate.swift` — powerWatcher 闭包改为 `recordPowerState`；新增 `lastIsOnBattery` + `reapplyBatteryHold()`；`wiring()` 里 `settingsApplier.attach(rotation:)`。**`startWallpaper()` 尾段与 B1 门一个字符未动**
- `Sources/PicApp/Settings/SettingsView.swift` — 六个 Binding 取代五处 seeded @State；两条联动 `.disabled` + opacity 0.34；7 个 accessibilityIdentifier；`reapplyBatteryHold` 闭包注入
- `Sources/PicApp/Settings/SettingsComponents.swift` — GlowSlider 读 `isEnabled`；步进器读数改走 `SettingsPresentation.rotationLabel`（消除第二份换算）
- `Sources/PicApp/PicApp.swift` — 注入 `reapplyBatteryHold`
- `scripts/probe-settings-restart.sh` + 两份 evidence — 三轮探针
- `.planning/WINDOWS.md` — 新增 `W-2026-10-03-28`（-27 仍 moot 未回收）

## Decisions Made

1. **模式/轮换/电池也走 `SettingsApplier`**，不让视图直写 `RotationController` / `arbiter`。理由是速度/音量/静音已经确立了这条路径，第二条路只是等着漂移。
2. **`.battery` 搬进 applier，AppDelegate 只剩两个薄壳**：`recordPowerState`（记状态）与 `reapplyBatteryHold`（读状态重估）。电源跃迁与设置窗 toggle 走同一个方法。
3. **电池 toggle 的 persist 顺序是「先写盘再重估」**：`store.persist()` → `reapplyBatteryHold()`。重估读的是内存里的 store，写盘先后不影响决策，但让「改完立刻落盘」在时序上成立。
4. **字体本 plan 零改动即达标** —— 05-01 已经把 `mono` 落成系统等宽，四道字体门（ttf / FontLoader / CTFontManager / NSFont(name:）本轮实测全 0。原 IBM Plex Mono 打包链路整体取消，`W-2026-10-03-27` 随之 moot（号不回收）。

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `SettingsComponents.swift` 缺 `import PicCore`**
- **Found during:** Task 1 首次 `swift build`
- **Issue**：步进器读数改走 `SettingsPresentation.rotationLabel` 后，该文件只 import 了 SwiftUI。
- **Fix**：加一行 `import PicCore`。
- **Verification**：`swift build` 0 error。
- **Committed in:** `23a8c65`

**2. [Rule 1 - 我的测试算错] 就近吸附用例把「299 秒」写成了「299 分钟」**
- **Found during:** Task 1 GREEN 首跑（2 条红）
- **Issue**：`rotationMinutes(seconds: 299*60)` 等于 299 分钟，最近表项是 120 而不是 5，用例期望写反了；生产实现没错。
- **Fix**：用例改成 `seconds: 299`（≈4.98 分钟 → 5）、`302`、以及 `111*60` → 120。
- **Verification**：`Executed 12 tests, with 0 failures`。
- **Committed in:** `23a8c65`

**3. [Rule 3 - Blocking] `makeApplier(arbiter: HoldArbiter = HoldArbiter())` 编不过**
- **Found during:** Task 1 GREEN 首跑
- **Issue**：默认参数表达式在 nonisolated 上求值，`HoldArbiter.init` 是 `@MainActor`。
- **Fix**：去掉默认值，四个调用点显式传。
- **Committed in:** `23a8c65`

**4. [Rule 3 - Blocking] 视图里 `volumePercent` 既当 Binding 又当数值用，`.rounded()` 解析错**
- **Found during:** Task 1 `swift build`
- **Issue**：属性名 `volumePercent` 遮蔽了 `Int(...)` 的取整链，编译器把 `.rounded` 解析到 `Binding` 上。
- **Fix**：onChanged 与标签两处都改走静态函数 `SettingsPresentation.volumePercent(store.volume)`，Binding 只作为 `GlowSlider` 的取址参数。
- **Committed in:** `23a8c65`

**5. [Rule 1 - 判据与现状不符] `SettingsApplierTests` 的目标条数 9 → 实到 8**
- **Found during:** Task 1 验收自检
- **Issue**：计划点名的第 5 条「held 下 applyVolume 落位（`PIC_` 不受门影响）」在 05-01 已有 `testVolumeAndMutedApplyWithoutGate`，重复写一条同义用例是纯膨胀。
- **Fix**：按计划 `fails_when` 明写的口子「条数以文件里 `func test` 实际数回填判据数字」回填为 8；既有断言一条未删。第 5 条改写成真有覆盖面的 `testBatteryPolicyClearsHoldIdempotently`（**解除方向** + 幂等，05-01 从未测过）。
- **Verification**：`Executed 8 tests, with 0 failures`。
- **Committed in:** `23a8c65`

**6. [Rule 1 - 计划事实错误] 探针的 argument domain seeding 不可用（第 2 次）**
- **Found during:** Task 2 写探针
- **Issue**：计划第二轮写 `.build/debug/Pic … -rate 1.75 -volume 0.35 …`。05-01 已实测：argument domain 下 `UserDefaults.object(forKey:)` 返回 `NSTaggedPointerString`，`as? Float` / `as? Bool` 转不成，store 读到 seed 默认值 → BOOT 断言必然红。
- **Fix**：沿用 05-01 的进程名域 `defaults write Pic …`（`.build/debug/Pic` 进程名即 Pic）。**连带一个新后果**：进程名域是持久的，第 ③ 轮「无 seeding 回默认值」必须先 `defaults delete Pic` 清场，否则读到上一轮的值 —— 计划原文按 argument domain 写的那一轮（`⚠️ 若本机 com.local.pic 域有历史值…`）漏了这一步。
- **Verification**：三轮全绿。
- **Committed in:** `0e0d918`

**7. [Rule 2 - 缺真实落点] `settings-apply.log` 原本无处可产**
- **Found during:** Task 2
- **Issue**：计划说该文件「复用 probe-settings.sh 的输出并追加 `PIC_SETTINGS_APPLY` 行检查」，但启动路径本身不触发任何 apply（apply 由控件事件驱动），照写会得到一个永远为空或永远「missing」的产物。
- **Fix**：先按实测把探针跑一遍再定形状 —— 结果**电池那一条确实会在运行期出现**（`powerWatcher.start` 的同步回调 → `recordPowerState` → `applyBatteryPolicy`），于是把它变成真断言：`ROUND1_APPLY_BATTERY=ok` + `APPLY_BATTERY_SINGLE_SITE=ok`（三轮恰好各一行）。其余五条如实记 `APPLY_RUNTIME_LINES` 的实测值与「无 UI 交互即不触发」，并在 W-28 里登记，不拿 emit 落点数冒充运行期证据。
- **Verification**：`PROBE_RC=0`；`evidence/settings-apply.log` 的 `APPLY_EMIT_SITES=7` / `APPLY_RUNTIME_LINES=3`。
- **Committed in:** `0e0d918`

**8. [Rule 3 - Blocking] 探针第 ① 轮后的三轮计数读到还没生成的文件**
- **Found during:** Task 2 探针首跑
- **Issue**：`grep -c … r1.ev r2.ev r3.ev` 写在第 ① 轮之后，r2/r3 的证据文件尚未生成。
- **Fix**：把三轮计数段移到三轮跑完之后。
- **Verification**：`PROBE_RC=0`。
- **Committed in:** `0e0d918`

**9. [Rule 1 - 判据环境适配，沿用 05-01 Deviation 5/6] verify 脚本要加单文件分支 + 剥 ANSI**
- **Issue**：计划 `<automated>` 里的 `src_count` 传的是文件路径（`[ -d ]` 守卫会返回 -1）；`grep -c 'error:'` 对断言型红光恒 ≥ 1。
- **Fix**：`src_count` 加文件分支（先 `dirname`）；编译器诊断计数改用 `:line:col: error:` 并先 `sed` 剥 ANSI。判据语义与数字一个未放宽。
- **Committed in:** 不适用（verify 脚本不入库）

---

**Total deviations:** 9 auto-fixed（1 × Rule 3 编译阻塞 ×3 / 1 × Rule 1 我自己写错 / 1 × Rule 1 判据与现状不符 / 1 × Rule 1 计划事实错误 / 1 × Rule 2 缺真实落点 / 1 × Rule 1 判据环境适配 ×1 / 1 × Rule 3 探针脚本时序）
**Impact on plan:** 九条里没有一条放宽读数或改产物凑判据。三条改了产品代码的形状（`import PicCore`、Binding 取值、`.rounded` 链），全是编译/解析修正，语义等价；两条改了**判据本身**（条数 9→8 回填、verify 的 ANSI 剥离），都按计划 `fails_when` 预留的口子做且一个数字没放松；两条把计划里写错的事实（argument domain、evidence 无落点）按实测改形。**没有触碰 Phase 4 的公开面，也没有碰 `SettingsStore` 的七键。**

## Issues Encountered

- **UI 交互半边仍未跑**（同 05-01 的 halted 面）：本 plan 的探针只驱动到 `wiring()`，设置窗里的「拖一次滑杆 → 看播放器变」这一跳没有运行期证据。已登记 `W-2026-10-03-28`，`evidence/settings-apply.log` 里如实记 `APPLY_RUNTIME_LINES=3（三条全是电池那一条）`。两条置灰联动的「点不动」同理 —— XCUITest 断言归 05-04。
- **一处刻意的未动**：`AppDelegate.rescanAndApply()` 里的 `rotation.setMode` / `setInterval` 仍是 04-05 的直写形状，没有改走 `SettingsApplier`。改它是更彻底的「单一落点」，但会动 Phase 4 的装配路径，且计划 Task 1 的 AppDelegate 动作只点名了 powerWatcher 抽取与 `attach(rotation:)`。**留给 05-04 或 Phase 6 的接线决定**，不在本 plan 顺手改。
- **`SettingsView` 的 `playableCount` 仍是 @State = 0**（空态/来源卡的真数据在 05-03 接线）。它不是「渲染假数据的假绑定」，但确实是下一波要收掉的最后一个。

## User Setup Required

None —— 无外部服务配置。

## Next Phase Readiness

- **给 05-03 的直接接口**：`SettingsView` 现在只剩 `playableCount` 一个待接 @State；六项真绑定 + 两条联动 + 7 个 accessibilityIdentifier 都已就位，05-03 接 `MediaLibraryReport.playableCount` 与空态皮时不需要动本轮的绑定结构。
- **给 05-04 的三条硬提醒**：
  1. `evidence/uitest.log` 仍是 **05-01 留下的过期读数**（修复前的用例集），收口门禁若直接消费会拿到误导性的结论；先重跑 `run-uitests.sh`。
  2. 两条置灰联动的 XCUITest 断言现在**可以**写了：identifier 已加齐（`mode-segmented` / `rotation-stepper` / `volume-slider` / `volume-value` / `sound-toggle` / `battery-toggle` / `transcode-open`），且 `GlowSlider` 的禁用是真禁用（`isEnabled` 已接），`isEnabled == false` 的断言应当成立。
  3. 新证据可消费：`evidence/settings-restart.log`（三轮 + 电池 apply 单点）与 `evidence/settings-apply.log`。
- **待收的 W 条目**：-28（交互半边，open）、-25 / -48（`run-uitests.sh` 的两条守卫分支未走过）、-49（⌘, 按键响应）。**-27 仍 moot，未回收。**
- **本 worktree 的 globals**：`.build/debug/Pic` 的进程名域 `Pic` 由新探针用完即 `defaults delete Pic` 清场；不碰 `com.local.pic`。

---
*Phase: 05-settings*
*Completed: 2026-10-03（Task 1 全绿含两条变异反向验证；Task 2 探针三轮全绿 + W-28 登记）*