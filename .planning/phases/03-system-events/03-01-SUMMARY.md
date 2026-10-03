---
phase: 03-system-events
plan: 01
subsystem: playback-core
tags: [hold-arbiter, lock-watcher, system-events, veto-set, d-05, d-09, test-01]
status: complete

requires: []
provides:
  - HoldReason 6 cases / powerset 64 / order [0..5]
  - LockWatcher（System/ 分层首个 Watcher，start() 同步投递当前值）
  - LockSignalNames + sessionReader 注入口
  - PIC_HOLD 事件驱动 + PIC_HOLD_OBSERVER_TICKS
  - scripts/probe-lock.sh + evidence/lock-wiring.log
depends_on: []
affects: [03-02, 03-03, 03-04, 03-05]

tech-stack:
  added: []
  patterns:
    - Watcher 只产 HoldReason，不碰播放端（D-09 单向流）
    - 通知只当触发器，状态一律重读公开只读键（T-03-01）
    - 判据打在去重门之外才可红（D-05 / D-07）

key-files:
  created:
    - Sources/PicCore/System/LockWatcher.swift
    - Tests/PicCoreTests/SystemEventPipelineTests.swift
    - .planning/spike/LockWatcherDriver.swift
    - scripts/probe-lock.sh
    - .planning/phases/03-system-events/evidence/lock-wiring.log
  modified:
    - Sources/PicCore/State/HoldReason.swift
    - Sources/PicApp/AppDelegate.swift
    - Tests/PicCoreTests/HoldArbiterTests.swift
    - test.sh
    - .planning/WINDOWS.md

decisions:
  - order 取 1…5 而非 Phase 2 注释预告的 0…4（manualPause 已占 0，撞号会让 activeReasons 排序不确定）→ W-2026-10-03-14
  - LockWatcher 的通知只当触发器，收到后重读 CGSessionScreenIsLocked（T-03-01 的 mitigate 落点）
  - sessionReader 作为第三个注入参数，让 currentLockState() 的夹具单测自足，不依赖本机锁屏状态
  - PIC_HOLD 的 resumeAt 只出现在解除分支（Phase 2 定死的形状 + 03-05 的行尾锚定正则）

metrics:
  duration: 1097s
  completed: 2026-10-03
  tasks: 2

actuals:
  tokens: 21000
  tasks: 2
  commits: 3

commits: 3
plan_head_before: a9cd0504cb07f2d432e1225b30d26370c981aee4
plan_head_after: 8865b8d346edb64a40b56c209d1d4913a9336cd7
---

# Phase 3 Plan 01: 锁屏一条路端到端 + HoldReason 补到 6 case Summary

把「锁屏暂停 → 从原处续播」这一条路纵向打通并端到端证明，同时把 `HoldReason` 从 1 个 case 补到 6 个，使后续三个 Watcher 只是往同一个集合里加东西。

## What was built

**6 个 `HoldReason`，幂集恰 64 组。** 加 `fullscreen(1) / screenLocked(2) / displayAsleep(3) / systemSleeping(4) / battery(5)`，`manualPause` 的 `order = 0` 一字未改。幂集测试是**运行时**从 `HoldReason.allCases` 生成的 —— Phase 2 写的 `for mask in 0..<(1 << all.count)` 一个字没动，加完 case 自动从 2 扩到 64。**不存在手抄的 64 条断言。**

**`Sources/PicCore/System/LockWatcher.swift`（新，`System/` 目录首次建立）。** 分布式通知 → `Bool`。`center` / `names` / `sessionReader` 三个注入参数全部可注入；`start(onChange:)` **先注册两个观察者、再同步回调一次 `currentLockState()`** —— 因为 `com.apple.screenIsLocked` 是跃迁通知，本会话自起播起屏幕一直锁着，没有跃迁可等。`stop()` 按 token 逐个 `removeObserver` 后清空数组（Pitfall 4）。零 AVFoundation。

**通知只当触发器，不是状态本身（T-03-01）。** 收到任何信号后一律重读 `CGSessionCopyCurrentDictionary()` 的 `CGSSessionScreenIsLocked`，只把这个公开只读键的值喂给 `HoldArbiter`。伪造的「已解锁」通知因此最多触发一次重读，读到仍是锁着就不会误恢复播放。

