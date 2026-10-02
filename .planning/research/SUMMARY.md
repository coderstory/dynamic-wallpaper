# Project Research Summary

**Project:** Pic — macOS 视频动态壁纸
**Domain:** macOS 原生菜单栏 app / 桌面级视频渲染（Swift + AppKit + AVFoundation）
**Researched:** 2026-10-02 ~ 2026-10-03（四份并行调研的合成）
**Confidence:** HIGH（本机实测量的 SDK / 层级机制 / 播放 API）· MEDIUM-HIGH（领域 pitfall 一手 issue）· MEDIUM（视觉布局与性能旋钮取值）

---

## 0. 先读这一节：证据强度分级（合成的核心约束）

四份调研的**证据来源不一样**，合成时**不能把弱证据写得和强证据一样确定**。下表是本文档贯穿使用的分级口径：

| 来源 | 证据类型 | 强度 |
|---|---|---|
| **STACK.md** | 本机 SDK 头文件 grep + `swiftc -typecheck` 实编译 9 个探针 + C 探针运行输出 + `curl` 走 GitHub REST API | **HIGH**（核心 API 结论）/ MEDIUM（性能旋钮取值、路线 C/D 可行性） |
| **ARCHITECTURE.md** | 本机枚举真实窗口层级 + 反汇编 3 个在售 app + 读 SDK 头文件 | **HIGH**（桌面层级与检测机制）/ MEDIUM（Space 与耗电行为） |
| **PITFALLS.md** | GitHub issue 一手证据（带 issue 号 + 实测数字），**但那是别家项目的环境，不是本机** | **MEDIUM-HIGH**（issue 证据充分；功耗绝对数值 / FFmpeg 许可细节偏低） |
| **FEATURES.md** | App Store 实时抓取（iTunes Search/Lookup API，一手开发者描述） | **HIGH**（Part A 功能全景 + Part B 控件存在性）/ MEDIUM（Part B 视觉与布局） |

> **联网失败声明（必须保留）**：调研期间内置 `WebSearch` / `WebFetch` **全程失败**（ARCHITECTURE 记录 6/6 返回 `API Error: 400`；PITFALLS 记录 cs-web-fetch 抓 Bing 超时）。agent 改用 **本机 SDK 头文件 + `curl` 直连 GitHub REST API + Apple 开发者文档 JSON API** 取证。因此本文档**不含任何未经实测或未经一手 API 返回的「网络检索结论」**；确实查不到的，已在 §6 集中列出。

---

## Executive Summary

**产品形态。** Pic 是一个自用的 macOS 27 菜单栏 app：指定一个文件夹，把里面的视频当桌面壁纸循环播放，做成签名 `.app` 能拷到别的 Mac 上跑。Core Value 是**不偷电、不抢性能**——全屏 / 锁屏 / 熄屏 / 睡眠 / 电池供电时自动让路。

**这个品类的专家做法高度收敛，且已被实测证实。** 桌面层级不是玄学：本机实时枚举窗口证明，在售 app `Hanami Live Wallpaper` 的窗口正停在 `kCGDesktopWindowLevel = -2147483623`，而 Finder 的桌面图标层在 `-2147483603`（高 20 级）、Dock 在 `20`。反汇编三个在售 app 的结果一致：**零私有框架、零辅助功能符号、零屏幕录制权限**，公开 API 足够。播放侧同理收敛——`AVQueuePlayer` + `AVPlayerLooper` + `AVPlayerLayer`，且 `AVSampleBufferDisplayLayer` / `AVSampleBufferVideoRenderer` 在 macOS 27 SDK 里刚被 deprecate，是明确的**不要碰**。这个品类的真正卖点从来不是「能播视频」（人人都会），而是**「什么时候不播」**：所有成熟竞品的宣传语都堆在暂停策略上（Smart Pause / Smart Auto-Pause / occlusion algorithm）。我们把暂停策略当核心做，赛道选对了。

**最大风险是一个门禁（Gate），不是一个难题。** Phase 1 的桌面层级 spike 是**唯一门禁**：如果 `-2147483623` 层的窗口让桌面图标点不动 / 拖不动，或 Finder 刷新后壁纸被盖掉，路线 A 就不成立，整个架构必须重做（退回 ScreenSaver `.saver` bundle 或 `com.apple.wallpaper` 扩展路线）。ARCHITECTURE 已把这句话写死：*"P1 是所有后续阶段的前置门。若 P1 证伪，整个架构需重做，后面全部作废。"* 这个 spike 是**几小时的一次性验证 app**，不是产品代码，但它必须先跑。除门禁外，其余风险都是**已知且可防**的工程细节：暂停仲裁必须用 veto 集合而非优先级链（否则「锁屏中退出全屏」会误恢复播放）、切换视频必须先 `disableLooping()` → `removeAllItems()` 再入队（否则直接抛异常崩溃）、全屏检测必须用 `visibleFrame` 而非 `bounds`（刘海屏 top 内缩 32pt，实测覆盖率只有 96.548%，Chrome 更差只有 87.343%）。

**两个必须在开工前拍板的前置决策**（详见 §4.1）：一是**签名类型**——免费 Apple ID 签名 7 天过期且无法公证，**满足不了 PACK-01「能拷到别的 Mac」**，这个决策便宜但发现得晚就代价高昂；二是**转码的 ffmpeg 路线与 PROJECT.md 已定决策冲突**——STACK 实测本机没装 ffmpeg 并判定该路线违反自足性，PITFALLS 实测 macOS 27 上 `brew install ffmpeg` 因 `lame` / `dav1d` 无 bottle 直接失败。

---

## Key Findings

### Recommended Stack

**零三方依赖的纯系统框架栈。** 整个栈（播放 / 转码 / 菜单栏 / 窗口 / 电源 / 显示）系统框架全齐，引入 SPM 包只增加签名与体积负担。`confidence: MEDIUM`（这是取舍判断，不是实测）。

**核心组件：**
- **Swift 6.4 + AppKit + AVFoundation** — 主语言与框架。壁纸窗口**必须**走 AppKit：SwiftUI 不暴露 `NSWindow.Level` / `collectionBehavior` / `ignoresMouseEvents` / `isOpaque` 的完整控制面，这是硬性的、无替代的。
- **`AVQueuePlayer` + `AVPlayerLooper` + `AVPlayerLayer`** — 播放三层。`AVPlayerLooper`（macOS 10.12+）自动生成 ≥3 个 item 副本预取，无缝、无黑帧。**不采用** `AVPlayer` + KVO 手动 seek 回 0（每次循环一个 seek，必现卡顿/闪黑）。**不采用** `AVSampleBufferDisplayLayer`（queue 管理 API 已 `API_DEPRECATED(macos(10.8, 15.0))`）与 `AVSampleBufferVideoRenderer`（ObjC 侧在 macOS 27 SDK 中已 `API_DEPRECATED(macos(14.0, 27.0))`）。**不采用** AVKit 的 `AVPlayerView`（带 UI chrome，3 个在售 app 全部只用 AVFoundation）。
- **`videoGravity = .resizeAspectFill`** — 裁剪在显示层完成，**零解码开销**。**绝不要**为裁剪建 `AVVideoComposition`（那是逐帧渲染，会掉出硬解路径）。
- **`audioTimePitchAlgorithm = .spectral`** — 变速保音高，**必须显式设**：头文件原文写明「applications linked on or after iOS 15.0 or macOS 12.0 的默认值是 `AVAudioTimePitchAlgorithmTimeDomain`」。`.varispeed` 会变调（用户明确不要）；`.lowQualityZeroLatency` 在 macOS 上 `API_UNAVAILABLE`。
- **`VTIsHardwareDecodeSupported`** — 硬解**探测 + 门控**，不是开关。AVFoundation 不暴露 per-item 的 hw/sw decode 选择器；`VideoToolbox` 的 `kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder` 只作用于自建 `VTDecompressionSession`，`AVPlayer` 用不到。`confidence: MEDIUM`（推理依据充分，**未在真机抓 VideoToolbox 调用栈验证**）。
- **`AVAssetReader` + VideoToolbox 硬编码 HEVC + `kVTCompressionPropertyKey_ConstantQualityFactor`** — 系统转码路径。该 key 是 **macOS 27 SDK 新增**（`API_AVAILABLE(macos(27.0))`），头文件原文称其「designed for consistent visual quality with or without bitrate limit constraints」。已 `[typechecked]`。

**关键版本与 API 事实（全部本机实测）：**
- **Deployment target 定 macOS 15.0，不是 27** —— 实测 `AVAssetExportSession.export(to:as:)` 在 macOS 14.0 target 即可编译；`ConstantQualityFactor` 用 `#available(macOS 27.0, *)` gate。定 27 就只能跑 27 的 Mac，与「拷到别的 Mac 上跑」直接冲突。`confidence: HIGH`
- **`kCGDesktopWindowLevel` / `kCGDesktopIconWindowLevel` 是 C 宏，Swift 导入不了** —— 实测 `error: cannot find 'kCGDesktopWindowLevel' in scope`。⚠️ **这与 ARCHITECTURE.md / REQUIREMENTS.md 的写法冲突，见 §4.1 决策 #1。**
- **窗口层级常量硬编码 + 单元测试锁定** —— `NSWindow.Level(rawValue: -2147483623)`。数值由 C 宏算式固定（`kCGBaseWindowLevel = INT32_MIN` + `kCGNumReservedBaseWindowLevels = 5` + 20），Apple 保留不会变。
- **音量 / 速度必须挂 `AVPlayer`，不能挂 `AVPlayerItem`** —— `AVPlayerLooper` 头文件原文：「AVPlayerItem replicas will be generated at initialization time so any changes made to the specified AVPlayerItem's property afterwards will not be reflected in the replicas」。**这是「设置改动立即生效」需求的第一号实现坑**（UI-SPEC §9 也单独记了这条）。
- **`NSWindow.displaySyncEnabled` 不存在** —— 实测 AppKit 全框架 grep 无此符号；它属于 `CAMetalLayer`。走 `AVPlayerLayer` **没有**这个旋钮。原调研问题里的这一条是错的。
- **`CMVideoCodecType` 没有 `.hevc` 成员** —— 它是 `UInt32` typealias，必须用全局常量 `kCMVideoCodecType_HEVC`。
- **转码侧两个实测坑**：类名是 `AVAssetReaderTrackOutput`，构造签名是 `(track:outputSettings:)` **单数**，不是 `(videoTracks:outputSettings:)`；常量名是 `kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder`（`kVTCompressionPropertyKey_RequireHardwareAcceleratedVideoEncoder` **不存在**）。

