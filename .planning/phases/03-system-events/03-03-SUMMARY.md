---
phase: 03-system-events
plan: 03
subsystem: system-events
tags: [display-watcher, pause-03, pause-04, d-01, d-09, d-11, d-15, t-03-10, t-03-11, t-03-12, t-03-13, test-03-03]
status: complete

requires: [PAUSE-03, PAUSE-04]
provides:
  - DisplaySignals（两字段）+ 显式 init —— 熄屏与睡眠是两条各自独立的 reason
  - DisplayWatcher：CGDisplayIsAsleep 现读 + 重配置回调 + willSleep/didWake 通知对
  - 唯一重算出口 re-evaluate()：睡眠、唤醒、重配置三个入口全部汇入它（Pitfall 7）
  - start() 的同步重算契约（装配层启动依赖，由本 plan 拥有）
  - SystemDisplayReconfigurationHook + DisplayReconfigurationHook 协议（注入缝，使「重配置 → 重算」可单测）
  - 本机实测：显示器此刻就是熄着的 —— CGDisplayIsAsleep=1，loginwindow_pid=489
  - scripts/probe-display.sh + evidence/display-sleep-signals.log（20 行）
depends_on: [03-01]
affects: [03-05]

tech-stack:
  added: []
  patterns:
    - 启动即重算：四个 Watcher 各自拥有「start() 返回前把当前状态算一遍」这条契约，不许由装配层代为假设
    - 通知对驱动的唯一状态位：systemSleeping 由 willSleep/didWake 切换，不来自任何采样（T-03-11）
    - C 函数指针 → Swift 闭包的桥用全局表；注册本来就是进程级的，表正好对上真实语义
    - 判据的反向验证必须能编译 —— 编译失败冒充判据转红（W-2026-10-03-17 已点名）

key-files:
  created:
    - Sources/PicCore/System/DisplayWatcher.swift
    - Tests/PicCoreTests/DisplayWatcherTests.swift
    - .planning/spike/DisplayWatcherDriver.swift
    - scripts/probe-display.sh
    - .planning/phases/03-system-events/evidence/display-sleep-signals.log
  modified:
    - .planning/WINDOWS.md

decisions:
  - DisplaySignals 带显式 init（不是编译器合成的 memberwise init）——
    否则把 displayAsleep 换成计算属性会让构造点一起编译不过，反向验证就只剩「编译失败」这一种红法
  - 重配置回调走协议注入缝 DisplayReconfigurationHook：真机实现仍调 CGDisplayRegisterReconfigurationCallback，
    但单测不必真拔一次线就能打同一条路径
  - C 回调不假设投递线程：一律 DispatchQueue.main.async + MainActor.assumeIsolated，不在 C 边界做隔离假设
  - 威胁模型 T-03-10 的「回调绑定在 CGMainDisplayID() 上」按 SDK 实测改写（该函数没有 display 参数）→ W-19
  - 探针汇总行改名 DISPLAY_RECONFIG_FIRED_LINE_COUNT：原先叫 ..._COUNT=1，读起来像「回调触发了 1 次」，
    而实测是 0 次 —— 证据文件里的数字不能有第二种读法
  - 两个跃迁如实各记一行 unobservable，且附上 pmset 现读（PreventUserIdleSystemSleep=1，
    外部 caffeinate 正挡着系统睡眠）而不是只写「屏幕锁着」

metrics:
  duration: 990s
  completed: 2026-10-03
  tasks: 2

actuals:
  tokens: 11400
  tasks: 2
  commits: 3

commits: 3
plan_head_before: 8ff99cceffcbf24f9cb93cf67f45ce70399a2b21
plan_head_after: 95837bdaa1dcf6f1f23b1b2445e60e5c4a0416b9
---

# Phase 3 Plan 03: 熄屏与睡眠 —— 两条独立 reason，一个重算出口 Summary

**本机此刻显示器就是熄着的**（`CGDisplay_IS_ASLEEP=1`，实测）—— 所以「启动即重算」这条契约在本机不是形式主义：只等跃迁的实现会永远看不到这一位。

## What was built

**`DisplaySignals` + `DisplayWatcher`，一个类型带两个 reason。** 拆成两个类型会让「暂停与恢复走同一个 `re-evaluate()`」（PITFALLS Pitfall 7）写两遍，两遍迟早漂移。文件头写明了这个理由。

