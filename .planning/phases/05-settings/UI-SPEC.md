---
phase: "5"
slug: "05-settings"
status: draft
shadcn_initialized: false
preset: none
created: "2026-10-03"
---

# Phase 5 — UI Design Contract（设置窗口与即时生效）

> 本文件把**全局 UI-SPEC（`.planning/UI-SPEC.md`，权威设计源，只读）**翻译成 Phase 5 的可执行、可验证契约。
> 冲突裁决顺序：全局 UI-SPEC > 本文件 > spike 现状。spike（`.planning/spike/SettingsSpike.swift`）是已编译渲染的起点，**不是**契约本身 —— 它与全局稿的已知差异在 §13 列出，其中 executor 必须补齐的已标注。
> 本 Phase 覆盖需求：SOURCE-04 · UI-01~04 · PLAY-07~10 · MENUBAR-02 · MENUBAR-06（断言锚点 TEST-04 / TEST-07~10）。

---

## Design System

| Property | Value |
|----------|-------|
| Tool | none —— 原生 macOS SwiftUI（非 React/Next/Vite，shadcn 门不适用，无 components.json） |
| Preset | not applicable |
| Component library | SwiftUI（macOS 27 SDK）+ AppKit，第一方；**零第三方 UI 依赖** |
| Icon library | SF Symbols（UI-SPEC §11 已接受与手绘 SVG 的形状差异，不追 100% 一致） |
| Font | **系统默认（2026-10-03 用户拍板，不打包字体文件）** —— 等宽文本（数值/副标签/节标题/按钮）用 `.system(design: .monospaced)`（系统等宽，SF Mono）；行标题用系统默认字体。原「打包 IBM Plex Mono」项已取消，无回退路径 |

---

## Component Inventory

Could not enumerate by package command: 本项目是原生 SwiftUI app —— 无 npm/SPM 设计系统包、无 components.json 可枚举。下表来自**已编译、已渲染**的 spike（`.planning/spike/SettingsSpike.swift`，2026-10-03 经 `swiftc -parse-as-library -target arm64-apple-macosx15.0` 编译 + `ImageRenderer` 渲染验证，截图 `.planning/design/shots/spike-v3.png`），非凭记忆召回。

**这是 Phase 5 的已知可用基线（非封闭清单）。** 系统 SwiftUI 原生控件当然可用；但**不得新增自造组件**（见 §10 自造成本锁定）。

| Component | 来源（spike 行号区间） | Notes |
|-----------|----------------|-------|
| `Color` 扩展（pBg/pFg/pAccent/pAccFg/pCard/pSep/pEdge/pGlow/pWarn/pWarnGlow/pDim） | 5–17 | B1 深海令牌，照抄全局 UI-SPEC §3；注意 spike 曾把 pSep 调到比全局更深的值（深色下更可见），契约照抄全局 0.16 |
| `mono(_:_:)` 字体助手 | 18–20 | 系统等宽（`.system(design: .monospaced)`）—— 2026-10-03 拍板字体用系统默认，不换打包字体 |
| `Tile` | 23–41 | 图标瓷砖 26×26 圆角 6，双阴影发光；`warn: true` 切换警告配色 |
| `GlowToggle: ToggleStyle` | 44–59 | 40×23 开关，开态 accent + 发光 |
| `GlowSlider` | 62–89 | `DragGesture` 自绘滑杆 92×18，轨高 4，手柄 14 |
| `GlowSegmented` | 92–113 | 自绘分段控件（`.tint()` 对 macOS 分段控件着色有限，已定自绘） |
| `GlowStepper` | 116–138 | ▲▼ 步进器 + 中间数值框 |
| `Row` | 141–163 | 行结构：Tile + 标题 + 副标签 + 控件，minHeight 42，底部 hairline |
| `SectionHead` | 165–173 | 节标题（uppercase + tracking） |
| `Card` | 176–183 | **无 clipShape**（§13 坑 1），background + overlay 描边 |
| `Hint` | 185–191 | 卡片下方灰色说明行 |
| `GlowButton: ButtonStyle` | 318–330 | 次按钮（描边）与主按钮（accent 实心） |

