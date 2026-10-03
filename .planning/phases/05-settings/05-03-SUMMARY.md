---
phase: 05-settings
plan: 03
subsystem: ui
tags: [swift, swiftui, empty-state, hold-reason, ffmpeg, session-state, probe, evidence, windows]

# Dependency graph
requires:
  - phase: 04-media-library
    provides: MediaCoordinator.onStateChange（单一 handler）+ FolderPicker（04-04，全仓唯一 NSOpenPanel 落点）+ rescanFolderNow 重扫入口 + LibraryState 四态 / MediaLibraryReport.playableCount
  - phase: 03-system-events
    provides: HoldReason 全 6 case + order 0…5（W-2026-10-03-14 定死）+ PlaybackDecision.activeReasons（已排序）
  - phase: 01-transcode-tools
    provides: ExternalToolLocator / FFmpegToolStatus（命名已在文件头为本 plan 让位，声明「06-04 收编为薄委托」）
  - phase: 05-02
    provides: SettingsView 六项真绑定 + 两条置灰联动的 Binding 注入面 + 7 个 accessibilityIdentifier
provides:
  - SettingsPresentation：emptyStateBody（空态文案全 Sources 唯一一份）、isEmptyState（三态一张皮）、holdReasonLabel（6 case 无 default）、joinedReasons（order 排序顿号连接）、playbackPausedTitle / playbackRunningTitle
  - FFmpegAvailability：PATH 目录可执行位判定（**零执行**）+ resolveFromPATH + label（可用/未安装）
  - SettingsSessionState：app 层会话态（lastLibraryState / playableCount / lastScanDate / isScanning），**不进 SettingsStore 七键**
  - AppDelegate：requestFolderNow（设置窗「选择…」）、rescanLibrary（菜单与设置窗共用的唯一重扫落点）、FolderPickOutcome 三态取代裸 Bool
  - PicApp：注入 requestFolder / rescanLibrary / sessionState（environment）
  - SettingsView：来源卡计数行空态皮（warn 数字 + exclamationmark 瓷砖 + 引用常量文案）、运行状态卡全原因 + ffmpeg 行、扫描期防重入、4 个新 accessibilityIdentifier
  - scripts/probe-status-card.sh：两轮 source + ffmpeg 自洽 + 锁屏活体观察（blocked 分支先查 W-29 在册）
  - 可 grep 证据行：PIC_FFMPEG available=<0|1> label=<可用|未安装>、LIVE_LOCK_OBSERVATION=<attempted|blocked>
  - W-2026-10-03-29（锁屏活体未目视）/ W-2026-10-03-30（ffmpeg 版本串记账偏差）
affects: [05-04（收口门禁消费 evidence/status-card.log；XCUITest 有 4 个新 identifier 可断言：select-button / rescan-button / status-paused / status-ffmpeg；W-29 的 XCUITest 解法归 05-04）, 06-transcode（TRANS-02 把 PATH-only 判定收编进 ExternalToolLocator，见 W-30 的解开条件）]

actuals:
  tokens: 380   # chars/4 over the realized diff（645 行变更）
  tasks: 2
  commits: 3

tech-stack:
  added: []
  patterns:
    - 「文案单一来源 = 常量 + 全树计数门 + 逐字相等断言」三件套：第二份字面量拷贝不会自己漂移提醒，只会漂成两个版本的承诺
    - 会话态与持久态分家：`SettingsSessionState` 是 app 层的只读快照，AppDelegate 是它的唯一写入口；`SettingsStore` 七键冻结因此零接触
    - 重扫「搬家不复制」：菜单 `rescanFolderNow` 退化成打一行菜单读数的薄壳，实体搬进 `rescanLibrary()`，设置窗与菜单共用

key-files:
  created:
    - Sources/PicCore/App/FFmpegAvailability.swift
    - Sources/PicApp/Settings/SettingsSessionState.swift
    - Tests/PicCoreTests/FFmpegAvailabilityTests.swift
    - scripts/probe-status-card.sh
    - .planning/phases/05-settings/evidence/status-card.log
  modified:
    - Sources/PicCore/App/SettingsPresentation.swift
    - Sources/PicApp/Settings/SettingsView.swift
    - Sources/PicApp/AppDelegate.swift
    - Sources/PicApp/PicApp.swift
    - Tests/PicCoreTests/SettingsPresentationTests.swift
    - .planning/WINDOWS.md

