# 转码 / 降帧功能审计报告

审计对象：`Sources/PicCore/Transcode/*`、`Sources/PicCore/Media/FrameRateTable.swift`、`Sources/PicApp/Transcode/*`、`AppDelegate` 装配段
审计日期：2026-10-06
方法：静态代码走查 + 本机真实数据取证（`~/Library/Application Support/Pic/frame-rate-table.json`、`/Users/coderstory/Documents/Videos{,/Converted}`、ffmpeg 9.0.2 实测）

---

## 0. 结论摘要

主流程（串行 drain → 预检 → tmp→rename → 回写）确实成立，**问题全部集中在「状态一致性」「路径生命周期」「用户操作兜底」三处**。最严重的一条已在本机真实复现：

> 本机 `Converted/` 里有 **199 个**已生成的 `-30fps.mp4` 产物，而帧率表里 **0 行**是 `done`、`derivativeMtime` 全为 null。
> 后果是：播放池从 496 条膨胀到 **695 条（+40%）**，同一段素材以「原片 + 已降帧产物」两种形态各播一次，降帧的省电收益归零。

| # | 严重度 | 问题 | 影响 |
|---|--------|------|------|
| 1 | **P0** | `done` 状态与磁盘产物脱节，无对账 | 播放池 +40%，同一素材重复入池，降帧收益归零 |
| 2 | **P0** | 切换视频目录后两个队列仍指向旧目录 | 产物写错位置；叠加 #3 造成**不可逆丢文件** |
| 3 | **P0** | 转码删源用 `removeItem`，不走废纸篓 | 用户原片无法恢复 |
| 4 | **P1** | `scan()` 整表快照覆盖写 → lost update | #1 的最可能直接触发机制 |
| 5 | **P1** | `FrameRateTable.prune()` 从未被调用 | 换目录/重装后计数虚高、表无限膨胀 |
| 6 | **P1** | 递归扫源 + 扁平产物名 → 同 stem 互相覆盖 | 子目录同名文件丢产物 |
| 7 | **P1** | `scale=-2:1440` 无条件放大 | 1080p 源被放大到 2560×1440（已实测） |
| 8 | **P1** | 取消/暂停语义错乱 | 取消显示"失败"；暂停被静默解除且无法续跑 |
| 9 | **P2** | 转码进度条把 0…1 当百分比再除 100 | 进度条几乎不动 |
| 10 | **P2** | `Converted` 排除规则三处大小写不一致 | 小写 `converted/` 目录逃过降帧扫描 |
| 11 | **P2** | 两队列无互斥 | 同时对同一源文件开工 |
| 12 | **P2** | 转码队列无取消/暂停 | 批次不可中断 |
| 13 | **P3** | `ConvertedLibrary.playbackItems` 死代码 | 与 `PlaybackPool.build` 双实现，必然漂移 |

---

## 1. P0-1：`done` 与磁盘产物脱节 —— 降帧成果全部失效

### 证据（本机真实数据）

```
Converted/ 内产物                     : 199 个
帧率表 state 分布                      : okAt30=295, needsConvert=201  ← 无一个 done
derivativeMtime 非空的行                : 0       ← updateState(.done) 一次都没落盘成功
needsConvert 且产物已存在于磁盘的行        : 199   ← 全部是「已转完但仍标记为待转」
产物 mtime 早于源 mtime 的行             : 0       ← 排除「源被改动导致缓存失效」
```

最终以复刻 `PlaybackPool.build` 跑真实数据：

```
root 扫描条目           : 496
Converted 产物条目       : 199
被一对一替换的根条目       : 0      ← liveDerivative 要求 state.recovered == .done，永远拿不到
最终播放池大小           : 695 (+40%)
同一素材池中重复           : 199
```

### 根因

状态机把「完成」当成**权威真相**存进表里，而磁盘产物才是**真正的事实**：

- `PlaybackPool.swift:29-36` `liveDerivative` 要求 `entry.state.recovered == .done` 才肯替换 → 替换闸门永远关闭；
- 紧接着 `PlaybackPool.swift:19-23` 的通用追加循环接管：因为源还在、不算孤儿，`isOrphanDerivative` 返回 false → 产物被**再追加一次**；
- `FrameRateTable.reusableEntry` 校验的是**源**的 size/mtime，**从不看产物在不在**；一旦回落到全量重探（`resolveFrameRate` 非缓存分支），新 entry 的 state 只由 fps 算出 → 无条件回到 `needsConvert`，`done` 被抹掉且再也回不来。

