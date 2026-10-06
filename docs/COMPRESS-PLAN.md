# 代码压缩执行路线图（代码是负资产）

> 原则：代码是负资产，默认删。注释也是负资产，默认删。验收脚手架是重复的、更脆弱的负资产。

## 已完成

1. ✅ 修正病根：CLAUDE.md 两条规则
   - 「注释篇幅不设上限」→「注释是负资产，默认不写，超 2 行先怀疑在讲故事」
   - 「emit 打点是验收锚点一个字不能改」→「emit 正在废弃，由 XCTest 替代，可删」
2. ✅ 零风险压缩（已提交，净减 32 行，327 测试全绿）
   - 删死常量 baselineCRF/baselinePreset + 死测试
   - MediaLibrary.isInsideConverted 收敛三处重复
   - LockWatcher/DisplayWatcher/FullscreenDetector 观察者循环化

## 待执行（按负资产大小排序）

### 第一步：删验收脚手架（约 -500 行产品 + -4000 行脚本）

**目标**：整套「emit 字符串打点 + shell grep」验收体系，用 XCTest 替代。

1. 删三个探针文件（-416 行）：
   - `Sources/PicCore/Playback/LoopProbe.swift`（185）
   - `Sources/PicCore/Playback/WindowProbe.swift`（148）
   - `Sources/PicCore/Playback/FrameDriver.swift`（83）
2. 删 AppDelegate 里的验收脚手架（-120 行）：
   - `startFrameDriver` / `startLoopProbeIfRequested` / `startObservability` / `tick`
   - `startHoldObserver` / `armHoldObservation` / `observeHold` / `lastHoldSnapshot` / `holdObserverTicks`
   - `scheduleQuitAfterIfRequested` / `openSettingsIfRequested`（--quit-after / --open-settings 测试开关）
   - `lockSignalNames` 里的 PIC_LOCK_SIGNAL_PREFIX 分支
   - `applicationWillTerminate` 里的 emit 打点
3. 删 80 处 `emit("PIC_xxx")` 打点（产品代码里的字符串锚点）
4. 删 `scripts/`（2875 行）+ `test.sh`（689 行）+ `UITests`（445 行）
   - 保留 `build.sh`（打包必需）

**风险**：删 emit 后，test.sh 会全红 —— 所以要一起删，不能只删一半。

### 第二步：砍注释（约 -700 行）

注释/代码比 30-58%（PlayerController 74 行代码配 43 行注释）。只留「反重构警告」229 行，删「复述行为 + 讲坑故事」的 ~900 行。

标准：一条注释超 2 行 → 删到只剩「AI 会犯的那条错」。

### 第三步：删冗余包装（约 -20 行）

- `RotationController.setMode`（mode 已 public var，17 处调用点改 `mode = x`）
- `TranscodeQueue.isActive`（5 行 switch → 两个 `==`）
- 两个队列的磁盘预检重复 → 抽 helper

### 第四步：过度防御降级（约 -150 行）

- `DesktopWindowInset` 内缩补偿 → 覆盖率容差
- Chrome 双窗口聚合 → 粗判
- 签名锁 PlayerControllerSurface → 删

## 目标

产品代码 7172 → 约 5000 行，脚本 4000 → 0，测试保留核心回归锁。

## 执行方式

每个文件独立 commit，每步 `swift test --disable-sandbox` 全绿再推进。
第一步「删验收脚手架」是最大的耦合改动，建议单独一个会话/子代理专注做。
