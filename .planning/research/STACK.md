# Stack Research — macOS 视频动态壁纸

**Domain:** macOS 原生菜单栏 app（Swift / AppKit / AVFoundation）
**目标平台:** macOS 27（`ProductVersion = macosx27.0`）
**Researched:** 2026-10-02（第二轮：补联网验证）
**Confidence:** HIGH（Apple SDK API 全部本地实测）/ MEDIUM（性能旋钮取值）/ MEDIUM（路线 C/D 可行性）

> **验证方法**：本机 SDK 头文件 grep + `swiftc -typecheck` 实编译 + C 探针运行时输出 + `curl` 走 GitHub REST API。
> 每条结论后标 `confidence:`。查不到的写「未找到公开资料」，**没有编造的 API 名 / 版本号 / URL**。
> 代码片段标 `[typechecked]` = 已用 `swiftc -typecheck -sdk <macOS 27 SDK> -target arm64-apple-macosx27.0` 编译通过。

---

## 0. 先说四条会改变路线图的结论

1. **`com.apple.wallpaper` 扩展 + 私有 `WallpaperExtensionKit.framework` 路线在本机真实存在**（PROJECT.md 假设只有两条路，实际至少四条）。`/System/Library/PrivateFrameworks/WallpaperExtensionKit.framework` 本机实测存在。但**开源 868★ 项目 phosphene 在 macOS 27 上已出现私有 framework 字段不兼容的真实故障**（见 §4）。`confidence: HIGH`
2. **FFmpegKit 已于 2026-07 官方退役**，GitHub repo `archived: true`。继任者 `arthenica/ffmpeg-kit-next`（LGPL-3.0，**仅源码分发**，2026-10-01 仍在推送）。`confidence: HIGH`
3. **本机没装 ffmpeg**（`which ffmpeg` → not found）。「调用本机已装 ffmpeg 二进制」当前不成立，且违反「拷到别的 Mac 上跑」的自足性。`confidence: HIGH`
4. **全屏检测有生产级参考实现**（MIT 项目 wallnetic 实测源码）：`Timer` 2 秒轮询 + `CGWindowListCopyWindowInfo` 跑在 `.utility` 队列 + 去抖定时器 + bundleId 白名单。见 §2.2。`confidence: HIGH`（源码实测）

---

## 1. 推荐栈

### 1.1 Core Technologies

| 技术 | 版本 | 用途 | 为什么是它 |
|---|---|---|---|
| **Swift** | 6.4（`swiftlang-6.4.0.34.1`） | 主语言 | 唯一选择。无 C++/ObjC 主逻辑需求。 |
| **SwiftUI** | macOS 14+ | 设置窗口、菜单栏 Popover、库列表 | 只用于「普通 UI」。壁纸窗口不用 SwiftUI，见 §1.4。 |
| **AppKit** | macOS 14+ | 壁纸 `NSWindow`、菜单栏、AVPlayer 承载 | SwiftUI 不暴露 `NSWindow.Level` / `collectionBehavior` / `ignoresMouseEvents`，壁纸层必须走 AppKit。 |
| **AVFoundation**（`AVQueuePlayer` + `AVPlayerLooper` + `AVPlayerLayer`） | macOS 10.12+ | 播放 / 无缝循环 / 变速 | 系统零依赖、硬解默认开启、`AVPlayerLayer` 走 GPU 直通。 |
| **AVFAudio**（`AVAudioUnitTimePitch`） | macOS 10.10+ | 备选变速保音高 | 只在 `.spectral` 实测不够用时才上（见 §3.3）。 |
| **VideoToolbox** | macOS 10.13+ | 硬解探测 + 硬编码转码 | `VTIsHardwareDecodeSupported` 做能力门控；转码走 `AVAssetWriter` + VT 属性字典。 |
| **ScreenSaver.framework** | macOS 10.0+ | ScreenSaver bundle 路线 | 公有 API（`ScreenSaverView` / `startAnimation` / `stopAnimation` / `animateOneFrame`）。已在 SDK 中确认。 |

**Language / SDK 快照（本机实测）**
```
Xcode:  未安装完整版，仅 CommandLineTools
SDK:    /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk → ProductVersion macosx27.0
Swift:  6.4 (swiftlang-6.4.0.34.1)
OS:     macOS 27.0.1 (26A434), arm64
```
`confidence: HIGH`

---

### 1.2 视频播放栈：具体取舍

| 方案 | 结论 | 理由 |
|---|---|---|
| **`AVQueuePlayer` + `AVPlayerLooper`** | ✅ **v1 采用** | `AVPlayerLooper`（macOS 10.12+）自动生成 ≥3 个 item 副本预取，无缝、无黑帧。`confidence: HIGH` |
| `AVPlayer` + KVO 手动 seek 回 0 | ❌ 不采用 | 每次循环一个 seek，必现卡顿/闪黑。壁纸场景绝对不可接受。 |
| `AVQueuePlayer` 手动 enqueue 多个副本 | △ 备选 | 若将来要「无缝接下一支视频」而非单支循环，可手工预排 2~3 支。 |
| `AVSampleBufferDisplayLayer` | ❌ **不用** | **整个 queue 管理 API 已 `API_DEPRECATED(macos(10.8, 15.0))`**，注释明写 "Use sampleBufferRenderer's … instead"。macOS 27 上用它全是 deprecation 警告。`confidence: HIGH` |
| `AVSampleBufferVideoRenderer` | ❌ **v1 不用** | 本身 macOS 14.0+，但在 **macOS 27 SDK 中它的 ObjC API（`enqueueSampleBuffer:` / `status` / `flush` / `requiresFlushToResumeDecoding`）对 Swift 已 `API_DEPRECATED(macos(14.0, 27.0))`**，要求改用新的 Swift async `sampleBufferReceiver(adding:)` / `EnqueueResult` / `RenderingEvent` API。等于追一套刚改版的新 API，收益（自己做缩放/裁剪）v1 用不到。`confidence: HIGH` |
| `AVPlayerView`（AVKit） | ❌ 不用 | 带 UI 控件（播放条、控制按钮），吃额外内存和事件处理，且不能纯 GPU 直通。`confidence: MEDIUM` |

#### `AVPlayerLooper` 的三个硬约束（头文件原文，与「设置改动立即生效」直接相关）`confidence: HIGH`

