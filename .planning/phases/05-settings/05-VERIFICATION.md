---
phase: 05-settings
verified: 2026-10-04T00:26:13Z
status: human_needed
score: 7/9 must-haves verified
covered_files:
  - .planning/phases/05-settings/05-01-PLAN.md
  - .planning/phases/05-settings/05-01-SUMMARY.md
  - .planning/phases/05-settings/05-02-PLAN.md
  - .planning/phases/05-settings/05-02-SUMMARY.md
  - .planning/phases/05-settings/05-03-PLAN.md
  - .planning/phases/05-settings/05-03-SUMMARY.md
  - .planning/phases/05-settings/05-04-PLAN.md
  - .planning/phases/05-settings/05-04-SUMMARY.md
  - .planning/phases/05-settings/UI-SPEC.md
  - .planning/phases/05-settings/evidence/settings-apply.log
  - .planning/phases/05-settings/evidence/settings-restart.log
  - .planning/phases/05-settings/evidence/settings-tracer.log
  - .planning/phases/05-settings/evidence/status-card.log
  - .planning/phases/05-settings/evidence/test-sh-phase5.log
  - .planning/phases/05-settings/evidence/uitest.log
  - Pic.xcodeproj/project.pbxproj
  - Sources/PicApp/App/MenuContentView.swift
  - Sources/PicApp/AppDelegate.swift
  - Sources/PicApp/PicApp.swift
  - Sources/PicApp/Settings/SettingsComponents.swift
  - Sources/PicApp/Settings/SettingsSessionState.swift
  - Sources/PicApp/Settings/SettingsView.swift
  - Sources/PicCore/App/FFmpegAvailability.swift
  - Sources/PicCore/App/SettingsApplier.swift
  - Sources/PicCore/App/SettingsPresentation.swift
  - Sources/PicCore/Render/WallpaperWindowController.swift
  - Tests/PicCoreTests/FFmpegAvailabilityTests.swift
  - Tests/PicCoreTests/SettingsApplierTests.swift
  - Tests/PicCoreTests/SettingsPresentationTests.swift
  - UITests/PicUITests/SettingsControlsUITests.swift
  - UITests/PicUITests/SettingsWindowUITests.swift
  - scripts/probe-settings-restart.sh
  - scripts/probe-settings.sh
  - scripts/probe-status-card.sh
  - scripts/run-uitests.sh
  - test.sh
covered_digest: "v2:sha256:990c416458831a55bc9db5599ea5ef545e94c3991ef4b0dc419ecf4e60801fc3"
behavior_unverified: 1
behavior_unverified_items:
  - truth: "SC-1 后半句 —— 关闭设置窗只隐藏窗口，进程不退出、菜单栏图标仍在、激活策略回到 .accessory（MENUBAR-02）"
    test: "解锁会话下启动 app → 菜单栏「打开设置」开窗 → 点窗口关闭按钮 → 观察菜单栏图标是否仍在、Dock 是否无图标、进程是否存活"
    expected: "设置窗消失；进程仍在（app.state != .notRunning）；菜单栏图标仍在；Dock 无图标（activationPolicy 回到 .accessory）"
    why_human: "这是运行期状态跃迁（激活策略 + 进程生命周期），源码层只有 .onDisappear → hideSettingsAndRestorePolicy() 一处 setActivationPolicy(.accessory)，无任何测试触达；对应的 SettingsWindowUITests.testClosingWindowKeepsProcessAlive 因会话全程锁屏从未跑过（W-2026-10-03-34）"
