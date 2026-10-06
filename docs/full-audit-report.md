# 全量代码审查报告（97 个文件，无抽样）

> 范围：57 个产品源文件 + 40 个测试文件，逐行审查。
> 方法：5 个并行审查代理，覆盖「实现合理性 / 重复 / 形式主义 / 环境耦合 / 死代码」五维。
> 结论：**产品代码可减约 210 行，测试代码可减约 250 行，另发现 1 条死测试 + 1 组死常量 + 多处环境耦合脆弱测试。**

---

## 一、产品代码可优化点（精确到文件/行号）

### 收益最大的三处跨文件重复

| 重复点 | 位置 | 减行 |
|---|---|---|
| **`Converted/` 目录排除判定**（三处逐字相同） | MediaLibrary:121 / FpsTranscodeQueue:151 / TranscodeCandidateFilter:42 | -8 |
| **ffmpeg argv 构造**（共享 15 个 token） | TranscodeCommand + FpsDownscaleCommand | -14 |
| **路径排序比较器**（`$0.url.path < $1.url.path` 三处） | MediaLibrary:144 / ConvertedLibrary:49 / TranscodeCandidateFilter:28 | -3 |

### 自绘控件收敛（最大单项收益）

- `GlowSegmented` / `ChoiceGrid` / `TabBar` 三者都是「N 选 1」，可合并成一个参数化 `ChipPicker`（SettingsComponents.swift）→ **-55 行**
- 卡片描边样板 `.background(RoundedRectangle...fill)+.overlay(...stroke)` 重复 6+ 处 → 抽 `cardChrome` 修饰器 → -10 行

### 系统信号模块（Watcher 重复）

- FullscreenDetector：观察者注册重复 + FullscreenSignals 构造重复 → -16
- DisplayWatcher：sleep/wake 观察者重复 → -8
- LockWatcher：locked/unlocked 观察者重复 → -7
- PowerWatcher：单槽用数组承载 → -3
- AutoStartManager：SMAPP_STATUS 打点重复 + domain 字符串重复 → -9

### AppDelegate（装配点）

- `freeSpaceProvider` / `rootProvider` / `availability` 闭包各重复 2 次 → -9
- `invalidateCache + emit + rescan` 模式重复 4 次 → -8
- 两个「批次完成」handler 仅差 token → -6

### 转码队列（两个 runJob 同构）

- 磁盘预检段逐字相同 → 抽 helper -7
- `isActive` 用 5 行 switch 表达两个 `==` → -4
- `looksLikeUsableOutput` 可单表达式 → -3
- 类型泄漏：`(runner as? ProcessTranscodeRunner)?.cancel()` → 协议补 cancel()

### 两个 Section 同构

- `jobRow` / `progressBar` / `ScrollView 分隔线` / `availabilityBar` 四处同构 → -53

### 其他零散

- SettingsStore：`defaults.object() as? T ?? seed` 重复 6 次 + playMode if-let 链 → -7
- RotationController：`setMode` 冗余包装 + switch 分支可合并 → -7
- PlayerController：中间变量 + `isActive` 简化 → -2
- InstallPathwaysView：3 次 pathway 调用数据化 → -10
- WallpaperWindowController：换行+编码重复 → -2

**产品代码合计：约 -210 行**

---

## 二、测试代码可优化点

### 明确的死测试 / 死常量

