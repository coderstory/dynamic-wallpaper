---
phase: 04-media-library
plan: 07
subsystem: testing
tags: [swift, avfoundation, avqueueplayer, avplayerlooper, rotation, gap-closure]

requires:
  - phase: 04-media-library
    provides: "RotationController（04-02）、PlayerController 装配 + load/stop 语义（04-05）、UAT 缺口清单"
provides:
  - "RotationController.advance(reason:) 的 loopSingle 按 reason 分流（G-04-3）"
  - "PlayerController.load(url:) 改为先插后扫的单落点交接，消除空队列帧（G-04-3b）"
  - "PlayerControllerSwapTests：load 返回时队列立即非空的不变量"
  - "RotationControllerTests 7 → 9 条：用例 1/7 换驱动、新增用例 8/9 锁两种 reason 语义"

actuals:
  tokens: 1494
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "轮换锁定只约束 rotationElapsed 一路，userRequested 按 reason 分流（reason 是唯一区分量）"
    - "队列交接先插后扫：insert(item, after: nil) 后 filter { $0 !== item } 扫掉全部旧条目"

key-files:
  created:
    - Tests/PicCoreTests/PlayerControllerSwapTests.swift
  modified:
    - Sources/PicCore/Playback/PlayerController.swift
    - Sources/PicCore/Playback/RotationController.swift
    - Tests/PicCoreTests/RotationControllerTests.swift

key-decisions:
  - "loopSingle 的「永远停在同一条」保留在 rotationElapsed 上，不删 —— PLAY-03 是轮换模式语义，用户显式意图只是覆盖它而不是取消它"
  - "load 的交接形状定为 insert + 全量扫旧两行，因为 after: nil 是追加到队尾（AVPlayer.h:940）；只插不扫会让旧片继续播且队列无界增长"
  - "用例 1/7 改驱动不改断言 —— [0,0,0,0,0] 与 [1,0,1,2] 的字面断言逐字保留，由新增的用例 8 承接 userRequested 语义"

requirements-completed: [PLAY-03, PLAY-06, MENUBAR-04]

coverage:
  - id: D1
    description: "单循环模式下点菜单「立即下一个」当场换到列表的下一条（userRequested 按列表前进），轮换到点仍锁定同一条"
    requirement: MENUBAR-04
    verification:
      - kind: unit
        ref: "Tests/PicCoreTests/RotationControllerTests.swift#testUserRequestedAdvancesInLoopSingle"
        status: pass
      - kind: unit
        ref: "Tests/PicCoreTests/RotationControllerTests.swift#testRotationElapsedHoldsLoopSingleLocked"
        status: pass
    human_judgment: false
  - id: D2
    description: "换片不出现空队列帧：load 返回时队列已非空、currentItem 是新条目、items() 无旧条目残留"
    requirement: PLAY-06
    verification:
      - kind: unit
        ref: "Tests/PicCoreTests/PlayerControllerSwapTests.swift#testLoadLeavesQueueNonEmptyImmediately"
        status: pass
      - kind: unit
        ref: "Tests/PicCoreTests/PlayerControllerFreezeTests.swift#testStopEmptiesQueueAndIsIdempotent"
        status: pass
    human_judgment: false
  - id: D3
    description: "轮换器仍与播放进度彻底解耦 + PlayerController 的 D-01 八个签名逐字未改 + stop() 降级语义未动"
    requirement: PLAY-06
    verification:
      - kind: unit
        ref: "Tests/PicCoreTests/PlayerControllerFreezeTests.swift (空 conformance 编译期判据)"
        status: pass
    human_judgment: false
  - id: D4
    description: "用户肉眼确认：菜单点击端到端换片、切换过程不闪屏（04-UAT SC3 复测）"
    verification: []
    human_judgment: true
    rationale: "闪屏与「点了没反应」是用户可见的主观表现 —— 队列非空与 reason 分流只证明结构上消除了成因，无法替代用户对画面平滑度与响应感的实际复测"

# Metrics
duration: 12min
completed: 2026-10-03
status: complete
---

# Phase 04 Plan 07: Gap 修复（G-04-3 点了不切 + G-04-3b 切换闪屏）Summary

**单循环下菜单「立即下一个」按 reason 分流当场换片，换片队列交接改为先插后扫、全程无空帧**

## Performance

- **Duration:** 12 min
- **Started:** 2026-10-03T15:33:00Z
- **Completed:** 2026-10-03T15:45:00Z
- **Tasks:** 3
- **Files modified:** 4

## Accomplishments

