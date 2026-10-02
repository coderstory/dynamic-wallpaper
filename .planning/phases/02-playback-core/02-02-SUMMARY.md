---
phase: 02-playback-core
plan: 02
subsystem: playback-core-vertical-slice
tags: [tracer, desktop-level-window, avplayerlayer, avplayerlooper, pid-claim, d-04, d-08, d-09, d-12, d-13, sys-02]
requires: [Phase 1 GATE=A, 02-01 三个冻结接口]
provides: [WallpaperWindow, WallpaperWindowController, WindowProbe, LoopProbe, scripts/run-probe.sh, evidence/order.log, evidence/inset.log, evidence/loop.log]
affects: [02-03, 02-04, phase-03, phase-04, phase-07]
tech-stack:
  added: []
  patterns: [two-probe-split-by-D-04, single-assembly-point, no-space-level-special-casing, measured-blocked-not-asserted-blocked]
key-files:
  created:
    - Sources/PicCore/Render/WallpaperWindow.swift
    - Sources/PicCore/Render/WallpaperWindowController.swift
    - Sources/PicCore/Playback/WindowProbe.swift
    - Sources/PicCore/Playback/LoopProbe.swift
    - scripts/run-probe.sh
    - .planning/phases/02-playback-core/evidence/order.log
    - .planning/phases/02-playback-core/evidence/inset.log
    - .planning/phases/02-playback-core/evidence/loop.log
    - .planning/phases/02-playback-core/evidence/loop-run1-original-criterion.log
    - .planning/WINDOWS.md
  modified:
    - Sources/PicApp/AppDelegate.swift
    - Sources/PicApp/PicApp.swift
    - test.sh
decisions:
  - "D-04 的两半各归其位：层级值用 CoreGraphics 运行时符号（不硬编码数字），图标层标识符全树 0 次；ORDER 判定搬回 .planning/spike/ 的 throwaway 探针"
  - "循环判据①由 endedCount==0 纠正为 endedCount==cycles —— AVPlayerLooper 每圈必发一次播完通知，原判据会让「在循环」与「不循环」不可区分"
  - "黑帧可观测性改用屏取回的平均亮度（白对照标定）判定，不再用两次取图的字节是否相同"
  - "D-09 的严格同层外来窗口在本锁屏会话实测为 0；同层族为 7。两个数都记，不合并成一个"
  - "test.sh 的源码判据扫描对象一律是 Sources/，绝不允许出现拿 test.sh 自己当判据对象的检查项"
metrics:
  duration: 19min
  completed: 2026-10-03
  commits: 3
plan_head_before: 875741d529eea987afe6439adfbd0b80f9ef3095
plan_head_after: 86669612ae1042c250f8be28f8a348574bdff2b0
actuals:
  tokens: 11000
  tasks: 3
  commits: 3
status: complete
---

# Phase 02 Plan 02: tracer 竖切 —— 一条命令从零到「桌面图标后面有视频在循环」

一条路走通：`AppDelegate.wiring()` → 桌面层窗口 → `AVPlayerLayer` → `AVQueuePlayer` 循环 → 菜单栏常驻 → 无 Dock 图标。
SC2 的三个可自动判定部分全部落成数字；两条不可自动判定的部分如实登记为 BLOCKED。

---

## 🔴 诚实基线

**产品未在解锁会话验证过。** 屏幕全程锁着（`loginwindow` PID 489 恒在）。
下面「跑过」一栏里没有任何一条来自有前台用户的会话 —— 但也**没有一条依赖眼睛**：
层级、bounds、时间控件状态、队列长度、通知计数、循环时长统计都是客观读数。

### 跑过（命令可复现，每个数字来自实跑）

