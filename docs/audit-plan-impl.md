# Pic 深度审查 —— 可执行实施计划

- 配套设计文档：`audit-plan-deep.md`（维度判断、风险权重、注释分析）
- 本计划：把设计文档的 Phase A→D 拆成**原子任务**，每个任务可独立执行、可验证
- 方法论：superpowers（TDD 红绿循环 + 两段式评审）

---

## 0. 方法论调适：审查 ≠ 写功能

superpowers 的 TDD 是为「写功能/修 bug」设计的（先写测试描述期望行为）。但「审查」第一阶段是**发现**——在不知道 bug 在哪之前，无法写「期望行为」的测试。

所以本计划把任务分成**两类**，对应两个阶段：

| 类型 | 阶段 | 做法 | 验证方式 |
|---|---|---|---|
| **发现任务** | 先跑 | 读代码 + 推理 + 临时复现探针 | 「找到 N 处问题」或「确认无问题」，附代码依据 |
| **修复任务** | 发现之后 | TDD 红绿循环：先写失败测试→看红→改→看绿 | `swift test --disable-sandbox --filter Xxx` 全绿 |

**纪律**：发现任务不得顺手改代码；修复任务不得没写失败测试就改。两者严格分离。

---

## 1. 前置：注释精简（激进档）

> 目标：注释占比 17.6% → ~12%。这是 Phase A 前的清理，产出干净基线。

### 任务 0.1：删演变叙事 + 复述 + 空行（发现+修复混合，约 16 处）
- 文件：`Sources/PicApp/Transcode/TranscodeSection.swift`（:133「先前这里又除了一次 100」）等 4 处演变叙事 + 11 处复述 + 1 空行
- 做法：删注释行（不碰代码）
- 验证：`swift build --disable-sandbox` 通过；注释占比下降到约 16.4%

### 任务 0.2：下沉 2 处带约束的 MARK 信息
- 文件：`Sources/PicCore/Transcode/FpsDownscaleCommand.swift`（「档位常量不做配置化」）、`Sources/PicCore/Media/FrameRateTable.swift`（「变更口都落盘——只在状态跃迁时调用」）
- 做法：把这两条约束信息写回文件头 doc comment（删 MARK 时丢掉的）
- 验证：`grep -n "不做配置化" FpsDownscaleCommand.swift` 有结果；`grep -n "状态跃迁" FrameRateTable.swift` 有结果

### 任务 0.3：压缩多行 doc comment 为一行（约 80-100 行）
- 文件：所有含多行 `///` 的文件（307 行整行注释中约 2/3 是多行）
- 做法：多行 `///` 压成一行核心点，凡含「不得/必须/顺序/刻意/必现/否则」的关键词保留
- 验证：`swift build` 通过；注释占比 ≤ 14%

### 任务 0.4：行内注释逐条过（约删 80-120 行）
- 文件：所有含行内 `//` 的文件（954 行）
- 做法：删「复述行为/复述命名」，保留「反重构警告/契约」
- 验证：注释占比 ≤ 13%（目标 12%）；229 处反重构警告一字不减

---

## 2. Phase A：三个命门维度（发现任务，产出发现清单）

> 每个发现任务产出「发现清单」，不是改代码。清单条目格式：位置 + 级别 + 根因 + 正确方案。

### 任务 A.1：状态机正确性 —— 决策链完整走查
- 文件：`Sources/PicCore/State/HoldArbiter.swift`、`HoldReason.swift`、`PlaybackDecision.swift`、6 个 Watcher
- 查：6 个 `HoldReason` 的每个 set 入口是否都汇到 `HoldArbiter.set`；有没有绕开仲裁器直连 PlayerController 的地方
- 验证：产出「决策链走查表」——每个 reason 的 set 入口、是否经过 arbiter、有无旁路

### 任务 A.2：状态机正确性 —— 锚点语义边界
- 文件：`HoldArbiter.swift`（`resumeAnchor`）、`PlaybackRouter.swift`、`RotationController.swift`
- 查：叠加暂停（先锁屏再全屏）、hold 期间 advanceNow 换片、hold 期间改速度，锚点是否指向正确位置
- 验证：产出「锚点边界表」——每个场景的锚点写入/消费是否正确

### 任务 A.3：AVFoundation 陷阱 —— looper 克隆边界
- 文件：`Sources/PicCore/Playback/PlayerController.swift`
- 查：`preferredMaximumResolution`、`audioTimePitchAlgorithm`、`preferredForwardBufferDuration` 设在 looper 前 vs 后，克隆时哪些属性保留
- 验证：产出「属性挂载位置表」——每个属性的挂载点、是否影响克隆

### 任务 A.4：进程生命周期 —— AVPlayerItem 释放
- 文件：`PlayerController.swift`（`load`/`stop`）、`WallpaperWindowController.swift`
- 查：`load(url:)` 每次新建 item + 重建 looper，旧 item 是否释放；`player.remove()` + looper 引用循环
- 验证：产出「生命周期表」——每次 load/stop 的对象创建与释放路径

### 任务 A.5：进程生命周期 —— Timer/观察者配对
- 文件：`AppDelegate.swift`（`ticker`）、`SystemRotationScheduler.swift`、`FrameDriver.swift`、`LoopProbe.swift`、各 Watcher
- 查：每个 Timer/addObserver 是否有 invalidate/remove 配对；`applicationWillTerminate` 是否唯一收口
- 验证：产出「配对表」——每个注册点的注销点

