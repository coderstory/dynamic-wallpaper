---
phase: 03-system-events
plan: 04
subsystem: system-events
tags: [power-watcher, pause-05, d-01, d-09, d-11, d-15, t-03-14, t-03-15, t-03-16, t-03-17, test-03-04]
status: complete

requires: [PAUSE-05]
provides:
  - BatteryHoldPolicy.shouldHold(isOnBattery:pauseOnBatteryEnabled:) —— PAUSE-05 的唯一判定处，纯函数
  - PowerReadState 三态（onBattery / onAC / failed）——「读不到」有它自己的名字，不再折成 false
  - PowerWatcher：IOKit ps 读数 + IOPSNotificationCreateRunLoopSource，start() 同步读一次
  - SettingsStore.pauseOnBattery（默认 false，纯追加）+ Key.pauseOnBattery（第七键）
  - 本机实测：有内置电池（MacBook Air M5）、runloop_source=1、POWER_CALLBACKS_FIRED=0
  - scripts/probe-power.sh + evidence/power-signals.log（18 行）
depends_on: [03-01]
affects: [03-05]

tech-stack:
  added: []
  patterns:
    - 判定抽成纯函数，Watcher 只报事实：拔电源做不到，但两个 Bool 的四种组合谁都能注入
    - 三态读数：读失败不折值（T-03-16），上报与返回值共用同一次读取
    - Unmanaged 原件 + @_silgen_name 的显式 CFRelease：注册与释放严格配对，两个字面量都可被 grep 到

key-files:
  created:
    - Sources/PicCore/System/PowerWatcher.swift
    - Tests/PicCoreTests/PowerWatcherTests.swift
    - .planning/spike/PowerWatcherDriver.swift
    - scripts/probe-power.sh
    - .planning/phases/03-system-events/evidence/power-signals.log
  modified:
    - Sources/PicCore/State/SettingsStore.swift
    - Tests/PicCoreTests/SettingsStoreTests.swift
    - .planning/WINDOWS.md

decisions:
  - shouldHold 的实现体用显式 return 而不是单表达式 —— 计划的反向验证 perl 找的是 `return isOnBattery$`
  - 注释里**不**写出合取式的字面量形式：反向验证用整文件首次替换，注释里抄一遍会让它落在注释上（D-07）
  - 电源源与描述字典走 NSArray / NSDictionary 桥，而不是 CFArray 的 UnsafeRawPointer 路径
  - IOPSGetPowerSourceDescription 返回 **unretained**（IOPowerSources.h:303 明写不该 release），用 takeUnretainedValue
  - run loop source 持有 Unmanaged 原件而非 takeRetainedValue —— 释放必须是显式的那一次（T-03-15）
  - POWER_TRANSITION 的 reason 写 requires_physical_unplug，不写 session_locked（拔电源与锁屏无关）
  - 回调次数与总投递数分成两行打点（POWER_CALLBACKS_FIRED / POWER_DELIVERY_COUNT / POWER_START_SYNC_DELIVERIES）

metrics:
  duration: 780s
  completed: 2026-10-03
  tasks: 2

actuals:
  tokens: 21000
  tasks: 2
  commits: 3

commits: 3
plan_head_before: 9e45d748300d1cdbbd85f4a6bb380a99aa904102
plan_head_after: 2814a574097e2b0500414490efd5a64ad9344320
---

# Phase 3 Plan 04: 电池供电 —— 默认关闭是纯函数里的第二项合取 Summary

**本机是 MacBook Air M5，有内置电池**（`INTERNAL_BATTERY_PRESENT=1`，实测 `sysctl hw.model` = `Mac17,3`）。PAUSE-05 的活体路径**硬件可达**，走不通的只有「拔电源」这个需要人在场的动作本身。

## What was built

**`BatteryHoldPolicy` 是 PAUSE-05 的唯一判定处，纯函数，两个输入都可注入。** 拔电源是硬件动作本会话做不到，但 `shouldHold(isOnBattery:pauseOnBatteryEnabled:)` 的四种组合谁都能测 —— 判定逻辑因此 100% 可测，被 `testPolicyHoldsOnlyWhenEnabledAndOnBattery` 四行锁死，其中 `true,false → false` 就是 D-11 的核心那一行。

