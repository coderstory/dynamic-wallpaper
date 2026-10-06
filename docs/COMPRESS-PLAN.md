# 代码压缩执行路线图（代码是负资产）

> 原则：代码是负资产，默认删。注释也是负资产，默认删。验收脚手架是重复的、更脆弱的负资产。

## 已完成

1. ✅ 修正病根：CLAUDE.md 两条规则
   - 「注释篇幅不设上限」→「注释是负资产，默认不写，超 2 行先怀疑在讲故事」
   - 「emit 打点是验收锚点一个字不能改」→「验收只走 XCTest，不得再引入字符串打点」
2. ✅ 零风险压缩（已提交，净减 32 行，327 测试全绿）
   - 删死常量 baselineCRF/baselinePreset + 死测试
   - MediaLibrary.isInsideConverted 收敛三处重复
   - LockWatcher/DisplayWatcher/FullscreenDetector 观察者循环化
3. ✅ **第一步：删验收脚手架**（净减 5022 行，327 测试全绿，0 新增告警）
   - **产品代码 7118 → 6270（-848）**：删三个探针文件（457 行：LoopProbe/WindowProbe/FrameDriver）、
     AppDelegate 695 → 438（-257，全部探针接线 + 5 个测试开关 + 35 处打点）、
     清掉 80 处 `emit`、删 FullscreenDetector 里只服务探针的 4 个死方法（-73）、
     删 `PIC_MAX_RES` 解码上限实验开关、删 `--open-settings`/`--quit-after` 与 `PIC_LOCK_SIGNAL_PREFIX` 分支
   - **脚本层 4009 → 0**：`scripts/`(2875) + `test.sh`(689) + `UITests/`(445)
   - **工程层 135 → 0**：`Pic.xcodeproj` 摘掉 PicUITests target（-123）、scheme 去掉 TestableReference（-12）
   - **路线图漏掉的耦合点（本次补上）**：
     ① `build.sh` 有第二遍「保留探针」构建产出 `PicProbe.app` + `probe_symbols` 符号计数，
        删探针必须同步改，否则交付线直接断；
     ② `AutoStartTests` 有 4 个用例直接断言 emit 出来的字符串，实测替身已记录了
        `registerCount/unregisterCount/openSettingsCount` 与 launchctl 调用序列 → 断言改行为、不重写逻辑；
     ③ `AutoStartManager` 的打点靠**注入闭包**，删打点要连构造参数一起摘；
     ④ `FullscreenDetector.emit` 是**没人注入过的死参数**（AppDelegate 用的是默认空实现），打点从未触发过；
     ⑤ 删 `--open-settings` 会连带收敛 `MenuBarLabel` 的 PicOpenSettings 通知桥（那桥只为它存在）
   - **验证**：`swift test --disable-sandbox` 327 测试 / 2 skipped / 0 失败（与基线逐项一致）；
     `git worktree` 另建 HEAD 基线全新构建比对，唯一告警 12 → 9，**新增 0**，
     消失的 3 条是随 `LoopProbe.swift` 一起删掉的过时 AVFoundation API 告警

## 待执行（按负资产大小排序）

### 第二步：砍注释（**暂缓**，待重新评估）

原估「只留反重构警告 229 行，删 ~900 行」。但第七轮的结论与此冲突：统计纠正后，
现存注释几乎全是**整行 doc comment**，且绝大多数是「反重构警告 / 契约」——为降占比砍它们
违背 CLAUDE.md 的初衷。**未做全量清理**；只顺手修了 3 处已失真的措辞（emit 时代的
「打点」「grep」「探针」等表述）。要推进得先给出「哪一类注释该删」的可判别标准。

### 第三步：删冗余包装（部分完成）

- ✅ `RotationController.setMode`：已删，17 处调用点直写 `mode =`
- ✅ `TranscodeQueue.isActive`：已简化成两个 `==`
- ⛔ 两个队列的磁盘预检重复 → 抽 helper：**已判定不做**（DRY 陷阱，见下节「明确不动」）