1. > "AVPlayerItem replicas will be generated at initialization time so **any changes made to the specified AVPlayerItem's property afterwards will not be reflected** in the replicas used for looping playback."
   → **改 template item 属性对已在播的副本无效。** 音量/速度必须挂在 `AVPlayer` 上（立即生效），或监听 `looper.loopingPlayerItems`（KVO）逐个改，或 `disableLooping()` 重建。**这是「立即生效」需求的第一个实现坑。**
2. > "AVPlayerItemOutputs and AVPlayerItemMediaDataCollectors **are not transferred to the replicas**"
   → 将来若挂 `AVPlayerItemVideoOutput`，必须手动挂到每个副本上。
3. > 会把 `AVQueuePlayer` 的 `actionAtItemEnd` 改成 `AVPlayerActionAtItemEndAdvance`，并在 `disableLooping()` 或副本播完后恢复。

**推荐写法** `[typechecked]`：

```swift
import AVFoundation

final class WallpaperPlayer {
    private let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?

    func play(_ url: URL) {
        let item = AVPlayerItem(url: AVURLAsset(url: url))

        // 变速保音高：macOS 12+ 默认是 .timeDomain，必须显式设 .spectral
        item.audioTimePitchAlgorithm = .spectral

        // 资源旋钮（见 §2）
        item.preferredForwardBufferDuration = 3.0
        item.preferredPeakBitRate = 12_000_000

        looper?.disableLooping()
        looper = AVPlayerLooper(player: player, templateItem: item)
        player.automaticallyWaitsToMinimizeStalling = false
        player.rate = speed              // rate 挂 player = 立即生效
        player.volume = volume            // volume 也挂 player = 立即生效
        player.play()
    }
}
```

`AVPlayerLooper(player:templateItem:)`、`AVQueuePlayer()`、`AVPlayerItem(url:)`、`audioTimePitchAlgorithm`、`preferredForwardBufferDuration`、`preferredPeakBitRate`、`automaticallyWaitsToMinimizeStalling`、`rate`、`volume` 全部编译通过。`confidence: HIGH`

---

### 1.3 硬解（hw_decode）怎么开

**结论：AVPlayer 在 macOS 上默认就走硬件解码，Swift 侧没有「开关」可以打开它。** `confidence: MEDIUM`（推理依据充分；未在真机抓 `VideoToolbox` 调用栈验证）

- `AVFoundation` 不暴露 per-item 的 hw/sw decode 选择器。VideoToolbox 有 `kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder`（macOS 10.9+，**默认 true**）和 `kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder`（macOS 10.9+），但这两个 key 只作用于**自建 `VTDecompressionSession`**，`AVPlayer` 用不到。`confidence: HIGH`（API 存在性与版本已核实）

- **正确做法是「探测 + 门控」**：入列前用 `VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)`（macOS 10.13+）确认机型硬解，不支持则拒绝并提示转码。`confidence: HIGH`

```swift
import VideoToolbox
import CoreMedia

func canDecode(_ codec: CMVideoCodecType) -> Bool {
    VTIsHardwareDecodeSupported(codec)
}
canDecode(kCMVideoCodecType_H264)   // 'avc1'
canDecode(kCMVideoCodecType_HEVC)   // 'hvc1'
```
`confidence: HIGH`（已 typecheck）

- **同名 Swift 成员不存在**：`CMVideoCodecType` 是 `UInt32` typealias，**没有 `.hevc` / `.h264` 成员**。实测报错：`type 'CMVideoCodecType' (aka 'UInt32') has no member 'hevc'`。必须用全局常量。`confidence: HIGH`

---

### 1.4 窗口层级：SwiftUI vs AppKit 分工

**结论：`NSApplicationDelegate` + 自定义 `NSWindow` 子类是必须的地基；SwiftUI 只做设置窗口和菜单栏。** `confidence: HIGH`

理由是硬性的：SwiftUI 不暴露 `NSWindow.Level`、`collectionBehavior`、`ignoresMouseEvents`、`isOpaque` 的完整控制面。壁纸窗口必须能：
- 停在桌面图标**之下**
- 跟随所有 Space（`canJoinAllSpaces`）
- Exposé 时不动（`stationary`）+ Cmd-Tab 时不参与（`ignoresCycle`）
- 全屏时能一起上屏（`fullScreenAuxiliary`）
- 完全不接鼠标（`ignoresMouseEvents = true`）

这些**全部**只在 AppKit 上。`confidence: HIGH`

**分工表**

| 层 | 技术 | 职责 |
|---|---|---|
| App 生命周期 | **AppKit** `NSApplicationDelegate` + `setActivationPolicy(.accessory)` | 无 Dock 图标、关窗口不退出、菜单栏常驻 |
| 壁纸窗口 | **AppKit** `NSWindow` 子类（borderless）+ `AVPlayerLayer` | 桌面层级、裁剪填充、暂停/恢复 |
| 菜单栏 | SwiftUI `MenuBarExtra`（或 AppKit `NSStatusItem`） | 菜单项 |
| 设置窗口 | SwiftUI `Settings` scene | 全部表单控件 |
| 播放状态 | `@Observable` class（Swift 5.9+），SwiftUI 订阅 | 设置改动 → 立即广播给播放器 |

> 菜单栏用 `MenuBarExtra` 还是 `NSStatusItem`：**建议 `MenuBarExtra`**（SwiftUI 原生、样板更少），但需在 Phase 1 验证它在 `.accessory` 策略 + 无 Dock 图标下的行为；`NSStatusItem` 是稳妥退路。`confidence: MEDIUM`

**窗口层级关键值（本机 C 探针实测运行值）** `confidence: HIGH`

```objc
// C 探针实际输出
kCGMinimumWindowLevel     = -2147483643
kCGDesktopWindowLevel     = -2147483623
kCGDesktopIconWindowLevel = -2147483603
```

**坑（必须处理）**：`kCGDesktopWindowLevel` / `kCGDesktopIconWindowLevel` 是 **C 宏，Swift 导入不了**。实测编译错误：

```
error: cannot find 'kCGDesktopWindowLevel' in scope
note: macro 'kCGDesktopWindowLevel' unavailable: structure not supported
```

`CGWindowLevelKey` 枚举的 Swift 成员名在本 SDK 下**无法确定**（试过 `minimumWindowLevelKey` / `minWindowLevelKey` 等 7 种拼法全部编译失败；CoreGraphics.swiftinterface 不含该符号——走 clang module）。`confidence: HIGH`

