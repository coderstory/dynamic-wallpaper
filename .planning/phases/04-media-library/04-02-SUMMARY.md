---
phase: 04-media-library
plan: 02
subsystem: playback
tags: [swift, swiftpm, xctest, rotation, timer, xorshift]

# Dependency graph
requires:
  - phase: 04-media-library
    provides: VideoItem（轮换器的元素类型，只用 url）与 MediaLibrary 扫描内核（04-01 交付）
provides:
  - PlayMode 三 case 纯增量（loopSingle / loopList / shuffle，rawValue 冻结）
  - RotationController 轮换内核（三模式选取 + advances 打点 + onAdvance 单向出参，类型签名里拿不到 PlayerController）
  - RotationScheduling / RandomSource 两个注入 seam + SeededRandomSource（xorshift64，可播种可复现）
  - SystemRotationScheduler（主 runloop .common 一次性定时器，schedule 先 cancel）
affects: [04-05 装配（onAdvance → PlayerController.load）, 05-settings（模式分段控件按 allCases 渲染、setInterval 当场生效）, 07 长跑（定时器累积观察点）]

# Actuals (#2632)
actuals:
  tokens: 7030   # chars/4 over the realized diff（28121 chars / 6 文件）
  tasks: 3
  commits: 3

# Tech tracking
tech-stack:
  added: []   # 零第三方依赖不变
  patterns:
    - 注入 seam 双协议不标 @MainActor，由 @MainActor 持有者负责隔离（Phase 1 #ConformanceIsolation 教训的延续）
    - 「结构上不可绕过」式解耦：init 签名里没有 player + 文件里六项播放进度词零计数 —— 不靠纪律靠类型
    - 键集合断言用「实测空 suite 差集」排除系统键，不写死前缀清单（防恒绿陷阱）

key-files:
  created:
    - Sources/PicCore/Playback/RotationController.swift
    - Sources/PicCore/Playback/SystemRotationScheduler.swift
    - Tests/PicCoreTests/PlayModeTests.swift
    - Tests/PicCoreTests/RotationControllerTests.swift
  modified:
    - Sources/PicCore/State/SettingsStore.swift
    - Tests/PicCoreTests/SettingsStoreTests.swift

key-decisions:
  - "start() 首条装载不记进 advances —— 计划用例 1/2 的期望数组（5 次→[0,0,0,0,0]、6 次→[1,2,0,1,2,0]）只有在不记首条时才可满足；advances 只记两种切换（.rotationElapsed/.userRequested）"
  - "setMode 与 mode 属性共用同一真相源（setMode 只做 mode = newMode）：计划正文说「二选一」，但冻结的符号清单与用例文本两者都用 —— 保留双入口、单一真相源，不存第二份"
  - "setInterval 在未 start() 时不排程：否则首程会被提前到 start() 之前，用例 5 的 scheduleCount == 1 读数就漂了"
  - "advance 末尾对两种 reason 一律重排程（计划原文「在 advance 末尾重新排程」）；空列表时不重排 —— 定时器自然熄火，是 04-03 降级的机器前置"
  - "PlayModeTests 用例 5 的系统键排除用全新空 suite 实测差集（本机实测 dictionaryRepresentation 返回裸键名 + ~60 系统键，带前缀过滤会得空集）"

patterns-established:
  - "变异反向验证的红日志编译错误判别用编译器诊断形态（:line:col: error: / error: SwiftCompile），XCTest 断言行是 :line: error: 单数字段不命中 —— 本机 swift 6.4 连续两个 plan 验证（04-01 / 04-02）"

requirements-completed: [PLAY-03, PLAY-04, PLAY-05, PLAY-06]

