PHASE_3_VERDICT

# Phase 3 判定：系统事件仲裁

**本文件是 Phase 3 的唯一判定文件。Phase 4–7 只引用它**，不回翻五份 SUMMARY 与 git log。
判据输入全部来自 `.planning/phases/03-system-events/evidence/` 下的原始日志，不从 SUMMARY 转述。

**本 Phase 的产品未在解锁会话验证过。屏幕在本 Phase 执行期间锁着**
（`evidence/lock-state` 的 `LOCKED=1 LOCKEDTIME=1790976529 ONCONSOLE=1 LOGINWINDOW_PID=489`，
以及 `evidence/holds-live.log` 的 `LOCK_STATE_AT_START=1 … loginwindow_pid=489` 与 `LOCK_READ_RAW=LOCKED=1 KEYS=14`）。
这行不加任何限定语。本文件里所有实测读数都产生于锁屏会话。

⚠️ **执行期间会话锁定态变了两次，如实记在这里 —— 本 Phase 的全部活体读数都只是「采集时刻」的读数。** 03-05 开工时（11:25 前后）
`swift -e` 读 `CGSessionCopyCurrentDictionary()` 得 `HAS_KEY=false KEYS=11`（键不存在 = 未锁），
显示器 `CGDisplay_IS_ASLEEP=0`，产品实跑读到 `PIC_HOLD active=0 … holds=(none)` 与 `status=playing`；
到 11:47 采集活体 evidence 时会话已重新锁上（`LOCKED=1 KEYS=14`）、显示器也已熄（`ASLEEP=1`）。
采集之后（11:53 复跑 `test.sh` 时）会话又回到**未锁**（`KEYS=11`），
同一次复采里 `probe-fullscreen.sh` 读到 `COVERAGE=0.000 WINDOW_COUNT=0
FULLSCREEN_VERDICT=0 reason=not_covering` —— 与 03-02 入库的 `COVERAGE=1.000` 完全不同，
因为那次是在锁屏会话下采的。**第四次**（11:57 再跑 `test.sh`）会话又锁上，
四份 probe evidence 的读数全部与入库版本不同 —— `test.sh` 的告警因此同时打出 4 条。
逐次读数见 `evidence/session-state-changed.log`（`READ_1` ~ `READ_5`）。
**03-02 已入库的 evidence 未被覆盖**，复采另记在 `evidence/session-state-changed.log`。

**未为了制造锁屏态去锁屏、也未为了凑单 reason 去改产品** —— 最终 `holds-live.log` 里
`holds=(screenLocked,displayAsleep)` 的**两个** reason 都是真实读数，见「四栏口径 → 跑过」。

⚠️ **两条读数都是「采集时刻」的读数，不是常量。** 采集之后（11:50 前后）显示器又亮了
（独立复读 `CGDisplay_IS_ASLEEP` 得 **0**）。因此 `holds-live.log` 里的 `displayAsleep`
只对**采集那 12 秒窗口**成立；引用它时不得当成「本机显示器一直熄着」。

## 5 条 Success Criteria 逐条结论

判据原文见 `.planning/ROADMAP.md` Phase 3 Success Criteria 第 1–5 条。结论列只有
`PASS` / `PASS-with-gap` / `PARTIAL` / `BLOCKED` 四种取值，每行都挂一个真实证据路径与一个数字。