### 第四步：过度防御降级（**复核后否决**，三项全不动）

逐项读源码 + 读锁它的测试后，结论是这条路线图的前提写错了 —— 这三项都是**承重设计**：

- **`DesktopWindowInset` 内缩补偿（14/9）→ 覆盖率容差**：换容差是**更差**的方案。
  真全屏窗口在 `CGWindowList` 里被系统性内缩（1470×956 实测 14/9），补偿后 coverage 正好 = 1.0，
  所以阈值能钉死在精确 1.0；改成容差（≈0.96）就等于把阈值放宽到「97% 也算全屏」，
  正好复活注释里警告的那类假阳性（铺满 visibleFrame 但够不到刘海的应用）。
  **风险提示**：14/9 是该分辨率实测值，换屏要重新量；量偏的表现是「真全屏没被识别」（漏暂停），
  不是误判。已写进源码注释。
- **Chrome 双窗口聚合 → 粗判**：Chrome 的 `0,33,1470,124` + `0,121,1470,835` 是**同 pid 两扇窗**，
  逐窗口口径必漏判；按 pid 分组求和才是对的。`split` 基准上 `global=1.000` 而
  `perWindowBest=0.600`，两者相等即聚合退化 —— 单测逐字锁着。
- **签名锁 `PlayerControllerSurface` → 删**：它是 12 行测试侧契约锁，价值是抓公开面意外漂移。
  删它只能换来 `attach(to:)` + `playerLayer` 那 9 行死代码 —— **先拆防护网再删代码，净值是负的**。
  且该文件自己写着「改产品代码去迁就协议，不要改协议」。

## 结论：本仓库的「删代码」阶段到此为止

产品代码 7118 → **6127**，脚本 4009 → 0，测试 5703 → 5625（321 用例，2 skipped），
全程 `swift test` 绿、零新增编译告警。

距路线图原来写的「约 5000 行」还差 ~1100 行，但那 1100 行**不是负资产**：它们是
反重构警告（注释）、类型化观察口、以及上面刚被否决的承重防御。再往下删就要开始删「判据」本身，
那不是瘦身，是降低可靠性。

**还能继续的两个方向，都需要先定标准，不是机械删**：

1. **注释**：现存注释几乎全是整行 doc comment，且绝大多数是「反重构警告 / 契约」。
   要动就得先写出可判别的删除标准（候选：演变叙事 / 证据出处 / 告警符号 / 验证体系自解说），
   按标准逐条过，而不是按比例砍。
2. **真重构**（非删）：两个转码队列的状态机确有同形段落，但差异 6-7 处，硬抽是 DRY 陷阱。
   若要做，得先设计出不会引入 6-7 个钩子的抽象，属独立课题。


## 目标

产品代码 7118 → 约 5000 行（第一步后 6270，第二轮审计后 **6163**），
脚本 4009 → 0（**已达成**），测试保留核心回归锁（322 用例，2 skipped）。

## 第二轮审计：公开面清零（已完成）

**方法**：用脚本枚举 `Sources/` 的全部 `public` 成员（239 个），逐个统计其在产品代码里的引用数
（减去声明自身），产品侧为 0 的列为候选，**再逐条人工复核**。复核是必需的——扫描有两类盲区：

- **假阳性**：`public override var canBecomeKey/canBecomeMain` 这种，AppKit 自己回调，源码里当然没人调；
- **假阴性**：名字太常见（`token` / `label` / `labels` / `parseChunk`）会被同名局部变量、循环变量、
  别的类型的同名成员盖过去，扫不出来。

**已删（产品侧零调用，测试改动干净，净减约 174 行）**：