**FFmpeg 路线：v1 不引入。** `confidence: MEDIUM`
1. **FFmpegKit 已于 2026-07 官方退役**，GitHub API 返回 `archived: true`。`confidence: HIGH`
2. 继任者 `arthenica/ffmpeg-kit-next`（LGPL-3.0，`archived: false`，`pushed_at: 2026-10-01`）**"distributed as source only"** —— 无预编译包，引入它等于要自己编译整个 FFmpeg。
3. 系统 VideoToolbox + `ConstantQualityFactor` 已能达成「视觉无损」，零体积、零许可风险。
4. 若实测达不到视觉无损，**升级路径是「提高 `ConstantQualityFactor` 或降到 ProRes 422」**（`kCMVideoCodecType_AppleProRes422`，真·视觉无损，代价是文件巨大），**不是引入 FFmpeg**。

**窗口层级路线全景（对 PROJECT.md 假设的修正）** —— PROJECT.md 说业界两种做法，实测开源生态**至少还有两条**：

| 路线 | 机制 | 代表 | 许可 / ★ | 本机可用性 | confidence |
|---|---|---|---|---|---|
| **A. desktop-level `NSWindow`** ✅ **v1 起步** | `kCGDesktopWindowLevel` + `AVPlayerLayer` | `wallnetic`（67★）、`live-wallpaper`（80★）、`hazel`（23★） | MIT / MIT / GPL-3.0 | 100% 公有 API | HIGH |
| **B. ScreenSaver `.saver` bundle** | `ScreenSaver.framework`（公开） | `WallpaperMachine`（152★，291 文件，最成熟）、`wallnetic` 的 `ScreenSaverBridge` | GPL-2.0 / MIT | 公有 API | HIGH |
| **C. `com.apple.wallpaper` 扩展 + 私有 `WallpaperExtensionKit`** | `dlopen` 私有 framework，桥接 `WallpaperRemoteContextXPC` 等 | `phosphene`（868★，MIT） | MIT | ⚠️ framework 本机存在，**macOS 27 已出现真实故障** | HIGH（存在性 + 故障证据） |
| **D. 直接改 Aerial manifest JSON** | 写 `~/Library/Application Support/com.apple.wallpaper/aerials/manifest/entries.json` | `VideoPaper`（31★，MIT，仅 `.mov`） | MIT | ✅ 本机该目录实测存在 | HIGH（存在性）/ **LOW（跨版本稳定性）** |

> ⚠️ **命名冲突警告（给 roadmapper）**：ARCHITECTURE.md 的路线表用的 **C = `CGSSession` 私有框架**、**D = 硬编码 WindowServer level 数字**，与 STACK.md 的 **C = wallpaper 扩展**、**D = Aerial manifest** **完全不是一回事**。两份文档字母相同、含义不同。本文档统一采用 **STACK.md 的 A/B/C/D 定义**。

**路线 C 的 macOS 27 故障实证** `confidence: HIGH`（STACK.md 引 phosphene issue #29）：

> DATA_k7m2qp9x_START
> phosphene #29（2026-08-25，macOS 27.0 build 26A5416b，M4 MacBook Air `Mac16,12`，已 closed）：「The failure begins when the second video causes the `Shuffle All` item to be added. Building `WallpaperSettingsViewModelsXPC` then fails because **a nested menu picker item is missing the `isDownloaded` field expected by the current private framework.** Keeping exactly one video works reliably.」
> DATA_k7m2qp9x_END

→ **含义**：私有 framework 的数据结构**在 macOS 27 上已经变了**。phosphene 自家写了 `verifyRuntimeLayout()` 自检来探测失效，恰恰说明这条路的维护成本是持续的。`confidence: MEDIUM`（基于 issue 文本的推断）

**建议** `confidence: MEDIUM`：v1 起步走 A；**但 Phase 1 spike 必须把 C / D 作为对照项**（A 的层级问题正是 PROJECT.md 自认的最大风险）。若走 C，**必须设计 OS 版本熔断 + `verifyRuntimeLayout()` 式自检**。C/D 的共同优势是 A 做不到的：壁纸真正进「系统设置 → 墙纸」列表、进锁屏、随系统主题切换、由系统负责省电调度。

**代码复用度警示** `confidence: HIGH`：`harryfrzz/hazel` 是 **GPL-3.0 传染，不能抄进本项目**；`jaywcjlove/vidwall` **无 LICENSE 文件 = 默认全权保留，不可复用**；`WallpaperMachine` 是 **GPL-2.0**。架构参考首选 `fatihkan/wallnetic`（MIT，带单测，已实读 `PowerManager.swift`）。

---

### Expected Features

**先纠正三处前提错误（FEATURES.md 实测）** —— 题面给的对标产品有两个不成立，直接影响 roadmap：
- **Wallpaper Engine 没有 macOS 版** —— 官网标题字面即 "Animated Wallpapers on **Windows**"。只能当**功能设计参考**，不能当 macOS 竞品。
- **VIDHub 不是壁纸 app** —— App Store 上是 "VidHub - Video Library & Player"（云盘/视频库播放器）。
- **iWallpaper 有两个** —— macOS 版是 id1552826194；id1155869721 是 iOS 端。

→ 真正的 macOS 对标是 **VideoPaper / Dynamic Wallpaper Studio / 4K Live Wallpaper / Dynamic Wallpaper Library** 这批。

**品类共识：主轴不是「能播视频」，是「什么时候不播」。** 所有成熟竞品的卖点都堆在暂停策略上。

**Must have（table stakes，缺了 = 产品显得残废）：**
- **选择来源（本地视频 / 文件夹引用）** — 所有竞品的起点。VideoPaper 明确支持 "individually, or by **folder reference**"
- **菜单栏常驻 + 关窗口不退出** — 这类 app 的默认形态（VideoPaper "Lives, unobtrusively, in your Menu Bar"）
- **播放模式三选一：Single Loop / Playlist Loop / Shuffle** — Dynamic Wallpaper Studio 原词，**三个选项的名字都不用改**
- **暂停条件（自动 / 智能暂停）** — 4K Live Wallpaper "**Smart Auto-Pause Mode**"、Dynamic Wallpaper Studio "**Smart Pause**"。**这就是我们的 Core Value，不可省**
- **电池供电时暂停** — 品类惯例是**默认关**（我们已定）
- **看不见时不播（遮挡即停）** — iWallpaper 原话："occlusion algorithm ensures it must be **dynamic when it can be seen, and static when it cannot be seen**"
- 播放速度可调、出声开关 + 音量、开机自启、裁剪填满屏幕

**Should have（我们的竞争优势，严格对齐 Core Value）：**
- **改动立即生效** — 竞品普遍要重启 / 重开设置才生效。能直接感知的品质差距。需要在设置绑定层做**观察者**而非「下次生效」
- **完全离线：文件夹即唯一真相** — 所有内容型竞品都要账号 + 云 + 订阅；我们是纯本地文件夹
- **一个总闸管所有暂停条件** — 竞品把暂停散在 "Performance" tab 或 "Smart Pause" 一簇里
- **失败时露出系统原壁纸** — 竞品都没明说这个行为
- **保画质转码管线** — **全竞品无人做，唯一真正没人做的功能，也是复杂度最高的一处**（HIGH 成本）

**Anti-Features（故意不做）** —— 共同点：都会直接违反 Core Value（偷电 / 抢性能 / 变重）：壁纸库与缩略图网格、账号/云/订阅、多显示器每屏独立配置、网页/YouTube/摄像头壁纸（内嵌 `WKWebView`，永久联网，与 Core Value 正面冲突）、视觉效果栈、屏保模式 / 锁屏视频壁纸（与「锁屏时暂停」**直接互斥**）、壁纸编辑器、隐藏桌面图标、全局快捷键、下载/分享/导出、每个视频单独一套参数。

**设置窗口 IA 已定稿**（FEATURES.md B 部分 → 已由 `.planning/UI-SPEC.md` 定稿取代，见 §4.1 决策 #3）：
- 一个 Settings scene、一个 Form、**无侧边栏、无主窗口**；转码走独立 `Window` scene（**明确反对 sheet** —— 转码是长任务，sheet 会锁死设置窗口且进度条没地方放）
- 4 组分区：来源 / 播放 / 声音 / 电源与系统
- 「用户不要视频列表」的**唯一例外**：转码窗口的任务队列。**这条例外必须写进 Phase 计划，否则会被当 scope creep 砍掉**
- 两条置灰联动：单循环时轮换时间置灰；声音关闭时音量置灰

**Feature Dependencies（关键约束）：**
- **设置窗口 requires 全部绑定稳定** —— 「立即生效」意味着设置层是**观察者**，这比窗口外观更影响 Phase 拆分
- **暂停状态机 conflicts with 声音** —— 暂停时音频必须停，但「暂停」与「音量=0」是两回事，恢复时要**还原用户设的音量，不要记成 0**
- **转码 conflicts with 不自动监听** —— 转码产出新文件后不会自动进播放列表，必须显式提示「转码完成，重新扫描」。**这是 v1 的已知摩擦，不是 bug**
- **开机自启 requires 签名** —— 不分发的开发阶段这个 toggle 是死的

**MVP 分期：**
- **v1 Launch With**：文件夹选择（递归）+ 状态计数、三种播放模式、轮换时间（单循环置灰）、播放速度 + 保音高、出声 + 音量（联动置灰）、电池供电开关（默认关）、开机自启、暂停条件总闸 + 自动续播、文件夹失效露系统壁纸、菜单栏常驻 + 5 个菜单项（不含文件名）、设置窗口 4 组 IA
- **v1.x Add After Validation**：转码管线落地（触发条件：核心播放稳定跑一周）、轮换时间支持「按时间段」预设档
- **v2+ Future**：多显示器（**建议不做** —— iWallpaper 的整个价值主张就是这个，做了就得全面超越，收益不匹配自用定位）、裁剪方式可调（fill / fit / 居中）

**macOS 27 SwiftUI 已知坑（FEATURES.md B.6，12 条，标注 [实测] = 本机真编译验证过）：**

| # | 坑 | 说明 |
|---|---|---|
| 1 | **`AVPlayerItem` 没有 `rate` 也没有 `defaultRate`** `[实测]` | 速度在 `AVPlayer` 上 |
| 2 | **保音高要设在 item 上** `[实测]` | `.lowQualityZeroLatency` 在 macOS 上 unavailable —— **别照抄 iOS 代码** |
| 3 | **`SMAppService.register()` / `unregister()` 是 throwing** `[实测]` | 必须 `try` + 错误处理 |
| 4 | **`SMAppService.Status` 没有 `.disabled`** `[实测]` | 实际四 case：`notRegistered` / `enabled` / **`requiresApproval`** / `notFound`。`.requiresApproval` 表示用户还没在系统设置里批准 —— toggle 要能显示「需授权」并给出跳转，**不能当成失败** |
| 5 | **`NSWindow` 没有 `isIgnoringMouseEvents`** `[实测]` | 在 **`NSView.ignoresMouseEvents`** 上。写对了但设错层级，桌面就点不动了 |
| 6 | **`Toggle` 放进 `LabeledContent` 会变成 checkbox** `[文档]` | **永远别这么包** |
| 7 | **`MenuBarExtra` 被用户移除会自动终止 app** `[文档]` | 要设 `LSUIElement = true` |
| 8 | **`Settings` scene 会自动启用「设置…」菜单项** `[文档]` | 别再手动加一份，会重复 |
| 9 | **`SettingsLink` 是从 `MenuBarExtra` 打开设置的正路** `[实测]` | macOS 14+。已开则置前，不会叠窗口 |
| 10 | **Command Line Tools 编不了 `@State`** `[实测]` | 报 `SwiftUIMacros.StateMacro could not be found` —— **本机已解决，见 §4.1 决策 #4** |
| 11 | **macOS 的 `Form` 不是 iOS 的 grouped list** `[文档]` | 别拿 iOS 直觉套 |
| 12 | **不存在 `FormInspector` 这类「新式侧边设置」API** `[实测，MEDIUM]` | 探测四个规范路径全部 404。**别按它做计划** |

