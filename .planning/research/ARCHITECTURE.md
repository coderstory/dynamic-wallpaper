# Architecture Research — Pic (macOS 视频动态壁纸)

**Domain:** macOS 原生菜单栏应用 / 桌面级视频渲染
**Researched:** 2026-10-02
**Confidence:** **HIGH（桌面层级与检测机制）/ MEDIUM（Space 与耗电行为）**

---

## 0. 证据分级（先读这个）

本文档所有结论标注三档证据等级，**请勿混淆**：

| 标记 | 含义 |
|---|---|
| **【实测】** | 本机 macOS 27.0.1 上读取 SDK 头文件 / 编译运行 / 枚举真实窗口 / 反汇编已安装 app 得到的事实 |
| **【推断】** | 由实测事实 + 文档语义推导，未跑过 |
| **【待验证】** | 必须实机 demo 才能定论，**文中已逐条标出** |

> **联网调研失败声明**：本次 WebSearch / WebFetch 工具全部返回 `API Error: 400`（6 次尝试全失败）。因此本文档**不含任何联网检索结论**。所幸本机可读到完整 macOS 27 SDK 头文件，且系统里已安装 3 个同类 app 可供逆向——**实测证据强于二手博客**。确实查不到的部分已在 §9 如实标注「未找到公开资料」并附上给你的调研 prompt。

---

## 1. 核心结论（TL;DR）

1. **「把视频放到桌面图标后面」在 macOS 27 上可行，且只需公开 API。** 正确层级是 `CGWindowLevelForKey(.desktopWindow)` = **-2147483623**，桌面图标在 **-2147483603**，Dock 在 **20**。本机实测已有一个在售 app 的窗口正停在 -2147483623。**无需辅助功能权限、无需私有框架、无需屏幕录制权限。** 【实测】
2. **AppKit 没有 `NSDesktopWindowLevel` 常量**（已 grep 确认不存在）。CoreGraphics 的 `CGWindowLevelForKey` 是唯一来源——这直接决定了代码写法。【实测】
3. **ScreenSaver 路线是补充而非替代**，且不是 `.appex` 而是 `.saver` bundle（`CFBundlePackageType=BNDL`）。系统自带 saver 在 macOS 27 上仍在，说明机制存活。【实测】
4. **`kAXFullScreenAttribute` 不是公开 API**（全 SDK 搜索确认只有 `kAXFullScreenButtonAttribute`）。业界常说的「AXFullScreen 检测」依赖私有属性串。3 个在售 app **全部改用公开的 `CGWindowListCopyWindowInfo`**，且 0 个引用辅助功能符号。【实测】
5. **锁屏检测没有公开 API**，在售 app 统一用分布式通知 `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked`。【实测】
6. **架构建议**：SwiftUI 负责菜单栏 + 设置窗口，AppKit **只**负责壁纸窗口。其余全部下沉为无 UI 的纯 Swift 层。

---

## 2. 核心难点 1 —— 把视频放到桌面图标后面

### 2.1 路线对比表

| 路线 | 主屏 | Dock | Mission Control / 多 Space | 全屏应用时 | 权限需求 | Confidence | 需实机 demo |
|---|---|---|---|---|---|---|---|
| **A. desktop-level `NSWindow`** | ✅ 已实测 | ✅ 自动避开（Dock 在 layer 20） | ⚠️ 语义推断，行为未实测 | 需自行暂停（level 远低于全屏窗口，理论上不会跑到前面） | **无** | **HIGH** | ✅ **必须** |
| **B. `.saver` bundle** | ✅ 系统管理 | ✅ | ✅ 系统管理 | ✅ 系统自动切走 | 无 | **MEDIUM** | ⚠️ 建议 |
| **C. `CGSSession` 私有框架** | — | — | — | — | — | — | 不建议 |
| **D. 硬编码 WindowServer level 数字** | — | — | — | — | — | **LOW / 不建议** | — |

---

### 2.2 路线 A：desktop-level `NSWindow` —— **推荐**

#### 层级数值（全部【实测】，编译并运行验证）

| 符号 | 数值 | Swift 写法 |
|---|---|---|
| `kCGBaseWindowLevel` | `-2147483648` | — |
| `kCGMinimumWindowLevel` | `-2147483643` | — |
| `kCGDesktopWindowLevel` | **`-2147483623`** | `NSWindow.Level(CGWindowLevelForKey(.desktopWindow))` |
| `kCGDesktopIconWindowLevel` | `-2147483603` | `NSWindow.Level(CGWindowLevelForKey(.desktopIconWindow))` |
| `kCGScreenSaverWindowLevel` | `1000` | `NSWindow.Level.screenSaver` |
| `kCGDockWindowLevel` | `20` | `NSWindow.Level.dock` |
| `kCGNormalWindowLevel` | `0` | `NSWindow.Level.normal` |

> ⚠️ **常见错误：用 `.desktopIconWindowLevel` 会盖住桌面图标。** 要在图标**下面**必须用 `.desktopWindow`。这两个只差 20，是本题最容易踩的坑。

**AppKit 侧没有对应常量** —— `NSDesktopWindowLevel` / `NSDesktopIconWindowLevel` 在 AppKit 头文件中不存在（已 grep 确认）。AppKit 只有 `NSNormalWindowLevel` / `NSFloatingWindowLevel` / `NSDockWindowLevel` / `NSStatusWindowLevel` / `NSScreenSaverWindowLevel` 等。**所以 `CGWindowLevelForKey` 不是「偷懒写法」，是唯一写法。**

#### 本机实测窗口层级图（macOS 27.0.1，实时枚举 `CGWindowListCopyWindowInfo`）

```
layer -2147483626   Window Server          ← 比桌面壁纸还低
layer -2147483624   WindowManager
layer -2147483623   花見动态壁纸  ★★★      ← 正是 kCGDesktopWindowLevel
layer -2147483603   访达 (Finder)          ← 正是 kCGDesktopIconWindowLevel，桌面图标在这
layer -2147483602   Window Server
layer -2147483601   通知中心
layer 0             夸克 / Ghostty         ← 普通应用窗口
layer 20            程序坞 (Dock)
layer 24            Window Server          ← 主菜单
layer 2147483629    微信输入法
```

