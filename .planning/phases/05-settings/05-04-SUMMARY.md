---
phase: 05-settings
plan: 04
subsystem: testing
tags: [xctest, macos, swiftui, evidence-bridge, gate-script]

requires:
  - phase: 05-settings
    provides: "设置窗全部控件与 accessibilityIdentifier、SettingsApplier 六条证据行、PIC_SETTINGS_BOOT 回读锚点、菜单栏 5 项模型"
provides:
  - "11 条 XCUITest：控件全景 / 两条置灰以交互不生效为准 / 空态逐字 / 菜单实点 / 拖速度闭环 / 立即下一个回归"
  - "run-uitests.sh 的 Skipped 计数与「每条 skip 必须有 W 陪跑」非零退出守卫"
  - "test.sh Phase 5 常驻门禁 7 条（分层 / 单点 / 零执行 / 零残留 / W 编号唯一）"
  - "SC-4 听音等人工项在 STATE.md Deferred Verification 与 W-2026-10-03-33 的双记账"
affects: [06-transcode, 07-system, testing]

actuals:
  tokens: 294
  tasks: 2
  commits: 3

tech-stack:
  added: []
  patterns:
    - "skip / blocked 必须有配对的 W 登记，缺登记即非零退出 —— 静默跳过冒充通过被结构性堵死"

key-files:
  created:
    - UITests/PicUITests/SettingsControlsUITests.swift
    - .planning/phases/05-settings/evidence/test-sh-phase5.log
  modified:
    - UITests/PicUITests/SettingsWindowUITests.swift
    - scripts/run-uitests.sh
    - test.sh
    - Pic.xcodeproj/project.pbxproj
    - .planning/WINDOWS.md
    - .planning/STATE.md
    - .planning/phases/05-settings/evidence/uitest.log

key-decisions:
  - "G-04-3 回归单列一条用例而非并进 TEST-10 —— 用户指令「每个测试钉住一条契约」，两条契约塞一条测试会让任一回归都定位不到"
  - "G-04-3 的「装载的视频 URL 变化」用 PIC_ROT_ADVANCES 计数递增代理 —— T-03-02 禁文件名进证据，给证据行加 URL 会破隐私红线"
  - "W-2026-10-03-34 单独立条覆盖「11 条一条没跑」—— skip 是测试跑起来才有的，锁屏挡住时没有 skip 记录可循"
  - "Phase 5 门禁的 7 个数字全部先数现状再写死（0/0/0/1文件/1/1/0/0）"
  - "src_count 的路径守卫 -d 改 -e：单文件门（FFmpegAvailability）否则恒返 -1 判红"

patterns-established:
  - "no() 文案与 ok() 判据名逐字相同，红绿靠 ✅/❌ 前缀区分（沿用 04-06，D-14）"
  - "XCUITest 的置灰判定一律 isEnabled + 证据行「点了没反应」，不碰视觉变淡"

requirements-completed: [UI-03, TEST-07, TEST-08, TEST-09, TEST-10]