**两个 reason 各自独立。** `start` 的 `onChange` 传 `DisplaySignals`，接线方拆成两次 `set` —— 文件内**不出现仲裁器的类型名**（剥注释后计数 0，D-09）。`displayAsleep` 每次重算都**现读** `CGDisplayIsAsleep(CGMainDisplayID())`；`systemSleeping` 只由 `willSleep` / `didWake` 这一对通知切换，是内存里**唯一**的状态字段（文件头注明它不来自任何采样 —— T-03-11）。

**唯一重算出口。** 三个入口 —— 重配置回调、`willSleep`、`didWake` —— 全部汇入私有 `re-evaluate()`，回调里不直接写 `onChange`。否则唤醒路径与暂停路径不对称（Pitfall 7 点的正是这个）。

**重配置回调可摘除。** `stop()` 走 `CGDisplayRemoveReconfigurationCallback`（剥注释后计数 1）；两个 `NSWorkspace` token 存数组逐个摘。`testStartRecomputesOnceSynchronously` 断言 `unregisterCount == 1`。

**注入缝。** `DisplayReconfigurationHook` 协议 + `SystemDisplayReconfigurationHook`（真机，真调 CoreGraphics）。真拔一次线才能验的路径，现在单测可以打；真机实现一个字符没退化成 mock。

**零 AVFoundation、零 player、零定时器。** 剥注释后（`test.sh` 那 4 条 `-e`）`AVFoundation|AVPlayer|HoldArbiter` 计数 **0**，`Timer` 计数 **0**（D-01 的逐帧轮询没有复活）。

## Verification actually run

| 项 | 结果 |
|---|---|
| `swift build` | RC=0 |
| `swift test --filter DisplayWatcherTests` | **`Executed 5 tests, with 0 failures`** |
| 反向验证（注入耦合后重跑） | RC=**1**，失败列表含 `testWakingWithDisplayStillAsleepDoesNotResume` |
| 恢复后 `cmp -s` | 与备份**逐字节**一致 |
| `perl scripts/probe-display.sh`（外层再套 alarm） | **RC=0** |
| evidence 七条判据 | 七条 `grep -c` 全 **1** |
| evidence 行数 / 媒体路径 | **20 行** / `fixtures/｜/Users/｜.mp4` 计数 **0** |

⚠️ 本 plan 在 wave 2 与 03-02 / 03-04 并行且共用同一 `.build/`（W9），按计划只跑 `--filter DisplayWatcherTests`，**未**跑全量 `swift test`、**未**跑 `bash test.sh`。全量校验归 03-05。

### 反向验证：把两个 reason 耦合 → 独立性用例必须转红

```
perl -0pi -e 's/self\.displayAsleep = displayAsleep/self.displayAsleep = systemSleeping   \/\/ MUTATION/' DisplayWatcher.swift
```

`MUTATION_COUNT=1`（`perl` 确实改到了，不是没匹配上）→ `swift test --filter DisplayWatcherTests` **RC=1**，失败行：

```
DisplayWatcherTests.swift:136: error: -[... testWakingWithDisplayStillAsleepDoesNotResume] :
  XCTAssertEqual failed: ("[]") is not equal to ("[PicCore.HoldReason.displayAsleep]")
  - 唤醒只解除 systemSleeping —— 熄屏仍在，holds 不得被覆盖成空集
DisplayWatcherTests.swift:138: error: ... : XCTAssertFalse failed - 熄屏仍在 → 一律不播
DisplayWatcherTests.swift:139: error: ... : XCTAssertTrue failed - 唤醒那一瞬不得有任何 seek
```

恢复后 `cmp -s` 一致 → 重跑回到 `Executed 5 tests, with 0 failures`。

### `evidence/display-sleep-signals.log`（20 行，全文）

```
DISPLAY_START_SYNC_DELIVERED=1 displayAsleep=1 systemSleeping=0
DISPLAY_SIGNALS_REGISTERED=1 sleep=NSWorkspaceWillSleepNotification wake=NSWorkspaceDidWakeNotification reconfig=1
MAIN_DISPLAY_ID=1
CGDisplay_IS_ASLEEP=1
DISPLAY_SIGNALS displayAsleep=1 systemSleeping=0
SESSION_LOCKED=1 loginwindow_pid=489 session_keys=14
POWER_SOURCE=AC Power
POWER_SLEEP_DISABLED=0
POWER_DISPLAYSLEEP_MINUTES=5
POWER_PREVENT_SYSTEM_SLEEP=1
POWER_PREVENT_DISPLAY_SLEEP=0
DISPLAY_RECONFIG_WINDOW_SECONDS=4
DISPLAY_RECONFIG_CALLBACKS_FIRED=0
DISPLAY_SLEEP_TRANSITION=unobservable reason=session_locked CGSSessionScreenIsLocked=1 loginwindow_pid=489
SYSTEM_SLEEP_TRANSITION=unobservable reason=session_locked CGSSessionScreenIsLocked=1 loginwindow_pid=489
DISPLAY_DELIVERY_COUNT=1
DISPLAY_STOP_UNREGISTERED=1
PROBE_DRIVER_RC=0
DISPLAY_RECONFIG_FIRED_LINE_COUNT=1
DISPLAY_LOG_LINES=18
```

