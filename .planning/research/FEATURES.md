# Feature Research — macOS 视频动态壁纸

**Domain:** macOS 视频动态壁纸（菜单栏 native app）
**Researched:** 2026-10-02
**Confidence:** Part A **HIGH**（App Store 一手元数据，实时抓取）· Part B 控件存在性 **HIGH**（本地 macOS 27 SDK 实编译验证）· Part B 视觉/布局 **MEDIUM**（Apple 文档 + macOS 惯例，未运行渲染）

**验证环境（实测）**：`macOS 27.0.1 (26A434)` · SDK `MacOSX27.0.sdk` · `Swift 6.4` · target `arm64-apple-macosx27.0`

---

## ⚠️ 先纠正题目前提里的三处错误

调研过程中发现题面给的三个对标产品有两个不成立。这会直接影响 roadmap，先说清楚：

| 题面所说 | 实测结果 | 证据 |
|---------|---------|------|
| **Wallpaper Engine (macOS)** | ❌ **Wallpaper Engine 没有 macOS 版** | 官网标题字面即 "Animated Wallpapers on **Windows**"；帮助站有独立章节 "Wallpaper Engine on Linux or Mac OS"（即"不支持"FAQ）；仅通过 Steam / Green Man Gaming 售卖 |
| **VIDHub** | ❌ **不是壁纸 app** | App Store 上是 "VidHub - Video Library & Player"，开发者 Nanjing Oumi Software Development —— 云盘/视频库播放器品类，与动态壁纸无关 |
| **iWallpaper** | ⚠️ **有两个** | macOS 版是 "iWallpaper - Live Wallpaper"（id1552826194，min macOS 10.15）；"iWallpaper - 4K 8K Screens"（id1155869721）是 iOS 端，别搞混 |

**结论**：Wallpaper Engine 只能当**功能设计参考**（性能规则 / 播放列表 / 电池暂停），不能当 macOS 竞品。真正的 macOS 对标是 **VideoPaper / Dynamic Wallpaper Studio / 4K Live Wallpaper / Dynamic Wallpaper Library** 这批。

---

# Part A — 功能全景

## Table Stakes（缺了 = 产品显得残废）

竞品描述里**反复出现**的功能即为品类惯例。用户不会因为你做了而夸你，但缺了会走。

| Feature | 为什么是惯例 | Complexity | Notes |
|---------|------------|------------|-------|
| 选择来源（本地视频 / 文件夹） | 所有竞品的起点。VideoPaper 明确支持 "individually, or by **folder reference**" | LOW | 我们的"文件夹 + 递归"已定，直接对标 VideoPaper 的 folder reference |
| 菜单栏常驻 + 关窗口不退出 | 菜单栏是这类 app 的默认形态（VideoPaper "Lives, unobtrusively, in your Menu Bar"；Irvue 亦然） | MEDIUM | 需 `LSUIElement=true` + 显式生命周期管理 |
| **播放模式：单循环 / 列表循环 / 列表随机** | Dynamic Wallpaper Studio 原词："Single Loop, Playlist Loop, or **Shuffle**" —— 三个选项的名字都不用改 | LOW | 已定，直接落地 |
| **暂停条件（自动 / 智能暂停）** | 品类核心承诺。4K Live Wallpaper "**Smart Auto-Pause Mode**"；Dynamic Wallpaper Studio "**Smart Pause**"；Wallpaper Engine 自动在游戏/最大化时暂停 | MEDIUM | **我们的 Core Value 就是这个**，不可省 |
| **电池供电时暂停** | iWallpaper "Support battery-powered **static** energy saving"；4K Live Wallpaper "The power source is **disconnected**"；Wallpaper Engine "automatically pause when switching to battery power" | LOW | 品类惯例是默认关（我们已定） |
| 播放速度可调 | VideoPaper "Adjust wallpaper ... playback **speed** independently" | LOW | 需配 pitch 保持（见下） |
| 出声开关 + 音量 | 4K Live Wallpaper / Mural 都有音频层 | LOW | |
| 开机自启 | macOS 工具类 app 基线 | LOW | `SMAppService`，非沙盒可用 |
| 裁剪填满屏幕 | 全品类默认（`resizeAspectFill`）；VideoPaper 额外暴露 scale/alignment | LOW | 我们只做 fill，对齐留白 |
| **看不见时不播（遮挡即停）** | iWallpaper 的 "occlusion algorithm ensures it must be **dynamic when it can be seen, and static when it cannot be seen**" | MEDIUM | 这是品类的核心叙事，直接对应我们的"锁屏/熄屏/睡眠暂停" |