**`PowerWatcher` 只报事实，不做策略。** 它产出一个 `Bool`（是否在电池上），不出现 `SettingsStore`、不出现 `HoldArbiter`、不出现 `AVFoundation`（剥注释后三者计数 **0**）。判据用 `test.sh` 那 4 条 `-e` 的过滤器实测，不是裸 `grep -c`。

**三态读数，「读不到」有它自己的名字。** `PowerReadState.failed` 不折成 `false`：折成「在电池上」会无故暂停（用户看得见的坏事），折成「在 AC 上」会漏暂停，两个方向都是用户可见的行为变化。上报与返回值**共用同一次读取**，不存在「打点时的状态」与「返回给调用方的状态」分属两次读取的缝。

**事件驱动，零定时器。** `IOPSNotificationCreateRunLoopSource` 挂主 run loop，回调里**重读**当前状态（与 `LockWatcher` / `DisplayWatcher` 同形：信号只当触发器，状态一律现读）。剥注释后 `Timer` 计数 **0**。

**`start()` 同步读一次。** 电源状态**当下可读**，不像锁屏 / 熄屏要等跃迁。`POWER_START_SYNC_DELIVERED=1` 打在任何时间流逝之前 —— 少这一次，在电池上启动的机器会一直不产生 hold 直到下次拔插。

**`SettingsStore` 纯追加，既有 6 字段 / 6 键 / 6 行 persist 一字未改。** `testExistingSeedCallSitesStillCompile` 用**位置无关的具名传参**把这条锁住；将来谁把 `pauseOnBattery` 插进既有参数中间，那里立刻编译不过。

## Verification actually run

| 项 | 结果 |
|---|---|
| `swift build` | RC=**0**，零 warning |
| `swift test --filter 'PowerWatcherTests\|SettingsStoreTests'` | **`Executed 19 tests, with 0 failures`**（SettingsStore 13 + PowerWatcher 6；计划要求 n ≥ 13） |
| 反向验证（`shouldHold` 忽略开关） | `MUTATED_RC=**1**`，两条目标用例**都**转红 |
| 恢复后 `cmp -s` | `PowerWatcher.swift` 与 `SettingsStore.swift` 均与备份**逐字节**一致 |
| `bash scripts/probe-power.sh`（外层套 alarm 120） | **RC=0** |
| evidence 判据 | 17 条全 **1**，`POWER_EVIDENCE_OK` |
| evidence 行数 / 媒体路径 | **18 行** / `fixtures/｜/Users/｜.mp4` 计数 **0** |
| `POWER_TRANSITION` 在 `POWER_CALLBACKS_FIRED` 之后 | **OK**（第 14 行 vs 第 10 行） |

⚠️ 本 plan 在 wave 2 与 03-02 / 03-03 并行且共用同一 `.build/`（W9），按计划只跑 `--filter` 自己的两个 suite，**未**跑全量 `swift test`、**未**跑 `bash test.sh`。全量校验归 03-05。

### 反向验证：忽略开关 → D-11 那两行必须转红

```
perl -0pi -e 's/isOnBattery && pauseOnBatteryEnabled/isOnBattery/' PowerWatcher.swift
```

`MUT=1`（签名匹配上）、`VER=1`（`return isOnBattery$` 确实出现了）→ `swift test --filter PowerWatcherTests` **RC=1**，失败行：

```
PowerWatcherTests.swift:60: error: testPolicyHoldsOnlyWhenEnabledAndOnBattery :
  XCTAssertFalse failed - 在电池上但开关关 → 不 hold（D-11：默认关闭）
PowerWatcherTests.swift:77: error: testDefaultSettingMeansBatteryNeverHolds :
  XCTAssertFalse failed - 默认设置下即便真在电池上也不得 hold
```

两条**都**红了 —— 不是只有一条。第二条（联合判据）才是真正锁住「开关真的接进了判定」的那条：只断第一条的话，一个把 `pauseOnBatteryEnabled: false` 硬写死的实现也能让它全绿，而真机上开关根本不起作用。

