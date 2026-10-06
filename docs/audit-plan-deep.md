# Pic 深度审查计划（第七轮 · 面向 AI 协作）

- 制定日期：2026-10-06
- 前提：本项目**纯面向 AI**——代码与注释的唯一读者是 AI。注释可以直接写核心点、可以精简；代码不必为「人类可读」牺牲性能与简洁。
- 背景：前六轮已完成 P0/P1/P2 修复（327 测试全绿，11 个提交已 push）。本计划不再重复已知项，专攻**一般性审查会忽略的深层次问题**。

---

## 0. 为什么需要一轮专门的「深层次」审查

前六轮抓到的问题有个共同点：都是「单一文件、单一函数里的显性 bug」。但面向 AI 的项目有几类风险是**静态扫描和逐函数审查都抓不到**的：

1. **跨文件不变量被 AI 破坏**：注释里写了 191 处「不得/必须/顺序/不可」，但 AI 改 A 文件时看不到 B 文件对 A 的隐性依赖。注释说「顺序不可换」，改完代码后注释还在、语义却已漂移——**注释与代码的一致性**本身是一类 bug。
2. **运行时序问题**：`@MainActor` + `Task { }` + `await` 的时序交错，单测跑单点不跑交错。锁屏瞬间点菜单、转码中换目录、启动瞬间拔盘——这些**并发交错**不会出现在单测里。
3. **面向 AI 的注释反噬**：注释写得越「权威」，AI 越不敢质疑。一句过时的反重构警告，比没有注释更危险（AI 会严格照着一个错误的规则执行）。

---

## 1. 审查维度（审查专家判断 · 按项目本质重排）

> **维度设计的判断依据**：这是一个「macOS 菜单栏常驻 + 桌面层视频壁纸」应用——零第三方依赖、零网络、零数据库、零用户输入拼接、argv 全数组。它不是通用 Web 服务，所以传统「安全/性能」维度的权重**必须按项目本质重排**。下面是重排后的维度，标注了「用户提出」vs「专家补充」vs「权重重校准」。

### 1.1 命门维度（P0，专家补充——用户清单里没有）

| 维度 | 为什么是命门 | 关键文件 |
|---|---|---|
| **状态机正确性** | 这个项目本质是一个状态机：`Watcher(6 信号源) → HoldArbiter(veto 集合) → PlayerController`。它的正确性 = 「6 个布尔信号 → 1 个 shouldPlay 决策」在**所有 2⁶ 组合 + 时序交错**下都正确。前六轮抓的 bug（恢复速度回落、暂停语义、锚点错位）全是这条链上的。决策一错，用户看到的就是「壁纸盖在全屏应用上」或「锁屏后还在放」——产品的核心承诺 | HoldArbiter、HoldReason、PlaybackDecision、6 个 Watcher |
| **AVFoundation 隐蔽陷阱** | `AVPlayerLooper` 克隆语义、`preferredMaximumResolution`/`audioTimePitchAlgorithm`/`preferredForwardBufferDuration` 设在 looper 之前 vs 之后、`AVQueuePlayer` 队列操作时序——这些只有踩过坑才知道要查。用户提的「播放切换稳定性」是对的，但没点出这些具体 API 陷阱 | PlayerController、PlaybackRouter |
| **进程生命周期/资源回收** | 这个 app **不退出**（关窗只隐藏）。换目录 100 次内存是否线性增长？重扫是否释放旧 AVPlayerItem？转码 Process 句柄、Timer、观察者长跑几天是否泄漏？**常驻进程的泄漏是「慢慢死」，比崩溃更阴险，单测测不出** | AppDelegate、PlayerController、各 Watcher、TranscodeQueue |

### 1.2 高优先级维度（P1）

| 维度 | 核心问题 | 关键文件 |
|---|---|---|
| **线程安全**（用户提出） | `assumeIsolated` 25 处、`nonisolated(unsafe)` 4 处、`@unchecked Sendable` 3 处——每一处都是「AI 猜错隔离域就崩」的雷 | 所有 Watcher、ProcessTranscodeRunner、LineSplitter |
| **注释-代码一致性**（专家补充，面向 AI 独有） | 191 处反重构警告是否仍准确；注释里「顺序/门控/刻意不用某 API」的断言与代码是否脱节。**一条过时的权威注释比没有注释更危险** | 全仓，重点 PlayerController、HoldArbiter、AppDelegate |
| **并发交错时序**（用户提出） | 跨 `await` 的状态、锁屏+菜单、转码+换目录、启动+拔盘 | AppDelegate、FpsTranscodeQueue、TranscodeQueue |