- **G-04-3 关闭**：`advance(reason:)` 的 `.loopSingle` 支按 reason 二分 —— `.userRequested` 走 `(currentIndex + 1) % items.count`（用户意图优先），`.rotationElapsed` 保持 `nextIndex = 0`（PLAY-03 轮换锁定不动）。`loopList` / `shuffle` 两支、空列表 guard、打点、`onAdvance`、重排程全部零改动。
- **G-04-3b 关闭**：`load(url:)` 的 `removeAllItems()` 一行换成两行 —— 新条目先 `player.insert(item, after: nil)` 入队，再 `player.items().filter { $0 !== item }.forEach { player.remove($0) }` 扫掉全部旧条目。队列在交接全程非空，交接完成后只剩新条目。
- **判据有牙齿**：`RotationControllerTests` 7 → 9 条（用例 1/7 换驱动 reason、断言字面 `[0,0,0,0,0]` 与 `[1,0,1,2]` 逐字保留；新增用例 8/9 分别锁 userRequested 前进与 rotationElapsed 锁定）；新增 `PlayerControllerSwapTests` 锁「load 返回时队列立即非空 + currentItem 是新条目 + 无旧条目残留」。两处变异各自转红，红光均来自 `XCTAssert` 而非编译失败。
- **冻结面守住**：`PlayerController` 的 D-01 八个签名逐字未改（`PlayerControllerFreezeTests` 的空 conformance 编译通过）、`stop()` 三步未动、D-12/D-13 的两行 item 属性保留、`RotationController` 零播放器引用。

## Task Commits

Each task was committed atomically:

1. **Task 1: PlayerController.load 单落点交接（先插后扫）** - `7f2454f` (fix)
2. **Task 2: RotationController.advance(reason:) 按 reason 分流** - `84b1ee8` (fix)
3. **Task 3: 用例按 reason 分流 + 两条新用例 + 队列不变量新文件 + 两处变异反向验证** - `3a3460b` (test)

**Plan metadata:** 本 SUMMARY 的 commit

## Files Created/Modified

- `Sources/PicCore/Playback/PlayerController.swift` — `load(url:)` 改单落点交接（先插后扫），消除空队列帧；`stop()` 与八个公开签名未动
- `Sources/PicCore/Playback/RotationController.swift` — `advance(reason:)` 的 `.loopSingle` 支按 reason 分流，一个 if/else
- `Tests/PicCoreTests/RotationControllerTests.swift` — 用例 1/7 改由轮换路径驱动（断言字面保留）；新增用例 8/9
- `Tests/PicCoreTests/PlayerControllerSwapTests.swift`（新建） — 1 条：`testLoadLeavesQueueNonEmptyImmediately`

## Decisions Made

- **不删用例 1 的 `[0,0,0,0,0]` 断言**：这条断言的**意图**（单循环在轮换路径下锁死）是 04-02 冻结的行为，删掉就没人能复核 PLAY-03 没被顺手改掉。做法是换驱动 reason（`scheduler.fire()` 而非 `advanceNow()`），由新增的用例 8 承接 userRequested 语义，两条成对锁死「reason 是唯一区分量」。
- **`load` 用 insert + 全量扫旧，不用 `replaceCurrentItem(with:)`**：后者只换当前项、不清当前项之后的旧条目，`items()` 会留残留；且队列会有非新条目但 currentItem 换新的不一致中间态。
- **用例 9 的 `scheduleCount == 4`**：start 排 1 次 + 每次切完重排 3 次 —— 把「切完立刻重排下一程」这条 PLAY-06 行为一并钉住，代价只是一条已有属性的断言。

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] 干净 worktree 上 `fixtures/` 缺席，变异 2 的红光无法成立**
- **Found during:** Task 3（`PlayerControllerSwapTests` 与变异 2）
- **Issue:** `fixtures/` 是 gitignored（`.gitignore` 第 6 行），worktree 里不存在 → `PlayerControllerSwapTests` 抛 `XCTSkip` → 变异 2 回退成 `removeAllItems()` 后用例**跳过而非失败**，`SW_GREEN` 仍为 0，`SWAP_TEST_IS_BLIND_OR_MUTATION_COMPILED` 必然触发。同一形态已在 04-03 / 04-04 Deviation 7 / 04-05 Deviation 3 / 04-06 各确立一次。
- **Fix:** 从主检出 `/Users/coderstory/dev/pic/fixtures/` **拷贝** `clip-a.mp4` / `clip-b.mp4` 进本 worktree 的 `fixtures/`（零 ffmpeg、纯文件拷贝，非 `scripts/make-fixtures.sh` 的转码路径 —— 遵守铁律 1）。
- **Files modified:** 无入库文件（`fixtures/` gitignored）
- **Verification:** `PlayerControllerSwapTests` 实跑 `Executed 1 test, with 0 failures`（真跑、非 skip）；变异 2 转红 `MUT2_RC=1 / MUT2_FAILHIT=4 / RED2_ASSERT=2 / RED2_COMPILE=0`
- **Committed in:** 无（不入库文件）