结果是两头落空：一对一替换彻底失效（那份 merge 逻辑白写），同时还多追加了一份重复播放。

### 修复方向

把「是否有可用产物」做成派生值而非持久化状态位：

1. `reusableEntry` 命中 `.done` 行时，若 `hasLiveDerivative()` 为 false → 返回 nil 或直接降为 `needsConvert`；
2. `PlaybackPool.liveDerivative` 的替换判据改为「表里 `.done` **或** 磁盘上存在同名产物且源未被后续改动」，不再单靠状态位；
3. 更彻底的一步：产物命名是可推导的（见 P1-6），直接按 `<stem>-30fps.mp4` 反查磁盘存在性即可判定，完全不依赖表。

---

## 2. P0-2：切换视频目录后队列仍指向旧目录

`TranscodeQueue` 的输出根目录和 `FpsTranscodeQueue` 的 root，都在 **`lazy var` 首次求值时固化**：

```swift
// AppDelegate.swift:43-57
TranscodeOutputNaming(root: store.resolvedFolderURL() ?? ...)   // 只算一次
// AppDelegate.swift:74-89
FpsTranscodeQueue(runner: ..., root: store.resolvedFolderURL() ?? ...)  // 只算一次
```

换目录的唯一入口 `requestFolderNow()`（`:497-501`）只做 `pickFolder()` → `rescanAndApply()`，**不重建任何队列**。

有意思的是 `TranscodeViewModel` 反而拿了动态闭包 `wallpaperRootProvider`（`:65-70`），于是形成了最坏的组合不对称：

| | 输入侧（扫谁） | 输出侧（写哪） |
|---|---|---|
| 转码 | **动态**新目录 `TranscodeViewModel.loadCandidates()` | **固化**旧目录 `TranscodeQueue.naming.root` |
| 降帧 | 固化旧目录 `FpsTranscodeQueue.root` | 固化旧目录（同一个 field） |

**后果**：用户换了目录后再点"开始转码" → 候选来自新目录，产物写进旧目录的 `Converted/`（用户永远看不到），然后触发删源（见下一条）——**源文件没了，产物在找不到的地方**。

**修复**：给两个队列各自加 `updateRoot(_:)`，在 `pickFolder()` 落 `$accepted` 时同步调用；或让 queue 持有 `() -> URL?` 闭包（与 ViewModel 一致）。

---

## 3. P0-3：转码删源是硬删除，不走废纸篓

```swift
// TranscodeQueue.swift:183-185
if jobs[index].state == .succeeded, jobs[index].deletesSource {
    try? FileManager.default.removeItem(at: source)     // ← 不可恢复
}
```

- 壁纸目录自动扫描的候选即 `deletesSource: true`（`TranscodeViewModel.loadCandidates()`）；
- 全仓其余删文件的路径都走 `trashItem`（`AppDelegate.confirmTrashWallpaper` 还专门做了二次确认）；**只有这一处是 `removeItem`**；
- 与 P0-2 叠加 = 丢数据；甚至在 `#6` 的同 stem 覆盖场景下，第一个文件的删除也是永久性的；
- 删除结果还被 `try?` 吞掉，失败与成功在 UI 上完全一样。

**修复**：改 `trashItem(at:)`；至少把 `try?` 换成能区分失败的形式并反映到 job 尾部提示。

---

## 4. P1-4：`scan()` 的整表覆盖写导致 lost update

`FpsTranscodeQueue.scan()` 的写法是经典 read-modify-write 全量结构：

```swift
// FpsTranscodeQueue.swift:106        var table = FrameRateTable.load(from: tableURL)  // 进内存快照
// FpsTranscodeQueue.swift:164        try? table.upsert(entry, to: tableURL)           // 循环内每个新探测整表落盘
// FpsTranscodeQueue.swift:139        try? table.save(to: tableURL)                    // 收尾再用陈旧快照整表覆盖
```

而 `runJob` 的回写是同一粒度整表操作：

```swift
// FpsTranscodeQueue.swift:266-269  writeTableState → load → mutate → save
```