### 1.3 中优先级维度（P2）

| 维度 | 核心问题 | 关键文件 |
|---|---|---|
| **常驻隐性成本**（专家把「性能+资源占用」合并重校准） | 首屏时间（菜单栏 app 用户期望秒开）、24 小时后台的 CPU/内存/功耗、44 处 FileManager 调用 | AppDelegate.bootstrap、MediaLibrary、ConvertedLibrary |
| **代码稳定性**（用户提出） | 崩溃面：数组越界、可选值、磁盘满、权限拒绝、JSON 损坏 | 全仓 `[index]`、`first!`、IO 错误路径 |

### 1.4 低优先级维度（P3）

| 维度 | 核心问题 | 关键文件 |
|---|---|---|
| **隐私**（专家从「安全」里拎出来单列） | 日志不泄漏文件名（本项目独有红线）、符号链接纵深、自启动 plist 路径注入。**注意：这个项目没有传统注入面**（argv 全数组、零网络、零 SQL），把「安全」当独立维度去扫 SQL/命令注入是浪费时间 | MediaLibrary、ConvertedLibrary、LaunchAgentWriter、各 emit 调用点 |
| **UI 布局**（用户提出） | 固定 780pt 宽度溢出、磁贴网格、长文件名截断、空态 | SettingsComponents、SettingsView、两个 Section |
| **UX 交互**（用户提出） | 菜单「暂停」语义、降帧/转码可控性、无障碍、反馈即时性 | MenuContentView、SettingsView、FpsTranscodeSection |
| **注释合理性**（用户提出，面向 AI 独有） | 注释是否「帮 AI 少犯错」还是「浪费注意力」；单位/量纲/常量值的精度 | 全仓对照 CLAUDE.md 注释纪律 |

### 1.5 权重重校准的三个关键判断（专家意见）

1. **「代码安全」降权**：零第三方依赖 + 零网络 + 零 SQL + argv 全数组 → 传统注入面几乎为零。安全审查的正确落点是「隐私」（日志不泄漏文件名）和「符号链接纵深」，不是逐项扫注入。**把安全列成一个靠前的独立维度，是拿通用项目的模板硬套**。
2. **「性能」与「资源占用」合并为「常驻隐性成本」**：壁纸播放器没有高并发/大数据，O(n²) 已修。真正的性能问题是「首屏时间」和「24 小时后台的隐性消耗」，这两个是同一个维度的两面。
3. **补上三个命门维度**：状态机正确性、AVFoundation 陷阱、进程生命周期——这三样是这个项目「正确性」的根基，比「UI/UX」重要一个量级。用户清单里没有显式列它们，但它们才是深水区。

---

## 2. 每个维度的具体审查点（这是计划的核心）

### 维度 A：状态机正确性（命门，专家补充）

**核心命题**：`shouldPlay = holds.isEmpty` 这个决策，必须在 6 个信号源的 2⁶ 组合 + 任意时序下都正确。前六轮抓到的「恢复速度回落」「暂停语义」「锚点错位」全是这条链的 bug。

1. **决策链完整走查**：6 个 `HoldReason`（manualPause / fullscreen / screenLocked / displayAsleep / systemSleeping / battery）的每个 set 入口，是否都最终汇到 `HoldArbiter.set`？有没有绕开仲裁器直连 `PlayerController` 的地方（注释纪律明令禁止，但需验证）？
2. **锚点语义的边界**：`resumeAnchor` 只在 ∅→非∅ 写入。叠加暂停（先锁屏再全屏）、hold 期间 `advanceNow` 换片、hold 期间改速度——锚点是否总指向正确位置？`arbiterSeek` 对已换片的 seek 是否错位？
3. **decision 的幂等与重放**：`set` 里 `before != after` 才 apply；`applyCurrentDecision` 绕过 set。启动时「四个 Watcher 已置位」这个前提，AI 若调整 wiring 顺序就会破坏。审计这个前提是否被注释锁死。
4. **`isManuallyPaused` 的语义泄漏**：它是「只读派生量」，但菜单/UI 用它判断「继续 vs 暂停」。系统压住（非 manualPause）时它返回 false——UI 语义是否正确？

