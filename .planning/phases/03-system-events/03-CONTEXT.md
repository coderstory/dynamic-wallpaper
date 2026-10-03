# Phase 3: 系统事件仲裁 - Context

**Gathered:** 2026-10-03
**Status:** Ready for planning
**Mode:** mvp

<domain>
## Phase Boundary

壁纸在用户不需要的时候自动让路，且**每次暂停都能说出为什么**。

四个 Watcher 各自独立可测，多条件叠加时按 **veto 集合**正确仲裁，解除后**从原处续播**。

**本 Phase 零 UI 工作** —— 设置窗是 Phase 5。本 Phase 只需把「当前为什么暂停」这个信息**暴露出来**（供 Phase 5 渲染）。

**UI 设计门跳过**：planner 的 UI gate 报 `block: true`，但 `matchedToken: ui` 命中的是 ROADMAP.md 里「UI **文案**排序」这个中文词，不是前端代码。Phase 3 不产出任何界面。

</domain>

<decisions>
## Implementation Decisions

### 继承自 Phase 1/2 的硬约束（已实测，不得重新推导）

- **D-01:**  🔴 四类系统检测必须走事件通知，禁止逐帧轮询。
Phase 2 实测 `.app` 下显示刷新回调**仍是降级路径**（`DRIVER=timer_fallback_hz30`，27 Hz），且 `REFRESH_SESSION=locked` 表明**无法区分「`.app` 也拿不到」与「锁屏会话压制」**。
→ 锁屏 / 熄屏 / 睡眠 / 全屏四类检测一律走 `DistributedNotificationCenter` / `NSWorkspace` 事件。逐帧轮询方案直接排除。

- **D-02:**  🔴 全屏检测禁用 0.95 覆盖率阈值。
Phase 1 实测 `FALSE_POSITIVE_OBSERVED=1`：Ghostty(pid 1227) 与 CC Switch(pid 1228) 各把 `visibleFrame`(1470×833) 铺满 → `coverage=1.000` ≥ 0.95 被判成全屏，但两者 bounds 高 833 < 屏幕 frame 高 956，**结构上够不到刘海，可证不是全屏**。
coverage 已顶在 **1.000 上限**，任何阈值调整都改不了。

**用户 2026-10-03 已拍板：走 ① —— 设计几何之外的判别信号。**

具体信号候选（planner 可选，但必须**公开 API**，且必须给出本机实测结论）：
- 窗口 `styleMask` 含 `.fullScreen`（公开 API，AppKit 原生判定；注意 Phase 1 实测 `NSWindow` 上没有 `isFullScreen` 属性，用 `styleMask.contains(.fullScreen)`）
- `NSWorkspace.activeSpaceDidChangeNotification` 关联（Space 序号跳变）
- 其他 `NSWorkspace` 通知

**要求**：几何信号可以保留作辅助，但**不得单独作为判定依据**；几何外信号必须能独立触发暂停。
若三条候选在本机都测不出可用结论，如实记 `BLOCKED` + 每条的实测原因，**不要退回纯几何阈值**。

- **D-03:** 🔴 桌面层窗口有 14pt/9pt 系统性内缩（叠加刘海 33pt，共 47pt）。任何覆盖率/全屏几何计算必须先处理。

- **D-04:** 🔴 坐标系：`CGWindowListCopyWindowInfo` 左上角原点；`NSScreen.frame` 左下角原点。先翻转再比。

- **D-05:** ⚠️ `PIC_HOLD` 是 0.5 秒轮询不是事件驱动（`WINDOWS.md` 登记），短于 0.5 秒的暂停会漏采 → 本 Phase 接线时改事件驱动。

- **D-06:** ⚠️ `AppDelegate.startWallpaper()` 有直连 `player.play()` 在菜单边界外，需本 Phase 复核（`W-2026-10-03-10`）。

- **D-07:**  ⚠️ 停止用「源码字面量 grep」做判据。
Phase 1 出现 5 次、Phase 2 出现 3 次「自己的判据被自己违反」（注释里写了字面量，`grep -c` 误报）。
→ 判据只扫不含注释的代码（统一过滤器），或改用**行为断言**（单测 / 探针输出）不碰源码文本。

- **D-08:** 按 PID 认领窗口，不按 layer。本机 `DevDesk` 在跑，`FOREIGN_SAME_LEVEL=0`、`FOREIGN_DESKTOP_FAMILY=7` → 桌面族里确实还有 7 扇别人的窗口。

### 已冻结可直接用的接口（Phase 2 定死，**不要改签名**）

```
HoldReason      : Hashable, Comparable, CaseIterable —— 本 Phase 加 5 个 case
HoldArbiter     : Set<HoldReason> veto 集合 · set(_:active:) 单一入口
                  resumeAnchor 只在 ∅→非∅ 写入（D-15 已实现且有单测）
                  isManuallyPaused 是只读派生量，不是独立真相源
PlaybackDecision: holds: Set<HoldReason> · shouldPlay = holds.isEmpty · activeReasons 已排序
PlaybackTarget  : 协议（arbiterCurrentPosition 等）
PlayerController: AVQueuePlayer + AVPlayerLooper；rate/volume 挂 player 不挂 item
SettingsStore   : 含 Battery 相关开关位（Seed 已定义 sourceFolder/rate/volume/isMuted/playMode/rotationInterval）
```

### 架构（ROADMAP 已定，照抄）