| 删除对象 | 行数 | 为什么是负资产 |
|---|---|---|
| `HoldStatus` 整类型 + `HoldArbiter.holdStatus` | 46 | `PlaybackDecision` 的纯转发壳，且带**第二套**「6 case → 中文」映射（`HoldReason.uiLabel`），与活的 `SettingsPresentation.holdReasonLabel` 文案不同 |
| `ConvertedLibrary.playbackItems` | 11 | 与 `PlaybackPool.build` 重复的第二套合并实现，只有测试在喂 |
| `LaunchAgentWriter.existingExecutablePath` | 13 | 产品零调用；测试改读落盘 plist（断言真实产物，比调产品读回口更强） |
| `FrameRateTable.needsConvertCount` / `okAt30Count` | 7 | 产品侧队列自己按 `entries` 现算 |
| `PowerWatcher.currentPowerSourceKeys` | 6 | 注释自述「供探针逐字打印」 |
| `TranscodeOutputNaming.root` / `FpsTranscodeQueue.root` | 6 | 两个无人读的便捷访问器（`rootProvider` 才是真相源） |
| `SettingsPresentation.playbackPausedTitle` / `playbackRunningTitle` | 3 | 只被「两个常量互不相等」的同义反复测试喂着 |

**等价简化**（行为不变）：`RotationController.setMode` 冗余包装（17 处调用点直写 `mode =`，
与 `SettingsApplier` 统一为一条写路径）；`LibraryState.shouldShowWallpaper` 与
`TranscodeQueue.isActive` 的 4 分支 switch → 单表达式。

**死注入面**：`MenuItem.perform(…, store:)` 的参数从未被函数体读过。连同 `MenuContentView` 的
`@Environment(SettingsStore.self)` 与 `PicApp` 给菜单注入的 `.environment(store)` 一起去掉 ——
菜单从此在**结构上**不可能依赖设置值。

**契约迁移**（删壳不能丢判据）：`HoldStatusTests` → `HoldArbiterContractTests`。
「六个文案两两不同」改测活的 `SettingsPresentation.holdReasonLabel`；
「原因按 order 排序 + 叠加全列」改测 `PlaybackDecision.activeReasons` 与 `joinedReasons`。
测试数 327 → 322（-5 个只测已删成员的用例），其余判据一条没少。

### 明确不动（复核后判定为真需求，别再来删）

- `WallpaperWindow.canBecomeKey/canBecomeMain`：AppKit 回调（扫描假阳性）
- `WallpaperWindowController.reassert()`：**I1 缺陷（主屏变更后壁纸窗口不重建）的预留修复件**
- `PlayerController.attach(to:)` + `playerLayer`：被 `PlayerControllerFreezeTests` 的签名锁协议
  逐字锁着，而该文件写着「改产品代码去迁就协议，不要改协议」——要删得先改协议，属独立决策
- `MediaLibrary.scanCount` / `PlaybackRouter.loadCount` / `DisplayWatcher.isReconfigurationRegistered` /
  `PowerWatcher.isSourceRegistered`：**类型化观察口**，锁的是「缓存命中 / 未重载 / 注册幂等」
  这类真行为。删了要拿 mock 替代，代码更多
- 两个队列抽公共预检：**已于上一轮判定为 DRY 陷阱**（差异点 6-7 处，硬抽要引 6-7 个钩子），
  别被「两段长得像」骗了

### 扫描盲区里的残留候选（仍待定夺）

`LibraryAvailability.token(_:)`、`LibraryState.reasonToken`、`FFmpegAvailability.label(available:)`、
`MenuBarModel.labels(isPaused:)`、`ProgressParser.parseChunk(_:)`、
`RotationController.advances`（产品侧原本只用 `.count`，现在一个产品调用点都没有）。
这些名字太常见，脚本扫不出来，需人工逐个确认；删它们要动测试断言语义。


## 执行方式

每个文件独立 commit，每步 `swift test --disable-sandbox` 全绿再推进。
第一步「删验收脚手架」是最大的耦合改动，建议单独一个会话/子代理专注做。
