---
phase: 03-system-events
plan: 05
type: execute
wave: 3
status: complete
depends_on: [03-01, 03-02, 03-03, 03-04]
requirements: [PAUSE-06, PAUSE-07]
subsystem: playback-arbiter
tags: [d-06, d-12, b1, watcher-wiring, verdict, wave-3, full-suite]
commits: 2
plan_head_before: 8f0b8f87672e09a4d8f7164c7a2a4592ada6fc6b
plan_head_after: 4931306484bb69fd4b1e56736e62b880a5d634ea
---

# Phase 3 Plan 05 Summary: 装配 + HoldStatus + D-06 收口 + VERDICT

**四个 Watcher 第一次接进产品，起播路径零播放器直连且设置落位受 `decision.shouldPlay` 门控，
「当前为什么暂停」成为可读数据，并拿到本 Phase 在锁屏会话下的活体 hold。**

## 本 plan 做了什么

Wave 3 的唯一 plan，也是 Phase 3 的收口。前四个 plan 交付的四个 Watcher 到此为止都是
**各自可测的孤立类型** —— 没有一根线接进产品，`HoldArbiter` 至今只被 `.manualPause` 动过。
本 plan 是它们唯一的装配点。

| 产物 | 内容 |
|---|---|
| `HoldStatus.swift`（新建） | D-12 的数据落点：`shouldPlay` / `reasons`（复用 `activeReasons`，不重排）/ `labels` / `summary`；`HoldReason.uiLabel` 六条互不相同的中文。**零 SwiftUI / 零 AppKit** |
| `HoldArbiter.swift`（改） | **纯追加两个成员**（W10）：`applyCurrentDecision()` + `holdStatus`。`decision` / `resumeAnchor` / `set` / `isManuallyPaused` 一字未改 |
| `AppDelegate.swift`（改） | `wiring()` 接四根线（`lockWatcher` 最后）；`applicationWillTerminate` 摘四个 `stop()`；D-06 收口；B1 门控；新增 `PIC_HOLD_SUMMARY` 行。**不改 `observeHold()`**（03-01 已改） |
| `HoldStatusTests.swift`（新建） | **6 条**，含 B1 的变异靶子 |
| `run-probe.sh holds` | 12 秒零变化窗口的活体 evidence，落 Phase 3 自己的目录 |
| `test.sh`（改） | 追加 6 项 |
| `03-VERDICT.md`（新建） | 5 条 SC 逐条四取值结论 + 四栏表 + 交给下一阶段 |
| `WINDOWS.md`（改） | Phase 3 号段分配表 + `-20` / `-21` / `-22` / `-23` |

## B1：起播路径的门控（本 plan 最危险的一条）

`PlayerController.setRate(r)` 就是 `player.rate = r`（`PlayerController.swift:51`）。
SDK `AVPlayer.h:150` 明文 + Phase 1/2 的本机实测都证明它**会把已 hold 的播放器重新拉起**。
所以**只把 `play()` 换成 `applyCurrentDecision()` 是不够的** —— `setRate` 本身就是第二根能恢复播放的线。

最终顺序：

```
arbiter.applyCurrentDecision()  →  setVolume  →  setMuted  →  if arbiter.decision.shouldPlay { setRate }
```

**两次变异都做了，且都带自检：**

| 变异 | 结果 | 红灯来源 |
|---|---|---|
| 删掉 `if decision.shouldPlay {` | `GATE_GREP=1` → `GATE_AFTER=0`（**计数下降，否则判「变异没生效」**），`GATE_MUTATED_RC=1` | 编译失败（`extraneous '}'`） |
| 把门控换成恒真 `if true {` | rc=1 | **`XCTAssertEqual failed: ("1") is not equal to ("0")`** |