---

## 3. Phase B：线程安全 + 注释一致性 + 稳定性

### 任务 B.1：线程安全 —— 25 处 assumeIsolated 逐个核对（发现）
- 文件：全仓 25 处 `assumeIsolated`
- 查：每处的回调投递来源（NSWorkspace 通知 queue、CGDisplay C 回调、IOPS C 回调、Timer、asyncAfter），是否都先 hop 到主队列
- 验证：产出「assumeIsolated 核对表」——每处的投递来源、是否合法、风险

### 任务 B.2：线程安全 —— nonisolated(unsafe) 4 处 + @unchecked Sendable 3 处（发现）
- 文件：`DisplayWatcher.swift`（reconfigHandlers）、`PowerWatcher.swift`（powerHandlers）、`LoopProbe.swift`（tokens）、`ProcessTranscodeRunner.swift`、`LineSplitter`
- 查：每处读写是否全部在锁内；@unchecked 的「我保证」是否成立
- 验证：产出「Sendable 审计表」

### 任务 B.3：注释-代码一致性 —— 191 处反重构警告抽样（发现）
- 文件：全仓
- 查：抽样 20 条「顺序不可换/必须门控/刻意不用某 API」，验证代码当前是否真的这么做
- 验证：产出「漂移清单」——哪些注释已与代码脱节

### 任务 B.4：稳定性 —— 下标越界 + 磁盘满失败路径（发现）
- 文件：`TranscodeQueue.swift`、`FpsTranscodeQueue.swift`、`RotationController.swift`、`SettingsView.swift`
- 查：所有 `[index]`/`[0]`/`first!` 的边界保证；磁盘满时 moveItem/trashItem 失败路径
- 验证：产出「越界/失败路径清单」

---

## 4. Phase C：并发交错 + 播放切换 + 隐私

### 任务 C.1：并发交错 —— 锁屏瞬间删壁纸（发现→可转修复）
- 文件：`AppDelegate.swift`（`deleteCurrentWallpaperNow`）、`HoldArbiter.swift`
- 查：锁屏 set hold 与 deleteCurrent 的 advance 交错，advance 触发的 loadPlayback→arbiterApply 是否绕过 hold
- 验证：产出结论；若确认是 bug，转入修复任务（写交错测试→红→改→绿）

### 任务 C.2：并发交错 —— 转码中换目录
- 文件：`TranscodeQueue.swift`（`runJob` 的 temporaryURL/outputURL 计算时机）、`TranscodeOutputNaming.swift`
- 查：换目录瞬间，正在跑的 job 的产物落在旧目录还是新目录
- 验证：产出结论

### 任务 C.3：播放切换稳定性 —— 锚点错位（P3-N4 深挖）
- 文件：`HoldArbiter.swift`、`RotationController.swift`
- 查：hold 期间轮换定时器仍在跑，解锁后播的是另一条，resumeAnchor 来自旧片 → seek 错位
- 验证：产出结论；若确认是 bug，转修复任务

### 任务 C.4：隐私 —— 日志不泄漏文件名
- 文件：全仓 `emit(...)` 调用点
- 查：每处 emit 是否遵守「不打印路径/文件名」；`deleteCurrentWallpaperNow` 的 `name=\(lastPathComponent)` 是否刻意
- 验证：产出「隐私泄漏清单」

---

## 5. Phase D：常驻成本 + UI/UX + 注释合理性

### 任务 D.1：常驻隐性成本 —— 首屏时间 + 后台消耗
- 文件：`AppDelegate.swift`（bootstrap）、`MediaLibrary.swift`（scan 串行探测）、`ProcessWhichProbe`（同步 waitUntilExit）
- 查：启动路径同步阻塞点；24 小时后台的 CPU/内存
- 验证：产出「成本清单」

### 任务 D.2：UI/UX —— 菜单「暂停」语义 + 转码可控性 + 无障碍
- 文件：`MenuContentView.swift`、`SettingsView.swift`、`SettingsComponents.swift`（GlowSlider/GlowToggle）
- 查：isManuallyPaused 不区分「用户暂停」vs「系统压住」；转码队列无取消；自绘控件无 VoiceOver
- 验证：产出「UX 问题清单」

### 任务 D.3：注释合理性 —— 对照 CLAUDE.md 纪律全量过
- 文件：全仓（精简后的干净基线）
- 查：必留四类是否完整、必删五类是否清干净、注释里的单位/量纲/常量值是否准确
- 验证：产出「注释合理性清单」

---

## 6. 修复阶段：发现清单 → TDD 循环

> Phase A→D 的「发现任务」产出的是**发现清单**。每个确认的 bug，按严重度排序，逐个走 TDD 红绿循环：

```
对每个 bug：
1. RED   写复现失败的测试（临时探针或正式用例）
2. GREEN 写最少代码修复
3. 回归  swift test --disable-sandbox 全绿
4. 提交
```

修复顺序按严重度（Critical > Major > Minor），Critical 级发现须先修才能继续后续发现任务。

---

## 7. 验收（完成标准）

1. Phase A→D 的每个发现任务都产出「清单」或「确认无问题」结论
2. 每个 Critical/Major bug 都有「能照抄的正确方案」（代码或设计）
3. 每个修复都走 TDD 红绿循环，`swift test --disable-sandbox` 全绿
4. 注释精简达标（占比 ≤ 13%），229 处反重构警告不减