**`PIC_HOLD` 改事件驱动（D-05）。** 0.5 秒 `Timer` 换成 `withObservationTracking` + 在 `onChange` 里重新 arm。`active=` 与 `reason=` 都从 `decision.activeReasons` 派生 —— 此前 `active` 取自「是否手动暂停」而 `reason` 在**两个分支里都写死**成手动暂停，导致 `active=1 reason=screenLocked` 结构上打不出来。两个分支合并成一个格式串，该字面量在全文件从 2 处收敛为 **1 处**。

**`PIC_HOLD_OBSERVER_TICKS=<n>`（D-05 唯一不空的机器判据）。** 打在 `guard snapshot != lastHoldSnapshot` **之前**。这一条是本次修订的核心：`observeHold()` 里的去重门让「观察驱动」与「0.5 秒轮询」在「12 秒窗口内 `PIC_HOLD` 行数」这个判据下输出完全相同（都是 1 行）—— 那是个空判，撞 D-07「一条从没红过的判据不证明它会红」。本行在门外：观察器被调用几次就是几。

## Verification actually run

| 项 | 结果 |
|---|---|
| `swift build` | RC=0 |
| `swift test` | **36 项全绿**（Phase 2 基线 24 + 本 plan 12） |
| `swift test --filter SystemEventPipelineTests` | 8 项，0 失败 |
| `bash test.sh` | **通过 39 失败 0 跳过 0**（基线 32 + 新增 7） |
| `bash scripts/probe-lock.sh` | RC=0 |

`evidence/lock-wiring.log`（11 行，driver 跑 6 秒，2 次合成投递）：

```
LOCK_START_SYNC_DELIVERED=1 locked=1
LOCK_SIGNAL_REGISTERED=1 center=DistributedNotificationCenter locked=com.local.pic.tests.lock.locked unlocked=com.local.pic.tests.lock.unlocked
LOCK_SIGNAL_INJECTED name=com.local.pic.tests.lock.locked source=com.local.pic.tests
LOCK_HOLD_APPLIED holds=(screenLocked) resumeAt=42.000
LOCK_SIGNAL_INJECTED name=com.local.pic.tests.lock.unlocked source=com.local.pic.tests
LOCK_RESUME seeks_to_anchor=1 seeks=42.000 holds=(none)
LOCK_TRANSITION=unobservable reason=session_locked CGSSessionScreenIsLocked=1
LOCK_SESSION_AT_START=1 real_CGSSessionScreenIsLocked=1 session_keys=14
LOCK_SIGNAL_COUNT=2
LOCK_ANCHOR_PRESERVED=1 seeks=42.000
```

- `LOCK_START_SYNC_DELIVERED` 打在任何合成投递之前，且**未投递任何通知**就发生 —— `start()` 的同步回调成立。
- `LOCK_RESUME seeks=42.000` 与进入 hold 时的 `resumeAt=42.000` **相等** —— 从原处续播，不是从头播（PAUSE-06）。
- 全文 `com.apple.screenIsLocked` 计数 **0** —— 合成事件一次都没碰系统通知名。

### 两次反向验证（真跑，不是声称）

**① 覆盖语义下反例必须转红** —— 备份 `HoldArbiter.swift`，`perl` 把 `before.subtracting([reason])` 换成 `Set()`，`swift test --filter HoldArbiterTests/testLockedThenFullscreenExitDoesNotResume` RC 从 0 → 1，三条断言同时红：

```
HoldArbiterTests.swift:177: XCTAssertEqual failed: ("[]") is not equal to ("[.screenLocked]")
HoldArbiterTests.swift:178: XCTAssertFalse failed - 锁屏仍在 → 一律不播
HoldArbiterTests.swift:179: XCTAssertTrue failed - 退出全屏那一刻不得有任何 seek
```

覆盖式实现在「退出全屏」那一刻把 `holds` 写成空集并触发了一次 seek —— 正是 ARCHITECTURE §6.1 点名的反模式。恢复后 `cmp -s` 与备份逐字节一致。

**② `System/` 引入 AVFoundation 后 `test.sh` 必须转红** —— 往 `LockWatcher.swift` 插 `import AVFoundation`，汇总从 `通过 39 失败 0` 变 `通过 38 失败 1`，该项显示 `❌ System/ 四个 Watcher 零 AVFoundation —— System/ 依赖了播放框架`。恢复后 `cmp -s` 一致、回到 39/0。

### 活体烟测（未落 evidence 文件）

`.build/debug/Pic` 实跑 7 秒（本机会话锁着）：

```
PIC_HOLD_OBSERVER_TICKS=1
PIC_HOLD active=1 reason=screenLocked holds=(screenLocked)
```

