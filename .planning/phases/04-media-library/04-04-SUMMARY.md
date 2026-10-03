---
phase: 04-media-library
plan: 04
subsystem: ui
tags: [swift, appkit, nsopenpanel, swiftpm, xctest, menu, seam]

# Dependency graph
requires:
  - phase: 04-media-library (plan 01)
    provides: MediaLibrary 扫描内核（invalidateCache / scan / playableCount）
  - phase: 04-media-library (plan 02)
    provides: RotationController（advanceNow / setItems / setMode / setInterval）+ SystemRotationScheduler
  - phase: 04-media-library (plan 03)
    provides: MediaCoordinator + WallpaperPresenting / PlaybackStopping 两个 seam + LibraryAvailability.token + hide()/show()/stop()
  - phase: 02-playback-core
    provides: MenuContentView / PicApp / AppDelegate 既有骨架与 SettingsStore 三级优先
provides:
  - 五项菜单：MenuItemID 纯增量到 5 case（立即下一个 / 重新扫描文件夹），渲染仍零手写 Button
  - FolderRequestPolicy 纯函数（该不该弹框四态 / normalizedPath / isAcceptableSelection）
  - FolderPicker 协议 + NSOpenPanelFolderPicker（全仓唯一 NSOpenPanel 落点）
  - AppDelegate 四方法四持有者：requestFolderIfNeeded / rescanAndApply / nextVideoNow / rescanFolderNow + 两个 seam 适配类型
  - PIC_FOLDER_REQUEST_REASON / PIC_FOLDER_PICKED / PIC_FOLDER_PICK_CANCELLED / PIC_FOLDER_PICK_REJECTED / PIC_MENU_ACTION 读数
affects: [04-05 装配（onAdvance → player.load、startWallpaper 目录协调）, 04-06 test.sh 判据（NSOpenPanel 落点形态）, 05-settings（设置窗换目录走 rescanAndApply）]

# Actuals (#2632)
actuals:
  tokens: 6811   # chars/4 over the realized diff（27244 chars / 8 文件）
  tasks: 3
  commits: 5      # T1/T2 各 RED+GREEN 两段 + T3 单段（装配胶水无测试面，见 TDD Gate Compliance）

# Tech tracking
tech-stack:
  added: []   # 零第三方依赖不变
  patterns:
    - 「该不该弹框」与「这次选择合不合法」都是只吃标量的纯函数（envOverride 由调用方取）—— 决策不读全局状态才能穷举
    - 面板被隔离在单文件 seam 后面：协议只交出 URL 或 nil，不写设置、不碰激活策略，「用户取消」不需要任何特殊分支
    - 「切换目录」与「重新扫描」共用同一个 rescanAndApply —— 两处实现必然会漂

key-files:
  created:
    - Sources/PicCore/App/FolderRequestPolicy.swift
    - Sources/PicApp/FolderPicker.swift
    - Tests/PicCoreTests/FolderRequestPolicyTests.swift
  modified:
    - Sources/PicCore/App/MenuItem.swift
    - Sources/PicApp/App/MenuContentView.swift
    - Sources/PicApp/PicApp.swift
    - Sources/PicApp/AppDelegate.swift
    - Tests/PicCoreTests/MenuBarModelTests.swift

key-decisions:
  - "bootstrapAfterWiring 对 requestFolderIfNeeded 的返回值取 guard：取消/被拒时不再跑 rescanAndApply —— 否则未配置态会被 onStateChange 再打一遍同一 token，取消分支那行 emit 就不是「唯一方式」了（D-17：一个数不两种读法）"
  - "coordinator 用 lazy var：构造参数要包住 wallpaper / player 两个持有者，属性默认值里引用不了 self；每次访问都在主线程，无竞态"
  - "rotation 的随机源用启动时刻做 seed（SeededRandomSource），间隔与模式在 rescanAndApply 里从 store 带过来 —— 不存第二份真相"
  - "rescanAndApply 的 catch 写成 typed catch（as MediaLibraryError）+ 不可达兜底（.folderUnreadable）：apply 的参数是具体错误类型，裸 catch 拿到的是 any Error 编译不过"