| 项 | 命令 | 结果 |
|---|---|---|
| 产品包编译 | `swift build` | `BUILD_RC=0` |
| 单测 | `swift test` | `Executed 14 tests, with 0 failures` |
| tracer 起进程 22 秒 | `PIC_SOURCE_FOLDER=$PWD/fixtures perl -e 'alarm 22; exec @ARGV' swift run Pic` | `ACTIVATION_POLICY_RAW=1`；`TICK` 10 行，`status` 全 `playing`，`items` 恒 3，`pos` 1.742→3.742→5.742→7.742→1.741 |
| 层级判定 | `bash scripts/run-probe.sh order` | `ORDER=ok`、`REASON=none_all_four_criteria_met`、`SELF_LEVEL=-2147483623`、`ICON_LEVEL=-2147483603`、`SELF_LEVEL_CROSSCHECK=agree` |
| 几何内缩 | `bash scripts/run-probe.sh inset` | `INSET_LEFT=14 TOP=9 RIGHT=14 BOTTOM=9`、`SCREEN_FRAME=0,0,1470,956`、`WINDOW_FRAME=14,9,1442,938`、`SCREENS_COUNT=1` |
| 300 秒无缝循环（跑了两轮，每轮满 300 秒墙钟） | `bash scripts/run-probe.sh loop` | 150 个采样点，`status` 全 `playing`、`items` 恒 3、`hasItem` 恒 1；`LOOP_CYCLES=37`、`LOOP_ENDED=37`、`LOOP_ENDED_PER_CYCLE=1.000`、`LOOP_STALLED=0`、`LOOP_FAILED=0`、`LOOP_DURATION=300` → `LOOP_VERDICT=pass` |
| 黑帧可观测性 | 两次 `screencapture` + ffmpeg `signalstats` 量平均亮度 | 屏取回平均亮度 `16` / `16.0027`（YUV 黑电平），纯白对照 `235`，阈值 `23.5` → `BLACKFRAME=blocked reason=no_screen_recording_permission` |
| 全量回归 | `bash test.sh` | 退出 0，**通过 23 失败 0**（原 15 + 新增 8） |
| 新判据反向对照 | 临时注入一个被禁 token 后重跑 `test.sh` | 22 通过 1 失败 —— 证明新判据不是永远过的形状 |

### 没跑过（没做，不是做不到）

| 项 | 为什么没跑 |
|---|---|
| **SC2「无黑帧」** | 屏取回的平均亮度停在黑电平（16，对白对照 235），取回的帧没有任何桌面内容。黑帧判定在本机原理上无法进行，`BLACKFRAME=blocked` |
| **SC5「切换 Space 后不消失」** | 需真人 Mission Control 操作 + 多 Space 环境。本机 `screens_count=1`，会话锁定 |
| **SC1「点击和拖动桌面图标完全不受影响」** | 需真人手点。沿用 Phase 1 的处置：事后补做，不阻塞 |
| **解锁会话的 PDCA-A1 门禁复跑** | 屏幕锁着。这是 02-01 挂着的唯一未闭合项，结论仍是 `GATE_RERUN=blocked` |
| **刷新驱动（`NSScreen.displayLink`）复测** | Phase 1 实测本进程拿不到任何显示刷新回调（`FRAME_DRIVER=timer_fallback_hz30`）。产品里刻意不放第二个假的「在刷新」信号；刷新驱动复测是 02-04 的 `.app` 验收项（PDCA-A4） |
| **菜单栏图标的肉眼确认、菜单点开的渲染** | 无屏幕录制权限。本 Phase 用 `ACTIVATION_POLICY_RAW=1` 作可自动核对的代理 |

### 应该能跑但未测

| 项 | 逻辑依据 | 未测什么 |
|---|---|---|
| 窗口真在桌面图标**后面**合成 | `ORDER=ok` + `SELF_LEVEL=-2147483623 < ICON_LEVEL=-2147483603`，两个探针独立读数 `agree` | 只是层级次序，不是合成结果 —— 没人看过那一帧 |
| 视频真的**贴满**铺满主屏无黑边 | `videoGravity = .resizeAspectFill` + `WINDOW_FRAME=14,9,1442,938` 对 `SCREEN_FRAME=0,0,1470,956` | 没有一帧像素被看过（屏取回是黑的） |
| `reassert()` 真的让窗口在切 Space 后仍在 | 它重设四项集合行为再 `orderFrontRegardless()`，形状与 `init` 相同 | **没有任何代码自动调用它**（这正是 SYS-02 要的形状），调用点是 02-04 |
| `AVPlayerLooper` 的长期稳定性 | 本轮 300 秒 37 圈零失败零卡顿 | Phase 7 的 50 次换片与长跑验收才是它的考场 |