---

### Architecture Approach

**分层单向数据流，`State/` 零依赖是全部可测性的保证。**

```
UI 层 (SwiftUI)  MenuBarExtra + Settings
   ↓ 读写
状态层 (纯 Swift，无 UI 无 AVFoundation)  SettingsStore · MediaLibrary · PlaybackPolicy
   ↓ 决策
引擎层 (AVFoundation)  PlayerController · TranscodeService
   ↓ 挂载
系统事件层 (AppKit/CG/IOKit)  4 个 Watcher ──→ HoldArbiter
   ↓
渲染层 (AppKit，唯一必须用 AppKit 的地方)  WallpaperWindowController
```

**Major components：**
1. **`SettingsStore`** — 所有用户设置的单一真相源；`@Observable`；写 UserDefaults。**不做什么**：不含业务逻辑，不碰 AV。
2. **`MediaLibrary`** — 递归扫描文件夹 → `[VideoItem]`；按格式/可解码性过滤；支持手动 rescan。**不做什么**：不自动监听文件系统（v1 Out of Scope）。
3. **`HoldArbiter`** ★ — 汇聚所有 `HoldReason`；决定 `shouldPlay`；维护 resume anchor。**不做什么**：**不碰 AVPlayer**，只输出布尔 + 原因。
4. **`PlayerController`** — 持有 AVPlayer/AVPlayerItem；响应 `shouldPlay`；seek/速率/音量。**不做**播放决策。
5. **`WallpaperWindowController`** — 建/销毁桌面级 `NSWindow`；挂 `AVPlayerLayer`。
6. **4 个 Watcher**（`FullscreenDetector` / `LockWatcher` / `PowerWatcher` / `DisplayWatcher`）— **只产出 `HoldReason`，不直接改播放器状态**。
7. **`TranscodeService`** — 非原生格式 → 转码；v1 可为 stub。

**边界的核心设计**：单向数据流 `Watcher → HoldArbiter → PlayerController`。所有 `*Watcher` **只**产出 `HoldReason`，**不直接**控制播放器。这让暂停逻辑可单测（纯函数，无 AVFoundation）。

**暂停仲裁：不要用「优先级链」，用「veto 集合」。** 朴素做法是维护 `currentReason: HoldReason?`，新条件来了就覆盖 —— **这是错的**：

> 用户在锁屏状态下退出全屏应用 → 若用覆盖式，fullscreen 解除就把 `currentReason` 清空 → **在仍然锁屏的情况下恢复播放**。

正确模型是 **`Set<HoldReason>` veto 集合**，**集合为空才播放**。优先级排序的**唯一用途是 UI 文案**（「因全屏暂停」），**不参与播放决策**。这是 REQUIREMENTS PAUSE-07 已锁定的语义。

**Resume Anchor —— 「从哪里续播」**：锚点在 **`holds` 由空变为非空的那一刻**记录当前播放位置，此后**不再更新**，直到集合清空。

```
t0  holds={}            playing @ 00:42      resumeAnchor = nil
t1  fullscreen 触发      holds={fullscreen}   resumeAnchor = 00:42  ← 锚定
t2  screenLocked 触发    holds={full, locked} resumeAnchor 保持 00:42  ← 不覆盖
t3  fullscreen 解除      holds={locked}       shouldPlay = false      ← 正确，不恢复
t4  screenLocked 解除    holds={}             seek(to: 00:42) → 播放  ← 从最初锚点续播
```

**为什么不每次暂停都更新锚点？** 若 t2 时锚点被更新成 00:55，t4 就会从 00:55 续播——跳过 t1→t2 之间本该播放的内容，用户感知为「莫名其妙往前跳」。

**不变式**：① `holds` 是唯一播放判据 ② 锚点在 `∅ → 非∅` 写入，在 `非∅ → ∅` 消费并清空 ③ 锚点生命周期内不被二次暂停覆盖 ④ 重复 `set(reason, active:)` 幂等。

**系统事件源（全部公开 API，实测存在于 SDK）：**

| 事件 | API | 公开? |
|---|---|---|
| 全屏 | `CGWindowListCopyWindowInfo` | ✅ |
| 锁屏 / 解锁 | 分布式通知 `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked` | ❌ **未文档化**，但 2 个在售 app 在用，无权限需求。**【待验证】** |
| 锁屏（备选） | `CGSessionCopyCurrentDictionary()` | ✅ 公开，但【实测】**无锁屏键**，无法用于锁屏检测 |
| 显示器熄屏 | `CGDisplayIsAsleep()` + `NSWorkspace.screensDidSleepNotification` | ✅（wallnetic 实测用此**双保险**） |
| 系统睡眠 / 唤醒 | `NSWorkspace.willSleepNotification` / `didWakeNotification` | ✅ |
| 电池 / 供电 | `IOPSCopyPowerSourcesInfo` / `IOPSGetPowerSourceState(..., kIOPSPowerSourceIsAC)` | ✅ |
| 低电量模式 | `ProcessInfo.isLowPowerModeEnabled` + 通知 | ✅ macOS 12+ |
| 屏保开始/结束 | 分布式通知 `com.apple.screensaver.didstart` / `didstop` | ❌ 未文档化 |
| Space 切换 | `NSWorkspace.activeSpaceDidChangeNotification` | ✅【推断】存在，未逐一 grep 确认 |

> **锁屏检测的诚实说明**：这是唯一一个「靠未文档化通知」的必需项。`com.apple.screenIsLocked` 在公开 SDK 里 **grep 不到**，但它在两个独立在售 app 的二进制里都存在，可信度高。**仍建议实机验证。** 若该通知失效，降级方案是轮询 `CGSessionCopyCurrentDictionary()` 的 `kCGSessionOnConsoleKey`（锁屏时通常仍为 true，**实际不可靠**）——**真正的降级方案未找到公开资料**。

**全屏检测：没有公开 API，是几何判定。** `kAXFullScreenAttribute` **不是公开 API**（全 SDK 搜索确认只有 `kAXFullScreenButtonAttribute`）；3 个在售 app **全部改用公开的 `CGWindowListCopyWindowInfo`**，且 **0 个引用辅助功能符号**。**→ 放弃辅助功能方案**（申请权限 + App Store 拒审，且 MirageWallpaper 作者明确拒绝为这个功能申请权限）。

**7 条反模式（本域特有，代码评审必查）：**
1. **用 `.desktopIconWindowLevel` 放壁纸** —— 会盖住桌面图标。必须用 `.desktopWindow`。**这两个只差 20，肉眼极难发现，代码评审列为必查项。**
2. **用优先级链做暂停仲裁** —— 见上文的锁屏+全屏反例。
3. **每次暂停都更新续播锚点** —— 锚点漂移，跳过本该播放的片段。
4. **用 `AXFullScreen` 属性检测全屏** —— 私有属性，要辅助功能权限。
5. **用 SwiftUI 做壁纸窗口** —— SwiftUI 没有 window level 概念，永远无法把窗口放到图标后面。
6. **把 watcher 直接连到播放器** —— 绕过仲裁器，多条件并存时行为不可预测且无法单测。
7. **用 AVKit 的 `AVPlayerView`** —— 带 UI chrome，壁纸不需要。

**推荐项目结构**（`State/` 零依赖 → 可毫秒级单测；`System/` 与 `Playback/` 严格分离 → 保证单向流；`Render/` 独立成目录 → 路线 A 失败时改动面被限制在这一个目录）：

```
Pic/
├── PicApp.swift · AppDelegate.swift（唯一装配点 wiring()）· Info.plist
├── State/    SettingsStore · HoldReason · PlaybackDecision · HoldArbiter
├── Media/    VideoItem · MediaLibrary · TranscodeService(v1=stub)
├── Playback/ PlayerController · PlaybackQueue
├── System/   FullscreenDetector · LockWatcher · PowerWatcher · DisplayWatcher
├── Render/   WallpaperWindow · WallpaperWindowController   ← ★ 唯一必须 AppKit 的地方
├── Features/ MenuBar/MenuContentView · Settings/SettingsView
└── Tests/    HoldArbiterTests · PlaybackDecisionTests
```

**窗口配置骨架（ARCHITECTURE 版，已实测属性/flag/数值；⚠️ 层级写法见 §4.1 决策 #1）：**

```swift
final class WallpaperWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        level = NSWindow.Level(CGWindowLevelForKey(.desktopWindow))  // 必须是 .desktopWindow，不是 .desktopIconWindow
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        isOpaque = true
        ignoresMouseEvents = true   // ⚠️ 实测：NSWindow 无此属性，在 NSView 上 —— 见 B.6 坑 #5
        backgroundColor = .black
        hasShadow = false
        isReleasedWhenClosed = false
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
```

**权限需求：零。** 不需要辅助功能权限（不调 AX API）、不需要屏幕录制权限（只读窗口**元数据**不读像素）、不需要私有框架。**注意**：Hanami 是 **Mac App Store 上架版本且开启了 App Sandbox**，仍然正常工作 —— PROJECT.md 里「非 App Store 才能用非公开 API」的预设可以放宽，**本方案根本不需要非公开 API**。

---

### Critical Pitfalls

**Top 5（按严重度排序，全部带一手 issue 证据）：**

1. **Pitfall 1 —— 「桌面窗口层级」方案可能根本不存在可行的公开 API 落点。** `NSWindow.level` 有下限；设 `level = kCGDesktopWindowLevel - 1` 时窗口要么被系统忽略（不进合成树）、要么被 Finder 桌面刷新时重绘覆盖，结果是「壁纸出现了一帧就没了」。
   **如何避免**：Phase 1 **必须先跑 demo 定案，不要先写架构**。demo 只需回答一个问题：`NSWindow` 设在 `.desktopWindow` 层时，**点击桌面图标能否选中、图标能否拖动**。能 → Route A 成立。不能 → 只能走 Route B 或降级。
   **⚠️ 与 ARCHITECTURE 的调和**：ARCHITECTURE 已用本机实时枚举证明**位于** `.desktopWindow` 层（-2147483623）可行（在售 app 正在跑）；PITFALLS 说的是**设到该层之下**是未定义空间。两者不矛盾，但 PITFALLS 补了 ARCHITECTURE 没列的验收动作：**「图标可点、可拖动、Finder 刷新后壁纸还在」**。
   **Warning signs**：demo 里壁纸窗口 `orderOut` 后不回来 / 壁纸在 Finder 图标刷新后消失 / 窗口能看见但点不到。
   **Phase**：Phase 1（层级可行性 demo）。