**Table Stakes 共识**：品类的主轴不是"能播视频"（人人都会），而是**"什么时候不播"**。所有成熟竞品的卖点都堆在暂停策略上。我们把这条当核心做，是选对了赛道。

---

## Differentiators（我们的竞争优势）

严格对齐 PROJECT.md 的 Core Value：**不偷电、不抢性能、别人看不出在播视频**。

| Feature | 价值主张 | Complexity | Notes |
|---------|---------|------------|-------|
| **改动立即生效** | 竞品普遍要重启/重开设置才生效。改速度当场变、改模式当场换片 —— 这是能直接感知的品质差距 | MEDIUM | 已定为硬约束。需要在设置绑定层做**观察者**而非"下次生效" |
| **完全离线：文件夹即唯一真相** | 所有内容型竞品都要账号 + 云 + 订阅（Hanami / Dynamic Wallpaper Studio / 4K Live Wallpaper / Mural 全是订阅制）。我们是纯本地文件夹，拷 .app 到另一台 Mac 就能用 | LOW | 既是 differentiator 也是分发约束（PROJECT.md Distribution） |
| **一个总闸管所有暂停条件** | 竞品把暂停散在 "Performance" tab（Wallpaper Engine）或 "Smart Pause" 一簇里，用户要逐条勾。我们一个主开关 + 下面分组从属 | LOW | 直接服务 Core Value |
| **失败时露出系统原壁纸** | 文件夹被删/无有效视频 → 隐藏壁纸窗口让系统壁纸透出，而不是黑屏/空桌面。竞品都没明说这个行为 | LOW | 已定，是"干净"体验的差异点 |
| **保画质转码管线** | 全竞品都只写 "Import local videos"，**没有一家提供转码**。我们要做无损保质转码，把非原生格式接进来 | HIGH | 唯一真正没人做的功能，也是复杂度最高的一处 |
| 菜单不显示当前文件名 | 界面干净，减少信息噪音 | LOW | 用户明确选择 |

---

## Anti-Features（故意不做）

这一节是防 scope creep 的。多数条目的共同点：**都会直接违反我们的 Core Value**（偷电 / 抢性能 / 变重）。

| Anti-Feature | 为什么会被要求 | 为什么有害 | 替代做法 |
|-------------|--------------|-----------|---------|
| **壁纸库 / 浏览 / 缩略图网格 / 搜索 / 分类** | 内容型 app 的标配，用户容易照搬 | 逼出账号+云+订阅+网络；用户**已明确不要** | 只留文件夹路径一行 + 一个状态计数 |
| **账号 / 登录 / 同步 / 订阅 / 内购** | App Store 品类惯例 | 直接违反"拷 .app 到别的 Mac 跑"的分发约束 | 完全不做 |
| **多显示器每屏独立配置** | iWallpaper 的**全部卖点**就是它 | PROJECT.md 已 Out of Scope；复杂度远超收益 | v1 只做主屏 |
| **网页 / YouTube / 摄像头当壁纸** | Wallpaper Play、Vidwall、Mural 都做，看着很酷 | 需要内嵌 `WKWebView`，永久联网，GPU 占用与我们的 Core Value **正面冲突** | 不做。要这类用别的工具 |
| **视觉效果栈**（调色、实时挂件、粒子、天气、音轨混音器） | Mural 的卖点 | GPU 预算直接爆掉，且无法关机 | 不做 |
| **屏保模式 / 锁屏视频壁纸** | 4K Live Wallpaper、Mural 都做 | 与"锁屏时暂停"这条需求**直接互斥** | 不做，锁屏就停 |
| **壁纸编辑器 / 创作工具** | Wallpaper Engine Editor（SceneScript） | 规模巨大，对"文件夹播放"零价值 | 不做 |
| **隐藏桌面图标 / 免打扰模式** | Dynamic Wallpaper Studio、4K Live Wallpaper、Dynamic Wallpaper Library 都有 | 要改 Finder 系统状态，副作用外溢；用户没要求 | 不做。系统原生"隐藏桌面图标"快捷键已够用 |
| **全局快捷键** | Dynamic Wallpaper Studio 有 | 单人自用价值低；引入 Carbon/辅助功能注册的权限摩擦 | 不做；菜单栏点击已足够快 |
| **下载 / 分享 / 导出壁纸** | 品类标配 | 引入网络 + 存储管理 | 不做 |
| **每个视频单独一套参数** | Wallpaper Engine 允许每个壁纸自带设置 | 会自然长出一个列表 UI —— 正是用户否掉的形态 | 全局一套配置 |