第二次变异是**追加**的。计划给的删行变异必然留下悬空的 `}`，红灯会来自编译失败 ——
那正是 W-2026-10-03-17 点名、03-03 因此把耦合点从字段声明挪到 init 赋值体的反模式。
补一个**能编译**的变异，红灯才落在断言上。两次恢复后 `cmp -s` 均与备份逐字节一致。

⚠️ **`status=paused` 为 0 的病因独立于 D-06 时序。** 不要去调
`startWallpaper()` 与 `wiring()` 的先后，那是错修法。

## 活体 evidence：真实系统信号

`evidence/holds-live.log`（12 秒窗口，`emit` 走 stderr 故 stdout/stderr 合并采集）：

```
LOCK_STATE_AT_START=1 source=CGSessionCopyCurrentDictionary.CGSSessionScreenIsLocked loginwindow_pid=489
PIC_HOLD active=1 reason=screenLocked holds=(screenLocked,displayAsleep)
PIC_HOLD_SUMMARY summary=锁屏,显示器熄屏 reasons=2
TICK_PAUSED_LINES=7   TICK_LINES=7   OBSERVER_TICKS_MAX=1
```

**这不是合成通知。** 合成的那条只在 `scripts/probe-lock.sh` 里、用
`com.local.pic.tests.lock.` 前缀跑（`LOCK_START_SYNC_DELIVERED=1`），本 plan 的这条来自真实会话读数。

`OBSERVER_TICKS_MAX=1` 是 **D-05 的行为判据**：12 秒零决策变化窗口里 `observeHold()` 只被调用过一次。
该计数打在去重门**之前**（`holdObserverTicks += 1` 位于 `guard snapshot != lastHoldSnapshot` 之上）——
**不用**「`PIC_HOLD active=` 行数 == 1」，去重门让它在合规与违规两种实现下结果相同，那是空判（D-07）。

## ⚠️ 三条与计划 AC 不符的实测，已按实际读数记录、未改产品

计划 AC 期望 `holds=(screenLocked)` 与 `summary=锁屏 reasons=1`，实测是
`holds=(screenLocked,displayAsleep)` 与 `summary=锁屏,显示器熄屏 reasons=2`。

原因：采集时会话**锁着且显示器已熄**，两个真实 reason 同时成立
（`CGDisplay_IS_ASLEEP=1`，与 `evidence/display-sleep-signals.log` 一致）。
**没有为了凑单 reason 去改产品。**

## ⚠️ 会话锁定态在本 plan 执行期间切换了至少四次

这是本 plan 最重要的诚实性发现，逐次读数在 `evidence/session-state-changed.log`（`READ_1` ~ `READ_5`）：

| 时刻 | 读数 | 后果 |
|---|---|---|
| 11:25 开工 | `HAS_KEY=false KEYS=11`、`ASLEEP=0` | 产品实跑 `holds=(none) status=playing` |
| 11:47 采集 | `LOCKED=1 KEYS=14`、`ASLEEP=1` | 活体 hold 成立 |
| 11:50 采集后 | `ASLEEP=0` | 显示器点亮，`displayAsleep` 只对采集窗口成立 |
| 11:53 复跑 | `KEYS=11` | 复采 `COVERAGE=0.000`（vs 03-02 入库的 `1.000`） |
| 11:57 再复跑 | 再次锁上 | 四份 probe evidence 读数全部与入库版本不同 |

处置：**未锁屏去制造它**，也未改产品凑数。`test.sh` 的 `probe_line` 现在会先留档旧值、
变了就打告警。四份 03-01~03-04 入库的 evidence 已 `git checkout` 全部还原 ——
**不替别的 plan 改产物值**。

**推论（已写进 VERDICT）：任何依赖「屏幕锁着」的读数都只在采集窗口内成立，
Phase 4–7 不得把本 Phase 的活体读数当稳定基线。**

## `-23`：装配后暴露的全屏间歇性误暂停