key-decisions:
  - "「选择…」与首启引导共用一个 `pickFolder()`（面板 → 校验 → 写盘），**取消的语义由调用方决定**：首启取消 = 从没配过（发 folder_unconfigured），设置窗取消 = 保持现状（不发任何状态行）。两种取消共用一行会谎报当前状态"
  - "重扫入口收敛成 `rescanLibrary()`：菜单侧只留一个打 `PIC_MENU_ACTION=rescan_folder` 的薄壳，实体只有一份"
  - "空态判定只有一条：`SettingsPresentation.isEmptyState` = `!state.shouldShowWallpaper`。三态（没配过/目录没了/扫到 0）在 UI 上刻意**不区分** —— 用户要的是一句解释，不是三种诊断"
  - "会话态计数在隐藏态归零：目录没了之后留着旧数字会让空态皮变成假的（「有 N 个视频」却什么都没播）"
  - "ffmpeg 只判可执行位，不跑二进制 —— 本机没有 timeout 机制，ffmpeg 类调用绝不进自动路径（主会话红线）。版本串是 Phase 6 的事，W-30 已记账"

patterns-established:
  - "变异替换（perl `s///` 不带 `/g`）只打**第一处**匹配，包括注释里的。判据字面量写进注释 = 变异打偏而代码没坏（D-15 的第 N 次沿用）。本次实证：把 `.sorted()` 写进 doc comment 后，MUT-P5-REASON-ORDER 命中的是注释"
  - "`src_count` 的单文件分支不能只用 `dirname`：目录分支会递归吃进子目录（`AppDelegate.swift` → `Sources/PicApp/` → 连 `Settings/SettingsView.swift` 一起数），单文件语义要另用直接 grep"
  - "bash 的 `${v##*= }` 不按预期剥掉带空格的前缀（`${v##*=}` 才行）。解析 evidence 行用 `sed 's/.*available=//'`，别赌参数展开"
  - "blocked 分支要先 grep W 条目在册再放行（W-2026-10-03-25 的形状）：一条从没红过的守卫不证明它会红，但缺条目即退非 0 的守卫能挡住静默跳过"

requirements-completed: [SOURCE-04, UI-02, UI-04]

