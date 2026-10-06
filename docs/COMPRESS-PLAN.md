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

产品代码 7118 → 约 5000 行（第一步后为 6270），脚本 4009 → 0（**已达成**），测试保留核心回归锁。

## 顺带发现的下一轮候选（第一步删除后新产生的「孤儿」）

以下是**因为打点消失而失去全部产品调用方**的域类型/方法，目前只剩测试在用。
它们不是 grep 脚手架，删它们要动测试断言语义，故本轮未动：

- `HoldArbiter.holdStatus` 与整个 `HoldStatus` 类型（`HoldStatusTests` 锁着它）
- `LibraryAvailability.token(_:)`（`reasonToken` 的冗余别名）与 `LibraryState.reasonToken`
- `FFmpegAvailability.label(available:)`
- `RotationController.advances` 历史数组 —— 产品侧原本只用 `.count`，现在**一个产品调用点都没有了**

## 执行方式

每个文件独立 commit，每步 `swift test --disable-sandbox` 全绿再推进。
第一步「删验收脚手架」是最大的耦合改动，建议单独一个会话/子代理专注做。
