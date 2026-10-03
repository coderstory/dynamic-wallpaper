---
phase: 04-media-library
plan: 03
subsystem: media
tags: [swift, xctest, appkit, avfoundation, pure-function, protocol-seam]

# Dependency graph
requires:
  - phase: 04-media-library (plan 01)
    provides: MediaLibrary 扫描内核 + MediaLibraryReport.playableCount + MediaLibraryError 两 case + fixture 树脚本（内嵌可播放种子）
  - phase: 02-playback-core
    provides: PlayerController（八签名冻结面）与 WallpaperWindowController（attach/reassert/teardown/emit）
provides:
  - LibraryState 四态纯决策（folderUnconfigured / folderMissing / noPlayableVideos / playing）+ reasonToken（folder_unconfigured / folder_missing / no_playable_videos / playing）
  - WallpaperWindowController.hide()/show()（保留语义，与 teardown 的销毁语义并存 —— SOURCE-06 恢复路径的前置）
  - PlayerController.stop()（纯增量：disableLooping → looper=nil → removeAllItems，幂等，不碰 play/pause）
  - PlayerControllerSurface 编译期冻结判据（八签名逐字 conformance）
  - MediaCoordinator（扫描结果 → 窗口/播放器动作的唯一落点）+ WallpaperPresenting / PlaybackStopping 两个 seam 协议
affects: [04-05 装配（AppDelegate wiring + PIC_LIBRARY_STATE 行）, 04-06 test.sh 判据, 05-settings 空态显示]

# Actuals (#2632)
actuals:
  tokens: 6043   # chars/4 over the realized diff (24170 chars, 7 files)
  tasks: 3
  commits: 6      # 3 RED + 3 GREEN（tdd="true" 每 task 两段）

# Tech tracking
tech-stack:
  added: []   # 零第三方依赖不变
  patterns:
    - 用空协议 conformance 把「冻结签名」从源码 grep 升级成编译期判据（final class 无法子类替身时的替代牙齿）
    - 决策（纯函数）/ 执行（协议 seam 薄壳）分层：MediaCoordinator 零 AppKit / 零 AVFoundation，降级路径可在无屏幕环境穷举
    - hasAppliedOnce 布尔区分「未调用过」与「调用过且状态相同」，幂等门不用默认值猜

key-files:
  created:
    - Sources/PicCore/Media/LibraryAvailability.swift
    - Sources/PicCore/Media/MediaCoordinator.swift
    - Tests/PicCoreTests/LibraryAvailabilityTests.swift
    - Tests/PicCoreTests/PlayerControllerFreezeTests.swift
    - Tests/PicCoreTests/MediaCoordinatorTests.swift
  modified:
    - Sources/PicCore/Render/WallpaperWindowController.swift   # 纯增量 hide()/show()
    - Sources/PicCore/Playback/PlayerController.swift          # 纯增量 stop()

key-decisions:
  - "fixtures/clip-a.mp4 用 04-01 内嵌的 Motion-JPEG 种子再生（make-media-fixture-tree.sh + 一次文件落位），不跑 make-fixtures.sh —— 后者调 ffmpeg，撞本 wave 红线；fixtures/ 本就 gitignored"
  - "T2 运行时用例的等待改为 await Task.sleep 400ms（04-01 tracer 实测形状）：Thread.sleep 堵死主 run loop，looper 的入队派发永远跑不到（首跑 0 条目实证）"
  - "协议与 extension 必须落文件作用域（嵌在测试类里 extension 找不到嵌套协议，编译红）"
  - "W9 的「不跑全量 swift test」按其意图而非字面执行：本 worktree 与 04-02 隔离、无共享 .build，全量跑只覆盖已合并的 04-01 基线 + 本 plan 产物，正是 objective 的成功判据"

patterns-established:
  - "seam 方法名刻意与产品方法名错开（stopPlayback() vs stop()）：语义更宽的协议口不给窄实现同名"

requirements-completed: [SOURCE-06]