### 计划断言在本机事实上不成立的三处（已登记 W-2026-10-03-19）

**① 威胁模型 T-03-10 的「回调绑定在 `CGMainDisplayID()` 上」不成立。**
`CGDisplayConfiguration.h:235` 的真实声明是

```c
CGError CGDisplayRegisterReconfigurationCallback(
    CGDisplayReconfigurationCallBack __nullable callback,
    void * __nullable userInfo)
```

**没有 display 参数**，注册与摘除都是**进程级**的。实测 `REGISTER_RC=0 success=true`、`REMOVE_RC=0`。
`PLAN_DEVIATION=` 实现按真实签名走（一张全局表，正对上进程级语义）。**不变量没变**：摘不掉仍是进程内永久泄漏，注册与注销必须严格配对。

**② 计划 `<verify>` 的注入 perl 在本仓的代码形状下无法编译。**
原 perl 把 `public var displayAsleep: Bool` 换成 `Bool { systemSleeping }`。`DisplaySignals` 必须有显式 `init`（否则 `currentSignals()` 构造不出两个字段的值），而该 init 里的 `self.displayAsleep = displayAsleep` 对计算属性赋值是**编译错误** —— 编译失败冒充「判据转红」，正是 W-2026-10-03-17 点名过的反模式。
`PLAN_DEVIATION=` 把耦合点从**字段声明**移到 **init 赋值体**。计划 `<action>` 第 6 条本来就给了两个可选口径（「把两个字段合并成一个共用字段**或**把仲裁侧改成一次性清空两个 reason 的语义」），取编译得通的那一个。**判据的意图、目标用例名、AC 里的机器判据，一个字没改**；改的只是注入点，且新注入点**能编译**（已实测 `MUTATED_RC=1` 来自断言失败，不是编译失败）。

**③ 计划 AC 写「`start` 函数体里有对 `currentSignals()` 的调用」。**
实现里 `start()` 调的是 `re-evaluate()`，而 `currentSignals()` 在 `re-evaluate()` 里 —— 这是 Pitfall 7 的「唯一重算路径」要求的形状，直接内联进 `start()` 就多出第二条读值路径。
机器判据 `grep -c 'currentSignals()'` 实测 **2**，未放宽；行为判据 `testStartRecomputesOnceSynchronously` 未放宽且通过。**改的是 AC 的措辞，不是判据。**

### 两行 unobservable：附的是现读数，不是「屏幕锁着」四个字

计划要求引用 `lock-state.txt`。本 plan 额外把电源 / 显示器状态**现读**打进去，因为「锁屏 ≠ 熄屏 ≠ 睡眠」这三件事在本机恰好各不相同：

- `SESSION_LOCKED=1` `loginwindow_pid=489` —— 与 `lock-state.txt` 的 `LOCKED=1` / `LOGINWINDOW_PID=489` 一致
- `CGDisplay_IS_ASLEEP=1` —— **显示器此刻是熄着的**（不是假设，是读数）
- `POWER_PREVENT_SYSTEM_SLEEP=1` —— 外部 `caffeinate -i -t 300` 正挡着系统睡眠
- `POWER_PREVENT_DISPLAY_SLEEP=0` + `POWER_DISPLAYSLEEP_MINUTES=5` —— 显示器睡眠**没有被**任何断言挡住，所以它真的睡了
- `DISPLAY_RECONFIG_CALLBACKS_FIRED=0` —— 4 秒观察窗内 0 次。**如实打 0，没有为了让这个数非 0 去制造任何事件**

### 未实测 / 未证明的（不冒充已验证）