### 维度 B：AVFoundation 隐蔽陷阱（命门，专家补充）

1. **looper 克隆边界**：`preferredMaximumResolution`、`audioTimePitchAlgorithm` 注释说「设在 looper 之前，克隆体不带」。但 `preferredForwardBufferDuration`（=3.0）呢？它在 `item` 上，克隆时保留吗？循环下一圈 buffer 是否掉回默认？
2. **先插后扫的闪屏窗口**：`load(url:)` 先 `insert(item, after: nil)` 再 `remove` 旧 item，保队列非空防闪屏。AI 若「优化」成先 remove 再 insert，闪屏回归。审计注释警示是否够强。
3. **`stop()` 三步顺序**：`disableLooping → looper=nil → removeAllItems`。与 `load` 交错（stop 后立刻 load）是否有窗口。
4. **克隆 item 的属性冻结**：`AVPlayerLooper` 每个 loop 边界克隆模板 item，模板的属性在 init 时冻结。哪些「改设置当场生效」的诉求（rate/volume/muted）是挂在 player 上而非 item 上？有没有漏挂到 item 导致「设置改了但循环下一圈失效」？

### 维度 C：进程生命周期/资源回收（命门，专家补充）

1. **AVPlayerItem 释放**：`load(url:)` 每次新建 item + 重建 looper，旧 item 是否真的被释放？`player.remove()` + looper 引用循环？
2. **换目录 100 次**：`rescanAndApply` 反复执行，`MediaLibrary.cached`、`ConvertedLibrary` 每次 new、`AVURLAsset` 探测——是否有线性增长的缓存/对象？
3. **Timer/观察者配对**：`ticker`、`SystemRotationScheduler.timer`、`FrameDriver.fallbackTimer`、`LoopProbe.sampler`、所有 `addObserver`（通知/DistributedNotification/CGDisplay/IOPS）——每个是否有 invalidate/remove 配对？`applicationWillTerminate` 是否是唯一收口？
4. **Process 句柄**：`ProcessTranscodeRunner.process` 在 `clearProcess` 置 nil，但转码中途退出/崩溃时，句柄是否泄漏？`cancel()` 的 `terminate()` 后句柄清理路径。

### 维度 1：线程安全（P1）

**为什么这是首要**：前六轮只修了 1 处 `assumeIsolated` 越界（P1-3）。还有 25 处 `assumeIsolated` 没逐个核对其**合法前提**——每处都要问：「这个回调真的保证在主线程/主 actor 上投递吗？」

具体清单：

1. **逐个审计 25 处 `assumeIsolated`**：对照每个回调的投递来源（`NSWorkspace` 通知的 `queue`、`CGDisplay` C 回调、`IOPS` C 回调、`Timer`、`DispatchQueue.asyncAfter`）。P1-3 修了 LockWatcher，但 DisplayWatcher 的 `reconfigTrampoline`（C 回调 → `DispatchQueue.main.async` → `assumeIsolated`）和 PowerWatcher 的 `powerTrampoline` 是否**每一处**都先 hop 到主队列再 assume？
2. **`nonisolated(unsafe)` 4 处**：`reconfigHandlers`、`powerHandlers`、`LoopProbe.tokens` 等。它们靠「NSLock + 单槽表」保护，但 AI 增删代码时极易漏加锁。审计每处的读写是否**全部**在锁内。
3. **`@unchecked Sendable` 3 处**：`ProcessTranscodeRunner`、`LineSplitter`、测试里的 Fake。`@unchecked` 是「我保证，编译器你别管」——审计这个保证是否真的成立，尤其是 `LineSplitter` 的 `buffer` 跨 `readabilityHandler`（后台队列）与 `run`（调用线程）两个来源的写入。
4. **跨 `await` 的下标访问**：`runJob(at index:)` 用 `index` 跨多个 `await` 访问 `jobs[index]`。前几轮判断「当前时序安全」，但 AI 若在 `scan`/`enqueue` 里加并发，这个假设立刻崩。审计是否需要改成按 `id` 查找。

### 维度 2：注释-代码一致性（本项目独有，最易被 AI 破坏）

