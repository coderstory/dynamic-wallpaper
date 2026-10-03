# Pic — macOS 视频动态壁纸

## What This Is

一个 macOS 27 原生菜单栏 app：指定一个文件夹，把里面的视频当桌面壁纸循环播放。自用工具，产出打包成 DMG（**不签名、不公证**）。

## Core Value

桌面一直是活的视频，而且**不偷电、不抢性能**——全屏 / 锁屏 / 用电池时自动让路，其余时间安静地待在菜单栏。

**编码方针：代码越少越好。** 用最少的代码实现需求中的功能 —— 优先系统 API 而非自造，优先框架能力而非手写，少文件、少抽象层、不过度处理。

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
- **「最小代码量」与 UI 定稿的张力（待解）**：用户要求最少代码，但 UI-SPEC 定稿里有三处是**额外的代码**：① 滑杆自绘（没有 `SliderStyle`，系统滑杆用不了）② 分段控件自绘（`.tint()` 对 macOS 分段控件着色有限）③ 打包 IBM Plex Mono 字体（+字体文件 +注册代码）。**三处合计约 80 行 + 一个字体文件**，属于可接受的量级，但若后续要更省，这三处是第一顺位可砍的。
- **设置窗口 IA（已定）**：一个 Settings scene、一个 `Form`、4 个 Section、无侧边栏。① 壁纸来源（`NSOpenPanel` + 格式说明）② 播放（模式 = `.segmented` 三段控件；轮换时间 = `Stepper`，**单循环时 `.disabled(true)`**；速度/音量 = `LabeledContent` + `Slider`，**数值写进 label**）③ 电源与系统（电池供电时播放、开机自启）④ 底部 `[ 转码… ]` 按钮开独立窗口。递归子目录**不做成开关**（已定死行为，做成 toggle 是给用户不该有的选择）。宽固定 460 / 高默认 560 / min 440。
- **菜单栏点开 = 一个下拉菜单**，菜单项固定 5 条、无子层级：暂停/继续、立即下一个、重新扫描文件夹、打开设置窗口、退出。**不显示当前文件名。**（原文「点开直接弹设置窗口」与 5 条菜单项互相矛盾，以 REQUIREMENTS MENUBAR-03~07 + 设计稿为准，2026-10-03 厘清）
- **首次启动 = 直接弹文件选择框**，选完开始播，不做引导流程。
- **多 Space / 台前调度 = 跟随系统默认**，不做差异化处理。
- **工具链（已装好并实测通过）**：Xcode 27.0（Build 27A266a）已安装并通过 `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` 切换生效，`xcodebuild` / `actool` / macOS 27 SDK 全部可用。此前"只有 CommandLineTools、`@State` 和 `@Observable` 编不过"的限制**已解除**——两者现在都能编译，`Form` + `.formStyle(.grouped)` + `Slider` + `@State` + `@Observable` 组合已 `-typecheck` 通过。开发无工具链约束。
- **纯 Rust 路线的结论（已评估）**：技术上可行（`objc2` + `core-graphics` crate），但**避不开 AppKit** —— 桌面层级壁纸本质上就是 `NSWindow` 挂在 `kCGDesktopWindowLevel`，换语言不换 API。额外代价是 AVFoundation 异步 API 在 `objc2` 下远不如 Swift 顺手。已定为 **Swift 路线**。
- **`ffmpeg-kit` 已归档、官方接棒为 `ffmpeg-kit-next`（均已验证，GitHub API 实测）**：原仓库 `arthenica/ffmpeg-kit` `archived: true`，最后推送 `2026-07-02`。接棒仓库 `arthenica/ffmpeg-kit-next` `archived: false`，最后推送 `2026-10-01`，描述为 "Official continuation of FFmpegKit"，许可证同为 `LGPL-3.0`，明确支持 macOS。**本项目不用它**（走系统 `ffmpeg` 调用路线），仅作记录：若将来要改进程内转码以摆脱 PATH 依赖，这是官方可用途径。
- **SwiftUI 换肤能力（已编译 + SDK 头文件验证）**：SDK `SwiftUI.swiftinterface` 里共 27 个 public `*Style` 协议，`ToggleStyle` / `PickerStyle` / `ButtonStyle` / `FormStyle` 均在，**但没有 `SliderStyle`**（grep 结果 0，写出来直接编译报 `cannot find type 'SliderStyle' in scope`）。→ 滑杆无法自定义样式，`.tint()` 只能改填充色；要做到设计稿那种完全换肤需用 `DragGesture` 自绘。其余全部实测通过：`.shadow(color:radius:)` 双层发光、`.overlay` + `.stroke` 描边、`LinearGradient` + `.animation(.repeatForever)` 呼吸光、自定义 `ToggleStyle`、`.ultraThinMaterial` + `NSVisualEffectView(.hudWindow, .behindWindow)`、`.font(.system(design:.monospaced))`。**成本注意**：发光 = 阴影 + 模糊，吃 GPU，设置窗偶尔开无所谓，不要做成常驻动画。
- **窗口层级写法（已定案，2026-10-03）**：`CGWindowLevelForKey(.desktopWindow)` **在 Swift 里可用**，返回 `-2147483623`。实测编译+运行通过；`.desktopIconWindow` = `-2147483603`，两者差 20。`NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))` 赋值给 `NSWindow.level` 成功。**不需要硬编码数字**（SUMMARY.md 记录的 STACK vs ARCHITECTURE 冲突以此定案，ARCHITECTURE 正确）。
- **签名与分发（已定，2026-10-03）**：**不签名、不公证**，但**要做 DMG**。用户明确：dmg 需要，只是不搞签名。产出是打包成 DMG 的 `.app`，省掉 Apple Developer Program（$99/年）与 `notarytool` 公证流程。
- **打包工具已就绪**：本机已装 `create-dmg`（Homebrew），打包脚本几乎零成本。
- **未签名 app 的开机自启有风险【待验证】**：`SMAppService.mainApp` 在未签名 app 上的行为需实测 —— 登录项注册可能因签名缺失而失败或被系统拒绝。这是 SYS-01 的最大不确定点，Phase 必须实测。若不可行，退路是写一个 `LaunchAgent` plist 到 `~/Library/LaunchAgents/`。
- **转码的 ffmpeg 现实约束**：实测 macOS 27 上 `brew install ffmpeg` **会失败**（`lame` / `dav1d` 无预编译包，连锁缺 bottle）。本机最终是用 evermeet.cx 的**静态二进制**装成的（9.0.2）。→ 安装提示不能只写 `brew install ffmpeg`，必须给出静态二进制等替代途径。
- **API 存在性已编译验证**（macOS 27 SDK）：`AVPlayerItem` 无 `rate`/`defaultRate`（速度在 `AVPlayer`）；保音高要设 item，`.lowQualityZeroLatency` 在 macOS unavailable，`.varispeed` 会变调；`SMAppService.register()` 是 throwing；`SMAppService.Status` 无 `.disabled`（是 `notRegistered`/`enabled`/`requiresApproval`/`notFound`）；`NSWindow` 无 `isIgnoringMouseEvents`（在 `NSView`）；`FormInspector` 不存在；`CGWindowLevelForKey(.desktopWindow)` 可用，需 `NSWindow.Level(rawValue:)` 转换。