| SC | 结论 | 证据（文件:字段） | 数字 |
|---|---|---|---|
| SC1 任意应用进入全屏 → 壁纸暂停；退出全屏 → 从暂停处续播（不从头）；刘海屏 / Chrome / 超宽屏三场景各验证一遍 | PARTIAL | `fullscreen-signals.log:FULLSCREEN_VERDICT` `:COVERAGE` `:WINDOW_COUNT` `:STYLEMASK_UNAVAILABLE`；`FullscreenGeometryTests` 5 条 + `FullscreenDetectorTests` 4 条 | 合取判定已跑通：`FULLSCREEN_VERDICT=0 reason=geometry_without_signal`、`COVERAGE=1.000`、`COVERING=1`、`NON_GEOMETRIC=0`、`WINDOW_COUNT=4`、`STYLEMASK_UNAVAILABLE=1`、`WINDOW_DICT_STYLE_KEY_COUNT=0`；几何基准对齐 Phase 1 的 `1.000/1.000/1.000`。**缺口：真实跃迁与三场景各跑一遍均未做** —— 本机无 Chrome、单屏、锁屏会话，见「没跑过」①。**另有一条反向实测**：`evidence/fullscreen-falsepositive.log` 记到间歇性误暂停，见「没跑过」④ |
| SC2 锁屏 / 显示器熄屏 / 系统睡眠 三类事件各自触发暂停，解除后各自正确续播 | PARTIAL | `holds-live.log:PIC_HOLD` `:PIC_HOLD_SUMMARY` `:TICK_PAUSED_LINES` `:LOCK_STATE_AT_START`；`lock-wiring.log:LOCK_ANCHOR_PRESERVED`；`display-sleep-signals.log:DISPLAY_START_SYNC_DELIVERED` | **锁屏与熄屏有活体证据**：`PIC_HOLD active=1 reason=screenLocked holds=(screenLocked,displayAsleep)`、`PIC_HOLD_SUMMARY summary=锁屏,显示器熄屏 reasons=2`、`TICK_PAUSED_LINES=7`（`TICK_LINES=7`，全程 `status=paused`）。续播锚点由单测锁住：`LOCK_ANCHOR_PRESERVED=1 seeks=42.000`。**缺口：真实跃迁与解除后的续播未观测** —— 会话自始至终锁着，无 lock→unlock 边沿；显示器已是熄屏稳态，点亮那一下没发生；睡眠被外部 `caffeinate` 挡着，见「没跑过」②③④ |
| SC3 「电池供电时暂停」开关默认关闭；打开后拔电源暂停、插回续播 | PARTIAL | `power-signals.log:BATTERY_HOLD` `:IS_ON_BATTERY` `:INTERNAL_BATTERY_PRESENT` `:POWER_TRANSITION`；`PowerWatcherTests` 6 条 | 默认关闭与判定逻辑已过：`BATTERY_HOLD enabled=0 verdict=0`、`IS_ON_BATTERY=0`、`POWER_SOURCE_VALUE=AC Power`、`INTERNAL_BATTERY_PRESENT=1`。**缺口：拔/插电源均未实测** —— 本机全程在 AC 上，需物理动作，见「没跑过」⑤ |
| SC4 veto 仲裁正确：锁屏状态下退出全屏不恢复播放；多条件叠加时只有集合清空才续播 | PASS | `swift test` 全量；`HoldArbiterTests.testShouldPlayMatchesEmptyHoldsForEverySubset` / `testLockedThenFullscreenExitDoesNotResume` / `testAllCasesCountIsSixAndPowersetIsSixtyFour`；`test.sh` 的「起播路径零播放器直连」 | `Executed 67 tests, with 0 failures`。幂集子集在**运行时**从 `allCases` 生成，`HoldReason` 6 个 case → 恰好 **64** 组，逐组断言 `decision.holds == subset` 与 `shouldPlay == subset.isEmpty`。反例用例断言「锁屏中退出全屏 `holds` 仍非空、不恢复播放」。**且经注入式反向验证**：把 `PublicDecision` 的耦合点改掉后用例转红（见 03-01 的 `MUTATED_RC=1`）。`test.sh` 剥注释后 `player.player.play()` / `player.player.pause()` 计数各 = **0** |
| SC5 续播锚点不漂移：锚点在 `holds` 由空变非空时写入、由非空变空时消费，叠加暂停期间不被二次覆盖 | PASS | `HoldArbiterTests.testAnchorNotOverwrittenAcrossAllSixReasons` / `testAnchorWrittenOnlyOnEmptyToNonEmptyTransition` / `testResumeSeeksToAnchorThenClearsAnchor`；`lock-wiring.log:LOCK_ANCHOR_PRESERVED` | 6 个 reason 逆序解除下 `seeks == [42.0]`（一条 seek，锚点未被二次覆盖）；`∅ → 非∅ → ∅ → ∅` 四步下 `seeks` 恒为首次那个值。合取式「原因 A 后跟原因 B，解除 A 不 seek，解除 B 才 seek 到最初的 42」有独立用例 |

**SC1 / SC2 / SC3 都不写 `PASS`。** 它们的自动部分过了，但**真实跃迁**那一跳没过，
缺口必须落在结论列里，不能塞进脚注（Phase 1 SC4 的教训：`01-VERDICT.md` 自述
「VERDICT overstated its LOCK= evidence chain, SC4 relabelled PARTIAL」）。

## 四栏口径

## 跑过