patterns-established:
  - "两个 NSOpenPanel 判据的子串污染修法（Task 2 全仓计数 / Task 3 AppDelegate 计数）：计划冻结的类名 NSOpenPanelFolderPicker 自身含子串，判据须测「构造调用 NSOpenPanel( 计数」或「含 token 的文件清单」，04-06 落 test.sh 时照此形态"

requirements-completed: [SOURCE-01, SOURCE-05, SOURCE-08, MENUBAR-04, MENUBAR-05, SYS-03]

# Coverage metadata (#1602)
coverage:
  - id: D1
    description: "菜单从 3 项纯增量到 5 项：MenuItemID 顺序冻结 [pauseResume, nextVideo, rescanFolder, openSettings, quit]，quit 保持最后；渲染仍只由 allCases 遍历产出（Button 行数 == ForEach 行数 == 1）"
    requirement: MENUBAR-04
    verification:
      - kind: unit
        ref: Tests/PicCoreTests/MenuBarModelTests.swift#testMenuItemIDsAreExactlyTheFiveFixedItems
        status: pass
      - kind: unit
        ref: Tests/PicCoreTests/MenuBarModelTests.swift#testLabelsHaveExactlyFiveEntriesInEveryState
        status: pass
      - kind: other
        ref: "gates MENU_FIVE_ITEMS_OK（button=1=forEach、default_branch=0、activate_next=1、activate_rescan=1、default_params=1/1）"
        status: pass
    human_judgment: false
  - id: D2
    description: "两条新文案逐字冻结（立即下一个 / 重新扫描文件夹），五条文案两两不同且不含文件名/扩展名/路径；MENUBAR-08 哨兵用例原样通过"
    requirement: MENUBAR-05
    verification:
      - kind: unit
        ref: Tests/PicCoreTests/MenuBarModelTests.swift#testNextVideoAndRescanLabelsAreDistinctAndPathless
        status: pass
      - kind: unit
        ref: Tests/PicCoreTests/MenuBarModelTests.swift#testLabelsNeverContainAnyMediaFileName   # 一字未改，git diff 零命中
        status: pass
    human_judgment: false
  - id: D3
    description: "perform(.nextVideo) / perform(.rescanFolder) 各自只调注入闭包，不碰 arbiter/store/quit（T-04-22）；既有五个参数一字未改、新参数带默认值，Phase 2 三处调用点零改动"
    verification:
      - kind: unit
        ref: Tests/PicCoreTests/MenuBarModelTests.swift#testPerformNextVideoCallsOnlyItsInjectedClosure
        status: pass
      - kind: unit
        ref: Tests/PicCoreTests/MenuBarModelTests.swift#testPerformRescanFolderCallsOnlyItsInjectedClosure
        status: pass
    human_judgment: false
  - id: D4
    description: "「该不该弹框」四态纯函数：空串 true / 纯空白 true（T-04-19 防永久卡死）/ 已配置 false / 环境变量覆盖压过一切（SYS-03 / SOURCE-07 决策半边）"
    requirement: SYS-03
    verification:
      - kind: unit
        ref: Tests/PicCoreTests/FolderRequestPolicyTests.swift#testEmptySourceFolderAndNoEnvOverrideRequestsFolder
        status: pass
      - kind: unit
        ref: Tests/PicCoreTests/FolderRequestPolicyTests.swift#testWhitespaceOnlySourceFolderIsTreatedAsUnconfigured
        status: pass
      - kind: unit
        ref: Tests/PicCoreTests/FolderRequestPolicyTests.swift#testConfiguredSourceFolderDoesNotRequestFolder
        status: pass
      - kind: unit
        ref: Tests/PicCoreTests/FolderRequestPolicyTests.swift#testEnvOverrideSuppressesTheRequest
        status: pass
      - kind: unit
        ref: Tests/PicCoreTests/FolderRequestPolicyTests.swift#testIsAcceptableSelectionRejectsNilAndRegularFiles
        status: pass
    human_judgment: false
  - id: D5
    description: "FolderPicker seam：NSOpenPanelFolderPicker 三个必设项齐全、不碰激活策略、不碰设置；全仓唯一面板落点"
    verification:
      - kind: other
        ref: "gates（判据适配后）：panel_nofiles=1 panel_dirs=1 panel_single=1 panel_activation=0 panel_store=0；构造调用 NSOpenPanel( 全仓恰 1 处、含 token 的文件恰 FolderPicker.swift 一个"
        status: pass
    human_judgment: true
    rationale: "面板真弹出、用户真取消这些活体行为需要 GUI 会话（本机屏幕锁着）；本 plan 只有结构判据与纯函数决策侧的覆盖，运行期读数（PIC_FOLDER_*）要 04-05 装配后的 evidence"
  - id: D6
    description: "AppDelegate 接线：四方法各恰 1 处、store.persist() 恰 1 处、NSApp.setActivationPolicy 恰 3 处（三处一字未动）、PIC_LIBRARY_STATE 恰 2 处各有独立语义、B1 门 gate_line(318) < rate_line(319)、AppDelegate 内零直接面板使用"
    verification:
      - kind: other
        ref: "gates（判据适配后）：next=1 rescan=1 request=1 rescan_apply=1 invalidate=1 advance=1 persist=1 activation=3 state_line=2；排除 seam 类名后 NSOpenPanel 计数 0"
        status: pass
      - kind: unit
        ref: "全量 swift test 108 tests, 0 failures（Phase 1–3 与 04-01/02/03 的全部用例 + 本 plan 新增 8 条）"
        status: pass
    human_judgment: true
    rationale: "首启弹框 → 选定 → 持久化 → 立即起播这条链的运行期行为（读数行真的打出来、换目录立即换片）需要活体 GUI 会话；本 plan 的判据是结构计数 + 单测，活体 evidence 属 04-05"
  - id: D7
    description: "「重新扫描文件夹」显式失效缓存后走与切换目录同一条 rescanAndApply（SOURCE-05 机制）；「立即下一个」只叫轮换器不碰播放端（MENUBAR-04 行为侧）"
    requirement: SOURCE-05
    verification:
      - kind: other
        ref: "gates：invalidate=1 advance=1；rescanAndApply 单实现被 requestFolder 成功路径与 rescanFolderNow 共同调用（源码各恰 1 处引用）"
        status: pass
    human_judgment: true
    rationale: "「点了当场可见」「换片即时生效」是运行期行为，需 04-05 接上 onAdvance → player.load 之后才有可观测的活体判据；本 plan 只能锁机制在位（显式失效 + 单一路径 + 零播放器直连）"