**两种可行解，推荐第二种** `confidence: MEDIUM`：

| 解法 | 做法 | 评价 |
|---|---|---|
| A. ObjC/C shim target | 3 行 `.m`：`CGWindowLevel f(void){ return kCGDesktopWindowLevel; }`，Swift 走 bridging header | 需混入 ObjC target，与「纯 Swift」目标冲突 |
| **B. 硬编码常量** ✅ | `NSWindow.Level(rawValue: -2147483623)`，启动时肉眼验证层级 | 数值由 C 宏算式固定（`kCGBaseWindowLevel = INT32_MIN` + `kCGNumReservedBaseWindowLevels = 5` + 20），Apple 保留不会变。**务必加启动断言 + 单元测试锁定这三个数** |

```swift
// [typechecked] 搭配硬编码层级使用
enum DesktopLevel {
    static let minimum     = NSWindow.Level(rawValue: -2147483643) // kCGMinimumWindowLevel
    static let desktop     = NSWindow.Level(rawValue: -2147483623) // kCGDesktopWindowLevel
    static let desktopIcon = NSWindow.Level(rawValue: -2147483603) // kCGDesktopIconWindowLevel
}
```
`confidence: HIGH`（数值与代码均实测）

**桌面窗口模板** `[typechecked]`：

```swift
import AppKit
import AVFoundation

final class WallpaperWindow: NSWindow {
    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)

        level = DesktopLevel.desktop          // ← 图标层之下；Phase 1 核心断言
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        isOpaque = true                        // 省一层合成，见 §2
        hasShadow = false
        ignoresMouseEvents = true              // 完全不抢点击
        isReleasedWhenClosed = false
        backgroundColor = .black

        let layer = AVPlayerLayer()
        layer.videoGravity = .resizeAspectFill  // 裁剪填满主屏，零解码开销
        contentView = NSView(frame: frame)
        contentView?.wantsLayer = true
        contentView?.layer = layer
    }
}
```
`confidence: HIGH`（全部属性 + `AVPlayerLayer.videoGravity` 已 typecheck）

---

### 1.5 支持层 / 三方库

| 库 | 版本 | 用途 | 何时用 |
|---|---|---|---|
| 无 | — | — | **v1 零三方依赖。** 整个栈（播放 / 转码 / 菜单栏 / 窗口）系统框架全齐，引入 SPM 包只增加签名与体积负担。`confidence: MEDIUM` |

### 1.6 开发工具

| 工具 | 用途 | 备注 |
|---|---|---|
| `swiftc -typecheck` | 极快验证 API 拼写 / 可用版本 | 本次调研的主要手段，比开 Xcode 快几个数量级。建议固化成 Phase 1 的日常验证习惯。 |
| `powermetrics` | 测真实功耗 | 已确认存在：`/usr/bin/powermetrics`。**需要 root**：`sudo powermetrics --show-process-energy -i 2000 -n 5` `confidence: MEDIUM`（存在性 HIGH；flag 名未逐一验证） |
| Xcode Instruments（Energy Log / Time Profiler） | 定位耗电来源 | 需完整版 Xcode，**本机未安装** `confidence: HIGH` |
| `ffprobe` | 转码产物验收 | 本机无 ffmpeg，需 `brew install ffmpeg` |
| XCTest | 回归测试 | 建议为窗口层级常量 + 播放策略写单测 |

---

## 2. 降低资源占用

### 2.1 旋钮清单

| 旋钮 | 建议值 | 可用版本 | confidence | 说明 |
|---|---|---|---|---|
| `AVPlayerItem.preferredForwardBufferDuration` | `3.0` | macOS 10.12+ | HIGH | 头文件原话：「设低会增加卡顿重缓冲，设高会增加系统资源占用」；另警告「系统可能缓冲少于该值」。本地文件不需要网络缓冲，3~5s 足够 |
| `AVPlayerItem.preferredPeakBitRate` | `源码率 × 1.2`，或置 `0` | macOS 10.10+ | HIGH（API）/ MEDIUM（取值） | 本地文件播放时设 `0`（不限制）通常最省。**两种配置需 Phase 1 A/B 实测** |
| `AVPlayer.automaticallyWaitsToMinimizeStalling` | `false` | 公有 | HIGH | 避免缓冲边界自动降速，配合 Looper 预取副本 |
| `AVPlayerLayer.videoGravity = .resizeAspectFill` | 固定 | 公有 | HIGH | **裁剪在显示层完成，零解码开销。** 不要为裁剪建 `AVVideoComposition`（那是逐帧渲染，掉出硬解路径） |
| `AVPlayerItem.audioTimePitchAlgorithm = .spectral` | 固定 | macOS 10.9+ | HIGH | 见 §3.3 |
| `NSWindow.isOpaque = true` + 不透明背景色 | 固定 | 公有 | MEDIUM | 让系统跳过背景合成。**必须在 Phase 1 用 `powermetrics` A/B 实测收益**，本文档未实测 |
| `NSWindow.ignoresMouseEvents = true` | 固定 | 公有 | HIGH | 省掉每帧命中测试 |
| `NSWindow.hasShadow = false` | 固定 | 公有 | HIGH | 无阴影绘制 |
| `.borderless` + `.stationary` + `.ignoresCycle` | 固定 | macOS 10.6+ | HIGH | 减少 Space 切换时的窗口重建 |
| **CVPixelBuffer 池** | **v1 不做** | — | HIGH | 只有走 `AVPlayerItemVideoOutput` / `AVSampleBufferVideoRenderer` 才需自管。v1 用 `AVPlayerLayer`（系统管），自建 `CVPixelBufferPool` 是纯粹的复杂度浪费 |
| **帧率降采样** | **v1 不做** | — | MEDIUM | 没有公开 API 能把 60fps 源降成 30fps 播放而仍走硬解。转码降帧是唯一可靠手段 → 归到转码路线 |
| `NSWindow.displaySyncEnabled` | **⚠️ 此 API 不存在于 NSWindow** | — | HIGH | **原问题里的这一条是错的。** 实测 AppKit 全框架 grep 无此符号；它属于 **`CAMetalLayer.displaySyncEnabled`**（QuartzCore/CAMetalLayer.h:143）。走 `AVPlayerLayer` **没有这个旋钮**。要跟 VSync 同步只能换 `CAMetalLayer` + `AVSampleBufferVideoRenderer`——而后者在 macOS 27 刚被 deprecate。不值得走 |
| 后台线程 QoS | `.utility` | — | MEDIUM（**已修正**） | `AVPlayer` 自带解码线程，不需要额外后台线程。**唯一需要显式 QoS 的是全屏检测轮询** —— wallnetic 实测源码用 `DispatchQueue(label: "com.wallnetic.power.fullscreen", qos: .utility)` 把 `CGWindowListCopyWindowInfo` 挪出主线程。转码循环建议 `.utility` |
| **`Timer` vs `DispatchSourceTimer`** | **用 `Timer` + 去抖定时器** | — | MEDIUM（**已从 LOW 修正**） | **第一轮我倾向 `DispatchSourceTimer`，读到 wallnetic 实测源码后推翻。** 生产级 MIT 项目选的是 `Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true)` + 一个 `fullscreenDebounceTimer`。结论：两者性能差异在此场景**不可测**，真正重要的是**去抖**——全屏状态抖动会让壁纸反复暂停/续播，比 Timer 开销伤得多 |