coverage:
  - id: D1
    description: "TEST-07 设置窗控件全景：13 个 accessibilityIdentifier 存在且可点，转码入口 disabled 占位"
    requirement: TEST-07
    verification:
      - kind: automated_ui
        ref: "UITests/PicUITests/SettingsControlsUITests.swift#testAllControlsExistAndTranscodeStaysDisabled"
        status: unknown
    human_judgment: true
    rationale: "会话锁屏（evidence/uitest.log 的 SCREEN_LOCKED=1），该用例从未执行。只证明测试目标编译通过（XCODEBUILD_BUILD_RC=0）。见 W-2026-10-03-34"
  - id: D2
    description: "TEST-08 两条置灰联动：单循环下点步进器不产生 rotationInterval、静音下拖滑杆不产生 volume，恢复后当场生效"
    requirement: TEST-08
    verification:
      - kind: automated_ui
        ref: "UITests/PicUITests/SettingsControlsUITests.swift#testRotationRowIgnoresTapsInSingleLoopAndRecoversInListLoop"
        status: unknown
      - kind: unit
        ref: "Tests/PicCoreTests/SettingsPresentationTests.swift"
        status: pass
    human_judgment: true
    rationale: "置灰条件与量纲换算的单测全绿；「点不动」这个交互事实本会话无人验证。见 W-2026-10-03-34"
  - id: D3
    description: "TEST-09 空态：空目录启动逐字显示空态文案，重扫按钮保持可用"
    requirement: TEST-09
    verification:
      - kind: automated_ui
        ref: "UITests/PicUITests/SettingsControlsUITests.swift#testEmptyFolderShowsVerbatimCopyAndRescanStaysEnabled"
        status: unknown
      - kind: unit
        ref: "Tests/PicCoreTests/SettingsPresentationTests.swift#testEmptyStateBodyIsSingleSourced"
        status: pass
    human_judgment: true
    rationale: "文案单一来源已由单测锁；屏上逐字渲染未被验证。见 W-2026-10-03-34"
  - id: D4
    description: "TEST-10 菜单栏 5 项实点 + G-04-3 立即下一个在单循环下仍推进"
    requirement: TEST-10
    verification:
      - kind: automated_ui
        ref: "UITests/PicUITests/SettingsControlsUITests.swift#testMenuBarExposesFiveHittableItems"
        status: unknown
      - kind: unit
        ref: "Tests/PicCoreTests/MenuBarModelTests.swift"
        status: pass
    human_judgment: true
    rationale: "5 项的文案与顺序由 MenuBarModelTests 逐字锁死；物理实点与「菜单项 → advanceNow()」装配无运行期证据。见 W-2026-10-03-31"
  - id: D5
    description: "SC-4 交互半边：拖速度滑杆当场生效 + 退出重起回读同一值"
    requirement: UI-03
    verification:
      - kind: automated_ui
        ref: "UITests/PicUITests/SettingsWindowUITests.swift#testRateDragAppliesImmediatelyAndSurvivesRelaunch"
        status: unknown
      - kind: integration
        ref: ".planning/phases/05-settings/evidence/settings-restart.log"
        status: pass
    human_judgment: true
    rationale: "seeding 路径的「改值 → 重启 → 回读」已由 probe-settings-restart.sh 三轮全绿；手拖那一跳未跑。见 W-2026-10-03-32"
  - id: D6
    description: "SC-4 人声不变调（0.5×/2×）的听感确认"
    requirement: UI-03
    verification: []
    human_judgment: true
    rationale: "自动化原理上覆盖不了 —— 参数与 .spectral 落位可断言，「听起来没变调」不可断言。见 W-2026-10-03-33"
  - id: D7
    description: "test.sh Phase 5 常驻门禁 7 条 + 收口三件套（build / swift test / test.sh 全绿，XCUITest blocked）"
    verification:
      - kind: other
        ref: "bash test.sh → 通过 71 失败 0 跳过 5"
        status: pass
      - kind: other
        ref: "swift test → Executed 190 tests, with 0 failures"
        status: pass
      - kind: other
        ref: "bash scripts/run-uitests.sh → UITEST_STATUS=blocked reason=screen_locked（W-2026-10-03-25 已登记）"
        status: pass
    human_judgment: false

# Metrics
duration: 96min
completed: 2026-10-04
status: complete
---

# Phase 05 Plan 04: XCUITest 全套 + test.sh Phase 5 门禁

**11 条 XCUITest 交付但因会话锁屏一条未跑（编译通过已证），并把「没跑过」做成结构性不可能静默通过：run-uitests.sh 现在数 Skipped 并逐条回 W 登记簿核对；test.sh 从 64 条门增到 71 条**

## Performance

- **Duration:** 96 min
- **Started:** 2026-10-03T23:58Z
- **Completed:** 2026-10-04T01:35Z
- **Tasks:** 2
- **Files modified:** 9

## ⚠️ 先读这一段：本 plan 的诚实边界

