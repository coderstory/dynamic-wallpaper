---
phase: 02-playback-core
plan: 03
subsystem: ui-menubar
tags: [menubar, holdarbiter, veto-set, menubar-08, privacy-sentinel, appkit-termination, accessory-policy, d-11, d-15, t-02-08, t-02-09, t-02-10]
requires:
  - phase: 02-01
    provides: [HoldArbiter（veto 集合 + 续播锚点）, MenuBarModel, SettingsStore, PlayerController]
  - phase: 02-02
    provides: [AppDelegate.wiring() 装配点, LoopProbe, scripts/run-probe.sh, WallpaperWindow]
provides:
  - Sources/PicApp/App/MenuContentView.swift（菜单三项 + SettingsSkeletonView 最小骨架）
  - HoldArbiter.isManuallyPaused（只读派生量）
  - AppDelegate.presentSettingsWindow() / hideSettingsAndRestorePolicy() / terminateApp()
  - --quit-after 启动参数（测试脚手架，非产品能力）
  - scripts/run-probe.sh quit 子命令 + evidence/quit.log
  - Tests/PicCoreTests/MenuBarModelTests.swift（哨兵法 7 例）
  - test.sh 四条新判据（23 → 27 项）
affects: [02-04, phase-03, phase-04, phase-05]
tech-stack:
  added: []
  patterns:
    - single-terminate-literal（结束进程的全局调用全仓唯一落点，其余走注入闭包）
    - menu-renders-allCases（菜单项只由 MenuItemID.allCases 遍历产出 → 隐私断言才有牙齿）
    - sentinel-reverse-verified（哨兵判据每次改动都做一次真实的改红→恢复双向验证）
    - observable-single-source（UI 只读仲裁器派生量，不另设可变真相源）
key-files:
  created:
    - Sources/PicApp/App/MenuContentView.swift
    - Tests/PicCoreTests/MenuBarModelTests.swift
    - .planning/phases/02-playback-core/evidence/quit.log
  modified:
    - Sources/PicApp/PicApp.swift
    - Sources/PicApp/AppDelegate.swift
    - Sources/PicCore/State/HoldArbiter.swift
    - Sources/PicCore/Playback/LoopProbe.swift
    - Tests/PicCoreTests/HoldArbiterTests.swift
    - scripts/run-probe.sh
    - test.sh
key-decisions:
  - "T1 的 AC 与 key_links 自相矛盾：AC 要求 MenuContentView.swift 内出现 arbiter.set(.manualPause 字面量，key_links 要求它经 MenuBarModel.perform 转手。两条同时成立会双触发仲裁器。保留 key_links 的单一路由，判据改为「UI 侧零 AVPlayer 直连 + perform 的 pauseResume 分支被 spy 断言确实调了仲裁器」——比原 grep 更强，因为它在 perform 被改成空实现时也会红。"
  - "T1 AC「全仓 NSApp.terminate(nil) 恰好 1 处」在开工时不成立（02-02 的 LoopProbe 已有第二处）。改源码不放宽判据：LoopProbe 改为注入 terminate 闭包，收敛为 1 处。"
  - "T2 的两条锚点用例在首跑即绿 —— HoldArbiter.set 早在 02-01 就已实现 D-15。无法拿到 RED，改用两次定向变异证明它们有牙齿（seek(0) / 读实时位置），各自精确命中对应断言。"
  - "PIC_HOLD 由 AppDelegate 的 0.5 秒观察定时器打，而不是往菜单里插回调 —— 后者会让「谁改播放状态」多出一个入口（D-11）。代价是短于 0.5 秒的暂停可能被漏掉，已如实登记。"
requirements-completed: [MENUBAR-03, MENUBAR-07, MENUBAR-08, PAUSE-08]
actuals:
  tokens: 8495
  tasks: 3
  commits: 3