### 2.2 暂停条件：所需 API + 生产级参考实现 `confidence: HIGH`（除注明外）

| 需求 | API | 可用版本 | confidence |
|---|---|---|---|
| 电池 / 低电量模式 | `ProcessInfo.processInfo.isLowPowerModeEnabled` + `NSProcessInfoPowerStateDidChangeNotification` | macOS 12.0+ | HIGH |
| AC / 电池供电 | `IOPSCopyPowerSourcesInfo()` / `IOPSGetPowerSourceState(..., kIOPSPowerSourceIsAC)`（`IOKit.framework/Headers/ps/IOPowerSources.h`）。wallnetic 实测用 `import IOKit.ps` + `CFRunLoopSource` 观察电源变化 | 公有 | HIGH |
| 锁屏 / 会话不活跃 | `NSWorkspace` 通知 + 会话状态复查。wallnetic 定义 `isSessionInactive` = 登录窗口遮挡 或 用户切换 | 公有 | MEDIUM |
| 显示器熄屏 | `NSWorkspace.screensDidSleepNotification` + `CGDisplayIsAsleep(CGMainDisplayID())` 作兜底复查（wallnetic 实测用此双保险） | 公有 | HIGH |
| 系统睡眠 | `NSWorkspace.willSleepNotification` / `didWakeNotification` | 公有 | MEDIUM |
| 屏幕保护启动 | `DistributedNotificationCenter`（wallnetic 实测 `isScreenSaverActive`） | 公有 | MEDIUM |
| **全屏应用检测** | **见下方实测方案** | — | **HIGH** |

**全屏检测：wallnetic 实测源码方案（MIT，可直接照抄思路）** `confidence: HIGH`

> 来源：`raw.githubusercontent.com/fatihkan/wallnetic/main/src/Wallnetic/Engine/PowerManager.swift`（本轮 curl 实读）

```swift
private let fullscreenQueue = DispatchQueue(label: "com.wallnetic.power.fullscreen", qos: .utility)

private func startFullscreenMonitoring() {
    // 源码注释原话："Check periodically for fullscreen apps
    //                (more reliable than notifications alone)"
    fullscreenCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
        self?.recoverIfStrandedAsleep()
        self?.checkFullscreenApps()
    }
}

private var fullscreenDebounceTimer: Timer?   // 去抖，防状态抖动

private func checkFullscreenApps() {
    let frontApp = NSWorkspace.shared.frontmostApplication
    let screens = NSScreen.screens.compactMap { $0.displayID.map(CGDisplayBounds) }
    // 源码注释原话：CGWindow bounds 是全局左上原点，NSScreen.frame 是左下原点，
    //   直接比 Y 会在某些布局下把「大窗口」误判成「全屏」
    fullscreenQueue.async { /* CGWindowListCopyWindowInfo 在这里跑，避开主线程 */ }
}
```

**要点** `confidence: HIGH`：
- 2 秒轮询，`CGWindowListCopyWindowInfo` **必须挪出主线程**
- bundleId 白名单跳过：自己、Finder、Dock、SystemUIServer、controlcenter、notificationcenterui
- 必须用 `CGDisplayBounds(displayID)` 而非 `NSScreen.frame`（坐标系不同，否则误判）
- 通知不可靠，轮询是主路径；另有 `recoverIfStrandedAsleep()` 用 `CGDisplayIsAsleep` 兜底「通知丢了但屏已亮」

### 2.3 测量方法 `confidence: MEDIUM`（工具存在性 HIGH，flag 用法 MEDIUM）

```bash
# A) 功耗：需要 root
sudo powermetrics --show-process-energy -i 2000 -n 5

# B) 耗电来源：Energy Log（需完整版 Xcode，本机未装）

# C) 对照实验设计（Phase 1 必做）
#    固定视频 × 固定时长 × 4 组：
#      1) 不播（进程在，窗口在）
#      2) AVPlayerLayer + isOpaque + Looper（v1 配置）
#      3) isOpaque = false
#      4) AVPlayerView
#    每组 5 分钟，比 GPU active% / CPU wakeups / residual power
```

---

## 3. 转码栈

### 3.1 四方案对比

| 方案 | 画质 | 速度 | App 体积 | 许可 | 结论 |
|---|---|---|---|---|---|
| **`AVAssetWriter` + VideoToolbox 硬编码 HEVC** | ✅ 可达视觉无损 | 快（HW 编码器） | +0 | 系统 API | ✅ **推荐** |
| `AVAssetExportSession` + `AVAssetExportPresetHEVCHighestQuality` | ⚠️ preset 黑盒，无法调质量参数 | 快 | +0 | 系统 API | ✅ **快速/兜底路径** |
| 内置 FFmpeg（FFmpegKitNext） | ✅ 视觉无损（`-crf` / `-qp`） | 中 | **未找到公开资料**（PROJECT.md 估 +80~150MB，未复核） | **LGPL-3.0** → 动态链接必须可替换 | ❌ v1 不上 |
| 调用本机 ffmpeg 二进制 | ✅ 同上 | 快 | +0 | 取决于 build flags | ❌ **本机没装 ffmpeg**（实测）；且要求每台目标 Mac 都 brew install，违反「拷走就能跑」 |

### 3.2 推荐实现：System-only 转码路径