`FullscreenDetector` 间歇性把 `.fullscreen` 置位，导致壁纸被误暂停。
一次插桩观测（3 轮中 1 轮读到 `DBG_SET after=fullscreen before=`），随后 5 轮复跑均未复现
→ **如实记「间歇性，给不出稳定复现率」，未为了让它非 0 去制造应用切换事件**。

**不是本 plan 引入的回归** —— 装配前该 detector 从未 `start()` 过，误判在产品里结构上不可达。
成因属 03-02 的判定口径（Ghostty 恒覆盖 → `covering` 恒真，前台应用一变即误判）。
**未改判定口径**：改它属 D-02 的架构决策，且需要真实跃迁样本，本会话没有。

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 · Blocking] `probe-lock.sh` 的源码清单漏了 `HoldStatus.swift`**
- **Found during:** Task 2（`bash test.sh` 报「锁屏跃迁观测已采集 ❌」）
- **Issue:** 给 `HoldArbiter` 加了返回 `HoldStatus` 的 `holdStatus` 之后，该脚本因手写的
  `SRC=` 清单未同步而编译失败（`PROBE_COMPILE_RC=1`），**并把 evidence 日志清空**——
  空文件会让后续判据静默通过、假绿。
- **Fix:** 补上该文件，并在脚本里写明「新增/删除 `State/` 下的文件时必须同步改这里」。
  另三个探针脚本不经 `HoldArbiter`，逐个核对过 `SRC=` 清单，未受影响。
- **Files:** `scripts/probe-lock.sh`
- **Commit:** `4931306`

**2. [Rule 1 · Bug] `probe_line` 读 stdout 而非 evidence 文件**
- **Found during:** Task 2 首次跑 `test.sh`（四条 probe 判据全红）
- **Issue:** 这些脚本把 driver 输出写进 evidence 文件，只往 stderr 打一行 `PROBE_OK`；
  只收 stdout 会恒红。
- **Fix:** 改为先跑脚本、再读 evidence 文件。**未**放宽判据本身。
- **Commit:** `4931306`

**3. [Rule 2 · Correctness] `test.sh` 的 probe 判据会静默覆盖别的 plan 的 evidence**
- **Found during:** Task 2 复跑 `test.sh` 时 `fullscreen-signals.log` 被覆盖
  （`COVERAGE` 1.000 → 0.000，因为会话已解锁）
- **Issue:** `probe-*.sh` 就地覆盖 evidence。若会话态与当初采集时不同，覆盖掉的就是上一个 plan 的读数。
- **Fix:** `probe_line` 先留档旧值，`cmp` 不一致时额外打一条告警；本 plan 已把
  03-01~03-04 的四份 evidence 全部还原。**判据未动，产物值未动。**
- **Commit:** `4931306`

### Plan-self inconsistencies (documented, not silently resolved)

**4. [B1 变异靶子] 追加第二次变异（换真值），使红灯来自断言而非编译失败**
计划给的删行变异必然让文件编译不过，红灯会来自 `extraneous '}'` —— W-17 同类反模式。
补一次能编译的变异（`if true {`），红灯落在 `XCTAssertEqual`。**判据未放宽，两次都跑。**

**5. [AC 与实测不符] 三条 AC 期望值按实际读数记录**
`holds=(screenLocked,displayAsleep)` / `summary=锁屏,显示器熄屏 reasons=2` / `items=3` 而非 `items=1`。
成因是采集时锁屏与熄屏两个真实信号同时成立。**修正则，未改产物。**

**6. [W 编号冲突] 计划内部 `-20`~`-23` 的两处说法互斥**
`<action>` 说追加 `-20`/`-21`/`-22`，AC 又要求存在 `-23` 并称其为「四类跃迁未观测汇总」。
处置：内容按 `<action>` 写入 `-20`/`-21`/`-22`（与 `W-2026-10-03-19` 描述 E 的「`-20`~`-23`
由 03-05 独占」一致），`-23` 另记本 plan 新发现、计划里没有的事实（全屏误暂停）。
两条 AC 都满足（`-23` 存在、`-22` 为 `resolved`、`uniq -d` 为空），内容不重复。