**第一次跑这轮判据时 `MUTATION_NOT_APPLIED`**：`perl` 的整文件首次替换落在了**我的注释上** —— 我在 `shouldHold` 的文档注释里抄了一遍合取式的字面量。那句注释什么都没改坏，判据却会转绿。这正是 D-07 点名的反模式（Phase 1 出现 5 次、Phase 2 出现 3 次「自己的判据被自己违反」）。**改的是注释，不是判据**：注释改成散文描述不变量，代码里的字面量留在实现体一行。**按 03-02 的做法：判据一个没放宽。**

### `evidence/power-signals.log`（18 行，全文）

```
POWER_START_SYNC_DELIVERED=1
POWER_SOURCE_REGISTERED=1 runloop_source=1
POWER_SOURCE_KEY=Power Source State
POWER_SOURCE_KEY_COUNT=17
POWER_SOURCE_VALUE=AC Power
IS_ON_BATTERY=0
BATTERY_HOLD enabled=0 verdict=0
INTERNAL_BATTERY_PRESENT=1
POWER_OBSERVE_WINDOW_SECONDS=4
POWER_CALLBACKS_FIRED=0
POWER_DELIVERY_COUNT=1
POWER_START_SYNC_DELIVERIES=1
POWER_STOP_UNREGISTERED=1
POWER_TRANSITION=unobservable reason=requires_physical_unplug CGSSessionScreenIsLocked=1 loginwindow_pid=489 action=unplug_power_cord_required
PMSET_CROSSCHECK=Now drawing from 'AC Power'
PROBE_DRIVER_RC=0
POWER_CALLBACK_FIRED_LINE_COUNT=1
POWER_LOG_LINES=16
```

### 计划 AC 的 API 字面值在本机 SDK 上不成立（四处）

`03-04-PLAN.md` 把 IOKit 电源源写成「字典键 `"AC Power"`（`kIOPSPowerSourceStateKey`）取 `CFBoolean` 值」。**两处都不成立**：

| 计划写的 | SDK 实测 | 依据 |
|---|---|---|
| 键 = `AC Power` | 键 = **`Power Source State`** | `IOPSKeys.h:311`：`#define kIOPSPowerSourceStateKey "Power Source State"` |
| 值 = `CFBoolean` | 值 = **`CFString`**（`AC Power` / `Battery Power` / `Off Line`） | `IOPSKeys.h:303`：「Type CFString」；`IOPSKeys.h:754-766` 三个取值 |

`"AC Power"` 是**取值**（`kIOPSACPowerValue`，`IOPSKeys.h:760`），不是键。**判据改的是「核对哪个字面量」，不是放宽判据** —— 真实键名与真实取值都逐字打进 evidence，而且键名是从 SDK 常量 `kIOPSPowerSourceStateKey` 读出来打的，不是手抄的字符串。

第三条：`POWER_TRANSITION` 的 `reason`。计划写死 `reason=session_locked`，但**拔电源的可达性与屏幕锁不锁无关** —— 屏幕锁着照样拔得动线，写「锁屏」是错的归因。本机确有内置电池（`INTERNAL_BATTERY_PRESENT=1`），所以实际原因写 `requires_physical_unplug`。

第四条：`IOPSGetPowerSourceDescription` 返回的是 **unretained** 指针（`IOPowerSources.h:303` 明写 "Caller should NOT release the returned CFDictionary"）。用 `takeRetainedValue()` 会多 release 一次 —— 实现改用 `takeUnretainedValue()`，并把这句依据写进注释。

### 一个数不能有两种读法（第一版的真实缺陷）

第一版把电源事件回调与 `start()` 的同步投递**合在一个计数器**里，结果 `POWER_CALLBACKS_FIRED=1`，而同一份日志 `POWER_DELIVERY_COUNT=1` 也是 1 —— 读起来像「电源回调触发了 1 次」。**实测是 0 次**（在 AC 上不动电源，IOKit 不投递任何回调）。

改成三行分开打点：`POWER_CALLBACKS_FIRED`（只数事件投递）、`POWER_DELIVERY_COUNT`（总投递）、`POWER_START_SYNC_DELIVERIES`（start() 那次，1）。**没有为了让这个数非 0 去制造任何事件。**

### 本机电池可行性：实测，不是假设