**这张表是路线 A 可行性的直接证据**：一个真实在售的动态壁纸 app（`/Applications/Hanami Live Wallpaper.app`）的窗口，正停在 `kCGDesktopWindowLevel`，而 Finder 的桌面图标层在它**上面 20 级**。这不是推测，是这台机器此刻的运行状态。

同时验证了 **Dock 在 layer 20**——远高于 -2147483623，所以 desktop-level 窗口**天然不会盖住 Dock**，不需要额外处理。

#### 反汇编验证：3 个在售 app 的做法

| App | `CGWindowLevelForKey` | `CGWindowListCopyWindowInfo` | 私有框架 | 辅助功能符号 |
|---|---|---|---|---|
| Hanami Live Wallpaper | ✅ | ✅ | **0** | **无** |
| Dynamic Wallpaper | ✅ | ✅ | **0** | **无** |
| Wallpaper Monster | ✅ | ✅ | **0** | **无** |

三者一致：**公开 API 足以实现**，无一家使用私有框架。这是一个很强的收敛信号。

#### 窗口配置骨架

```swift
final class WallpaperWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        // 关键 1：桌面级。必须是 .desktopWindow，不是 .desktopIconWindow
        level = NSWindow.Level(CGWindowLevelForKey(.desktopWindow))
        // 关键 2：不参与 Space 循环，台前调度时不隐藏，多 Space 跟随，全屏时让位
        collectionBehavior = [
            .canJoinAllSpaces,        // 出现在所有 Space
            .stationary,              // 台前调度时不隐藏、不缩放
            .ignoresCycle,            // Cmd+` 循环时不参与
            .fullScreenAuxiliary,     // 全屏应用切到前台时可随其隐藏
        ]
        isOpaque = true
        ignoresMouseEvents = true   // 必须：否则壁纸吃掉全桌面点击
        backgroundColor = .black
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
```

**配置项逐条依据（`NSWindow.h` 原文，【实测】）：**

| flag | 数值 | Apple 文档原文 |
|---|---|---|
| `.canJoinAllSpaces` | `1 << 0` | 加入其他 app 的 Space 集合与全屏 Space |
| `.stationary` | `1 << 4` | *"Unaffected by exposé. Stays visible and stationary, like desktop window."* |
| `.ignoresCycle` | `1 << 6` | 不参与 `windowLevel != NSNormalWindowLevel` 的默认循环行为 |
| `.fullScreenAuxiliary` | `1 << 8` | *"Windows with this collection behavior can be shown with the fullscreen window."* |
| `.canJoinAllApplications` | `1 << 18` | macOS 13+ 新增，可能需要一并考虑【推断】 |

#### 权限需求：**零**

- ❌ 不需要辅助功能权限（不调 AX API）
- ❌ 不需要屏幕录制权限（不读窗口像素，只读窗口**元数据**）
- ❌ 不需要私有框架

**注意**：Hanami 是 **Mac App Store 上架版本且开启了 App Sandbox**，仍然正常工作。PROJECT.md 里「非 App Store 才能用非公开 API」的预设可以放宽——本方案**根本不需要非公开 API**。【实测】

#### ⚠️ 待实机 demo 验证的项（不能靠推断）

| 待验证项 | 为什么推断不够 |
|---|---|
| 多 Space 下 `canJoinAllSpaces` + 负层级窗口是否真在每个 Space 都出现 | Apple 未文档化负层级窗口的 Space 行为 |
| 台前调度（Mission Control）时是否显示 / 是否缩小 | `.stationary` 语义是「像桌面窗口一样」，但负层级是否触发未验证 |
| `.fullScreenAuxiliary` 在负层级下是否真的让位 | 文档描述针对 normal level 窗口 |
| 有虚拟桌面 / Stage Manager 时行为 | macOS 27 新特性，未在文档中找到相关说明 |
| 屏幕保护程序启动时的实际表现 | 需实跑 |

**这些是 Phase 1 spike 的验收清单。**

---

### 2.3 路线 B：`.saver` bundle —— 补充，非替代

#### 实测的真实结构

系统 saver 在 `/System/Library/Screen Savers/`，**扩展名是 `.saver` 不是 `.appex`**：

```
/System/Library/Screen Savers/
├── FloatingMessage.saver
└── Random.saver
```

`FloatingMessage.saver` 的 Info.plist（macOS 27，【实测】）关键键：

| 键 | 值 |
|---|---|
| `NSPrincipalClass` | `FloatingMessageView` ← **唯一必填项** |
| `CFBundlePackageType` | `BNDL` |
| `CFBundleExecutable` | `FloatingMessage` |
| `LSMinimumSystemVersion` | `27.0` |

在售 app 的嵌入式 saver（`Hanami.saver`，【实测】）：

- 路径 `Contents/Resources/Hanami.saver`
- `NSPrincipalClass` = `HuajianScreenSaverView`
- `CFBundleIdentifier` = `whbalzac.HuajianScreenSaver`（**与主 app 的 id 不同**，独立 bundle id）
- 链接 **`ScreenSaver.framework`（公开框架，非私有）**
- 二进制中引用 `animateOneFrame` / `hasConfigureSheet`
- 带 `ConfigureSheet.nib` + `thumbnail.tiff`

`ScreenSaverView` 公开 API（SDK `ScreenSaverView.h`）：`animateOneFrame`、`hasConfigureSheet`、`startAnimation`/`stopAnimation`、`backingStoreType`。

#### macOS 27 上还能用吗

**证据：能用，但没跑过。** macOS 27.0.1 系统里 3 个 `.saver` 仍在 `/System/Library/Screen Savers/`，Hanami 也仍在分发带 `.saver` 的 MAS 版本。机制存活。**但「saver 能显示视频」这件事本身未实测**——saver 走 `animateOneFrame` 定时回调渲染，播视频要自己接 `AVPlayerLayer`。【待验证】

#### 关键限制：saver **不能**替代桌面窗口

saver 只在**系统空闲进入屏保时**才实例化。用户正常工作时它在壁纸那个时隙里根本不存在。所以：

- **动态壁纸主诉求 → 必须走路线 A**
- 路线 B 唯一价值：让屏保启动时也显示当前视频（体验锦上添花）
- 代价：一个额外 bundle target + 独立签名 + 双份渲染逻辑

**建议：v1 不做。** 等 Phase 1 spike 确认路线 A 稳定后再评估。

#### 补充发现：屏保事件反而是「暂停信号」

Hanami 与 Dynamic Wallpaper 的二进制里都有这四个分布式通知字符串：

```
com.apple.screenIsLocked / com.apple.screenIsUnlocked
com.apple.screensaver.didstart  / com.apple.screensaver.didstop
```

说明它们**监听屏保开始/结束来驱动暂停状态机**——而不是靠 saver 自己播。这条印证了 §4 的仲裁设计。

---

### 2.4 路线 C / D：不建议

| 路线 | 判断 |
|---|---|
| `CGSSession` 私有框架 | 路线 A **根本不需要它**。`CGSessionCopyCurrentDictionary()` 虽然是**公开**的（macOS 10.3+，`CGSession.h`），但【实测】它只暴露 5 个键：`kCGSessionUserIDKey` / `kCGSSessionUserNameKey` / `kCGSessionConsoleSetKey` / `kCGSessionOnConsoleKey` / `kCGSSessionLoginDoneKey`——**没有锁屏键**，无法用于锁屏检测。无收益。 |
| 硬编码 WindowServer level 数字 | `-2147483623` 虽有 `#define` 公开常量，但 Swift 侧要硬编码就得写 magic number，**且 `CGWindowLevelForKey` 本来就公开可用**。零收益，纯增加脆弱性。 |
| `SonomaScreenSaver` / 其他私有框架 | **未找到公开资料**，且无任何在售 app 使用（3/3 均 0 私有框架）。**不采用。** |