coverage:
  - id: D1
    description: "菜单栏固定三项（暂停/继续、打开设置、退出），由 MenuItemID.allCases 遍历渲染"
    requirement: MENUBAR-03
    verification:
      - kind: integration
        ref: "test.sh 判据「菜单只由 MenuItemID.allCases 遍历渲染（Button 行数 1 = ForEach 行数 1）」"
        status: pass
      - kind: other
        ref: "swift build 退出 0"
        status: pass
    human_judgment: false
  - id: D2
    description: "手动暂停/继续经 HoldArbiter 仲裁，不直连 AVPlayer；暂停态是 decision.holds 的派生量"
    requirement: PAUSE-08
    verification:
      - kind: unit
        ref: "Tests/PicCoreTests/MenuBarModelTests.swift#testPerformPauseResumeGoesThroughArbiterNotDirectly"
        status: pass
      - kind: other
        ref: "test.sh 判据「菜单侧零 AVPlayer 直连（D-11 单向流 / T-02-08）」"
        status: pass
      - kind: unit
        ref: "Tests/PicCoreTests/HoldArbiterTests.swift#testIsManuallyPausedIsDerivedFromHolds"
        status: pass
    human_judgment: false
  - id: D3
    description: "暂停后解除从暂停处续播（D-15 锚点只写一次），期间位置被改也不覆盖"
    requirement: PAUSE-08
    verification:
      - kind: unit
        ref: "Tests/PicCoreTests/HoldArbiterTests.swift#testManualPauseResumesFromAnchorNotFromZero"
        status: pass
      - kind: unit
        ref: "Tests/PicCoreTests/HoldArbiterTests.swift#testAnchorNotOverwrittenBySecondHold"
        status: pass
      - kind: other
        ref: "定向变异验证：seek(0) 与读实时位置两次注入分别让对应断言变红，恢复后 cmp 逐字节一致"
        status: pass
    human_judgment: false
  - id: D4
    description: "菜单「退出」走 NSApp.terminate 路径，跑完 applicationWillTerminate 收尾且进程真正消失"
    requirement: MENUBAR-07
    verification:
      - kind: unit
        ref: "Tests/PicCoreTests/MenuBarModelTests.swift#testPerformQuitCallsInjectedClosureOnlyOnce"
        status: pass
      - kind: integration
        ref: "bash scripts/run-probe.sh quit → evidence/quit.log: QUIT_HOOK_SEEN=1 / QUIT_EXITED=1"
        status: pass
      - kind: other
        ref: "test.sh 判据「结束进程的全局调用全仓唯一落点（AppDelegate）」"
        status: pass
    human_judgment: true
    rationale: "自动证明的是「菜单 quit 动作 = terminateApp()」与「该路径走完收尾并让进程消失」两段。真人点击菜单栏图标这一跳需要 XCUITest（本机无 .xcodeproj，D-01）或解锁会话下的人工点击 —— 见 WINDOWS.md W-2026-10-03-07。"
  - id: D5
    description: "菜单不出现当前播放的文件名（MENUBAR-08 隐私）"
    requirement: MENUBAR-08
    verification:
      - kind: unit
        ref: "Tests/PicCoreTests/MenuBarModelTests.swift#testLabelsNeverContainAnyMediaFileName"
        status: pass
      - kind: other
        ref: "哨兵反向验证：注入 clip-sentinel.mp4 后 8 处断言失败，恢复后 24 项全绿且 cmp 逐字节一致"
        status: pass
      - kind: other
        ref: "test.sh 判据「菜单结构体内零取文件名 API（MENUBAR-08）」"
        status: pass
    human_judgment: false
  - id: D6
    description: "打开设置窗口：最小骨架窗，且关闭后激活策略恢复为 .accessory"
    requirement: MENUBAR-03
    verification:
      - kind: other
        ref: "swift build 退出 0；test.sh 判据「结束进程的全局调用全仓唯一落点」之外的策略切换集中在 AppDelegate"
        status: pass
    human_judgment: true
    rationale: "设置窗能打开、关闭后 Dock 图标消失，都依赖真实点击与肉眼观察。本机屏幕锁定且无屏幕录制权限，无法自动判定 —— 只验证了源码形状（策略切换集中在一个入口，关闭路径必调 setActivationPolicy(.accessory)）。MENUBAR-02 的完整设置窗本身属 Phase 5。"
duration: 46min
completed: 2026-10-03
status: complete
---

# Phase 02 Plan 03: 菜单三项接上仲裁器，续播锚点与进程终止各落一份证据

