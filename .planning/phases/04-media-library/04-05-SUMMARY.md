---
phase: 04-media-library
plan: 05
subsystem: playback
tags: [swift, swiftpm, xctest, rotation, wiring, seam, probe]

# Dependency graph
requires:
  - phase: 04-media-library (plan 01)
    provides: MediaLibrary 扫描内核（scan 缓存 / MediaLibraryReport.items）+ VideoItem
  - phase: 04-media-library (plan 02)
    provides: RotationController（onAdvance 单向出参 / setItems / start / advanceNow / advances）+ SeededRandomSource + SystemRotationScheduler
  - phase: 04-media-library (plan 03)
    provides: MediaCoordinator.apply -> LibraryState（.playing / 三隐藏态的纯决策）
  - phase: 04-media-library (plan 04)
    provides: AppDelegate 四方法四持有者（requestFolderIfNeeded / rescanAndApply / nextVideoNow / rescanFolderNow）+ bootstrapAfterWiring
provides:
  - PlaybackRouter + VideoLoading seam（轮换 onAdvance → 可注入装载，零播放框架/零 AppKit/零仲裁器）
  - AppDelegate 装配：PlayerLoadingAdapter（装载后重放仲裁决策）、LibraryState 驱动的装载分派、startWallpaper 异步化并挪到 bootstrap 末尾（SC1/SC3/SC4）
  - PIC_ROT_MODE / PIC_ROT_START / PIC_ROT_STOP / PIC_ROT_ADVANCES 运行期读数
  - scripts/probe-rotation-wiring.sh + evidence/rotation-wiring.log（装配链活体证据，应用级路径如实标 informational=1）
affects: [04-06 test.sh 判据（PIC_ROT_* / B1 / NSOpenPanel 形态移交）, 05-settings（改设置立即生效的轮换侧已就位）, 07 长跑（应用级启动路径的活体采集）]

# Actuals (#2632)
actuals:
  tokens: 6497   # chars/4 over the realized diff（T1 7441 + T2/T3 18547 = 25988 chars / 6 文件）
  tasks: 3
  commits: 5      # T1 RED+GREEN（并行执行者）+ T2 + T3 + 本 SUMMARY

# Tech tracking
tech-stack:
  added: []   # 零第三方依赖不变
  patterns:
    - 装载后立刻重放仲裁决策（PlayerLoadingAdapter）：换片路径与起播路径共用 B1 那道门的语义，hold 会话不留「先播一下」的旁路
    - LibraryState 驱动的装载分派只看 coordinator.apply 的返回值 —— AppDelegate 不自判「有没有视频」，与 LibraryAvailability 纯函数不漂第二处
    - 探针证据只证 PicCore 侧装配链，应用级路径结构性声明 informational=1（不进任何门禁）

key-files:
  created:
    - Sources/PicCore/Playback/PlaybackRouter.swift
    - Tests/PicCoreTests/PlaybackRouterTests.swift
    - .planning/spike/RotationWiringDriver.swift
    - scripts/probe-rotation-wiring.sh
    - .planning/phases/04-media-library/evidence/rotation-wiring.log
  modified:
    - Sources/PicApp/AppDelegate.swift

key-decisions:
  - "装载分派替换而非追加：04-04 的 rescanAndApply 里已有 rotation.setItems+start，router.start(with:) 已包含两者，保留会双重驱动轮换器 —— 换成按 LibraryState 分派的单一路径（见 Deviation 2）"
  - "PIC_ROT_MODE 打在 rescanAndApply 既有的模式/间隔同步之后（那里是唯一真相源），不在装配处再同步第二遍（D-17）"
  - "file_missing 守卫移除（计划允许的两个选项之一）：装载前存在性由 MediaLibrary.scan 的 folderMissing + 探针负责，firstVideoURL 保留不删"
  - "启动时 items[0] 装载两次（rescanAndApply 的 .playing 分派 + startWallpaper 起播段，两者都是计划明文）：同 URL 幂等装载、第二次 scan 走缓存（T-04-25），终态正确"