# Coverage metadata (#1602)
coverage:
  - id: D1
    description: "空态：三态一张皮、warn 皮 + 感叹号瓷砖 + 逐字文案（常量单源，视图零字面量）"
    verification:
      - kind: unit
        ref: "Tests/PicCoreTests/SettingsPresentationTests.swift — testEmptyStateBodyMatchesSpecVerbatim / testEmptyStateBodyIsSingleSourced / testThreeHideStatesShareOneEmptySkin；Executed 20 tests, with 0 failures"
        status: pass
      - kind: other
        ref: "GATES emptycopy_total=1（Sources 全树恰好 1 份）/ emptycopy_view=0（视图零拷贝）/ constant_ref=1"
        status: pass
    human_judgment: false
  - id: D2
    description: "空态下「重新扫描」保持可用，扫描中三个入口一起防重入"
    verification:
      - kind: other
        ref: "SettingsView.swift 剥注释后 `Button(\"…\") {}` 计数 == 1，且那唯一一处是转码「打开…」的 disabled 占位；重扫按钮无 .disabled(isEmpty) 分支，只受 isScanning 约束"
        status: pass
    human_judgment: true
    rationale: "「点得动」在 SwiftUI 上还差一次 XCUITest 的 isEnabled 断言，归属 05-04；代码形态与常量侧已钉住"
  - id: D3
    description: "运行状态卡：暂停与否 + 全 6 case 原因文案 + 多原因按 order 排序顿号连接"
    verification:
      - kind: unit
        ref: "testHoldReasonLabelsCoverAllSixCasesVerbatim（allCases 穷举 + 两两不同）/ testJoinedReasonsSortsByOrderBeforeJoining / testJoinedReasonsEmptyReturnsEmptyString / testJoinedReasonsSingleReasonHasNoSeparator"
        status: pass
      - kind: other
        ref: "变异 MUT-P5-REASON-ORDER：MUT=1，RC=1，失败恰为 testJoinedReasonsSortsByOrderBeforeJoining（XCTAssert 红，编译器诊断 0），恢复后逐字节一致"
        status: pass
    human_judgment: false
  - id: D4
    description: "ffmpeg 可用性：PATH 可执行位判定，零执行"
    verification:
      - kind: unit
        ref: "Tests/PicCoreTests/FFmpegAvailabilityTests.swift — Executed 6 tests, with 0 failures（全部注入临时目录与权限位，不依赖本机 PATH）"
        status: pass
      - kind: other
        ref: "GATES process=0 nstask=0 import SwiftUI/AppKit/AVFoundation 各 0（剥注释后单文件）；探针 FFMPEG_SELF_CONSISTENT=ok available=1 label=可用"
        status: pass
    human_judgment: false
  - id: D5
    description: "「选择…」/「重新扫描」复用 Phase 4 的单一流水线，不开第二入口"
    verification:
      - kind: other
        ref: "GATES folderpicker_files=1 / nsopenpanel_calls=1（全仓唯一构造调用）/ view_nsopenpanel=0 / libstate_sites=2（打点数门未破）/ rescan_ref=2（声明 + 唯一调用点）/ settingsstore_diff=0；bash test.sh 全绿（通过 64 失败 0）"
        status: pass
    human_judgment: false
  - id: D6
    description: "活体验证：锁屏态开设置窗看到「屏幕已锁定」副标签（SC-5 ③）"
    verification: []
    human_judgment: true
    rationale: "本会话屏幕锁定（LOCK_STATE_AT_PROBE=1），无法开窗目视。探针记 LIVE_LOCK_OBSERVATION=blocked reason=screen_locked 并先 grep W-2026-10-03-29 在册；文案映射由穷举单测逐字钉住，缺的是「屏上真的出现这行字」。按旧例不阻塞"
  - id: D7
    description: "来源卡计数行与空态皮的视觉形态（warn 数字 / 感叹号瓷砖 / 换行后的副行是否破行）"
    verification: []
    human_judgment: true
    rationale: "本轮没有截图，warn 配色的对比度与副行折行后的卡片高度都只到代码形态；XCUITest 与截图归 05-04"

# Metrics
duration: 47min
completed: 2026-10-04
status: complete
---

# Phase 5 Plan 03: 空态 + 运行状态卡 + 选择/重扫接线 Summary

**把右列三张卡与来源卡接上真数据 —— 空态三态一张皮且文案逐字（SOURCE-04 / UI-02）、运行状态卡全 6 case 原因与 ffmpeg 可用性（UI-04）、「选择…」与「重新扫描」复用 Phase 4 的单一流水线。**

## Performance

- **Duration:** 47 min
- **Completed:** 2026-10-04T00:30Z
- **Tasks:** 2
- **Files modified:** 11（+595 / -50）

## Accomplishments

- **空态文案的单一来源有三道牙**：逐字相等断言（哨兵写在测试里）+ 全 Sources 计数恰好 1 + 变异 `MUT-P5-EMPTY-COPY` 反向验证。改前缀两个字符 → 红光来自断言、失败恰是那一条用例、恢复后逐字节一致。
- **原因排序是真判据不是注释**：变异拿掉排序后，`testJoinedReasonsSortsByOrderBeforeJoining` 转红（红光来自断言，编译器诊断 0）。**第一次跑变异时它打偏了** —— 我把 `.sorted()` 写进了 doc comment，perl 不带 `/g` 只打第一处匹配，于是命中注释、代码没坏、`MUT=0`。判据字面量不许进注释，这次是第 N 次实证。
- **ffmpeg 判定真的零执行**：`FFmpegAvailability.swift` 剥注释后 `Process(` / `NSTask` / `import SwiftUI|AppKit|AVFoundation` 各 0。六条用例注入临时目录与权限位（0755 / 0644 / 空 / 畸形 PATH），**不依赖本机 PATH**，干净 clone 上同读数。
- **打点数门没破**：`PIC_LIBRARY_STATE` 在 AppDelegate 仍恰好 2 处（取消分支 + onStateChange handler），会话态更新是**扩 handler 体**而不是加打点。`NSOpenPanel(` 全仓仍 1 处，`SettingsStore` 七键零 diff，`test.sh` 64 绿 0 红。
- **两处搬不复制**：选目录拆出 `pickFolder()`（面板 → 校验 → 写盘），首启引导与设置窗「选择…」共用；重扫抽成 `rescanLibrary()`，菜单侧退化成一行读数的薄壳。

