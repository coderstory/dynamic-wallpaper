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

## 1. 审查维度（12 个，按风险权重排序）

| # | 维度 | 核心问题 | 关键文件 |
|---|---|---|---|
| 1 | **线程安全** | `assumeIsolated` 25 处、`nonisolated(unsafe)` 4 处、`@unchecked Sendable` 3 处——每一处都是「AI 猜错隔离域就崩」的雷 | 所有 Watcher、ProcessTranscodeRunner、LineSplitter |
| 2 | **注释-代码一致性** | 191 处反重构警告是否仍准确；注释里「顺序/门控/刻意不用某 API」的断言与代码是否脱节 | 全仓，重点 PlayerController、HoldArbiter、AppDelegate |
| 3 | **并发交错时序** | 跨 `await` 的状态、锁屏+菜单、转码+换目录、启动+拔盘 | AppDelegate、FpsTranscodeQueue、TranscodeQueue |
| 4 | **资源占用** | 44 处 FileManager 调用、AVPlayerItem/AVPlayerLayer 生命周期、Timer 泄漏、观察者注销配对 | PlayerController、WallpaperWindowController、各 Watcher |
| 5 | **启动/切换/播放速度** | 首屏路径上的同步阻塞、`waitUntilExit`、启动时的全量探测 | AppDelegate.bootstrap、ProcessTranscodeRunner、MediaLibrary |
| 6 | **播放切换稳定性** | AVPlayerLooper 克隆、先插后扫、队列清空闪屏、seek 锚点 | PlayerController、PlaybackRouter、HoldArbiter |
| 7 | **UI 布局** | 固定 780pt 宽度、磁贴网格、长文件名截断、空态 | SettingsComponents、SettingsView、两个 Section |
| 8 | **UX 交互** | 菜单「暂停」语义、降帧/转码的可控性、无障碍、反馈即时性 | MenuContentView、SettingsView、FpsTranscodeSection |
| 9 | **代码安全** | 路径穿越、符号链接、注入面、隐私（日志不泄漏文件名） | MediaLibrary、TranscodeCommand、LaunchAgentWriter |
| 10 | **代码稳定性** | 崩溃面：数组越界、可选值、磁盘满、权限拒绝 | 全仓 `[index]`、`first!`、IO 错误路径 |
| 11 | **性能** | 已修 O(n²)/写放大；剩余：扫描串行、逐文件 IO、主线程阻塞 | MediaLibrary、ConvertedLibrary、FrameRateTable |
| 12 | **注释合理性** | 面向 AI 的注释是否「帮 AI 少犯错」还是「浪费注意力」；过度注释 vs 缺注释 | 全仓对照 CLAUDE.md 注释纪律 |

---

## 2. 每个维度的具体审查点（这是计划的核心）

### 维度 1：线程安全（最高优先级）

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

按「风险密度 → 影响面 → 可验证性」排优先级，分阶段执行：

**Phase A（先行，最高价值）**：
- 维度 1 线程安全：25 处 `assumeIsolated` 逐个核对投递来源
- 维度 2 注释-代码一致性：191 处反重构警告抽样 + 前六轮改动后的注释漂移
- 维度 10 稳定性：下标越界 + 磁盘满失败路径

**Phase B**：
- 维度 3 并发交错：4 个交错场景逐一走查（可写临时并发测试）
- 维度 6 播放切换稳定性：looper 克隆边界 + 锚点错位
- 维度 9 安全：路径穿越纵深 + 日志隐私纪律

**Phase C**：
- 维度 4 资源占用：Timer/观察者配对
- 维度 5/11 速度与性能：启动阻塞、扫描串行
- 维度 7/8 UI/UX：布局溢出、菜单语义、无障碍

**Phase D（收尾）**：
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