1. **`TranscodeCommandTests.testBaselineConstantsAreCrfEighteenPresetMedium`（死测试）**：锁的 `baselineCRF`/`baselinePreset` 在 `arguments()` 从未使用，且与 `VideoEncoderProfile.preset="fast"` 自相矛盾。→ 连同产品侧两个死常量一起删。
2. `ExternalToolLocatorTests.testNotExecutableProbePathIsSkippedNotFatal`（名字与实现不符 + 完全重复）
3. `ExternalToolLocatorTests.testGuiMinimalPathStillFindsHomebrewInstall` 与 `testAvailableWhenHomebrewPathExists` 重复
4. `FFmpegAvailabilityTests.testGuiMinimalPathStillFindsHomebrewInstall` 与 `testExplicitProbePathIsReportedAvailable` 重复
5. `FpsDownscaleCommandTests.testAboveThirtyIsDownscaled`（严格子集）
6. `FpsDownscaleCommandTests.testFrameRateNilIsDecidedByCallerNotPredicate`（测 struct 默认值，非被测逻辑）
7. `FpsTranscodeQueueTests.testCancelWithEmptyQueueIsSafe`（零断言 smoke）
8. `SystemEventPipelineTests.testHoldReasonPowerSetIsExactlySixtyFour`（跨文件重复）

### 环境耦合脆弱测试（干净环境 skip 或失败）

| 文件 | 问题 | 严重度 |
|---|---|---|
| **RealLibraryPlaybackPoolTests** | 依赖真实片库 + 真实帧率表 + `moveItem` 用户文件（defer 还原，被 kill 则丢失） | 🔴 最重 |
| **PlayerControllerFreezeTests / SwapTests** | 依赖 gitignored 的 `fixtures/clip-a/b.mp4` | 🟠 重 |
| **PowerWatcherTests** | 3 条真 IOKit + 硬 sleep | 🟠 重 |
| **SettingsPresentationTests.testEmptyStateBodyIsSingleSourced** | 读真实源码文件，目录结构一变就断 | 🟡 中 |
| ProcessCancellation / TranscodeMainActorFreeze | 依赖 sleep/轮询节奏，flaky | 🟡 中 |

### 可抽 helper 的重复样板（最大减行）

- FpsTranscodeQueueTests：9 处重复的 6 行队列构造 → -60~80
- MenuBarModelTests：哨兵断言 + perform 构造重复 → -40~50
- SystemEventPipelineTests：watcher 构造重复 → -30~40
- SettingsApplierTests：前后构造不一致 → -25~35

**测试代码合计：约 -250 行（含可删死测试 + 可抽 helper）**

---

## 三、诚实结论

1. **测试绝大多数是「有设计意图的回归锁」**，不是形式主义——注释里大量规格编号（D-04/TRANS-04/C8-C9 等）+ 反证用例设计，锁的是「防 AI 改坏」的契约。
2. **真正的形式主义只有约 8 条**（上面列出），死测试 1 条，死常量 1 组。
3. **环境耦合脆弱测试是最大的工程质量隐患**：RealLibraryPlaybackPoolTests 在干净环境必 skip，PlayerController 两个测试依赖 gitignored fixture，这些是「假绿」。
4. **可减总量约 460 行**（产品 210 + 测试 250），占全仓 12000 行的 4%。

### 建议的执行顺序（按收益/风险比）

1. **删死测试 + 死常量**（零风险，约 -10 行）
2. **跨文件重复抽取**（Converted 排除 + argv 构造 + 排序，约 -25 行）
3. **自绘控件收敛 ChipPicker**（-55 行，需同步 XCUITest）
4. **测试 helper 抽取**（-150 行，机械重构）
5. **环境耦合测试改造**（用临时目录 + 注入替身替代真实片库/fixture，消除假绿）

---

## 四、关键发现（需你决策）

**`baselineCRF`/`baselinePreset` 是死常量**：`TranscodeCommand.arguments()` 根本不用它们，实际走 `VideoEncoderProfile.qualityTokens()`。这暴露一个「注释说改了要同步测试、但改了零影响」的漂移——正是「注释-代码一致性」维度要抓的问题。

**`RealLibraryPlaybackPoolTests` 有数据丢失风险**：`testDeletingDerivativeFallsBackToSource` 真实 move 用户的派生片文件，靠 `defer` 还原。若测试进程被 kill，`defer` 不执行，用户文件以 `.bak` 形式丢失。这是测试代码里最危险的一条。