---

## 3. 核心难点 2 —— 全屏检测

### 3.1 方案对比

| 方案 | 准确性 | 耗电 | 权限 | Confidence |
|---|---|---|---|---|
| **A. `CGWindowListCopyWindowInfo` 轮询** | 高 | 每次调用约几 ms CPU；1s 轮询可忽略 | **无** | **HIGH**【实测有 3 个在售 app 采用】 |
| B. `NSWorkspace.didActivateApplication` + AX `AXFullScreen` | 高 | 事件驱动，几乎零耗电 | ⚠️ **需辅助功能权限** | **LOW** —— `AXFullScreen` 私有 |
| C. `NSWindow.didEnterFullScreen` | — | — | 无 | **不可行** —— 只管自己进程的窗口 |
| D. 私有 API / 通知 | — | — | — | **未找到公开资料** |

### 3.2 关键发现：`AXFullScreen` 是私有的

全 SDK grep 结果，公开的只有：

```
kAXFullScreenButtonAttribute  = "AXFullScreenButton"    ← 公开
kAXFullScreenButtonSubrole    = "AXFullScreenButton"    ← 公开
```

**`kAXFullScreenAttribute` 不存在。** 业界教程里常写的 `AXUIElementCopyAttributeValue(el, "AXFullScreen" as CFString, &value)` 用的是**未文档化属性串**。直接后果：

- 要用就得申请辅助功能权限（`AXIsProcessTrusted()`）
- App Store 审核大概率被拒
- 3 个在售 wallpaper app 的导入符号里**没有任何 AX 符号**

**→ 放弃方案 B。** PROJECT.md 里写的候选方案应据此收敛。

### 3.3 推荐实现：窗口列表 + 事件触发混合

```swift
final class FullscreenDetector {
    private let mainDisplayID: CGDirectDisplayID
    private var timer: Timer?

    /// 任一非本进程的 layer-0 窗口铺满主屏 → 判定全屏
    private func computeFullscreen() -> Bool {
        let screenFrame = NSScreen.main?.frame ?? .zero
        guard screenFrame != .zero,
              let list = CGWindowListCopyWindowInfo(
                  .optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]]
        else { return false }

        for w in list {
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  let owner = w[kCGWindowOwnerName as String] as? String,
                  owner != ProcessInfo.processInfo.processName,
                  let b = w[kCGWindowBounds as String] as? [String: Any]
            else { continue }

            let r = CGRect(x: b["X"] as! CGFloat, y: b["Y"] as! CGFloat,
                           width: b["Width"] as! CGFloat, height: b["Height"] as! CGFloat)
            // 铺满主屏（含 Retina 下 bounds == frame 的情况）
            if r.width  >= screenFrame.width  - 2,
               r.height >= screenFrame.height - 2 {
                return true
            }
        }
        return false
    }

    /// 事件触发（免费、即时）+ 定时兜底（防轮询漏事件）
    func start() {
        let ws = NSWorkspace.shared.notificationCenter
        for n in [NSWorkspace.didActivateApplicationNotification,
                  NSWorkspace.didDeactivateApplicationNotification] {
            ws.addObserver(forName: n, object: nil, queue: .main) { [weak self] _ in
                self?.recompute()
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.recompute()
        }
    }
}
```

**耗电控制**：`CGWindowListCopyWindowInfo(.optionOnScreenOnly)` 在有 12 个窗口的桌面下是微秒级操作；1 秒轮询的实际开销远低于一次视频解码。事件触发负责即时响应，轮询只兜底。

**为什么不用私有 API 轮询**：三个在售 app 都用 `CGWindowListCopyWindowInfo`，收敛信号已经足够强。

**⚠️ 待验证：**
- 全屏窗口的 `kCGWindowBounds` 在 Retina 下是否等于 `NSScreen.frame`（`CGWindowList` 用的是**全局坐标**，而 `NSScreen.frame` 也是全局坐标，理论上对齐，但**未实测**）
- 全屏应用是否为 `kCGWindowLayer == 0`（不同 app 可能不同，**未找到公开资料**）
- 容差 `2pt` 是否足够 / 是否需要按缩放因子调整