### 假定依赖

| 项 | 假定内容 | 未验证之处 |
|---|---|---|
| 打包成 `.app` 后 `bundle id = com.local.pic`，`UserDefaults.standard` 落进正确域 | 沿用 `build.sh` 现有的 `CFBundleIdentifier` | 未打包验证过；开发期靠 `PIC_SOURCE_FOLDER` 环境变量绕过 |
| `com.local.pic` 域里已预置 `sourceFolderPath` | 02-01 实际执行过 `defaults write` 并回读确认 | Phase 4 起要换成用户自选目录 |
| 解锁会话下层级值仍为 `-2147483623` | 原值来自 Phase 1 的 `gate-01.log`（同样是锁屏会话） | **本 plan 未在解锁会话复跑** —— 这是 PDCA-A1 BLOCKED 的直接后果 |

---

## 三份证据（全部在 `.planning/phases/02-playback-core/evidence/`）

### `order.log` —— 层级 + PID 认领

```
ORDER=ok
ORDER_SOURCE=spike_windowprobe
REASON=none_all_four_criteria_met
SELF_LEVEL=-2147483623
FOREIGN_SAME_LEVEL=0
PID_CLAIM_REQUIRED=0
ICON_LEVEL=-2147483603
SELF_LEVEL_SPIKE=-2147483623
FOREIGN_DESKTOP_FAMILY=7
PID_CLAIM_REQUIRED_BAND=1
WINDOWS_TOTAL=15
OWNED_WINDOW_COUNT=1
FOREIGN_OWNERS=none
SELF_LEVEL_CROSSCHECK=agree
PROBE_RC product=0 spike=0
```

**两个探针分住两处，是 D-04 逼出来的，不是洁癖。** 产品侧（`Sources/`）需要知道「桌面图标层的值」才能判 ORDER，
而那个取值的 CoreGraphics 标识符被 D-04 禁用、T3 又要求 `Sources/` 全树 0 次。两条同时满足的办法不是硬编码数字，
是把「需要图标层值」的那一半放回 `.planning/spike/WindowProbe.swift`（Phase 1 已验证的 throwaway 探针，现编译现跑）。
产品代码一行也没进 `.planning/spike/`，反向也不破。

`SELF_LEVEL_CROSSCHECK=agree` 是两把独立尺子量的同一个数：产品侧按 PID 认领导出的层级，
与 spike 侧按 PID 认领导出的层级一致。`SELF_LEVEL=-2147483623` 与 Phase 1 `gate-01.log` 的原值**逐位相同**。

### `inset.log` —— D-08 四个内缩整数

```
INSET_LEFT=14   INSET_TOP=9   INSET_RIGHT=14   INSET_BOTTOM=9   INSET_RECORDED=1
SCREEN_FRAME=0,0,1470,956   WINDOW_FRAME=14,9,1442,938   SCREENS_COUNT=1
```

坐标系陷阱已处理：先按 `screens[0]` 的高度（956）把 `CGWindowList` 的左上角原点翻成左下角原点再比。
本会话翻完之后数值恰好自洽（`WINDOW_FRAME` 与 `WINDOW_FRAME_RAW_CG` 相同，因为窗口上下内缩对称），
但翻转路径是真的跑了 —— Phase 1 的全屏场景在没翻转的版本上算错过。

**与 D-08 记录的 14/9 相符**，但本 Phase **不据此做任何判定** —— 需要据此判定全屏几何的是 Phase 3（PDCA-A5）。
需要注意的是：本机 `SCREENS_COUNT=1`、`SCREEN_FRAME` 是 1470×956（D-08 提到的刘海 33pt 在本会话读数里不出现），
所以这四个数是「本会话的实测」，不是「D-08 那个场景的确认」。

### `loop.log` —— 300 秒无缝循环

```
LOOP_SAMPLES=150   LOOP_ENDED=37   LOOP_ENDED_PER_CYCLE=1.000   LOOP_STALLED=0   LOOP_FAILED=0
LOOP_VERDICT=pass  LOOP_CYCLES=37  LOOP_POS_MONOTONIC=0  LOOP_DURATION=300
BLACKFRAME=blocked reason=no_screen_recording_permission
BLACKFRAME_EVIDENCE=capture_a_yavg=16 capture_b_yavg=16.0027 white_control_yavg=235 threshold=23.5
```