两者虽同为 `@MainActor`，但 `scan()` 循环体内有 `await specProvider(source)` 悬挂点，另一条 `@MainActor` 任务可以在此插入。**任何一个 scan 快照先 load、后 save 的窗口里发生了 `writeTableState(.done)`，那些 `done` 都会被整表覆盖回 `needsConvert`。** 这与本机观测到的「产物全在、`done` 全无、`derivativeMtime` 全 null」完全吻合。

**修复**：`updateState` 落盘前重新 `load` 一次做行级 merge（或给表加版本号/乐观锁）；最简单的是让所有写入路径共用一个内存中的单一表实例，磁盘只在边界落一次。

---

## 5. P1-5：`prune()` 从未被调用

`FrameRateTable.prune(keepingLiveSources:)`（`FrameRateTable.swift:131`）的唯一调用点在自己的单元测试（`FrameRateTableTests.swift:177`）。生产代码零调用。

后果：
- 换目录 / 删文件后，孤儿行**永久**留在表里；`tableTotal` 与 UI「N 行」读数虚高；
- 表随时间单调增长，每次 `scan` 都要全量 load/save 整份 JSON；
- 卸载重装后指向新目录时尤其明显 —— 旧目录的行一条都不会消失。

**修复**：在 `FpsTranscodeQueue.scan()` 收尾时用本次扫到的 live path 集调一次 `prune`。

---

## 6. P1-6：递归扫源 + 扁平产物名 → 同名文件互相覆盖

两条链路都是递归收集、扁平输出：

```swift
// TranscodeOutputNaming.outputURL        root/Converted/<stem>.mp4        ← 只用 lastPathComponent
// FpsDownscaleCommand.derivativeName     <stem>-30fps.mp4                 ← 只用 lastPathComponent
```

`TranscodeCandidateFilter.candidates(in:)` 与 `FpsTranscodeQueue.scan()` 都用递归 enumerator。于是：

```
Wallpaper/风景/a.mkv   → Converted/a.mp4
Wallpaper/城市/a.mkv   → Converted/a.mp4   ← 覆盖前者
```

- 第二个会整体覆盖第一个的产物（后者赢），第一个的降帧成果丢失；
- 表里有两行指向同一个 `derivativePath` → `PlaybackPool` 会把两个源文件各替换成同一个产物，播放池出现重复；
- 当前系统是平铺目录所以侥幸没发作，属**潜伏型**。

**修复**：产物路径保留相对子目录层级（`<relPath>/<stem>-30fps.mp4`），或冲突时加消歧 suffix。

---

## 7. P1-7：`scale=-2:1440` 是无条件拉伸，不是"高度上限"

```swift
// FpsDownscaleCommand.swift:34
"-vf", "fps=\(Int(maxFrameRate)),scale=-2:\(maxHeight)"
```

注释写的是「**高度上限**」、UI 文案写的是「缩到 2560×1440」，但 ffmpeg 语义是**强制高度=1440**。实测：

```
输入: 1920x1080 @60fps
输出: 2560x1440 [SAR 1:1 DAR 16:9], 30 fps
```

即 1080p 源被**放大**并重编码：体积变大、画质因二次编码变差、耗时更长，与"降帧省解码"的初衷南辕北辙。

本机抽样 81 个文件：`>1440p` 77 个、`=1440p` 1 个、`<1440p` **2 个**（当前片库以 4K 为主，故当下影响面小，但换一批素材就是全量问题）。

**修复**：`scale=-2:'min(1440,ih)'`（注意单引号，避免 ffmpeg 把 `(` 当表达式出问题），或小分辨率源直接跳过 scale。

---

## 8. P1-8：取消与暂停的语义错乱

三处独立缺陷：

**a) 用户主动取消 → 显示"失败"**
`cancel()`（`FpsTranscodeQueue.swift:84-87`）只置标志 + `terminate()` 进程。`runJob` 拿到非 0 退出码 → `.failed(reason: "exit_nonzero")`，并 `writeTableState(.failed)`。UI（`FpsTranscodeSection.swift:159`）显示「失败 · exit_nonzero」。用户视角：点取消 = 报错。

**b) `consumeCancel()` 顺带把暂停标志抹掉**
```swift
// FpsTranscodeQueue.swift:93-100
let was = _cancelRequested
_cancelRequested = false
_pauseRequested = false      // ← 无论 was 是 true 还是 false，暂停一律被清
```
配合 `run()` 里的 `if shouldStop() { if consumeCancel() {...}; break }`（`:194-197`）：纯暂停场景也会走到这里 → `_pauseRequested` 被静默清除 → `isPaused` 变 false → UI 从"已暂停"跳回 idle。