2. **Pitfall 2 —— 全屏检测没有公开 API，且几何判定在刘海屏 / Chrome 上会失效。** 两类错误：
   **(a) 假阴性** —— MirageWallpaper #73 实测数据：MacBook Air M3 13"（刘海屏）macOS 27.2 beta 上，全屏窗口顶部边缘因刘海下移，edgesMatch 判定失效，实测覆盖率仅 **96.548%**，低于 98.5% 阈值；**Chrome 更差，仅 87.343%**。该 issue 的日志暴露硬事实：
   ```
   display=1 bounds=0.0,0.0,1470.0,956.0 safe=0.0,32.0,1470.0,924.0
   ```
   `safe`（visibleFrame）比 `bounds` **顶部内缩 32pt** —— 那是刘海。用 `bounds` 算永远 100%，用 `visibleFrame` 算永远差一点。且 Chrome 全屏时同一 pid 会出现**两个** eligible 窗口，逐窗口匹配必然失败，**必须按 pid 聚合**。
   **(b) 假阳性** —— 隐藏 Dock 时选「填充」铺满屏幕（**不是**全屏）也会误触发停止。作者原话：**遮盖到 95 左右就是全屏**。
   **如何避免**：几何判定**用 `visibleFrame` 不用 `bounds`**，阈值 ~95%，**按 pid 聚合多个 rect**；过滤 window `layer` 与 `alpha`；用**事件**驱动（TzJ2006 PR #72 明确记录了「remove the 500 ms polling timer」这个动作）；**接受误判存在**，且**误判方向要选对：宁可少暂停（多耗点电）也不要误暂停（用户觉得壁纸坏了）**。
   **Warning signs**：在自己 Mac 上测通、用户 Mac 上不触发 → 先怀疑刘海 / Chrome / 超宽屏；日志里 `match=none` 但 `front=` 有值。
   **Phase**：Phase 1（原型，与 Pitfall 1 的层级方案**耦合**）+ Phase 3（落地）。

3. **Pitfall 3 —— 「播放/暂停」状态机被系统与自己的策略互相打架。** 两种互相独立的强制暂停源被混为一谈，表现是「壁纸莫名停了」：
   **系统侧**：phosphene #18 记录 WallpaperAgent 在**壁纸选择器交互期间**推 `=== UPDATE === mode: idle`，extension 策略把 `idle → paused`。表现是点开系统设置墙纸面板、或点击菜单栏图标，壁纸立刻暂停，交互完才恢复。**这是 WallpaperAgent 驱动的模式切换，不是自己的遮挡检测有 bug。** 注意 `NSWorkspace` 全量通知列表里**没有** `didEnterFullScreenNotification`（已用 Apple 文档 JSON 核对）——所以自建遮挡判定是唯一公开路径。
   **如何避免**：每个信号源独立可测，任一源坏掉不污染其他；**且对外暴露「当前为什么暂停」**（wallnetic #250 就是这条需求）。
   **⚠️ 与 ARCHITECTURE 的调和**：PITFALLS 引 Startorch PR #54 的 `PauseReason` **声明序**（`user > screen asleep > session inactive > fullscreen > desktop covered > low power > battery`）。**这个声明序只用于 UI 文案排序**；播放决策必须用 ARCHITECTURE §6.2 的 veto 集合（REQUIREMENTS PAUSE-07 已锁定）。用优先级链做决策是 ARCHITECTURE 反模式 2。
   **Phase**：Phase 2（播放与暂停策略）→ 本文档归入 **Phase 3**。

4. **Pitfall 4 —— AVQueuePlayer + AVPlayerLooper 队列状态管理错误 → 直接崩溃。**
   > DATA_v3n8wt4z_START
   > `NSInvalidArgumentException: An AVPlayerItem can occupy only one position in a player's queue at a time.` —— VideoPaper issue #3（macOS 26.0.1, M1 Max），「添加新壁纸」时必崩
   > DATA_v3n8wt4z_END
   根因（PR #4 定位）：多个 `AVPlayerLooper` 把**同一个** `AVPlayerItem` 加进同一个 `AVQueuePlayer`。同项目 wallpaper-play PR #45 记录了同一区域的另一类问题：用 NotificationCenter observer 做多视频循环会出现**重复 observer** 与 **loop 状态泄漏**，还伴随「本地视频循环时屏幕闪烁」。
   **如何避免**：切换视频前必须按序 `looper.disableLooping()` → `player.removeAllItems()` → 才能把新 item 入队；observer 注册与注销**严格配对**；`Timer` / `CADisplayLink` 必须在同一处 `invalidate()`。
   **Phase**：Phase 2（播放内核）。

5. **Pitfall 5 —— 每换一个视频就泄漏（内存与 GPU 资源双涨）。** VideoPaper PR #7 是个具体样本：`loadSwiftData()` 用 `FileManager.fileExists(atPath:)` 检查**存的是 `file://` URL 字符串**的值 → 检查恒为 false → 每次启动都走恢复分支，后果是每次启动堆一份重复文件 + 每次启动都碰 `@Attribute(.externalStorage)`，外部 blob 缺失时 CoreData 抛 `NSException`。用户侧症状见 wallpaper-play #37：「每几小时就持续无响应」（macOS 15.5 / M3 Max / 本地视频重复播放）。
   **如何避免**：换片显式 `replaceCurrentItem(with:)`；文件存在性检查统一用 `URL.path`（**不要把 `absoluteString` 喂给 `fileExists(atPath:)`**）；目录扫描结果做缓存。**验收标准写死：连续切换 50 次，内存回到基线 ±10%。**
   **Phase**：Phase 2（播放内核）+ Phase 7 前复验。

**其余 4 条 Critical（同类严重，列此以免遗漏）：**

6. **Pitfall 6 —— Space 切换后壁纸窗口消失 / 只在启动时的那个 Space 出现。** phonto #37（macOS 26.6.2）作者直指要害：「The Dock keeps one wallpaper window per Space, and on macOS 26 those sit at the exact same window level phonto was using.」wallnetic #256 记录本质：**Space 标识是会话相关的**，重开 app 后保存的分配可能根本无法再识别，其验收标准之一是「Never claim persistent Space identity when it cannot be established」。phosphene #21 另有拔插大屏后**尺寸不跟随**。
   **如何避免**：订阅 `NSWorkspace.activeSpaceDidChangeNotification`，切 Space 时**主动 re-assert** 窗口；**不要承诺 Space 级持久配置**（被两个独立项目分别踩到的设计陷阱）。
   **Warning signs**：在自己单屏 Mac 上永远复现不了 → **必须外接屏 + 多 Space 测**。

7. **Pitfall 7 —— 屏幕唤醒 / 睡眠 / 解锁后，播放状态不重算。** TzJ2006 PR #79 就是修这个：「re-evaluate wallpaper playback after a display wakes so occlusion rules apply immediately」。VideoPaper #8 更糟：解锁后只看到**冻结帧**；重新登录后背景变灰直到重启。phosphene #13 同源（`hasLiveRenderer(onDisplay:)` 把「有活 renderer」当成「已托管」→ 桌面一直黑屏）。phosphene #16 给了量化后果：`teardownGrace = 15.0s` × 双屏 × 2 角色 → **一个切壁纸动作短暂维持 8+ 个并发 4K decoder**，抢 VideoToolbox 有限的解码会话池，退化成软件解码，**卡顿约 15 秒**（实测窗口 +15.004s，与 teardownGrace 精确对上）。
   **如何避免**：暂停与恢复走**同一个 `re-evaluate()` 函数**，输入是全部信号的当前值；切屏时**手-off 式拆除**（新 renderer `onFirstFrameReady` 立刻拆旧），15 秒宽限期只留给休眠唤醒场景。**验收标准：连续 20 轮 休眠→唤醒 / 锁屏→解锁，播放状态 100% 正确，无黑屏无灰屏。**

8. **Pitfall 8 —— 非上架分发：签名、公证、自启三者各自的坑。** `SMAppService.mainApp`（macOS 13+）注册的是 **helper executable** 形态，`register()` 是 throwing，`status` **没有 `.disabled`**（四 case：`enabled` / `notRegistered` / `requiresApproval` / `notFound`）。公证自 **2023-11-01 起不再接受 `altool` 或 Xcode 13 及更早版本**，必须用 `notarytool` 或 Xcode 14+。
   **⚠️ 需求与手段的冲突**：PROJECT.md 的 Distribution 明确是「签名 .app，能拷到别的 Mac 跑」。**免费 Apple ID 签名的 .app 满足不了「能拷走」这一条**（约 7 天有效期 + 无法公证 + Gatekeeper 拦截）—— **必须在 Phase 6 前拍板**。

9. **Pitfall 9 —— 转码：FFmpegKit 已退役 + 许可状态 + 子进程退出码陷阱。**
   **(a)** 已核实 `arthenica/ffmpeg-kit` 仓库 `archived = true`，README 原文 `FFmpegKit has been officially retired`，继任项目 FFmpegKitNext **「distributed as source only」**。**这不是「官方弃用」那么简单 —— 是整条预编译二进制分发链断了。**
   **(b) 许可**：README 原文「Licensed under LGPL 3.0 by default, GPL v3.0 if GPL licensed libraries are enabled」。**开了 GPL 库（如 lame）就变 GPL v3.0**。**【待验证】**：具体到「自用不上架」场景下 GPL v3.0 对本项目的实际义务边界，**未找到针对此场景的公开资料**。
   **(c) 本机实测：Homebrew 装不上。** `brew install ffmpeg` 在 macOS 27 上因 `lame` / `dav1d` **无 bottle** 直接失败，必须先 `brew install --build-from-source`。
   **(d) 管道吞掉退出码。** `cmd | tail` 会拿到 0，检测代码**不能靠管道输出判断成败**。必须 `Process.run()` + `terminationStatus`。
   **如何避免**：转码方案**先做独立可行性验证**再决定；转码写临时目录**先检查剩余空间**；输出写 `xxx.tmp` 再 rename，避免半成品被扫进播放目录；**转码与播放不能抢同一资源**（`nice` 或串行化）。