patterns-established:
  - "「计划说追加、现实已有等价调用」时按 must_hives 的真值语义取单一路径，并记 deviation —— 不留双重驱动"

requirements-completed: [SOURCE-07]

# Coverage metadata (#1602)
coverage:
  - id: D1
    description: "PlaybackRouter seam：onAdvance 先绑后 start（items[0] 当场装载）、.loopList 按序、.shuffle 一轮内每条恰好一次、空列表零装载、重绑不放大单次 advance 的装载；零播放框架/零 AppKit/零仲裁器"
    verification:
      - kind: unit
        ref: Tests/PicCoreTests/PlaybackRouterTests.swift#testStartLoadsFirstItemForLoopSingle
        status: pass
      - kind: unit
        ref: Tests/PicCoreTests/PlaybackRouterTests.swift#testAdvanceNowLoadsNextInLoopList
        status: pass
      - kind: unit
        ref: Tests/PicCoreTests/PlaybackRouterTests.swift#testShuffleRoundVisitsEveryItemExactlyOnce
        status: pass
      - kind: unit
        ref: Tests/PicCoreTests/PlaybackRouterTests.swift#testEmptyItemsLoadsNothing
        status: pass
      - kind: unit
        ref: Tests/PicCoreTests/PlaybackRouterTests.swift#testStartRebindingDoesNotDoubleLoadPerAdvance
        status: pass
      - kind: other
        ref: "mutation: MUT-P4-LOAD（recordLoad 的装载调用换空操作）→ testStartLoadsFirstItemForLoopSingle 转红，7 条断言失败、0 条编译诊断（:line:col: error: / SwiftCompile 形态判别），恢复后 cmp -s 逐字节一致"
        status: pass
    human_judgment: false
  - id: D2
    description: "AppDelegate 装配结构：startWallpaper 异步化且仅 bootstrapAfterWiring 末尾一处调用（requestFolder → rescan → startWallpaper 顺序写死）；LibraryState 分派装载/停装载；PlayerLoadingAdapter 装载后重放仲裁决策（applyCurrentDecision ≥ 2）；B1 门行号序 324 < 325；04-04 既有分层（persist=1 / activation=3 / AppDelegate 零直接面板使用）未破"
    verification:
      - kind: other
        ref: "gates APPDELEGATE_ROTATION_WIRING_OK（startfunc=1 startcall=1 adapter=2 apply=2 rotrun=2 rotstop=1 panel_excl_seam=0 persist=1 activation=3 rots=1/1/1/1 gate_line=324 rate_line=325）"
        status: pass
      - kind: unit
        ref: "全量 swift test 113 tests, 1 skipped（04-03 既有 XCTSkip）, 0 failures — Phase 1–4 全部用例"
        status: pass
    human_judgment: false
  - id: D3
    description: "SC4 应用级路径「下次启动自动读取已配置文件夹并开始播放」的运行期行为（真实 GUI 启动一次 app）"
    verification: []
    human_judgment: true
    rationale: "应用级启动序列需要真实启动一次 app 才能证；当前屏幕锁着、显示器熄着（CGDisplay_IS_ASLEEP=1），本 Phase 不采集 —— evidence 里结构性声明 PIC_ROT_APP_LAUNCH informational=1 scope=piccore-chain，登记为 Phase 7 的活；PicCore 侧装配链由 D1/D4 覆盖"
  - id: D4
    description: "活体证据 rotation-wiring.log：三模式装载计数与顺序、shuffle 一轮 3 不重复、空列表 0、模式 token、行数；零媒体文件名、零 Phase 2/3 路径；PIC_EVIDENCE_DIR 重定向不改入库证据（重定向产物与入库日志逐字节一致）"
    verification:
      - kind: other
        ref: "command: bash scripts/probe-rotation-wiring.sh → ROTATION_WIRING_EVIDENCE_OK（items=1 loopsingle=1 looplist=ok shuffle=3 empty=0 mode=1 lines=1 applaunch=1 redirect=1 filename_leak=0 foreign_path=0，EVIDENCE_LINES=10）"
        status: pass
    human_judgment: false