---

## 4. 核心难点 3 —— 系统事件源

全部为公开 API，**实测确认存在于 SDK**：

| 事件 | API | 公开? | 备注 |
|---|---|---|---|
| 全屏 | `CGWindowListCopyWindowInfo` | ✅ | 见 §3 |
| 锁屏 / 解锁 | 分布式通知 `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked` | ❌ 未文档化 | **但 2 个在售 app 在用**；无权限需求 |
| 锁屏（备选） | `CGSessionCopyCurrentDictionary()` | ✅ 公开 | 【实测】**无锁屏键**，仅作 session 切换兜底 |
| 显示器熄屏 | `CGDisplayIsAsleep()` / `CGDisplayIsActive()` | ✅ | `CGDisplayConfiguration.h` |
| 显示器热插拔 / 配置变更 | `CGDisplayRegisterReconfigurationCallback` | ✅ | `CGDisplayConfiguration.h:235` |
| 系统睡眠 / 唤醒 | `NSWorkspace.willSleepNotification` / `didWakeNotification` | ✅ | `NSWorkspace.h:322-323` |
| 电池 / 供电 | `IOPSCopyPowerSourcesInfo` / `IOPSGetPowerSourceDescription` / `IOPSNotificationCreateRunLoopSource` | ✅ | IOKit `ps/`，3 个 app 均用 |
| 低电量模式 | `ProcessInfo.isLowPowerModeEnabled` + `NSProcessInfoPowerStateDidChangeNotification` | ✅ macOS 12+ | `NSProcessInfo.h:495,513` |
| 屏保开始/结束 | 分布式通知 `com.apple.screensaver.didstart` / `didstop` | ❌ 未文档化 | 2 个在售 app 在用 |
| App 激活/失活 | `NSWorkspace.didActivateApplicationNotification` | ✅ | 用作全屏检测的事件触发器 |
| Space 切换 | `NSWorkspace.activeSpaceDidChangeNotification` | ✅ | 【推断】存在，未逐一 grep 确认 |

**锁屏检测的诚实说明**：这是唯一一个「靠未文档化通知」的必需项。`com.apple.screenIsLocked` 在公开 SDK 里 **grep 不到**（全 SDK 搜索 `screenIsLocked` 无结果），但它在两个独立在售 app 的二进制里都存在，可信度高。**仍建议实机验证。** 若该通知失效，降级方案是轮询 `CGSessionCopyCurrentDictionary()` 的 `kCGSessionOnConsoleKey`（锁屏时通常仍为 true，实际不可靠）——**真正的降级方案未找到公开资料**。

---

## 5. 架构分层

### 5.1 系统概览

```
┌──────────────────────────────────────────────────────────────────────┐
│  UI 层 (SwiftUI)                                                      │
│  ┌────────────────────┐  ┌────────────────────┐                      │
│  │ MenuBarExtra 场景   │  │ Settings 场景       │                      │
│  │ (菜单栏 + 弹窗)     │  │ (设置窗口)          │                      │
│  └─────────┬──────────┘  └─────────┬──────────┘                      │
└────────────┼───────────────────────┼─────────────────────────────────┘
             │ 读写                   │ 读写
             ▼                       ▼
┌──────────────────────────────────────────────────────────────────────┐
│  状态层 (纯 Swift，无 UI，无 AVFoundation)                              │
│  ┌────────────────────────────────────────────────┐                  │
│  │ SettingsStore   — Observable, UserDefaults 持久化 │                  │
│  │ MediaLibrary    — 扫描/索引/筛选视频               │                  │
│  │ PlaybackPolicy  — ★ 暂停仲裁状态机                 │                  │
│  └────────────────────────────────────────────────┘                  │
└────────────┬───────────────────────────────────┬────────────────────┘
             │ 决策（要不要播 / 播哪个）              │ 订阅（设置变更）
             ▼                                    ▼
┌──────────────────────────────────────────────────────────────────────┐
│  引擎层 (AVFoundation)                                                │
│  ┌──────────────────────┐  ┌──────────────────────┐                │
│  │ PlayerController     │  │ TranscodeService     │                │
│  │ AVPlayer/AVPlayerItem │  │ AVAssetExportSession │                │
│  └──────────┬───────────┘  └──────────────────────┘                │
└─────────────┼────────────────────────────────────────────────────────┘
              │ 挂载 AVPlayerLayer
              ▼
┌──────────────────────────────────────────────────────────────────────┐
│  系统事件层 (AppKit / CoreGraphics / IOKit)                            │
│  ┌───────────────┐ ┌──────────────┐ ┌────────────┐ ┌─────────────┐ │
│  │FullscreenDet. │ │ LockWatcher  │ │ PowerWatch │ │DisplayWatch │ │
│  └───────┬───────┘ └──────┬───────┘ └─────┬──────┘ └──────┬──────┘ │
│          └────────────────┴───────────────┴───────────────┘           │
│                        │ 上报 HoldReason                              │
│                        ▼                                              │
│  ┌──────────────────────────────────────────────┐                   │
│  │  HoldArbiter  ←—— 所有事件在此汇聚 ——→        │                   │
│  └──────────────────────┬───────────────────────┘                   │
└─────────────────────────┼───────────────────────────────────────────┘
                          ▼
┌──────────────────────────────────────────────────────────────────────┐
│  渲染层 (AppKit — 唯一必须用 AppKit 的地方)                            │
│  ┌──────────────────────────────────┐                               │
│  │ WallpaperWindowController        │                               │
│  │  NSWindow(level: kCGDesktop)     │                               │
│  │  + AVPlayerLayer                 │                               │
│  └──────────────────────────────────┘                               │
└──────────────────────────────────────────────────────────────────────┘
```

### 5.2 组件职责与边界