**「以为是 Bug 其实是设计如此」Top 5（写进文档和 UI 就能消掉 80% 投诉）：**
1. **切换壁纸 / 全屏退出 / 解锁瞬间，壁纸会闪一下** —— MirageWallpaper #73 维护者原话：「动态壁纸都会闪一下是因为覆盖静态壁纸取渲染器刚播放壁纸时成功的第一帧，恢复实时渲染需要时间，**这不是 bug**。」→ 写进 README，不要当 bug 修。
2. **点开「系统设置 › 墙纸」或点菜单栏图标，壁纸会暂停** —— WallpaperAgent 行为，**不是你的 bug**。唯一能做的是把暂停原因显示出来。
3. **显示器多 / 用 Space 时壁纸「时有时无」** —— 跨 Space 的持久配置在公开 API 下**无法可靠实现**。v1 只做主屏，UI 上**不承诺 Space 级配置**。
4. **非原生格式（avi/mkv/webm）播放不了** —— 走转码。系统动态壁纸（Aerial）本身用 HEVC Main10 240fps（`manifest/entries.json` + `videos/*.mov`，~3840×2160 / ~12 Mbit/s）—— 你的 mp4 只要不是 HEVC 硬解规格就会明显更耗电。→ **设置里对每个视频显示「是否硬解」**，让用户自己权衡。
5. **换壁纸时卡顿约 15 秒** —— 若实现里保留类似 teardown 宽限期，**这是必然结果而非偶发**。

**Technical Debt Patterns（短视捷径 → 何时可接受）：**

| Shortcut | 长期代价 | 何时可接受 |
|---|---|---|
| 轮询 `CGWindowListCopyWindowInfo`（500ms）代替事件通知 | 全天后台轮询的电量成本 | 仅调研期 demo；**正式版必须换事件驱动** |
| 用 `AVPlayer.rate` 直接变速 | **会变调**（PROJECT.md 已列硬约束）；设非法值会抛 `NSException` | **永不** |
| 每次换片 `AVPlayerItem(url:)` 重建 | 内存单调上涨 | **永不** |
| 检测转码成功靠管道退出码 | **恒为 0，等于没检测** | **永不** |
| 免费 Apple ID 签名分发 | 7 天过期、无法公证、**拷不到别的 Mac** | 仅本机调试 |
| 转码输出直接写播放目录 | 半成品被扫进目录 → 播不了 | **永不** |
| 不写「当前暂停原因」 | 用户无法自诊断，投诉变成玄学 | **永不** |

**Performance Traps：** `teardownGrace` 式延迟拆除（切壁纸后卡 ~15s，**双屏立刻触发**）· 多窗口并发解码抢 VideoToolbox 池（退化为软件解码）· 500ms 全屏轮询（常驻即全天）· `preferredForwardBufferDuration` 设过大（解码积压、内存涨、耗电高）· 递归目录每次切文件重扫（I/O 尖峰）· **「性能档位」只有 UI 没有实际效果**（wallnetic PR #261 记录过这个：设置项存在但「no effect on playback」）。

**Security：** 为全屏判定申请辅助功能权限（权限过重 + TCC 弹窗时机不可控 + 用户拒绝后功能直接废 —— MirageWallpaper 作者明确拒绝）· 分发时未公证（Gatekeeper 拦截）· 误以为不上架 = 无需签名（**签名是分发的前提，不是上架的前提**）。

**UX Pitfalls：** 不显示当前暂停原因 · 菜单显示当前文件名（用户已明确不要）· 不显示「是否硬解」· **音效戛然而止**（用户明确反馈「有点怪」，暂停/恢复加音频渐弱渐强）· **第三方通知音也触发暂停**（壁纸音乐因无关音效中断，需可自定义的 app 白名单）· 「重新扫描文件夹」做成自动监听。

**「Looks Done But Isn't」验收清单（10 条）** —— 每条都是「在自己机器上测通 ≠ 做完」：
- [ ] **层级方案**：能播 ≠ 能贴在图标后面。必须验证「图标可点、可拖动、Finder 刷新后壁纸还在」
- [ ] **全屏检测**：必须在**刘海屏 + Chrome + 超宽屏**上各测一遍
- [ ] **播放内核**：单片能播 ≠ 列表循环不崩。必须跑 **50 次切换，内存回基线 ±10%**
- [ ] **暂停策略**：能暂停 ≠ 能正确恢复。必须跑 **20 轮 休眠/唤醒/锁屏/解锁/插拔显示器**
- [ ] **变速**：能变速 ≠ 不变调。必须**实际听 0.5× / 2× 的人声**
- [ ] **音频**：能出声 ≠ 睡眠时也停
- [ ] **自启**：能注册 ≠ 用户只点一次就成。必须验证 `requiresApproval` 分支有引导
- [ ] **分发**：本机能跑 ≠ 别的 Mac 能跑。必须在**未装开发者工具的第二台 Mac** 上验证
- [ ] **转码**：命令能跑 ≠ 装得上。`brew install ffmpeg` 在 macOS 27 上的失败需先解决
- [ ] **设置即时生效**：改了设置当场生效 ≠ 下一个视频才生效（PROJECT.md 硬约束）

---

## Implications for Roadmap

### 4.1 前置决策（开工前必须拍板 —— 便宜但发现得晚就代价高昂）

| # | 决策 | 冲突是什么 | 影响 | 紧急度 |
|---|---|---|---|---|
| **1** | **窗口层级的 Swift 写法** | **STACK.md**：`kCGDesktopWindowLevel` 是 C 宏导入不了，`CGWindowLevelKey` 的 Swift 成员名**试了 7 种拼法全部编译失败**（CoreGraphics.swiftinterface 不含该符号），推荐**硬编码 `NSWindow.Level(rawValue: -2147483623)`**。**ARCHITECTURE.md 与 REQUIREMENTS.md PLAY-01 / PROJECT.md**：`CGWindowLevelForKey(.desktopWindow)` 可用，需 `NSWindow.Level(rawValue:)` 转换。**两份 HIGH-confidence 实测文档直接冲突。** | 影响壁纸窗口能否编译。**解法是 5 分钟的 typecheck**，两种写法都测一遍即可定案 | **Phase 1 前**（它是 spike 的第一行代码） |
| **2** | **签名类型** | PROJECT.md Distribution = 「签名 .app，能拷到别的 Mac 跑」。PITFALLS #8：**免费 Apple ID 签名 7 天过期 + 无法公证 + 拷到别的 Mac 被 Gatekeeper 拦**，**满足不了 PACK-01**。要满足就必须 **Developer ID + 公证**（付费开发者账号） | **影响架构自由度**（PITFALLS 原文：签名前置决策要在 Phase 0/1 就确认）。也是唯一「事后补救成本为 HIGH」的项 | **Phase 1 前**（决策）；Phase 7 落地 |
| **3** | **设置窗口尺寸规格以谁为准** | **FEATURES.md B.4**：宽固定 **460pt** / 高 560 / min 440。**`.planning/UI-SPEC.md`（2026-10-03 定稿，REQUIREMENTS UI-01 指定为准）**：宽固定 **780pt** / min 宽 **680pt** / 高随内容（约 420）/ 无侧边栏 / 两列 | 直接影响 Phase 5 的工作量。**UI-SPEC 更晚、已定稿、且被 REQUIREMENTS 显式引用 → 以 UI-SPEC 为准**，FEATURES B.4 的 460 是过时建议 | Phase 5 前（**现在记下即可**） |
| **4** | **Xcode 工具链** | STACK / ARCHITECTURE / PITFALLS **三份都记录了「Xcode 未安装，仅 CommandLineTools」作为阻塞**（PITFALLS 原话：「建不了 app，正式开发前需先装 Xcode」；FEATURES 坑 #10「Command Line Tools 编不了 `@State`」） | ✅ **已解除** —— PROJECT.md Context 记录：Xcode 27.0（27A266a）已装、`xcode-select` 已切、`Form` + `.formStyle(.grouped)` + `Slider` + `@State` + `@Observable` 组合已 `-typecheck` 通过。**roadmapper 不要按三份文档的陈旧阻塞排期** | **已关闭** |
| **5** | **转码的 ffmpeg 路线** | PROJECT.md 决策：「转码走**调用系统已安装的 `ffmpeg`** 路线…App 不内置、不联网下载」（REQUIREMENTS TRANS-01/02 已落条）。**STACK.md 实测**：本机 `which ffmpeg` → **not found**；且判定该路线**违反「拷到别的 Mac 上跑」的自足性**（要求每台目标 Mac 都 brew install）；**PITFALLS #9(c) 实测**：macOS 27 上 `brew install ffmpeg` 因 `lame` / `dav1d` 无 bottle **直接失败**，要先 `--build-from-source` | **需求与实测环境正面冲突。** 可能出路：① 接受 brew 预装前提并把 `--build-from-source` 写进文档 ② 改用系统 `AVAssetReader` + VideoToolbox 路径（STACK 推荐，但有「视觉无损能否达成」的验证成本）③ v1 只播原生格式、转码延后。**本文档不替你拍板** | **Phase 6 前**（但要在 Phase 1 就意识到，因为它影响「自足性」这条分发约束的整体判断） |

### 4.2 门禁与依赖结构

**🚧 唯一的门禁（Gate）：Phase 1 桌面层级 spike。**
ARCHITECTURE 原文：*"P1 是所有后续阶段的前置门。若 P1 证伪，整个架构需重做，后面全部作废。"*
PITFALLS #1：*"Phase 1 **必须先跑 demo 定案，不要先写架构**。"*
→ **做不成 = 后面全废**。但它是**几小时的一次性验证 app（throwaway，非产品代码）**，成本极低、信息量极大。**没有任何理由不先做它。**

**🧱 地基（必须先做，后续全部依赖）：** Phase 2 播放内核竖切 —— `SettingsStore` / `HoldArbiter` / `PlayerController` 的**接口在此定死**，Phase 3/4/5 全部依赖它。

**🔀 可并行：** **Phase 3（系统事件仲裁）与 Phase 4（媒体库与轮换）无耦合**（ARCHITECTURE §10 明确建议并行）。两者只共享 `MediaLibrary` 与 `HoldArbiter` 的接口 —— **接口先定死即可并行**。

**⛓️ 严格串行：** Phase 1 → Phase 2 → {Phase 3 ‖ Phase 4} → Phase 5 → Phase 6 → Phase 7。
（Phase 5 依赖 Phase 2 的 `SettingsStore` 与 Phase 3/4 提供的可调项；Phase 6 依赖 Phase 4 的 `MediaLibrary`；Phase 7 依赖 Phase 3–5。）

### Phase 1: 桌面层级可行性 spike 🚧 **门禁**