**核心命题**：面向 AI 的注释是「给 AI 的约束指令」。约束指令与代码脱节 = 一个会主动误导下一个 AI 的 bug。

具体清单：

1. **逐条核对 191 处反重构警告**：每条「顺序不可换/必须门控/刻意不用某 API」都要验证——代码当前是否真的这么做的？例如：
   - `setRate 必须门在「应当播放」之后` → 查所有 `setRate`/`setDesiredRate` 调用点是否都门控了
   - `四个 Watcher 必须强持有，谁创建谁 stop()` → 查 `applicationWillTerminate` 是否与 `wiring()` 严格配对
   - `invalidateCache 必须同步排在重扫之前` → 查所有 `rescanAndApply` 调用点
2. **反查「代码已改、注释没跟」**：前六轮改了不少代码（P0/P1/P2），是否有改动让某条旧注释失效？例如删源校验（P1-5）后，`TranscodeJob.deletesSource` 的注释「成功即永久删除」是否还准确（现在是「校验后删除」）。
3. **注释的「进化叙事」残留**：CLAUDE.md 明令禁止「此前/改成/旧实现」这类 AI 能自己 `git log` 的叙事。扫一遍是否有前几轮修复后遗留的「此前这里会 X」注释。

### 维度 3：并发交错时序

**单测测不到的交错，是面向 AI 项目最大的盲区。**

具体清单：

1. **锁屏瞬间点「删除当前壁纸」**：`deleteCurrentWallpaperNow` 先 `advanceNow` 再 `trashItem`。若此刻 arbiter 正因锁屏 set hold，advance 触发 `loadPlayback` → `arbiterApply` 会不会绕过 hold 拉起播放器？
2. **转码中换目录**：`TranscodeQueue` 的 `naming.rootProvider` 是闭包（换目录跟着走），但**正在跑的 job** 的 `temporaryURL` 是入队时算好的还是运行时算的？换目录瞬间，`runJob` 里的 `outputURL` 落在旧目录还是新目录？
3. **启动瞬间拔盘**：`bootstrapAfterWiring` 里 `rescanAndApply` → `startWallpaper` 之间拔盘，`library.scan` 返回 folderMissing，但 `startWallpaper` 可能已拿到旧 folder 的 URL。
4. **降帧 scan 与 run 并发**：`FpsTranscodeQueue.scan()` 和 `run()` 都改 `jobs`。若用户在 scan 未完成时点「开始降帧」，`run()` 读到的是半成品的 `jobs` 吗？（`isScanning` 门控是否存在竞态窗口）

### 维度 4：资源占用

1. **AVPlayerItem/AVPlayerLayer 生命周期**：`load(url:)` 每次新建 item + 重建 looper，旧 item 是否真的被释放？（`player.remove()` + looper 引用循环？）
2. **Timer 泄漏**：`ticker`、`SystemRotationScheduler.timer`、`FrameDriver` 的 fallbackTimer、`LoopProbe.sampler`——每个 Timer 是否有对应的 invalidate？`deinit` 兜底是否覆盖？
3. **观察者注销配对**：所有 `addObserver`（通知、DistributedNotification、CGDisplay 回调、IOPS source）是否都有 `removeObserver`/`unregister` 配对？`applicationWillTerminate` 是否是唯一收口？
4. **内存缓存**：`MediaLibrary.cached`、`FrameRateTable`、`TranscodeQueue.jobs` 无上限？`advances`（已判定不修，但记录）。壁纸视频的解码缓冲 `preferredForwardBufferDuration = 3.0` 是否合理？

### 维度 5：启动/切换/播放速度

1. **启动路径的同步阻塞**：`applicationDidFinishLaunching` → `wiring()`（四个 watcher start 里有没有同步 IO/探测？）→ `bootstrapAfterWiring`（await）。任何一步同步阻塞都会延迟菜单栏图标出现。
2. **首屏全量探测**：`MediaLibrary.scan` 对每个视频 `await probe.metadata`（开 AVURLAsset 读帧率/时长）。几百个视频 = 几百次 asset 打开，首播延迟多久？能否异步分批 + 先播第一个？
3. **切换速度**：`load(url:)` 新建 item 的开销、`preferredMaximumResolution` 是否影响首帧。
4. **`waitUntilExit`**：`ProcessWhichProbe.whichFFmpeg` 是同步 `waitUntilExit`，在启动路径上吗？（`refreshFFmpegAvailability` 启动时调一次）