- **D-09:**  4 个 Watcher（`FullscreenDetector` / `LockWatcher` / `PowerWatcher` / `DisplayWatcher`）**只产出 `HoldReason`，不直接碰播放器**。
单向流：`Watcher → HoldArbiter → PlayerController`。**任何 Watcher 都不许 import AVFoundation 或持有 player。**

- **D-10:**  ** 🚫 **不要用优先级链做决策。
本域反模式：锁屏 + 全屏同时成立时，优先级链会在「退出全屏」时误恢复播放。veto 集合语义：只有 `holds` 清空才续播。
优先级**只允许**用于 UI 文案排序（`HoldReason.order` 已存在）。

- **D-11:**  「电池供电时暂停」**开关默认关闭**。

- **D-12:**  必须对外暴露「**当前为什么暂停**」—— 这是 Phase 5 的 `UI-04` 落点，本 Phase 只需产出数据，不做渲染。

### 用户已确认（2026-10-03）

- **全屏检测走「几何之外加判别信号」**（见 D-02）
- **构建系统维持 D-01 原案：SwiftPM → Phase 5 引入 Xcode 工程。** UI 测试（TEST-07~10）必须有 `.xcodeproj`，但单测（TEST-01~06）用 `swift test` 即可，不必提前背 `project.pbxproj` 的成本。
- **交付的 `.app` 必须剥离测量脚手架。** Phase 2 实测：产品代码 1279 行里有 **493 行（38.5%）是测量脚手架**，其中 `LoopProbe` **206 行会进交付的 `.app`**。用户 2026-10-03 拍板：**`.app` 只含产品代码**，探针留在源码里不进 bundle。
  → 这条要在 `build.sh` 落地，并加判据：**打进 `.app` 的二进制里不得出现探针符号**。实现阶段（Phase 4 或 7）必须做。

### Claude's Discretion
- 4 个 Watcher 的具体实现方式（`DistributedNotificationCenter` 订阅哪些 name / `NSWorkspace` 通知的组合）
- 「熄屏」与「睡眠」的判定信号选择
- 电池状态读取方式（`IOKit.ps` / `IOPSNotificationCreateRunLoopSource`）

</decisions>

<specifics>
## Specific Ideas

**核心测试资产是 TEST-01：6 个输入（全屏 / 锁屏 / 熄屏 / 睡眠 / 电池 / 用户手动）× 开闭 = 64 种组合逐一断言。**

Phase 2 的幂集测试已写成**运行时从 `HoldReason.allCases` 生成**（当时 n=1 → 2 个子集）。本 Phase 加 5 个 case 后**自动扩到 32 个**（n=5 → 2⁵）。
`HoldReason` 若含 6 个 case（`manualPause` + 5）则为 **2⁶ = 64**。**请核对最终 case 数使幂集恰好是 64** —— TEST-01 要求 64 种组合。

**锁屏跃迁未验证**：`CGSSessionScreenIsLocked` 只验证了**能读出状态**（40 秒 9 次采样全为 1），**未验证跃迁时是否翻转**。本 Phase 必须实测跃迁才能写进产品代码 —— **但当前屏幕锁着、无跃迁可观察**，如实记 `unknown` 并列为待人工项，不要伪造。

</specifics>

<canonical_refs>
## Canonical References

- `.planning/phases/02-playback-core/02-VERDICT.md` —— Phase 3 只引用它
- `.planning/phases/02-playback-core/02-PDCA.md` —— A1/A2/A5 硬约束的来源
- `.planning/WINDOWS.md` —— 13 条已知窗口，尤其 W-05/W-08/W-10
- `Sources/PicCore/State/HoldArbiter.swift` · `PlaybackDecision.swift` · `HoldReason.swift` —— **已冻结，不要改签名**
- `.planning/spike/FullscreenProbe.swift` —— Phase 1 的全屏几何探针，含 `--selftest` 三条基准值与 `FALSE_POSITIVE_OBSERVED=1`
- `.planning/spike/LockProbe.swift` —— Phase 1 的锁屏探针
- `.planning/spike/out/fullscreen-scenarios.log` —— 5 场景的原始日志
- `.planning/research/PITFALLS.md`
- `.planning/ROADMAP.md` Phase 3 的 Success Criteria

</canonical_refs>

<existing_artifacts>
## 已有资产

- **产品代码** 14 文件 / 1279 行，`test.sh` 32 项全绿，`swift test` 24 项
- **`fixtures/`** 4.2MB 测试视频
- **`.planning/spike/`** 全套探针：FullscreenProbe（`--selftest` / `--inspect` / `--replay`）、LockProbe、CGSession 键表探针
- **`evidence/`** Phase 2 的实测日志
- **工具链**：Xcode 27.0、Swift 6.4、ffmpeg 9.0.2；`Package.swift` 用 `.swiftLanguageMode(.v5)`；测试框架 XCTest

</existing_artifacts>

<constraints>
## Constraints

- **最少代码**：优先系统/框架现成能力。每引入一层抽象都要能说清现成的为什么不能用
- **零第三方依赖**（Phase 2 已达成，本 Phase 保持）
- **诚实基线**：明确区分「跑过 / 没跑过 / 应该能跑但未测 / 假定依赖」。判据不得用形容词
- **不伪造数字**：任何度量必须来自真跑过的、可复现的命令
- **屏幕当前锁着**：无法实测的（锁屏跃迁、切 Space、熄屏、睡眠、拔电源）如实标 `unknown` / BLOCKED + 原因，**继续推进不阻塞**
- **Watchers 零 AVFoundation**：这是可测性与分层的前提，不是风格偏好

</constraints>