## Verification

| 项 | 结果 |
|---|---|
| `swift build` | `Build complete!` |
| `swift test`（**全量**，wave 3 首次解除 W9） | `Executed 67 tests, with 0 failures`（≥53 要求） |
| `swift test --filter HoldStatusTests` | `Executed 6 tests, with 0 failures` |
| `bash test.sh` | `通过 50  失败 0  跳过 0`（≥40 要求） |
| `run-probe.sh holds` | rc=0，25 行 evidence |
| B1 变异 ×2 | 均转红，均有自检，恢复后 `cmp -s` 一致 |
| `test.sh` 插桩反向验证 | 插 `import AVFoundation` → `通过 49 失败 1` 且该条 ❌ → 恢复 → `通过 50 失败 0` |
| 剥注释后 `player.player.play()` / `pause()` | 各 **0** |
| 五个 `arbiter.set(.<reason>` | 各 ≥ **1** |
| `applyCurrentDecision()` | **1** 处，行 282 < `setVolume(` 行 294 |
| B1 门控行号 | `if arbiter.decision.shouldPlay {` 行 **296** < `setRate` 行 **297** |
| `PIC_HOLD active=` / `PIC_HOLD_SUMMARY summary=` | 各恰好 **1** |
| `HoldArbiter` 追加清单 | 恰好 **2**（W10）；`decision` / `resumeAnchor` / `set` / `isManuallyPaused` 各 1 |
| `HoldStatus.swift` 的 SwiftUI/AppKit/AVFoundation | **0** |
| W 号段冲突 | `uniq -d` 输出为空 |

## Known Stubs

无。全屏误暂停（`-23`）不是桩 —— 它是**已定位成因、已量化、未修**的缺陷，理由已记在 WINDOWS.md。

## Threat Flags

| Flag | File | Description |
|---|---|---|
| threat_flag: gate-must-survive | `Sources/PicApp/AppDelegate.swift:296` | `if arbiter.decision.shouldPlay {` 是 B1 门控，最易被后人「顺手清理」掉。判据 + 变异 + 活体 evidence 三重锁，已登记 `W-2026-10-03-21` |
| threat_flag: hand-maintained-source-list | `scripts/probe-lock.sh` | `SRC=` 是手写清单，`swift build` 不会更新它。漏列会让 evidence 被清空 → 判据假绿。已在脚本内写明同步要求 |

## Actuals

| 维度 | 计划 | 实测 |
|---|---|---|
| tokens | 52000 | **8504**（`chars/4` over 实际改动，34017 chars） |
| tasks | 2 | 2 |
| commits | — | **2**（`f24571e`、`4931306`） |

估算高估约 6 倍。差额主要在**环境实测与计划 AC 核对**上：会话锁定态切换四次、
发现并量化全屏误暂停、发现并修 `probe-lock.sh` 的源码清单缺陷 ——
这些都不在计划的 token 估算里。

## Self-Check: PASSED

- ✅ `f24571e` 存在（Task 1：4 个文件，318 insertions）
- ✅ `4931306` 存在（Task 2：脚本 + VERDICT + evidence + WINDOWS）
- ✅ `Sources/PicCore/State/HoldStatus.swift` 存在
- ✅ `Tests/PicCoreTests/HoldStatusTests.swift` 存在（6 个 `func test`）
- ✅ `.planning/phases/03-system-events/03-VERDICT.md` 存在（5 行 SC 结论）
- ✅ `.planning/phases/03-system-events/evidence/holds-live.log` 存在（25 行）
- ✅ `W-2026-10-03-20` ~ `-23` 存在，`uniq -d` 为空
- ✅ 两个 commit 均无文件删除
- ✅ 工作树干净

**STATE.md / ROADMAP.md 未被本 plan 修改**（编排器拥有这些写入）。