## Constraints

- **Platform**: macOS 27 原生，Swift + SwiftUI + AVFoundation — 用户明确要原生 app
- **Distribution**: **不签名、不公证，但要打 DMG**。**不上 App Store**（可用非公开 API）
- **Display**: 只主屏 — v1 范围裁剪
- **Formats**: mp4 / mov / m4v 走硬件解码 — 保画质、省电
- **Audio**: 变速必须保持原音高 — AVPlayer 默认会变调
- **Reactivity**: 设置改动必须**立即生效** — 改速度/音量/模式当场变，不允许"下次换片才生效"或"要重启"
- **代码量**: **最少代码实现需求** —— 这是用户明确的整体方针。优先用系统 / 框架已有的能力（`AVQueuePlayer`+`AVPlayerLooper` 而非自写循环、`UserDefaults` 而非持久化框架、AppKit 而非自造渲染）。每引入一层抽象、每写一个自造组件，都要能说清为什么现成的不能用
- **Process**: 调研期不写生产代码，本项目文档产出必须区分「已验证 / 仅推断 / 待验证」

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| **门禁证伪 → 自动转路线 B（.saver bundle）** | 用户 2026-10-03 拍板：Phase 1 若证明桌面层级方案不成立，不回头问，直接换已调研确认存在的 `.saver` 屏保 bundle 路线继续 | — Pending |
| **转码产物落 `<壁纸目录>/Converted/`** | 用户 2026-10-03 拍板：产物集中、原目录干净；扫描器排除该目录名即可杜绝回流 | — Pending |
| **交付的 `.app` 剥离测量脚手架** | 用户 2026-10-03 拍板。Phase 2 实测 493/1279 行（38.5%）是测量代码，`LoopProbe` 206 行会进 bundle；交付物只含产品代码 | — Pending |
| 🚫 **转码实测默认不执行（用户 2026-10-03 叫停）** | 用户反馈「电脑都发烫」。一次 VMAF 测量跑出 **779.9% CPU**（libvmaf `n_threads=8`）。**Phase 6 的 CRF/VMAF 实测默认不跑** —— 除非用户显式要求。参数可退化为「保守默认值 + 标注未实测」，或用 `-t 5` 秒级短片 + `n_threads=2` 降载 | — Pending |
| **Phase 6 转码参数本机实测确定**（⚠️ 已被上一条暂停） | 用户 2026-10-03 拍板。本机无可靠联网渠道（铁律 1），故从 484 个真实样本抽不同码率样本，实跑不同 CRF/preset，用 SSIM/VMAF 量出「视觉无损」的真实数值 —— 结论来自本机真实数据，不依赖二手资料 | — Pending |
| **申请屏幕录制权限** | 用户 2026-10-03 拍板。`screencapture` 无权限导致「无黑帧」「铺满无黑边」「图标点选拖动」三项永远无法自动验证 | — Pending |
| **门禁验收用强证据推进** | 用户 2026-10-03 拍板：Phase 1 的「桌面图标仍可点选」无法自动化，用窗口层级序 + 截图 + Finder 重启存活作证据继续，人工补确认事后做 | — Pending |
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
| 不签名不公证，但要做 DMG | 用户明确：dmg 要，签名不要；省掉 $99 + 公证 | — Pending |
| 先跑领域调研再定架构 | 桌面窗口层级方案可行性未知 | — Pending |
| **最小代码量** | 用户明确的整体编码方针 | ⚠️ 与 UI-SPEC 的自绘滑杆/分段控件、打包字体有张力，见 Context |

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