| 交付物 | 真跑过吗 | 证据 |
|---|---|---|
| XCUITest **测试目标编译** | ✅ 跑过 | `evidence/uitest.log` 的 `XCODEBUILD_BUILD_RC=0` |
| XCUITest **11 条用例本身** | ❌ **一条都没跑** | `SCREEN_LOCKED=1` → `UITEST_STATUS=blocked reason=screen_locked`，日志里没有任何 `Test Case` 行 |
| `swift build` / `swift test` | ✅ 跑过 | 190 tests, 0 failures |
| `bash test.sh`（含新增 7 条门） | ✅ 跑过 | 通过 71 失败 0 跳过 5（基线 64，+7） |
| SC-4 听音（0.5×/2× 人声） | ❌ 原理上自动化不了 | W-2026-10-03-33 |

会话全程锁屏。05-01 入库的那份 `uitest.log` 读数是**修复前**的，本 plan 重新采了一次 ——
新读数把 05-01 遗留的 pbxproj 缺陷挖了出来（见 Deviation 1）。

## Accomplishments

- **11 条 XCUITest** 交付：`SettingsControlsUITests` 6 条（控件全景 / 两条置灰 / 空态 / 菜单实点 /
  立即下一个回归）+ `SettingsWindowUITests` 追加的拖速度闭环。置灰断言全部走
  `isEnabled` + 证据行「点了没反应」，`opacity` 在测试文件里剥注释后计数为 0。
- **挖出并修掉 05-03 遗留的 pbxproj 缺陷**：`SettingsSessionState.swift` 从未登记进
  `project.pbxproj`，SwiftPM 自动发现让 `swift build/test` 全绿，xcodebuild 却编不过 ——
  这正是 05-01 那份 `bundle identifier for PicApp couldn't be read` 读数背后的真凶。
- **skip 纪律从「建议」变成「守卫」**：`run-uitests.sh` 数出 `UITEST_SKIPPED=`，
  逐条把 skip 串里的 W 号回 `.planning/WINDOWS.md` 核对，缺登记即
  `W_FOR_SKIP_MISSING` 非零退出。
- **test.sh Phase 5 常驻门禁 7 条**，每条 `no()` 文案与 `ok()` 判据名逐字相同。
- **人工项诚实双记账**：SC-4 听音进 STATE.md `## Deferred Verification`（W-33），
  锁屏活体（W-29）、菜单实点与拖动（W-31/32）、全套未跑（W-34）一并登记。

## Task Commits

1. **Task 1: XCUITest 全套 + skip 守卫** - `1620a05` (feat)
2. **Task 2: test.sh Phase 5 门禁 + 人工项登记 + 三件套收口** - `aae7dd3` (feat)

## Files Created/Modified

- `UITests/PicUITests/SettingsControlsUITests.swift`（新建）— 6 条控件级交互测试
- `UITests/PicUITests/SettingsWindowUITests.swift` — 追加拖速度 → 当场生效 → 重启回读
- `scripts/run-uitests.sh` — `UITEST_SKIPPED` 计数 + W 陪跑守卫 + 起测前清 store 7 键
- `test.sh` — Phase 5 门禁段 7 条（插在 Phase 4 evidence 之后、渲染段之前）
- `Pic.xcodeproj/project.pbxproj` — 登记 `SettingsControlsUITests.swift` 与漏掉的
  `SettingsSessionState.swift`（PBXBuildFile / PBXFileReference / PBXGroup / Sources 四处）
- `.planning/WINDOWS.md` — 新登记 W-31/32/33/34，W-25 转 resolved
- `.planning/STATE.md` — Deferred Verification 追加 Phase 5 三项人工清单
- `.planning/phases/05-settings/evidence/uitest.log` — 本 plan 重新采集的读数
- `.planning/phases/05-settings/evidence/test-sh-phase5.log` — 收口三件套 + `PHASE5_FINAL`

## Decisions Made

1. **G-04-3 单列一条用例**（`testNextVideoMenuItemAdvancesEvenInSingleLoopMode`），
   不并进 TEST-10 的菜单测试。计划正文写「恰好 4 条 + 第 5 条」，但 `must_haves` 把 G-04-3
   列为独立真相；两条契约塞一条测试，任一回归都定位不到具体那条 —— 用户的「每个测试钉住
   一条契约」优先。