---

# Part B — 设置窗口信息架构（重点）

## B.0 总体结论

**一个 Settings scene，一个 Form，4 个 Section，无侧边栏，无主窗口。转码走独立 `Window` scene。**

```
┌─────────────────────────────────────────┐
│ Pic                                    🔘 │  ← Settings scene（自动获得 ⌘, 菜单项）
├─────────────────────────────────────────┤
│ 来源                                     │
│   文件夹   ~/Videos/Wallpapers    [选择…] │
│   状态     已找到 42 个视频 · 递归子目录    │
│ ─────────────────────────────────────── │
│ 播放                                     │
│   播放模式  [单循环][列表循环][列表随机]    │
│   轮换时间  每 10 分钟            [－][＋] │
│   播放速度  1.0×  ────────●────────     │
│ ─────────────────────────────────────── │
│ 声音                                     │
│   播放声音                        [ ●── ] │
│   音量      ──────●───────────────      │
│ ─────────────────────────────────────── │
│ 电源与系统                                │
│   电池供电时播放                  [ ──● ] │
│   开机自启                      [ ──● ] │
│ ─────────────────────────────────────── │
│ 其他                                     │
│   转码                              [转码…] │
└─────────────────────────────────────────┘
```

---

## B.1 分组设计：为什么是这 4 组

| Group | 内容 | 分组理由 |
|-------|------|---------|
| **来源** | 文件夹路径 + 选择按钮 + 状态行 | 单独成组，因为它是**唯一有状态的输入**（路径 + 扫描结果），且扫描失败要在原地报错 |
| **播放** | 模式 / 轮换 / 速度 | 三个都是"怎么播"，共用同一个心智模型 |
| **声音** | 出声 / 音量 | 声音是独立子系统，且需要"关掉后置灰"的联动 |
| **电源与系统** | 电池 / 开机自启 | 这两条都是**系统级副作用**，跟播放参数不是一回事，混在一起会让用户误以为影响播放 |

**不用侧边栏的理由**：只有 4 组、约 10 个控件，侧边栏会把 4 个 tab 撑成 4 次点击，而且 macOS 设置侧边栏惯例暗示"多个平级功能域"——我们只有一个。`TabView` + sidebar 在这种体量下是纯开销。

---

## B.2 逐控件映射 + 理由