---

## Spacing Scale

**本窗不套用通用 8pt 网格 —— 间距体系是全局 UI-SPEC + spike 定稿的固定「仪表盘网格」。** 以下是**封闭的合法值集合**，executor 不得发明新值：

| Token | 值（pt） | 用途 |
|-------|---------|------|
| hairline | 1 | 卡片内行分隔线 |
| tileGap | 12 | 图标瓷砖↔文字；标签组↔控件组（L4「紧跟」间隙，**不是** space-between） |
| titleSubGap | 1 | 行标题↔副标签 |
| cardGap | 12 | 卡片之间 / SectionHead 与卡片 |
| windowPad | 14 | 窗口四周内边距；双列间距 |
| rowPadH | 13 | 行水平内边距 |
| rowMinH | 42 | 行最小高度 |
| tile | 26×26（圆角 6） | 图标瓷砖 |
| cardRadius | 10 | 卡片圆角 |
| segRadius / btnRadius | 7 | 分段控件 / 按钮圆角 |
| slider | 92×18（轨 4 / 手柄 14） | 滑杆 |
| toggle | 40×23（手柄 19，圆角 11.5） | 开关 |
| btnPadH / btnPadV | 12 / 4 | 按钮内边距 |

Exceptions（相对「4 的倍数」原则）: windowPad 14、rowPadH 13、rowMinH 42、tile 26 —— 这些是**全局 UI-SPEC 自己的数字**（§4「固定 12pt 间隙」、§5「26×26 瓷砖」），归一化到 4 的倍数会违反权威设计源。封闭集合本身即为防漂移约束。

---

## Typography

| Role | Size | Weight | Font | Line | Usage |
|------|------|--------|------|------|-------|
| Micro | 10.5 | 400 | 系统等宽（.monospaced()） | 单行 | 副标签（路径、「音高不变」「默认关」）、Hint 行 |
| SectionHead | 10.5 | 600 | 系统等宽（uppercase + tracking 1.3pt） | 单行 | 四个节标题 |
| Value | 11.5 | 400 | 系统等宽（.monospaced()） | 单行 | 控件旁数值（`1.00×`、`60%`、`15 分钟`）、按钮文字 |
| Label | 12.5 | 400 | 系统默认字体 | 单行 | 行标题（文件夹、模式、轮换…） |
| Display | 20 | 600 | 系统等宽（.monospaced()） | 单行 | 计数数字（正常 accent / 空态 warn） |

- **恰好 2 个字重**：400 regular + 600 semibold。
- 与 spike 的两处归一（半点差异，10.5pt 下视觉不可辨，契约以本表为准）：spike 的 11pt 读数 → 统一 11.5；spike 节标题的 `.medium`(500) → 统一 semibold(600)。
- 所有行文本 `lineLimit(1)`；路径截断规则见 §14 overflow。

---

## Color（B1 深海 —— 照抄全局 UI-SPEC §3）

| Role | Value | Usage |
|------|-------|-------|
| Dominant (60%) | `#0A1826` | 窗口底 |
| Secondary (30%) | `rgba(13,32,52,0.92)` 卡片底 + 顶部 LinearGradient `rgba(76,196,245,0.14)`→40% 渐隐 + 右下 RadialGradient 补光 | 卡片、环境光 |
| Accent (10%) | `#4CC4F5`（accentFg `#04202E`） | 见下方 reserved-for 清单 |
| Warn | `#F5B544`（warnGlow `rgba(245,181,68,0.30)`） | **空态专用**（数字、感叹号瓷砖）；**非 destructive** —— 本 Phase 无破坏性操作 |
| fg / fgMuted | `#DCE8F4` / 60% | 主文字 / 副文字 |
| sep / edge / glow | `rgba(90,170,240,0.16)` / `rgba(90,190,255,0.32)` / `rgba(76,196,245,0.32)` | 分隔线 / 描边 / 发光 |