# Coverage metadata (#1602)
coverage:
  - id: D1
    description: "PlayMode 纯增量到三 case：loopSingle 的 rawValue 逐字未改且仍是 allCases 第一个，老配置 \"loopSingle\" 读回仍是 .loopSingle，未知 rawValue 仍回落 seed（D-04）"
    requirement: PLAY-03
    verification:
      - kind: unit
        ref: Tests/PicCoreTests/PlayModeTests.swift#testLoopSingleRawValueIsUnchangedAndStaysFirstCase
        status: pass
      - kind: unit
        ref: Tests/PicCoreTests/PlayModeTests.swift#testAllCasesAreExactlyThreeInDeclarationOrder
        status: pass
      - kind: unit
        ref: Tests/PicCoreTests/PlayModeTests.swift#testPersistedLoopSingleStringStillResolvesFromUserDefaults
        status: pass
      - kind: unit
        ref: Tests/PicCoreTests/PlayModeTests.swift#testUnknownPersistedRawValueFallsBackToSeed
        status: pass
      - kind: other
        ref: "mutation: MUT-P4-RAWVALUE（case loopSingle 改显式 rawValue）→ testLoopSingleRawValueIsUnchangedAndStaysFirstCase 转红，2 条断言失败、0 条编译诊断"
        status: pass
    human_judgment: false
  - id: D2
    description: "SettingsStore 的 7 个键一个未增删：persist() 写出的键集合恰好 7 个（D-03 的行为断言代理）"
    verification:
      - kind: unit
        ref: Tests/PicCoreTests/PlayModeTests.swift#testPersistWritesExactlyTheSevenKnownKeys
        status: pass
      - kind: unit
        ref: "Tests/PicCoreTests/SettingsStoreTests.swift 全 13 条（含既有 testPersistWritesBackToDefaults / testPlayModeDefaultIsLoopSingle）复跑全绿"
        status: pass
    human_judgment: false
  - id: D3
    description: "列表循环按顺序走完一圈再回第一条（PLAY-04）"
    requirement: PLAY-04
    verification:
      - kind: unit
        ref: Tests/PicCoreTests/RotationControllerTests.swift#testLoopListWalksEveryItemThenWrapsToFirst
        status: pass
      - kind: other
        ref: "mutation: MUT-P4-ROTATION（loopSingle 路改成顺序前进）→ testLoopSingleAlwaysReturnsTheSameItem 转红，6 条断言失败、0 条编译诊断"
        status: pass
    human_judgment: false
  - id: D4
    description: "列表随机一轮内每条恰好一次（TEST-03），同 seed 顺序逐字相同、不同 seed 至少一个不同，洗袋真的调用注入源（PLAY-05）"
    requirement: PLAY-05
    verification:
      - kind: unit
        ref: Tests/PicCoreTests/RotationControllerTests.swift#testShuffleVisitsEveryItemExactlyOncePerRound
        status: pass
      - kind: unit
        ref: Tests/PicCoreTests/RotationControllerTests.swift#testShuffleOrderIsIdenticalForSameSeedAndDiffersForAnotherSeed
        status: pass
      - kind: other
        ref: "mutation: MUT-P4-SHUFFLE（洗袋改成顺序轮转）→ testShuffleVisitsEveryItemExactlyOncePerRound 转红，2 条断言失败、0 条编译诊断"
        status: pass
    human_judgment: false
  - id: D5
    description: "「到点就切」与播放进度零耦合（PLAY-06 / D-10）：RotationController.swift 剥注释后六项播放依赖词全 0，ManualScheduler.fire() 即推进，全程无片长概念"
    requirement: PLAY-06
    verification:
      - kind: unit
        ref: Tests/PicCoreTests/RotationControllerTests.swift#testRotationElapsedAdvancesWithoutWaitingForPlayback
        status: pass
      - kind: other
        command: "src_count 六项门：rot_playback_deps=0/0 rot_progress_reads=0/0/0/0（import AVFoundation / import AppKit / AVPlayer / arbiterCurrentPosition / currentTime / AVPlayerItemDidPlayToEndTime），proto_sched=1 proto_rand=1 seeded=1 seed_const=1 nextint=2 sys_av=0/0 sys_invalidate=2 → ROTATION_DECOUPLING_GATES_OK"
        status: pass
    human_judgment: false
  - id: D6
    description: "空列表不打点、不回调、不崩、不排程（04-03 降级与 04-05 装配的共同前置）"
    verification:
      - kind: unit
        ref: Tests/PicCoreTests/RotationControllerTests.swift#testEmptyListAdvancesNothingAndCallsOnAdvanceZeroTimes
        status: pass
    human_judgment: false
  - id: D7
    description: "模式与轮换间隔变更当场生效，不需要重建控制器"
    verification:
      - kind: unit
        ref: Tests/PicCoreTests/RotationControllerTests.swift#testModeAndIntervalChangesTakeEffectOnNextAdvance
        status: pass
    human_judgment: false

# Metrics
duration: 11 min
completed: 2026-10-03
status: complete
---

# Phase 4 Plan 2: 轮换内核 Summary