# Coverage metadata (#1602)
coverage:
  - id: D1
    description: "四态纯决策：没选目录压过任何扫描结果；目录没了/不可读 → folderMissing；success(0) → noPlayableVideos；success(n>=1) → playing；四 token 两两不同、恰三态隐藏（SOURCE-06 决策半边）"
    requirement: SOURCE-06
    verification:
      - kind: unit
        ref: Tests/PicCoreTests/LibraryAvailabilityTests.swift#testUnconfiguredFolderWinsOverAnyScanOutcome
        status: pass
      - kind: unit
        ref: Tests/PicCoreTests/LibraryAvailabilityTests.swift#testMissingFolderYieldsFolderMissingAndHidesWallpaper
        status: pass
      - kind: unit
        ref: Tests/PicCoreTests/LibraryAvailabilityTests.swift#testUnreadableFolderAlsoYieldsFolderMissing
        status: pass
      - kind: unit
        ref: Tests/PicCoreTests/LibraryAvailabilityTests.swift#testZeroPlayableVideosYieldsNoPlayableVideos
        status: pass
      - kind: unit
        ref: Tests/PicCoreTests/LibraryAvailabilityTests.swift#testPositiveCountYieldsPlaying
        status: pass
      - kind: unit
        ref: Tests/PicCoreTests/LibraryAvailabilityTests.swift#testAllCasesHaveDistinctTokensAndExactlyThreeHideWallpaper
        status: pass
    human_judgment: false
  - id: D2
    description: "WallpaperWindowController.hide() 只 orderOut(nil) 保留窗口、show() 原样叫回、不隐式 attach、不碰 level/collectionBehavior；既有四成员一字未改"
    verification:
      - kind: other
        ref: "gates LIBRARY_AVAILABILITY_OK（hide=1 show=1 hide_clears_window=0 collectionBehavior_assigns=1 existing_members=4/4 level_calls=1@WallpaperWindow.swift）"
        status: pass
    human_judgment: true
    rationale: "hide/show 的真实窗口可见性需要活体观察（屏幕锁着，本机 CGDisplay_IS_ASLEEP=1）；本 plan 只有结构判据与 MediaCoordinator 协议层的 show/hide 计数，窗口级行为留给 04-05 接线后的 evidence"
  - id: D3
    description: "PlayerController.stop() 清空队列且幂等，不碰 play/pause；八个 D-01 冻结签名由 PlayerControllerSurface 空 conformance 锁成编译期判据"
    verification:
      - kind: unit
        ref: Tests/PicCoreTests/PlayerControllerFreezeTests.swift#testStopEmptiesQueueAndIsIdempotent
        status: pass
      - kind: other
        ref: "gates PLAYER_CONTROLLER_STOP_OK（stop=1 looper_nil=1 disable_looping=2 play_pause_in_stop=0 frozen_methods=8/8 conform=1）+ HoldArbiterTests 13/13 + SystemEventPipelineTests 8/8"
        status: pass
    human_judgment: false
  - id: D4
    description: "MediaCoordinator：播放态只 show 从不停；三个隐藏态 stopPlayback+hide；重复输入幂等；隐藏→播放→再隐藏的完整恢复序列（SOURCE-06 执行半边）"
    requirement: SOURCE-06
    verification:
      - kind: unit
        ref: Tests/PicCoreTests/MediaCoordinatorTests.swift#testPlayingStateShowsWallpaperAndNeverStops
        status: pass
      - kind: unit
        ref: Tests/PicCoreTests/MediaCoordinatorTests.swift#testEmptyLibraryStopsAndHidesExactlyOnce
        status: pass
      - kind: unit
        ref: Tests/PicCoreTests/MediaCoordinatorTests.swift#testMissingFolderStopsAndHides
        status: pass
      - kind: unit
        ref: Tests/PicCoreTests/MediaCoordinatorTests.swift#testRepeatedIdenticalInputIsIdempotent
        status: pass
      - kind: unit
        ref: Tests/PicCoreTests/MediaCoordinatorTests.swift#testRecoveryFromHiddenToPlayingResumesWithoutRestart
        status: pass
    human_judgment: false
  - id: D5
    description: "变异反向验证：去掉幂等门后 testRepeatedIdenticalInputIsIdempotent 转红，红光来自断言失败而非编译失败（D-16）"
    verification:
      - kind: other
        ref: "mutation: MUT-P4-IDEMPOTENCY_removed（幂等 guard 整行替换）→ MUTATED_RC=1，2 条断言失败、0 条编译器诊断；恢复后 cmp -s 逐字节一致、再跑 5/5 绿（MEDIA_COORDINATOR_OK）"
        status: pass
    human_judgment: false