**Accent reserved for（穷举）**：分段控件选中段填充；滑杆填充与手柄拖动态发光；开关开态填充+发光；主按钮（转码「打开…」）填充；次按钮文字（选择…/重新扫描/扫描）与描边；计数数字（正常态）与呼吸圆点；步进器 chevron 与数值文字；环境光渐变（低透明度）。**禁止**用于：正文文字、行标题、卡片底（那些用 fg / fgMuted / card）。

**动画红线**：呼吸渐变 10s（opacity 0.5↔1.0）**只在设置窗打开时跑**，`@Environment(\.accessibilityReduceMotion)` 为真时关闭；发光不做常驻动画（吃 GPU）。

---

## Copywriting Contract

| Element | Copy |
|---------|------|
| Primary CTA | **「选择…」** —— 选择壁纸来源文件夹（复用 Phase 4 的 `NSOpenPanel`，含递归子目录说明） |
| 次按钮 | 「重新扫描」（来源卡）/「扫描」（维护卡，同一动作）/「打开…」（转码窗口入口） |
| 菜单入口 | 「打开设置 ⌘,」（MENUBAR-06） |
| Empty state heading | 计数数字 `0` + 「个可用视频」——数字转 warn `#F5B544` + warnGlow，圆点换 `exclamationmark` 警告瓷砖 |
| Empty state body | **「没找到能播的文件。壁纸已隐藏，桌面显示的是系统原壁纸。」** —— 逐字硬需求（UI-02），产品决策「露出系统壁纸」必须说清 |
| Error state | 本窗**无错误弹窗**：文件夹未配置 / 被删 / 扫到 0 共用上述空态文案（三态一张皮，见 §8）；ffmpeg 缺失时运行状态卡显示「未安装」，完整安装指引属 Phase 6（TRANS-02，且 macOS 27 上 brew 会失败，必须给静态二进制途径） |
| Destructive confirmation | **无** —— 本 Phase 无破坏性操作，不做任何确认弹窗 |

---

## 布局与控件映射（L4 双列 → Phase 5 数据绑定）

**核心 L4 规则**：标签左对齐、控件紧跟其后（`Spacer(minLength: 12)` 撑开），**不是** macOS 系统设置的「标签右对齐成槽」——这是用户在 L1–L4 里选 L4 的结果，**禁止改回 space-between**。

**窗口**：单个 Settings scene；宽 **780pt 固定**、min 宽 **680pt**、高随内容（`.fixedSize(horizontal: false, vertical: true)`，**不写死**）；标准标题栏（标题「Pic 设置」）；**无侧边栏**。