unverified_non_inferable: 1
advisory:
  - finding: "XCUITest testAllControlsExistAndTranscodeStaysDisabled 的断言已与产品代码矛盾 —— 解锁后重跑必红"
    category: other
    reason: "Phase 6 的 9d18a81 把「转码」按钮的 .disabled(true) 换成了「只调 opacity 0.34 + 弹安装途径弹层」（SC#1 两半句同时成立的要求），但 Phase 5 留下的该用例仍断言 XCTAssertFalse(el(\"transcode-open\").isEnabled)。修法：把该断言改成「ffmpeg 可用时可点并打开转码窗 / 不可用时 opacity 变淡但仍可点并弹途径」；解锁重跑 W-2026-10-03-34 之前必须先修，否则 run-uitests.sh 会以 failed 而非 passed 收场"
    evidence_status: "确定性（源码对照，非推断）：Sources/PicApp/Settings/SettingsView.swift 的 transcode-open 按钮只有 .opacity 无 .disabled；UITests/PicUITests/SettingsControlsUITests.swift:157 断言 isEnabled == false"
  - finding: "音高保持（.spectral）零测试覆盖，W-2026-10-03-33 的「单测锁」与事实不符"
    category: other
    reason: "PlayerController.load(url:) 第 37 确有 item.audioTimePitchAlgorithm = .spectral，但 `grep -rniE 'pitch|音高|不变调|变调' Tests/ UITests/` 命中 0 —— 全仓没有任何断言锁这一行。W-2026-10-03-33 声称「Phase 2 冻结面，单测锁」不成立。后果：任何人删掉这一行，198 条单测仍全绿，SC-4 的保音高面静默失效。修法：加一条断言 item 创建后 audioTimePitchAlgorithm == .spectral 的单测"
    evidence_status: "确定性（grep 命中 0）"
  - finding: "05-04 SUMMARY 与 W-2026-10-03-34 均称「11 条 XCUITest」，实际是 10 条"
    category: other
    reason: "SettingsWindowUITests 4 条 + SettingsControlsUITests 6 条 = 10 条 `func test`。记账数字错一位，不影响任何判定；改 SUMMARY 的三处「11」与 W-34 首句即可"
    evidence_status: "确定性（逐文件计数）"
  - finding: "test.sh 的「设置窗渲染成功」门渲染的是 spike，不是产品 SettingsView"
    category: other
    reason: "test.sh:698 的 $SRC = \".planning/spike/SettingsSpike.swift .planning/spike/Render.swift\"。产品设置窗 Sources/PicApp/Settings/SettingsView.swift 从未被任何自动路径渲染过 —— B1 皮肤与 L4 双列的视觉面没有任何机器读数，只能靠活体目视"
    evidence_status: "确定性（test.sh:35 的 SRC 定义）"
  - finding: "Phase 5 的 ROADMAP 模式标为 mvp，但 Goal 不是 User Story，MVP 验证门禁无法执行"
    category: other
    reason: "user-story.validate 对 Goal 返回 valid=false（缺 \"As a …, I want …, so that …\" 三槽）。本次改按 ROADMAP 的 5 条 Success Criteria 逐条判定 —— 那 5 条本身就是可判定的契约，严于用户故事，且不依赖编造。修法：跑 /gsd mvp-phase 5 把 Goal 改写成 User Story，或把 mode 改回 null"
    evidence_status: "确定性（gsd_run query user-story.validate 返回 valid=false）"
human_verification:
  - test: "SC-4 听音 —— 以 0.5× 与 2× 各播一段**含人声**的素材，确认音高不变（纯音乐或无人声素材不算）"
    expected: "两种速度下人声音高听起来相同（只有快慢变化）"
    why_human: "自动化只能证明 .spectral 在 item 创建时已落位与 rate 当场生效；「听起来没变调」没有任何一条断言能表达。W-2026-10-03-33 明令不得拿「参数设对了」冒充「听过了」"
  - test: "解锁会话下重跑 bash scripts/run-uitests.sh（**先修 advisory 第 1 条的 transcode 断言**）"
    expected: "10 条用例全过，或每条 skip 都带 W 号且 WINDOWS.md 有配对登记（UITEST_SKIPPED= 与 W_FOR_SKIP_MISSING 检查通过）"
    why_human: "本次全程锁屏（evidence/uitest.log: SCREEN_LOCKED=1 → UITEST_STATUS=blocked reason=screen_locked），测试进程从未启动"
  - test: "解锁会话下打开设置窗，确认「壁纸来源」卡在计数 0 时数字为警告黄、感叹号瓷砖在位、空态副行逐字为「没找到能播的文件。壁纸已隐藏，桌面显示的是系统原壁纸。」"
    expected: "warn 色 #F5B544 生效；重扫按钮仍可点"
    why_human: "纯函数与文案常量已被单测逐字锁死，但产品 SettingsView 从未被任何自动路径渲染（test.sh 渲染的是 spike），屏上效果未目视"
  - test: "解锁会话下打开设置窗，确认 B1 深海皮肤 + L4 双列（左：来源/播放，右：电源与系统/维护/运行状态）且无侧边栏"
    expected: "布局与 .planning/phases/05-settings/UI-SPEC.md §7 一致"
    why_human: "几何（780/680）有活体探针读数，皮肤与布局只有源码与 spike 渲染，无产品视图的渲染证据"
  - test: "锁屏态打开设置窗，确认运行状态卡标题为「已暂停」、副标签逐字为「屏幕已锁定」"
    expected: "副标签出现且逐字一致"
    why_human: "W-2026-10-03-29 已登记；evidence/status-card.log 的 LIVE_LOCK_OBSERVATION=blocked reason=screen_locked。数据链与 6 条文案映射已被单测钉住，只缺一次屏上确认"
  - test: "关窗路径 —— 打开设置窗后点关闭，确认进程不退、菜单栏图标仍在、Dock 无图标"
    expected: "见 behavior_unverified_items 第 1 条"
    why_human: "运行期状态跃迁，无测试触达"
---

# Phase 5: 设置窗口与即时生效 — 验证报告

**Phase Goal:** 用户有一个按 UI-SPEC 定稿的设置窗；所有可调项改完**当场生效**；扫不到视频时界面明确告诉他壁纸已隐藏；任何时候都能看到「现在为什么暂停」。
**Verified:** 2026-10-04T00:26:13Z
**Status:** `human_needed`
**Re-verification:** No — 首次验证（此前 6 个 phase 中仅本 phase 缺 VERIFICATION.md）