# Metrics
duration: 24 min
completed: 2026-10-03
status: complete
---

# Phase 4 Plan 5: 轮换装配 Summary

**PlaybackRouter 把 RotationController.onAdvance 接到可注入的 VideoLoading seam（5 条单测 + 断言型变异红光），AppDelegate 装配成产品：LibraryState 驱动装载分派、装载后重放仲裁决策、startWallpaper 异步化挪到 bootstrap 末尾（SC1/SC3/SC4），活体证据只证 PicCore 链、应用级路径如实标 informational=1**

## Performance

- **Duration:** 24 min（本执行者 T2–T3：2026-10-03T11:47Z → 12:11Z；T1 由并行执行者先行完成）
- **Started:** 2026-10-03T11:47:00Z（T2–T3 会话）
- **Completed:** 2026-10-03T12:11:05Z
- **Tasks:** 3（全部完成；T1 tdd="true" RED→GREEN 由任务级并行执行者交付，T2/T3 由本执行者交付）
- **Files modified:** 6（5 新建 + 1 修改；diff 25988 chars）

## Accomplishments

- 轮换的每一条「下一条」真的驱动装载：`PlaybackRouter.start(with:)` 先绑 `onAdvance` 再 `setItems`/`start()`，`items[0]` 当场进 `loadPlayback`；`advanceNow()` 驱动下一条（SC3）；`.loopList` 按序 `[0,1,2,0]`、`.shuffle`（seed 42）一轮内 3 条恰好一次、空列表零装载、重绑不放大单次 advance（5/5 绿 + MUT-P4-LOAD 变异红：7 断言失败、0 编译诊断）
- AppDelegate 装配全过：`PlayerLoadingAdapter` 装载后立刻 `arbiter.applyCurrentDecision()`（hold 会话换片不先播一下，T-04-24）；`rescanAndApply` 按 `coordinator.apply` 返回的 `LibraryState` 分派（`.playing` → `router.start`，三隐藏态 → `router.stop` + `PIC_ROT_STOP`）；`startWallpaper()` 异步化、走 `MediaLibrary.scan` + `router.start`，仅在 `bootstrapAfterWiring()` 末尾被调用一次（`requestFolderIfNeeded → rescanAndApply → startWallpaper` 顺序写死，SC4）
- B1 门与 04-04 既有分层一字未动：`if arbiter.decision.shouldPlay {`（324）早于 `player.setRate(store.rate)`（325）；`persist` == 1、`setActivationPolicy` == 3、AppDelegate 零直接面板使用（排除 seam 类名后 NSOpenPanel == 0）、`wiring()` 四根 Watcher 线未动
- 活体证据一条命令到手：`PIC_ROT_LOOPSINGLE_LOADS=4` / `PIC_ROT_LOOPLIST_ORDER=ok` / `PIC_ROT_SHUFFLE_ROUND_UNIQUE=3` / `PIC_ROT_EMPTY_LOADS=0` / `PIC_ROT_MODE=shuffle`，全部独立计数行（D-17）；日志零媒体文件名、零 Phase 2/3 路径；应用级启动路径如实打 `PIC_ROT_APP_LAUNCH informational=1 scope=piccore-chain reason=app-launch-blocked-by-locked-screen`（T-04-28）
- 全量 `swift test` **113 tests, 1 skipped（04-03 既有）, 0 failures**；`swift build` 退出码 0；按 wave 纪律未跑 `bash test.sh`（统一校验在 04-06）

## Task Commits