# Metrics
duration: 9 min
completed: 2026-10-03
status: complete
---

# Phase 4 Plan 4: 用户可控入口 Summary

**菜单 3→5 项（立即下一个 / 重新扫描文件夹，零手写 Button）+ FolderRequestPolicy 纯函数与 FolderPicker 面板 seam + AppDelegate 首启弹框/选定即持久化/换目录与重扫同路径接线，新增 8 条单测，全量 108 tests 0 failures**

## Performance

- **Duration:** 9 min（2026-10-03T11:38:04Z → 11:46:40Z）
- **Started:** 2026-10-03T11:38:04Z
- **Completed:** 2026-10-03T11:46:40Z
- **Tasks:** 3（全部完成；T1/T2 按 tdd="true" 走 RED→GREEN，T3 为装配胶水单段）
- **Files modified:** 8（3 新建 + 5 修改；diff 27244 chars / +372 −11）

## Accomplishments

- 五项菜单一次成型且判据全过：`MenuItemID.allCases` 冻结序 `[.pauseResume, .nextVideo, .rescanFolder, .openSettings, .quit]`；`ForEach` 一个字未改自动带出两个新项；`activate` 补两路且无 `default:`；`perform` 既有五参数一字未改、两个新闭包带默认值 —— Phase 2 的三处调用点零改动
- 「该不该弹框」成为可穷举的纯函数：空串 / 纯空白（T-04-19 防永久卡死）/ 已配置 / 环境变量覆盖四态各有专门用例；`normalizedPath` 走 `resolvingSymlinksInPath().standardizedFileURL.path`（D-09）
- 面板被关进单文件 seam：`FolderPicker.swift` 全仓唯一构造 `NSOpenPanel()` 的地方，三个必设项齐全，不碰激活策略、不碰设置 —— 「用户取消」就是干净的 `nil`，无需特殊分支
- AppDelegate 接线全过：取消/被拒/选定各有独立读数、写偏好仅 `persist()` 一处、激活策略仍是三处一字未动、`PIC_LIBRARY_STATE` 恰两处各有独立语义、B1 门行号序保持（318 < 319）
- MENUBAR-08 哨兵 `testLabelsNeverContainAnyMediaFileName` **一字未改**（diff 零命中）且继续通过；`test.sh` 既有菜单判据（Button==ForEach、结构体内零取文件名 API）实测未破