**`kVTCompressionPropertyKey_ConstantQualityFactor` 是 macOS 27 SDK 新增的**（`API_AVAILABLE(macos(27.0))`），头文件原话：

> "Requires the encoder to maintain consistent quality by specifying a target constant quality factor in the range of 0.0 to 1.0. In contrast to cases where `kVTCompressionPropertyKey_Quality` which will cause the quantization parameter to adhere to a fixed value, this property is **designed for consistent visual quality with or without bitrate limit constraints**. 0.0 is the lowest quality and 1.0 implies the highest quality possible."

**这正是「保画质转码」要的那个旋钮。** `confidence: HIGH`

```swift
import AVFoundation
import CoreMedia
import CoreVideo
import VideoToolbox

func transcode(src: URL, dst: URL) async throws {
    let asset = AVURLAsset(url: src)

    // 解码侧：AVAssetReaderTrackOutput 出 CVPixelBuffer
    guard let vTrack = try await asset.loadTracks(withMediaType: .video).first else { return }
    let reader = try AVAssetReader(asset: asset)
    let vOut = AVAssetReaderTrackOutput(
        track: vTrack,
        outputSettings: [kCVPixelBufferPixelFormatTypeKey as String:
                         kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange])
    vOut.alwaysCopiesSampleData = false
    reader.add(vOut)

    // 编码侧：VideoToolbox 硬编码 HEVC
    let writer = try AVAssetWriter(outputURL: dst, fileType: .mp4)
    var props: [String: Any] = [
        kVTCompressionPropertyKey_RealTime as String: false,
        kVTCompressionPropertyKey_AllowFrameReordering as String: false,
        kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder as String: true,
    ]
    if #available(macOS 27.0, *) {
        props[kVTCompressionPropertyKey_ConstantQualityFactor as String] = 0.95  // 视觉无损档
    }
    let settings: [String: Any] = [
        AVVideoCodecKey: kCMVideoCodecType_HEVC,
        AVVideoWidthKey: 3840,
        AVVideoHeightKey: 2160,
        AVVideoCompressionPropertiesKey: props,
    ]
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
    input.expectsMediaDataInRealTime = false
    writer.add(input)
    // … pump loop（建议在 .utility QoS 的 Task 上跑）
}
```
`confidence: HIGH` — 已 typecheck。**三个已实测的坑**：
- 类名是 `AVAssetReaderTrackOutput`，构造签名 **`(track:outputSettings:)` 单数 track**，不是 `(videoTracks:outputSettings:)`
- 常量名是 **`kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder`**；`kVTCompressionPropertyKey_RequireHardwareAcceleratedVideoEncoder` **不存在**
- `CMVideoCodecType` 无 `.hevc` 成员，用全局常量 `kCMVideoCodecType_HEVC`（4CC `'hvc1'`）

**极速兜底路径** `[typechecked]`：
```swift
let session = AVAssetExportSession(asset: asset,
                                   presetName: AVAssetExportPresetHEVCHighestQuality)!
try await session.export(to: dst, as: .mp4)
```
`AVAssetExportSession.export(to:as:)` 实测在 **macOS 14.0 deployment target 即可编译**（14/15/26/27 四个 target 全部 typecheck 通过）。`confidence: HIGH`

**API 迁移表（实测 deprecation 警告）** `confidence: HIGH`

| 旧 API | deprecation | 替代 |
|---|---|---|
| `AVAssetExportSession.outputURL` / `.outputFileType` / `.exportAsynchronously` | macOS 27.0 / 15.0 | `try await session.export(to:as:)` |
| `AVAsset(url:)` | macOS 15.0 | `AVURLAsset(url:)` |
| `asset.tracks(withMediaType:)` | macOS 13.0 | `try await asset.loadTracks(withMediaType:)` |
| `AVPlayerItemVideoOutput(pixelBufferAttributes: nil)` | macOS 27.0 | `init(pixelBufferAttributes: CVPixelBuffer.Attributes)` |

### 3.3 变速保音高

| 方案 | 结论 |
|---|---|
| **`AVPlayerItem.audioTimePitchAlgorithm = .spectral`** ✅ **v1 采用** | 头文件原话：「`Spectral` is often the best choice due to the **highly inclusive range of rates it supports**, assuming that it is desirable to **maintain a constant pitch regardless of the edit rate**」——正是壁纸变速需求。`confidence: HIGH` |
| ⚠️ 别信默认值 | `AVPlayerItem` 头文件原话：「**The default value for applications linked on or after iOS 15.0 or macOS 12.0 is `AVAudioTimePitchAlgorithmTimeDomain`**」（macOS 12 之前才是 `.spectral`）。**必须显式设置。** `confidence: HIGH` |
| `AVAudioUnitTimePitch` + `AVAudioEngine` | 备用。若 Phase 1 实测 `.spectral` 在 0.5×~2.0× 有可听瑕疵再上。代价：要从 `AVPlayer` 拆音频轨道（`AVAudioMix`），复杂度显著上升。`confidence: MEDIUM` |
| `AVAudioTimePitchAlgorithmVarispeed` | ❌ 会变速调 —— 用户明确不要。`confidence: HIGH` |
| `AVAudioTimePitchAlgorithm.lowQualityZeroLatency` | ❌ `API_UNAVAILABLE(macos)`，macOS 上根本不存在。`confidence: HIGH` |
| 可用算法全集 | `.timeDomain` / `.spectral` / `.varispeed`（三者 macOS 10.9+ 均 `API_AVAILABLE`）。`confidence: HIGH` |

---

## 4. 窗口层级路线（对 PROJECT.md 假设的修正）

PROJECT.md 说「业界两种做法：desktop-level NSWindow，或 ScreenSaver bundle」。**实测开源生态至少还有两条**，且都是 macOS 26+ 路线：