| 项 | 命令 | 产物 | 数字 |
|---|---|---|---|
| **装配后的活体 hold（真实系统信号）** | `bash scripts/run-probe.sh holds` | `evidence/holds-live.log` | `LOCK_STATE_AT_START=1 … loginwindow_pid=489`；`LOCK_READ_RAW=LOCKED=1 KEYS=14`；`HOLDS_LIVE=holds=(screenLocked,displayAsleep)`；`PIC_HOLD active=1 reason=screenLocked holds=(screenLocked,displayAsleep)`；`PIC_HOLD_SUMMARY summary=锁屏,显示器熄屏 reasons=2`；`TICK_LINES=7`、`TICK_PAUSED_LINES=7`、`OBSERVER_TICKS_MAX=1`、`HOLD_SUMMARY_LINES=1`、`PIC_HOLD_ACTIVE_LINES=1`；`OBSERVATION_WINDOW_SECONDS=12`。**这不是合成通知** —— 合成的那条只在 `scripts/probe-lock.sh` 里用 `com.local.pic.tests.lock.` 前缀跑 |
| D-05 的行为判据（事件驱动） | 同上 | `evidence/holds-live.log:OBSERVER_TICKS_MAX` | 12 秒零决策变化窗口里 `PIC_HOLD_OBSERVER_TICKS` 的**最大值 = 1**。0.5 秒轮询会涨到约 24。该行打在 `observeHold()` 的去重门**之前**（`AppDelegate.swift` 的 `holdObserverTicks += 1` 位于 `guard snapshot != lastHoldSnapshot` 之上） |
| 产品编译 | `swift build` | 终端输出 | `Build complete!` |
| 产品单测（全量，wave 3 首次） | `swift test` | 终端输出 | `Executed 67 tests, with 0 failures` |
| 无头回归（全量判据） | `bash test.sh` | 终端输出 | `通过 50  失败 0  跳过 0`。**插桩反向验证实测跑过**：往 `Sources/PicCore/System/LockWatcher.swift` 插 `import AVFoundation` → 汇总变 `通过 49  失败 1` 且该条显示 `❌` → 恢复后 `cmp -s` 一致 → 再跑回到 `通过 50  失败 0` |
| B1 的两次变异验证 | `swift test --filter HoldStatusTests` | 终端输出 | ① 删掉测试里 `if decision.shouldPlay {` → `GATE_GREP=1` 降到 `GATE_AFTER=0`（**变异自检：计数下降，否则判「变异没生效」**），`GATE_MUTATED_RC=1`；② 把该门控换成恒真 → `XCTAssertEqual failed: ("1") is not equal to ("0")`，**红灯来自断言失败而非编译失败**（W-17 同类反模式的规避）。两次恢复后 `cmp -s` 均与备份逐字节一致 |
| 幂集仲裁 | `swift test` | `HoldArbiterTests` | 6 个 `HoldReason` case → 运行时生成 **64** 组子集，逐组断言 |
| 锁屏接线（合成通知，仅 03-01 的脚手架前缀） | `bash scripts/probe-lock.sh` | `evidence/lock-wiring.log` | `LOCK_START_SYNC_DELIVERED=1 locked=1`；`LOCK_HOLD_APPLIED holds=(screenLocked) resumeAt=42.000`；`LOCK_RESUME seeks_to_anchor=1 seeks=42.000 holds=(none)`；`LOCK_ANCHOR_PRESERVED=1 seeks=42.000`；`LOCK_SIGNAL_INJECTED_COUNT=2` |
| 熄屏 / 睡眠信号 | `bash scripts/probe-display.sh` | `evidence/display-sleep-signals.log` | `DISPLAY_START_SYNC_DELIVERED=1 displayAsleep=1 systemSleeping=0`；`CGDisplay_IS_ASLEEP=1`；`DISPLAY_SIGNALS_REGISTERED=1 … reconfig=1`；`DISPLAY_STOP_UNREGISTERED=1` |
| 电源信号 | `bash scripts/probe-power.sh` | `evidence/power-signals.log` | `POWER_START_SYNC_DELIVERED=1`；`POWER_SOURCE_VALUE=AC Power`；`IS_ON_BATTERY=0`；`BATTERY_HOLD enabled=0 verdict=0`；`INTERNAL_BATTERY_PRESENT=1`；`POWER_STOP_UNREGISTERED=1` |
| 全屏信号 | `bash scripts/probe-fullscreen.sh` | `evidence/fullscreen-signals.log` | `FULLSCREEN_VERDICT=0 reason=geometry_without_signal coverage=1.000 non_geometric=0`；`STYLEMASK_UNAVAILABLE=1 reason=not_a_key_in_CGWindowList_dictionary`；`WINDOW_DICT_KEY_COUNT=11`；`WINDOW_DICT_STYLE_KEY_COUNT=0` |