Each task was committed atomically (T1 tdd="true" → RED/GREEN 两段，由任务级并行执行者交付；T2/T3 由本执行者交付):

1. **Task 1 RED: PlaybackRouter 失败测试** - `9f92909` (test)
2. **Task 1 GREEN: PlaybackRouter + VideoLoading seam 实现** - `f71aa71` (feat)
   -（经 `f6dc31e` 合入，任务级并行 with wave 3）
3. **Task 2: AppDelegate 装配（router / 分派 / 异步起播挪位）** - `13c29e7` (feat)
4. **Task 3: 活体证据（driver + probe 脚本 + evidence）** - `7f5755b` (feat)

**Plan metadata:** 本 SUMMARY 提交（docs）

## Files Created/Modified

- `Sources/PicCore/Playback/PlaybackRouter.swift`（T1）- `protocol VideoLoading`（唯一方法 `loadPlayback(url:)`，名字与 `PlayerController.load(url:)` 刻意错开）+ `@MainActor PlaybackRouter`（`start`/`stop`/`advanceNow`/`current`/`loadCount`）；零 AVFoundation/AppKit/SwiftUI/AVPlayer/HoldArbiter
- `Tests/PicCoreTests/PlaybackRouterTests.swift`（T1）- 恰 5 条 + 文件内 `RecordingLoader` / `NoopScheduler`（不跨文件引用 04-02 的 helper）
- `Sources/PicApp/AppDelegate.swift`（T2）- `PlayerLoadingAdapter`（文件底部，与既有两个适配同位）；`router` 强持有（lazy）；`rescanAndApply` 的 LibraryState 分派 + `PIC_ROT_MODE`；`startWallpaper()` 异步化 + `router.start` + `PIC_ROT_START`；`nextVideoNow` 的 `PIC_ROT_ADVANCES`；启动序列删同步调用、bootstrap 末尾追加 `await startWallpaper()`
- `.planning/spike/RotationWiringDriver.swift`（T3，throwaway）- `@main` 与产品源一起编译；文件内 `RecordingLoader` / `NoopScheduler`；8 行读数每行一个数
- `scripts/probe-rotation-wiring.sh`（T3）- probe-lock.sh 全部纪律（perl alarm / 不用 set -e / PIC_EVIDENCE_DIR 重定向 / 编译失败也落日志）
- `.planning/phases/04-media-library/evidence/rotation-wiring.log`（T3）- 装配链读数 + informational 行，10 行

## Decisions Made

- **装载分派替换而非追加**（Deviation 2 详述）：04-04 已在 `rescanAndApply` 里直接 `rotation.setItems` + `rotation.start()`；`router.start(with:)` 内部已做这两步，追加会双重驱动轮换器 —— 按计划 must_hives 的真值（「`MediaCoordinator.apply` 判 `.playing` → 同一轮里 `router.start(with: report.items)`」）换成单一路径
- **`PIC_ROT_MODE` 打在 rescanAndApply 的既有同步之后**：那里是模式/间隔的唯一真相源（04-04 建），装配处不再同步第二遍
- **`file_missing` 守卫按计划给的选项移除**：存在性由 `MediaLibrary.scan` 的 `folderMissing` + 探针负责；`firstVideoURL` 保留不删（不为此消警告动别处）
- **启动时 items[0] 装载两次是计划明文的双路径**（rescanAndApply `.playing` 分派 + startWallpaper 起播段）：同 URL 幂等装载，第二次 `scan` 走缓存不重复 I/O（T-04-25 缓解），终态一致
- **反代码膨胀红线落实**：`dispatchPlayback` 是唯一的辅助（8 行、4 个调用点共用，短于内联）；适配器方法体 2 行；无计划外的防御分支 / 闭包包装 / 间接层

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - 计划 grep 缺陷] T2 的 AppDelegate `NSOpenPanel == 0` 被冻结类名污染**
- **Found during:** Task 2 verify 首跑
- **Issue:** `grep -c 'NSOpenPanel'` 是子串匹配，04-04 冻结的类名 `NSOpenPanelFolderPicker`（picker 持有者声明行）自带该子串 —— 判据按字面恒为 1，不可满足；唯一命中正是判据要保护的 seam 句柄（04-04 Deviation 3 同款，上游契约已预告）
- **Fix:** 按意图改测：剥注释后排除 `NSOpenPanelFolderPicker` 类名的 NSOpenPanel 计数 == 0（实测 0）—— AppDelegate 内零直接面板使用，意图收紧而非放宽
- **Files modified:** 无入库文件（仅 verify 脚本，/tmp）
- **Verification:** panel_excl_seam=0；行号定位确认唯一命中即 seam 句柄声明行
- **Committed in:** 不适用
- **⚠️ 给 04-06 的移交**：常驻判据须用「排除 seam 类名」或「构造调用 `NSOpenPanel(` 计数」形态（与 04-04 Deviation 2/3 的移交一致）