2. **「装载的视频 URL 变化」用 `PIC_ROT_ADVANCES` 计数递增代理**。T-03-02 禁文件名进任何
   证据行；给 `nextVideoNow()` 的证据行加 URL 会破隐私红线。计数递增同时证明「列表非空」
   与「切了一次」——`advance()` 在空列表时直接 return，计数恒 0。
3. **W-2026-10-03-34 单独立条**覆盖「11 条一条没跑」。skip 是测试跑起来之后才可能有的记录，
   锁屏把测试进程挡在启动之前时没有任何 skip 痕迹可循，不单立条目会让读 SUMMARY 的人
   误以为「只差菜单栏那一项」。
4. **Phase 5 门禁的数字全部先数现状再写死**（0 / 0 / 0 / 1 文件 / 1 / 1 / 0），
   其中 `NSOpenPanel(` 的范围收窄到 `Sources/PicApp`（与 Phase 4 的全仓口径互补而非重复）。

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `SettingsSessionState.swift` 未登记进 pbxproj（05-03 遗留）**
- **Found during:** Task 1（首次跑 `run-uitests.sh`，`XCODEBUILD_BUILD_RC=1`）
- **Issue:** 05-03 新增 `Sources/PicApp/Settings/SettingsSessionState.swift` 时只加了文件，
  没加 `project.pbxproj`。SwiftPM 自动发现 Sources 让 `swift build`/`swift test` 全绿，
  xcodebuild 走显式 target 列表，直接编不过：`cannot find 'SettingsSessionState' in scope`。
  05-01 那份 `UITEST_TEST_RC=1 / bundle identifier for PicApp couldn't be read` 的读数
  背后就是它 —— 当时被误读成「边建边测的解析竞态」。
- **Fix:** 在 pbxproj 的 PBXBuildFile / PBXFileReference / PBXGroup / PBXSourcesBuildPhase
  四处补登该文件。
- **Files modified:** `Pic.xcodeproj/project.pbxproj`
- **Verification:** `plutil -lint` OK；`run-uitests.sh` 的 `XCODEBUILD_BUILD_RC=0`
- **Committed in:** `1620a05`

**2. [Rule 2 - Missing Critical] 门禁 3（NSOpenPanel 单点）BSD grep 不递归**
- **Found during:** Task 2（首次跑 `test.sh`，该条判红读数为「落在 0 个文件里」）
- **Issue:** 写成 `grep -l -F 'NSOpenPanel(' Sources/PicApp`。BSD grep 不带 `-r` 时给目录
  不递归，静默返回 0 个文件 —— 读数看起来像「SYS-03 没实现」，实际实现就在
  `FolderPicker.swift`。开发者的交互式 shell 有 profile 别名把 grep 变成递归版，
  所以手工试是通的、写进 test.sh 才暴露。
- **Fix:** 补 `-r`，并把「不带 -r 会静默返回 0」写进判据旁的注释。
- **Files modified:** `test.sh`
- **Verification:** `bash test.sh` 该条转 ✅
- **Committed in:** `aae7dd3`

**3. [Rule 2 - Missing Critical] `src_count` 传单文件时恒返 -1**
- **Found during:** Task 2（同一次 `test.sh` 首跑，门禁 5 判红读数为 `Process(=-1 NSTask=-1`）
- **Issue:** `src_count` 的守卫是 `[ -d "$dir" ]`，门禁 5 传的是**文件**
  `Sources/PicCore/App/FFmpegAvailability.swift`，于是直接返回 -1 判红 ——
  一个恒红的门比没有门更坏。
- **Fix:** 守卫从 `-d` 改 `-e`。目录不存在时返 -1 的既有语义一个字节没变
  （Phase 3/4 十几条门依赖它），只是额外接受已存在的文件路径。
- **Files modified:** `test.sh`
- **Verification:** `bash test.sh` 该条转 ✅；Phase 3/4 全部既有门仍绿
- **Committed in:** `aae7dd3`