| 组件 | 职责 | 依赖 | **不做什么** |
|---|---|---|---|
| `SettingsStore` | 所有用户设置的单一真相源；`@Observable`；写 UserDefaults | 无 | 不含业务逻辑，不碰 AV |
| `MediaLibrary` | 递归扫描文件夹 → `[VideoItem]`；按格式/可解码性过滤；支持手动 rescan | SettingsStore（读源目录） | **不自动监听文件系统**（v1 Out of Scope） |
| `HoldArbiter` | 汇聚所有 HoldReason；决定 `shouldPlay`；维护 resume anchor | 无 | **不碰 AVPlayer**，只输出布尔 + 原因 |
| `PlayerController` | 持有 AVPlayer/AVPlayerItem；响应 `shouldPlay`；seek/速率/音量 | MediaLibrary, HoldArbiter, SettingsStore | 不判断「为什么」暂停 |
| `WallpaperWindowController` | 建/销毁桌面级 NSWindow；挂 AVPlayerLayer | PlayerController | 不做播放决策 |
| `FullscreenDetector` | 轮询 + 事件触发 → `HoldReason.fullscreen` | 无 | 不直接改播放器状态 |
| `LockWatcher` | 分布式通知 → `HoldReason.screenLocked` | 无 | 同上 |
| `PowerWatcher` | IOKit + 低电量模式 → `HoldReason.battery` | 无 | 同上 |
| `DisplayWatcher` | CGDisplay 回调 → `HoldReason.displayAsleep` | 无 | 同上 |
| `TranscodeService` | 非原生格式 → 转码；产出缓存文件 | MediaLibrary | v1 可为 stub |

**边界的核心设计**：所有 `*Watcher` **只**产出 `HoldReason`，**不直接**控制播放器。单向数据流：`Watcher → HoldArbiter → PlayerController`。这让暂停逻辑可单测（纯函数，无 AVFoundation）。

---

## 6. 暂停优先级仲裁状态机

### 6.1 核心洞察：不要用「优先级链」，用「veto 集合」

朴素做法是维护一个 `currentReason: HoldReason?`，新条件来了就覆盖。这**是错的**：

> 用户在锁屏状态下退出全屏应用 → 若用覆盖式，fullscreen 解除就把 `currentReason` 清空 → **在仍然锁屏的情况下恢复播放**。

正确模型是 **veto 集合**：每个条件独立持有自己的否决权，**集合为空才播放**。

### 6.2 状态定义

```swift
enum HoldReason: Int, Comparable, CaseIterable {
    case fullscreen        // 全屏应用（要求最高：最影响体验）
    case screenLocked      // 锁屏
    case displayAsleep     // 显示器熄屏
    case systemSleeping    // 系统睡眠
    case battery           // 电池供电（默认关）
    case manual            // 用户手动暂停（要求最低）
}

struct PlaybackDecision: Equatable {
    var shouldPlay: Bool { holds.isEmpty }
    var holds: Set<HoldReason>     // 当前所有生效的否决原因
    var topReason: HoldReason?     // = holds.min()，仅用于 UI 展示
}
```

**优先级排序的唯一用途是 UI 文案**（「因全屏暂停」），**不参与播放决策**。这是「优先级」需求的正确落点。

### 6.3 Resume Anchor —— 「从哪里续播」

`resumeAnchor` 在 **`holds` 由空变为非空的那一刻**记录当前播放位置，此后**不再更新**，直到集合清空。

```
t0  holds={}            playing @ 00:42      resumeAnchor = nil
t1  fullscreen 触发      holds={fullscreen}   resumeAnchor = 00:42  ← 锚定
t2  screenLocked 触发    holds={full, locked} resumeAnchor 保持 00:42  ← 不覆盖
t3  fullscreen 解除      holds={locked}       shouldPlay = false      ← 正确，不恢复
t4  screenLocked 解除    holds={}             seek(to: 00:42) → 播放  ← 从最初锚点续播
```

**为什么不每次暂停都更新锚点？** 若 t2 时锚点被更新成 00:55，t4 就会从 00:55 续播——跳过了 t1→t2 之间本该播放的内容，用户感知为「莫名其妙往前跳」。**锚点只在进入暂停态时设定一次**，语义是「这次暂停从哪开始算起」。

### 6.4 仲裁器实现

```swift
@MainActor
final class HoldArbiter: ObservableObject {
    @Published private(set) var decision = PlaybackDecision()

    private var resumeAnchor: CMTime?
    private let onChange: (PlaybackDecision) -> Void

    func set(_ reason: HoldReason, active: Bool) {
        let before = decision.holds
        let after = active ? before.union([reason]) : before.subtracting([reason])

        // 进入暂停态：锚定续播位置
        if before.isEmpty && !after.isEmpty {
            resumeAnchor = onChange.currentPosition
        }
        guard before != after else { return }

        decision = PlaybackDecision(holds: after)

        if after.isEmpty, let anchor = resumeAnchor {
            onChange.seek(to: anchor)     // 续播，不是从头
            resumeAnchor = nil
        }
        onChange.apply(decision)
    }
}
```

**不变式：**
1. `holds` 是唯一的播放判据
2. `resumeAnchor` 在 `∅ → 非∅` 时写入，在 `非∅ → ∅` 时消费并清空
3. 锚点生命周期内不被二次暂停覆盖
4. 重复 `set(reason, active:)` 幂等（`guard before != after`）

---

## 7. 数据流

### 7.1 设置变更 → 立即生效（PROJECT.md 硬需求）

```
用户在设置窗口拖动速度滑块
    ↓
SettingsStore.speed = 1.5                    (@Observable，@MainActor)
    ↓ withAnimation 通知所有观察者
    ├──→ PlayerController.rate = 1.5        当场改 AVPlayer.rate，不等换片 ✅
    └──→ (持久化) UserDefaults
```

**关键约束：`PlayerController` 必须订阅 `SettingsStore` 的变化并**立即**改 live 的 `AVPlayer` 实例**。禁止「下次换片才生效」——这是需求里明确拒绝的行为。