| 列 | 卡片 | 行（图标 SF Symbol · 标签 · 副标签 · 控件） | 数据绑定（读/写） |
|----|------|------|------|
| 左 | 壁纸来源 | `folder.fill` · 文件夹 · 当前路径（middle 截断）· GlowButton「选择…」 | `SettingsStore.sourceFolder`（写：NSOpenPanel 选完 → persist → 立即重扫） |
| 左 | 壁纸来源 | 呼吸圆点（accent）或 `exclamationmark` 警告瓷砖 · **N 个可用视频** · GlowButton「重新扫描」 | 读：`MediaLibraryReport.playableCount`；触发：重扫 → `MediaCoordinator.apply` |
| 左 | 播放 | `repeat` · 模式 · GlowSegmented「单循环/列表循环/随机」 | `SettingsStore.playMode`（`PlayMode.allCases` 顺序渲染，见 §11）+ `RotationController.mode` 当场生效 |
| 左 | 播放 | `timer` · 轮换 · GlowStepper（5/10/15/30/60/120 分钟，≥60 显示「N 小时」） | `SettingsStore.rotationInterval`（秒；UI 分钟×60）；`mode == .loopSingle` → **整行 disabled + opacity 0.34** |
| 左 | 播放 | `gauge.with.dots.needle.67percent` · 速度 · 副标签「音高不变」· GlowSlider 0.5–2.0 + 数值 `1.00×` | `SettingsStore.rate` + `PlayerController.setRate`；音高见 §9 SC-4 |
| 左 | 播放 | `speaker.wave.2.fill` · 声音 · GlowSlider 0–100 + 数值 `60%` + GlowToggle | `SettingsStore.volume`（Float 0–1 ↔ UI 0–100 映射）+ `PlayerController.setVolume`；Toggle ↔ `SettingsStore.isMuted` + `PlayerController.setMuted`；`isMuted` → **滑杆 disabled + opacity 0.34** |
| 右 | 电源与系统 | `battery.75` · 电池时播放 · 副标签「默认关」· GlowToggle | `SettingsStore.pauseOnBattery`（默认 false） |
| 右 | 电源与系统 | `power` · 开机自启 · GlowToggle | **本地 @State，不持久化** —— `SettingsStore` 无此键（7 键冻结）；行为接线 Phase 7（见 §12） |
| 右 | 维护 | `arrow.triangle.2.circlepath` · 重新扫描 · GlowButton「扫描」 | 同「重新扫描」动作（spike 缺此行，executor 补齐，见 §13） |
| 右 | 维护 | `arrow.left.arrow.right` · 转码 · 副标签「MKV / AVI → MP4」· GlowButton primary「打开…」 | **Phase 5 渲染 + disabled 占位**（副标签追加「待后续版本」）；Phase 6 接线（§12） |
| 右 | 运行状态 | `pause.circle.fill`（播放中 `play.circle.fill`）· 已暂停/播放中 · 副标签=当前原因 | `PlaybackDecision.holds` / `HoldArbiter.holdStatus`（见 §8 映射表） |
| 右 | 运行状态 | `checkmark.seal.fill` · ffmpeg · 副标签「9.0.2 · 可用」/「未安装」 | PATH 探测（版本串 + 可用性） |

卡片下方 Hint：左列「递归扫子目录 · 只认 MP4 / MOV / M4V」；右列「全屏 / 锁屏 / 熄屏 / 睡眠时自动暂停」。

---

## 状态契约

### 正常态（populated）
计数 = **accent 发光大数字（20pt semibold）** + 呼吸圆点 + 「个可用视频」；副标签可含「上次扫描 HH:MM」（本会话未扫过则省略）。

### 空态（SC-2 / UI-02）—— 必须有
触发条件：`MediaCoordinator.lastState ∈ {folderUnconfigured, folderMissing, noPlayableVideos}`（三态一张皮，UI 不区分）：
- 数字转 **warn `#F5B544`**，发光换 `warnGlow`
- 圆点换 `exclamationmark` 瓷砖（`#F7C463 → #C47A10` 渐变）
- 副行文案逐字：**「没找到能播的文件。壁纸已隐藏，桌面显示的是系统原壁纸。」**
- **「重新扫描」按钮保持可用**（它是恢复路径，不置灰）

### 置灰联动（SC-3 / UI-03）—— 恰好两条
1. `playMode == .loopSingle` → **轮换整行**（步进器）置灰
2. `isMuted == true` → **音量滑杆**置灰

置灰 = `.disabled(true)` **且** opacity 0.34 —— **禁用交互，不是只调透明度**。选置灰不选隐藏（隐藏让人怀疑自己记错了）。切换回列表循环/随机、开声音后恢复可用。

### 运行状态卡（SC-5 / UI-04）
暂停原因文案映射（穷举，`HoldReason` 全 6 case）：

| HoldReason | 副标签文案 |
|------------|-----------|
| `manualPause` | 手动暂停 |
| `fullscreen` | 检测到全屏应用 |
| `screenLocked` | 屏幕已锁定 |
| `displayAsleep` | 显示器已熄屏 |
| `systemSleeping` | 系统正在睡眠 |
| `battery` | 电池供电中 |