**c) 暂停后无法续跑**
同处 `break` 跳出 `while`，`defer { isRunning = false; onBatchFinished?() }` 触发 → VM 的 `isRunning=false`。此时点 UI 的「继续」（`FpsTranscodeViewModel.resume()`）只是清了已经清过的标志，**没有任何地方重新调用 `run()`** → 点了没反应，必须重新点「开始降帧」。

顺带：`onBatchFinished` 是**无条件**触发的 —— `didWork` 算了出来却在 `:201` 被 `_ = didWork` 丢弃，于是哪怕一个 job 没跑也发重扫 + `PIC_FPS_RESCAN=1` 打点。

---

## 9. P2-9：转码进度条量纲错误

```swift
// TranscodeSection.swift:130
.frame(width: 96 * percent / 100)
```

`ProgressParser.percent` 返回的是 **0…1**（`ProgressParser.swift:83` 已 clamp 到 `0...1`）。这里再除 100 → 进度条最大宽度 0.96pt，肉眼恒为空。
对照组 `FpsTranscodeSection.swift:137` 用 `progressWidth * percent`，是对的。同一份值两个视图两种解释。

---

## 10. P2-10：`Converted` 排除规则三处不一致

| 位置 | 比对方式 |
|---|---|
| `MediaLibrary.swift:116` | `caseInsensitiveCompare` ✅ |
| `TranscodeCandidateFilter.swift:34` | `caseInsensitiveCompare` ✅ |
| **`FpsTranscodeQueue.swift:122`** | `pathComponents.contains(MediaLibrary.excludedDirectoryName)` — **大小写敏感** ❌ |

后果：用户壁纸目录下若存在小写 `converted/` 子目录 —— 它被根扫描排除（影片本来就看不到了），但**能被降帧队列扫进去并生成产物**。`TranscodeOutputNaming.swift:14` 的注释正好预言了这类漂移：「两个名字漂移的那天就是回流闸门失效的那天」。

---

## 11. 其余 P2/P3

- **两队列无互斥**（`AppDelegate` 各自持有独立 queue/runner）：可同时对同一源文件开工。转码删源后，先前生成的降帧产物变孤儿；反之亦然。
- **转码队列零控制面**：`TranscodeQueue` 没有 pause/cancel，`ProcessTranscodeRunner.cancel()` 只在降帧路径被调用。用户点了「开始转码」就停不下来。
- **`(runner as? ProcessTranscodeRunner)?.cancel()`**（`FpsTranscodeQueue.swift:86`）：用具体类型下转型拿取消能力，换任何 runner 实现就静默失效（FakeRunner 下取消逻辑完全测不到）。
- **`jobs` 数组按下标捕获**：`runJob` 的进度闭包捕获 `index`；`FpsTranscodeQueue.scan()` 会 `jobs = candidates` 整体替换数组 → 运行期重扫会让 index 指到别的 job 或越界。UI 虽有 `isRunning` 门禁，属于设计脆弱而非当前 bug。
- **`TranscodeQueue.run()` 的 `for index in jobs.indices`**（`:107`）：范围在循环起算一次，运行中追加的 job 本轮看不到；同理 `TranscodeViewModel` 可在 `run()` 期间 `enqueue`，新 job 需再次点开始。
- **幂等策略两套**：转码用 `TranscodeOutputNaming.skipDecision`（产物 mtime ≥ 源 mtime）；降帧完全不需要这个是因为只看状态位 —— 而正是这个差异让降帧缺少了「产物还在就别重转」的最后一道兜底。
- **`ConvertedLibrary.playbackItems`（`ConvertedLibrary.swift:47`）是死代码**：生产唯一入口用 `PlaybackPool.build`（`AppDelegate.swift:294`），此函数只在测试里被调用。两份合并孕育漂移。

---

## 12. 场景矩阵