**菜单栏三项（暂停/继续、打开设置、退出）全部由 `MenuItemID.allCases` 遍历渲染并接上真实行为；续播锚点由两条定向变异验证过的单测钉死（D-15）；`NSApp.terminate` 那条路径走完 `applicationWillTerminate` 收尾并让进程真正消失，落成 `evidence/quit.log`；菜单不出现文件名成为一条经过真实「改红→恢复」双向验证的断言。**

---

## 🔴 诚实基线

**屏幕全程锁着**（沿用 Phase 1 的 `loginwindow` PID 489 会话）。下面「跑过」一栏里没有任何一条来自有前台用户的会话 ——
但也**没有一条依赖眼睛**：源码计数、单测、进程表、stderr 读数都是客观读数。

### 跑过（每个数字来自实跑，命令可复现）

| 项 | 命令 | 结果 |
|---|---|---|
| 产品包编译 | `swift build` | `BUILD_RC=0` |
| 单测（本 plan 结束时） | `swift test` | `Executed 24 tests, with 0 failures`（起始 14） |
| 全量回归 | `bash test.sh` | 退出 0，**通过 27 失败 0**（起始 23） |
| 菜单起进程 12 秒 | `PIC_SOURCE_FOLDER=$PWD/fixtures perl -e 'alarm 12; exec @ARGV' .build/debug/Pic` | `ACTIVATION_POLICY_RAW=1`、5 条 `TICK` 全 `status=playing items=3`、退出后进程表无残项 |
| 优雅终止（判据主体） | `bash scripts/run-probe.sh quit` | `QUIT_MODE=graceful_request`、`QUIT_PID=78599`、`QUIT_HOOK_SEEN=1`、`QUIT_EXITED=1`、`QUIT_WALL_SECONDS=4` |
| 信号路径（仅观测） | 同上，第二轮 | `SIGTERM_HOOK_SEEN=0`、`SIGTERM_EXITED=1` |
| 哨兵反向验证（红） | 注入 `return ["clip-sentinel.mp4"]` 后 `swift test` | `Executed 24 tests, with 8 failures`，失败行含「菜单标签里出现了哨兵文件名：`["clip-sentinel.mp4"]`」 |
| 哨兵反向验证（恢复） | 从备份恢复后 `swift test` | `Executed 24 tests, with 0 failures`；`cmp` 退出 0 |
| 锚点用例的牙齿（两次定向变异） | 临时改 `arbiterSeek(to: 0)` / `arbiterSeek(to: 当前位置)` | 分别为 `[0.0] != [42.0]` 与 `[55.0] != [42.0]`；第二次**只有** `testAnchorNotOverwrittenBySecondHold` 变红 |

### 没跑过（没做，不是做不到）

| 项 | 为什么没跑 |
|---|---|
| **点菜单栏图标退出** | 需真人点击。本机无 `.xcodeproj` 故无 XCUITest（D-01），会话锁定、屏幕录制无权限。→ WINDOWS.md `W-2026-10-03-07` |
| **真人点「暂停」后看视频是否停** | 同上；且屏取回是黑的（02-02 已实测 `no_screen_recording_permission`） |
| **设置窗的肉眼验收**（能打开、关闭后 Dock 图标消失） | 同上。源码形状已验（T-02-09：策略切换集中在 `AppDelegate`，关闭路径必调 `.accessory`） |
| **`PIC_HOLD active=1` 的真实菜单点击触发** | 本 plan 的 quit 探针不驱动暂停；`PIC_HOLD active=0` 那行在 `--quit-after` 那一轮实测出现过（`resumeAt=0.235`），`active=1` 未在真实点击下采到样 |
| **解锁会话的 PDCA-A1 门禁复跑** | 屏幕锁着。02-01 挂着的唯一未闭合项，结论仍是 `GATE_RERUN=blocked` |

### 应该能跑但未测