## Task Commits

1. **Task 1 RED: 判据先行** — `f2cf18e` (test)
2. **Task 1 GREEN: 实现面** — `dea94e7` (feat)
3. **Task 2: 视图接线 + 探针 + W-29/W-30 登记** — `e05c655` (feat)

_Task 1 是 `tdd="true"`：RED 阶段 `swift test` 因 `cannot find 'FFmpegAvailability' in scope` 真红。GREEN 后无重构改动，故无 refactor 提交。_

## Files Created/Modified

- `Sources/PicCore/App/SettingsPresentation.swift` — 空态文案常量、`isEmptyState`、`holdReasonLabel`（6 case 无 `default:`）、`joinedReasons`（`.sorted()` 全文件唯一）、状态卡两标题
- `Sources/PicCore/App/FFmpegAvailability.swift`（新） — `resolve(searchPaths:fileManager:)` / `resolveFromPATH(environment:)` / `label(available:)`
- `Sources/PicApp/Settings/SettingsSessionState.swift`（新） — `lastLibraryState` / `playableCount` / `lastScanDate` / `isScanning` + `update(state:)`
- `Sources/PicApp/Settings/SettingsView.swift` — 三个注入闭包 + environment sessionState；计数行空态皮、维护卡行改纯展示、运行状态卡两行、扫描期防重入、4 个新 identifier
- `Sources/PicApp/AppDelegate.swift` — `sessionState` + handler 内更新、`pickFolder()`/`FolderPickOutcome`/`requestFolderNow()`、`rescanLibrary()` + 菜单薄壳、`rescanAndApply` 的 isScanning 与计数回写
- `Sources/PicApp/PicApp.swift` — 注入两个闭包 + sessionState environment
- `Tests/PicCoreTests/SettingsPresentationTests.swift` — +8 条（20 条总）
- `Tests/PicCoreTests/FFmpegAvailabilityTests.swift`（新） — 6 条
- `scripts/probe-status-card.sh` + `evidence/status-card.log`（新） — 两轮 source + ffmpeg 自洽 + 锁屏活体观察
- `.planning/WINDOWS.md` — W-2026-10-03-29 / W-2026-10-03-30

## Decisions Made