### 维度 6：播放切换稳定性

1. **AVPlayerLooper 克隆边界**：`preferredMaximumResolution`、`audioTimePitchAlgorithm` 设在 looper 之前（注释说克隆体不带），但 `preferredForwardBufferDuration` 呢？它克隆吗？改设置后循环下一圈是否掉回默认？
2. **先插后扫的闪屏窗口**：`load(url:)` 的「先 insert 后 remove 旧 item」——这段代码是「队列全程非空防闪屏」，但 AI 若「优化」成先 remove 再 insert，闪屏就回来了。审计注释是否足够警示。
3. **seek 锚点**：`HoldArbiter.resumeAnchor` 只在 ∅→非∅ 写入。多屏、多 reason 叠加、hold 期间换片（advanceNow）时，锚点是否指向正确位置？（P3 已列 N4「hold 期间轮换锚点错位」，深度确认）
4. **`stop()` 三步顺序**：`disableLooping → looper=nil → removeAllItems`，注释说顺序不可换。审计 `stop` 与 `load` 交错时（stop 后立刻 load）是否有窗口。

### 维度 7：UI 布局

1. **固定宽度 780pt 的溢出**：长文件名（`truncationMode(.middle)`）、长命令串（`textSelection`）、安装途径弹层 560pt。极端内容（超长目录名、超长 ffmpeg 路径）是否撑破布局？
2. **磁贴网格**：`LazyVGrid` 2 列，`Tile` 内 `ChoiceGrid3x2`（6 格）在窄窗口下的换行。
3. **空态/半空态**：`isEmpty` 与「有目录但 0 视频」的区分、`playableCount` 归零逻辑（P1-6 已修状态条，但空态图标/文案是否一致）。

### 维度 8：UX 交互

1. **菜单「暂停」语义**（P3 已列）：`isManuallyPaused` 不区分「用户暂停」vs「系统压住」。锁屏中点「暂停」叠加 manualPause，解锁后仍暂停。深挖：菜单是否该显示「继续」vs「已被锁屏压住」。
2. **降帧/转码的可控性**：转码队列无暂停/取消（P3 F8 已列）。一批几十个 MKV 转起来停不掉——UX 硬伤。
3. **反馈即时性**：滑杆 onChanged 直通 store+applier，但 `persist` 只在 onEnded——拖动中杀进程会丢设置吗？
4. **无障碍**：自绘 GlowSlider 无 VoiceOver 值（P3 已列）、GlowToggle 缺 on/off 状态。

### 维度 9：代码安全

1. **路径穿越**：`MediaLibrary` 有「符号链接解析后必须仍在根内」的纵深（`resolved.hasPrefix(rootRealPath + "/")`），但 `ConvertedLibrary`、`TranscodeCandidateFilter` 是否也有同样的防护？还是只靠「不跟进符号链接」？
2. **命令注入**：argv 全数组形态（已确认无拼接），但 `nice -n 10` + ffmpegPath 的 path 来自 `ExternalToolLocator` 探测，若探测路径被污染？
3. **隐私**：日志不泄漏文件名（注释纪律），但 `deleteCurrentWallpaperNow` 的 `emit("PIC_DELETE_OK name=\(victim.lastPathComponent)")` 泄漏了文件名——这是刻意的（删除确认需要）还是疏漏？审计所有 emit 是否都遵守「不打印路径/文件名」的纪律。
4. **LaunchAgent 写入**：`LaunchAgentWriter.write(executablePath:)` 的 executablePath 来自 `Bundle.main.executablePath`，写入 `~/Library/LaunchAgents`。权限、路径注入。

### 维度 10：代码稳定性

1. **数组下标越界**：`jobs[index]`、`items[nextIndex]`、`rotationChoicesMinutes[i]`——所有下标访问是否都有边界保证？尤其 `modeIndex` 的 `PlayMode.allCases[i]`（i 来自 UI，若 allCases 变了）。
2. **可选值崩溃面**：`first!`、`[0]`（已扫到 0 处，但再确认）、隐式解包。
3. **磁盘满/权限拒绝**：转码写 `.tmp`、`moveItem`、`trashItem` 的失败路径是否都 `try?` 兜住？P1-5 加了删源校验，但 `moveItem` 失败（磁盘满）时 `output_conflict` 的源文件保留了吗？
4. **JSON 损坏**：`FrameRateTable.load` 静默返回空表（`try?` 兜底），但「表损坏 → 全量重探」会不会导致降帧队列把已降帧文件重新排队（P0-1 类历史问题）？