| 项 | 读数 | 来源 |
|---|---|---|
| 有没有内置电池 | **有** | `INTERNAL_BATTERY_PRESENT=1`；`sysctl hw.model` = `Mac17,3`（MacBook Air, M5） |
| 当前电源来源 | **AC** | `IS_ON_BATTERY=0`、`POWER_SOURCE_VALUE=AC Power`、`PMSET_CROSSCHECK=Now drawing from 'AC Power'` |
| `pmset` 与 IOKit 是否一致 | **一致** | 两处独立读到 `AC Power` |
| 电源源字典键数 | **17** | `POWER_SOURCE_KEY_COUNT=17` |

两条独立来源（IOKit 读数 / `pmset -g batt`）给同一个答案 —— 这是计划要求的交叉参考，真跑出来是相符的。

### 未实测 / 未证明的（不冒充已验证）

| 项 | 状态 | 解开条件 |
|---|---|---|
| **拔电源跃迁** | `unobservable` | **物理拔掉电源线**。用户在休息，本会话不做任何需要人在场的硬件操作。解锁条件已写进 `POWER_TRANSITION` 行的 `action=` 字段 |
| 插电源跃迁 | `unobservable` | 同上（反向动作） |
| 事件源**真在跃迁时**投递回调 | **未证明** | `POWER_CALLBACKS_FIRED=0` 只证明「没跃迁时它不乱投递」；**没有**证明「跃迁时它会投递」。这是 `runloop_source=1` 之外的另一半 |
| `stop()` 后事件源真的不再投递 | **未证明** | 同上，需要一次真实跃迁配合 `stop()` |
| `UNSAFE`/`Off Line` 第三态的映射 | 代码有（落 `failed`），**未实测** | 需要一台无电池的外接电源机器 |

**已证明的接线部分**：`start()` 同步读实测生效（`POWER_START_SYNC_DELIVERED=1` 打在任何时间流逝之前）；事件源挂上（`runloop_source=1`）；`stop()` 摘掉（`POWER_STOP_UNREGISTERED=1`）。

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] 反向验证的 perl 会打在注释上，判据形同虚设。**
第一次跑 `<verify>` 得 `MUTATION_NOT_APPLIED`。原因是 `perl -0pi` 的整文件**首次**替换命中了 `shouldHold` 文档注释里抄的合取式字面量，**代码一个字没改坏**。注释改成散文描述不变量，实现体改用显式 `return`（计划的判据找的是 `return isOnBattery$`）。**判据未放宽。**

**2. [Rule 1 - Bug] 电源回调计数与同步投递计数混成一个数。**
第一版 `POWER_CALLBACKS_FIRED=1` 会被人读成「回调触发了 1 次」，实测是 0 次。拆成三行分开打点。这与 03-03 的 `DISPLAY_RECONFIG_FIRED_COUNT` 是**同一个坑的第二次出现** —— 同一个数有两种读法，证据就假了。

**3. [Rule 2 - 缺失的关键功能] `CFRelease` 在 Swift 里不可用，`stop()` 的显式释放原本无法写出来。**
Swift 把 CF 对象交给 ARC，`CFRelease` 被标成 unavailable。计划要求「`stop()` 必须 `CFRelease` 掉 source」（T-03-15），`swift build` 却在 API 层面挡着。做法：持有 `IOPSNotificationCreateRunLoopSource` 返回的 **Unmanaged 原件**（不 `takeRetainedValue`，否则所有权交给 ARC、释放就变隐式），`stop()` 里用 `@_silgen_name("CFRelease")` 显式还**恰好一次**。已单独实测这个 shim 链接得上、跑得通、不双重释放。

**4. [Rule 2 - 缺失的关键功能] `PowerWatcher` 缺一个可单测的三态读数口。**
计划只给了 `currentIsOnBattery() -> Bool`。但「读不到」与「在 AC 上」折成同一个 `false` 会抹掉一次真实的读数失败 —— T-03-16 要求「读失败绝不静默折值」，一个 `Bool` 的返回口做不到。补 `PowerReadState` 三态 + `currentPowerSourceStateValue()` + `currentPowerSourceKeys()`（供探针逐字打印，不手抄）。

### PLAN_DEVIATION（判据未放宽，事实已更正）