- `holds` 非空 → 标题「已暂停」，副标签 = 原因列表按 `HoldReason.order` 排序、顿号连接（veto set 下多原因叠加必须全列，否则用户误判 bug —— PAUSE-07 的 UI 落点）
- `holds` 空 → 标题「播放中」，图标 `play.circle.fill`
- ffmpeg 行：PATH 探测到 → 「{版本} · 可用」；否则「未安装」

---

## Success Criteria → 可验证 UI 契约

> 断言风格沿用项目既有纪律：行为断言优先（单测/XCUITest/探针），**禁止源码字面量 grep 当判据**（Phase 3 D-07）。XCUITest 需要 `.xcodeproj` —— Phase 2 D-01 已定**本 Phase 引入 Xcode 工程**。屏幕锁定导致无法目视的项目照旧标 BLOCKED 继续，不阻塞。

### SC-1 窗口（780pt / B1+L4 / 无侧边栏 / 关窗不退出）
**满足**：菜单栏「打开设置」打开单窗；宽 780 固定、min 680；高随内容不写死；无侧边栏；B1 皮肤 + L4 双列（左：来源/播放，右：电源与系统/维护/运行状态）；标准标题栏；关窗只隐藏（`orderOut`），进程不退、菜单栏图标仍在。
**断言**：探针读 `NSWindow.frame.width == 780`、`contentMinSize.width == 680`（`WINDOW_WIDTH=780` / `MIN_WIDTH_ENFORCED=1`）；XCUITest（TEST-07 前置）确认窗口存在且无侧边栏元素；关窗后 `pgrep` 进程存活 + `NSApp.activationPolicy == .accessory`（MENUBAR-02，`PROCESS_ALIVE_AFTER_CLOSE=1`）；截图对照 `.planning/design/shots/spike-v3.png`（有真实标题栏）。

### SC-2 空态（SOURCE-04 / UI-02 / TEST-09）
**满足**：见 §8 空态 —— warn 色 + 感叹号瓷砖 + 逐字文案。
**断言**：① 纯函数单测：`LibraryState → 空态视图模型`（颜色 token、tile warn 标志、文案常量）三态逐一断言；② XCUITest：指向空 fixture 目录启动（复用 Phase 4 fixture 机制）→ 断言文案存在、warn 元素存在；③ 文案用**常量字符串相等**断言（不是 contains 子串）。

### SC-3 置灰联动（UI-03 / TEST-08）
**满足**：见 §8 两条联动，`.disabled(true)` + opacity 0.34。
**断言**：① 单测：联动条件纯函数（`playMode → rotationEnabled`、`isMuted → volumeEnabled`）；② XCUITest：选「单循环」后步进器 `isEnabled == false` 且点击不改 `rotationInterval`；关声音后滑杆 `isEnabled == false`；切回列表循环/开声音后恢复 —— **「不可点」必须以交互不生效为准，不以视觉变淡为准**。

### SC-4 速度/声音当场生效 + 重启保留（PLAY-07~10 / TEST-04）
**满足**：拖速度滑杆（0.5×–2×）→ `AVPlayer.rate` 当场变；音量/声音开关当场变；不重启、不等换片；改完 `persist()`；重启读回。**保音高**：`audioTimePitchAlgorithm = .spectral`；该属性变更需**重建 `AVPlayerItem`**，重建后 seek 回 resumeAnchor（不从头播）。`rate`/`volume` **挂 `AVPlayer`，绝不挂 `AVPlayerItem`**（looper 副本 init 时冻结，挂 item 会让「立即生效」变成假的 —— Phase 2 D-13）。
**断言**：① TEST-04 单测：`SettingsStore` 存取/默认值/7 键 persist；② 行为断言：改 rate 后探针读 `PIC_RATE=`（无重启、无换片）；重启进程后回读持久值；③ 拖动实时生效（拖动中 onChanged 更新，`persist()` 在拖动结束调一次 —— 生效针对播放器，写盘节流不违反 PLAY-10）；④ **「0.5×/2× 人声不变调」是人工听音项** —— 自动化无法覆盖，列入 UAT 人工清单，诚实标注（不许拿参数设对了冒充听过了）。