### 维度 11：性能（剩余项）

1. **扫描串行**：`MediaLibrary.scan` 逐文件 `await probe.metadata`，串行。几百个文件的首扫时长。能否 `async let` 并发探测？
2. **逐文件 IO**：`ConvertedLibrary.scan`、`FrameRateTable.hasLiveDerivative` 里逐文件 `attributesOfItem`。
3. **主线程阻塞**：`ProcessWhichProbe` 的同步 `waitUntilExit`、`applyWindowChrome` 的 `asyncAfter`。

### 维度 12：注释合理性（面向 AI 的独特维度）

1. **对照 CLAUDE.md 注释纪律**：逐条检查「必留」四类（反重构警告/契约/跨文件不变量/非显然坑）是否完整，「必删」五类（复述行为/演变叙事/出处证据/验证自解说/告警符号）是否混入。
2. **注释是否「帮 AI 少犯错」还是「浪费注意力」**：每条注释问 CLAUDE.md 的那句「这句话是在帮 AI 少犯一条错，还是在浪费它的注意力？」
3. **过度注释 vs 缺注释**：`ProcessTranscodeRunner` 那条 64KB 管道注释（「stderr 必须丢 /dev/null，否则……必现」）是**极佳**的反重构警告（AI 极可能「优化」成挂 Pipe）。但反例：有没有「复述代码行为」的注释没删干净？
4. **注释的精度**：AI 会严格照注释执行。注释说「参数单位是秒」，代码却是毫秒——这种注释本身就是 bug。逐条核对注释里的单位/量纲/常量值。

---

## 3. 执行方式

> **本节已迁移到 `audit-plan-impl.md`**（可执行实施计划）。这里只保留维度→Phase 的映射关系，原子任务、TDD 验证、发现/修复分离都在实施计划里。两份文档的分工：本文件是**设计文档**（「哪里该查、为什么」），`audit-plan-impl.md` 是**实施计划**（「怎么查、怎么改、怎么验证」）。

Phase 映射（详见实施计划）：

**Phase A（命门，最高价值）**：
- 维度 A 状态机正确性：6 信号 → 决策链完整走查 + 锚点边界
- 维度 B AVFoundation 陷阱：looper 克隆边界 + 属性挂载位置
- 维度 C 进程生命周期：AVPlayerItem 释放 + Timer/观察者配对

**Phase B**：
- 维度 1 线程安全：25 处 `assumeIsolated` 逐个核对投递来源
- 维度 2 注释-代码一致性：191 处反重构警告抽样 + 前六轮改动后的注释漂移
- 维度 10 稳定性：下标越界 + 磁盘满失败路径

**Phase C**：
- 维度 3 并发交错：4 个交错场景逐一走查（可写临时并发测试）
- 维度 6 播放切换稳定性：锚点错位、stop/load 交错
- 隐私：日志不泄漏文件名 + 符号链接纵深

**Phase D（收尾）**：
- 常驻隐性成本：首屏时间 + 后台消耗
- 维度 7/8 UI/UX：布局溢出、菜单语义、无障碍
- 维度 12 注释合理性：对照 CLAUDE.md 纪律全量过一遍

每个发现都要：**位置 + 级别 + 根因 + 正确方案 + 可照抄的代码/设计**（延续前六轮的输出标准）。

---

## 4. 验收标准

1. 每个 Critical/Major 发现都给出「能照抄的正确方案」（代码或设计），不允许「建议优化」半句。
2. 每个发现都标注「代码依据或复现证据」（零臆造）。
3. 修复后 `swift test --disable-sandbox` 全绿，且新增回归用例覆盖。
4. 注释改动遵循 CLAUDE.md 纪律：新增反重构警告、删除演变叙事。

---

## 5. 与前六轮的关系