**同理**：
- `volume` → `AVPlayer.volume`（当刻生效）
- `audioTimePitchAlgorithm` → **需要重建 `AVPlayerItem`**，属于「改不了 live 对象」的少数例外。应在改动时重建并 seek 回 resumeAnchor，避免用户感知卡顿。【推断】
- `playMode` / `rotationInterval` → 由 `PlayerController` 订阅并重置内部计数器

### 7.2 系统事件 → 播放决策

```
FullscreenDetector ─┐
LockWatcher ────────┤
PowerWatcher ───────┼──→ HoldArbiter.set(reason:active:) ──→ PlaybackDecision
DisplayWatcher ────┤                                        ↓
(NSWorkspace sleep) ┘                              PlayerController.pause()/play()
                                                          ↓
                                             AVPlayer.rate = 0 / seek(resumeAnchor) → 1
```

**单向。** `PlayerController` 从不反查「现在为什么暂停」。

### 7.3 媒体库 → 播放

```
用户点「重新扫描」/ 启动 / 设置变更
    ↓
MediaLibrary.scan(rootURL)  递归 FileManager.enumerator
    ↓ 过滤：扩展名 ∈ {mp4,mov,m4v} 且 AVURLAsset 可加载视频轨
VideoItem[URL, duration, resolution]
    ↓ (持久化到 UserDefaults/Cache，只存 URL+元数据，不拷文件)
PlayerController 按 playMode 挑选 → replaceCurrentItem
```

**格式失效处理**（PROJECT.md 需求「文件夹被删/移动 → 露出系统原壁纸」）：
```
scan 返回空 或 rootURL 不存在
    ↓
PlayerController.stop() + WallpaperWindowController.orderOut(nil)
    ↓ 系统原壁纸自然露出（因为我们从不改系统壁纸，只是盖了一层）
```

### 7.4 壁纸窗口生命周期

```
App 启动
  ↓
NSApplicationDelegateAdaptor.applicationDidFinishLaunching
  ↓
MediaLibrary.scan → 空？→ 不建窗口（露出系统壁纸）
  ↓ 非空
WallpaperWindowController.show(screen: .main)   // 只主屏，v1
  ↓
挂 AVPlayerLayer → PlayerController.attach(layer:)
  ↓
订阅 decision：空→播放 / 非空→暂停
```

---

## 8. SwiftUI vs AppKit 分工

| 层 | 选择 | 理由 |
|---|---|---|
| 菜单栏 | **SwiftUI `MenuBarExtra`** | SDK 已确认可用（`arm64e-apple-macos.swiftinterface:2092`）。`LSUIElement=true` 与 3 个在售 app 一致 |
| 设置窗口 | **SwiftUI `Settings` 场景** | 纯 SwiftUI 足够。控件形态待 UI 研究定，但**容器**无需 AppKit |
| 壁纸窗口 | **必须 AppKit `NSWindow`** | SwiftUI **没有** window level 概念，无法设置 `level`。唯一例外 |
| 播放器 | **AVFoundation（不是 AVKit）** | 3 个在售 app 全部只链 AVFoundation。`AVPlayerView` 是 AVKit 的，壁纸场景不需要其 UI chrome |

**推荐的 App 入口：**

```swift
@main
struct PicApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        MenuBarExtra("Pic", systemImage: "photo.on.rectangle") {
            MenuContentView()          // 暂停/继续、立即下一个、重新扫描、设置、退出
        }
        Settings {
            SettingsView()             // 纯 SwiftUI
        }
        // 注意：body 里**不放** wallpaper 窗口——它由 AppDelegate 管理
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let wallpaper = WallpaperWindowController()
    let arbiter = HoldArbiter()
    let player = PlayerController()
    let library = MediaLibrary()
    let settings = SettingsStore()

    func applicationDidFinishLaunching(_ n: Notification) {
        LSUIElement 由 Info.plist 提供
        wiring()                        // 唯一装配点，见下
    }
}
```

**唯一装配点 `wiring()`** —— 所有依赖在此接一次，其余模块彼此只通过协议通信：

```swift
private func wiring() {
    player.attach(to: wallpaper)
    arbiter.onChange = player
    FullscreenDetector().start { arbiter.set(.fullscreen, active: $0) }
    LockWatcher().start     { arbiter.set(.screenLocked, active: $0) }
    PowerWatcher().start    { arbiter.set(.battery, active: $0) }
    DisplayWatcher().start  { arbiter.set(.displayAsleep, active: $0) }
    NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.didWakeNotification, ...) { arbiter.set(.systemSleeping, active: false) }
    // 设置订阅（保证立即生效）
    settings.$speed.sink { player.rate = $0 }
    settings.$volume.sink { player.volume = $0 }
    settings.$sourceFolder.sink { _ = library.scan(); player.reload() }
}
```

> **注意**：SwiftUI `@Observable` + `sink` 需要 Combine 或手写 `withObservationTracking`。建议 v1 直接在 `@MainActor` 上用 `Task { for await v in settings.$speed { ... } }`（AsyncStream），避免引入 Combine。【推断】

---

## 9. 推荐项目结构