- 这条是**真实系统读数**驱动的 hold，不是合成通知。
- `PIC_HOLD_OBSERVER_TICKS` 全程只出现 **1 次**（7 秒 / 0.5 秒轮询的话该是约 14 次）—— 事件驱动在活体上成立。
- 该次烟测**没有**写 `evidence/holds-live.log` —— 那是 03-05 的产物，且它还需要本 plan 未交付的 `PIC_HOLD_SUMMARY`。

## Deviations from Plan

### 计划事实更正（W-2026-10-03-14）

`HoldReason.swift` 的 Phase 2 注释预告新 case 取 `fullscreen(0) / screenLocked(1) / …`，而 `manualPause` 已占着 0。两个 case 共用同一个 `order` 会让 `PlaybackDecision.activeReasons`（`holds.sorted()`）在两者之间顺序不确定，D-10 允许的「优先级只用于 UI 文案排序」就失效。**取 1…5，`manualPause` 的 0 未改**，实测 `map(\.order) == [0,1,2,3,4,5]`。登记为 `W-2026-10-03-14`。

### Rule 1 — Bug：`PIC_HOLD` 的 `resumeAt` 多了尾巴（commit `8865b8d`）

计划正文把合并后的形状写成「`active=<0|1> reason=<r> holds=<(...)> resumeAt=<秒>`」，我照此实现成**两个分支都带 `resumeAt`**。烟测发现活体输出是

```
PIC_HOLD active=1 reason=screenLocked holds=(screenLocked) resumeAt=0.000
```

而 03-05 的判据是**行尾锚定**的正则 `^PIC_HOLD active=1 reason=screenLocked holds=\(screenLocked\)$` —— 命中数为 **0**，03-05 会立刻假红。

同一份计划内部就有三种口径：正文的「两分支都带」、计划自己的证据行清单、以及 Phase 2 定死的串（`02-03-PLAN.md:174-175`）和 03-05 的正则（**只在解除分支带**）。前者带尾锚点、后者不带，不可兼得。**取后者**：`resumeAt` 只拼在解除分支，形状一个字不改地保持 Phase 2 的两分支形态；`PIC_HOLD active=` 字面量仍恰好 1 处（共用一个格式串，尾部按需拼接）。修正后正则命中 1。

### Rule 1 — Bug：driver 的 `String(format:)` 用了 `%s` 收 Swift `String`

首跑 `probe-lock.sh` 段错误退出（RC=139）、`holds=¯≠ÌÚ` —— 把 Swift `String` 按 `%s` 传进 `String(format:)` 是内存越界读。改 `%@` 后正常，且顺手把 `LOCK_HOLD_APPLIED` 从同步回调里挪开，使同步投递那一行与「收到通知」的行彻底分开（否则同步那次也会打一行 `LOCK_HOLD_APPLIED`，证不了「收到通知才生效」）。

### Rule 1 — Bug（自查）：判据被自己的注释违反（D-07 第四次）

两处：`Timer(timeInterval: 0.5` 与 `reason=manualPause` 被我写进了解释性注释，`grep -c` 立刻报错数非 0；修 `PIC_HOLD` 形状时又在注释里写了那条字面量，「恰好 1 处」变 2 处。两处都改成不复述字面量的说法。**判据一个没放宽。**

### 计划冲突（PLAN_DEVIATION）：`PIC_HOLD` 的形状三处口径不一

已在上面「Rule 1 — Bug」里详述。**改的是实现，不是判据**：Phase 2 冻结的输出串与 03-05 的判据都没动，是计划正文那一句与它们冲突。

### 对计划的一处加严

计划让 `test.sh` 追加 3 项，但其中 `State/` 零 AVFoundation 与 `kCGWindowName` **Phase 2 已有**（只要求确认仍绿），真正新增的只有 2 项，按原样实施只能到 34 项，够不到 AC 的「≥ 35」。没有为了凑数把既有项当新增，而是补了 5 条**本 plan 自己的 AC**（0.5 秒轮询为 0、`withObservationTracking` ≥ 1、`PIC_HOLD active=` 恰好 1 处、`reason=` 不写死、`PIC_HOLD_OBSERVER_TICKS=` 恰好 1 处）挂进 `test.sh` 每次重验 —— 它们原本只在本 plan 的 `<automated>` 里查一次。实测 32 → **39**。

另加一条：新判据的 `no()` 文案**带上 `ok()` 的同一句判据名**。03-05 的 `<automated>` 会在变异后的红日志里 `grep -c 'System/ 四个 Watcher 零 AVFoundation'` 确认是这一条红了；失败文案写成另一句（如「System/ 依赖了播放框架」）就查不到 —— 首跑时正是这个原因导致该 grep 命中 0。