| 设置项 | 控件 | 为什么是这个形态 |
|-------|------|----------------|
| 文件夹路径 | `LabeledContent` + `Button("选择…")` → `NSOpenPanel` | **不要用 TextField**。让用户手打路径是经典反模式，还得处理波浪号展开、权限、相对路径。`NSOpenPanel` 已实测可用（`canChooseDirectories=true` / `canChooseFiles=false` / `allowsMultipleSelection=false` / `canCreateDirectories=false` / `resolvesAliases=true`） |
| 递归子目录 | **不做成设置项** | PROJECT.md 已定为固定行为。做成可关的 toggle 是在给用户一个不该有的选择。用 footer 文案写死"包含子文件夹" |
| 已找到 N 个视频 | 状态行（`Text`，secondary） | 替代"视频列表"。用户要的是**确认扫到了**，不是**逐个挑**。这一行是"不要列表"和"要有反馈"之间的解 |
| **播放模式** | `Picker` + `.pickerStyle(.segmented)` | 3 个互斥短标签、常驻可见、一眼可切。`.radioGroup` 要占 3 行（Apple 文档自己在 macOS 示例里用过，但那是 2 项的老写法）；`.menu` 把当前值藏进下拉里，平白多一次点击。**三个选项的名字直接沿用 Dynamic Wallpaper Studio 的 "Single Loop / Playlist Loop / Shuffle"** |
| **轮换时间** | `Stepper(value:in:)` | 离散整数分钟，需要键盘可增减。**关键联动：单循环模式下必须 `.disabled(true)`** —— 只有一个视频时"轮换"无意义，置灰比报错或默默无效都好 |
| **播放速度** | `LabeledContent` + `Slider`，当前值写进 label（如"播放速度 1.0×"） | 连续量，需要滑杆。值必须可见 —— 滑杆单独放行看不出是 0.5 还是 1.5。`.timeDomain` 保持音高（已实测，见 B.5） |
| **播放声音** | `Toggle` | 布尔 → macOS 上自动渲染成开关。**绝不能包在 `LabeledContent` 里**（见 B.5 坑 #4） |
| 音量 | `LabeledContent` + `Slider`，`.disabled(!sound)` | 置灰直接表达依赖关系，不需要额外提示文案 |
| **电池供电时播放** | `Toggle`，默认 OFF | 布尔。默认 OFF 是品类惯例（见 Table Stakes） |
| **开机自启** | `Toggle` | 布尔。需处理 `.requiresApproval` 态（见 B.5 坑 #6） |
| **转码…** | `Button` → 打开独立 Window | 转码是**长任务**，不是设置值（见 B.3） |

**Form 样式**：`.formStyle(.grouped)` —— 这是现代 macOS 设置窗口外观。已实测可编译。
**不要在 Form 里混用 `GroupBox`**：inset-group Form 与 GroupBox 的内边距不一致，视觉会脏。`GroupBox` 只留给转码窗口。

---

## B.3 转码：独立窗口，不是 sheet，不是主窗口

**结论：独立 `Window` scene。**

| 方案 | 判断 |
|------|------|
| 塞进主窗口 | ✗ 我们**没有主窗口**（菜单栏 app），且转码会把这个窗口撑成完全不同的东西 |
| `sheet` | ✗ **明确反对**。转码是长任务（几十上百个文件），sheet 会锁死设置窗口、且进度条+逐文件状态在 sheet 里没地方放。sheet 适合"确认一个短操作"，不适合"跑一个任务" |
| **独立 `Window`** | ✓ 正确。设置窗口里只留一个「转码…」按钮触发；转码窗口可被关闭、可后台跑、可重新打开看进度 |

**转码窗口该有什么**（这是**唯一**允许出现列表的地方）：

- 目标文件夹 + 「选择…」
- 一个 `Table` / `List`：每个待转码文件的 **行**（不是壁纸库，是**任务队列**）
- 每行：文件名 / 状态 / 进度
- 「开始」「取消」「全部完成」

**关于"用户不要视频列表"的澄清**：用户否掉的是**浏览式**的视频列表/缩略图（用来挑壁纸）。转码队列是**操作产物**，一个输入任务的状态表，不违反该约束。建议在 Phase 计划里显式写清这条例外，免得后面被当成 scope creep 砍掉。

---

## B.4 窗口尺寸

| 项 | 建议值 | 理由 |
|----|--------|------|
| 设置窗宽度 | **固定 460pt** | 设置窗口宽度不该随内容回流；macOS 惯例窄而高 |
| 设置窗高度 | 默认 **560pt**，最小 **440pt** | 4 个 section + footer 在 560 内不滚动 |
| 最大尺寸 | 只设 **contentMaxSize 宽 460 / 高 720** | 不设 max 的话窗口能被拉到荒谬尺寸，显得没做完 |
| 是否需要 min | **需要**。`.frame(width:460, minHeight:440)` | 防止 section 被压扁 |
| 转码窗口 | 固定宽 ~640，高度**可自由调** | 表格行数不定，列表必须能滚动伸缩 |

`NSWindow.contentMinSize` / `contentMaxSize` / `center()` 均已实测存在于 macOS 27 SDK。

---