| 项 | 逻辑依据 | 未测什么 |
|---|---|---|
| 真人点击「暂停」→ 视频真的停 | `MenuContentView` 的 `.pauseResume` 唯一实现就是 `arbiter.set(.manualPause, active:)`，`PlayerController.arbiterApply` 是执行端，02-02 实测过它驱动真实 `AVQueuePlayer`（`status=playing` 那批读数） | 「菜单项 → 仲裁器」这一跳没有真人点击的证据，只有源码计数与 spy 断言 |
| 设置窗真能在 `.accessory` 下被激活 | `presentSettingsWindow()` 先提 `.regular` 再 `openWindow` 再 `activate`，与 `MenuBarSpike` 已验证的策略切换形状一致 | 没有人看过那个窗口 |
| 暂停期间位置被别处改动时的续播 | `testAnchorNotOverwrittenBySecondHold` 纯逻辑钉死（D-15） | 真实播放中「暂停期间位置被改」这个场景本 Phase 构造不出来 —— `HoldReason` 只有一个 case，Phase 3 才有第二个 reason |

### 假定依赖

| 项 | 假定内容 | 未验证之处 |
|---|---|---|
| `--quit-after` 走的那条路径与真人点菜单完全一致 | 二者调的是**同一个** `@objc func terminateApp()`，全仓该字面量唯一（`test.sh` 每次重验） | 「参数能退」已证；「点菜单能退」未证。**不允许把前者说成后者** |
| `PIC_HOLD` 的 0.5 秒轮询足以观测到一次真实点击 | 真人点击到下一次轮询的间隔远大于 0.5 秒 | 若暂停短于 0.5 秒则漏采；未构造该场景 |

---

## 三份交付证据

### `evidence/quit.log` —— 终止路径

```
QUIT_MODE=graceful_request
QUIT_PID=78599
QUIT_HOOK_SEEN=1
QUIT_EXITED=1
QUIT_TRIGGER=--quit-after 3 启动参数（测试脚手架，不是产品能力）
QUIT_WALL_SECONDS=4
QUIT_EVIDENCE=terminated_line=PIC_TERMINATED pid=78599 reason=application_will_terminate
SIGTERM_MODE=kil
SIGTERM_HOOK_SEEN=0
SIGTERM_EXITED=1
SIGTERM_HOOK_NOTE=AppKit 不为 SIGTERM 装 handler；走 applicationWillTerminate 的是 NSApp.terminate 路径，本探针的 QUIT_HOOK_SEEN 判据以那条路径为准。SIGTERM_HOOK_SEEN 为实测观测值，不作断言。
```

**为什么不用 `kill -TERM`**：本机已实测 AppKit **不为 SIGTERM 装信号处理函数** —— 最小 AppKit app 收到 SIGTERM 后零 delegate 回调、
进程立即死亡，走不到 `applicationWillTerminate`。拿「发信号能退」冒充「走 AppKit 收尾路径」会让 `QUIT_HOOK_SEEN=1` 永远不可达。
`SIGTERM_HOOK_SEEN=0` 是**实测观测值**，本 plan 不对它设任何期望 —— 它是框架的既有行为，改框架时会变。

**`--quit-after` 是测试脚手架，不是产品能力。** 它只在命令行显式传参时生效，默认不启动、不出现在菜单里。
`quit.log` 里以 `QUIT_TRIGGER=` 一行显式登记，并另立 `W-2026-10-03-08` 防止后续读者误当成用户可见能力。

### 锚点两用例 —— D-15 钉死

```
testManualPauseResumesFromAnchorNotFromZero   seeks == [42.0]，first != 0.0
testAnchorNotOverwrittenBySecondHold          42.0 暂停 → 位置改 55.0 → 解除 → seeks == [42.0]
```

**这两条不是「从来没红过的测试」。** `HoldArbiter.set` 早在 02-01 就已实现 D-15，所以它们首跑即绿、拿不到 RED。
改用两次**定向变异**证明有牙齿，且第二次精确只命中一条：

| 变异 | 变红的断言 |
|---|---|
| 解除时 `arbiterSeek(to: 0)` | `testManualPauseResumesFromAnchorNotFromZero`、`testAnchorNotOverwrittenBySecondHold`、`testAnchorWrittenOnlyOnEmptyToNonEmptyTransition` |
| 解除时读**实时位置**而非锚点 | **仅** `testAnchorNotOverwrittenBySecondHold`（`[55.0] != [42.0]`） |