| 场景 | 现状 | 判定 |
|---|---|---|
| 首次安装 → 首次降帧 | 主流程跑通，产物正确 | ✅ |
| 卸载后重装，**同**目录 | 表保留可复用 | ✅ |
| 卸载后重装，**换**目录 | 旧行永不清理，计数虚高 | ❌ P1-5 |
| 卸载后重装，产物已被手工删除 | 若行是 `.done` → `hasLiveDerivative` false → 回落原片 | ✅ 安全 |
| **换目录后不重启 App** | 队列仍指向旧目录，产物写错；删源造成丢文件 | ❌ P0-2 + P0-3 |
| 手工删掉整个 `Converted/` | 行若仍是 `.done` → 回落原片，但**永不重新生成**（不会被再排队） | ⚠️ 静默降级 |
| 源文件的 size/mtime 变了 | 缓存失效 → 重探 → `done` 被抹成 `needsConvert`（产物已在盘上） | ❌ P0-1 触发路径之一 |
| 两个功能同时开工 | 无互斥，两队列可并行 | ⚠️ P2 |
| 降帧中暂停 | 标志被清 + 无法续跑 | ❌ P1-8 |
| 降帧中取消 | 显示为"失败"，且写 `.failed` 到表 | ❌ P1-8 |
| App 崩溃 / 强退 | `converting` / `failed` 经 `recovered` 退回可重试；残留 `.tmp` **无人清理**，会一直躺在 `Converted/` | ⚠️ 缺启动清理 |
| ffmpeg 中途消失 | 每次 `runJob` 预检 → `ffmpeg_unavailable`，源保留 | ✅ |
| 磁盘满 | 预检 `disk_space` 拦截（用 ImportantUsage 容量），源保留 | ✅ |
| 目标目录被拔了（外接盘） | `try? createDirectory` 可能把整条路径重建出来；随后 ffmpeg 失败、源保留 | ⚠️ 有副作用 |

> 题外：tmp 残留是**确定性**的 —— 进程 `terminate()` 走 `line 179` 会清自己那个 `.tmp`，但强退路径（kill / 崩溃）没有对应清理；`FpsTranscodeQueueTests.testCancelLeavesNoTemporaryArtifacts` 只覆盖了主动取消。

---

## 13. 测试覆盖缺口（解释了这些 bug 为什么活到现在）

现有单测质量不低（`FrameRateTableTests` 18 项、`FpsTranscodeQueueTests` 15 项、`PlaybackPoolReplacementTests` 7 项），但都停在**单个 Methods 的正确性**，缺 injections：

- `testSuccessWritesDoneBackToTable` 只测「run 单独跑」，**没有任何测试覆盖 scan 与 run 交错** → P1-4 逃逸；
- 无「产物已在磁盘但表状态落后」的对账测试 → P0-1 逃逸；
- `PlaybackPoolReplacementTests` 全部手工构造 table，**没有一条用「表说 needsConvert、盘上有产物」 这个真实组合** → 40% 膨胀逃逸；
- 无「队列创建后 root 变化」的测试 → P0-2 逃逸；
- `FpsDownscaleCommandTests` 断言的是 argv 字面，没有一条真的跑 ffmpeg 验证分辨率 → P1-7 逃逸；
- UI 量纲（P2-9）没有 test.sh 探针覆盖。

---

## 14. 建议修复顺序

1. **P0-1 + P1-4**：把 `FrameRateTable` 的写入收敛成单一入口 + 行级 reload-merge；`PlaybackPool` 替换判据改为「磁盘产物存在」，脱离 `.done` 单点依赖；补「表落后于盘」的 RED 测试。
2. **P0-2 + P0-3**：queue 改持 `() -> URL?`；删源改 `trashItem`。这两条一起做 —— 单独修任何一个都会留下丢数据或产物错位的窗口。
3. **P1-8**：拆 `consumedCancel` 与 `consumedPause`；暂停用 Task 挂起而非 `break`；引入 `.cancelled` 状态，别复用 `.failed`。
4. **P1-6 / P1-7 / P1-5**：产物路径保留层级；`min(1440,ih)`；scan 收尾调 `prune`。
5. **P2**：统一 `Converted` 比对为 `caseInsensitiveCompare`；修 `96 * percent`；抹掉 `_ = didWork` 与死代码 `playbackItems`；两队列加互斥。

---

## 附：本次审计用到的取证命令

```bash
# 表与实际产物对账
python3 -c "import json,os; t=json.load(open('~/Library/Application Support/Pic/frame-rate-table.json')); ..."

# 分辨率行为实测
ffmpeg -hide_banner -f lavfi -i testsrc2=size=1920x1080:rate=60:duration=1 \
       -vf "fps=30,scale=-2:1440" -f null -    # → 输出 2560x1440
```
