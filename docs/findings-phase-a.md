# Phase A 发现清单

> 深度审计主线（`audit-plan-impl.md`）的发现记录。每条：位置 + 级别 + 根因 + 方案。

## A.1 状态机决策链走查

### 发现 A1-1（🟠 Major）：`.manualPause` 真相源分散

- **位置**：`Sources/PicCore/App/MenuItem.swift:44` 与 `Sources/PicApp/App/MenuContentView.swift:54`
- **现象**：`arbiter.set(.manualPause, ...)` 在两条路径各自实现了一遍。`MenuContentView.activate` 的 `.pauseResume` 分支直接 set，不调 `MenuBarModel.perform`；而 `perform` 里的 `.pauseResume` 分支（被测试驱动）在真实 UI 上不可达。
- **根因**：`perform` 是模型层入口（供 `MenuBarModel` 单测驱动），UI 层 `MenuContentView` 为「菜单不直连播放器」又写了一遍，职责重叠。
- **风险**：将来改「暂停/继续」语义（如 P3 的「区分继续 vs 系统压住」）要改两处；测试（测 perform）绿了不代表 UI（走 activate）对。
- **方案**：`MenuContentView.activate` 的 `.pauseResume` 改走 `MenuBarModel.perform(id, isPaused:, store:, arbiter:, quit:)`，消掉重复 set，让模型层成为唯一实现。

### 其余确认（无问题）

- 6 个 reason 的 set 入口全部汇到 `HoldArbiter.set`，无绕过仲裁器直连播放器的旁路。
- 决策出口只有 `arbiterApply`（`set` 内部 + `applyCurrentDecision`），符合单向流。
- `setRate/setVolume/setMuted/setDesiredRate` 直连是「设置」而非「播放决策」，且 setRate 有门控，合规。

---

## A.2 锚点语义边界

### 发现 A2-1（🔴 Critical）：hold 期间轮换定时器不暂停，resumeAnchor 指向失效的旧片位置

- **位置**：`RotationController.advance/reschedule` + `HoldArbiter.resumeAnchor` + `PlaybackRouter.bind`
- **现象**：`resumeAnchor` 记的是「锁屏那一刻的**时间位置**」，但 `RotationController` 与播放端彻底解耦、hold 期间定时器照常到点换片。解锁时 `arbiterSeek(to: resumeAnchor)` 把**新片**强行 seek 到旧片的位置。
- **推理链（代码依据）**：
  1. `RotationController.reschedule()` 每次 advance 后重排定时器，不读播放状态（注释明言「零播放进度读取」）
  2. hold 期间定时器到点 → `advance` → `onAdvance` → `loadPlayback` → 换新片
  3. `resumeAnchor` 是锁屏时记的旧片位置，换片后参照系失效
  4. 解锁 `set` → `after.isEmpty` → `arbiterSeek(resumeAnchor)` → 新片被 seek 到错误位置
- **后果**：锁屏 30 分钟解锁后，看到的不是「续播」，而是「新片跳到第 12 秒」——位置错乱。
- **根因（推断）**：`resumeAnchor` 只记录「时间位置」，换片后失去参照系。要么记录「片+位置」，要么 hold 期间冻结轮换。
- **方案（二选一，需产品拍板）**：
  - **A**：hold 期间冻结轮换——但破坏 `RotationController` 解耦，需把仲裁器状态漏进轮换器
  - **B（我更倾向）**：`resumeAnchor` 改记 `(url, seconds)`，解锁 seek 前先判断「当前片 == 锚点片」，不一致则放弃 seek。不破坏解耦，让「续播」自己判断锚点是否还有意义
- **待确认**：产品预期——hold 期间壁纸应该「保持不动、解锁继续同一条」，还是「允许换片、解锁播新片」？这决定选 A 还是 B。

### 其余确认（无问题）

- 锚点「只在 ∅→非∅ 写入一次」正确：叠加暂停不会二次覆盖（`before.isEmpty && !after.isEmpty` 门控）。
- 解除时「seek 后清空锚点」正确：`resumeAnchor = nil` 防止二次 seek。
- 起播路径 `applyCurrentDecision` 不碰锚点、不 seek，避免「起播顺带 seek 拽回暂停前位置」，正确。

## A.3 looper 克隆边界

### 发现 A3-1（🔵 Nit）：`preferredForwardBufferDuration` 的「必须在 looper 前」约束未显式警示

- **位置**：`PlayerController.load(url:)` :54
- **现象**：`preferredMaximumResolution`（:59-62）和 `audioTimePitchAlgorithm`（:52）都有注释强调「必须设在 looper 之前，克隆体不带」，但 `preferredForwardBufferDuration = 3.0`（:54）同样设在 looper 前，却**没有同样的警示**。
- **判断**：位置是对的（都在 looper 前），不构成 bug。但若 `preferredForwardBufferDuration` 也依赖克隆继承，它的「必须在 looper 前」约束应该和另外两个一样被显式警示——否则下一个 AI 可能「顺手」把它挪到 looper 之后（比如想在循环中动态调 buffer），从而破坏行为。
- **方案**：给 :54 补一条同类反重构警告，或确认该属性不依赖克隆继承后明确「可任意位置」。

### 其余确认（无问题）

- 三个 item 属性都设在 `AVPlayerLooper(player:templateItem:)` 创建之前，位置正确。
- `load` 的先插后扫 + `disableLooping` 顺序正确，looper 强持有（:33）避免模板 item 被踢出。

## A.4 AVPlayerItem 释放

### 结论：无泄漏、无引用循环（通过）

- `load(url:)` 里 `player.items().filter { $0 !== item }.forEach { player.remove($0) }` 移除旧 item，`stop()` 里 `removeAllItems()` 清空队列——旧 AVPlayerItem 的引用被释放。
- 引用链：`PlayerController.looper`（强持有）→ player；`WallpaperWindow.videoLayer`（let）→ player；player → items。无循环引用（looper 是 PlayerController 持有，item 不反向持 looper）。
- `hide()` 只 `orderOut`（窗口/图层保留），`stop()` 清空队列——降级时 item 已释放，窗口/图层残留但不泄漏（等恢复或 teardown）。

## A.5 Timer/观察者配对

### 结论：退出路径配对正确，运行期 Timer 无累积（通过）

- 4 个 watcher 的 `stop()` 在 `applicationWillTerminate`（:353-356）与 `wiring()` 的 `start()` 严格配对。这些是**进程级注册**（DistributedNotification / CGDisplay 回调 / IOPS runloop source），不摘会残留系统侧——注释「谁创建谁 stop」说的正是这个，非空话。
- `SystemRotationScheduler`：每次 `schedule` 前 `cancel()` + `deinit` 兜底，Timer 不累积。
- `ticker`（2s 定时器）：release 版已被 `#if !PIC_NO_PROBE` 剥掉；debug 版进程退出即回收，`applicationWillTerminate` 未显式 invalidate 属 Nit，不构成泄漏。

### 发现 A5-1（🔵 Nit）：`applicationWillTerminate` 未显式 `ticker?.invalidate()`

- debug 版（含 probe）下 `ticker` 由 `startObservability` 创建，退出路径未 invalidate。进程退出时主 RunLoop 销毁会回收，无实际泄漏，但为配对完整可补一行。