两次恢复后 `cmp` 退出 0，文件与注入前逐字节一致。
（第一次尝试用的变异是「把 `∅→非∅` 改成每次都写锚点」—— 它**打不红任何一条**，
因为测试里改位置是直接写 `FakeTarget.position`，不经过仲裁器。那次不算证明，已废弃。）

### 哨兵单测 —— MENUBAR-08

`MenuBarModelTests` 7 例，覆盖计划要求的五组断言：

1. 两种暂停态下标签恒为 3 项（等于 `MenuItemID.allCases.count`）、互不重复
2. 哨兵串 `clip-sentinel.mp4` 出现 0 次、`.mp4` 出现 0 次、源目录全路径与目录名出现 0 次
3. 暂停/继续是两个不同文案，且两者都不含文件名成分
4. `perform(.quit)` 只调注入闭包一次、且不动播放状态
5. `perform(.pauseResume)` 经仲裁器生效；`perform(.openSettings)` 两者都不调

**哨兵串以字面量写死在测试里，不读 `fixtures/`** —— 否则干净 clone 上 `swift test` 会红。
「spy」打在**真仲裁器 + 假播放端**上（`HoldArbiter` 是 final class，不能用子类替身），
断言的是仲裁器被真的驱动了，而不是某个 mock 的调用计数。

**双向验证留痕**（计划要求贴两次的实际结果）：

```
红：  Executed 24 tests, with 8 failures
     MenuBarModelTests.swift:80: XCTAssertFalse failed - 菜单标签里出现了哨兵文件名：["clip-sentinel.mp4"]
     MenuBarModelTests.swift:82: XCTAssertFalse failed - 菜单标签里出现了媒体扩展名：["clip-sentinel.mp4"]
恢复：Executed 24 tests, with 0 failures
     cmp -s Sources/PicCore/App/MenuItem.swift <注入前备份>  → 退出 0
     grep -c 'clip-sentinel.mp4' Sources/PicCore/App/MenuItem.swift → 0
```

---

## 🔴 PLAN_DEVIATION —— 计划里在本机事实上不成立的断言

按纪律：不默默照做，修正断言，保留真值。下面每一条都改了**判据或源码**，没有一条改动**产物数值**。

### 1. T1 的 AC 与 key_links 自相矛盾（双触发仲裁器）

- **AC 写的**：`grep -c 'arbiter.set(.manualPause' Sources/PicApp/App/MenuContentView.swift` ≥ 1。
- **key_links 写的**：`MenuContentView → MenuBarModel.perform(.pauseResume) → HoldArbiter.set(...)`。
- **什么错了**：两条**同时成立会双触发仲裁器**。`MenuBarModel.perform` 的 `.pauseResume` 分支
  本身就是 `arbiter.set(.manualPause, active: !isPaused)`；视图若再自己调一次，幂等守卫会让
  第二次成为空操作 —— 表面全绿，实际上两个动作入口长期会漂。
- **保留哪一条**：保留 key_links 的**单一路由**（视图只调 `perform`）。
- **判据改成什么**：「`MenuContentView.swift` 内 `player.pause()+player.play()` 计数 = 0」
  ＋「`perform` 的 `.pauseResume` 分支被 spy 断言确实调了仲裁器」。
- **为什么这比原 grep 更强**：原 grep 只证明「文件里有这串字面量」—— 哪怕 `perform` 被改成空实现它照样绿。
  新判据在 `perform` 退化时会真的红。

### 2. T1 的 AC「全仓 `NSApp.terminate(nil)` 恰好 1 处」在开工时不成立

- **计划写的**：全仓该字面量恰好出现在 `Sources/PicApp/AppDelegate.swift` 一处。
- **实测到的**：开工时 `grep -rn 'NSApp.terminate' Sources/` 得 **2** 处 ——
  `AppDelegate.swift:63` 与 02-02 遗留的 `Sources/PicCore/Playback/LoopProbe.swift:152`
  （300 秒观察跑完后自己退出）。计划写下这条 AC 时，02-02 还没提交。
- **改源码，不放宽判据**：`LoopProbe` 改为构造时注入 `terminate` 闭包，由 `AppDelegate`
  把自己的 `terminateApp()` 注进去。对外的 `init` 增加一个参数，产品里唯一的调用点已同步。
