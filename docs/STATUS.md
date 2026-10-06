# Pic 现状与未修问题

> **唯一一份活文档。** 2026-10-06 归并：原先 12 份过程报告（`audit-*` / `findings-*` / `*-plan`）
> 描述的多是已修或已否决的状态，留着只会误导，已整体删除。结论都在本文。
> 改动过程看 `git log`，逐轮细节看 `.workbuddy/memory/`（那是流水账，不是文档）。

## 现状快照

- 产品代码 **6127 行**（`PicCore` 纯逻辑 + `PicApp` 装配与 UI），零第三方依赖，仅 macOS 27
- 测试 **5625 行 / 321 用例**（2 skipped），`swift test` 全绿
- 验收只有 XCTest 一条路：原 `scripts/` + `test.sh` + `UITests/` 那套「emit 打点 + shell grep」
  已整体删除（详见「明确不动」第 5 条）
- 构建：`swift build` 编译交付；`./build.sh` 出 .app + DMG（不签名）

## 未修问题（已逐条对当前代码复核，仍成立）

| # | 问题 | 位置 / 判据 | 为什么还没修 |
|---|---|---|---|
| 1 | **「转码」页没有取消/暂停**（「降帧」页有） | `TranscodeQueue` 无 `cancel`/`pause`/`resume`，对比 `FpsTranscodeQueue` 三件套齐全 | 缺产品决策：中途取消后 tmp 产物怎么处置（留 / 删 / 标失败）没定 |
| 2 | **主屏变更后壁纸窗口不重建** | 无 `didChangeScreenParametersNotification` 订阅；`WallpaperWindowController.reassert()` 已就绪但**无人调用** | 一行接线就能修，缺的是「何时算需要重建」的判断（换屏 / 改分辨率 / 合盖接显示器） |
| 3 | **拔盘或目录消失后再插回，不自动恢复** | `MediaLibrary` 无 FSEvents / 目录监听；恢复的唯一途径是用户手点「重新扫描」 | 需确认产品预期：自动恢复 vs 保持手动 |
| 4 | 自绘滑杆（速度 / 音量）**缺 VoiceOver** | `SettingsComponents` 里只有开关有 `accessibilityValue`，滑杆没有 | 无障碍支持，优先级低 |
| 5 | **首屏「壁纸出现」延迟** = 视频数 × 单文件探测 | `MediaLibrary.scan` 循环内 `await probe.metadata(entry)` 串行 | 并发探测会瞬时拉高 IO/CPU，对 24h 常驻 app 未必划算；替代方案是「先播第一个、其余后台补扫」 |
| 6 | `RotationController` 依赖 scheduler 在**主线程**投递，但协议没写明这个契约 | `RotationController.swift:205` 的 `MainActor.assumeIsolated` | 生产实现满足；属架构脆弱点 —— 换个非主线程的 scheduler 实现会崩 |
| 7 | `LineSplitter` **在锁内调 `emit`** | `ProcessTranscodeRunner.swift:110`（`unlock` 是 `defer`，所以仍在锁内） | 当前 `emit` 是 `Task { @MainActor }` 异步派发、非阻塞，无死锁；若将来改成同步实现会卡锁 |
| 8 | 转码过程中换目录 → **跨卷 `moveItem` 失败** | `TranscodeQueue.runJob`（tmp 在旧目录求值、产物在新目录求值） | 安全失败（源保留、标 `output_conflict`），边缘场景 |
| 9 | **2 条「真数据」用例在本机恒 skip** | `RealLibraryPlaybackPoolTests` 要求真实帧率表里有 `state == .done` 且派生片还活着的条目；本机表里 0 行 `done` → 两条都跳过 | 等于这两条覆盖是空转。要改动得用临时目录自造表才能自足运行。⚠️ 其中 `testDeletingDerivativeFallsBackToSource` 会**移动用户的真实派生片**再移回（靠 `defer` 还原）—— 真让它跑起来前先想清楚 |

**已随之消失的旧问题**（留个交代，别再从旧报告里翻出来）：删源日志里「刻意打印文件名供审计」
那 3 处随打点体系一起删了 —— 现在日志里一个文件名都没有，可审计性有轻微下降，这是删打点的既定代价。

## 明确不动（复核过，别再「顺手优化」）

1. **全屏几何的内缩补偿 + 按 pid 聚合**。换「覆盖率容差」是**更差**方案：补偿后真全屏的
   coverage 正好 = 1.0，阈值才能钉死在精确 1.0；改容差（≈0.96）等于放宽阈值，正好复活
   「铺满 visibleFrame 但够不到刘海」那类假阳性。Chrome 同 pid 两扇窗必须合并求和，逐窗口必漏判。
   ⚠️ 内缩 14/9 是 **1470×956 的实测值**，换屏要重新量；量偏的表现是「真全屏没被识别」（漏暂停），
   不是误判。
2. **两个转码队列不抽公共流水线**。差异 6-7 处（终态语义、是否写帧率表、取消处置），硬抽要引
   6-7 个钩子，是 DRY 陷阱。别被「两段长得像」骗。
3. **`PlayerControllerSurface` 签名锁保留**。删它只换来 `attach(to:)` + `playerLayer` 那 9 行死代码，
   却先拆掉 12 行公开面防护网，净值是负的。该文件自己写着「改产品代码去迁就协议，不要改协议」。
4. **类型化观察口保留**（`scanCount` / `loadCount` / `isReconfigurationRegistered` /
   `isSourceRegistered` / `RotationController.advances`）。它们锁的是「缓存命中 / 未重载 / 注册幂等 /
   切换原因」这类真行为，删了要拿 mock 替代 —— 代码更多，判据更弱。
   `advances` 尤其是 `reason` 的**唯一**出口，而 reason 是「单循环不重载同一片」那条修复的判据。
5. **验收不得再引入字符串打点**（`emit` / 输出行 grep）。那套体系需要产品代码常驻打点，
   比等价断言更脆弱，且会渗进交付二进制。

## 本地目录（不在 git 里，别当成项目的一部分）

| 目录 | 是什么 | 删了会怎样 |
|---|---|---|
| `ffmpeg-kit-next/` | `arthenica/ffmpeg-kit-next` 的**源码 clone**，转码选型时读过它（`PROJECT.md` 里「它不硬编码编码质量参数」那条结论出自它的 `apple/src/`）。**零依赖**：交付二进制不链任何 ffmpeg 库，转码是 spawn 系统 `ffmpeg` | 编译/测试/打包/运行都不受影响；要复核那条结论得重新 clone |
| `.planning/` | 内部规划归档（research / phases / 证据），README 明说不对外 | 历史调研与验收证据丢失 |
| `build/` `dist/` | 构建产物 | `./build.sh` 重建 |
| `fixtures/` | 3 个短视频夹具 | 相关用例自动 skip（`PlayerControllerFreeze/Swap` 各一条） |

## 相关文档

- `CLAUDE.md` —— 写代码时遵守的规则（注释纪律、红线、架构约束）
- `docs/agents/*.md` —— 协作流程（issue tracker / triage 标签 / 领域文档约定）
- `.workbuddy/memory/` —— 逐轮工作流水账（含每轮「为什么这么改」），不是给人读的文档