## Task Commits

Each task was committed atomically (T1/T2 tdd="true" → RED/GREEN 两段)：

1. **Task 1 RED: 五项菜单失败测试 + 编译骨架** - `a9c8bfa` (test)
2. **Task 1 GREEN: 文案与 perform 分支落地** - `0378123` (feat)
3. **Task 2 RED: FolderRequestPolicy 失败测试 + 骨架** - `ae6a59f` (test)
4. **Task 2 GREEN: 纯函数实现 + FolderPicker seam** - `a04a5de` (feat)
5. **Task 3: AppDelegate 接线（装配胶水，无测试面）** - `2878f40` (feat)

**Plan metadata:** 本 SUMMARY 提交（docs）

## TDD Gate Compliance

- **T1 RED**：`Executed 10 tests, with 9 failures` —— 全部为断言失败（骨架文案为空串、perform 分支 break），0 编译错误；GREEN 后 10/10 绿
- **T2 RED**：`Executed 5 tests, with 4 failures` —— 全部为断言失败（骨架恒 false / 恒 true），0 编译错误；GREEN 后 5/5 绿
- **T3 无 RED 段**：计划的 `<files>` 只有 `AppDelegate.swift`，无测试文件 —— 装配胶水按 tdd.md 自己的 skip 判据（"Glue code connecting existing components"）单 feat 提交；其行为面由结构判据 + 全量回归（108/108）覆盖，活体判据属 04-05
- 无 REFACTOR 段（实现一次到位，无后续清理可做）

## Files Created/Modified

- `Sources/PicCore/App/MenuItem.swift` - 5 case（追加位置纪律写进文件头）、两条冻结文案、perform 两个带默认值闭包参数
- `Sources/PicCore/App/FolderRequestPolicy.swift` - 三个纯函数：shouldRequestFolder / normalizedPath / isAcceptableSelection；零 AppKit、零全局状态读取
- `Sources/PicApp/FolderPicker.swift` - `@MainActor protocol FolderPicker` + `NSOpenPanelFolderPicker`；全仓唯一面板落点
- `Sources/PicApp/App/MenuContentView.swift` - init 两个带默认值闭包、activate 补两路（无 default:）；ForEach 与 Divider 规则不动
- `Sources/PicApp/PicApp.swift` - MenuContentView 构造点注入两个闭包（纯增量两行）
- `Sources/PicApp/AppDelegate.swift` - 四个强持有者 + lazy coordinator + 两个 seam 适配类型 + 四方法 + Task 化 bootstrap；startWallpaper 末尾段与调用顺序一个字符未动
- `Tests/PicCoreTests/MenuBarModelTests.swift` - 两条「三项」断言改名收紧到五项；追加 3 条；哨兵用例一字未改
- `Tests/PicCoreTests/FolderRequestPolicyTests.swift` - 5 条纯函数用例；零 AppKit、零 fixtures 依赖

## Decisions Made