## 没跑过

| 项 | 为什么没跑 | 证据 |
|---|---|---|
| ① SC1 的真实全屏跃迁 + 刘海屏 / Chrome / 超宽屏三场景各一遍 | 本机无 Chrome、单屏（`SCREENS_COUNT=1`）、会话锁定。**不合成** `com.apple.screenIsLocked` 之外的系统跃迁去凑 | `fullscreen-signals.log:FULLSCREEN_TRANSITION=unobservable reason=session_locked CGSSessionScreenIsLocked=1`。三场景的几何基准只能对齐 Phase 1 的 `1.000/1.000/1.000` |
| ② SC2 的锁屏跃迁（lock → unlock） | 会话自始至终 `CGSSessionScreenIsLocked=1`，**没有边沿可等**。合成通知那条只验接线，不冒充真实跃迁 | `lock-wiring.log:LOCK_TRANSITION=unobservable reason=session_locked CGSSessionScreenIsLocked=1`；真实会话态见 `holds-live.log:LOCK_READ_RAW=LOCKED=1 KEYS=14` |
| ③ SC2 的熄屏跃迁与睡眠跃迁 | 显示器**已经是熄着的**（`CGDisplay_IS_ASLEEP=1`，`pmset displaysleep 5` 的稳态），点亮那一下没发生；系统睡眠被外部 `caffeinate -i -t 300` 挡着（`POWER_PREVENT_SYSTEM_SLEEP=1`） | `display-sleep-signals.log:DISPLAY_SLEEP_TRANSITION=unobservable` `:SYSTEM_SLEEP_TRANSITION=unobservable`（各带 `reason=session_locked CGSSessionScreenIsLocked=1 loginwindow_pid=489`）；`DISPLAY_RECONFIG_CALLBACKS_FIRED=0` |
| ④ SC1 的**反向**实测：全屏误暂停的复现率 | 观测到但**给不出稳定复现率**。装配后 `FullscreenDetector` 间歇性把 `.fullscreen` 置位；一次插桩观测（3 轮中 1 轮）读到 `DBG_SET after=fullscreen before=`，随后 5 轮复跑均未复现。**未为了让它非 0 去制造应用切换事件** | `evidence/fullscreen-falsepositive.log`；登记为 `W-2026-10-03-23`。成因属 03-02 的判定口径（Ghostty 恒覆盖 → `covering` 恒真，前台应用一变即误判），**不是本 plan 装配引入的回归** —— 装配前该 detector 从未 `start()` 过 |
| ⑤ SC3 的拔电源 / 插回电源 | 本机全程在 AC 上，需物理动作。**不制造** | `power-signals.log:POWER_TRANSITION=unobservable reason=requires_physical_unplug CGSSessionScreenIsLocked=1 loginwindow_pid=489 action=unplug_power_cord_required`；`PMSET_CROSSCHECK=Now drawing from 'AC Power'` |
| ⑥ SC2 的「解除后各自正确续播」的**活体**一跳 | 依赖 ②③ 的跃迁。锚点逻辑本身已由单测与 03-01 的合成路径证明（`LOCK_RESUME seeks_to_anchor=1 seeks=42.000`），但**真实跃迁下的续播**未观测 | `lock-wiring.log:LOCK_ANCHOR_PRESERVED=1`（合成路径）；真实跃迁无 |
| ⑦ 四个 Watcher 常驻的泄漏证据 | 需要长跑（Phase 7 的 20 轮休眠/唤醒 + 7 天）。本 Phase 只证明**注册与注销成对**：四个 `start()` 与四个 `stop()` 都在位，`LOCK_STOP`/`DISPLAY_STOP_UNREGISTERED=1`/`POWER_STOP_UNREGISTERED=1`/`FULLSCREEN_OBSERVERS_REMOVED=1` | `test.sh` 的「起播路径零播放器直连」等判据每次重验；泄漏证据交 Phase 7 |

## 逻辑可行但本 Phase 未测