**PlayMode 纯增量三 case（rawValue 冻结）+ RotationController 三模式轮换内核（注入式调度器 / 可播种随机源 / 类型签名里拿不到 PlayerController）+ SystemRotationScheduler 主 runloop 定时器，12 条新单测 + 两处断言型变异红光，全量 swift test 88 条全绿**

## Performance

- **Duration:** 11 min
- **Started:** 2026-10-03T11:16:51Z
- **Completed:** 2026-10-03T11:27:32Z
- **Tasks:** 3（全部完成）
- **Files modified:** 6（4 新建 + 2 修改；其中 SettingsStoreTests.swift 是偏差 1 的必要一处）

## Accomplishments

- 「到点就切 ≠ 播完才切」做成**结构上不可绕过**：`RotationController.init(scheduler:random:)` 没有 player 参数，文件剥注释后六项播放依赖词（AVFoundation / AppKit / AVPlayer / arbiterCurrentPosition / currentTime / AVPlayerItemDidPlayToEndTime）全部 0 计数 —— 不是纪律约束，是类型签名里根本拿不到
- 列表随机的判据可复现且有牙齿：seed=42 两次跑出逐字相同的 `[1,0,2,2,1,0]`，seed=43 给出 `[0,1,2]`；`CountingRandomSource.calls > 0` 从另一侧证明洗袋真的调了注入源（T-04-10）
- 两处变异反向验证均为断言失败型红光：`MUT-P4-RAWVALUE`（rawValue 改名）2 条断言失败、`MUT-P4-ROTATION`（单循环改顺序前进）6 条、`MUT-P4-SHUFFLE`（洗袋改顺序轮转）2 条，三者编译诊断均为 0；恢复后 `cmp -s` 逐字节一致
- 回归：全量 `swift test` **88 tests, 0 failures**（wave 1 的 76 + 本 plan 12），`swift build` 退出码 0

## Task Commits

Each task was committed atomically:

1. **Task 1: PlayMode 纯增量到三 case + PlayModeTests 5 条** - `1fb911d` (feat)
2. **Task 2: RotationController 轮换内核 + SystemRotationScheduler** - `1ba3f17` (feat)
3. **Task 3: RotationControllerTests 7 条 + 两处变异反向验证** - `85a37c8` (test)

**Plan metadata:** 本 SUMMARY 提交（docs）

## Files Created/Modified

- `Sources/PicCore/State/SettingsStore.swift` - `PlayMode` 追加 `loopList` / `shuffle` 两行（纯增量；Key 的 7 键、Seed 默认值、persist() 全部未动）
- `Sources/PicCore/Playback/RotationController.swift` - `RotationScheduling` + `RandomSource` 协议、`SeededRandomSource`（xorshift64 + 播种散列 `0x9E3779B97F4A7C15 | 1`）、`@MainActor RotationController`（三路选取 / advances 打点 / onAdvance 单向出参）；零 AVFoundation、零 AppKit、零播放进度读取
- `Sources/PicCore/Playback/SystemRotationScheduler.swift` - 主 runloop `.common` 一次性定时器；`schedule` 先 `cancel()`，`cancel()` 走 `invalidate()`，`deinit` 兜底（Phase 7 泄漏观察点）
- `Tests/PicCoreTests/PlayModeTests.swift` - 5 条：rawValue 冻结 + allCases 顺序 + 老配置读回 + 未知值回落 seed + persist 恰好 7 键（空 suite 实测差集排除系统键）
- `Tests/PicCoreTests/RotationControllerTests.swift` - 7 条 + 文件内 `ManualScheduler` / `CountingRandomSource`；零 AVFoundation import
- `Tests/PicCoreTests/SettingsStoreTests.swift` - 一处断言更新（偏差 1：`allCases` 从单 case 改为三 case 冻结顺序）

## Decisions Made