本计划**不重复**前六轮已修项（P0/P1/P2 全部 + 部分 P3）。聚焦：
- **注释-代码一致性**（全新维度，前六轮未涉及）
- **并发交错时序**（前六轮只修了单点，未系统审查交错）
- **面向 AI 的注释合理性**（本项目独有，前六轮只做「写得对不对」，未做「注释与代码是否脱节」）

---

## 6. 注释现状分析（面向 AI 的独立审查对象）

> 本节是**分析结论**，回答「这个项目的注释到底处于什么状态、哪里有问题」；第 7 节「注释精简」才是**执行**。二者分开：先看懂，再动手。

### 6.1 总量与占比（实测，2026-10-06）

| 指标 | 数值 |
|---|---|
| 源码总行数 | 7185 |
| 含 `//` 的行数 | 1261（占比 **17.6%**） |
| 整行注释（`///`/`//` 开头） | 307 行（4.3%） |
| 行内注释（代码后 `//`） | 954 行（13.3%） |
| 反重构警告/契约（含「不得/必须/顺序/刻意/必现/否则」） | 229 行 |
| `MARK:` 分组标记 | 65 处 |
| 演变叙事（此前/先前/改成/原来/曾经） | 4 处 |
| 复述命名/行为（启发式） | ~11 处 |
| 空注释行 | 1 处 |

### 6.2 结构判断：注释占比高，但「病态」和「健康」各占多少

**结论：17.6% 对「纯面向 AI」项目不算离谱，但其中有约 81 处是明确的「浪费注意力」废注释，另有约 200 行「中性描述」可压缩。**

拆解：

1. **229 处反重构警告/契约 —— 这是核心资产，一个字都不能删**。AI 最大的风险是「自作主张优化它认为冗余的代码」，这些「顺序不可换/刻意不用某 API/必现」的注释正是防这个的。它们占注释总量的 18%，却是注释**价值最高**的部分。
2. **954 行行内注释 —— 主因**。其中混着三类：该留的反重构警告、该删的复述、以及介于两者之间的中性描述。行内注释是注释占比高的直接来源。
3. **65 处 MARK + 4 处演变叙事 + 11 处复述 + 1 空行 ≈ 81 处 —— 明确的废注释**，删了不损失任何「帮 AI 少犯错」的信息。

### 6.3 典型案例（正反两面）

**✅ 该留的（反重构警告，价值极高）**：

```swift
// stderr 必须丢给 /dev/null，不能挂一个不读的 Pipe：管道缓冲区（约 64KB）一满，
// ffmpeg 就阻塞在写 stderr 上，进程永不退出 —— 表现是 waitUntilExit 挂住、队列卡死、
// CPU 归零（转长视频必现）。
```
（`ProcessTranscodeRunner.swift`）——AI 极可能「优化」成挂 Pipe，这条注释直接防住一个必现的生产事故。

**❌ 该删的（演变叙事，AI 会自己 `git log`）**：

```swift
/// 先前这里又除了一次 100，进度条最大只有 0.96pt，肉眼恒为空。
```
（`TranscodeSection.swift:133`）——这是前几轮修 progress 量纲时遗留的「此前」叙事，CLAUDE.md 明令禁止。

**⚠️ 已漂移的（注释-代码不一致，最危险）**：

```swift
// 「成功即永久删除」  ← P1-5 加删源校验后，实际语义已变成「校验产物可用后才删」
```
这类「注释还权威、代码已变」的漂移，比没有注释更危险——AI 会严格照错误的规则执行。这正是维度 2「注释-代码一致性」要专项查的。

### 6.4 面向 AI 的注释判断标准（本项目专用）

对每条注释问一句 CLAUDE.md 的判据：**「这句话是在帮 AI 少犯一条错，还是在浪费它的注意力？」**

| 判断 | 处置 |
|---|---|
| 帮 AI 少犯错（反重构警告/契约/跨文件不变量/非显然坑） | **留** |
| 浪费 AI 注意力（复述行为/复述命名/演变叙事/出处证据/纯装饰） | **删** |
| 注释说「单位是秒」但代码是毫秒 | **这是 bug，改注释或改代码** |

**关键原则**：注释是「给 AI 的约束指令」。约束指令与代码脱节 = 一个会主动误导下一个 AI 的 bug。注释的**精度**和**一致性**，比注释的**数量**重要得多。

---

## 7. 前置任务：注释精简（激进档）