**2. [Rule 1 - 计划与现实不符] rescanAndApply 的装载分派是「替换」不是「追加」**
- **Found during:** Task 2 实现前核算
- **Issue:** 计划 T2 ③ 说在「扫描 → coordinator.apply」之后**追加**分派，但 04-04 建的 rescanAndApply 里已有 `rotation.setItems(report.items)` + `rotation.start()` —— `router.start(with:)` 内部已包含这两步，两者并存会双重驱动轮换器（start 两次、定时器重排两次）
- **Fix:** 按计划自己的 must_hives 真值（「`MediaCoordinator.apply` 判 `.playing` → 同一轮里 `router.start(with: report.items)`」）把直接调用替换为 `dispatchPlayback(for:items:)` 的状态分派 —— 单一驱动路径
- **Files modified:** Sources/PicApp/AppDelegate.swift
- **Verification:** 用例全绿；结构判据 rotrun=2 rotstop=1；轮换器只经 router 一个入口被驱动
- **Committed in:** 13c29e7

**3. [Rule 1 - 判据环境适配] T2 全量测试的 `Executed N tests, with 0 failures` grep 恒空**
- **Issue:** 全量输出实打 `Executed 113 tests, with 1 test skipped and 0 failures`（skip 是 04-03 既有的 XCTSkip）—— 计划的 grep 形态匹配不到（04-04 Deviation 7 同款）
- **Fix:** 以 ALLTESTS_RC=0 + skipped 形态的汇总行作判读
- **Files modified:** 无入库文件（仅 verify 脚本，/tmp）
- **Verification:** ALLTESTS_RC=0，Executed 113 tests, with 1 test skipped and 0 failures
- **Committed in:** 不适用

**4. [Rule 3 - Blocking] 三个 `<automated>` 块硬编码主检出路径**
- **Issue:** 均以 `cd /Users/coderstory/dev/pic` 开头，在本 worktree 执行会校验**主检出**的代码（worktree-path-safety #4767 要防的缺陷；04-02/04-04 同款）
- **Fix:** 全部落成 /tmp 脚本并以本 worktree root 重定根，命令体逐字不变（T1 红日志判别见 Deviation 6 的既有形态适配）
- **Verification:** 三个 verify 各自打出 OK 行（PLAYBACK_ROUTER_OK / APPDELEGATE_ROTATION_WIRING_OK / ROTATION_WIRING_EVIDENCE_OK）
- **Committed in:** 不适用

**5. [Rule 3 - Blocking] T3 的 SRC 清单漏列 `State/SettingsStore.swift`**
- **Found during:** Task 3 编译前核算依赖
- **Issue:** `RotationController` 依赖 `PlayMode`（定义在 `State/SettingsStore.swift`），计划列的 5 个源文件编译必红 —— fails_when ① 预判了这条（「SRC 清单漏了某个源文件……改脚本不加产品代码」，probe-lock.sh 头注记过同款真事故）
- **Fix:** SRC 追加 `Sources/PicCore/State/SettingsStore.swift`（其依赖仅 Foundation/Observation，可独立编入）
- **Files modified:** scripts/probe-rotation-wiring.sh（SRC 清单一行 + 头注说明）
- **Verification:** 编译退出 0，PROBE_DRIVER_RC=0，8 行读数齐全
- **Committed in:** 7f5755b