- **bootstrapAfterWiring 对返回值取 guard**（取消/被拒不再跑 rescanAndApply）：保住「取消分支那行 emit 是该路径记录 token 的唯一方式」这条计划语义，避免对同一件事打两遍读数（D-17）
- **coordinator 为 lazy var**：构造参数要包 wallpaper / player，属性默认值里引用不了 self；主线程访问无竞态
- **rotation 的 seed 用启动时刻**，模式与间隔在 rescanAndApply 从 store 带过来（不存第二份真相）
- **typed catch + 不可达兜底**：`apply` 吃具体错误类型，兜底按 `.folderUnreadable`（隐藏 + 让出桌面，最安全的降级方向）
- **不跑 `bash test.sh`**（按计划的 wave 纪律，统一校验在 04-06）；但对其受影响的既有判据做了只读实测：absoluteString=0、Button==ForEach==1、NSApp.terminate=1、player.player.play/pause=0、0.5s 轮询=0 —— 全部未破

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - 计划算术] MenuBarModelTests 期望 8 条，实际 10 条**
- **Found during:** Task 1（写测试前核算既有条数）
- **Issue:** 判据写「Executed 8 tests」，但文件既有 7 条（含要改名的 2 条）+ 新增 3 条 = 10 条；计划自己在括号里预判了这条（「以文件里 func test 的实际条数为准…回填确切数字」）
- **Fix:** 判据按实际回填为 10；用例一条没少（改名保留 2 条 + 哨兵一字未改 + 既有其余原样）
- **Files modified:** 无入库文件（仅判读数字）
- **Verification:** `Executed 10 tests, with 0 failures`；TEST_FUNC_COUNT=10
- **Committed in:** 不适用

**2. [Rule 1 - 计划 grep 缺陷] T2 全仓 NSOpenPanel 计数 == 1 被计划自己冻结的类名污染**
- **Found during:** Task 2 verify 首跑（all_nsopenpanel=2）
- **Issue:** `src_count 'NSOpenPanel'` 是子串匹配，计划的符号清单冻结的类名 `NSOpenPanelFolderPicker` 自身含该子串（声明行 1 处 + 构造 1 处 = 2）—— 判据按字面不可满足，且唯一「多余」命中正是判据要保护的 seam 本身
- **Fix:** 按 fails_when ⑨ 的「落点」意图改测两个更硬的形态：构造调用 `NSOpenPanel(` 全仓恰 **1** 处；含该 token 的文件恰 `FolderPicker.swift` **一个**。意图（唯一落点、SYS-03 有实现）收紧而非放宽
- **Files modified:** 无入库文件（仅 verify 脚本，/tmp）
- **Verification:** 构造计数实测 1；`grep -rln NSOpenPanel Sources/` 只有 FolderPicker.swift
- **Committed in:** 不适用
- **⚠️ 给 04-06 的移交**：落 test.sh 常驻判据时必须用「构造调用计数」或「文件清单」形态，裸子串计数会被类名恒撑到 2

**3. [Rule 1 - 计划 grep 缺陷] T3 的 AppDelegate NSOpenPanel == 0 被同一根因污染**
- **Found during:** Task 3 verify 首跑（nsopenpanel=1）
- **Issue:** 唯一代码命中是 `let picker: any FolderPicker = NSOpenPanelFolderPicker()` —— 那正是计划 T3 ② 要求持有的 seam 句柄，不是「seam 被绕过」
- **Fix:** 按 fails_when ④ 的意图改测：排除 `NSOpenPanelFolderPicker` 类名后计数 == **0**（实测通过）—— AppDelegate 内没有任何直接面板使用
- **Files modified:** 无入库文件（仅 verify 脚本，/tmp）
- **Verification:** 排除后计数 0；行号定位确认唯一命中即 holder 声明行
- **Committed in:** 不适用

**4. [Rule 1 - 计划文本矛盾] T2 文件头注释指令与 files_modified / 符号清单矛盾**
- **Found during:** Task 2（决定协议落位前）
- **Issue:** action 要求文件头写「为什么协议在 PicCore/App/ 而实现要在 PicApp/」，但同一计划的 files_modified 与 Artifacts 符号清单都把 `protocol FolderPicker` 放在 `Sources/PicApp/FolderPicker.swift`（PicCore/App 下没有 FolderPicker.swift 这一项）
- **Fix:** 按 files_modified（范围权威）把协议与实现同放 PicApp/FolderPicker.swift；文件头注释改写为解释真正的分层 —— 决策（FolderRequestPolicy，纯函数）在 PicCore/App、面板胶水在 PicApp
- **Files modified:** Sources/PicApp/FolderPicker.swift（头注释的措辞）
- **Verification:** 文件头说明分层理由；判据零涉及
- **Committed in:** a04a5de