**2. [Rule 3 - Blocking] 判据脚本的 `cd` 需重锚本 worktree**
- **Found during:** Task 1（首个 verify 脚本）
- **Issue:** plan 三条 `<verify><automated>` 都以 `cd /Users/coderstory/dev/pic &&` 开头；本 executor 被隔离在 `agent-a731869d23b065988` worktree，直接 `cd` 到主检出会在别人的检出上跑测试/改文件。且 worktree 隔离沙箱拒长复合命令。
- **Fix:** 三条判据原样照抄，只把首行 `cd` 换成本 worktree 的绝对路径，其余逐字不变（计数口径、判据阈值、`cmp -s` 恢复校验全部未动）。
- **Files modified:** 无入库文件（判据脚本写在 scratchpad）
- **Verification:** 三条判据分别打出 `PC_LOAD_SINGLE_HANDOFF_OK` / `ROTATION_REASON_AWARE_OK` / `GAP_FIX_TEST_SUITE_OK`
- **Committed in:** 无（不入库文件）

---

**Total deviations:** 2 auto-fixed（2 × Rule 3 blocking）
**Impact on plan:** 两项都是执行环境适配（worktree 隔离 + gitignored fixture），判据本身零改动，未产生任何范围外代码改动。

## Issues Encountered

- **T1 的注释纪律冲突**：原 `load` 的文档注释整段描述「先停 looper，再清队列，最后入队新 item」的旧顺序，改了代码不改注释会留下误导性文档。改为重写为 2 行说明「先插后扫 + 为什么不能清空」，遵守铁律 4（只写不变量/反直觉陷阱，不写任务编号与代码复述）。
- **`RC_EXECUTED9=3` 而非 1**：`--filter` 的输出里 `Executed 9 tests, with 0 failures` 出现 3 次（suite 行 + class 行 + all 行）。判据用的是 `grep -cE ... -ge 1`，非 `== 1`，本就兼容。

## Verification

| 项 | 结果 |
|---|---|
| `swift build --package-path .` | RC=0 |
| `swift test --filter RotationControllerTests` | `Executed 9 tests, with 0 failures`，九个用例名各命中 |
| `swift test --filter PlayerControllerSwapTests` | `Executed 1 test, with 0 failures`（实跑，非 skip） |
| `swift test --filter PlayerControllerFreezeTests` | `Executed 1 test, with 0 failures` |
| `swift test`（全量） | **176 tests, with 0 failures**（173 基线 + 3 新增） |
| `PlayerController` `load` 函数体（剥注释/按函数体） | `removeAllItems`=0、`replaceCurrentItem`=0、`player.insert(`=1、`player.remove(`=1、buffer/spectral/`AVPlayerLooper(` 各=1 |
| `PlayerController` `stop()` 函数体（剥注释） | `disableLooping()`=1、`looper = nil`=1、`removeAllItems`=1 |
| `RotationController`（剥注释） | `nextIndex = 0`=1、`reason == .userRequested`=1、`% items.count`=2；`AVFoundation`/`AppKit`/`AVPlayer`/`currentTime`/`arbiterCurrentPosition`/`AVPlayerItemDidPlayToEndTime` 全=0 |
| 变异 1（`MUT-P4-USERREQ`） | RC=1，命中 `testUserRequestedAdvancesInLoopSingle`，`XCTAssert`≥1，编译器诊断形态=0 |
| 变异 2（`MUT-P4-LOADSWAP`） | RC=1，命中 `testLoadLeavesQueueNonEmptyImmediately`，`XCTAssert`≥1，编译器诊断形态=0，残留 `player.insert(`/`player.remove(`=0 |
| 两次变异恢复 | `cmp -s` 逐字节一致；树内无 `MUT-P4` 残留 |

⚠️ 按 plan `<verification>` 末条，本 plan **不跑**全量 `bash test.sh`（04-06 / 验证环节职责），**零 ffmpeg**。

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- **两个 gap 在结构上已关闭**，但 **G-04-3b 的主观面（画面是否真的不闪）仍需用户在 04-UAT SC3 复测时肉眼确认** —— 判据证明的是「队列全程非空，无 currentItem 空帧」，不是「观感平滑」。
- **回归风险已登记**：PLAY-03 的轮换锁定语义现在与 MENUBAR-04 的用户意图共用一条 `advance` 路径。将来任何改动 `loopSingle` 分支的 plan 都必须同时保住用例 1/9（锁定）与用例 8（前进）三条，否则会静默回归。
- Phase 04 剩余 gap 状态需由 orchestrator 在 STATE.md / ROADMAP.md 统一收口（本 executor 按指令未更新）。

---
*Phase: 04-media-library*
*Completed: 2026-10-03*