- **`start()` 首条装载不记 `advances`**（偏差 2）：计划的用例 1/2 期望数组只有在不记首条时才可满足；`advances` 语义收窄为「只记切换」，首条是装载不是切换
- **`setMode` 与 `mode` 双入口、单一真相源**：计划正文「二选一」与冻结符号清单（两者都在）矛盾，按符号清单保留，`setMode` 只做 `mode = newMode`
- **`setInterval` 未 `start()` 时不排程**：否则用例 5 的 `scheduleCount == 1` 读数会漂；运行中的重排程（cancel + schedule）不受影响
- **`advance` 末尾对两种 reason 一律重排程、空列表不重排**：前者照计划原文，后者让定时器在降级路径自然熄火
- **系统键排除用空 suite 实测差集**（本机实测：裸键名 + 约 60 个系统键，`AppleLanguages` / `com.apple.*` / `NS*` 一类）：不写死前缀清单，将来加第 8 键立刻红

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] 既有 SettingsStoreTests 的 allCases 断言与计划的纯增量改动直接冲突**
- **Found during:** Task 1（改 SettingsStore.swift 前核算既有用例）
- **Issue:** `SettingsStoreTests.testPlayModeDefaultIsLoopSingle` 断言 `PlayMode.allCases == [.loopSingle]`，而计划要求追加两 case 后 SettingsStoreTests 仍全绿 —— 两者不可同时成立。该断言自带的文案写着「Phase 2 只枚举单循环；随机/顺序/播完停止属 Phase 4」，即它本来就声明了自己是 Phase 2 临时态
- **Fix:** 断言更新为 `[.loopSingle, .loopList, .shuffle]`（与 PlayModeTests 用例 2 完全一致的三 case 冻结顺序）—— 判据收紧到计划冻结的公开面，不是放宽
- **Files modified:** Tests/PicCoreTests/SettingsStoreTests.swift
- **Verification:** `swift test --filter SettingsStoreTests` → Executed 13 tests, with 0 failures；全量 88 条全绿
- **Committed in:** 1fb911d

**2. [Rule 1 - Bug] 计划正文「start() 把 items[0] 记进 advances」与计划自己的用例期望数组矛盾**
- **Found during:** Task 2（实现前核算用例算术）
- **Issue:** 用例 1 期望 5 次 advanceNow 后 `advances.map(\.index) == [0,0,0,0,0]`、用例 2 期望 6 次后 `[1,2,0,1,2,0]` —— 两者都要求 start() **不**追加条目；若按正文记首条，分别是 6 条与 7 条
- **Fix:** 按用例（判据）实现：`start()` 触发 `onAdvance(items[0])` 并排首程，但不打点 —— `advances` 只记 `.rotationElapsed` / `.userRequested` 两种切换。首条是装载不是切换，语义也更干净
- **Files modified:** Sources/PicCore/Playback/RotationController.swift
- **Verification:** 用例 1/2 逐字绿；全量 88 条全绿
- **Committed in:** 1ba3f17

**3. [Rule 1 - Bug] 用例 3 按计划描述写会被变异②蒙混过关（判据必须加严）**
- **Found during:** Task 3（写用例前实证变异②的输出）
- **Issue:** 计划对用例 3 只要求「每轮 index 构成 {0,1,2} 的排列」，但顺序轮转实现（变异②：`nextIndex = (currentIndex + 1) % items.count`）产出 `[1,2,0,1,2,0]`，**同样满足两个排列断言** —— 变异②转不了红，违反计划自己的验收条件（「变异②后失败列表含 testShuffleVisitsEveryItemExactlyOncePerRound」）与 fails_when ⑥（「判据要改严，不许把用例改松」）
- **Fix:** 用例 3 在排列断言之外追加 seed=42 的冻结顺序断言 `[1,0,2,2,1,0]`（由 SeededRandomSource 冻结算法唯一决定，本机实测）—— 正是计划 fails_when ⑥ 点名要求的加严方向
- **Files modified:** Tests/PicCoreTests/RotationControllerTests.swift
- **Verification:** 变异②红日志含该用例、2 条断言失败、0 条编译诊断
- **Committed in:** 85a37c8

**4. [Rule 1 - Bug] 用例 3 的调用次数算术不自洽**
- **Found during:** Task 3（核算「第 2–4 个 / 第 5–7 个 index」窗口）
- **Issue:** 计划写「调 advanceNow() 5 次」+「断言第 2–4 个与第 5–7 个 index 各构成一个排列」—— 5 次只有 5 个条目，第 5–7 个窗口不存在；且「第 2–4 个」的编号只有把 start() 的首条记进 advances 才对齐（已由偏差 2 排除）
- **Fix:** 调 6 次（两整轮），窗口取第 1–3 与第 4–6 个条目 —— 判据不变（两个完整轮次各自是排列），只修正算术
- **Files modified:** Tests/PicCoreTests/RotationControllerTests.swift
- **Verification:** 用例 3 绿；变异②照红
- **Committed in:** 85a37c8