**5. [Rule 3 - 编译必需] T1 在 AppDelegate 加了两个空 stub**
- **Found during:** Task 1（PicApp.swift 注入后编译）
- **Issue:** PicApp 的两个闭包调 `appDelegate.nextVideoNow()/rescanFolderNow()`，方法不存在则 `swift build` 红 —— 计划 fails_when ① 预判了这条（「说明本 task 的 T3 还没实现这两个 AppDelegate 方法」）
- **Fix:** T1 RED 提交里带两个标注「RED 骨架」的空方法让包可编译；T3 提交替换为真实实现（轮换器 / 失效缓存 + 重扫）。终态与计划的 must_hives 一致
- **Files modified:** Sources/PicApp/AppDelegate.swift
- **Verification:** T1 两个提交各自 build 绿；T3 后四方法各恰 1 处
- **Committed in:** a9c8bfa → 2878f40

**6. [Rule 3 - 执行环境] 三个 `<automated>` 块硬编码主检出路径**
- **Issue:** 均以 `cd /Users/coderstory/dev/pic` 开头，在本 worktree 执行会校验主检出（worktree-path-safety #4767 要防的缺陷；04-01/02/03 三个兄弟 plan 同款）
- **Fix:** 全部落成 /tmp 脚本并以本 worktree root 重定根，命令体逐字不变
- **Verification:** 三个 verify 各自打出 OK 行（T2/T3 的两处判据适配见 Deviation 2/3）
- **Committed in:** 不适用

**7. [Rule 1 - 判据环境适配] T3 汇总串 grep 对带 skip 的全量输出不匹配**
- **Issue:** 判据 grep `Executed [0-9]+ tests, with 0 failures`，但全量汇总实际打 `Executed 108 tests, with 1 test skipped and 0 failures`（skip 是 04-03 既有的 XCTSkip）—— grep 恒空；`ALLTESTS_RC=0` 才是真信号（04-03 Deviation 2 同款形态）
- **Fix:** 以 ALLTESTS_RC=0 + 全量汇总行（108 tests, 1 skipped, 0 failures）作判读
- **Committed in:** 不适用

---

**Total deviations:** 7 auto-fixed（4 处 Rule 1 计划判据/算术/文本缺陷 + 1 处 Rule 1 判据环境适配 + 2 处 Rule 3 执行环境适配）
**Impact on plan:** 全部为让判据**本身**可达成而修，无一放宽读数、无一改产物值凑判据。两处 NSOpenPanel 判据的修法都把「唯一落点」锁得更硬（构造计数 + 文件清单），且给 04-06 留了明确的形态移交。

## Issues Encountered

- `coordinator.apply(scanOutcome: .failure(error))` 首次编译红（`any Error` → `MediaLibraryError`）—— 改 typed catch + 不可达兜底后过；属常规 Swift 类型修正
- 屏幕锁着不影响本 plan：全部判据是命令行可验证的读数；面板与起播的活体行为已如实标 human_judgment（D5/D6/D7），等 04-05 的 evidence

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- 给 04-05 的公开面：`RotationController.onAdvance` 尚未接 `player.load`（本 plan 刻意不接，T-04-22）；`startWallpaper()` 的目录获取与起播协调（「先 await bootstrap 再起播」）是 04-05 的活，本 plan 保证了 `requestFolderIfNeeded` / `rescanAndApply` 两个方法存在且可调
- Phase 5 设置窗换目录：改 `store.sourceFolder` + `persist()` 后调 `rescanFolderNow()`（或直接 `rescanAndApply`）即得「换目录立即换片」（SOURCE-08 的入口在设置窗，机制已就位）
- ⚠️ 给 04-06 的移交：NSOpenPanel 判据须用「构造调用计数 / 文件清单」形态（Deviation 2/3），裸子串计数被冻结类名恒撑到 2
- ⚠️ `nextVideoNow` 的换片实际生效依赖 04-05 接上 onAdvance；在那之前菜单项只打读数 + 叫轮换器（MENUBAR-04 的「即时生效」要到 04-05 才完整）
- `bash test.sh` 统一校验在 04-06（本 plan 未跑，按 wave 纪律；受影响的既有判据已只读实测未破）
- 全量 `swift test` 本 worktree 实测 **108 tests, 0 failures**（1 skipped 为 04-03 既有的 fixtures 缺席 XCTSkip）

---
*Phase: 04-media-library*
*Completed: 2026-10-03*