## 验证方式声明

本报告**不采信任何 SUMMARY 声称**。9 条 must-have 逐条回到 `/Users/coderstory/dev/pic` 的真实源码、单测、
探针 evidence 与 `test.sh` 门禁上核对；结论分三类：**自动已验**（有跑过的读数）、**需人工**（环境阻塞）、
**未验**（无任何证据）。三条已知人工阻塞（SC-4 听音 / XCUITest 全未跑 / 锁屏子标签未活体观测）如实登记为
PARTIAL，未做任何粉饰。另新发现 4 项问题，见「Advisory」段 —— 其中第 1 项会直接卡住 W-34 的解开条件。

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | 设置窗打开时 780pt 宽 / contentMinSize 680，B1 深海 + L4 双列，无侧边栏（SC-1 前半 / UI-01） | ✓ VERIFIED | `SettingsPresentation.swift:12,14` 两个常量 → `SettingsView.swift:59` 唯一消费点；`testWindowConstantsMatchContract` 锁 780/680；**活体**探针读数 `evidence/settings-tracer.log: PIC_SETTINGS_WINDOW width=780 minWidth=680`（由产品视图的 `emitWindowGeometry()` 读 `NSApp.windows` 打出，非 mock）；B1 令牌 `SettingsComponents.swift:11,19`（pBg `#0A1826` / pWarn `#F5B544`，与 UI-SPEC §3 逐字一致）；`grep -rn "NavigationSplitView\|NSSplitView\|sidebar" Sources/PicApp/` 命中 0 → 无侧边栏 |
| 2 | 菜单栏「打开设置 ⌘,」可打开设置窗（MENUBAR-06） | ✓ VERIFIED | `MenuItem.swift:openSettings` → `MenuBarModel.label` 逐字「打开设置」；`MenuContentView.swift` 的 `.openSettings` 分支调 `presentSettings()` + `openWindow(id:"settings")`；`MenuShortcut` 挂 `keyboardShortcut(",", modifiers:.command)`；`MenuBarModelTests.testLabelsHaveExactlyFiveEntriesInEveryState` 锁 5 项与顺序。**局限**：XCUITest 明确不发真实 ⌘, 按键（`.accessory` app 无 key window 时会被系统接管去开「系统设置」），故按键响应面只有代码证据 |
| 3 | 空态：计数 0 → 警告黄数字 + 感叹号瓷砖 + 逐字文案「没找到能播的文件。壁纸已隐藏，桌面显示的是系统原壁纸。」（SC-2 / UI-02 / SOURCE-04） | ✓ VERIFIED | `SettingsPresentation.emptyStateBody` 全仓唯一一份；`testEmptyStateBodyMatchesSpecVerbatim` 常量相等断言 + `testEmptyStateBodyIsSingleSourced`（剥注释后计数 == 1）双锁；`testThreeHideStatesShareOneEmptySkin` 用 `LibraryState.allCases` 穷举三态一张皮；`SettingsView.swift` 空态分支 `Tile(symbol:"exclamationmark", warn:true)` + `foregroundStyle(isEmpty ? Color.pWarn : Color.pAccent)`；`settings-tracer.log: PIC_LIBRARY_STATE=no_playable_videos` 是活体读数。**局限**：产品视图的屏上渲染未目视（见 Human Verification 第 3 条） |
| 4 | 两条置灰联动**禁用交互**（非只调透明度）（SC-3 / UI-03） | ✓ VERIFIED | 判据 `rotationControlsEnabled(playMode:) = playMode != .loopSingle` 与 `volumeControlsEnabled(isMuted:) = !isMuted`，各有正反两向单测；**禁用是真的**：`GlowStepper` 用原生 `Button`，`.disabled(true)` 确实拦得住；`GlowSlider` 是自绘 `DragGesture`，`SettingsComponents.swift:78` 读 `@Environment(\.isEnabled)`，`.onChanged` 与 `.onEnded` **两处**都 `guard isEnabled else { return }`；`SettingsView.swift:100,127` 同时挂 `.disabled()` + `.opacity(0.34)`。取掉任一条联动的纯函数，对应单测即转红（断言层，非编译层） |
| 5 | 速度/声音/音量**改动当场生效**，不重启、不等下次换片（SC-4 中段 / PLAY-07~10） | ✓ VERIFIED | `GlowSlider` 的 `onChanged` 直通 `store.rate = …` → `applier.applyRate()`，`onEnded` 才 `store.persist()`（节流纪律）；`SettingsApplier.applyRate` 有 `shouldPlay` 门，门内 `PlayerController.setRate`（挂 `AVPlayer` 而非 `AVPlayerItem`，避免 looper 副本冻结）；**行为级单测**四条直接断言 `player.player.rate / volume / isMuted`：`testPlayingRateAppliesImmediately`、`testHeldPlayerDoesNotGetRateApplied`、`testVolumeAndMutedApplyWithoutGate`、`testRateReappliesAfterHoldReleased` |
| 6 | 改完重启 app 后保留（SC-4 末段 / TEST-04） | ✓ VERIFIED | **活体三轮**：`evidence/settings-restart.log` 的 `ROUND1_SEEDED=ok` / `ROUND2_IDEMPOTENT=ok` / `ROUND3_DEFAULTS=ok`，回读锚点 `PIC_SETTINGS_BOOT`（AppDelegate `emitBootSettings()`，值全部来自 store）；`SettingsStoreTests` 11 条含 `testPersistWritesBackToDefaults` / `testLaunchAtLoginDefaultsFalseAndRoundTrips` |
| 7 | 运行状态卡显示 是否暂停 + 暂停原因（全屏/锁屏/熄屏/睡眠/电池）+ ffmpeg 可用性（SC-5 / UI-04） | ✓ VERIFIED | 6 条原因文案 `testHoldReasonLabelsCoverAllSixCasesVerbatim` 逐字锁且两两不同（`HoldReason.allCases.count == 6`）；`testJoinedReasonsSortsByOrderBeforeJoining` 锁多原因排序与顿号连接（`screenLocked+manualPause` → 「手动暂停、屏幕已锁定」）；ffmpeg `FFmpegAvailability.label` 两值穷举 + `status-card.log: FFMPEG_SELF_CONSISTENT=ok available=1 label=可用`；`Process(` / `NSTask` 在 `FFmpegAvailability.swift` 剥注释后计数 0/0（零执行，test.sh 门禁同款） |
| 8 | 关闭设置窗只隐藏，进程不退出、图标仍在（MENUBAR-02） | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | 代码在位：`PicApp.swift` `.onDisappear { appDelegate.hideSettingsAndRestorePolicy() }` → `AppDelegate.swift:369` `NSApp.setActivationPolicy(.accessory)`；全仓 `NSApp.terminate` 只在 `terminateApp()` 一处（菜单退出路径），无 `terminateAfterLastWindowClosed`。但这是**运行期状态跃迁**，**没有任何测试触达** —— 对应的 `testClosingWindowKeepsProcessAlive` 因锁屏从未跑过（W-2026-10-03-34）。证据不足，不判 VERIFIED |
| 9 | 速度 0.5×–2× 且**保持原音高**（SC-4 前半 / PLAY-07 后半） | ⚠️ PARTIAL | 区间与控件：`GlowSlider(value:$rateDrag, range: 0.5...2)` + `testRateBoundsAreHalfToDouble` ✓；`PlayerController.load(url:)` 第 37 行 `item.audioTimePitchAlgorithm = .spectral` 在位 ✓。**但 `grep -rniE "pitch\|音高\|不变调\|变调" Tests/ UITests/` 命中 0** —— 零测试覆盖；W-2026-10-03-33 声称的「Phase 2 冻结面，单测锁」不成立。且 0.5×/2× 人声听音从未发生（W-33，open）。代码形态在位 ≠ 听过了 |