| 项 | 状态 | 解开条件 |
|---|---|---|
| 熄屏跃迁（亮 → 灭） | `unobservable` | 解锁会话重跑 `bash scripts/probe-display.sh`（约 10 秒，脚本无需修改） |
| 睡眠跃迁（睡 → 醒） | `unobservable` | 同上；系统睡眠还被外部 `caffeinate` 断言挡着 |
| `willSleep` 的投递延迟 | 未实测 | `queue: .main` 是异步投递，与进程真正进入睡眠的间隔量不到 → Phase 7 的 20 轮 |
| 真实跃迁触发暂停 / 唤醒后立刻恢复 | 未证明 | 与 W-2026-10-03-16（锁屏跃迁）同批 |

**已证明的接线部分**：`start()` 的同步重算**实测生效** —— `DISPLAY_START_SYNC_DELIVERED=1 displayAsleep=1` 打在任何时间流逝、任何通知之前；三个入口注册成功（`reconfig=1`，两个通知名 rawValue 与计划 AC 逐字相同）；`stop()` 摘掉回调（`DISPLAY_STOP_UNREGISTERED=1`）。

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] 探针汇总行名会产生第二种读法。**
脚本原本追加 `DISPLAY_RECONFIG_FIRED_COUNT=1`（`grep -c` 的**行数**）。同一份日志里真实值是 `DISPLAY_RECONFIG_CALLBACKS_FIRED=0` —— 两个数挨着，`..._COUNT=1` 会被读成「回调触发了 1 次」，而实测是 0 次。
**改为** `DISPLAY_RECONFIG_FIRED_LINE_COUNT=1` 并在注释里写明两者不是同一个数。判据一个没动（只认 `^DISPLAY_RECONFIG_CALLBACKS_FIRED=[0-9]+$`）。

**2. [Rule 2 - 缺失的关键功能] `DisplaySignals` 缺显式 `init`。**
计划 `<output>` 的公开面只列了两个字段。但 `DisplaySignals` 必须能在字段被耦合时**仍然编译**，否则唯一能证明「独立性判据不是空判」的反向验证就退化成编译错误。按 `FullscreenSignals` 的既有形状补上显式 `init`。

**3. [Rule 2 - 缺失的关键功能] 重配置回调路径原本不可测。**
`CGDisplayRegisterReconfigurationCallback` 要 C 函数指针，产品代码没法注入。加 `DisplayReconfigurationHook` 协议做注入缝 —— 真机实现仍直调 CoreGraphics，**不是 mock**。

### PLAN_DEVIATION（判据未放宽，事实已更正）

见上「计划断言在本机事实上不成立的三处」。三条全部登记为 **W-2026-10-03-19**，附 SDK 头文件行号与实测 RC。

## Known Stubs

无。本 plan 新增的两个源文件与一个脚本里没有 `=[]` / `=null` / `TODO` / `FIXME` 形态的空实现，evidence 每行都有确切数字。

## Threat Flags

| Flag | File | Description |
|------|------|-------------|
| threat_flag: new-process-spawn | `.planning/spike/DisplayWatcherDriver.swift` | throwaway 驱动用 `Process` 跑 `/usr/bin/pmset`（`-g` / `-g batt` / `-g assertions`）与 `/usr/bin/pgrep -x loginwindow`。三条都是**只读、无副作用、不写盘**的命令，输出只被解析成布尔量 / 电源键值 / pid 后再落 evidence（原始 `pmset` 文本一行不打进去，含路径的 `hibernatefile` 之类不会漏）。计划威胁模型未列这一条 —— 记在这里，因为它是本 plan 新引入的进程边界 |
| threat_flag: global-callback-table | `Sources/PicCore/System/DisplayWatcher.swift` | `reconfigHandlers` 是一张进程级全局表，锁保护。真实 API 本身就是进程级注册（见 W-19），所以这张表的粒度是对的；但若将来有多屏差异化需求（每个 `CGDisplayID` 各自的回调），这张表要先扩成按 display 索引 —— 当前实现**不**区分屏 |

## Self-Check: PASSED

- `Sources/PicCore/System/DisplayWatcher.swift` —— FOUND
- `Tests/PicCoreTests/DisplayWatcherTests.swift` —— FOUND
- `.planning/spike/DisplayWatcherDriver.swift` —— FOUND
- `scripts/probe-display.sh` —— FOUND
- `.planning/phases/03-system-events/evidence/display-sleep-signals.log` —— FOUND（20 行）
- commits `2554154` / `b928cb8` / `95837bd` —— 全部 FOUND（`git log --oneline`）
- `STATE.md` / `ROADMAP.md` —— **未改动**（本 plan 由编排器持有这两处写入）