## B.5 明确不要的东西（用户已拍板）

- ❌ 视频列表
- ❌ 缩略图 / 预览网格 / 搜索框
- ❌ 每个视频的独立设置
- ❌ 设置窗口的侧边栏 / `TabView`
- ❌ 显示当前播放文件名
- ❌ 工具栏
- ❌ 分类、收藏、标签

---

## B.6 macOS 27 SwiftUI 已知坑（全部实测 / 文档实证）

> 标注 **[实测]** 的 = 在本机 macOS 27.0 SDK 上真编译验证过，不是文档抄的。

| # | 坑 | 等级 | 说明 |
|---|-----|------|------|
| 1 | **`AVPlayerItem` 没有 `rate` 也没有 `defaultRate`** | **[实测]** | 播放速度在 **`AVPlayer`** 上（`player.rate` / `player.defaultRate`，均可写）。写错会直接编译失败 |
| 2 | **保音高要设在 item 上** | **[实测]** | `item.audioTimePitchAlgorithm = .timeDomain`（保音高）。`.spectral` 也保音高；**`.varispeed` 是变调**（花栗鼠效应）。**`.lowQualityZeroLatency` 在 macOS 上 unavailable** —— 别照抄 iOS 代码 |
| 3 | **`SMAppService.register()` / `unregister()` 是 throwing** | **[实测]** | 必须 `try` + 错误处理。"开机自启"这个 toggle 不能想当然 |
| 4 | **`SMAppService.Status` 没有 `.disabled`** | **[实测]** | 实际四个 case：`notRegistered` / `enabled` / **`requiresApproval`** / `notFound`。`.requiresApproval` 表示用户还没在系统设置里批准 —— toggle 要能显示"需授权"并给出跳转，**不能当成失败** |
| 5 | **`NSWindow` 没有 `isIgnoringMouseEvents`** | **[实测]** | 在 **`NSView.ignoresMouseEvents`** 上。壁纸窗口要点击穿透，必须让 contentView 设这个。写错编译不过；写对了但设错层级，桌面就点不动了 |
| 6 | **`Toggle` 放进 `LabeledContent` 会变成 checkbox** | **[文档]** | Apple 文档原文：inset-group Form 里的 `Toggle` 默认渲染成 switch，但作为 `LabeledContent` 的 value 元素时会变成 checkbox。**永远别这么包** |
| 7 | **`MenuBarExtra` 被用户移除会自动终止 app** | **[文档]** | Apple 明确警告。我们是菜单栏独占 app，要设 `LSUIElement = true` 隐藏 Dock 图标 |
| 8 | **`Settings` scene 会自动启用「设置…」菜单项** | **[文档]** | 传 view 进 `Settings` 就会自动有。别再手动加一份，会重复 |
| 9 | **`SettingsLink` 是从 `MenuBarExtra` 打开设置的正路** | **[实测]** | macOS 14+。已开则置前，不会叠窗口 |
| 10 | **Command Line Tools 编不了 `@State`** | **[实测]** | 报 `SwiftUIMacros.StateMacro could not be found`。开发必须用完整 Xcode，不是 CLT。本机当前 `xcode-select` 指向 CLT，**开工前要先装/切 Xcode** |
| 11 | **macOS 的 `Form` 不是 iOS 的 grouped list** | **[文档]** | Apple 原文：macOS 上 Form 是**对齐的竖直堆叠**。而且 Apple 自己的 macOS 示例刻意**不用 section**、label 带冒号、picker 用 `.radioGroup`。我们的 `.formStyle(.grouped)` + `Section` 是更新式惯例，可行，但别拿 iOS 直觉套 |
| 12 | **不存在 `FormInspector` 这类"新式侧边设置"API** | **[实测，MEDIUM]** | 探测 `forminspector` / `forminspectorcontent` / `inspectorable` / `inspectors` 四个规范路径，全部 404，SwiftUI 文档索引里也没命中。**结论：没有现成的 inspector 式设置框架可套**，别按它做计划 |

**开工前的环境待办**：本机 `xcode-select -p` = `/Library/Developer/CommandLineTools`，**没有完整 Xcode**。项目约束是原生 SwiftUI app，Phase 1 之前必须解决，否则任何 SwiftUI 代码都编不动。（这是环境问题，不是设计问题，但会直接卡住开发。）