1. **两个「重扫」入口只留一个能点的**（用户 2026-10-03 指令）。留来源卡计数行那个 —— UI-SPEC §8 明写「空态下「重新扫描」按钮保持可用（它是恢复路径）」，这是行为红线；维护卡那行（§13 点名要补齐）**保留行、去掉按钮**，改为纯展示「上次扫描 HH:MM / 本会话未扫描」。计划原文要求两处都点同一个闭包（判据 `rescan 相关闭包调用计数 ≥ 2`），与用户指令冲突，按指令走；该计数在 `<automated>` 里不是硬门，且改后 `rescanLibrary` 在 `SettingsView` 内仍是「声明 1 + 调用 1」，第二入口消失且不可能漂移。
2. **「上次扫描 HH:MM」落在维护卡的纯展示行**，不在来源卡计数行。计划把它放计数行；但计数行在空态时要显示空态文案，非空态显示时间会让同一行承担两种语义，而维护卡那行空着反而是浪费。UI-SPEC §8 只写「副标签可含」。
3. **取消选目录有两种语义，不共用一行**：首启取消 = 从没配过（发 `folder_unconfigured`，这是该 token 的唯一记录点）；设置窗取消 = 保持现状（**不发任何状态行**）。原实现把两者写在一起，设置窗接线时若原样复用，用户点「选择…」再取消会在正在播放时打出 `folder_unconfigured` —— 那行会谎报当前状态。故拆成 `FolderPickOutcome` 三态由调用方分派。
4. **`FFmpegAvailability` 与既有 `ExternalToolLocator` 刻意并存**：后者带 `which` 执行与 `.available(path:)`，前者是零执行的 PATH-only 判定。`ExternalToolLocator` 的文件头早已为本 plan 让位并写明「06-04 收编为薄委托」，本 plan 不动它（D-17）。
5. **`resolved(搜索路径)` 跳过空目录项**：`URL(fileURLWithPath: "")` 会落到当前目录，那会让「没装」误报成「装了 ./ffmpeg」。一个 `!dir.isEmpty` 守卫换掉一整类假阳性。

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - 计划事实错误] 变异 ② `.sorted()` → `.reversed()` 编不过**
- **Found during:** Task 1 验收
- **Issue**：`reasons.reversed()` 在 `map` 之前给不出 `String`，编译器报 `no 'reversed' candidates produce the expected contextual result type 'String'`。计划的红光纪律是「红光来自断言、`error:` 计数 == 0」，这条变异产生的是**编译器诊断**，直接违反同一份计划自己的纪律。
- **Fix**：改用保型变异 —— 删掉排序调用（`reasons.sorted().map` → `reasons.map`），行尾挂 `// MUT-P5-REASON-ORDER`。类型不变、语义破坏，多原因用例转红。
- **Verification**：`MUT2=1` `R2_RC=1` `R2_ASSERTS=2` `R2_ERRORS=0` 失败恰为 `testJoinedReasonsSortsByOrderBeforeJoining`；恢复后 `cmp -s` 一致。
- **Committed in:** `dea94e7`

**2. [Rule 3 - D-15 判据字面量进注释] 变异 ② 第一次命中的是注释不是代码**
- **Found during:** Task 1 验收首跑
- **Issue**：`MUT2=0` 变异没打上。`joinedReasons` 的 doc comment 里写了「`.sorted()` 只允许出现在本函数」，perl 不带 `/g` 只替换**第一处**匹配 —— 注释在前，于是变异被注释吃掉、代码一行没改、测试照绿。这正是计划 `fails_when` ④ 点名的「perl 没匹配上 = 判据没跑起来，不许当已验证」。
- **Fix**：注释改成「排序调用只允许出现在本函数」，不再逐字出现该调用。
- **Verification**：`MUT2=1`、红光来自断言。
- **Committed in:** `dea94e7`

**3. [Rule 1 - 计划与用户指令冲突] 「重新扫描」两处入口 → 收敛为一处**
- **Found during:** Task 2 视图接线
- **Issue**：计划要求来源卡「重新扫描」与维护卡「扫描」都点同一个闭包（判据：调用点 ≥ 2）；用户 2026-10-03 指令要求只留一处，另一处删掉或改纯展示。
- **Fix**：留来源卡（UI-SPEC §8 的行为红线），维护卡保留行去掉按钮改纯展示。详见 Decisions 1。
- **Verification**：`SettingsView` 内 `Button("…") {}` 计数 == 1 且唯一一处是转码的 disabled 占位；`rescanLibrary` 在视图内「声明 + 唯一调用」= 2。
- **Committed in:** `e05c655`