- **实测收敛为 1 处**，并把「恰好 1」做成 `test.sh` 每次自动重验的判据。
- 记于 `W-2026-10-03-09`。

### 3. T2 的两条锚点用例拿不到 RED

- **计划写的**：两条用例是新写的，按 TDD 应当先红。
- **什么错了**：不是断言错，是**前提错** —— `HoldArbiter.set` 在 02-01 T3 就已实现 D-15 的锚点逻辑，
  这两条用例是给它加的护栏，不是它的实现。
- **怎么处理**：不假装拿到了 RED。改用两次定向变异证明用例有牙齿（见上表），
  并把「第一次尝试的变异打不红任何断言」这件事本身也写下来。
- **产物数值一个字没改**。

### 4. `grep -c ... || echo 0` 让整数比较报错

- **计划写的**（隐含）：`grep -cE '^PIC_TERMINATED ' ... || echo 0`。
- **实测到的**：第一版 `run-probe.sh quit` 打出 `[: 0\n0: integer expression expected` ——
  `grep -c` 命中 0 行时**同时**打印 `0` 并以 1 退出，`|| echo 0` 于是追加了第二个 `0`。
- **改成**：先 `grep -c` 接住输出（`grep` 总会打印一个整数），再用 `${shook:-0}` 兜空，
  比较前加 `2>/dev/null` 与数字守卫。修好后第二轮探针零告警。

### 5. 「菜单侧零 AVPlayer 直连」的第一版判据范围过宽

- **计划写的**（隐含）：威胁 T-02-08 说「`MenuContentView` 内 `player.pause()/play()` 计数必须为 0」。
- **实测到的**：我第一版把范围写成整个 `Sources/PicApp/`，立刻抓到
  `AppDelegate.startWallpaper()` 里的 `player.player.play()` —— 计数 1，判据红。
- **什么是对的**：T-02-08 的威胁边界是「**菜单动作**」。起播时那处 `play()` 不是菜单动作，
  且发生在任何 watcher 存在之前（Phase 3 才接），不归这条判据管。
- **改成**：范围收窄到 `MenuContentView.swift` 单文件 —— 与威胁模型原文一致。
- **同时把发现的东西留下**：起播那处 `play()` 另立 `W-2026-10-03-10`，
  要求 Phase 3 接 watcher 时复核起播时序，**不为让判据变绿而把它从记录里抹掉**。

### 6. 「菜单项数量」的断言措辞

- **计划写的**（隐含）：断言标签数组「恰好等于 3 个元素」。
- **改成**：断言写成 `labels.count == MenuItemID.allCases.count` **且** `== 3`。
  前者让 Phase 4 加菜单项时这条自动跟着改口径，后者把本 Phase 的「三项」钉死 ——
  两个数都断，避免只钉死一个数字而被无声绕过。

---

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `LoopProbe` 的自退路径与 `AppDelegate` 各写一遍终止调用**

- **发现于**：T1 验收（执行 AC「全仓 `NSApp.terminate` 恰好 1 处」时）
- **问题**：两处各自调全局终止，将来必然漂移；且违反计划明写的区域约束。
- **处理**：`LoopProbe.init` 增加 `terminate: @escaping () -> Void`，`AppDelegate` 注入自己的 `terminateApp()`。
  对外方法签名只增一个参数，调用点唯一。
- **验证**：`grep -rn 'NSApp.terminate' Sources/` = 1；`test.sh` 新增判据每次自动重验。

**2. [Rule 2 - Missing critical] 菜单的暂停/继续没有可观测的行**

- **发现于**：T2
- **问题**：暂停发生在菜单点击路径上，`AppDelegate` 看不到它，运行期「暂停了没有」只能靠肉眼。
- **处理**：`AppDelegate` 加 0.5 秒观察定时器，打 `PIC_HOLD active=… reason=manualPause holds=… resumeAt=…`。
  空集写成 `holds=(none)` 而不是空串（空串会让 grep 匹配到别的行）。
- **为什么用轮询而不是回调**：往菜单里插一个「状态变化回调」会让「谁改播放状态」多出第二个入口，
  与 D-11 的单向流相冲突。轮询只读，不写。