**Score:** 7/9 truths verified（1 present-but-behavior-unverified，1 部分未验）

### 5 条 Success Criteria 逐条判定

| SC | 判定 | 一句证据 |
|----|------|----------|
| **SC-1** 设置窗 780/680 + B1+L4+无侧边栏；关窗只隐藏、进程不退出 | **PARTIAL** | 几何与皮肤有活体探针读数 `width=780 minWidth=680` + 无侧边栏（命中 0）；但「关窗只隐藏、进程不退出、图标仍在」这半句是运行期状态跃迁，零测试触达（#8） |
| **SC-2** 空态警告黄 + 感叹号瓷砖 + 逐字文案 | **PASS** | 文案常量双锁（逐字相等 + 全仓唯一）+ 三态一张皮穷举单测 + 产品视图分支代码在位；屏上渲染未目视（记为人工项，非判定缺口） |
| **SC-3** 两条置灰联动**禁用交互** | **PASS** | 纯函数正反两向单测 + `GlowSlider` 的 `guard isEnabled`（onChanged/onEnded 两处）+ `GlowStepper` 走原生 Button → 真禁用，不是只调透明度 |
| **SC-4** 0.5×–2× 保音高 + 改动当场生效 + 重启保留 | **PARTIAL** | 当场生效（4 条行为级单测）与重启保留（三轮活体 `settings-restart.log`）都 PASS；「保持原音高」**只到代码**（`.spectral` 在位）—— 零测试覆盖（W-33 的「单测锁」不实）+ 人声听音从未做 |
| **SC-5** 运行状态卡：暂停 + 原因 + ffmpeg 可用性 | **PASS** | 6 条原因文案逐字锁 + 多原因排序/连接单测 + ffmpeg 两值穷举且零执行 + 活体 `FFMPEG_SELF_CONSISTENT=ok`；锁屏态「屏幕已锁定」副标签未活体观测（W-29，记为人工项） |

**5 条 SC：2 PASS / 3 PARTIAL / 0 FAIL。** 三条 PARTIAL 的成因全部是「环境锁屏 + 听感」，无一是产品代码缺失。