| 项 | 逻辑依据 | 本 Phase 未测什么 |
|---|---|---|
| 锁屏 / 熄屏 / 睡眠 / 电池四类**跃迁**都能触发暂停 | 四个 Watcher 的 `start()` 同步重算已实测生效（`LOCK_START_SYNC_DELIVERED=1` / `DISPLAY_START_SYNC_DELIVERED=1 displayAsleep=1` / `POWER_START_SYNC_DELIVERED=1`），观察者也已注册（`DISPLAY_SIGNALS_REGISTERED=1 … reconfig=1`、`POWER_SOURCE_REGISTERED=1 runloop_source=1`、`FULLSCREEN_SIGNALS_REGISTERED=1 …`）。**本机独有的强事实**：屏幕锁着 + 显示器熄着，所以「启动即已处于 hold 中」这条**不需要等跃迁**就被活体 evidence 捕到了（`holds-live.log` 的 `holds=(screenLocked,displayAsleep)`） | 四条 `*_TRANSITION=unobservable`。跃迁投递路径本身（`com.apple.screenIsLocked` / `willSleep` / IOKit 电源源在**状态变化**时的投递）一次都没跑过 |
| 解除 hold 后从原处续播 | `HoldArbiter.set` 的锚点四步已由单测锁住（6 reason 逆序解除下 `seeks == [42.0]`），03-01 的合成路径也实测过 `LOCK_RESUME seeks_to_anchor=1 seeks=42.000` | 真实跃迁下的续播。合成通知**不冒充**真实系统跃迁 |
| Phase 5 的运行状态卡能显示「当前为什么暂停」 | `HoldStatus.summary` + 六个互不相同的 `uiLabel` 已就位并有单测（`testSixReasonsHaveDistinctChineseLabels` 断言两两不等且长度 ≥ 2）；活体 evidence 里打出 `PIC_HOLD_SUMMARY summary=锁屏,显示器熄屏 reasons=2` | **零渲染**。本 Phase 不 import SwiftUI / AppKit（`test.sh` 两条判据锁死）。真机上的显示效果属 Phase 5 |
| 四根 Watcher 线的强持有与生命周期 | 四个类型全部被 `AppDelegate` **强持有**（`let` 属性），`wiring()` 接四根线、`applicationWillTerminate` 摘四个 `stop()`，两侧成对 | 长跑期的实际泄漏量（Phase 7） |

## 假定依赖

| 项 | 假定内容 | 未验证之处 |
|---|---|---|
| 本机「锁屏会话」这一前提贯穿全 Phase | 假定采集期间会话锁着。`holds-live.log` 的 `LOCK_STATE_AT_START=1` 与 `LOCK_READ_RAW=LOCKED=1 KEYS=14` 支持它 —— **但该假定在本 plan 执行期间已被推翻四次**，见 `evidence/session-state-changed.log` | ⚠️ **本 plan 执行期间该前提被打破至少四次**：11:25 前后读到 `HAS_KEY=false KEYS=11`（未锁）、显示器 `ASLEEP=0`，产品实跑 `holds=(none) status=playing`。**未锁屏去制造它**，最终采集时前提自行恢复。若后续 Phase 引用本文件的活体读数，须知道会话状态在同一天内变过 |
| `FullscreenDetector` 的判定口径 | 假定 `verdict = nonGeometricActive && covering` 的误暂停方向可接受 | **本会话实测到反向误判**（`fullscreen-falsepositive.log`，3 轮中 1 轮）。装配前它在产品里结构上不可达，装配后可达。已登记 `W-2026-10-03-23`，**未改判定口径** —— 改它属 D-02 的架构决策，且需要真实跃迁样本 |
| `setRate` 在非零值时会把播放器拉起 | 假定 SDK 文档与本机实测成立。依据是 `AVPlayer.h:150` 明文 + 本机实测（pause 后置 rate=1.0 → `timeControlStatus` 0.25 秒内由 `.paused`(0) 变 `.playing`(1)） | 依据来自 Phase 1/2 的 SDK 阅读与一次实测，本 Phase 未重做该实测（本会话无可控的播放器对象）。门控本身已由 `testSetRateOnStartPathIsGatedByShouldPlay` 的两次变异 + 活体 `status=paused` 证明成立 |
| 屏幕锁着时壁纸「应当」是暂停的 | 假定 D-09 的单向流语义：Watcher 产 reason，仲裁器决定，播放端执行 | 活体 evidence 证明**已 hold 时播放器确实是 `paused`**（7/7 条 `TICK`），但没有证明「解锁后会自动恢复」—— 那需要 ② 的跃迁 |