- **代价**：短于 0.5 秒的暂停可能被漏采 —— 已如实登记在诚实基线。

**3. [Rule 2 - Missing critical] 终止判据缺少「量的是不是同一个进程」这道护栏**

- **发现于**：T2
- **问题**：`QUIT_HOOK_SEEN` 只匹配 stderr 里的 PID 串。若将来某次跑起来时 `APP_PID` 与
  收尾行里的 PID 对不上，判据仍会绿。
- **处理**：`run-probe.sh quit` 比对二者，不一致就打 `QUIT_PID_MISMATCH expected=… got=…`。
  本轮实测一致（`QUIT_EVIDENCE=terminated_line=PIC_TERMINATED pid=78599`，`QUIT_PID=78599`）。

**4. [Rule 2 - Missing critical] 「菜单标签恒 3 项」这条隐私判据可被绕过**

- **发现于**：T3
- **问题**：哨兵单测锁的是 `MenuBarModel.labels` 的输出。若有人绕过模型、在视图里手写一个
  `Button(Text(当前文件名))`，测试照样全绿。
- **处理**：`test.sh` 加判据「`MenuContentView.swift` 里 `Button(` 的行数 == `ForEach(MenuItemID.allCases` 的行数 × 1」——
  手写第二个 Button 立刻让计数不等。

**5. [Rule 2 - Missing critical] 结束进程调用散落没有自动判据**

- **发现于**：T1（同一个问题，判据侧也要补）
- **处理**：`test.sh` 加判据「剥注释后 `Sources/` 内 `NSApp.terminate` 计数 == 1」。

### 环境类（不是改动类）

**6. 在 `master` 上提交。** 仓库无 remote、单分支，Phase 1 与 02-01/02-02 的全部提交也都在 `master`，
编排器要求在本工作树正常提交，沿用既有做法。

**7. 全部 spawn 的进程已终止。** 每轮探针结束与每个 `swift run` 之后都查过 `pgrep -fl 'debug/Pic|run-probe'`，
最后一次为空；桌面层无残窗。

---

## 任务执行结果

| Task | 内容 | Commit | 结果 |
|---|---|---|---|
| T1 | 菜单三项接上 `HoldArbiter` + 设置骨架窗 + 策略恢复 | `c58f24f` | `BUILD_RC=0`、8 条源码判据全过、进程实测 `ACTIVATION_POLICY_RAW=1` / `TICK status=playing items=3` |
| T2 | 续播锚点两用例 + `PIC_HOLD` + `quit` 探针 | `b99e169` | `quit.log` 七行判据全中、两次定向变异证明用例有牙齿 |
| T3 | 哨兵单测 + 4 条判据挂进 `test.sh` | `047e1cf` | `bash test.sh` 退出 0，**通过 27 失败 0**；哨兵改红→恢复双向验证完成 |

---

## T3：四条新判据长什么样

```
✅ 产品代码 swift build 通过
✅ 产品单测全绿（24 项）
✅ Sources/ 无硬编码桌面层级字面量（D-04）
✅ Sources/ 不出现被禁用的图标层级标识符（D-04）
✅ State/ 零 AVFoundation 依赖（ARCHITECTURE §9）
✅ Sources/ 不用 URL 的字符串形式做存在性检查（D-14 / Pitfall 5）
✅ Sources/ 零 Space 级特殊处理（SYS-02 自动判据）
✅ Sources/ 不读窗口标题（T-02-03 隐私）
✅ 菜单只由 MenuItemID.allCases 遍历渲染（Button 行数 1 = ForEach 行数 1）    ← 新增
✅ 菜单结构体内零取文件名 API（MENUBAR-08）                                ← 新增
✅ 菜单侧零 AVPlayer 直连（D-11 单向流 / T-02-08）                           ← 新增
✅ 结束进程的全局调用全仓唯一落点（AppDelegate）                             ← 新增
```

**隐私判据的范围是刻意收窄到行区间的**：`sed -n '/struct MenuContentView/,/^}/p'` 只切出菜单结构体，
设置窗骨架 `SettingsSkeletonView`（同文件、要显示源目录路径）不在范围内 —— 那是 MENUBAR-08 允许的例外。
判据**没有**写成「扫不到东西」的形式：区间若为空，那条检查会恒绿，所以区间截取本身要能被肉眼验证。