150 个采样点里 `status` 全为 `playing`、`items` 全为 3、`hasItem` 全为 1 —— 这是三条独立读数的一致结论，
不是「看起来在动」。

**`LOOP_POS_MONOTONIC=0` 是探针构造的 artifact，不是播放缺陷。** `AVPlayerLooper` 的队列里放的是**克隆 item**，
每过一个 loop 边界 `AVPlayer.currentTime()` 就归零，所以「跨边界单调不减」在原理上就测不出来。
播放是否正常的唯一口径是 `endedCount` / `failedCount` / `status` / `items` 四项 —— 这四项本轮全部成立。
`LOOP_POS_NOTE=` 一行无条件打印，无论 verdict 是 pass 还是 fail。

**`LOOP_ENDED=37` 与 `LOOP_CYCLES=37` 相等，是两个独立测法互相印证**（一个数通知，一个数 `currentTime` 归零次数），
这个相等本身就是「looper 在正常换片」的证据。这一点触发了下面第 3 条偏离。

### `loop-run1-original-criterion.log` —— 被纠正的那条判据的原始结果

第一轮循环按计划原文写的判据跑出 `LOOP_VERDICT=fail`。原始输出单独留档在
`evidence/loop-run1-original-criterion.log` —— 纠正判据这件事本身也要有证据，不能只留一个「已修复」的结论。

---

## 🔴 PLAN_DEVIATION —— 计划里在本机事实上不成立的断言

按纪律：不默默照做，修正断言，保留真值。下面每一条都改了**判据**，没有一条改动**产物数值**。

### 1. 循环判据①：`endedCount == 0` 在本机被证伪

- **计划写的**：`LOOP_VERDICT=pass` 当且仅当 ① `endedCount == 0 && failedCount == 0` …
- **实测到的**：300 秒里 `endedCount=37`、`failedCount=0`、`stalledCount=0`、`cycles=37`。
- **什么错了**：`AVPlayerLooper` **正是靠这条通知驱动「换下一条」的**。一个循环正常的播放器必然每圈发一次。
  原判据把 looper 的正常工作判成失败 —— 它让「在循环」与「不循环」变成同一个结论。
- **实测怎么证明**：`LOOP_ENDED` 与 `LOOP_CYCLES` 是两个互不相干的测法（通知计数 vs `currentTime` 归零次数），
  本轮都等于 37。若 `endedCount == 0` 才叫正常，那意味着播放器从来没换过片，也就是从来没循环过。
- **改成**：`failedCount == 0` **且** `endedCount == cycles`。两轮各跑满 300 秒，改判据后 `LOOP_VERDICT=pass`。
- **产物数值一个字没改**：`LOOP_ENDED=37`、`LOOP_CYCLES=37` 两轮都原样保留在证据里。

### 2. `success_criteria` 里「`Sources/` 全树 `CGWindowLevelForKey` 0 次」与 D-04 自相矛盾

- **计划写的**：success_criteria 第 8 条要求 `Sources/` 全树 `desktopIconWindow` 与 `CGWindowLevelForKey` 各 0 次。
- **什么错了**：D-04 钦定的唯一层级写法就是
  `level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))`。
  要求这个符号 0 次，会把**钦定的正确写法本身**判成违规。
- **实测到的**：`CGWindowLevelForKey` 在 `Sources/` 出现 1 次（`WallpaperWindow.swift` 那一行，正是钦定写法），
  运行结果 `SELF_LEVEL=-2147483623`、`ORDER=ok`；`desktopIconWindow` 在 `Sources/` 全树 **0 次**。
- **按哪个执行**：T3 的五条源码断言（其中不含 `CGWindowLevelForKey` 全树计数），
  以及 T2 对 `Sources/PicCore/Playback/WindowProbe.swift` **单文件**的 0 次约束 —— 已实测 0 次。

### 3. D-09「至少一个同类壁纸 app 同处桌面层」在本锁屏会话未复现