> 用户拍板「激进精简」，目标把注释占比从 17.6% 降到约 12%。这是执行 Phase A 前的**前置任务**——注释密度降下来后，「注释-代码一致性」审查才有干净的基线。

### 7.1 现状量化（实测）

| 类别 | 数量 | 处置 |
|---|---|---|
| 整行 doc 注释 | 307 行（4.3%） | 压缩为一行核心点 |
| 行内注释 | 954 行（13.3%） | 保留反重构警告，删复述 |
| 反重构警告/契约（不得/必须/顺序/刻意/必现） | 229 行 | **保留**（核心资产） |
| `MARK:` 分组标记 | 65 处 | ✅ 已删（纯装饰分隔线） |
| 演变叙事（此前/先前/改成） | 4 处 | 待删 |
| 复述命名/行为 | ~11 处 | 待删 |
| 空注释行 | 1 处 | 待删 |

### 7.2 删除原则（严格对照 CLAUDE.md「必删」清单）

**必删**（浪费 AI 注意力）：
1. 演变叙事 —— 例 `TranscodeSection.swift:133`「先前这里又除了一次 100，进度条最大只有 0.96pt」→ 删，AI 会自己 `git log`
2. 复述代码行为 —— 「把 X 设成 Y」「让 Z 生效」这类 AI 自己读代码就懂的
3. 复述命名 —— 注释和标识符说的是同一件事
4. 纯装饰分隔线 —— `MARK:`、`---`、emoji 分隔

**必留**（帮 AI 少犯错）：
1. 反重构警告 —— 「顺序不可换」「刻意不用某 API」「必须门控」「必现」
2. 契约 —— 参数单位/返回语义（含三态与哨兵值）/前置条件
3. 跨文件不变量 —— 单文件推不出来的规则
4. 非显然的坑 —— 只陈述规则，不写发现过程

### 7.3 执行步骤

1. ✅ 删除 65 处 `MARK:` 标记（已完成，占 65 行）
2. ⏳ 删除 4 处演变叙事 + 11 处复述 + 1 空行（约 16 行）
3. ⏳ 压缩多行 doc comment 为一行核心点（307 行整行注释中，约 2/3 是多行的，可压掉约 80-100 行）
4. ⏳ 行内注释逐条过：删「复述行为」、保留「反重构警告」（954 行中预计删 80-120 行）
5. ⏳ 复验：`swift build --disable-sandbox` + `swift test --disable-sandbox` 全绿（注释删除不得影响编译/测试）

### 7.4 关键权衡（需用户知晓）

- **注释占比降到 12% 是「正确精简」的结果，不是目的**。删的是「浪费 AI 注意力」的废注释，绝不为了数字好看去砍「帮 AI 少犯错」的 229 处反重构警告。
- **`MARK:` 标记删除的副作用**：Xcode 跳转栏会失去分组。纯面向 AI 场景下无影响，但若日后仍需用 Xcode 导航，可考虑保留少量关键分组的 `MARK`。另有两处带实质约束的 MARK（`FpsDownscaleCommand`「档位常量不做配置化」、`FrameRateTable`「变更口都落盘——只在状态跃迁时调用」）随 MARK 一起删了，其约束信息需下沉到文件头注释补回。
- **压缩 doc comment 的风险**：多行注释里的「非显然坑」可能在压缩时被误删。压缩时逐条判断，凡含「不得/必须/顺序/刻意/必现/否则」的，压缩后仍保留这些关键词。

### 7.5 验收

- 注释占比 ≤ 13%（目标 12%）
- 229 处反重构警告一字不减
- `swift test --disable-sandbox` 全绿
- 删除后无编译警告（注释删除不引入新 warning）

---

## 8. 执行顺序（修订）

> **主线执行顺序已迁移到 `audit-plan-impl.md`**。三者关系一句话：

1. **前置：注释分析（第 6 节）+ 注释精简（第 7 节）**
2. **Phase A**：状态机正确性 + AVFoundation 陷阱 + 进程生命周期（三个命门）
3. **Phase B**：线程安全 + 注释-代码一致性 + 稳定性
4. **Phase C**：并发交错 + 播放切换稳定性 + 隐私
5. **Phase D**：常驻隐性成本 + UI/UX + 注释合理性

每个 Phase 的原子任务、发现/修复分离、TDD 验证步骤，见 `audit-plan-impl.md`。