---

## Threat Flags

| Flag | 文件 | 说明 |
|------|------|------|
| threat_flag: information-disclosure | `Sources/PicApp/App/MenuContentView.swift` | 菜单标签是全局常驻 UI。哨兵单测 + 源码判据（行区间内 `lastPathComponent`/`fileName`/`absoluteString` 计数 0）两条独立判据，且经过一次真实的改红→恢复验证 |
| threat_flag: tampering | `Sources/PicApp/App/MenuContentView.swift` | 菜单动作绕过仲裁器直连 AVPlayer 会让 Phase 3 的 veto 集合失效。判据：菜单文件内 `player.pause()+player.play()` = 0，且 `perform(.pauseResume)` 被 spy 断言确实调了仲裁器 |
| threat_flag: denial-of-service | `Sources/PicApp/AppDelegate.swift` | 设置窗把激活策略改成 `.regular` 后未恢复会让 Dock 图标永久出现。策略切换集中在 `AppDelegate` 一处，`onDisappear` 必调 `setActivationPolicy(.accessory)` |
| threat_flag: information-disclosure | `Sources/PicApp/AppDelegate.swift` | `PIC_HOLD` / `PIC_TERMINATED` / `PIC_QUIT_AFTER_SCHEDULED` 三族 stderr 行**只含 reason 名与数字**，不含路径、不含文件名 |
| threat_flag: spoofing | `scripts/run-probe.sh` | `QUIT_HOOK_SEEN` 只匹配 PID 那一段串。已加 `QUIT_PID_MISMATCH` 护栏，比对 stderr 里的 PID 与探针实际持有的 `$!` |

---

## 给下游的硬约束

1. **Phase 5 写完整设置窗时，删除 `--quit-after` 相关代码并改探针。** 现在它是一行留在产品源码里的
   测试脚手架（`W-2026-10-03-08`）。同时那条「真人点菜单退出」的 BLOCKED 就能靠 XCUITest 解开。
2. **Phase 3 接 watcher 时复核起播路径**（`W-2026-10-03-10`）：`AppDelegate.startWallpaper()` 里有一处
   `player.player.play()` 直连。Phase 3 的 watcher 若可能在起播前就置位，这条路径要改为经仲裁器起播。
3. **新增菜单项的唯一做法是加 `MenuItemID` 的 case**，`MenuBarExtra` 那一侧不需要动。
   绕过模型加 `Button` 会让两条判据立刻变红 —— 那是设计好的。
4. **`PIC_HOLD` 是 0.5 秒轮询的**，不是事件驱动的。要精确到毫秒级的 hold 时序，得另做事件观察；
   别把它当实时信号用。
5. **`NSApp.terminate` 全仓唯一落点这条判据每次 `bash test.sh` 都会跑。** 任何新的退出路径
   （例如 Phase 4 的扫描错误后退出）都必须经注入闭包，不许再写字面量。

---

## Self-Check: PASSED

- 3 个新建文件 + 7 个修改文件全部存在于磁盘
- 3 个任务提交全部存在于 `9f3cdba..047e1cf`（`git rev-list --count` = **3**，与 frontmatter 一致）
- `swift build` 退出 0 / `swift test` `Executed 24 tests, with 0 failures` / `bash test.sh` 退出 0 且通过 27
- 哨兵反向验证真的跑了：红的那次贴了失败行，恢复的那次贴了通过汇总，`cmp` 退出 0，
  `git diff -- Sources/PicCore/App/MenuItem.swift` 为空
- `STATE.md` 与 `ROADMAP.md` **未被修改**（编排器拥有这两处写入）；`git status --short` 为空
- 全部 spawn 的进程已终止（最后一次 `pgrep -fl 'debug/Pic'` 为空），菜单栏无残项
- Phase 1 的 `gate-01.log` 未被触碰（md5 `af32978a623e67d8afe9842368a47b8d`）

---

*Phase: 02-playback-core*
*Plan: 03*
*Completed: 2026-10-03*