## Known Stubs

无。三个 Watcher（`FullscreenDetector` / `PowerWatcher` / `DisplayWatcher`）**不属于本 plan** —— 本 plan 只立住 `System/` 分层并交付 `LockWatcher`。`HoldReason` 的另外 4 个 case 在此登记，检测逻辑由 03-02 / 03-03 / 03-04 交付。

## Unverified（不阻塞，如实登记）

| 项 | 状态 | 登记 |
|---|---|---|
| **真实锁屏跃迁触发暂停** | `LOCK_TRANSITION=unobservable` | `W-2026-10-03-16` |
| `com.apple.screenIsLocked` 在真解锁时是否投递 | 沿用 Phase 1 结论（PDCA-A7） | `W-2026-10-03-16` |
| `PIC_LOCK_SIGNAL_PREFIX` 是脚手架不是产品能力 | 照 `W-2026-10-03-08` 先例 | `W-2026-10-03-15` |
| `startWallpaper()` 的 `player.player.play()` 直连（D-06） | 已加注释标明 03-05 收口 | `W-2026-10-03-10`（03-05 结） |

**真实跃迁这条要说清楚**：`start()` 的**同步**回调已实测生效（`LOCK_START_SYNC_DELIVERED=1 locked=1`，未投递任何通知就发生），这只证明「订阅后立刻能用真实会话状态置位」。合成投递走的是**注入的通知中心 + 注入的通知名**，连「系统通知中心能否收到」这一层都没碰到。PAUSE-02 / PAUSE-06 的**接线**已证明，**真实跃迁触发暂停未证明**。

## Threat Flags

| Flag | File | Description |
|------|------|-------------|
| threat_flag: spoofing | `Sources/PicCore/System/LockWatcher.swift` | T-03-01 已 mitigate：通知只当触发器，状态重读 `CGSSessionScreenIsLocked`。可测部分（缺键 / 0 / 1 三夹具）已进单测；真实伪造投递记 `unverifiable_here` |
| threat_flag: tampering | `Sources/PicApp/AppDelegate.swift` | T-03-04：`PIC_LOCK_SIGNAL_PREFIX` 把通知名指向测试名。测试脚手架不是产品能力，危害面仅限本机开发者自伤 —— `W-2026-10-03-15` |

## Next

- **03-02** 复用本 plan 的 `System/` 分层与 `src_count` 判据，交付 `FullscreenDetector`。
- **03-03 / 03-04** 往 `HoldReason` 已建好的 4 个 case 上接检测逻辑（纯增量，不动 `order`）。
- **03-05** 是装配点：`startWallpaper()` 的 `play()` → `arbiter.applyCurrentDecision()`（D-06），`HoldStatus` / `PIC_HOLD_SUMMARY`，以及 D-05 的**行为**判据（12 秒零变化窗口里 `PIC_HOLD_OBSERVER_TICKS` 最大值恰好为 1）。⚠️ 03-05 若发现 `^PIC_HOLD active=1 reason=screenLocked holds=\(screenLocked\)$` 命中 0，病因是 `resumeAt` 尾巴 —— 本 plan 已在 `8865b8d` 修掉，实测命中 1。

## Self-Check: PASSED

- 文件全部存在：`Sources/PicCore/System/LockWatcher.swift`、`Tests/PicCoreTests/SystemEventPipelineTests.swift`、`.planning/spike/LockWatcherDriver.swift`、`scripts/probe-lock.sh`、`.planning/phases/03-system-events/evidence/lock-wiring.log` ✓
- 提交全部存在：`7c182a7`、`1549a06`、`8865b8d` ✓
- `HoldReason.allCases.count == 6` / `1 << count == 64` / `map(\.order) == [0..5]` —— 单测断言 ✓
- `HoldReason.manualPause.order == 0` 未被改动 ✓（`testOrderValuesAreDistinctAndManualPauseStaysZero`）
- `PIC_HOLD active=` 字面量恰好 1 处 ✓
- `LOCK_START_SYNC_DELIVERED` 证据行存在且先于任何投递 ✓
- `PIC_HOLD_OBSERVER_TICKS=` 打在去重门之前（行号 89 < 96）✓
- 两处临时变异均已撤销，`cmp -s` 与备份逐字节一致 ✓
- `STATE.md` / `ROADMAP.md` **未改动**（`.planning/state.json` 的改动是编排器在本任务之前就有的，未纳入本 plan 的任何提交）✓