---

# Feature Dependencies

```
文件夹选择
  └──requires──> 递归扫描（枚举子目录 + 过滤 mp4/mov/m4v）
                       │
                       ├──requires──> 播放模式（三选一）
                       │                  └──requires──> 轮换时间（单循环时置灰）
                       │
                       ├──requires──> 播放速度（AVPlayer.rate + item.audioTimePitchAlgorithm）
                       │
                       └──enhances──> 转码（产出新文件 → 需用户手动「重新扫描」，
                                          因为 v1 不做自动监听文件夹增删）

电池供电开关 ──> 暂停状态机 ──┐
锁屏 / 熄屏 / 睡眠 ───────────┼──> 单一「该不该播」决策 ──> 壁纸窗口显隐
全屏应用 ────────────────────┘

开机自启 ──requires──> 代码签名（SMAppService 要求已签名）
设置窗口 ──requires──> 上述全部有稳定绑定（否则「立即生效」无处落地）
```

### Dependency Notes

- **设置窗口 requires 全部绑定稳定**：「改动立即生效」意味着设置层是**观察者**，不是"下次换片时读取"。这决定了设置绑定的架构，比窗口外观更影响 Phase 拆分。
- **暂停状态机 conflicts with 声音**：全屏/锁屏时暂停，音频也必须停 —— 但"暂停"与"音量=0"是两回事，恢复时要还原用户设的音量，不要记成 0。
- **转码 conflicts with 不自动监听**：转码产出新文件后不会自动进播放列表，必须显式提示"转码完成，重新扫描"。这是 v1 的已知摩擦，不是 bug。
- **开机自启 requires 签名**：不分发的开发阶段这个 toggle 是死的，Phase 规划时别把它排在签名之前验证。

---

# MVP Definition

## Launch With（v1）

- [x] 文件夹选择（递归）+ 状态计数 —— 唯一真相源
- [x] 三种播放模式 —— 品类惯例，Dynamic Wallpaper Studio 原词
- [x] 轮换时间（单循环时置灰）
- [x] 播放速度 + 保音高 —— 注意：rate 在 `AVPlayer`，pitch 在 `AVPlayerItem`
- [x] 出声 + 音量（联动置灰）
- [x] 电池供电时播放（默认关）
- [x] 开机自启（需手动设一次）
- [x] 暂停条件总闸（全屏/锁屏/熄屏/睡眠）+ 自动续播
- [x] 文件夹失效 → 露出系统壁纸
- [x] 菜单栏常驻 + 5 个菜单项（不含文件名）
- [x] 设置窗口 4 组 IA
- [ ] 转码 —— **独立窗口**，但可排在核心播放之后

## Add After Validation（v1.x）

- [ ] 转码管线落地（保画质机制定案后）—— 触发条件：核心播放稳定跑一周
- [ ] 轮换时间支持"按时间段"（Wallpaper Engine 有，Irvue 有 30min/1h/3h/... 的预设档）—— 触发条件：用户实际嫌 Stepper 慢

## Future Consideration（v2+）

- [ ] 多显示器 —— **建议不做**。iWallpaper 的整个价值主张就是这个，做了就得全面超越，收益不匹配自用定位
- [ ] 裁剪方式可调（fill / fit / 居中）—— VideoPaper 有；我们先只做 fill

---

# Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| 文件夹选择 + 递归 | HIGH | LOW | **P1** |
| 菜单栏常驻 + 不退出 | HIGH | MEDIUM | **P1** |
| 三种播放模式 | HIGH | LOW | **P1** |
| 暂停条件总闸 | HIGH | MEDIUM | **P1** |
| 文件夹失效 → 露系统壁纸 | HIGH | LOW | **P1** |
| 音量 + 出声 | MEDIUM | LOW | **P1** |
| 设置窗口 4 组 IA | HIGH | LOW | **P1** |
| 电池供电开关 | HIGH | LOW | **P1** |
| 轮换时间（联动置灰） | MEDIUM | LOW | **P1** |
| 播放速度 + 保音高 | MEDIUM | MEDIUM | **P2** |
| 开机自启 | MEDIUM | LOW（但需签名） | **P2** |
| 转码（独立窗口） | MEDIUM | HIGH | **P3** |
| 裁剪方式可调 | LOW | LOW | **P3** |