### SC-5 运行状态卡（UI-04）
**满足**：见 §8 运行状态卡 —— 暂停与否 + 原因列表 + ffmpeg 可用性。
**断言**：① 单测：原因→文案映射纯函数（全 6 case + 多原因叠加的排序与连接）；② 渲染层用注入假 `PlaybackDecision` 的快照/视图模型断言；③ 一次活体验证：锁屏态开设置窗看到「屏幕已锁定」（屏幕锁着做不了就标 BLOCKED 事后补，照旧例）；④ ffmpeg 探测：PATH 探测结果 → 行文案（本机 ffmpeg 9.0.2-tessus 为阳性基准）。

---

## 自造成本（锁定清单 —— **不再新增**）

全局 UI-SPEC 定稿 + PROJECT.md「最小代码量」的张力已在 §Context 记录：两处自造是**已拍板的可接受成本**（约 80 行），同时也是**第一顺位可砍项**。Phase 5 契约：

| # | 自造项 | 理由（现成的为什么不能用） | 状态 |
|---|--------|--------------------------|------|
| 1 | `GlowSlider`（DragGesture 自绘，~40 行） | SDK 27 个 `*Style` 协议里**没有 `SliderStyle`**（grep 0，写出来编不过）；`.tint()` 只能改填充色 | spike 已实测 |
| 2 | `GlowSegmented`（自绘分段） | `.tint()` 对 macOS 分段控件着色范围有限 | spike 已实测 |

**字体：系统默认（2026-10-03 用户拍板，不打包字体文件）** —— 原第 3 项「打包 IBM Plex Mono」取消：等宽文本用 `.monospaced()` 系统等宽，正文用系统默认，零字体文件、零注册代码、零供应链面。

`GlowToggle` / `GlowStepper` / `GlowButton` / `Tile` / `Row` / `Card` / `SectionHead` / `Hint` 都是 spike 已实测组件 —— **照搬复用，不算新增自造**。规则：任何新控件先问「SwiftUI 原生 + `.tint()` 能不能凑合」；答案是否时才有资格进本表，且本表现在关闭。

---

## 接口依赖（冻结接口，只读不改签名）

| 接口 | 来源 | UI 怎么用 |
|------|------|----------|
| `SettingsStore`（7 字段 + `persist()` + `resolvedFolderURL()`） | Phase 2 冻结（`Sources/PicCore/State/SettingsStore.swift`；04-02 D-03：7 键不得增删） | 全部 6 个可调项的读写 + 改完 `persist()`。⚠️ `volume` 是 Float 0–1，UI 是 0–100 |
| `PlayerController`（`setRate` / `setVolume` / `setMuted`；rate/volume 挂 AVPlayer） | Phase 2 冻结（04-01 D-01 公开面） | 速度/音量/静音的「当场生效」落点 |
| `HoldArbiter` / `PlaybackDecision`（`holdStatus` / `holds` / `activeReasons` 已排序） | Phase 2 冻结 + Phase 3 扩展 | 运行状态卡的「是否暂停 + 原因列表」数据源 |
| `HoldReason`（全 6 case + `order` 0–5） | Phase 3（`Sources/PicCore/State/HoldReason.swift`） | 原因→文案映射（§8 表）；排序用 `order`，**只用于文案排序，不参与播放决策**（D-10） |
| `PlayMode`（`loopSingle/loopList/shuffle`，`allCases` 顺序冻结） | Phase 4 04-02 | 分段控件**按 `allCases` 顺序渲染**（04-02 T1 有单测锁序）；`loopSingle` 是置灰联动条件之一 |
| `RotationController`（`mode` 可读写直接生效） | Phase 4 04-02 | 模式切换的当场生效落点（不存第二份） |
| `MediaLibraryReport.playableCount` | Phase 4 04-01 | 计数数字 |
| `LibraryAvailability` / `LibraryState`（4 态 + `reasonToken`） | Phase 4 04-03 | 空态判定（`folderUnconfigured/folderMissing/noPlayableVideos` 三态一张皮） |
| `MediaCoordinator`（`apply(scanOutcome:folderConfigured:)` + `lastState` + `onStateChange`） | Phase 4 04-03 | 「选择…」/「重新扫描」后的重扫管线；`onStateChange` 驱动计数与空态刷新 |