**Rationale:** PROJECT.md 自认的最大技术风险；ARCHITECTURE §10 与 PITFALLS #1 一致要求它必须最先做，且**在写任何架构之前**。
**Delivers:** 一次性验证 app（throwaway）——
- 一个带帧号的彩色视图放在 `level = -2147483623`，逐项验收 ARCHITECTURE §2.2 的 **5 条【待验证】**
- PITFALLS #1 验收动作：**图标可点、可拖动、Finder 刷新后壁纸还在**
- **定案 §4.1 决策 #1**（`CGWindowLevelForKey` vs 硬编码）：5 分钟 typecheck 两版都试
- **全屏检测几何原型**（PITFALLS #2：`visibleFrame` 而非 `bounds`、~95% 阈值、按 pid 聚合、过滤 layer/alpha）—— 因为它与层级方案**耦合**
- 锁屏通知实测：`com.apple.screenIsLocked` 在 macOS 27 是否触发
- 顺带验 `MenuBarExtra` 在 `.accessory` 策略 + 无 Dock 图标下的行为（`confidence: MEDIUM`）；`NSStatusItem` 是稳妥退路
- 把路线 C / D 作为**对照项**（A 的层级问题正是最大风险）
- 用 `powermetrics` 做 `isOpaque = true` 的 A/B 实测（STACK §2.3 C 组对照实验：不播 / v1 配置 / `isOpaque=false` / `AVPlayerView`，每组 5 分钟）
**Addresses:** PLAY-01, PLAY-02, SYS-02
**Avoids:** PITFALLS #1, #2, #6；ARCHITECTURE §2.2 全部待验证项
**Research flag:** **不需要桌面研究** —— 这一阶段本身就是研究。它需要的是**执行**，不是调研。

### Phase 2: 播放内核竖切 🧱 **地基**

**Rationale:** 最小可感知价值（能端到端看到视频在桌面图标后面播）；ARCHITECTURE P2；**所有后续阶段的地基**。
**Delivers:** 菜单栏常驻（`LSUIElement=true`）+ 壁纸窗口 + 单文件无缝循环 + `SettingsStore`（`@Observable` + UserDefaults）+ `HoldArbiter`（先只接手动暂停）+ `AppDelegate.wiring()` 唯一装配点。
**Uses:** `AVQueuePlayer` + `AVPlayerLooper` + `AVPlayerLayer`；`audioTimePitchAlgorithm = .spectral`（显式设，默认是 `.timeDomain`）；`preferredForwardBufferDuration = 3.0`；`isOpaque = true` / `hasShadow = false` / `videoGravity = .resizeAspectFill`。
**Implements:** `State/` + `Playback/` + `Render/` 三层（ARCHITECTURE §9 结构）
**Addresses:** MENUBAR-01, MENUBAR-02, MENUBAR-07, MENUBAR-08, PLAY-01, PLAY-02, PLAY-08
**Avoids:** PITFALLS #4（入队纪律：`disableLooping()` → `removeAllItems()` → 再入队；observer 严格配对）、#5（50 次切换内存回基线 ±10%；`URL.path` 不是 `absoluteString`）、#7（暂停/恢复走同一个 `re-evaluate()`）
**Research flag:** **标准模式，跳过 research-phase** —— 架构与 API 已全部实测，坑已全部点名。

### Phase 3: 系统事件仲裁（veto 状态机）

**Rationale:** 需求里最复杂的一部分，**必须有 Phase 2 骨架才能接**。
**Delivers:** 4 个 Watcher（`FullscreenDetector` / `LockWatcher` / `PowerWatcher` / `DisplayWatcher`）+ 完整 veto 集合仲裁 + resume anchor + **纯逻辑单测**（不 import AVFoundation，毫秒级）+ 启动时层级常量单测锁死「三个魔法数字」。
**Addresses:** PAUSE-01 ~ PAUSE-08
**Avoids:** PITFALLS #2（落地）、#3（暂停状态机打架）、#7（唤醒/解锁重算）
**关键设计**：`Set<HoldReason>` veto 集合，**`isEmpty` 才播**（REQUIREMENTS PAUSE-07 锁定）；**优先级只用于 UI 文案排序**（PITFALLS #3 引的 Startorch 声明序不能用来做决策 —— 那是 ARCHITECTURE 反模式 2）；**必须对外暴露「当前为什么暂停」**（wallnetic #250）。
**【待验证】必须在 Phase 3 实测**：`com.apple.screenIsLocked` 分布式通知的稳定性（无 Apple 官方文档明载）。
**Research flag:** **不需要额外 research-phase** —— 但若 Phase 1 的锁屏实测失败，则**升级为需要 research**（「真正的降级方案未找到公开资料」）。

### Phase 4: 媒体库与轮换（**可与 Phase 3 并行**）

**Rationale:** ARCHITECTURE §10 明确 P3/P4 无依赖，**建议并行** —— 墙钟时间紧时两者只共享 `MediaLibrary` 与 `HoldArbiter` 的接口，接口先定死即可。
**Delivers:** 递归扫描（`FileManager.enumerator`）+ 扩展名过滤（mp4/mov/m4v）+ `AVURLAsset` 可加载视频轨校验 + 三种播放模式（单循环 / 列表循环 / 列表随机）+ 轮换计时器（到点就切，不等播完）+ 文件夹失效降级（`PlayerController.stop()` + `orderOut(nil)` → **系统原壁纸自然露出，因为我们从不改系统壁纸，只是盖了一层**）+ 重新扫描菜单项。
**Addresses:** SOURCE-01 ~ SOURCE-08, PLAY-03 ~ PLAY-06, MENUBAR-05
**Avoids:** PITFALLS #5（扫描结果**做缓存**，别每次切文件都重扫 —— 递归目录会放大这个问题）、#6（订阅 `activeSpaceDidChangeNotification` 主动 re-assert；**不承诺 Space 级持久配置**）
**Research flag:** **标准模式，跳过 research-phase**。

### Phase 5: 设置窗口与即时生效

**Rationale:** 依赖 Phase 2 的 `SettingsStore` 与 Phase 3/4 提供的可调项。UI 已定稿（`UI-SPEC.md` B1 深海 + L4 双列）。
**Delivers:** 按 `.planning/UI-SPEC.md` 实现（**780pt 固定宽 / min 680 / 两列 / 无侧边栏**，**以 UI-SPEC 为准，不是 FEATURES B.4 的 460**）+ 空态警告态（硬需求文案：「没找到能播的文件。壁纸已隐藏，桌面显示的是系统原壁纸。」）+ 两条置灰联动（单循环 → 轮换时间置灰；声音关 → 音量滑杆置灰）+ **全量订阅实现**（`rate` / `volume` 挂 `AVPlayer` 当场生效，**不挂 `AVPlayerItem`**）+ 首次启动直接弹 `NSOpenPanel`。
**Addresses:** UI-01 ~ UI-03, PLAY-07 ~ PLAY-10, SYS-03, MENUBAR-06
**Avoids:** PITFALLS UX（不显示暂停原因 → 投诉变玄学）、FEATURES B.6 坑 #6（`Toggle` 别包进 `LabeledContent`）、#2（保音高设 item，变速设 player）
**注意**：`audioTimePitchAlgorithm` 变更**需要重建 `AVPlayerItem`**，是「改不了 live 对象」的少数例外 —— 应在改动时重建并 seek 回 resumeAnchor。【推断】
**Research flag:** **不需要外部 research** —— UI-SPEC 已定稿。但**需要 `/gsd-ui-phase`**（config `ui_phase: true`，把 UI-SPEC 转成 UI 契约）。

### Phase 6: 转码 ＋ 独立窗口 ⚠️ **前置决策阻塞**

**Rationale:** FEATURES 把转码列为 v1.x（触发条件：核心播放稳定跑一周）；ARCHITECTURE 放最后（体积 / 复杂度最大）；也是**全品类唯一无人做的功能**（differentiator，但 HIGH 成本）。
**⚠️ 阻塞**：**§4.1 决策 #5 必须先解决**（PROJECT.md 的「调用系统 ffmpeg」路线与本机实测 + 自足性约束冲突）。
**Delivers:** PATH 检测（TRANS-01）+ 缺失时**置灰并提示安装途径**（TRANS-02）+ 视觉无损转码 + 产物落壁纸目录且**不被重扫**（TRANS-04/05）+ 任务队列窗口（进度 + **将要执行的实际命令，可审计** —— TRANS-06）。
**Addresses:** TRANS-01 ~ TRANS-06
**Avoids:** PITFALLS #9（退出码必须用 `terminationStatus`，**绝不用管道**；输出写 `xxx.tmp` 再 rename；转码与播放不抢资源；`nice` 或串行化）
**转码窗口的例外必须写进 Phase 计划**：**全 app 唯一允许出现列表的地方** —— 用户否掉的是**浏览式**视频列表，转码队列是**操作产物**。不写清楚会被当 scope creep 砍掉。
**Research flag:** ✅ **需要深度 research-phase** —— 理由：① ffmpeg 路线冲突未决 ② 「视觉无损」的 CRF / preset / 编码器选择（libx264 vs libx265 vs svt-av1 vs VideoToolbox hw）**完全未定** ③ 产物命名 / 目录规则必须避免「产物被再次扫成待转码输入」的无限循环（具体规则**待设计**）④ GPL v3.0 在自用场景的义务边界**【待验证】**。

### Phase 7: 打包分发与开机自启

**Rationale:** ARCHITECTURE P7 收尾；**签名类型已在 §4.1 决策 #2 前置拍板**，此处只落地。
**Delivers:** 签名 + 公证（`notarytool`，**不是 `altool`**）+ `SMAppService.mainApp` 注册 + **`requiresApproval` 分支引导**（「手动设一次」的落点 = 去「系统设置 › 通用 › 登录项」批准）+ **在第二台未装开发者工具的 Mac 上验证**。
**Addresses:** PACK-01, PACK-02, SYS-01, MENUBAR-01
**Avoids:** PITFALLS #8（签名 / 公证 / 自启三坑）、Recovery「免费 Apple ID 签名已分发出去」成本 HIGH
**Research flag:** **标准模式** —— `notarytool` + `SMAppService` 是 Apple 文档覆盖充分的常规流程。**不需要 research-phase。**

### 4.3 Phase Ordering Rationale

- **门禁优先**：Phase 1 是唯一「证伪则全废」的项，且成本极低（一次性验证 app）。ARCHITECTURE 与 PITFALLS **独立地**得出了同一结论 —— 这是最强的排期信号。
- **地基优先于功能**：Phase 2 定死 `SettingsStore` / `HoldArbiter` / `PlayerController` 三个接口，Phase 3/4/5 全部依赖它们。**接口先定死**是并行化的前提。
- **按架构分层切，不按 UI 页面切**：Phase 2 建 `State/` + `Playback/` + `Render/`（架构分层），Phase 3 加 `System/`，Phase 5 加 `Features/`。这对应 ARCHITECTURE §9 的目录结构，每阶段交付**一个可独立验证的层**，而不是半个页面。
- **暂停策略独立成阶段**：暂停仲裁是需求里最容易出 bug 的部分（覆盖式反例），且可做成不 import AVFoundation 的纯类型 → 必须给它独立阶段 + 毫秒级单测，不能混在「播放内核」里顺手做。
- **最复杂、依赖最多的放最后**：转码（Phase 6）依赖媒体库、有未决决策、体积与复杂度最大，且 FEATURES 明确建议等核心播放稳定后再做。
- **坑的规避落在具体阶段**：PITFALLS 的 9 条 Critical 全部映射到了阶段（见 §4.4），没有一条是「以后注意」。
- **并行是真实可用的**：Phase 3（事件层）与 Phase 4（媒体层）之间**零耦合**，这是本项目唯一的并行机会，值得在 ROADMAP 里显式标注。