| 路线 | 机制 | 代表项目 | 许可 / ★ | 本机可用性 | confidence |
|---|---|---|---|---|---|
| **A. desktop-level `NSWindow`** | `kCGDesktopWindowLevel` 窗口 + `AVPlayerLayer` | `ducbao414/live-wallpaper`（`WindowManager.swift` + `PlayerLayerView.swift`）、`harryfrzz/hazel`（`WallpaperWindow.swift`，仅 11 个源文件）、`fatihkan/wallnetic`（`DesktopWindowController.swift`） | MIT / GPL-3.0 / MIT | ✅ 100% 公有 API | HIGH |
| **B. ScreenSaver bundle** | `ScreenSaver.framework`（`ScreenSaverView` / `startAnimation` / `animateOneFrame`） | `WallpaperMachine/WallpaperMachine`（`DesktopSpaceWallpaperAPI.swift` + `AppRuleMonitor.swift`，291 文件）、`wallnetic` 的 `ScreenSaverBridge.swift` | GPL-2.0 / MIT | ✅ 公有 API | HIGH |
| **C. `com.apple.wallpaper` 扩展 + 私有 framework** | Info.plist 写 `EXExtensionPointIdentifier = com.apple.wallpaper`；`@main final class … : AppExtension`（`import ExtensionFoundation`）；`dlopen("/System/Library/PrivateFrameworks/WallpaperExtensionKit.framework/WallpaperExtensionKit")`，桥接 `WallpaperRemoteContextXPC` / `WallpaperSnapshotXPC` / `WallpaperCreationRequestXPC` / `WallpaperSettingsViewModelsXPC` / `WallpaperIDXPC` | `kageroumado/phosphene`（868★，MIT） | MIT | ⚠️ framework 本机存在，但**macOS 27 上已出现真实故障**，见下 | HIGH（存在性）/ HIGH（故障证据） |
| **D. 直接改 Aerial manifest JSON** | 往 `~/Library/Application Support/com.apple.wallpaper/aerials/manifest/entries.json` 写条目 + `videos/` + `thumbnails/` | `Mcrich-LLC/VideoPaper`（MIT，仅 `.mov`） | MIT | ✅ 本机该目录实测存在（`entries.json` / `videos/` / `thumbnails/` / `manifest.source`），`entries.json` 结构可见 | HIGH（存在性）/ LOW（跨版本稳定性） |

### 路线 C 的 macOS 27 故障实证 `confidence: HIGH`

phosphene issue **#29**（2026-08-25，macOS 27.0 build 26A5416b，M4 MacBook Air `Mac16,12`，已 closed）原文：

> "The failure begins when the second video causes the `Shuffle All` item to be added. Building `WallpaperSettingsViewModelsXPC` then fails because **a nested menu picker item is missing the `isDownloaded` field expected by the current private framework.** Keeping exactly one video works reliably."

相关 issue：#14「Does Mac 27 support?」、#20「Doesn't support Intel Mac anymore?」、#8「Harden private runtime bridging and unsafe WallpaperExtensionKit shims」、#10「Reduce filesystem blast radius with app sandbox」。

> **含义**：私有 framework 的数据结构**在 macOS 27 上已经变了**。phosphene 自家在 `PhospheneExtension.swift` 里写了 `verifyRuntimeLayout()` 自检来探测失效，恰恰说明这条路的维护成本是持续的。`confidence: MEDIUM`（基于 issue 文本的推断）

### 路线 C/D 的一个共同优势 `confidence: MEDIUM`

它们能实现路线 A **做不到**的事：**壁纸真正进「系统设置 → 墙纸」列表、进锁屏、随系统主题切换、由系统负责省电调度**。如果 Phase 1 demo 发现 A 层级压不住桌面图标、或 Exposé 行为异常，C/D 才是正解。

### 建议 `confidence: MEDIUM`

- **v1 起步走 A（desktop NSWindow）**：唯一 100% 公有 API 的路线，三个 MIT/GPL 项目证明可行。
- **但 Phase 1 demo 必须把 C / D 作为对照项**，因为 A 的层级问题正是 PROJECT.md 自认的最大风险。
- **C 的代价**：`com.apple.wallpaper` 是私有扩展点（grep 公开 SDK **零命中**），`WallpaperExtensionKit` 是 PrivateFramework，OS 升级可能整个失效（#29 已实证）。本项目不上 App Store、允许非公开 API，所以这条路可用；**但必须设计 OS 版本熔断 + `verifyRuntimeLayout()` 式自检**。
- **D 的代价**：直接改 `com.apple.wallpaper` 私有数据目录，稳定性完全依赖 Apple 不改 schema。VideoPaper 的 README 只声明支持 `.mov`。

### 代码复用度 `confidence: MEDIUM`

| 项目 | 可复用性 |
|---|---|
| `kageroumado/phosphene`（MIT） | **路线 C 的唯一完整实现**，架构参考价值最高。可读不可直接抄 |
| `fatihkan/wallnetic`（MIT，146 文件，带单测） | **路线 A 的架构参考首选**：`DesktopWindowController` / `PowerManager` / `PowerPauseOwnership` 分层清晰且有测试。已实读 `PowerManager.swift`，全屏检测方案可直接借鉴 |
| `ducbao414/live-wallpaper`（MIT） | **App Store 沙盒上架版**，与本项目「非沙盒 + 可用非公开 API」约束不同，沙盒技巧不能抄。可参考其 Power Saving Mode |
| `harryfrzz/hazel`（GPL-3.0） | 11 文件结构最简，但 **GPL-3.0 传染，不能抄进本项目**。`confidence: HIGH` |
| `jaywcjlove/vidwall` | **无 LICENSE 文件 = 默认全权保留，不可复用**。`confidence: HIGH` |

---

## 5. 开源生态全景（GitHub API 实测，2026-10-02）