**分层纪律**（继承 Phase 3/4，`test.sh` 有判据锁着）：`State/` 禁 AVFoundation；`Media/` 禁 AppKit/SwiftUI。设置窗的 SwiftUI 视图属 app 装配层（`AppDelegate.wiring()` 唯一装配点，D-10），**不进** `State/` 或 `Media/`。

---

## 行为接线归属（渲染在此、接线在后的，明确记账）

| 控件 | 渲染 | 行为接线 | 说明 |
|------|------|----------|------|
| 6 个可调项（模式/轮换/速度/音量/声音/电池） | **Phase 5** | **Phase 5**（当场生效 + persist） | 本 Phase 核心 |
| 开机自启 Toggle | **Phase 5**（本地 @State，不持久化 —— 7 键冻结不加第 8 键） | **Phase 7 SYS-01**（`SMAppService` 未签名行为待实测，退路 LaunchAgent plist） | 代码内注释标 `// 行为接线：Phase 7 SYS-01` |
| 转码「打开…」按钮 | **Phase 5**（disabled 占位 + 副标签「待后续版本」） | **Phase 6**（转码窗口 + ffmpeg 缺失置灰指引） | 不做空窗口 |
| ffmpeg 完整安装指引 | **Phase 5** 只显「未安装」 | **Phase 6 TRANS-02**（多途径：brew + 静态二进制） | 状态卡只报可用性 |
| 菜单栏其余 4 项（暂停/下一个/重扫/退出） | 不在本窗 | Phase 2/4 已有 | MENUBAR-06「打开设置」是本 Phase 唯一新增菜单接线 |

---

## 已知坑（继承全局 UI-SPEC §9/§11 —— 别再踩）

1. **`Card` 上禁用 `.clipShape(RoundedRectangle)`** —— 它把图标瓷砖的外发光在卡片边缘裁掉。改用 `background` + `overlay` 描边（spike 已修）。
2. **不写死窗口高度** —— 写死会留一截空白。用 `.fixedSize(horizontal: false, vertical: true)`，780×~390 按内容撑（spike 已修）。
3. **`rate`/`volume` 挂 `AVPlayer` 不挂 `AVPlayerItem`** —— looper 副本 init 时冻结，挂 item 让「立即生效」变假（Phase 2 D-13）。
4. **`audioTimePitchAlgorithm` 变更需重建 `AVPlayerItem`** —— 重建后 seek 回 resumeAnchor，不从 头播。
5. **发光 = 阴影 + 模糊，吃 GPU** —— 只在窗开着时跑，不做常驻动画，尊重 reduced-motion。
6. **`AVPlayerLooper` 副本冻结** → 音量/速度全部经 `PlayerController` 公开面，UI 不直接摸 player。

### spike 与契约的已知差异（executor 必须补齐的加粗）

| 差异 | 处置 |
|------|------|
| 字体是系统等宽（SF Mono） | moot —— 2026-10-03 拍板字体改系统默认，spike 的 `.monospaced()` 即终态，不再是待补齐差异（原「打包 IBM Plex Mono」项已取消） |
| **维护卡缺「重新扫描」行**（全局 §5 有、spike 没画） | **补齐**：加一行 `Row`（`arrow.triangle.2.circlepath` + 「扫描」按钮，同一重扫动作） |
| 转码按钮可点（空 action） | **改为 disabled 占位**（§12） |
| 分段控件比 HTML 稿略窄 | 微调即可，非阻塞 |
| 计数/开关等全是 @State 假数据 | **全部换成 §11 冻结接口的真绑定** |
| 无标题栏 | `ImageRenderer` 限制；真实 app 有红绿灯标题栏，非缺陷 |