**5. [Rule 3 - Blocking] 计划 `<automated>` 命令硬编码主检出路径**
- **Found during:** Task 1 执行前
- **Issue:** 三个 task 的 `<automated>` 均以 `cd /Users/coderstory/dev/pic` 开头 —— 在本 worktree 里执行会校验**主检出**的代码（worktree-path-safety #4767 要防的缺陷）
- **Fix:** 全部 verify 以 `git rev-parse --show-toplevel` 重定根到本 worktree，命令体逐字不变
- **Files modified:** 无入库文件变更（verify 脚本在 /tmp）
- **Verification:** 三个 verify 各自打出 OK 行
- **Committed in:** 不适用

**6. [Rule 1 - Bug] 变异红日志的 `error:` 计数门在本机 XCTest 输出格式下不可满足**
- **Found during:** Task 1 verify 设计（沿 04-01 Deviation 4 的同款发现）
- **Issue:** 本机 swift 6.4 的 XCTest 断言失败行自带 `error: -[...]` 前缀 —— 断言型红光的 `grep -c 'error:'` 恒 ≥ 1，计划的 `RED_COMPILE_ERRORS == 0` 门永远红
- **Fix:** 编译错误判别改为编译器诊断的独有形态（`:line:col: error:` 两数字段，或 `error: SwiftCompile`）；XCTest 断言行是 `:line: error:` 单数字段不命中。三处变异的红日志按新判别均为 0 条编译诊断 —— D-16 意图（红来自断言）完整保留
- **Files modified:** 仅 verify 脚本（/tmp，未入库）
- **Verification:** 三处变异 `RED*_COMPILE=0`、`RED*_ASSERT≥1`
- **Committed in:** 不适用

**7. [Rule 3 - Blocking] 计划 W9 禁跑全量 swift test，但本执行是隔离 worktree（.build 不共享）**
- **Found during:** 计划级 verification
- **Issue:** W9 禁令的理由是「与 04-03 共用同一 SwiftPM package 与同一 `.build/`」—— 该前提在并行 worktree 模式下不成立（各自独立 `.build/`），且调度方 success criteria 明确要求「swift test 全绿（含 wave 1 的 76 条 + 新增）」
- **Fix:** 在**本 worktree** 跑了一次全量 `swift test`（只覆盖本树：04-01 + 本 plan；04-03 的改动在它自己的 worktree，不受影响）：**88 tests, 0 failures**。04-06 的 `bash test.sh` 统一校验仍未跑（那条仍按计划留给 04-06）
- **Files modified:** 无
- **Verification:** FULL_TEST_RC=0，Executed 88 tests, with 0 failures
- **Committed in:** 不适用（无源码变更）

---

**Total deviations:** 7 auto-fixed（4 处 Rule 1 计划事实/算术错误 + 2 处 Rule 3 执行环境适配 + 1 处 Rule 1 判据环境适配）
**Impact on plan:** 全部为让计划的**判据本身**可达成而修，无一放宽判据。产品代码只有偏差 2 一处必要的设计取舍（start 不打点），其余都在测试与 verify 脚本侧。SettingsStoreTests.swift 的一行改动（偏差 1）是计划自相矛盾下的唯一出路，方向是把断言收紧到冻结公开面。

## Issues Encountered

None —— 无编译错误、无挂起、无环境故障；与并行兄弟 04-03 无构建产物冲突（隔离 worktree，各自 `.build/`）。

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- `RotationController` 公开面已冻结（符号清单见 04-02-PLAN.md「Artifacts」节）：04-05 装配可直接用 `init(scheduler:random:)` + `setItems` + `start` + `onAdvance → PlayerController.load(url:)`
- `SystemRotationScheduler` 由 AppDelegate 强持有即可；`deinit` 兜底是 Phase 7 长跑泄漏的观察点
- 模式切换 / 间隔变更已当场生效 —— Phase 5 设置窗只需写 `store.playMode = ...` + `controller.setMode(...)` / `setInterval(...)`
- 遗留（登记不阻塞）：`bash test.sh` 统一校验在 04-06；PlayMode 分段控件按 `allCases` 顺序渲染（Phase 5），顺序已被 PlayModeTests 用例 2 冻结
- ⚠️ 给 04-03 / 04-05 的提示：`start()` 的首条装载**不产生 advances 条目**，统计切换次数时从 0 起算（偏差 2 的语义收窄）

---
*Phase: 04-media-library*
*Completed: 2026-10-03*