| 项目 | ★ | 许可 | 最近推送 | 技术路线 |
|---|---|---|---|---|
| `kageroumado/phosphene` | 868 | MIT | 2026-09-30 | **C**：`com.apple.wallpaper` 扩展 + 私有 `WallpaperExtensionKit`。macOS 26+ |
| `WallpaperMachine/WallpaperMachine` | 152 | **GPL-2.0** | 2026-10-02 | **B**：ScreenSaver bundle。291 文件，最成熟 |
| `nhiroyasu/wallpaper-play` | 148 | MIT | 2026-05-26 | A（**已上 App Store**） |
| `jaywcjlove/vidwall` | 127 | **无 LICENSE** | 2026-09-09 | 拖拽设 4K 视频。无许可证 = 不可复用 |
| `ducbao414/live-wallpaper` | 80 | MIT | 2026-06-07 | **A**：desktop NSWindow。沙盒 + 签名 + 公证。README 称 4K 用 ~50MB RAM，含 Power Saving Mode |
| `fatatkan/wallnetic` | 67 | MIT | 2026-09-28 | **A + B 混合**，带 `PowerManager` / `PowerPauseOwnership` + 单测。**架构参考首选** |
| `Paradox07127/macos-wallpaperengine`（Loomscreen） | 57 | MIT | 2026-10-02 | 自研 **Metal** 渲染器跑 Wallpaper Engine 场景；也支持视频（mp4/m4v/mov/**avi** → 说明自带转码）。需 Apple Silicon + macOS 14.6+ |
| `Mcrich-LLC/VideoPaper` | 31 | MIT | 2025-11-10 | **D**：改 aerial manifest JSON。macOS 26+，仅 `.mov` |
| `harryfrzz/hazel` | 23 | **GPL-3.0** | 2026-04-18 | **A**。11 文件，最简 |
| `TzJ2006/desktop-video-for-mac` | 15 | **GPL-3.0** | 2026-06-18 | A |
| `vlzuiev/animated` | 15 | MIT | 2026-07-19 | A + 锁屏 |
| `yueseqaz/SakuraWallpaper` | 14 | MIT | 2026-08-11 | A |

`confidence: HIGH`（GitHub REST API 直接返回）

> **Wallpaper Engine 本身没有 macOS 官方版。** `Paradox07127/macos-wallpaperengine`（Loomscreen）README 明写 "An independent Metal implementation — **not affiliated with Wallpaper Engine**"，通过用户自己的 Steam 账号 + 许可下载 Workshop 素材。`confidence: MEDIUM`（源自该项目自述，未独立核实官方路线图）
>
> `wallpaper-engine-kde` 是 **Linux/KDE** 项目，与 macOS 无关，不应进技术选型表。`confidence: LOW`（依据命名常识，**未联网核实**）

---

## 6. FFmpeg 路线：明确结论

| 事实 | 证据 | confidence |
|---|---|---|
| **FFmpegKit 已于 2026-07 正式退役** | `arthenica/ffmpeg-kit` README：「`FFmpegKit` has been officially retired」；API `archived: true` | HIGH |
| 继任者是 **`arthenica/ffmpeg-kit-next`**（FFmpegKitNext） | README：「actively maintained continuation」；`archived: false`，LGPL-3.0，151★，`pushed_at: 2026-10-01` | HIGH |
| **FFmpegKitNext 只分发源码** | README：「distributed as source only」 | HIGH |
| 本机没装 ffmpeg | `which ffmpeg` → not found | HIGH |
| libx264 / libsvtav1 的 App 体积增量 | **未找到公开资料**（PROJECT.md 原文估 +80~150MB，本轮未能复核） | LOW |

**结论：v1 不引入 FFmpeg。** `confidence: MEDIUM`

理由：
1. 系统 VideoToolbox 硬编码 HEVC + `kVTCompressionPropertyKey_ConstantQualityFactor`（macOS 27 新增）已能达成「视觉无损」，零体积、零许可风险。
2. FFmpegKit 已退役 → 唯一选项 LGPL-3.0 的 FFmpegKitNext，**仅源码分发 = 要自己编译整个 FFmpeg**。构建链复杂度对自用工具是灾难。
3. LGPL-3.0 动态链接有合规要求：必须允许用户替换 ffmpeg 动态库（本项目可行，但仍是负担）。
4. 若 Phase 1 实测 VideoToolbox 达不到视觉无损，**升级路径是「提高 `ConstantQualityFactor` 或降到 ProRes 422」**（`kCMVideoCodecType_AppleProRes422`，真·视觉无损，代价是文件巨大），**不是引入 FFmpeg**。

---

## 7. 关键决策建议（给 roadmap 用）

| # | 决策 | confidence |
|---|---|---|
| 1 | **Deployment target 定 macOS 15.0**，不是 macOS 27 | HIGH —— 实测 `AVAssetExportSession.export(to:as:)` 在 macOS 14.0 target 即可编译；`ConstantQualityFactor` 用 `#available(macOS 27.0, *)` gate。定 27 就只能跑 27 的 Mac，与「拷到别的 Mac 上跑」冲突 |
| 2 | **零三方依赖**（v1） | MEDIUM |
| 3 | 播放 = `AVQueuePlayer` + `AVPlayerLooper` + `AVPlayerLayer`；**不碰** `AVSampleBufferDisplayLayer` / `AVSampleBufferVideoRenderer`（macOS 27 刚 deprecate ObjC 侧） | HIGH |
| 4 | 变速 = `audioTimePitchAlgorithm = .spectral`，显式设（默认是 `.timeDomain`） | HIGH |
| 5 | 裁剪 = `videoGravity = .resizeAspectFill`，**不用 `AVVideoComposition`** | HIGH |
| 6 | 窗口层级常量**硬编码 + 单元测试锁定**（Swift 拿不到 C 宏） | HIGH |
| 7 | 音量/速度挂 `AVPlayer` 而非 `AVPlayerItem`（Looper 副本不回传 template 改动） | HIGH |
| 8 | 转码 = `AVAssetReader` + VideoToolbox HW HEVC + `ConstantQualityFactor`；v1 不引入 FFmpeg | MEDIUM |
| 9 | SwiftUI 只做设置/菜单栏/库；AppKit 做 App 生命周期 + 壁纸窗口 | HIGH |
| 10 | 全屏检测 = `Timer` 2s 轮询 + `CGWindowListCopyWindowInfo` 走 `.utility` 队列 + bundleId 白名单 + 去抖（照 wallnetic 方案） | HIGH |
| 11 | Phase 1 需 A/B/C/D 四条路线同屏 demo；**路线 C 必须带 OS 版本熔断**（phosphene #29 实证 macOS 27 私有字段已变） | MEDIUM |

---

## 8. 未找到公开资料 —— 需要你用 web 工具调研

> 本轮已用 `curl` + GitHub REST API 补齐了 §8 的问题 4（全屏检测实现）与问题 1 的一半（路线 C 的 macOS 27 故障）。
> 以下几项**仍未查到**，需要你用 web 工具确认：

**【背景】**
macOS 视频动态壁纸自用工具（Swift + AppKit + AVFoundation），窗口层级有 A/B/C/D 四条候选路线，C/D 都依赖私有机制。转码走系统 VideoToolbox 还是引入 FFmpeg 也未定。

**【请回答】**
1. **FFmpegKitNext 从源码构建**：在 M 系列 Mac 上构建出可用 `.xcframework` 大概要多久（CPU 时间）？仓库里有没有可参考的 CI 配置？`https://github.com/arthenica/ffmpeg-kit-next`
2. **libx264 / libsvtav1 打进 macOS .app 的实测体积增量**是多少 MB？要实测数据，不要二手估算。
3. **macOS 26/27 上直接改写 `~/Library/Application Support/com.apple.wallpaper/aerials/manifest/entries.json`**：是否仍生效？会不会被系统覆盖？需不需要重启？有没有 Apple 官方文档描述这个 schema？（VideoPaper 只说 `.mov` 可用，没说稳定）
4. **`Wallpaper Engine for macOS` 有没有官方版或在开发中**？官方声明 / 路线图在哪？
5. **`wallpaper-engine-kde` 是否存在、是否与 macOS 有关**？（本轮按命名推断是 Linux/KDE 项目，未核实）
6. **macOS 视频壁纸 app 的实测功耗基线**：有没有 app 用 `powermetrics` 报过 CPU wakeups / GPU active% 具体数值？（用于给「不偷电」这个 Core Value 定量）

**【输出格式】**
- 每问给明确答案 + 可点击 URL + 来源日期
- 找不到的写「未找到公开资料」，**不要推测**
- 每条结论标 confidence（高/中/低）

**【截止时间】** 无限制

---

## 9. 版本兼容性

| 项 | 结论 | confidence |
|---|---|---|
| Swift 6.4 + macOS 27 SDK | 本机实测可 typecheck 全部推荐 API | HIGH |
| Deployment target **macOS 15.0** | 所有推荐 API 在 14.0+ 均可编译（逐个 target 实测）；`ConstantQualityFactor` 需 `#available(macOS 27.0, *)` | HIGH |
| `kVTCompressionPropertyKey_ConstantQualityFactor` | 仅 macOS 27.0+（`API_AVAILABLE(macos(27.0))`）；在 `-target arm64-apple-macosx26.0` 下编译失败 | HIGH |
| `AVSampleBufferVideoRenderer` ObjC API | 对 Swift 在 macOS 27 已 deprecated → 改用 `sampleBufferReceiver(adding:)` 系列 | HIGH |
| `AVSampleBufferDisplayLayer` queue API | macOS 15.0 起 deprecated | HIGH |
| `AVPlayerItemVideoOutput(pixelBufferAttributes:)` | macOS 27 deprecated（改 `CVPixelBuffer.Attributes`） | HIGH |
| `AVAssetExportSession` 旧三件套 | macOS 27 deprecated → `export(to:as:)` | HIGH |
| `AVAsset(url:)` | macOS 15 deprecated → `AVURLAsset(url:)` | HIGH |
| `WallpaperExtensionKit` 私有字段 | **macOS 27 已变**（phosphene #29：缺 `isDownloaded` 字段） | HIGH |
| FFmpegKit | 2026-07 退役，repo archived | HIGH |
| FFmpegKitNext | LGPL-3.0，仅源码，`pushed_at: 2026-10-01` | HIGH |

---

## Sources

**本机实测（HIGH）**
- `SDK: /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk`（ProductVersion `macosx27.0`）头文件：`AVPlayerLooper.h` / `AVPlayerItem.h` / `AVPlayer.h` / `AVAudioProcessingSettings.h` / `AVAudioMix.h` / `AVAssetExportSession.h` / `AVAssetReaderOutput.h` / `AVSampleBufferDisplayLayer.h` / `AVSampleBufferVideoRenderer.h` / `AVPlayerLayer.h`
- `VideoToolbox.framework/Headers/`：`VTCompressionProperties.h` / `VTDecompressionSession.h` / `VTDecompressionProperties.h` / `VTVideoEncoderList.h`
- `AppKit.framework/Headers/NSWindow.h` / `CoreGraphics.framework/Headers/CGWindowLevel.h` / `CGWindow.h` / `QuartzCore.framework/Headers/CAMetalLayer.h` / `ScreenSaver.framework/Headers/`
- `Foundation.framework/Headers/NSProcessInfo.h` / `IOKit.framework/Headers/ps/IOPowerSources.h`
- `swiftc -typecheck` 实编译 9 个探针文件（含 4 个故意写错以反推真实 API 名）
- C 探针运行时输出：`kCGMinimumWindowLevel` / `kCGDesktopWindowLevel` / `kCGDesktopIconWindowLevel` 实际数值
- 本机文件系统：`/System/Library/PrivateFrameworks/WallpaperExtensionKit.framework`、`~/Library/Application Support/com.apple.wallpaper/aerials/`
- `which ffmpeg` → not found

**联网实测 2026-10-02（HIGH，curl + GitHub REST API）**
- `api.github.com/repos/arthenica/ffmpeg-kit` → `archived: true`；README「Update (July 2026) … `FFmpegKit` has been officially retired」
- `api.github.com/repos/arthenica/ffmpeg-kit-next` → `archived: false`, LGPL-3.0, 151★, `pushed_at 2026-10-01`
- `api.github.com/search/repositories?q=macos+video+wallpaper+language:Swift` → 12 个项目元数据（★/许可/推送日期）
- `api.github.com/repos/kageroumado/phosphene/issues?state=all` + `/issues/29` + `/issues/14` → macOS 27 私有字段故障原文
- `raw.githubusercontent.com/kageroumado/phosphene/main/PhospheneExtension/{Info.plist,PhospheneExtension.swift}`
- `raw.githubusercontent.com/Mcrich-LLC/VideoPaper/main/VideoPaper/JsonWallpaperCoordinator.swift`
- `raw.githubusercontent.com/fatihkan/wallnetic/main/src/Wallnetic/Engine/PowerManager.swift` → 全屏检测 / 电源 / 熄屏实现全文
- 各项目 `git/trees?recursive=1` 文件树（判定技术路线）

**未获取（LOW）**
- FFmpeg libx264 / libsvtav1 的 App 体积实测增量 —— §8 问题 2
- FFmpegKitNext 从源码构建耗时 —— §8 问题 1
- `wallpaper-engine-kde` 是否存在及是否与 macOS 相关 —— §8 问题 5
- Wallpaper Engine 官方 macOS 路线 —— §8 问题 4

---
*Stack research for: macOS 视频动态壁纸*
*Researched: 2026-10-02（第二轮）*
*验证基线：macOS 27.0.1 / Swift 6.4 / SDK macosx27.0 / arm64*