- **计划写的**：探针必须打出「同层但非本 PID 的窗口数 **> 0**」。
- **实测到的**：`FOREIGN_SAME_LEVEL=0`、`FOREIGN_OWNERS=none`。
  当前锁屏会话在屏的窗口共 15 个：`Window Server`、`墙纸`、`WindowManager`、`访达`、`通知中心`、
  `loginwindow`、`Ghostty`、`CC Switch`，**没有一个停在 `-2147483623`**。
- **保留真值**：不把 0 改写成 1。
- **补了什么**：另打一组同层族读数 —— `FOREIGN_DESKTOP_FAMILY=7`（层级在我方 ±64 内、owner 不是自己的窗口有 7 个）、
  `PID_CLAIM_REQUIRED_BAND=1`。只按层级认领在这一族里仍会认错，D-09 的纪律照样成立；
  严格同层为 0 是**这个会话**的事实，不是纪律可以放松的理由。

### 4. `AVQueuePlayer.items` 是方法不是属性

- **计划写的**：`items=<player.items.count>`。
- **实测到的**：编译报 `method 'items' was used as a property; add () to call it`。实际 API 是 `player.items().count`。
- **改成**：判据改、产品值不动。实测恒为 3。

### 5. 黑帧可观测性：字节比对会给出错误的原因标签

- **计划写的**（隐含）：两次 `screencapture` 字节相同 → 取图管线返回常量占位 → `no_screen_recording_permission`。
- **实测到的**：两次取图**并不相同**（`aa30b1bd…` vs `5db57631…`），按字节判据会输出
  `detector_not_implemented_in_phase_02` —— 一个**错误**的原因。
- **真值**：把四张图都量了平均亮度，全部停在 YUV 黑电平 `16.0`（纯白对照 `235`）。第一张还与 Phase 1 的
  占位图 `gate-01.png`（`aa30b1bd…`）逐字节相同。看图确认：整帧全黑，右上角一个孤立蓝点。
- **改成**：用 ffmpeg `signalstats` 的平均亮度 + 纯白对照标定的阈值（白 × 10%）判定，
  `BLACKFRAME_EVIDENCE=` 行把三个数都打出来，判据本身可复现。
- **结论没变**：桌面真实像素仍然取不到，`BLACKFRAME=blocked reason=no_screen_recording_permission`。

### 6. 计划判据里的 `\s` 在本机 grep 上不可靠

- **计划写的**：`grep -v -e '^\s*//' -e '^\s*\*'`。POSIX BRE 不定义 `\s`。
- **改成**：全部用 `[[:space:]]`。而且**判据不靠这个过滤器承重** ——
  六个被计数的 token（层级字面量 / 图标层标识符 / `absoluteString` / Space 变更通知 / 窗口标题键 / `import AVFoundation`）
  在 `Sources/` 里**连注释里都没写**，所以即使过滤器完全失效，判据依然成立。这是 02-01 踩过的坑。

### 7. `WallpaperWindowController.layer` 从 `private let` 改成 `private(set) var`

- **计划写的**：`private let layer: AVPlayerLayer`，且 `WallpaperWindow.init(screen:player:)` 收一个 player。
- **什么冲突**：两个签名放在一起会造出**同一个 player 上的两个 `AVPlayerLayer`**，渲染哪一路变成不确定的事。
- **改成**：图层由 `WallpaperWindow` 创建（它是渲染子树的根）并以 `videoLayer` 暴露；控制器暴露
  `public private(set) var layer: AVPlayerLayer?`，首次 `attach` 后有值。
- **对外的方法签名 `attach(player:)` / `reassert()` / `teardown()` 一个字没改。**

---

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `LoopProbe.deinit` 触发 ActorIsolatedCall**

- **发现于**：T2 首次编译。
- **问题**：`deinit` 不是主线程隔离的，而 `removeObservers()` 是 `isolated` 方法。
- **处理**：观察者令牌改标 `nonisolated(unsafe)`，`deinit` 里直接调 `NotificationCenter.removeObserver`
  （该 API 本身线程安全），不绕道隔离方法。观察者泄漏是 D-14 明令禁止的，不能因为 `deinit` 而漏掉。

**2. [Rule 2 - Missing critical] 循环探针的 `status` 读数不可 grep**