**4. [Rule 1 - 计划事实错误] `onStateChange` handler 拿不到 playableCount**
- **Found during:** Task 2 接 AppDelegate
- **Issue**：计划写「在既有的 onStateChange handler 里更新 `lastLibraryState`/`playableCount`」，但 `MediaCoordinator.onStateChange` 的签名只给 `LibraryState`，条数在 `apply()` 的入参里。
- **Fix**：`playableCount` 在 `rescanAndApply` 拿到 `report` 的那一处直接回写（紧邻 `coordinator.apply` 调用，不新增打点）；`lastLibraryState` 与隐藏态归零仍走 handler。三个字段的写入点因此是两个而不是一个 —— 强行合并要么改 04-03 冻结的 handler 签名，要么把整份 report 传进去，两者都比两行直写更贵。
- **Verification**：`PIC_LIBRARY_STATE` 打点数仍 == 2；探针 `LIB_STATE_EMPTY=ok`。
- **Committed in:** `e05c655`

**5. [Rule 3 - 计划与既有代码风格冲突] `setUpWithError()` 在本仓不存在**
- **Found during:** Task 1 RED
- **Issue**：`override func setUpWithError() throws` 编译报「method does not override any method from its superclass」。
- **Fix**：照仓内既有写法 `override func setUp() async throws` / `tearDown() async throws`（`MediaLibraryTests` / `FolderRequestPolicyTests` 等 8 个文件同款）。
- **Committed in:** `f2cf18e`

**6. [Rule 2 - evidence 缺真实落点] `status-card.log` 原本只有判据行、缺被断言的三类行**
- **Found during:** Task 2 探针首跑
- **Issue**：探针只把断言结果写进 log，三类 `PIC_*` 原始行留在临时 evidence 文件里，随 `trap` 一起删掉 —— 计划的验收判据 `evidence/status-card.log 含 PIC_LIBRARY_STATE / PIC_FFMPEG / PIC_SETTINGS_WINDOW 三类行` 因此会红。
- **Fix**：按 `probe-settings.sh` 的纪律把两轮 stderr 直接落成 `$LOG`（emit 全走 stderr，同一行不落两遍），断言行追加在后面。
- **Verification**：`libstate=2 ffmpeg=2 window=2`（各两轮一行）。
- **Committed in:** `e05c655`

**7. [Rule 3 - 判据脚本自身错误] `${v##*= }` 不剥带空格的前缀**
- **Found during:** Task 2 探针脚本首跑
- **Issue**：ffmpeg 行解析出的是整行而不是 `0/1`，判据打 `inconsistent`（假红）。
- **Fix**：改 `sed 's/.*available=//'`。
- **Verification**：`FFMPEG_SELF_CONSISTENT=ok available=1 label=可用`。
- **Committed in:** `e05c655`

**8. [Rule 1 - 判据条数回填] `FFmpegAvailabilityTests` 目标 5 条 → 实到 6 条**
- **Found during:** Task 1 验收自检
- **Issue**：计划的 5 条只覆盖 `resolve` 与 `resolveFromPATH`，`label(available:)` 无任何用例 —— 而「只报可用性、不掺版本串」正是 W-2026-10-03-30 的边界，补一条两值穷举断言能把它钉住；不补就是明知有边界却没判据。
- **Fix**：加 `testLabelIsAvailableOrNotInstalledOnly`，判据数字按 05-02 的先例回填为 6。
- **Verification**：`Executed 6 tests, with 0 failures`。
- **Committed in:** `f2cf18e`

**9. [Rule 3 - 计划清单不全] `.planning/WINDOWS.md` 不在 `files_modified` 里，但计划要求写**
- **Issue**：计划的验收判据明写「`LIVE_OBSERVATION` 为 blocked 时 `W-2026-10-03-29` 已在 WINDOWS.md」，W-30 的记账偏差同样要落 WINDOWS.md，而 `files_modified` 漏了这个文件。
- **Fix**：按计划判据写 WINDOWS.md（两条 open 条目，四要素齐全），在 SUMMARY 记账。
- **Verification**：`w29=1`；探针的 blocked 分支先 grep 该条目在册才放行。
- **Committed in:** `e05c655`

---