---

# Competitor Feature Analysis

| Feature | VideoPaper (id6587549333) | Dynamic Wallpaper Studio (id1453504509) | 4K Live Wallpaper (id1469182113) | iWallpaper (id1552826194) | **Pic（我们）** |
|---------|------------------------|---------------------------------------|----------------------------------|----------------------|---------------|
| **来源模型** | 本地文件 **或 文件夹引用** | 壁纸库 + 导入本地 | 壁纸库 + 导入本地 | 云端库（CloudKit） | **纯文件夹 + 递归** |
| 播放模式 | 未明示 | Single Loop / Playlist Loop / **Shuffle** | 未明示 | 未明示 | **同上，沿用原词** |
| 播放速度 | ✅ 可调 | ❌ | ❌ | ❌ | **✅ 保音高** |
| 音量 / 音频 | ❌ | ❌ | ❌ | ❌ | **✅ + 保音高变速** |
| 电池策略 | ❌ | Smart Pause（拔电/闲置） | 断电即停 | 电池转静态省电 | **✅ 可开关，默认关** |
| 全屏暂停 | ❌ | Smart Pause（其他 app 活跃） | ✅ 全屏即停 | 遮挡即停 | **✅** |
| 多屏 | ✅ 每屏独立 scale/对齐/速度 | ✅ 每屏不同壁纸 | ✅ | ✅ **主卖点** | ❌（v1 Out of Scope） |
| 转码 | ❌ | ❌ | ❌ | ❌ | **✅ 全品类无人做** |
| 网络 / 账号 | ❌ | ❌ 订阅制 | ❌ 订阅制 | ✅ CloudKit | **❌ 全离线** |
| 隐藏桌面图标 | ❌ | ✅ 免打扰模式 | ✅ | ❌ | ❌（有意不做） |
| 网页/摄像头壁纸 | ❌ | ❌ | ❌ | ❌（Wallpaper Play、Vidwall 有） | ❌（有意不做） |

**最接近的对标是 VideoPaper**（同为菜单栏 + 文件夹 + 可调速度 + 交叉淡入的本地工具型 app）。**但我们比它多**：电池策略、全屏暂停、转码、变速保音高。它比我们多：多屏 per-screen 配置。

---

# Sources

**一手（实时抓取，HIGH）**
- Apple iTunes Search / Lookup API（US + CN，2026-10-02）—— `itunes.apple.com/search?term=...&entity=macSoftware`、`itunes.apple.com/lookup?id=...`。竞品功能**全部来自开发者自己在 App Store 写的描述**，非二手转述。
- Apple 开发者文档 JSON 端点（`developer.apple.com/tutorials/data/documentation/swiftui/{form,settings,settingslink,menubarextra,section,groupbox,labeledcontent,formstyle}.json`）
- 本机 SDK 头文件：`/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks/ServiceManagement.framework/Headers/SMAppService.h`
- **编译探针**（`swiftc -typecheck -target arm64-apple-macosx27.0`，一次性，产物已丢弃）：`/tmp/probe-pic/probe{,2,3,4}.swift` —— 验证坑 #1~#5、#9~#12。**这是调研期 demo，不是生产代码。**

**二手（MEDIUM）**
- wallpaperengine.io 首页 + help.wallpaperengine.io（仅 Windows 功能参考）

**未找到公开资料**
- **Wallpaper Engine 完整设置项清单** —— 帮助站所有路径都返回同一个落地页（SPA 路由），未能逐页抓取；其 macOS 状态已从产品形态确认。
- **任何 macOS 版 "Wallpaper Engine 等价物" 的官方设置规范** —— 无此物，品类无统一规范可抄。
- **macOS 27 上 `.formStyle(.grouped)` + `Section` 的实际渲染效果** —— 需运行 app 目视确认，本次仅静态验证。

---

*Feature research for: macOS 视频动态壁纸*
*Researched: 2026-10-02*