## 承接 WINDOWS.md 的 Phase 3 窗口

`W-2026-10-03-14` ~ `-19` 由 03-01 / 03-02 / 03-03 / 03-04 登记，本 plan **未改动其正文**，只在下表承接。
`-20` ~ `-23` 由本 plan 登记（分配表见 `WINDOWS.md` 的「Phase 3 的 W 编号分配表」）。

| 窗口 | 本 Phase 的动作 | 状态 |
|---|---|---|
| `-14` `HoldReason.order` 与 Phase 2 注释撞值 | 未改动。`testOrderValuesAreDistinctAndManualPauseStaysZero` 每次重验 | open（留档） |
| `-15` `PIC_LOCK_SIGNAL_PREFIX` 是脚手架 | 未改动，仍是全树唯一的锁屏信号脚手架 | open（Phase 5 可删） |
| `-16` 锁屏真实跃迁未观测 | `probe-lock.sh` 复跑，`LOCK_TRANSITION=unobservable` 依旧 | **open**（并入 `-20` 的逐条解开条件） |
| `-17` SYS-02 判据口径改为排除式 | **未改回**。`test.sh` 的两条排除式判据仍在，且已挂进本 plan 的四探针判据段 | open（留档） |
| `-18` D-02 语义降级 | 未改动。SC1 的结论已按该降级写成 `PARTIAL` | open（SC1 缺口） |
| `-19` 两条 deviation（A…E） | 未改动正文。描述 E 的**号段治理**由本 plan 收口：见下 | open（描述 A…D 仍未解） |
| **`-20` 四类跃迁未观测（本 plan 新登记）** | 合并登记锁屏 / 熄屏 / 睡眠 / 拔电源四类，逐条列解开条件 | **open** |
| **`-21` 起播设置落位必须门在 `shouldPlay` 后（本 plan 新登记）** | 已落地。`if arbiter.decision.shouldPlay {`（行 296）< `player.setRate(store.rate)`（行 297）；两次变异都转红；活体 `status=paused` 7/7 | **open**（留档防 Phase 4–7 清理） |
| **`-22` `W-2026-10-03-10` 直连 `player.player.play()`（本 plan 新登记）** | **已收口**：换成 `arbiter.applyCurrentDecision()`；剥注释后 `play()` / `pause()` 计数各 = 0；`applyCurrentDecision()` 出现在 `setVolume(` 之前（D-13 仍成立）；`applyCurrentDecision()` 不碰锚点（有独立单测） | **resolved** |
| **`-23` 全屏间歇性误暂停（本 plan 新登记）** | 观测到、量化了、**未改判定口径**（改它属 D-02 架构决策且无跃迁样本） | **open** |
| `W-2026-10-03-10`（Phase 2 登记的原始条目） | 风险描述「已 hold 却先 play 一下」**已不成立**，由 `-22` 以 `resolved` 承接 | **resolved** |

`-19` 描述 E 点名的号段冲突已按「不新建第二个 `-19`、不改动既有正文」处置：
`-20` ~ `-23` 由本 plan 独占，`grep -oE '^### W-2026-10-03-[0-9]+' | sort | uniq -d` 输出为空。

## Phase 3 的 7 个 requirement 覆盖对照

| ID | 交付 plan | 自动证据 |
|---|---|---|
| PAUSE-01 | 03-02 | `fullscreen-signals.log:FULLSCREEN_VERDICT=0 reason=geometry_without_signal coverage=1.000 non_geometric=0`；`FullscreenDetectorTests` 4 条 + `FullscreenGeometryTests` 5 条 |
| PAUSE-02 | 03-02 | 同上（续播锚点由 `HoldArbiterTests` 6 条共同覆盖） |
| PAUSE-03 | 03-03、**03-05** | `display-sleep-signals.log:DISPLAY_START_SYNC_DELIVERED=1 displayAsleep=1`；活体 `holds-live.log:holds=(screenLocked,displayAsleep)` 含 `.displayAsleep` |
| PAUSE-04 | 03-03、**03-05** | `display-sleep-signals.log:DISPLAY_SIGNALS_REGISTERED=1 sleep=NSWorkspaceWillSleepNotification wake=NSWorkspaceDidWakeNotification`；`systemSleeping` 未在本会话置位（睡眠跃迁未观测） |
| PAUSE-05 | 03-04 | `power-signals.log:BATTERY_HOLD enabled=0 verdict=0`；`SettingsStore.pauseOnBattery` 纯追加、默认 `false` |
| PAUSE-06 | **03-05** | `HoldStatus.summary` + 六个互不相同的 `uiLabel`（`HoldStatusTests` 6 条）；活体 `PIC_HOLD_SUMMARY summary=锁屏,显示器熄屏 reasons=2`；`test.sh` 的 `State/` 零 SwiftUI / 零 AppKit 两条判据 |
| PAUSE-07 | **03-05** | `arbiter.applyCurrentDecision()` 计数 = 1 且在 `setVolume(` 之前；剥注释后 `player.player.play()` / `pause()` 各 = 0；四个 `arbiter.set(.<reason>` 各 ≥ 1 |