**4. [Rule 3 - Blocking] 三处 Swift 编译错（`app`/`evidence` 越作用域、`String?` vs `String`、`waitForEvidence` 返回值）**
- **Found during:** Task 1（build-for-testing 连报三轮）
- **Issue:** 新写的测试文件有作用域与类型错误。`launchApp()` 里的局部 `app` 遮住了
  `el()` 需要的实例；`SettingsWindowUITests` 的 helper 叫 `waitForEvidence` 而不是 `evidence`；
  `split` 的结果是 `Substring`。
- **Fix:** 把 `app` 提为实例属性并让 `launchApp` 回填；补一个读证据的局部量；
  `String(...)` 显式转换。
- **Files modified:** `UITests/PicUITests/SettingsControlsUITests.swift`、`SettingsWindowUITests.swift`
- **Verification:** `XCODEBUILD_BUILD_RC=0`
- **Committed in:** `1620a05`

---

**Total deviations:** 4 auto-fixed（1 bug · 2 missing critical · 1 blocking）
**Impact on plan:** 全部是「让交付面真正可跑」的必要修正，无范围蔓延。
Deviation 1 修的是前序 plan 的缺陷但落在本 plan 的交付文件上；Deviation 2/3 是新写的门禁
自身的实现错（正是计划「写门前先数一遍真实现状」纪律要防的那类，但发生在**门禁代码**而不是被测源码上）。

## Issues Encountered

- **会话锁屏让本 plan 的核心交付面无法验证。** XCUITest 需要可交互会话，`run-uitests.sh`
  在跑测试之前就被守卫挡成 `blocked`（`SCREEN_LOCKED=1`）。这不是可以绕过的环境限制 ——
  守卫的存在正是为了不在锁屏态下弹权限链污染用户机器。处理方式是：把「没跑过」全部登记成
  W 条目 + STATE.md 人工清单，并让 `run-uitests.sh` 在下一次解锁重跑时**强制**把这些
  skip 暴露出来。**没有把「编译过了」写成「测试过了」。**
- **`probe-lock.sh` 误覆盖了 Phase 3 已入库 evidence。** 本 plan 手动跑它探测锁屏状态时，
  该脚本就地重写了 `.planning/phases/03-system-events/evidence/lock-wiring.log`。
  已用 `git checkout --` 复原（`git status` 确认干净）。这是 04-06 在 test.sh 里评论过的
  同一个坑：**探针脚本默认就地覆盖 evidence**，只有 test.sh 那段做了 `PIC_EVIDENCE_DIR`
  重定向。手工调用探针时必须自己重定向。

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- **Phase 5 的自动化收口完成**：`test.sh` 71 条门全绿、`swift test` 190 项全绿、
  Phase 5 的分层/单点/零执行/零残留/W 唯一五条不变量已成为每次校验都重验的常驻门。
- **解锁会话后第一件事**：重跑 `bash scripts/run-uitests.sh`，期望 `UITEST_STATUS=passed`
  且 11 条全过。任何 skip 都会带出 `UITEST_SKIPPED=` 与对应 W 号；W 号没登记则运行器
  非零退出，那正是 W-31/32/34 存在的意义。
- **SC-4 听音（W-33）需要真人**，且必须用**含人声**的素材 —— 纯音乐/无人声不算。
- **对 Phase 6/7 的移交**：`test.sh` 的 Phase 5 段是追加式分节，revert 即回到 Phase 4 门禁面；
  `src_count` 的 `-e` 守卫对新增的单文件门同样适用。

## Self-Check: PASSED

- 两条 task 的全部 `<acceptance_criteria>` 逐条实跑（见上表与各 task 的 verify 输出）
- 计划级 `<verification>`：`PHASE5_FINAL build=0 swifttest=0 testsh=0 uitest=blocked`，
  `MUT-P5-` 残留 0，W 标题 `uniq -d` 为空
- 关键文件均在盘上且已入库
- **诚实性复核**：`coverage:` 里 7 条交付物中 6 条标 `human_judgment: true`，
  唯一标 `false` 的 D7（门禁与三件套）每条 `verification` 都有实测 `pass`

---
*Phase: 05-settings · Plan 04*
*Completed: 2026-10-04*