### 4.4 Pitfall → Phase 映射（照搬 PITFALLS.md，供 roadmap 直接引用）

| Pitfall | 防御 Phase | 验证方式 |
|---|---|---|
| 1 层级方案无公开落点 | **Phase 1（门禁）** | demo 证明图标可点/可拖/Finder 刷新后仍在 |
| 2 全屏检测误判 | Phase 1（原型）+ Phase 3（落地） | **刘海屏 / Chrome / 超宽屏**三者各测一遍 |
| 3 暂停状态机打架 | Phase 3 | veto 枚举 + 「当前暂停原因」UI 可见 |
| 4 AVQueuePlayer 崩溃 | Phase 2 | 连播/快切 50 次无异常 |
| 5 换片内存泄漏 | Phase 2 + Phase 7 前复验 | 50 次切换内存回基线 ±10% |
| 6 Space 切换丢失 | Phase 2 + Phase 4 | 多 Space + 插拔显示器；UI 不承诺 Space 级配置 |
| 7 唤醒/解锁状态不重算 | Phase 2 + Phase 3 | 20 轮 休眠/唤醒/锁屏/解锁无黑屏灰屏 |
| 8 签名/公证/自启 | **Phase 1 决策 + Phase 7 落地** | 第二台未装开发工具的 Mac 上可运行 |
| 9 转码（FFmpegKit 退役/许可/退出码） | **Phase 1 意识 + Phase 6** | 独立构建验证 + `terminationStatus` 单测 |

### 4.5 Research Flags

**需要 `/gsd-plan-phase --research-phase <N>` 的阶段：**
- **Phase 6（转码）** —— **唯一一个真正需要额外研究的阶段**。理由：ffmpeg 路线冲突未决（§4.1 决策 #5）· 视觉无损的 CRF/preset/编码器全未定 · 产物命名规则待设计（防扫描死循环）· GPL v3.0 义务边界【待验证】。STACK.md §8 与 PITFALLS.md 的 Gaps 都指向这里。

**不需要研究（标准模式 / 已实测）：**
- **Phase 1** —— 它本身就是研究（经验性 spike）。**它需要的是执行，不是调研。**
- **Phase 2 / 3 / 4** —— 架构与 API 已全部本机实测，坑已全部点名并有 issue 号。**唯一例外**：若 Phase 1 的锁屏通知实测失败，Phase 3 需升级为需要 research（「真正的降级方案未找到公开资料」）。
- **Phase 5** —— UI-SPEC 已定稿。走 `/gsd-ui-phase`，不走 research。
- **Phase 7** —— `notarytool` + `SMAppService` 是 Apple 文档覆盖充分的常规流程。

**⚠️ 一个还没解决的联网问题可能影响 Phase 1/3** —— 见 §6。

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| **Stack** | **HIGH**（核心 API）/ **MEDIUM**（旋钮取值 + 路线 C/D 可行性） | Apple SDK API **全部本机实测**（头文件 grep + `swiftc -typecheck` 9 个探针 + C 探针运行输出）。但**性能旋钮的具体取值**（`preferredPeakBitRate`、`isOpaque` 收益）是 MEDIUM —— 需 Phase 1 A/B 实测。**硬解默认开启**是 MEDIUM —— 推理依据充分但**未在真机抓 VideoToolbox 调用栈验证**。**路线 C/D 可行性** MEDIUM。 |
| **Features** | **HIGH**（Part A + Part B 控件存在性）/ **MEDIUM**（Part B 视觉与布局） | Part A 是 **App Store 实时抓取的开发者亲述**（iTunes Search/Lookup API），非二手转述。Part B 控件存在性是**本机 SDK 实编译验证**。视觉/布局是 Apple 文档 + macOS 惯例，**未运行渲染** —— 「macOS 27 上 `.formStyle(.grouped)` + `Section` 的实际渲染效果」需 app 目视确认。 |
| **Architecture** | **HIGH**（桌面层级与检测机制）/ **MEDIUM**（Space 与耗电行为） | 层级机制有**本机实时窗口枚举 + 3 个在售 app 反汇编**双重证据（收敛信号极强：3/3 零私有框架、零 AX 符号）。拖到 MEDIUM 的是「Space 行为 + 耗电」—— 负层级窗口在多 Space / 台前调度的行为 **Apple 未文档化**，5 条【待验证】必须 Phase 1 spike。 |
| **Pitfalls** | **MEDIUM-HIGH**（issue 证据充分；功耗绝对数值 / FFmpeg 许可细节偏低） | 全部带可追溯 issue 号 + 实测数字（**未验证的 issue 号或 URL 一个都没有**）。**但证据来自别家项目的环境，不是本机** —— 例：MirageWallpaper #73 的 96.548% / 32pt 只在 **M3 Air 13" / macOS 27.2 beta** 实测过一次，是否普遍成立**【待验证】**。 |
| **Overall** | **MEDIUM-HIGH** | 「能不能做、怎么做」的问题**基本被本机实测回答完了**；「做出来好不好、稳不稳」的问题**必须靠 Phase 1 spike + Phase 2/3 验收清单回答**。 |

### Gaps to Address

**A. 未决冲突（roadmapper 必须在 ROADMAP 里显式处理）**
1. **窗口层级 Swift 写法**（§4.1 #1）—— 两份 HIGH 文档直接冲突，Phase 1 花 5 分钟 typecheck 定案。
2. **签名类型**（§4.1 #2）—— 免费 Apple ID 签名满足不了 PACK-01。
3. **设置窗尺寸**（§4.1 #3）—— UI-SPEC 780pt 覆盖 FEATURES 460pt。
4. **转码 ffmpeg 路线**（§4.1 #5）—— PROJECT.md 决策 vs 本机实测 + 自足性约束。

**B. 【待验证】清单（全部保留自四份源文档，一条不删）**

*来自 ARCHITECTURE.md（Phase 1 spike 验收清单）：*
- 多 Space 下 `canJoinAllSpaces` + **负层级窗口**是否真在每个 Space 都出现 —— Apple 未文档化负层级窗口的 Space 行为
- 台前调度（Mission Control）时是否显示 / 是否缩小 —— `.stationary` 语义是「像桌面窗口一样」，但负层级是否触发未验证
- `.fullScreenAuxiliary` 在负层级下是否真的让位 —— 文档描述针对 normal level 窗口
- 有虚拟桌面 / Stage Manager 时行为 —— macOS 27 新特性，未在文档中找到相关说明
- 屏幕保护程序启动时的实际表现 —— 需实跑
- `.saver` 路线**能否播视频** —— saver 走 `animateOneFrame` 定时回调渲染，播视频要自己接 `AVPlayerLayer`
- 全屏窗口的 `kCGWindowBounds` 在 Retina 下是否等于 `NSScreen.frame` —— 理论上对齐，**未实测**
- 全屏应用是否为 `kCGWindowLayer == 0` —— 不同 app 可能不同，**未找到公开资料**
- 容差 `2pt` 是否足够 / 是否需要按缩放因子调整
- `NSWorkspace.activeSpaceDidChangeNotification` —— **【推断】**存在，未逐一 grep 确认
- `.canJoinAllApplications`（macOS 13+ 新增）是否需一并考虑 —— **【推断】**
- `audioTimePitchAlgorithm` 变更需重建 `AVPlayerItem` —— **【推断】**
- `@Observable` + 订阅实现用 Combine 还是 `Task` + AsyncStream —— **【推断】**，建议避免引入 Combine

*来自 PITFALLS.md（Phase 2/3 执行时验证）：*
- **`com.apple.screenIsLocked` 分布式通知的稳定性** —— 无 Apple 官方文档明载，属未文档化用法，需 Phase 3 实测。**（这条同时被 ARCHITECTURE 列为未验证项 —— 两个独立来源都指向它，风险最高）**
- **GPL v3.0 在「自用不上架」场景的实际义务边界** —— 未找到针对此场景的公开资料
- **macOS 27 上刘海屏 `visibleFrame` 内缩值是否恒为 32pt** —— 只在 M3 Air 13" / macOS 27.2b 实测过一次
- **功耗绝对数值（AVPlayer 解码占多少电）** —— 未找到公开的一手实测数据
- **phonto #37（跨 Space 失效）根因未确定** —— 作者未能复现，怀疑与 macOS 26.6.2 特定版本相关。若 Phase 2 遇到，需自己写 `CGSCopySpacesForWindows` 探针复现

*来自 STACK.md：*
- `preferredPeakBitRate` 取值（`源码率 × 1.2` vs `0`）—— **两种配置需 Phase 1 A/B 实测**
- `NSWindow.isOpaque = true` 的**实际收益** —— 必须在 Phase 1 用 `powermetrics` A/B 实测，**文档未实测**
- `MenuBarExtra` 在 `.accessory` 策略 + 无 Dock 图标下的行为 —— 需 Phase 1 验证（`NSStatusItem` 是退路）
- 路线 D 的**跨版本稳定性** —— LOW。VideoPaper README 只声明支持 `.mov`
- `powermetrics` 的 flag 用法 —— 工具存在性 HIGH，**flag 名未逐一验证**

*来自 FEATURES.md：*
- macOS 27 上 `.formStyle(.grouped)` + `Section` 的**实际渲染效果** —— 需运行 app 目视确认，本次仅静态验证

**C. 联网未解决（§6 详列）** —— 调研期 WebSearch/WebFetch 全程失败，以下问题**只能靠公网回答**，本机无法定论。其中**第 1、2、3 条可能直接影响 Phase 1 的层级 spike 结论**。

---

## 未找到公开资料（需用 web 工具调研，四份文档原样汇总）

> 调研期内置 `WebSearch` / `WebFetch` **全部失败**（6/6 `API Error: 400`）。以下问题**本机无法回答**，需复制 prompt 去查。原文出处见括号。

