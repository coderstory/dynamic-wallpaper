# Pic — macOS 视频动态壁纸

## What This Is

一个 macOS 27 原生菜单栏 app：指定一个文件夹，把里面的视频当桌面壁纸循环播放。自用工具，做成签名 .app，能拷到别的 Mac 上跑。

## Core Value

桌面一直是活的视频，而且**不偷电、不抢性能**——全屏 / 锁屏 / 用电池时自动让路，其余时间安静地待在菜单栏。

## Business Context

<!-- 自用工具，不变现。保留此节以记录分发方式约束。 -->

- **Customer**: 用户自己（单机自用）
- **Revenue model**: 无（免费自用）
- **Success metric**: 连续运行一周不需重启、电池模式不被拖垮、别人看不出壁纸在播视频
- **Strategy notes**: 无

## Requirements

### Validated

（暂无 — 先发再验）

### Active

- [ ] 选择文件夹作为壁纸来源，**递归子目录**
- [ ] 菜单栏常驻；关窗口只隐藏窗口，**进程不退出**
- [ ] 播放 mp4 / mov / m4v（原生硬解），**裁剪填满主屏**
- [ ] 播放模式：单循环 / 列表循环 / 列表随机
- [ ] 轮换时间可选；**到点就切**（不等播完）
- [ ] **所有设置改动立即生效**，不用重启、不等下次换片
- [ ] 播放速度可调，**保持原音高**
- [ ] 可选出声 + 音量调节
- [ ] 以下情况**暂停播放**：全屏应用 / 锁屏 / 显示器熄屏 / 系统睡眠 / 电池供电（开关，默认关）
- [ ] 暂停条件解除后**自动续播**（不从头开始）
- [ ] 目录里没有效视频，或文件夹被删 / 移动 → 隐藏壁纸窗口，**露出系统原壁纸**
- [ ] 开机自启（**需手动设一次**）
- [ ] 菜单项：暂停/继续、立即下一个、重新扫描文件夹、打开设置窗口、退出（**不显示当前文件名**）
- [ ] 设置窗口 UI —— 信息架构与控件形态**待调研后规划**，不预先拍板
- [ ] 转码功能，目的是**格式兼容**（把 mkv/avi/webm 等原生播不了的转成能硬解的格式），**画质视觉无损**
- [ ] 转码产物放在**用户选择的壁纸目录内**（具体子目录 / 命名规则待定；必须保证产物不会被再次扫描成"待转码输入"，原视频保留不删）
- [ ] 转码走**调用系统已安装的 `ffmpeg`** 路线：检测 `ffmpeg` 是否在 PATH，未安装则转码入口置灰并提示安装方式（Homebrew `brew install ffmpeg` 等）。App **不内置、不联网下载**

### Out of Scope

- **视频文件列表 / 缩略图浏览** — 用户明确不要
- **多显示器铺满 + 每屏独立配置** — v1 只做主屏，控制复杂度
- **avi / mkv / webm 直接播放** — 非原生格式走转码路线
- **App Store 上架** — 只需能拷走的签名 .app，可用非公开 API
- **多 Space / 台前调度差异化行为** — v1 跟随系统默认
- **自动监听文件夹增删** — v1 手动「重新扫描文件夹」

## Context