- **发现于**：T1 首次实跑。
- **问题**：`\(AVPlayer.TimeControlStatus)` 在 Swift 里反射成 `AVPlayerTimeControlStatus(rawValue: 2)`。
  T2 的判定与 T3 的验收脚本都要按这个词读，反射串没法判。
- **处理**：加 `LoopProbe.statusToken(_:)` 映射成 `playing` / `paused` / `waiting` / `unknown(N)`。
  `TICK` 行与 `LOOP_SAMPLE` 行共用同一个映射，不留两份会漂移的实现。

**3. [Rule 2 - Missing critical] SC1「Dock 无图标」没有机器可读证据**

- **发现于**：T1。
- **问题**：计划只要求 `activationPolicy().rawValue == 1`，但没有任何地方把它打出来，
  下游只能靠肉眼或重跑探针。
- **处理**：起播后打一行 `ACTIVATION_POLICY_RAW=1`。三份证据里都能看到这一行。

**4. [Rule 2 - Missing critical] 起播时音量与静音状态没有落位**

- **发现于**：T1 写 `AppDelegate` 时。
- **问题**：计划步骤⑤只写了 `load` + `play`。不落位的话 app 以 `volume=1.0`、未静音起播 ——
  一个壁纸 app 开屏就出声是缺陷。
- **处理**：在 `play()` **之后**依次调 `setRate` / `setVolume` / `setMuted`。
  顺序不能反：挂在 `AVPlayer` 上的速度与音量必须在播放中改才生效（D-13）。

### 环境类（不是改动类）

**5. 在 `master` 上提交。** 仓库无 remote、单分支，Phase 1 与 02-01 的全部提交也都在 `master`，
编排器明确要求在本工作树正常提交，故沿用既有做法。

**6. 循环探针跑了两轮，每轮满 300 秒墙钟。** 第一轮按计划原文的判据跑出 `fail`，
用来定位判据缺陷；纠正后第二轮重跑。原始输出单独留档在 `evidence/loop-run1-original-criterion.log`。

---

## 任务执行结果

| Task | 内容 | Commit | 结果 |
|---|---|---|---|
| T1 | tracer：桌面层窗口 + 视频图层 + 菜单栏常驻一条路走通 | `570c725` | `BUILD_RC=0`、`ACTIVATION_POLICY_RAW=1`、`TICK status=playing items=3` |
| T2 | 两个探针 + 三份证据 | `89b9cdb` | `ORDER=ok`、`INSET_*=14/9/14/9`、`LOOP_VERDICT=pass`（150 采样 / 37 圈 / 300 秒） |
| T3 | SYS-02 落成可判定断言 + 挂进 `test.sh` | `8666961` | `bash test.sh` 退出 0，**通过 23 失败 0** |

---

## T3：8 条新判据长什么样

```
✅ 产品代码 swift build 通过
✅ 产品单测全绿（14 项）
✅ Sources/ 无硬编码桌面层级字面量（D-04）
✅ Sources/ 不出现被禁用的图标层级标识符（D-04）
✅ State/ 零 AVFoundation 依赖（ARCHITECTURE §9）
✅ Sources/ 不用 URL 的字符串形式做存在性检查（D-14 / Pitfall 5）
✅ Sources/ 零 Space 级特殊处理（SYS-02 自动判据）
✅ Sources/ 不读窗口标题（T-02-03 隐私）
```

**SYS-02 的可判定部分就是第 7 条**：`Sources/` 里没有任何 Space 变更通知的订阅，
`WallpaperWindowController.reassert()` **不被任何代码自动调用** —— 没有 watcher、没有定时器。
SC5 要的正是这个形状：走系统默认行为（`.canJoinAllSpaces` + `.stationary` + `.ignoresCycle` + `.fullScreenAuxiliary`），
不做差异化处理。02-04 会把 `reassert()` 接到 `.app` 的实测上。

**两个纪律写进了 `test.sh` 的注释里，防止下游再踩：**

1. **扫描对象一律是 `Sources/` 或产品源码文件。** 判据持有字面量是判据的定义，
   绝不允许反过来扫 `test.sh` 自己 —— 那样这条检查会恒红。