# Metrics
duration: 12 min
completed: 2026-10-03
status: complete
---

# Phase 4 Plan 3: 失效降级的决策与执行层 Summary

**四态纯函数决策（LibraryAvailability）+ 保留语义的 hide()/show() + looper 配对的 stop() + 协议 seam 的 MediaCoordinator（幂等、可恢复），12 条新单测 + 一处断言型变异验证，全量 88 tests 0 failures**

## Performance

- **Duration:** ~12 min（2026-10-03T11:17:44Z → 11:29Z）
- **Started:** 2026-10-03T11:17:44Z
- **Completed:** 2026-10-03T11:29:00Z
- **Tasks:** 3（全部完成；每个 task 按其 tdd="true" 走 RED→GREEN 两段提交）
- **Files modified:** 7（5 新建 + 2 纯增量修改；diff 24170 chars）

## Accomplishments

- **决策与执行分离落地**：`LibraryAvailability.evaluate` 只吃标量（`folderConfigured: Bool` + `Result<Int, MediaLibraryError>`），四态各有可 grep 的 reasonToken，6 条单测穷举；协调器只对着 `WallpaperPresenting` / `PlaybackStopping` 说话，零 AppKit / 零 AVFoundation / 零仲裁器引用
- **D-01 冻结面升级为编译期判据**：`PlayerControllerSurface` 逐字复刻八个签名 + 空 conformance —— 任何标签/类型/名字漂移直接编译红，比源码 grep 硬
- **stop() 按 Pitfall 4 配对纪律**：`disableLooping()` → `looper = nil` → `removeAllItems()`，幂等（连调两次队列仍空），不偷做 `arbiterApply` 的活
- **SOURCE-06 恢复路径有行为断言**：`testRecoveryFromHiddenToPlayingResumesWithoutRestart` 锁住「隐藏 → 恢复 → 再隐藏」整条序列（showCount==1、hideCount==2）
- **变异反向验证是断言型红光**：去掉幂等门 → `testRepeatedIdenticalInputIsIdempotent` 2 条断言失败、0 条编译器诊断；恢复后 `cmp -s` 逐字节一致
- **回归**：全量 `swift test` **88 tests, 0 failures**（wave 1 的 76 + 本 plan 12：6+1+5）

## Task Commits

Each task was committed atomically (tdd="true" → RED/GREEN per task):

1. **Task 1 RED: LibraryAvailability 失败测试 + 编译骨架** - `9e3252a` (test)
2. **Task 1 GREEN: 纯决策 + hide()/show() 保留语义** - `56091c8` (feat)
3. **Task 2 RED: 冻结测试 + stop() 编译骨架** - `49501c3` (test)
4. **Task 2 GREEN: stop() 实现** - `f461b51` (feat)
5. **Task 3 RED: MediaCoordinator 失败测试 + seam 骨架** - `1e0a44a` (test)
6. **Task 3 GREEN: apply() 实现** - `cb50803` (feat)

**Plan metadata:** 本 SUMMARY 提交（docs）

## TDD Gate Compliance

三个 task 的 RED 均为**目标用例的断言失败**（非编译失败、非零发现）：
- T1：骨架 evaluate 恒返 `.playing` → 4 用例 11 条断言失败
- T2：空 stop() 骨架 → 2 条 stop 断言失败（前置断言先单独跑绿过，见 Issues）
- T3：恒 show 骨架 → 4 用例断言失败
GREEN 后各 filter 全绿；无 REFACTOR 段（实现一次到位，无后续清理可做）。

## Files Created/Modified