四条 IOKit 字面值更正，见上「计划 AC 的 API 字面值在本机 SDK 上不成立（四处）」。**判据的核对对象改成了真实字面量，核对得更严**：键名从 SDK 常量读出来打，取值是三态字符串而不是 `true|false`，跃迁原因按硬件事实写而不是照抄计划的锁屏。

### 第五条 PLAN_DEVIATION：W 编号段本身冲突

`03-05-PLAN.md` 第 293 行写「`-19` 归 03-04」，而 **`03-03` 在 wave 2 里已经用掉了 `### W-2026-10-03-19`**。同一个号被两个 plan 各自声明。且 03-05 的另一条 AC 要求 `grep -oE '^### W-2026-10-03-[0-9]+' | sort | uniq -d` 的输出**为空**（每个编号只出现一次）—— 两条 AC 在事实上互斥。

**纠正**：不新建第二个 `-19` 标题，把本 plan 的两条追加进**这一个** `-19` 条目（描述 D / E），标题改为 `Phase 3 / Plan 03-03 + 03-04`。理由：① `uniq -d` 为空是 03-05 的硬判据，新建标题当场让它转红；② 本 plan 自己那条 AC 要求「该号不被 03-01/02/03/05 复用」—— 被 03-03 复用是**既有事实**，删 03-03 的条目等于改别的 plan 的产物；③ 号段表写在 03-05 里，实际取号是各 plan 各自进行 —— 真正的错在号段表发布得太晚。**改的是登记的归口，不是判据。**

实测 `uniq -d` 计数 = **0**。

## Known Stubs

无。新增的源文件 / 测试 / 脚本 / driver 里没有 `=[]` / `=null` / `TODO` / `FIXME` 形态的空实现；evidence 每行都有确切数字或确切字面量。

## Threat Flags

| Flag | File | Description |
|------|------|-------------|
| threat_flag: underscored-attribute | `Sources/PicCore/System/PowerWatcher.swift` | `@_silgen_name("CFRelease")` 是下划线开头的属性。选它是因为 Swift 已把 CF 交给 ARC、公开的 `CFRelease` 被标成 unavailable，而 T-03-15 要求**显式**的那一次释放（`Unmanaged.release()` 会与 ARC 的那次重复）。已单独实测链接与运行。Swift 若移除该属性，本文件会编译失败 —— 失败是响的，不是静默的 |
| threat_flag: process-spawn | `.planning/spike/PowerWatcherDriver.swift` | throwaway 驱动用 `Process` 跑 `/usr/bin/pmset -g batt` 与 `/usr/bin/pgrep -x loginwindow`。两条都是**只读、无副作用、不写盘**的命令；`pmset` 只取首行贴进 `PMSET_CROSSCHECK`（不含 `hibernatefile` 之类带路径的行）。计划威胁模型未列这一条 |

## Self-Check: PASSED

- `Sources/PicCore/System/PowerWatcher.swift` —— FOUND
- `Tests/PicCoreTests/PowerWatcherTests.swift` —— FOUND
- `Sources/PicCore/State/SettingsStore.swift` —— FOUND（六个既有键全在）
- `Tests/PicCoreTests/SettingsStoreTests.swift` —— FOUND
- `.planning/spike/PowerWatcherDriver.swift` —— FOUND
- `scripts/probe-power.sh` —— FOUND
- `.planning/phases/03-system-events/evidence/power-signals.log` —— FOUND（18 行）
- `.planning/WINDOWS.md` 含 `W-2026-10-03-19` —— FOUND（`uniq -d` 计数 = 0）
- commits `298aabc` / `9b9489e` / `2814a57` —— FOUND（`git log --oneline`）
- ⚠️ `plan_head_after` 指向 `2814a57`（内容树的最后一次提交），**不含**本文件自身的收尾提交 ——
  frontmatter 里写自己的 sha 是自引用：写进去就改 sha，改 sha 又要改文件，永远收敛不了。
  「本 plan 的代码 + evidence + SUMMARY 内容」在 `2814a57` 处即已完整，后续提交只动这一个
  计数字段本身。`commits: 3` 与该字段一致（实测 `git rev-list --count`）。
- `STATE.md` / `ROADMAP.md` —— **未改动**（本 plan 由编排器持有这两处写入）