2. **计数前先剥注释**（行注释 + 块注释的首行/中间行/末行）。但本 plan 的判据不靠这个过滤器承重：
   六个被计数的 token 在 `Sources/` 里连注释都没写。

**反向对照做过**：临时在 `Sources/PicCore/` 放一个含窗口标题键的文件，`test.sh` 立刻变成 22 通过 1 失败。
删掉后恢复 23 通过。**不允许出现「✅ 全绿」但通过数没涨。**

---

## Threat Flags

| Flag | 文件 | 说明 |
|------|------|------|
| threat_flag: information-disclosure | `Sources/PicCore/Playback/WindowProbe.swift` | 读 `CGWindowListCopyWindowInfo` 的**全系统**窗口元数据。只取四个键，窗口标题键一个字节不碰 —— `test.sh` 每次自动重验该键在 `Sources/` 出现 0 次 |
| threat_flag: spoofing | `Sources/PicCore/Playback/WindowProbe.swift` | 按 layer 认领会认错。已落成机器可读数字：`FOREIGN_SAME_LEVEL` / `FOREIGN_DESKTOP_FAMILY=7` / `PID_CLAIM_REQUIRED_BAND=1` |
| threat_flag: tampering | `Sources/PicCore/Render/WallpaperWindow.swift` | 一扇 borderless、全屏、`ignoresMouseEvents` 的窗口被插到所有其他窗口之下。四条配置（不吃鼠标 / 不能当 key / 不能当 main / borderless）合起来保证它不可能截获桌面上其他 app 的输入 |
| threat_flag: information-disclosure | `Sources/PicApp/AppDelegate.swift` | stderr 输出。`PIC_NO_SOURCE` 只打印**原因类别**不打印路径；`TICK` 行只含 `pos`/`status`/`items`，不含文件名 |

---

## 给下游的硬约束

1. **Phase 3 用覆盖率判断几何之前，先减掉 `evidence/inset.log` 的四个内缩数**（本会话 14/9/14/9）。
   本机 `screens_count=1`，刘海 33pt 在这组读数里不出现 —— 换显示配置要重跑 `bash scripts/run-probe.sh inset`。
2. **Phase 3/4 抄循环判据时抄纠正后的版本**（`failedCount == 0 && endedCount == cycles`），
   不要抄计划原文的 `endedCount == 0` —— 理由见上面 `PLAN_DEVIATION` 第 1 条。
3. **ORDER 判定仍走 `.planning/spike/WindowProbe.swift`。** 产品源码里 `CGWindowLevelForKey` 是**该出现的**
   （D-04 钦定写法），被禁用的图标层标识符才是 0 次 —— 两者别搞反。
4. **`PlayerController.attach(to:)` / `AppDelegate.attachPlayerLayer(_:)` 仍是未使用的注入点**，
   留给 02-04 的 `.app` 打包复测。本 plan 刻意不调它：`attach(player:)` 已经把同一个 player
   交给窗口侧的图层，两处都设 player 只会让「接缝在哪」变得不可判定。
5. **`WallpaperWindowController.reassert()` 刻意没有自动调用者** —— 这是 SYS-02 的一部分，不是遗漏。
6. **`loop` 子命令要跑满 300 秒墙钟**，执行前把命令超时提到 ≥420000ms。
7. **`.planning/WINDOWS.md` 里 6 条全是 `open`**，解锁后按各条的「解开条件」逐条闭合。

---

## Self-Check: PASSED

- 10 个新建文件 + 3 个修改文件全部存在于磁盘
- 3 个任务提交全部存在于 `875741d..8666961`（`git rev-list --count` = **3**，与 frontmatter 一致）
- `swift build` 退出 0 / `swift test` `Executed 14 tests, with 0 failures` / `bash test.sh` 退出 0 且通过 23
- `STATE.md` 与 `ROADMAP.md` **未被修改**（编排器拥有这两处写入）；`.planning/state.json` 的改动保持未暂存，
  未被本 plan 的任何提交带入
- 全部 spawn 的进程已终止，桌面层无残窗（`pgrep -fl 'debug/Pic|run-probe'` 为空）
- Phase 1 的 `gate-01.log` 未被触碰（md5 `af32978a623e67d8afe9842368a47b8d`，备份在 `evidence/gate-01-locked-session.md5`）