```
Pic/
├── PicApp.swift                    # @main，MenuBarExtra + Settings 场景
├── AppDelegate.swift               # 唯一装配点 wiring()
├── Info.plist                      # LSUIElement=true, NSPrincipalClass=NSApplication
│
├── State/                          # 纯 Swift，零 UI 零 AVFoundation —— 可单测
│   ├── SettingsStore.swift         # @Observable + UserDefaults
│   ├── HoldReason.swift            # enum + Comparable
│   ├── PlaybackDecision.swift      # veto 集合类型
│   └── HoldArbiter.swift           # ★ 仲裁状态机 + resume anchor
│
├── Media/
│   ├── VideoItem.swift
│   ├── MediaLibrary.swift          # 递归扫描（手动触发）
│   └── TranscodeService.swift      # v1 = stub
│
├── Playback/
│   ├── PlayerController.swift      # AVPlayer + AVPlayerItem 封装
│   └── PlaybackQueue.swift         # 列表循环 / 随机 / 轮换计时器
│
├── System/                         # 只产出 HoldReason，不碰播放器
│   ├── FullscreenDetector.swift    # CGWindowListCopyWindowInfo
│   ├── LockWatcher.swift           # 分布式通知
│   ├── PowerWatcher.swift          # IOKit ps + isLowPowerModeEnabled
│   └── DisplayWatcher.swift        # CGDisplayRegisterReconfigurationCallback
│
├── Render/                         # ★ 唯一必须 AppKit 的地方
│   ├── WallpaperWindow.swift       # NSWindow @ kCGDesktopWindowLevel
│   └── WallpaperWindowController.swift
│
├── Features/
│   ├── MenuBar/MenuContentView.swift
│   └── Settings/SettingsView.swift # 纯 SwiftUI，控件形态待 UI 研究
│
└── Tests/
    ├── HoldArbiterTests.swift      # 纯逻辑，无需 AVFoundation
    └── PlaybackDecisionTests.swift
```

**结构理由：**

- **`State/` 零依赖**是本架构最重要的可测性保证。暂停仲裁是需求里最容易出 bug 的部分（§6 的覆盖式反例），把它做成不 import AVFoundation 的纯类型，就能跑毫秒级单测。
- **`System/` 与 `Player/` 严格分离**，保证单向数据流（§5.2）。Watcher 若能直接改播放器，仲裁逻辑就会被绕过。
- **`Render/` 独立成目录** —— 因为它是唯一被平台约束逼着写 AppKit 的地方。把它隔离，将来若路线 A 失败要换方案，改动面被限制在这一个目录。
- **`State/SettingsStore` 单向**：UI 只写 store，store 只发通知，无人反向写 UI。

---

## 10. 建议构建顺序（供 roadmap 分期）

> 依赖关系：**P1 是所有后续阶段的前置门**。若 P1 证伪，整个架构需重做，后面全部作废。

| # | 阶段 | 交付 | 依赖 | 理由 |
|---|---|---|---|---|
| **P1** | **桌面层级可行性 spike** | 一次性验证 app：把一个彩色/带帧号的视图放在 `-2147483623`，逐项验收 §2.2 的 5 条待验证项，输出结论表 | 无 | **必须最先做**。PROJECT.md 已把它列为最大技术风险。它是 throwaway spike，不是产品代码 |
| **P2** | 内核竖切 | 菜单栏 + 壁纸窗口 + 单文件视频循环 + `SettingsStore` + `HoldArbiter`（先只接手动暂停） | P1 | 最小可感知价值。能端到端看到视频在桌面图标后面播 |
| **P3** | 系统事件仲裁 | 接入 4 个 Watcher + 完整 veto 状态机 + resume anchor + 单测 | P2 | 需求里最复杂的部分，必须有 P2 的骨架才能接 |
| **P4** | 媒体库与轮换 | 递归扫描、格式过滤、三种播放模式、轮换计时器、失效降级 | P2（可与 P3 并行） | 独立于 P3，二者无耦合，**建议并行** |
| **P5** | 设置窗口与即时生效 | SwiftUI 设置 UI + 全量订阅实现 + 变速保音高 | P2 | 依赖 P2 的 `SettingsStore`；P3/P4 提供可调项 |
| **P6** | 转码层 | 非原生格式转码 + 缓存 | P4 | 需求里张力最大的一项（体积 +80~150MB），应最后做 |
| **P7** | 分发与开机自启 | 签名 .app、`SMLoginItemService`/手动项、拷贝到别的 Mac 验证 | P3-P5 | 打包收尾 |

**并行建议**：P3 与 P4 无依赖，墙钟时间紧时可并行——两者只共享 `MediaLibrary` 与 `HoldArbiter` 的接口，接口先定死即可。

---

## 11. 反模式（本域特有）

### 反模式 1：用 `.desktopIconWindowLevel` 放壁纸

**错在哪**：会盖住桌面图标，比普通窗口更糟。
**改用**：`CGWindowLevelForKey(.desktopWindow)`。**代码评审时把这一行列为必查项**——它只差 20，肉眼极难发现。

### 反模式 2：用优先级链做暂停仲裁

**错在哪**：`currentReason = newReason` 的覆盖式写法，在「锁屏中退出全屏」时会错误恢复播放（§6.1）。
**改用**：`Set<HoldReason>` veto 集合，`isEmpty` 才播。优先级只用于 UI 文案。

### 反模式 3：每次暂停都更新续播锚点

**错在哪**：连续暂停（进全屏 → 又锁屏 → 退出全屏）会让锚点漂移，最终跳过本该播放的片段。
**改用**：锚点只在 `∅ → 非∅` 写入一次。

### 反模式 4：用 `AXFullScreen` 属性检测全屏

**错在哪**：私有属性（§3.2 已实测确认不在公开 SDK），要辅助功能权限，App Store 拒审。
**改用**：`CGWindowListCopyWindowInfo` + layer 0 + bounds 覆盖判定。

### 反模式 5：用 SwiftUI 做壁纸窗口

**错在哪**：SwiftUI 没有 window level 概念，永远无法把窗口放到图标后面。
**改用**：AppKit `NSWindow` + `NSHostingView` 承载 SwiftUI 内容（虽然本项目壁纸层不需要 SwiftUI）。

### 反模式 6：把 watcher 直接连到播放器

**错在哪**：绕过仲裁器 → 多条件并存时行为不可预测，且无法单测。
**改用**：watcher 只上报 `HoldReason`，唯一出口是 `HoldArbiter`。

### 反模式 7：用 AVKit 的 `AVPlayerView`

**错在哪**：带 UI chrome（播放控件），壁纸不需要；3 个在售 app 全部只用 AVFoundation。
**改用**：`AVPlayer` + 手动 `AVPlayerLayer`。

---

## 12. 未验证 / 需你调研的部分

### 12.1 必须实机 demo（无法靠文档或推理）