---

## UI Considerations

Applicable state considerations resolved: 9 covered, 1 backstop, 0 unresolved.

| Category | Element(s) | Status | Resolution / Reason |
|----------|------------|--------|---------------------|
| empty | 来源-计数行（form） | ✅ covered | count 0 → warn 空态（文案见 Copywriting Contract，逐字） |
| empty | 文件夹未配置/被删（form） | ✅ covered | 与 0 个视频共用同一空态皮（`LibraryState` 三态合一，UI 不区分） |
| loading | 扫描进行中（interactive-control） | ✅ covered | 保留旧计数、无 spinner（最小代码决定：扫描通常秒级）；扫描期间「选择…/重新扫描/扫描」`.disabled` 防重入 |
| error | 扫描失败（form） | ✅ covered | 无错误弹窗；`folderMissing` 走空态皮，干净降级是产品决策不是故障 |
| populated | 计数 N>0（media） | ✅ covered | accent 发光数字 + 呼吸圆点 + 「个可用视频」 |
| partial | 混入不可播文件（form） | ✅ covered | 只显 `playableCount`（Phase 4 已用 AVURLAsset 滤掉解不出视频轨的） |
| overflow | 长路径（static-content） | ✅ covered | 副标签 `lineLimit(1)` + `truncationMode(.middle)`（保留文件名，掐中间） |
| zero-one-many | 计数（form） | ✅ covered | 中文无单复数形变；N=1 与 N=999 同布局，数字宽度自适应不锁死 |
| reduced-motion | 呼吸/发光（domain-probe 项） | ✅ covered | `accessibilityReduceMotion` 为真时停呼吸动画与发光脉动 |
| long-text | 深路径 + 长 ffmpeg 版本串（static-content） | 🧪 backstop | 目测 hold-out：极深路径与异常长版本串不破行、不推挤控件（ lifts 为 backstop 验证项） |

---

## Registry Safety

| Registry | Blocks Used | Safety Gate |
|----------|-------------|-------------|
| （无） | — | not applicable —— 原生 SwiftUI，无第三方 UI registry。字体用系统默认（2026-10-03 拍板），不打包任何字体文件，非 registry 组件 |

---

## Checker Sign-Off

- [ ] Dimension 1 Copywriting: PASS
- [ ] Dimension 2 Visuals: PASS
- [ ] Dimension 3 Color: PASS
- [ ] Dimension 4 Typography: PASS
- [ ] Dimension 5 Spacing: PASS
- [ ] Dimension 6 Registry Safety: PASS
- [ ] Dimension 7 Inventory Provenance: PASS

**Approval:** pending

---

## 来源记账（Pre-Populated From）

| 来源 | 用到的决策 |
|------|-----------|
| 全局 `.planning/UI-SPEC.md`（权威，只读） | B1 令牌 · L4 规则 · 窗口尺寸 · 控件清单 · 空态文案 · 置灰规则 · §9/§9.5/§11 全部实现约束 |
| ROADMAP Phase 5 | 5 条 SC 的契约化 · 接口依赖 · 自造成本锁定 · 接线归属 |
| `.planning/spike/SettingsSpike.swift` | 全部组件基线 · 间距/字号的实测值 · 已修的 2 个坑 · 运行状态卡 |
| REQUIREMENTS.md | SOURCE-04 / UI-01~04 / PLAY-07~10 / MENUBAR-02·06 / TEST-04·07~10 的断言锚点 |
| Phase 2/3/4 CONTEXT + 04-02/04-03 PLAN | 冻结接口的确切签名与禁改红线 |
| 用户输入 | 0 项 —— 全部由上游工件回答 |
