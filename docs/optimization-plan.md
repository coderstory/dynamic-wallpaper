# 全文件逐行审查 · 优化方案

> 审查范围：全部 56 个产品源文件（Sources/），逐行文本审查。
> 结论：**可优化约 800-1200 行，分三类**。每类给出精确位置 + 方案 + 风险。

---

## 一、验收脚手架（可砍，约 500-700 行）

这些代码**只为 test.sh / 端到端验收喂数据，不产生任何用户功能**。

### 1. `emit("PIC_...")` 打点（80 处，约 160 行）

分布：AppDelegate 35、LoopProbe 14、AutoStartManager 10、SettingsApplier 7、FrameDriver 6、其余零星。

**方案**：这些打点是「探针/验收脚本读的日志」，release 版理论上不需要。但注意：它们现在**没有**被 `#if !PIC_NO_PROBE` 包住，所以**交付二进制里也在打日志**（写 stderr）。

- **最优**：把 `emit` 统一收口到一个 `#if !PIC_NO_PROBE` 内联函数，release 版整体置空，零运行时开销。
- 但「打点」本身是验收体系的一部分，删掉会破坏 `test.sh` 的 grep 断言。

**判断**：不删，但「release 版零开销化」（包进条件编译）。净减交付二进制的运行开销，不减源码行数。

### 2. 探针三件套（LoopProbe 194 + WindowProbe 166 + FrameDriver 95 = 455 行）

**方案**：已全部包在 `#if !PIC_NO_PROBE` 里，`build.sh` 传 `-DPIC_NO_PROBE` 剥掉。**源码行数不减，但交付二进制不含它们**。

**判断**：这三件套是「验收体系」的核心（测循环是否真的无缝、窗口层级对不对、显示刷新拿到没）。**删了 = 失去验收能力**，但如果你接受「只靠单测、不做端到端验收」，可以整个删掉，净减 455 行。

### 3. AppDelegate 的测试开关（`--quit-after`/`--open-settings`/`PIC_LOCK_SIGNAL_PREFIX` 等，约 80 行）

**方案**：这些是探针脚本的入口。删了 = 探针脚本没法驱动 app。

---

## 二、可精简的抽象/冗余（可砍，约 300-400 行）

### 4. SettingsComponents 自绘控件（512 行）

`GlowToggle`/`GlowSlider`/`ChoiceGrid`/`ChoiceGrid3x2`/`GlowSegmented`/`GlowButton`/`TabBar`/`Tile`/`CompactCard`/`CompactRow`/`StatusBar`/`SectionHead`/`IconBox`/`AboutIcon` = **14 个自绘控件**。

**方案**：
- `GlowSegmented` 和 `ChoiceGrid` 和 `TabBar` 三者都是「N 个可选项 + 选中态」——可收敛成一个通用 `Picker` 组件（策略模式，参数化项数/样式）。
- `GlowToggle` 可用 SwiftUI 原生 `Toggle` + `tint` 替代（但会失去「禁用态不降透明度」的定制，需评估）。
- `IconBox`/`SectionHead`/`StatusBar`/`Tile`/`CompactCard`/`CompactRow` 是布局原语，保留。

**风险**：自绘控件的 `accessibilityIdentifier` 被 XCUITest 依赖，改动要同步更新 UITest。**收益约 100-150 行。**

### 5. AppDelegate 装配点职责过重（695 行）

AppDelegate 承担了「装配 + 首启引导 + 菜单动作 + 转码/降帧队列管理 + 观测器 + 打点」六类职责。

**方案**：
- 把「转码/降帧队列的持有 + onBatchFinished 钩子」抽成独立 `TranscodeCoordinator`（约 80 行可抽走）
- 把「观测器/打点/探针启动」抽成 `ObservabilityHost`（约 60 行）
- 净减 AppDelegate 本体，但总量可能持平（抽走 ≠ 减少）

**风险**：AppDelegate 是「唯一装配点」，注释明言这是架构约束。拆分要谨慎，收益/风险比不高。**建议只做「观测器下沉」，队列管理保留。**

### 6. 两个转码 ViewModel 的转发方法（TranscodeViewModel 98 + FpsTranscodeViewModel 92）

`refresh()`/`reload()`/`sizeText` 等是「薄转发」。上一轮已去重 sizeText/isAvailable。

**方案**：进一步把 `@Published` 状态同步收敛成「用 @Observable 的 queue 直接观察」，省掉 VM 层的 `reload()` 转发。但 SwiftUI 需要 ObservableObject 才能驱动，收益有限。

---

## 三、苹果 API 客观约束（不可砍，约 1500 行）

这些是「在 macOS 做这件事」绕不开的：

### 7. 4 个 Watcher 的「注册→注销配对→C 回调转 Swift→线程 hop」（约 400 行）

每个 Watcher（Lock/Fullscreen/Display/Power）都要：
- `addObserver` + `removeObserver` 配对（否则泄漏）
- C 回调（`@convention(c)`）不能捕获上下文 → 全局单槽表 + NSLock
- C 回调线程不承诺 → `DispatchQueue.main.async` hop

**判断**：这是苹果 API 的客观要求，删了 = 泄漏/崩溃。

### 8. 转码子进程管理（ProcessTranscodeRunner 114 行）

stderr 管道、waitUntilExit 不冻 UI、取消、残行 drain —— 都是「长跑子进程」的客观坑。

### 9. 全屏检测几何算法（FullscreenGeometry 157 + FullscreenDetector 263）

苹果没有「是否全屏」的 API，只能几何硬算 + 处理刘海/双窗口/坐标系。

---

## 结论与建议

| 类别 | 行数 | 建议 |
|---|---|---|
| 探针三件套 | 455 | **可整个删**（接受失去端到端验收），否则保留 |
| 验收打点 | ~160 | 保留但 release 零开销化 |
| 自绘控件收敛 | ~150 | 做（策略模式，XCUITest 同步更新） |
| 装配点拆分 | ~80 | 谨慎做 |
| 苹果 API 约束 | ~1500 | 不可动 |

**最务实的两步**：
1. **探针 + 打点「release 零开销化」**（不改源码行数，但交付二进制更干净）—— 已部分完成（P2-5 剥了 2s 定时器）
2. **自绘控件收敛**（Picker 通用化，减 ~150 行）

**我的最终判断**：这个项目「能安全砍的」是探针 455 行 + 控件 150 行 ≈ 600 行，占 8%。其余是「功能 + 苹果 API 约束 + 面向 AI 护栏」的合理成本。