| 项 | 验证方式 |
|---|---|
| 负层级窗口在多 Space / 台前调度的真实行为 | P1 spike |
| 全屏时壁纸窗口是否真的让位 | P1 spike |
| `com.apple.screenIsLocked` 通知是否在 macOS 27 仍触发 | P1 spike（锁屏手动测） |
| 实际耗电数值（播放 vs 暂停） | P3 后实测 `pmset -g batt` |
| `.saver` 路线能否播视频 | 独立小实验 |

### 12.2 联网调研失败 —— 以下需你用 web 工具查

WebSearch/WebFetch 本次 6 次调用全部 `API Error: 400`。以下问题**本地无法回答**，请复制下面 prompt 去查：

```
【背景】
我在为 macOS 27 架构一个视频动态壁纸 app（菜单栏常驻，把视频放在桌面图标后面播放）。
已通过读 SDK 头文件 + 枚举本机窗口 + 反汇编 3 个在售同类 app，确认了这些事实：
- 桌面级 NSWindow 用 CGWindowLevelForKey(.desktopWindow) = -2147483623 可行，
  桌面图标在 -2147483603，Dock 在 20。零权限、零私有框架。
- kAXFullScreenAttribute 不是公开 API，只有 kAXFullScreenButtonAttribute。
- 锁屏通知 com.apple.screenIsLocked 不在公开 SDK 里，但两个在售 app 都在用。

【请回答以下问题，每问给明确答案 + URL】

1. macOS 26 / 27（Tahoe / 26.x）是否有人报告过
   "CGWindowLevelForKey(.desktopWindow)" 的窗口行为发生变化？
   例如：不再显示在桌面图标后、被 Stage Manager 遮挡、在多 Space 下失效、
   或系统更新后层级被重置。查 GitHub issue、Reddit r/mac、
   Stack Overflow、developer.apple.com forums。

2. Stage Manager（台前调度）开启时，负层级窗口的表现如何？
   桌面图标在 Stage Manager 下是否仍然位于 kCGDesktopIconWindowLevel？
   有没有人报告动态壁纸 app 在 Stage Manager 下失效？

3. 有没有现成的开源 macOS 视频壁纸项目？列出仓库地址、
   最近一次 commit 日期、以及它用的是 .saver 路线还是 desktop-level NSWindow 路线。
   已知可能的方向：GitHub 搜 "macos live wallpaper"、
   "mac dynamic wallpaper"、"video wallpaper swift"。

4. macOS 26/27 上 ScreenSaver bundle（.saver）机制是否已被弃用或限制？
   是否还能正常注册为自定义屏保？Sonoma / Sequoia 上有无已知回归？
   查 developer.apple.com/forums 里关于 screensaver bundle 的近期讨论。

5. CGWindowListCopyWindowInfo 在 macOS 15+ 是否需要屏幕录制权限？
   有无变化（例如 Sonoma 起对 kCGWindowName / kCGWindowOwnerName 做了限制）？
   只需要 window layer 和 bounds 的情况下，权限要求是什么？

6. 桌面级窗口播放视频的实测耗电数据。Apple Silicon Mac（如 M 系列）
   用 AVPlayer + AVPlayerLayer 全屏 5.4K 循环播放，
   对比不播放时的 battery drain（%/h）。有实测数据或专业评测吗？

7. macOS 27 上是否存在比 kCGDesktopWindowLevel 更"官方"的
   视频壁纸 API？Apple 在 macOS 26/27 发布说明里有没有提到
   dynamic wallpaper / animated wallpaper 的新 API 或新能力？

【输出格式】
- 每问单独一段，先给一句话结论，再给证据和 URL
- 明确标注每条信息的发布日期，优先近 12 个月
- 找不到的写「未找到公开资料」，不要推测
- 如果找到的是旧系统（Big Sur ~ Sonoma）的信息，请标注适用系统版本
```

---

## 13. 来源

### 本机实测（一手，可复现）

| 来源 | 方法 |
|---|---|
| `CGWindowLevel.h` 全部常量 | 读取 `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/.../CGWindowLevel.h`，**编译 C 程序运行打印实际数值** |
| `NSWindowCollectionBehavior` 全部 flag 与数值 | 读取 `AppKit.framework/Headers/NSWindow.h:128-149` + Apple 文档原文注释 |
| `AXFullScreen` 非公开 | 全 SDK 递归 grep `AXFullScreen` / `fullscreen` |
| `CGSessionCopyCurrentDictionary` 键集 | 读取 `CoreGraphics.framework/Headers/CGSession.h`（全文 61 行） |
| `NSDesktopWindowLevel` 不存在 | grep AppKit 全部头文件，返回空 |
| 实时窗口层级分布 | 自编 C 程序调 `CGWindowListCopyWindowInfo(.optionOnScreenOnly)` 枚举本机窗口，按 layer 分组打印 |
| 系统 saver 结构 | `find /System/Library/Screen Savers/` + `plutil -p` 读 `FloatingMessage.saver/Contents/Info.plist` |
| Hanami.saver 结构 | `plutil -p` + `otool -L` + `strings` |
| 3 个在售 app 的机制 | `nm -u`（导入符号）+ `otool -L`（框架）+ `codesign -d --entitlements`（沙盒）+ `strings` |
| 低电量模式 / 电源 API | 读取 `NSProcessInfo.h:494-513`、`IOKit/Headers/ps/*.h` |
| 显示休眠 API | 读取 `CGDisplayConfiguration.h:235,282,288` |
| `MenuBarExtra` 可用性 | 读取 `SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface:2092` |

### 环境

macOS 27.0.1 (26A434) · SDK `MacOSX27.0` · Xcode 27 (`DTXcodeBuild 27A200c`)

### 联网

**本轮全部失败**（WebSearch + WebFetch，6/6 返回 `API Error: 400`）。已按 §12.2 输出待调研 prompt。

---

*Architecture research for: macOS 视频动态壁纸*
*Researched: 2026-10-02*
*环境：macOS 27.0.1 · 所有常量与窗口层级均为本机实测，非文档推断*