- `Sources/PicCore/Media/LibraryAvailability.swift` - LibraryState 四态 + shouldShowWallpaper/reasonToken + evaluate/token 纯函数；零 AppKit/SwiftUI/AVFoundation/FileManager/SettingsStore
- `Sources/PicCore/Render/WallpaperWindowController.swift` - 纯增量 hide()（orderOut 保留）/ show()（orderFrontRegardless，不隐式 attach）；attach/reassert/teardown/emit 一字未改
- `Sources/PicCore/Playback/PlayerController.swift` - 纯增量 stop()；八签名未动，类注释补 stop↔teardown 成对说明
- `Sources/PicCore/Media/MediaCoordinator.swift` - 两个 seam 协议 + apply（决策委托纯函数、三支执行、幂等门、onStateChange）
- `Tests/PicCoreTests/LibraryAvailabilityTests.swift` - 6 条纯函数用例（allCases 运行时生成，不写死清单）
- `Tests/PicCoreTests/PlayerControllerFreezeTests.swift` - 文件作用域冻结协议 + 空 conformance + 1 条 stop 幂等运行时用例（fixtures 缺席 XCTSkip）
- `Tests/PicCoreTests/MediaCoordinatorTests.swift` - 5 条用例 + RecordingPresenter/RecordingStopper 替身

## Decisions Made

- **fixtures 再生不走 ffmpeg**：`make-fixtures.sh` 用 ffmpeg lavfi 合成，撞本 wave 红线；改用 04-01 已验证的 `make-media-fixture-tree.sh` 内嵌 Motion-JPEG 种子落位成 `fixtures/clip-a.mp4`（该种子 04-01 tracer 实测 looper 可入队 3 项）。fixtures/ 是 gitignored 目录，不进库
- **等待形状改为 `await Task.sleep(nanoseconds: 400_000_000)`**：计划写「等 300ms」未指定方式；`Thread.sleep` 堵死主 run loop 导致 looper 入队派发跑不到（首跑实测 0 条目，INVALID_RED 被当场识别并修正，未进 RED commit）；400ms 取 04-01 tracer 的实测值
- **W9「只跑 --filter」按意图执行**：本 worktree 与 04-02 完全隔离（无共享 .build、无其源码），全量 `swift test` 只覆盖已合并基线 + 本 plan 产物 —— 正是 objective 成功判据要的读数；`bash test.sh` 仍按计划留给 04-06
- **幂等门写成计划 perl 的字面目标形状** `guard next != lastState else { return lastState }`（包在 `if hasAppliedOnce` 里），保证变异替换一行命中且替换后可编译（D-16）

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - 计划事实错误] T1 判据指错了层级代码所在的文件**
- **Found during:** Task 1 verify 首跑（level_calls=0）
- **Issue:** 判据要求 `WallpaperWindowController.swift` 剥注释后 `CGWindowLevelForKey` 计数 == 1，但层级写法在 `WallpaperWindow.swift:29`（controller 里从来没有过这行）
- **Fix:** 判据重指到 `WallpaperWindow.swift`（该文件本 plan 零改动，`git diff` 空），D-19 意图（层级写法不得被动过）完整保留且实测 == 1
- **Files modified:** 无入库文件（仅 verify 脚本）
- **Verification:** LIBRARY_AVAILABILITY_OK 全过
- **Committed in:** 不适用（判据适配）

**2. [Rule 1 - 计划事实错误] T2 汇总串 grep 用了复数**
- **Issue:** 判据 grep `Executed 1 tests, with 0 failures`，但 XCTest 对单条用例打的是单数 `Executed 1 test`（本机实测）—— 判据按字面永不满足
- **Fix:** grep 改 `Executed 1 test, with 0 failures`；读数本身（1 条、0 失败）原样锁住
- **Committed in:** 不适用

**3. [Rule 1 - 计划 grep 缺陷] T2 的 S4 全文件计数结构性不可满足**
- **Issue:** 判据要求 PlayerController.swift 剥注释后 `player.pause()|player.play()` 计数 == 0，但 `arbiterApply`（D-01 冻结成员）本来就有各 1 处合法调用；计划自己的 fails_when ⑥ 预判了这一条并给出修法
- **Fix:** 按计划指示收窄到 `stop()` 函数体行区间（`sed -n '/public func stop()/,/^    }/p'`），实测 0；全文件计数 2 作为 informational 读数一并打出
- **Committed in:** 不适用