**Total deviations:** 9 auto-fixed（1 × Rule 1 计划事实错误 ×2 / 1 × Rule 3 D-15 判据进注释 / 1 × Rule 1 计划与用户指令冲突 / 1 × Rule 1 计划与冻结签名冲突 / 1 × Rule 3 仓内既有风格 / 1 × Rule 2 evidence 缺落点 / 1 × Rule 3 判据脚本自身 / 1 × Rule 1 判据条数回填 / 1 × Rule 3 计划清单不全）
**Impact on plan:** 没有一条放宽读数或改产物凑判据。三条改了判据的**写法**（变异②保型化、条数 5→6 回填、evidence 落原始流），都按计划 `fails_when` 预留的口子做且语义未放松；两条把计划里写错的事实（`.reversed()` 编不过、handler 拿不到计数）按实测改形；一条是用户指令与计划冲突时按指令走并**明确记账**。冻结面（`HoldReason` / `LibraryAvailability` / `MediaLibrary` / `SettingsStore` / `MediaCoordinator` 签名）零改动，`PIC_LIBRARY_STATE` 打点数仍 2、`NSOpenPanel(` 仍 1。

## Issues Encountered

- **锁屏活体观察未做**（SC-5 ③）：本会话 `LOCK_STATE_AT_PROBE=1`，无法开设置窗目视。探针记 `LIVE_LOCK_OBSERVATION=blocked reason=screen_locked`，并**先 grep `W-2026-10-03-29` 在册才放行**（缺条目即 `LIVE_LOCK_W_ENTRY_MISSING` 退非 0）—— 静默跳过比缺陷本身更坏。文案映射已由穷举单测逐字钉住，缺的是「屏上真的出现这行字」。XCUITest 解法（`PIC_LOCK_SIGNAL_PREFIX` 注入合成锁事件）归 05-04。
- **空态与状态卡的视觉形态未目视**：warn 配色对比度、空态副行折行后的卡片高度、纯展示的「重新扫描」行读起来是否自然，都只到代码形态，没有截图。归 05-04。
- **ffmpeg 版本串未显示**（W-2026-10-03-30）：状态卡只报可用性。本 Phase 转码入口是 disabled 占位、不执行 ffmpeg，所以不造成功能缺口 —— 但这是**已知不完整**而非已解决。
- **`requestFolderNow()` 未被运行期证据覆盖**：探针起的是无头进程，没有真人点「选择…」的面板交互。`PIC_FOLDER_PICKED` 的写盘路径由既有 `FolderRequestPolicyTests` 覆盖，本次新增的只是「取消不谎报状态」这条分派 —— 它同样未被运行期触发。

## User Setup Required

None —— 无外部服务配置。

## Next Phase Readiness

- **给 05-04 的四个新 anchor**：`select-button` / `rescan-button` / `status-paused` / `status-ffmpeg`，加上 05-02 的 7 个共 11 个 `accessibilityIdentifier`。XCUITest 现在可以直接断言：空态下 `rescan-button.isEnabled == true`（UI-SPEC §8 的恢复路径）、`status-ffmpeg` 副标签逐字等于「可用」或「未安装」、锁屏注入后 `status-paused` 副标签逐字等于「屏幕已锁定」（W-29 的自动化解法）。
- **给 05-04 的新证据**：`evidence/status-card.log`（两轮 + ffmpeg 自洽 + 锁屏读数）。注意 `evidence/uitest.log` **仍是 05-01 的过期读数**，收口门禁若直接消费会拿到误导结论（05-02 已提醒，此处未变）。
- **给 06-transcode 的接口约定**：`FFmpegAvailability` 是 PATH-only 判定，`ExternalToolLocator` 带 `which` 与路径。两者现在**并存**且各自有单测；Phase 6 接线时按 W-30 的解开条件把前者收编为后者的薄委托，别让 ffmpeg 探测出现两个真相源。
- **待收的 W 条目**：-29（锁屏活体，open）、-30（版本串，open）、-28 / -25 / -48 / -49 沿用 05-01/05-02 的登记。
- **本 worktree 的 globals**：`PIC_SOURCE_FOLDER` 只在探针子进程里设，`defaults` 域本 plan 未写入。

---
*Phase: 05-settings*
*Completed: 2026-10-04（Task 1 全绿含两条变异反向验证；Task 2 探针两轮全绿 + W-29/W-30 登记；全量 187 条测试绿、test.sh 64 绿 0 红）*