**6. [Rule 1 - 判据环境适配] T1 变异红日志的 `grep -c 'error:'` == 0 门在本机 XCTest 输出下不可满足**
- **Issue:** 本机 XCTest 断言失败行自带 `error: -[` 前缀，断言型红光的裸 `error:` 计数恒 ≥ 1（04-01 Deviation 4 / 04-02 Deviation 6 已确立的形态；T1 并行执行者同款处理，本执行者复跑 T1 verify 时沿用）
- **Fix:** 编译错误判别用编译器诊断独有形态（`:line:col: error:` / `error: SwiftCompile`）—— D-16 意图（红来自断言而非编译失败）完整保留
- **Verification:** RED_ASSERT=7 RED_COMPILE=0；MUTATED_RC=1 且失败列表含 testStartLoadsFirstItemForLoopSingle
- **Committed in:** 不适用（仅 verify 脚本，/tmp）

**7. [Rule 3 - 执行环境] 外层 `perl -e 'alarm 300; exec @ARGV' bash …` 包装被本会话沙箱拒绝**
- **Issue:** 验收判据的外层 perl-alarm 包装形态无法在本会话直接执行（shell 沙箱拒绝 exec 包装）
- **Fix:** 直接 `bash scripts/probe-rotation-wiring.sh` —— 脚本内部每条命令本就套 perl alarm（编译 180s / 运行 60s），工具级 timeout 作总时长兜底，覆盖等价
- **Verification:** PROBE_RC=0（两次：重定向 + 入库），证据齐全
- **Committed in:** 不适用

---

**Total deviations:** 7 auto-fixed（3 处 Rule 1 计划判据/现实缺陷 + 2 处 Rule 1 判据环境适配 + 2 处 Rule 3 执行环境/清单适配）
**Impact on plan:** 全部为让判据**本身**可达成而修，无一放宽读数、无一改产物值凑判据。唯一的产品侧取舍是 Deviation 2（替换而非追加，消除双重驱动）—— 方向与计划的 must_hives 真值一致。

## Issues Encountered

None —— 无编译错误、无挂起、无环境故障；T1 变异复跑后 `cmp -s` 逐字节一致、worktree 干净。

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- 04-06（test.sh 统一校验）的移交：① NSOpenPanel 判据用「排除 seam 类名 / 构造调用计数」形态（本 plan Deviation 1 + 04-04 Deviation 2/3）；② 全量 `Executed` grep 用 skipped 形态或只看 RC（Deviation 3）；③ `PIC_ROT_*` 四行各恰 1 处、B1 行号序（324 < 325）可作常驻判据；④ probe-rotation-wiring.sh 已支持 `PIC_EVIDENCE_DIR`，test.sh 段照 probe-lock 的接法即可
- Phase 5（设置窗）：模式/间隔改动写 `store` 后调 `rotation.setMode` / `setInterval` 即当场生效（04-02 已锁）；换目录走既有 `rescanAndApply` 单一路径 —— 装载分派已接好，无需再动 AppDelegate
- Phase 7（长跑）：应用级启动路径的活体采集（SC4 的 GUI 真启动）已登记 —— evidence 的 `PIC_ROT_APP_LAUNCH informational=1` 行不进任何门禁，届时补
- `bash test.sh` 本 plan 未跑（wave 纪律，统一校验在 04-06）；受影响的既有判据（B1 / persist / activation / 菜单零直连）已实测未破

---
*Phase: 04-media-library*
*Completed: 2026-10-03*