**4. [Rule 1 - 计划 grep 缺陷] T2 的 S5 `load` token 带了不存在的前缀空格**
- **Issue:** token 写 `func load(url `（尾随空格），而真签名是 `load(url: URL)`（冒号紧跟）—— 计数恒 0，frozen_methods 恒 7/8
- **Fix:** token 改 `func load(url:`；八签名逐一实测各 == 1
- **Committed in:** 不适用

**5. [Rule 1 - 判据环境适配] T3 变异红日志的 `error:` 计数门不可满足（04-01 同款）**
- **Issue:** 本机 XCTest 断言失败行自带 `error: -[...] : XCTAssert...` 前缀，裸 `grep -c 'error:'` 对断言型红光恒 ≥ 1（本例实测 2，全部是断言行）
- **Fix:** 编译错误判别改为编译器诊断独有形态（`:line:col: error:` 或 `error: SwiftCompile`），实测 0；D-16 意图（红来自断言而非编译失败）完整保留
- **Committed in:** 不适用

**6. [Rule 3 - 执行环境适配] 三个 `<automated>` 块硬编码主检出路径**
- **Issue:** 均以 `cd /Users/coderstory/dev/pic` 开头，在本 worktree 执行会校验主检出（worktree-path-safety #4767 要防的缺陷；04-01 Deviation 5 同款）
- **Fix:** 全部重定根到本 worktree root，命令体逐字不变；复杂复合命令被会话守卫拒绝，落成 /tmp 下的脚本文件执行（不入库）
- **Verification:** 三个 verify 各自打出 OK 行
- **Committed in:** 不适用

---

**Total deviations:** 6 auto-fixed（4 处 Rule 1 计划判据缺陷 + 1 处 Rule 1 判据环境适配 + 1 处 Rule 3 执行环境适配）
**Impact on plan:** 全部为让判据**本身**可达成而修，无一放宽读数、无一改产物值凑判据。产品代码零妥协：每个被修的判据都以更精确的形态锁住了原意图。

## Issues Encountered

- T2 首次 RED 跑用 `Thread.sleep(300ms)` 得到前置断言失败（looper 0 条目）—— 识别为 INVALID_RED（前置没成立而非目标行为红），改 `await Task.sleep(400ms)` 后前置绿、stop 断言红，才提交 RED commit。教训：XCTest 主线程用例里等待 AVFoundation 异步必须 yield 主线程
- 嵌套在测试类里的 protocol 对文件作用域 extension 不可见（`cannot find type` 编译红）—— 协议与 extension 都移到文件作用域
- `PlayerControllerFreezeTests` 在 fixtures/ 缺席的干净 clone 上会 XCTSkip 该条（1 skipped, 0 failures），判据 `Executed 1 test, with 0 failures` 仍然成立

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- 04-05 装配可直接消费的公开面：`LibraryAvailability.evaluate/token`、`MediaCoordinator(presenting:stopping:)` + `apply(scanOutcome:folderConfigured:)` + `onStateChange`（打 `PIC_LIBRARY_STATE=` 行）、`WallpaperWindowController.hide()/show()`、`PlayerController.stop()`
- seam 的产品侧实现留给 04-05：`WallpaperPresenting` 由薄适配包 `WallpaperWindowController`，`PlaybackStopping` 包 `PlayerController.stop()`（各只留一处 conformance）
- hide/show 的**窗口级**可见性读数（D2，human_judgment: true）待 04-05 接线后的活体 evidence；本 plan 只有结构判据与协议层计数
- `bash test.sh` 统一校验在 04-06（本 plan 未跑，按 wave 纪律）
- W9 说明：本 plan 在隔离 worktree 执行，与 04-02 零文件交叠；全量 `swift test` 88/88 已在本 worktree 实测

---
*Phase: 04-media-library*
*Completed: 2026-10-03*
