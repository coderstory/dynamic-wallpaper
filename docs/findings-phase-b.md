# Phase B 发现清单

> 深度审计主线 Phase B：线程安全 + 注释一致性 + 稳定性。

## B.1 assumeIsolated 25 处核对

### 结论：24 处合法，1 处依赖协议约定（无 Critical/Major）

全部 25 处逐一核对投递来源：

| 类别 | 处数 | 投递来源 | 判定 |
|---|---|---|---|
| NSWorkspace 通知（queue: .main） | LockWatcher 2、FullscreenDetector 3、DisplayWatcher 3 | `queue: .main` | ✅ 合法 |
| C 回调桥接（CGDisplay / IOPS） | DisplayWatcher reconfigTrampoline 1、PowerWatcher powerTrampoline 1 | `DispatchQueue.main.async` 先 hop 再 assume | ✅ 合法 |
| Timer / RunLoop.main | FrameDriver 2、LoopProbe 3、RotationController 1、AppDelegate tick 1 | `RunLoop.main.add` + Timer 回调在主线程 | ✅ 合法 |
| asyncAfter | FrameDriver 1、LoopProbe 1、AppDelegate 2 | `DispatchQueue.main.asyncAfter` | ✅ 合法 |
| 闭包回调（onBatchFinished 等） | AppDelegate 2 | 主 actor 内联回调 | ✅ 合法 |

### 发现 B1-1（🔵 Nit）：`RotationController.reschedule` 的 assumeIsolated 依赖协议约定

- **位置**：`RotationController.swift:209`
- **现象**：`scheduler.schedule(after:) { MainActor.assumeIsolated { ... } }` 的 `assumeIsolated` 依赖「`RotationScheduling` 实现总把 body 投递到主线程」。生产实现 `SystemRotationScheduler` 满足（`RunLoop.main.add`），但这是**协议约定**而非编译器保证——若有人写非主线程 scheduler 实现就崩。
- **判断**：当前生产实现正确，不构成 bug，但协议缺少「必须主线程投递」的显式契约，属架构脆弱点。

## B.2 Sendable 边界审计

### 结论：3 处 @unchecked Sendable + 4 处 nonisolated(unsafe) 保证成立（通过）

- `LineSplitter`（@unchecked Sendable）：`buffer` 所有写都在 `feed()` 的 `lock` 内，`emit` 只读捕获。✅
- `ProcessTranscodeRunner`（@unchecked Sendable）：`process`/`cancelled` 读写都在 `lock` 内。✅
- `reconfigHandlers`/`powerHandlers`（nonisolated(unsafe)）：NSLock + 单槽表，读写全在锁内。✅

### 发现 B2-1（🔵 Nit）：`LineSplitter.feed` 在锁内调用 `emit`

- **位置**：`ProcessTranscodeRunner.swift:109-110`
- **现象**：`emit(line)` 在 `lock.lock()` 块内被调用。当前 `emit` 是 `Task { @MainActor }` 异步派发，不会同步阻塞，无死锁。但若将来 emit 实现变成同步阻塞，会卡锁。
- **方案**：把 emit 移出锁块（先收集行、锁外再逐个 emit），或注释明确「emit 必须非阻塞」。

## B.4 稳定性崩溃面

### 结论：下标越界风险不存在（通过）

- `TranscodeQueue.run()` 的 `for index in jobs.indices` 是**值快照**，循环中 `enqueue` 追加的新 job 不会进入本轮。
- `armSourceDeletion` 只原地改 `deletesSource` 字段，不增删元素。
- `runJob(at index:)` 跨 `await` 访问 `jobs[index]` 安全：`await` 期间唯一可能改数组的 `enqueue` 是 append，不影响已求值的 indices 快照。
- Phase A 的改动（invalidateResumeAnchor 等）不涉及 jobs 数组时序。

### 磁盘满/权限失败路径

- `moveItem`/`trashItem` 失败均有 `try?` 兜住，P1-5 加的删源校验（`output_unverified`）在失败时保留源文件。✅

## B.3 注释-代码一致性

### 发现 B3-1（🟠 Major，已修）：`deletesSource` 注释漂移

- **位置**：`TranscodeQueue.swift:31-32`（`TranscodeJob.deletesSource` 字段注释）
- **现象**：注释写「转码成功后删源」「成功即永久删除」，但 P1-5 加删源校验后，实际语义是「转码成功 **且** 产物校验可用后」才删，产物不可用标 `output_unverified` 保留源。
- **风险**：这是「注释还权威、代码已变」的典型——AI 会严格照「成功即删除」理解，从而在别处（比如重构删源逻辑时）漏掉产物校验这个关键闸。
- **修法**：已更新注释，明确「删源时机 = 成功 + looksLikeUsableOutput 校验通过」。

### 其余抽样核对（无漂移）

- `setRate 必须门在应当播放之后`（AppDelegate:398）→ 代码 `if shouldPlay { setRate } else { setDesiredRate }`，门控存在，一致 ✅
- `四个 Watcher 必须强持有，谁创建谁 stop` → `applicationWillTerminate` 与 `wiring` 配对，一致 ✅
- `invalidateCache 必须同步排在重扫之前` → 各重扫入口均先 invalidate，一致 ✅（P0-2 修复后已补 requestFolderNow）

### 结论

191 处反重构警告抽样 + 前六轮改动点聚焦核对，发现 1 处真实漂移（deletesSource），已修。其余一致。