### Deferred Items

None. 三条未闭合项（W-29 / W-33 / W-34）都是**本里程碑内待人工动作**，不是后续 phase 承接的工作 —— 按 ROADMAP 全文扫描无匹配的后续 phase 目标或成功标准，不予递延。

### Advisory (New Scope, Unevidenced)

初次验证（`is_re_verification = false`），证据门禁不适用；以下均为初次发现，全部带确定性证据。

| # | Finding | Category | Why Advisory |
|---|---------|----------|--------------|
| 1 | **XCUITest `testAllControlsExistAndTranscodeStaysDisabled` 断言已与产品代码矛盾，解锁后重跑必红** | other | Phase 6 的 `9d18a81` 把转码按钮的 `.disabled(true)` 换成「只调 opacity 0.34 + 弹安装途径」（SC#1 两半句同时成立的要求），但 Phase 5 留下的用例仍断言 `XCTAssertFalse(el("transcode-open").isEnabled)`。证据：`SettingsView.swift:176` 该按钮只有 `.opacity` 无 `.disabled`，`SettingsControlsUITests.swift:157` 断言 `isEnabled == false`。**这会直接卡住 W-34 的解开条件** —— 解锁后不修就重跑，`run-uitests.sh` 会以 `failed` 而非 `passed` 收场 |
| 2 | **音高保持（`.spectral`）零测试覆盖，W-2026-10-03-33 的「单测锁」与事实不符** | other | `PlayerController.swift:37` 确有该行，但 `grep -rniE "pitch\|音高\|不变调\|变调" Tests/ UITests/` 命中 0。删掉这一行，198 条单测仍全绿，SC-4 保音高面静默失效 |
| 3 | **05-04 SUMMARY 与 W-34 均称「11 条 XCUITest」，实际 10 条** | other | `SettingsWindowUITests` 4 + `SettingsControlsUITests` 6 = 10 条 `func test`。记账数字错一位，不影响判定 |
| 4 | **`test.sh` 的「设置窗渲染成功」渲染的是 spike，不是产品 `SettingsView`** | other | `test.sh:35` 的 `SRC=".planning/spike/SettingsSpike.swift .planning/spike/Render.swift"`。产品设置窗从未被任何自动路径渲染 —— B1 皮肤与 L4 双列的视觉面没有机器读数 |
| 5 | **ROADMAP 标 `Mode: mvp` 但 Goal 不是 User Story，MVP 验证门禁无法执行** | other | `gsd_run query user-story.validate` 返回 `valid=false`（缺三槽）。改按 5 条 Success Criteria 判定 —— 那 5 条是可判定契约，严于用户故事且不依赖编造。修法：跑 `/gsd mvp-phase 5` 改写 Goal，或把 mode 改回 null |

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Sources/PicApp/Settings/SettingsView.swift` | 339 行设置窗主体 | ✓ VERIFIED | 14 个 `accessibilityIdentifier` 全在位（TEST-07 清单要求的 8 interactive + 1 conditional + 4 display + transcode-open）；无假 `@State`（仅 `rateDrag` 拖动暂态与 `showingPathways`，均非渲染假数据） |
| `Sources/PicApp/Settings/SettingsComponents.swift` | 自绘控件 | ✓ VERIFIED | `GlowSlider/GlowSegmented/GlowStepper/GlowToggle/Tile` 全在位；`mono()` 走系统 `.monospaced`，零字体文件零注册（2026-10-03 拍板项已落实） |
| `Sources/PicCore/App/SettingsPresentation.swift` | 纯展示映射 | ✓ VERIFIED | 不 import SwiftUI/AppKit/AVFoundation（test.sh 门禁实测 0/0）；窗口常量唯一来源 |
| `Sources/PicCore/App/SettingsApplier.swift` | 当场生效唯一落点 | ✓ VERIFIED | 不 import AVFoundation（只调 `PlayerController` 公开面）；`shouldPlay` 门 + 电池单一落点 |
| `Sources/PicApp/Settings/SettingsSessionState.swift` | 会话态 | ✓ VERIFIED | 不进 `SettingsStore`；隐藏态计数归零（避免空态皮造假） |
| `Sources/PicCore/App/FFmpegAvailability.swift` | ffmpeg 可用性 | ✓ VERIFIED | 零 `Process(` / 零 `NSTask`；已收编为 `ExternalToolLocator` 薄委托（Phase 6 的 D-17） |
| `Tests/PicCoreTests/SettingsApplierTests.swift` | 181 行 | ✓ VERIFIED | 8 条，含 4 条直接断言 AVPlayer 读数的行为级用例 |
| `Tests/PicCoreTests/SettingsPresentationTests.swift` | 169 行 | ✓ VERIFIED | 19 条，含窗口常量、两条联动正反向、文案逐字+唯一性、6 case 原因映射、多原因排序 |
| `Tests/PicCoreTests/FFmpegAvailabilityTests.swift` | 67 行 | ✓ VERIFIED | 6 条，注入假件（本机 PATH/FS 无关） |
| `UITests/PicUITests/SettingsWindowUITests.swift` | 4 条 | ⚠️ 已交付未运行 | 编译通过已证（`XCODEBUILD_BUILD_RC=0`）；运行被 W-34 挡住 |
| `UITests/PicUITests/SettingsControlsUITests.swift` | 6 条 | ⚠️ 已交付未运行 + **1 条断言已过期** | 见 Advisory #1。另：`storeKeys` 只清 7 键，`SettingsStore` 现有 8 键（`launchAtLogin` 由 Phase 7 的 `a2f1e5b` 加入），该键不会被清 → 跨用例串味 |
| `scripts/probe-settings.sh` / `probe-settings-restart.sh` / `probe-status-card.sh` | 三个探针 | ✓ VERIFIED | 均已产出可 grep evidence |
| `scripts/run-uitests.sh` | XCUITest 运行器 | ✓ VERIFIED | 锁屏守卫真实走到（`W_ENTRY_MISSING` 分支设计正确）；blocked/failed 可区分；W 号缺失即非 0 退出 |
| `.planning/phases/05-settings/evidence/*.log`（6 份） | 证据 | ✓ VERIFIED | 全部入库且含明确 verdict 行 |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|----|--------|---------|
| 菜单 `.openSettings` | `SettingsView` | `presentSettings()`（.regular + activate）→ `openWindow(id:"settings")` | ✓ WIRED | `MenuContentView.activate` 的 `.openSettings` 分支三步齐全 |
| `SettingsView` 控件 | `AVPlayer.rate/volume/isMuted` | `store.<键>` → `SettingsApplier.apply*()` → `PlayerController.set*` | ✓ WIRED | 4 条行为级单测直接断言 AVPlayer 读数 |
| `SettingsView.onAppear` | 可 grep 证据 | `WallpaperWindowController.emit` → `PIC_EVIDENCE_FILE` mirror | ✓ WIRED | `emit` 写 stderr + mirror 双写；未设环境变量时与原实现逐字节一致 |
| `MediaCoordinator.onStateChange` | `SettingsSessionState` | 单一 handler 同时打 `PIC_LIBRARY_STATE` + `sessionState.update(state:)` | ✓ WIRED | 全仓恰好 2 个 `PIC_LIBRARY_STATE` 打点处（正常路径 + 取消分支），符合 05-03 契约 |
| `HoldArbiter.decision.activeReasons` | 状态卡副标签 | `SettingsPresentation.joinedReasons`（排序只允许出现在该函数内） | ✓ WIRED | 单测锁排序；变异靶点 |
| `设置窗重扫` / `菜单重扫` | 同一入口 | `AppDelegate.rescanLibrary()`（`invalidateCache` + `rescanAndApply`）；`rescanFolderNow` 只多打一行菜单读数 | ✓ WIRED | 无第二套重扫语义 |
| 「选择…」 | `NSOpenPanel` | `FolderPicker` | ✓ WIRED | `grep -l -r -F 'NSOpenPanel(' Sources/PicApp` 恰好 1 个文件 |
| 「电池时播放」toggle | `arbiter.set(.battery,…)` | `reapplyBatteryHold()` → `applyBatteryPolicy(isOnBattery: lastIsOnBattery)`（与电源跃迁同一方法） | ✓ WIRED | test.sh 门禁实测 `arbiter.set(.battery` == 1、`BatteryHoldPolicy.shouldHold` == 1 |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| 全量单测 | `swift test` | `Executed 198 tests, with 0 failures (0 unexpected)`，exit 0 | ✓ PASS |
| 常驻门禁 | `bash test.sh` | `通过 102  失败 0 跳过 1`（跳过项是 Phase 7 的 7 天长跑，非本 phase），exit 0 | ✓ PASS |
| Phase 5 常驻门禁 7 条 | `test.sh` Phase 5 段 | 设置窗零 AVFoundation / PicCore 展示层零 UI 框架 / NSOpenPanel 单文件 / 电池单一落点 / ffmpeg 零执行 / MUT-P5- 零残留 / W 编号 `uniq -d == 0` —— 7 条全 ✅ | ✓ PASS |
| 窗口几何活体读数 | 已入库 evidence | `PIC_SETTINGS_WINDOW width=780 minWidth=680`（两轮：settings-tracer + settings-apply） | ✓ PASS |
| 重启保留活体读数 | 已入库 evidence | 三轮 `SETTINGS_RESTART_PROBE_OK` | ✓ PASS |
| XCUITest 运行 | `bash scripts/run-uitests.sh` | 本次**未重跑**（会覆盖已入库 evidence，且当前会话仍锁屏）；已入库 verdict = `UITEST_STATUS=blocked reason=screen_locked` | ? BLOCKED |

未跑满量套件以外的单条具名测试：8 条 must-have 的行为面均已被现有单测/探针覆盖，无需额外定向跑单条测试。

### Probe Execution

| Probe | Command | Result | Status |
|-------|---------|--------|--------|
| `scripts/probe-settings.sh` | `bash scripts/probe-settings.sh` | `SETTINGS_TRACER_PROBE_OK` · `PROCESS_EXITED=clean` · `width=780 minWidth=680` | PASS（已入库，本次未重跑） |
| `scripts/probe-settings-restart.sh` | `bash scripts/probe-settings-restart.sh` | `SETTINGS_RESTART_PROBE_OK` · 3/3 轮 ok | PASS（已入库） |
| `scripts/probe-status-card.sh` | `bash scripts/probe-status-card.sh` | `STATUS_CARD_PROBE=PASS`；但 `LIVE_LOCK_OBSERVATION=blocked reason=screen_locked` | PASS（部分 blocked，见 W-29） |
| `scripts/run-uitests.sh` | `bash scripts/run-uitests.sh` | `XCODEBUILD_BUILD_RC=0` → `SCREEN_LOCKED=1` → `UITEST_STATUS=blocked`，无任何 `Test Case` 行 | BLOCKED（非 FAILED，W-34 已登记） |

> 四个探针本次**均未重跑** —— 重跑会覆盖已入库的 evidence（test.sh 自身的 `p4_line` 纪律：探针重跑会覆盖已入库 evidence）。此处引用的是入库 verdict，并已回到生成它们的源码逐条复核。

### Requirements Coverage

**16/16 条全部有交付物**（10 条自动已验 / 6 条部分依赖 W-34 的未跑 XCUITest）。

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| **SOURCE-04** | 05-03 | 显示可用视频数量；为 0 时警告空态 | ✓ 已验 | `countRow` 读 `session.playableCount`；三态一张皮穷举单测 |
| **UI-01** | 05-01 | 设置窗按 UI-SPEC（B1 + L4 双列） | ✓ 已验 | 活体 `width=780 minWidth=680` + B1 令牌逐字 + 无侧边栏命中 0 |
| **UI-02** | 05-03 | 空态警告色 + 指定文案 | ✓ 已验 | 文案常量双锁 + `Tile(warn:)` / `pWarn` 在位 |
| **UI-03** | 05-02/05-04 | 两条置灰联动 | ✓ 已验 | 纯函数正反单测 + 真禁用（`guard isEnabled` / 原生 Button） |
| **UI-04** | 05-03 | 运行状态：暂停/原因/ffmpeg | ✓ 已验 | 6 case 文案逐字 + 排序连接单测 + ffmpeg 活体读数 |
| **PLAY-07** | 05-01 | 速度 0.5×–2×，保持原音高 | ⚠️ 部分 | 区间 ✓；保音高**只到代码**，零测试 + 未听音（W-33） |
| **PLAY-08** | 05-02 | 声音可开关 | ✓ 已验 | `applyMuted` → `player.isMuted`，`testVolumeAndMutedApplyWithoutGate` |
| **PLAY-09** | 05-02 | 音量可调节 | ✓ 已验 | `applyVolume` → `player.volume == 0.25` 行为级断言 |
| **PLAY-10** | 05-01/05-02 | 所有设置改动立即生效 | ✓ 已验 | 六项写入口全部 `store → apply* → persist`；4 条 apply 行为级单测 |
| **MENUBAR-02** | 05-01 | 关窗只隐藏，进程不退出 | ⚠️ 部分 | 代码在位（`.onDisappear` → `.accessory`；`NSApp.terminate` 全仓唯一）；运行期未验（#8，W-34） |
| **MENUBAR-06** | 05-01 | 菜单项「打开设置」 | ✓ 已验 | `MenuItemID.openSettings` + `MenuShortcut` ⌘, + 5 项顺序单测 |
| **TEST-04** | 05-02 | 设置持久化存取/默认/立即生效 | ✓ 已验 | 三轮活体 restart probe + `SettingsStoreTests` 11 条 |
| **TEST-07** | 05-04 | 全部控件可交互 | ⚠️ 部分 | 14 个 identifier 全在位（源码层 ✓）；hittable / disabled 断言只在未跑的 XCUITest 里，且其中 1 条已过期（Advisory #1） |
| **TEST-08** | 05-02/05-04 | 两条置灰联动不可点 | ⚠️ 部分 | 联动机制 ✓（真禁用）；「以交互不生效为准」的证据行断言只在未跑的 XCUITest 里 |
| **TEST-09** | 05-04 | 空态警告色与指定文案 | ⚠️ 部分 | 文案逐字单测 ✓；XCUITest 空目录 `staticText` 逐字相等断言未跑 |
| **TEST-10** | 05-04 | 菜单栏 5 项存在且可点 | ⚠️ 部分 | `MenuBarModelTests` 锁 5 项文案/顺序/哨兵（✓）；hittable 断言未跑（W-31 已登记） |

### Test Quality Audit

| Test File | Linked Req | Active | Skipped | Circular | Assertion Level | Verdict |
|-----------|-----------|--------|---------|----------|-----------------|---------|
| `SettingsApplierTests.swift` | PLAY-07/08/09/10 | 8 | 0 | 否 | **Behavioral**（直断 AVPlayer 读数 / RotationController 重排程计数） | ✓ 合格 |
| `SettingsPresentationTests.swift` | UI-01/02/03/04 | 19 | 0 | 否 | **Value**（逐字相等 + 全仓计数） | ✓ 合格 |
| `FFmpegAvailabilityTests.swift` | UI-04 | 6 | 0 | 否 | **Value**（注入假件判定） | ✓ 合格 |
| `SettingsWindowUITests.swift` | MENUBAR-02/06, TEST-04 | 4 | 0 | 否 | Behavioral | ⚠️ 已交付未运行（W-34） |
| `SettingsControlsUITests.swift` | TEST-07/08/09/10, UI-03 | 6 | 0 | 否 | Behavioral | ⚠️ 已交付未运行 + 1 条断言过期（Advisory #1） |

**Disabled tests on requirements:** 0（仅 3 处 `throw XCTSkip(...)`，均为运行时条件 skip 且串里带 W 号，非静态禁用）→ 无 BLOCKER
**Circular patterns detected:** 0 → 无 BLOCKER
**Insufficient assertions:** 0（无需求要求超出 value 级的证明）
**源码生成期望值的循环证据:** 无（期望值全部是字面量契约字符串或注入假件，无脚本自产期望值）

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `UITests/PicUITests/SettingsControlsUITests.swift` | 157 | `XCTAssertFalse(el("transcode-open").isEnabled)` 与产品代码矛盾（Phase 6 已改） | ⚠️ Warning（跨 phase 回归风险） | 解锁后重跑必红，卡住 W-34 解开条件。见 Advisory #1 |
| `UITests/PicUITests/SettingsControlsUITests.swift` | 18 | `storeKeys` 只列 7 键，`SettingsStore` 现有 8 键 | ⚠️ Warning | `launchAtLogin` 不会被清 → 跨用例状态串味（Phase 7 引入，非 Phase 5 缺陷） |
| `Sources/PicCore/Playback/PlayerController.swift` | 37 | `item.audioTimePitchAlgorithm = .spectral` 零测试覆盖 | ℹ️ Info | 静默失效风险。W-33 的「单测锁」表述需更正 |
| `test.sh` | 35, 698 | 「设置窗渲染成功」渲染 spike 而非产品视图 | ℹ️ Info | 产品 UI 视觉面无机器读数，只能活体目视 |
| Phase 5 源码全树 | — | 债务标记 `TBD`/`FIXME`/`XXX`/裸 `TODO`/`HACK` | ✅ 0 处 | 无 BLOCKER |
| Phase 5 源码全树 | — | 空实现 / 占位 `return nil` / console-log-only | ✅ 0 处 | 无 |

无 🛑 Blocker：无 must-have FAILED、无 artifact MISSING/STUB、无 key link NOT_WIRED、无未登记债务标记。

### Human Verification Required

6 项。自动部分全绿，全部缺口落在**环境（锁屏）与感官（听感）**上。

1. **SC-4 听音** —— 以 0.5× 与 2× 各播一段**含人声**的素材，确认音高不变。纯音乐/无人声不算。
2. **解锁后重跑 `bash scripts/run-uitests.sh`** —— ⚠️ **先修 Advisory #1 的 transcode 断言**，否则会以 failed 收场而非 passed。
3. **空态目视** —— 计数 0 时确认警告黄数字、感叹号瓷砖、逐字文案、重扫按钮可点。
4. **布局目视** —— 确认 B1 深海 + L4 双列（左：来源/播放，右：电源与系统/维护/运行状态）+ 无侧边栏。
5. **锁屏态副标签** —— 运行状态卡标题「已暂停」+ 副标签逐字「屏幕已锁定」（W-29）。
6. **关窗路径** —— 进程不退、菜单栏图标仍在、Dock 无图标（behavior-unverified 真相 #8）。

### Gaps Summary

**无 gap（`gaps:` 为空）。** 9 条 must-have 中 7 条自动已验、1 条因运行期状态跃迁无测试而记 `PRESENT_BEHAVIOR_UNVERIFIED`、1 条（保音高）代码在位但零测试覆盖且未听音。三条已知人工阻塞（W-29 / W-33 / W-34）均已如实登记为 PARTIAL/W 条目，未粉饰为已完成。5 条 SC 判定 2 PASS / 3 PARTIAL / 0 FAIL。

总体状态为 `human_needed` 而非 `passed`：behavior_unverified 计数为 1，且存在 6 项人工验证条目 —— 按决策树 Rule 2，human 项优先级高于 passed。

**同时必须记录 5 项初次发现（Advisory 段）**，其中第 1 项（transcode 断言过期）会实际阻断 W-34 的解开条件，建议在解锁重跑之前先行修复。

---

_Verified: 2026-10-04T00:26:13Z_
_Verifier: Claude (gsd-verifier)_