- **最大技术风险（未验证）**：macOS 没有公开 API 把视频放到桌面图标**后面**。业界两种做法——desktop-level `NSWindow` 贴在图标层下方，或做成 ScreenSaver bundle 借系统壁纸窗口播放。**这个可行性必须先调研 + demo 验证**，是 Phase 1 的核心任务。
- **全屏检测（未验证）**：判断"任意应用进入全屏"没有直接公开 API。候选方案：`NSWorkspace` 通知、`CGWindowListCopyWindowInfo` 轮询、私有 API。需调研定案。
- **转码方案（已定）**：调用**系统已安装的 `ffmpeg` 可执行文件**（PATH 检测 + `Process` 调用），App **不内置二进制、不联网下载**。未安装时功能降级——转码入口置灰 + 提示安装途径（Homebrew `brew install ffmpeg` 等）。
- **转码目的（已定）**：**只为格式兼容**，不为省资源。目标产物是 AVFoundation 能硬件解码的容器+编码。
- **画质标准（已定）**：**视觉无损** —— 人眼基本看不出差异。数学无损（`-qp 0`）会让文件大 2–5 倍、编码极慢，不采用。具体 CRF / preset / 编码器（libx264 vs libx265 vs svt-av1 vs VideoToolbox hw）待调研拍板。
- **转码产物位置（已定）**：落在用户选择的壁纸目录内，原视频保留不删。**命名 / 目录规则必须避免"产物被再次扫成待转码输入"的无限循环**——扫描器需排除产物，具体规则待设计。
- **转码质量参数（源码已验证）**：读 `ffmpeg-kit-next` 源码确认，它**不硬编码任何编码质量参数**，`apple/src/` 全部是 API 包装、质量参数由调用方传入——所以「视觉无损」的 CRF/preset 完全是本项目自己的决策。同时确认 macOS 包带 `macos-videotoolbox`（硬件编码，`LIBRARY_APPLE_VIDEOTOOLBOX=55`），但**硬件编码的画质控制达不到视觉无损**。→ **转码侧软编保质量（libx264/libx265 + CRF 调优），播放侧硬解（AVFoundation）**，两边不冲突。
- **耗电**：视频壁纸吃 GPU。用户要开关而非硬编码，电池供电时默认不播。
- **设置窗口**：用户要求先调研再规划 UI，不要先写代码再改。
- **工具链（已装好并实测通过）**：Xcode 27.0（Build 27A266a）已安装并通过 `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` 切换生效，`xcodebuild` / `actool` / macOS 27 SDK 全部可用。此前"只有 CommandLineTools、`@State` 和 `@Observable` 编不过"的限制**已解除**——两者现在都能编译，`Form` + `.formStyle(.grouped)` + `Slider` + `@State` + `@Observable` 组合已 `-typecheck` 通过。开发无工具链约束。
- **纯 Rust 路线的结论（已评估）**：技术上可行（`objc2` + `core-graphics` crate），但**避不开 AppKit** —— 桌面层级壁纸本质上就是 `NSWindow` 挂在 `kCGDesktopWindowLevel`，换语言不换 API。额外代价是 AVFoundation 异步 API 在 `objc2` 下远不如 Swift 顺手。已定为 **Swift 路线**。
- **`ffmpeg-kit` 已归档、官方接棒为 `ffmpeg-kit-next`（均已验证，GitHub API 实测）**：原仓库 `arthenica/ffmpeg-kit` `archived: true`，最后推送 `2026-07-02`。接棒仓库 `arthenica/ffmpeg-kit-next` `archived: false`，最后推送 `2026-10-01`，描述为 "Official continuation of FFmpegKit"，许可证同为 `LGPL-3.0`，明确支持 macOS。**本项目不用它**（走系统 `ffmpeg` 调用路线），仅作记录：若将来要改进程内转码以摆脱 PATH 依赖，这是官方可用途径。
- **API 存在性已编译验证**（macOS 27 SDK）：`AVPlayerItem` 无 `rate`/`defaultRate`（速度在 `AVPlayer`）；保音高要设 item，`.lowQualityZeroLatency` 在 macOS unavailable，`.varispeed` 会变调；`SMAppService.register()` 是 throwing；`SMAppService.Status` 无 `.disabled`（是 `notRegistered`/`enabled`/`requiresApproval`/`notFound`）；`NSWindow` 无 `isIgnoringMouseEvents`（在 `NSView`）；`FormInspector` 不存在；`CGWindowLevelForKey(.desktopWindow)` 可用，需 `NSWindow.Level(rawValue:)` 转换。

## Constraints

- **Platform**: macOS 27 原生，Swift + SwiftUI + AVFoundation — 用户明确要原生 app
- **Distribution**: 签名 .app，能拷到别的 Mac 跑；**不上 App Store**（可用非公开 API）
- **Display**: 只主屏 — v1 范围裁剪
- **Formats**: mp4 / mov / m4v 走硬件解码 — 保画质、省电
- **Audio**: 变速必须保持原音高 — AVPlayer 默认会变调
- **Reactivity**: 设置改动必须**立即生效** — 改速度/音量/模式当场变，不允许"下次换片才生效"或"要重启"
- **Process**: 调研期不写生产代码，本项目文档产出必须区分「已验证 / 仅推断 / 待验证」

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| 开机自启需手动设一次 | 避免首次运行弹权限 / 打扰 | — Pending |
| 只做主屏 | 多屏每屏独立配置复杂度远超需要 | — Pending |
| 菜单不显示当前文件名 | 用户在选项中未选 | — Pending |
| 只播原生格式，非原生走转码 | 硬解省电 | — Pending |
| 转码调用系统已装 `ffmpeg`，不内置不下载 | App 轻量、避开 GPL 内嵌、不执行网络下载的二进制 | — Pending |
| ffmpeg 缺失时功能降级而非阻断 | 无 ffmpeg 时其余壁纸功能照常可用 | — Pending |
| 转码只为格式兼容，不为省资源 | 用户明确；省资源靠原生硬解 + 播放期优化 | — Pending |
| 画质标准 = 视觉无损，非数学无损 | 视觉无损体积可接受；数学无损大 2-5 倍且极慢 | — Pending |
| 转码产物留在壁纸目录内，原视频不删 | 用户明确 | — Pending |
| 变速保持原音高 | 用户明确要求 | — Pending |
| 全屏 / 锁屏 / 熄屏 / 睡眠 一律暂停 | 省电优先 | — Pending |
| 文件夹失效 → 隐藏窗口露出系统壁纸 | 比留黑屏干净 | — Pending |
| 设置改动立即生效 | 用户明确要求，不接受重启或延迟生效 | — Pending |
| 签名 .app 自用分发，非 App Store | 可用非公开 API，省掉沙盒约束 | — Pending |
| 先跑领域调研再定架构 | 桌面窗口层级方案可行性未知 | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---

*Last updated: 2026-10-02 after initialization*