## 交给下一阶段必须处理什么

**Phase 4 内（不阻塞）**

1. **`-20` 的四类跃迁**：解锁会话后各跑一次 `bash scripts/probe-lock.sh` / `probe-display.sh` / `probe-power.sh`。
   脚本无需修改（`-22` 收口时修过 `probe-lock.sh` 的源码清单，见「本 Phase 修的两处」）。
2. **`-23` 的全屏误暂停**：需要真实跃迁样本才能改判定口径。**改它之前先重跑 `bash scripts/probe-fullscreen.sh`**
   采一份「真实进入全屏时的信号长什么样」，否则会在没有证据的情况下改架构。

**Phase 5 内**

3. **运行状态卡接 `HoldStatus.summary`** —— 零渲染的约束到 Phase 5 结束。`HoldArbiter.holdStatus` 是唯一入口，
   UI 侧**不得**另存一份 `reasons`（T-02-08 的同类问题）。
4. **`PIC_LOCK_SIGNAL_PREFIX` 脚手架（`-15`）可在 Phase 5 删除** —— XCUITest 到位后不再需要合成锁屏通知。

**Phase 7 内**

5. **20 轮休眠/唤醒 + 7 天长跑**：四个 Watcher 常驻的泄漏证据、`willSleep` 的投递延迟、长跑期的误暂停率都在那里。
6. **`test.sh` / `run-probe.sh` 的口径在 Phase 7 收口** —— 本 plan 给 `test.sh` 加了 6 项、
   给 `run-probe.sh` 加了 `holds` 子命令，两处都会被后续 Phase 复用。

## 本 Phase 修的两处（不在计划任务清单里，都是实测发现的）

1. **`scripts/probe-lock.sh` 的源码清单漏了 `HoldStatus.swift`**（Rule 3 · blocking）。
   本 plan 给 `HoldArbiter` 加了返回 `HoldStatus` 的 `holdStatus` 之后，该脚本因
   手写的 `SRC=` 清单未同步而编译失败（`PROBE_COMPILE_RC=1`），并把日志清空 ——
   **判据会静默变成假绿**。已在脚本里补上并写明「新增/删除 `State/` 下的文件时必须同步改这里」。
   另三个探针脚本不经 `HoldArbiter`，未受影响（逐个核对过 `SRC=` 清单）。
2. **计划 AC 的两条期望值与实测不符，按实际读数记录、未改产品**：
   ① AC 期望 `PIC_HOLD active=1 reason=screenLocked holds=(screenLocked)`，实测是
   `holds=(screenLocked,displayAsleep)` —— 会话锁着**且**显示器已熄，两个真实 reason 同时成立；
   ② AC 期望 `PIC_HOLD_SUMMARY summary=锁屏 reasons=1`，实测 `summary=锁屏,显示器熄屏 reasons=2`。
   **没有为了凑单 reason 去改产品**，两个 reason 都是真实读数（`CGDisplay_IS_ASLEEP=1`）。

## 复现命令

```bash
swift build
swift test                                    # Executed 67 tests, with 0 failures
bash test.sh                                  # 通过 50  失败 0  跳过 0
bash scripts/run-probe.sh holds               # → evidence/holds-live.log（12 秒窗口）
bash scripts/probe-lock.sh                    # → evidence/lock-wiring.log
bash scripts/probe-fullscreen.sh              # → evidence/fullscreen-signals.log
bash scripts/probe-display.sh                 # → evidence/display-sleep-signals.log
bash scripts/probe-power.sh                   # → evidence/power-signals.log
```