| # | 问题 | 出处 | 是否影响 Phase 1 |
|---|---|---|---|
| 1 | **macOS 26/27 上是否有人报告过 `CGWindowLevelForKey(.desktopWindow)` 的窗口行为变化**？（不再显示在桌面图标后 / 被 Stage Manager 遮挡 / 多 Space 失效 / 系统更新后层级被重置） | ARCHITECTURE §12.2 Q1 | ✅ **直接影响门禁判断** |
| 2 | Stage Manager（台前调度）开启时，**负层级窗口**的表现如何？桌面图标是否仍在 `kCGDesktopIconWindowLevel`？ | ARCHITECTURE §12.2 Q2 | ✅ **直接影响** |
| 3 | **`CGWindowListCopyWindowInfo` 在 macOS 15+ 是否需要屏幕录制权限**？（Sonoma 起对 `kCGWindowName` / `kCGWindowOwnerName` 是否有限制）—— 只需要 window layer 和 bounds 的情况下权限要求是什么？ | ARCHITECTURE §12.2 Q5 | ✅ **影响 Phase 1/3** |
| 4 | macOS 26/27 上 **ScreenSaver bundle（.saver）机制是否已被弃用或限制**？Sonoma / Sequoia 上有无已知回归？ | ARCHITECTURE §12.2 Q4 | ⚠️ 影响退路 B |
| 5 | **macOS 27 上是否存在比 `kCGDesktopWindowLevel` 更「官方」的视频壁纸 API**？Apple 在 26/27 发布说明里有无提到 dynamic / animated wallpaper 的新能力？ | ARCHITECTURE §12.2 Q7 | ⚠️ 影响路线选择 |
| 6 | **桌面级窗口播放视频的实测耗电数据** —— Apple Silicon 用 AVPlayer + AVPlayerLayer 全屏 5.4K 循环播放，对比不播放时的 battery drain（%/h） | ARCHITECTURE §12.2 Q6 | ❌ 影响验收标准定量 |
| 7 | **FFmpegKitNext 从源码构建** 在 M 系列 Mac 上出可用 `.xcframework` 要多久？仓库里有无可参考的 CI 配置？ | STACK §8 Q1 | ❌ Phase 6 |
| 8 | **libx264 / libsvtav1 打进 macOS .app 的实测体积增量**是多少 MB？（要实测数据，不要二手估算。PROJECT.md 原文估 +80~150MB，**本轮未能复核**） | STACK §8 Q2 | ❌ Phase 6 |
| 9 | macOS 26/27 上**直接改写 Aerial manifest `entries.json`** 是否仍生效？会不会被系统覆盖？需不需要重启？有无 Apple 官方 schema 文档？ | STACK §8 Q3 | ❌ 路线 D |
| 10 | **Wallpaper Engine for macOS 有没有官方版或在开发中**？官方声明 / 路线图在哪？ | STACK §8 Q4 | ❌ 仅竞品情报 |
| 11 | **`wallpaper-engine-kde` 是否存在、是否与 macOS 有关**？（本轮按命名推断是 Linux/KDE 项目，**未核实**，`confidence: LOW`） | STACK §8 Q5 | ❌ 仅技术选型表 |
| 12 | macOS 视频壁纸 app 的**实测功耗基线** —— 有没有 app 用 `powermetrics` 报过 CPU wakeups / GPU active% 具体数值？（用于给「不偷电」定量） | STACK §8 Q6 | ❌ 验收标准定量 |
| 13 | **Wallpaper Engine 完整设置项清单** —— 帮助站所有路径都返回同一落地页（SPA 路由），未能逐页抓取 | FEATURES Sources | ❌ 已从产品形态确认其 macOS 状态 |
| 14 | **任何 macOS 版「Wallpaper Engine 等价物」的官方设置规范** —— 无此物，品类无统一规范可抄 | FEATURES Sources | ❌ |
| 15 | **视频壁纸项目开源生态的完整清单** —— ARCHITECTURE §12.2 Q3 问的那一条，**已被 STACK.md 用 GitHub Search API 部分补齐**（12 个项目元数据 + 4 条路线判定） | ARCHITECTURE §12.2 Q3 | ✅ **已完成**（STACK §5） |

**输出格式要求（沿用原 prompt）**：每问给明确答案 + 可点击 URL + 来源日期；找不到的写「未找到公开资料」，**不要推测**；每条结论标 confidence。

---

## Sources

### Primary (HIGH confidence)

**本机实测（macOS 27.0.1 build 26A434 / arm64 / Swift 6.4 / SDK `MacOSX27.0`）**
- SDK 头文件：`AVPlayerLooper.h` / `AVPlayerItem.h` / `AVPlayer.h` / `AVAssetExportSession.h` / `AVAssetReaderOutput.h` / `AVSampleBufferDisplayLayer.h` / `AVSampleBufferVideoRenderer.h` / `AVPlayerLayer.h` / `VTCompressionProperties.h` / `VTDecompressionSession.h` / `NSWindow.h` / `CGWindowLevel.h` / `CGWindow.h` / `CAMetalLayer.h` / `NSProcessInfo.h` / `IOPowerSources.h` / `CGSession.h` / `CGDisplayConfiguration.h` / `SMAppService.h` / `ScreenSaver.framework`
- **`swiftc -typecheck` 实编译 9 个探针文件**（含 4 个故意写错以反推真实 API 名），产物已丢弃
- **C 探针运行输出**：`kCGMinimumWindowLevel` / `kCGDesktopWindowLevel` / `kCGDesktopIconWindowLevel` 实际数值
- **实时窗口层级枚举**（自编 C 程序调 `CGWindowListCopyWindowInfo(.optionOnScreenOnly)`，按 layer 分组）
- **3 个在售 app 反汇编**：`nm -u`（导入符号）+ `otool -L`（框架）+ `codesign -d --entitlements`（沙盒）+ `strings`
- 本机文件系统：`/System/Library/PrivateFrameworks/WallpaperExtensionKit.framework` · `~/Library/Application Support/com.apple.wallpaper/aerials/` · `/System/Library/Screen Savers/` · `/System/Library/Frameworks/ScreenSaver.framework/PlugIns/`（`legacyScreenSaver.appex`）
- `which ffmpeg` → **not found**

**一手 issue（全部经 GitHub REST API 实读，非记忆）**
- `kageroumado/phosphene` #13 #15 #16 #17 #18 #20 #21 #26 **#29**；PR #24 #25 #30 #32
- `museslabs/phonto` #36 **#37**；PR #21 #27
- `laobamac/MirageWallpaper` #52 **#73**（含全部评论与实测日志）
- `Mcrich-LLC/VideoPaper` #1 **#3** #6 **#8**；PR **#4** **#7**
- `nhiroyasu/wallpaper-play` #37 #38；PR #45
- `fatihkan/wallnetic` #250 **#255 #256** #257 #259 #260；PR #261 #262
- `TzJ2006/desktop-video-for-mac` PR **#72** #73 #76 #77 #78 **#79** #80
- `ducbao414/live-wallpaper` #1 **#4**
- `jaywcjlove/vidwall` #2
- `misaki1301/Startorch-Wallpaper-Engine` PR #52 #53 **#54** #61 **#62** #63 #64

**Apple 官方文档（经 developer.apple.com 文档 JSON API 直读）**
- `SMAppService` / `.mainApp` / `.Status`（四 case；macOS 13+）· `CGWindowLevelKey` / `CGWindowLevel` · `AVAudioTimePitchAlgorithm` / `AVPlayerItem.audioTimePitchAlgorithm`（非法值抛 `NSException`）· `AVPlayerItem.preferredForwardBufferDuration` · `ProcessInfo.isLowPowerModeEnabled` · `AVAudioSession` 平台列表（**不含 macOS**）· `NSWorkspace` / `NSApplication` 全部通知名（**无 fullscreen 通知**）· Notarizing macOS software before distribution · Resolving common notarization issues · SwiftUI `form` / `settings` / `settingslink` / `menubarextra` / `section` / `groupbox` / `labeledcontent` / `formstyle`

**App Store 一手元数据（iTunes Search / Lookup API，US + CN，2026-10-02）**
- 竞品功能**全部来自开发者自己在 App Store 写的描述**，非二手转述。id: VideoPaper `id6587549333` · Dynamic Wallpaper Studio `id1453504509` · 4K Live Wallpaper `id1469182113` · iWallpaper `id1552826194`（macOS）/ `id1155869721`（iOS）

**GitHub REST API（2026-10-02 实时元数据）**
- `api.github.com/repos/arthenica/ffmpeg-kit` → `archived: true`；README「Update (July 2026) … FFmpegKit has been officially retired」
- `api.github.com/repos/arthenica/ffmpeg-kit-next` → `archived: false`, LGPL-3.0, 151★, `pushed_at 2026-10-01`
- `api.github.com/search/repositories?q=macos+video+wallpaper+language:Swift` → 12 个项目元数据（★/许可/推送日期）
- 各项目 `git/trees?recursive=1` 文件树（判定技术路线）
- `raw.githubusercontent.com/.../wallnetic/.../PowerManager.swift` → 全屏检测 / 电源 / 熄屏实现全文
- `raw.githubusercontent.com/.../phosphene/.../{Info.plist,PhospheneExtension.swift}` · `VideoPaper/.../JsonWallpaperCoordinator.swift`

### Secondary (MEDIUM confidence)
- `wallpaperengine.io` 首页 + `help.wallpaperengine.io`（**仅 Windows 功能参考**）
- `Paradox07127/macos-wallpaperengine`（Loomscreen）README 自述「An independent Metal implementation — **not affiliated with Wallpaper Engine**」（**未独立核实官方路线图**）
- macOS 版本适配的社区经验（Apple 文档 + macOS 惯例），**未运行渲染验证**

### Tertiary (LOW confidence — 需验证)
- FFmpeg libx264 / libsvtav1 的 App 体积实测增量 —— **未找到公开资料**
- FFmpegKitNext 从源码构建耗时 —— **未找到公开资料**
- `wallpaper-engine-kde` 是否存在及是否与 macOS 相关 —— 按命名推断（**未联网核实**）
- 路线 D（Aerial manifest）的跨版本稳定性
- 刘海屏 `visibleFrame` 内缩值是否恒为 32pt —— 单次实测

### 联网工具状态
- **WebSearch / WebFetch 全程失败**：ARCHITECTURE 记录 6/6 返回 `API Error: 400`；PITFALLS 记录 cs-web-fetch 抓 Bing 超时。改用 `curl` 直连 **GitHub REST API + Apple 文档 JSON API** 完成全部检索，**均为一手来源**。

---

## 给 roadmapper 的三句话总结

1. **先跑 Phase 1 门禁再做别的。** 它是几小时的一次性验证 app，却决定整个架构是否成立。**没有任何理由不先做它。**
2. **开工前拍两个板：签名类型、ffmpeg 路线。** 两个都便宜，两个都「发现得晚就代价高昂」。
3. **Phase 3 与 Phase 4 可以并行**（本项目的唯一并行机会）；**Phase 6 转码是唯一需要额外深度研究的阶段**。

---
*Research synthesized: 2026-10-03*
*Sources: STACK.md (2026-10-02) · FEATURES.md (2026-10-02) · ARCHITECTURE.md (2026-10-02) · PITFALLS.md (2026-10-03)*
*Ready for roadmap: yes*
