# Pitfalls Research

**Domain:** macOS 27 原生视频动态壁纸 app（菜单栏常驻，Swift + AVFoundation）
**Researched:** 2026-10-03
**Confidence:** MEDIUM-HIGH（领域 issue 一手证据充分；功耗绝对数值 / FFmpeg 许可细节偏低）

> **证据基线**：本文所有 pitfall 均带可追溯来源。同类项目一手 issue tracker 实测：
> phosphene 868★ / phonto 431★ / MirageWallpaper 354★ / wallpaper-play 148★ / vidwall 127★ /
> live-wallpaper 80★ / wallnetic 67★ / VideoPaper 31★。Apple 官方文档 JSON API 直读验证。
> 本机实测环境：macOS 27.0.1 (26A434), arm64。
> **本文档不含任何未验证的 issue 号或 URL**；查不到的写【待验证】。

---

## Critical Pitfalls

### Pitfall 1: 「桌面窗口层级」方案可能根本不存在可行的公开 API 落点

**What goes wrong:**
`NSWindow` 的 `level` 有下限。桌面壁纸窗口、桌面图标窗口各占一个固定层，第三方 app 的普通窗口排在它们**上面**。设 `level = kCGDesktopWindowLevel - 1` 时，窗口要么被系统忽略（不进合成树）、要么被 Finder 桌面刷新时重绘覆盖。结果是「壁纸出现了一帧就没了」。

**Why it happens:**
Apple 从未把「在桌面图标层之下」设计成公开能力。`CGWindowLevelKey` 官方枚举里最低的一档是 `.desktopWindow`，再往下就是未定义空间。同类项目的两条真实路线：

- **Route A（NSWindow 贴在桌面层）** — phonto 用 `NSWindowCollectionBehavior::CanJoinAllSpaces | FullScreenAuxiliary | Stationary | IgnoresCycle`，可运行但在 macOS 26 上跨 Space 会失效（见 Pitfall 6）。
- **Route B（ScreenSaver bundle）** — Startorch PR #62 明确写：public-API `ScreenSaverView` bundle，host 是 `/System/Library/Frameworks/ScreenSaver.framework/PlugIns/legacyScreenSaver.appex`（bundle id `com.apple.ScreenSaver.Engine.legacyScreenSaver`，`NSExtensionPointIdentifier = com.apple.screensaver`），「No private frameworks or private API are used: only ScreenSaver.framework, AVFoundation and Core Animation」。（本机已确认该 appex 路径存在）

**How to avoid:**
Phase 1 **必须先跑 demo 定案**，不要先写架构。本机验证命令：

```bash
ls /System/Library/Frameworks/ScreenSaver.framework/PlugIns/
# 实测输出：legacyScreenSaver-x86_64.appex  legacyScreenSaver.appex
```

demo 只需回答一个问题：`NSWindow` 设在 `.desktopWindow` 层时，**点击桌面图标能否选中、图标能否拖动**。能 → Route A 成立。不能 → 只能走 Route B 或降级为「贴在图标下面但可被 Finder 盖住」的降级方案。

**Warning signs:**
- demo 里壁纸窗口 `orderOut` 后不回来
- 壁纸在 Finder 图标刷新（换壁纸/右键整理）后消失
- 窗口能看见但点不到，或能点到却挡了图标点击

**Phase to address:** Phase 1（层级可行性 demo）— 这是 PROJECT.md 已标注的「最大技术风险」，必须在任何架构决策之前

---

### Pitfall 2: 全屏检测没有公开 API，且几何判定在刘海屏/Chrome 上会失效

**What goes wrong:**
「任意应用进入全屏」无公开 API。用 `CGWindowListCopyWindowInfo` 轮询算覆盖率，会出现两类错误：

**(a) 假阴性 — 真全屏了但没检测到。** MirageWallpaper #73 有实测数据：MacBook Air M3 13"（刘海屏）macOS 27.2 beta 上，全屏窗口顶部边缘因刘海下移，edgesMatch 判定失效，实测覆盖率仅 **96.548%**，低于 98.5% 阈值；Chrome 更差，仅 **87.343%**。作者最终把阈值降到 ~95%，并明确拒绝为此申请辅助功能权限。

该 issue 附的实测日志暴露了另一个硬事实：
```
display=1 bounds=0.0,0.0,1470.0,956.0 safe=0.0,32.0,1470.0,924.0
```
`safe`（visibleFrame）比 `bounds` **顶部内缩 32pt** — 那是刘海。用 `bounds` 算永远 100%，用 `visibleFrame` 算永远差一点。且 Chrome 全屏时同一 pid 会出现**两个** eligible 窗口（`bounds=0,33,1470,124` 和 `bounds=0,121,1470,835`），逐窗口匹配必然失败，必须按 pid 聚合。

**(b) 假阳性 — 几乎全屏的非全屏窗口被判成全屏，壁纸一直暂停。** MirageWallpaper #73 同一线程：隐藏 Dock 时选「填充」铺满屏幕（**不是**全屏）也会误触发停止；作者怀疑是阴影让窗口边界超出屏幕。作者原话：**遮盖到 95 左右就是全屏**。同类诉求见 live-wallpaper #4：用户主要用**最小化**窗口，桌面仍被判定为「未被完全遮挡」，壁纸照播耗电。

**How to avoid:**
- 几何判定**用 `visibleFrame`（safe）不用 `bounds`**，阈值 ~95%，**按 pid 聚合多个 rect**
- 过滤 window `layer` 与 `alpha`，排除 Dock/菜单栏层
- 用 `NSWorkspace.activeSpaceDidChangeNotification` / `screensDidSleep` / `willSleep` / `sessionDidResignActive` 等**事件**驱动，不要全靠轮询 — TzJ2006 PR #72 明确记录了「remove the 500 ms polling timer」这个动作
- **接受误判存在**：作者明确说不想为了这个功能申请辅助功能权限。误判方向要选对：宁可少暂停（多耗点电）也不要误暂停（用户觉得壁纸坏了）

**Warning signs:**
- 在自己 Mac 上测通、用户 Mac 上不触发 → 先怀疑刘海 / Chrome / 超宽屏
- 日志里 `match=none` 但 `front=` 有值
- 壁纸在 Safari/Chrome 里不停，在别的 app 里会停

**Phase to address:** Phase 2（播放与暂停策略）— 但**判定原型必须在 Phase 1 demo 里一起验**，因为它和 Pitfall 1 的层级方案耦合

---

### Pitfall 3: 「播放/暂停」状态机被系统与自己的策略互相打架

**What goes wrong:**
两种互相独立的强制暂停源被混为一谈，导致「壁纸莫名停了」：

- **系统侧**：phosphene #18 记录 WallpaperAgent 在**壁纸选择器交互期间**推 `=== UPDATE === mode: idle`，extension 策略把 `idle → paused`。表现是：点开系统设置墙纸面板、或点击菜单栏图标，壁纸立刻暂停，交互完才恢复。issue 作者结论：这是 **WallpaperAgent 驱动的模式切换**，不是自己的遮挡检测有 bug。注意 `NSWorkspace` 全量通知列表里**没有** `didEnterFullScreenNotification`（已用 Apple 文档 JSON 核对 NSWorkspace + NSApplication 全部通知名，均无 fullscreen 相关项）——所以自建遮挡判定是唯一公开路径。
- **自建侧**：可见性判定把 Dock「填充」窗口误判成全屏（见 Pitfall 2b）。

**How to avoid:**
把暂停原因做成**单一枚举 + 固定优先级**（参考 Startorch PR #54 的 `PauseReason` 声明序）：
`user > screen asleep > session inactive > fullscreen > desktop covered > low power > battery`
多个信号同时成立时只取最高优先级的原因，**且对外暴露「当前为什么暂停」**（wallnetic #250 就是这条需求）。每个信号源独立可测，任一源坏掉不污染其他。

**Warning signs:**
- 用户说「我什么都没干它就停了」→ 多半是 idle 信号或误判全屏
- 暂停原因在 UI 上显示不出来，用户只能靠猜

**Phase to address:** Phase 2（播放与暂停策略）

---

### Pitfall 4: AVQueuePlayer + AVPlayerLooper 队列状态管理错误 → 直接崩溃

**What goes wrong:**
`NSInvalidArgumentException: An AVPlayerItem can occupy only one position in a player's queue at a time.`

VideoPaper issue #3（macOS 26.0.1, M1 Max）在「添加新壁纸」时必崩。根因（PR #4 定位）：多个 `AVPlayerLooper` 对象把**同一个** `AVPlayerItem` 加进同一个 `AVQueuePlayer`。重复入队不被允许，直接抛异常。

同项目 wallpaper-play PR #45 记录了同一区域的另一类问题：用 NotificationCenter observer 做多视频循环时，会出现**重复 observer** 与 **loop 状态泄漏**，还伴随「本地视频循环时屏幕闪烁」。

**How to avoid:**
- 切换视频前必须按序：`looper.disableLooping()` → `player.removeAllItems()` → 才能把新 item 入队
- 只有当 `AVPlayerItem` 真的变了才重建 looper，避免无谓重建
- observer 注册与注销**严格配对**；用 `[NSObject defaultSelector]` token 或 `addObserver(forName:object:queue:using:)` 返回的 token 持有
- `CADisplayLink` / `Timer` 必须在同一处 `invalidate()`

**Warning signs:**
- 崩溃日志出现 `AVPlayerItem ... only one position`
- 「添加视频时闪一下黑屏」「连播几次后卡住」→ 怀疑 observer 重复注册
- 内存持续上涨（见 Pitfall 5）

**Phase to address:** Phase 2（播放内核）

---

### Pitfall 5: 每换一个视频就泄漏（内存与 GPU 资源双涨）

**What goes wrong:**
每次换片重建 `AVPlayer` / `AVPlayerItem` 时旧对象没释放，反复切换（尤其轮换时间设得很短时）内存单调上涨，最终被 jetsam 杀掉或整段视频卡住。

VideoPaper PR #7 是个具体样本：`loadSwiftData()` 用 `FileManager.fileExists(atPath:)` 检查**存的是 `file://` URL 字符串**的值 → 检查恒为 false → **每次启动都走恢复分支**，后果有两个：
1. Application Support 里每次启动堆一份重复的 `.mov` / `.png`
2. 每次启动都碰 `@Attribute(.externalStorage)`，外部 blob 缺失时 CoreData 抛 `NSException`（`_PFRoutines readBytesForExternalReferenceData:` → `_crashOnException`）

用户侧症状见 wallpaper-play #37：「每几小时就持续无响应」，环境 macOS 15.5 / M3 Max / 本地视频重复播放。

**How to avoid:**
- 换片时显式 `replaceCurrentItem(with:)`，旧 item 不持有强引用
- 文件存在性检查统一用 `URL.path`，不要把 `absoluteString` 喂给 `fileExists(atPath:)`
- 目录扫描结果做缓存，别每次切文件都重扫（递归目录会放大这个问题）
- 验收标准写死：**连续切换 50 次，内存回到基线 ±10%**

**Warning signs:**
- Xcode Memory Graph 里 `AVPlayerItem` / `AVPlayer` 实例数与切换次数成正比
- `du -sh ~/Library/Application\ Support/<app>` 随启动次数增长
- `log stream --predicate 'process == "YourApp"'` 看 `jetsam` / `memorystatus` 警告

**Phase to address:** Phase 2（播放内核）+ Phase 5（稳定性）

---

### Pitfall 6: Space 切换后壁纸窗口消失 / 只在启动时的那个 Space 出现

**What goes wrong:**
设了 `CanJoinAllSpaces` 但壁纸窗口切 Space 后就没了。phonto issue #37（macOS 26.6.2）就是这个，作者复现不出来，作者的解释直指要害：

> The Dock keeps one wallpaper window per Space, and on macOS 26 those sit at the exact same window level phonto was using.

即 Dock 在**每个 Space 各持有一个**桌面层窗口，且在 macOS 26 上与第三方壁纸窗口**同层**。作者测试了单屏、内置+外接分开 Space、多 Space、手动启动与 LaunchAgent 启动均正常，怀疑与 26.6.2 特定版本有关。

wallnetic #256 从另一侧记录了同一类问题的**本质**：Space 标识是**会话相关**的，重开 app 后保存的分配可能根本无法再识别；该 issue 的验收标准之一是「Never claim persistent Space identity when it cannot be established」。

phosphene #21（macOS 26.5.2, M2 Pro, 内置+外接）另有一类：拔掉大屏再插回后，壁纸**尺寸不跟随**，不重新铺满。

**How to avoid:**
- 订阅 `NSWorkspace.activeSpaceDidChangeNotification`，切 Space 时**主动 re-assert** 窗口（重设 collectionBehavior + orderFront）
- 只做主屏（PROJECT.md 已裁剪范围），但仍要处理「插拔外屏后重算 bounds」
- **不要承诺 Space 级持久配置**——这是被两个独立项目分别踩到的设计陷阱

**Warning signs:**
- 在自己单屏 Mac 上永远复现不了 → 必须外接屏 + 多 Space 测
- 插拔显示器后壁纸尺寸错乱

**Phase to address:** Phase 2（播放内核）+ Phase 5（稳定性）

---

### Pitfall 7: 屏幕唤醒 / 睡眠 / 解锁后，播放状态不重算（暂停了或没恢复）

**What goes wrong:**
唤醒路径与暂停路径不对称。TzJ2006 PR #79 就是修这个：「re-evaluate wallpaper playback after a display wakes so occlusion rules apply immediately」——即唤醒后**立刻**重算，而不是等下一个信号。

VideoPaper issue #8 的表现更糟：解锁后只看到**冻结帧**；锁一次再解锁桌面正常，但**重新登录后背景变灰**，直到重启才恢复。作者说明用「替换 Apple 原始视频」的老办法也会这样。

phosphene #13（macOS 27.0 beta）同源：`hasLiveRenderer(onDisplay:)` 把「这块屏上有任何活 renderer」当成「WA 已经托管了东西」，于是把新 acquire 的回复**延后**，桌面就一直黑屏，PR #15 的修复是按 `isPreview` 角色拆开判断。

phosphene #16 给了量化后果：`teardownGrace = 15.0s` 让每个「每屏每角色」的旧 renderer 在 `invalidate` 后还活着 15 秒。双屏 × 2 角色 → **一个切壁纸动作短暂维持 8+ 个并发 4K decoder**，抢 VideoToolbox 有限的解码会话池，退化成软件解码或串行化，**卡顿约 15 秒**（实测窗口 +15.004s，与 teardownGrace 精确对上）。

**How to avoid:**
- 暂停与恢复走**同一个 `re-evaluate()` 函数**，输入是全部信号的当前值
- 休眠/唤醒/解锁/显示器热插拔各订阅对应通知，全部汇入该函数
- 切屏时**手-off 式拆除**：新 renderer 首帧就绪（`onFirstFrameReady`）立刻拆掉被顶替的旧 renderer，15 秒宽限期只留给休眠唤醒场景
- **验收标准**：连续 20 轮 休眠→唤醒 / 锁屏→解锁，播放状态 100% 正确，无黑屏无灰屏

**Warning signs:**
- 唤醒后内存没回落 → 旧 renderer/item 没拆
- 切壁纸后卡 15 秒 → 检查有没有 teardown 宽限期
- `killall` 相关进程后壁纸黑屏到手动重启 → acquire 时序竞态

**Phase to address:** Phase 2（播放内核）

---

### Pitfall 8: 非上架分发 —— 签名、公证、自启三者各自的坑

**What goes wrong:**

**(a) 自启 API 选错。** `SMAppService`（macOS 13+，已用 Apple 文档核实；`SMAppService.mainApp` 文档原文即「configure the main app to launch at login」）注册的是 **helper executable** 形态。PROJECT.md 的决定是「开机自启需手动设一次」，正好匹配 Apple 对首次注册的引导流程。

`register()` 是 **throwing**。`status` 是可选值，**没有 `.disabled`**，实际取值为 `enabled` / `notRegistered` / `requiresApproval` / `notFound`（已核实全部四个 case）。

**(b) 公证门槛。** Apple 文档：notary service 自 2023-11-01 起**不再接受 altool 或 Xcode 13 及更早版本**的上传，必须用 `notarytool` 或 Xcode 14+。签名本身失效会报 `The signature of the binary is invalid.`，用 `codesign -vvv --deep --strict` 自查（Apple 文档推荐此命令）。

**(c) 拷到别的 Mac。** 「能拷走的签名 .app」这条需求，成败取决于**签名类型**：
- 免费 Apple ID 签名 → 有有效期（约 7 天）且**无法公证**，拷到别的 Mac 会被 Gatekeeper 拦
- Developer ID 签名 + 公证 → 可长期分发、可 `spctl --assess` 通过

PROJECT.md 的 Distribution 明确是「签名 .app，能拷到别的 Mac 跑，不上 App Store（可用非公开 API）」。**免费 Apple ID 签名的 .app 满足不了「能拷走」这一条** —— 这是需求与手段的冲突，必须在 Phase 6 前拍板。

**How to avoid:**
- 自启用 `SMAppService.mainApp`，`register()` 包 do/catch；`status` 只按四个真实 case 分支，**`requiresApproval` 要引导用户去「系统设置 › 通用 › 登录项」手动批准**（这正是「手动设一次」的落点）
- 公证用 `notarytool`（或 Xcode 14+ 的分发 UI）
- 签名身份在 Phase 6 前确认，不要等到打包才发现要付费开发者账号

**Warning signs:**
- `register()` 抛错但 UI 没提示
- 另一台 Mac 上双击提示「无法验证开发者」
- `codesign -vvv --deep --strict` 报 invalid

**Phase to address:** Phase 6（分发与自启）— 但**签名前置决策要在 Phase 0/1 就确认**，因为它影响架构自由度

---

### Pitfall 9: 转码 — FFmpegKit 已退役 + 许可状态 + 子进程退出码陷阱

**What goes wrong:**

**(a) FFmpegKit 已官方退役。** 已核实 `arthenica/ffmpeg-kit` 仓库 **`archived = true`**，README 顶部（2026-07 更新）原文：`FFmpegKit has been officially retired`，继任项目 `FFmpegKitNext` **「distributed as source only」**（无预编译包）。

> 这不是「FFmpegKit 官方弃用」那么简单 —— 是**整条预编译二进制分发链断了**。任何写着「用 FFmpegKit」的方案在 macOS 27 上都要重新评估构建成本。

**(b) 许可。** README 原文：`Licensed under LGPL 3.0 by default, GPL v3.0 if GPL licensed libraries are enabled`。**开了 GPL 库（如 lame）就变 GPL v3.0**。PROJECT.md 说不上架、自用、不分发，GPL 传染性在此场景的实际约束需要单独判断 —— 但这条不能等到写代码时才发现。**【待验证】**：具体到「自用不上架」场景下 GPL v3.0 对本项目的实际义务边界，未找到针对此场景的公开资料。

**(c) 本机实测：Homebrew 装不上。** `brew install ffmpeg` 在 macOS 27 上因 `lame` / `dav1d` **无 bottle** 直接失败，必须先 `brew install --build-from-source`。

**(d) 管道吞掉退出码。** `cmd | tail` 会拿到 0，检测代码**不能靠管道输出判断成败**。必须 `Process.run()` + `terminationStatus`，或 `process.waitUntilExit()`。

**How to avoid:**
- 转码方案 Phase 0 先做**独立可行性验证**，再决定是否引入任何 FFmpeg 依赖
- 若引入：确认拿到的是 source-only 且能构建；许可结论写进决策记录
- 退出码检测：绝不用管道；用 `terminationStatus` / `terminationReason`
- 转码写临时目录**先检查剩余空间**；输出写 `xxx.tmp` 再 rename，避免半成品被扫进播放目录
- **转码与播放不能抢同一资源**：转码进程设低优先级（`nice`），或串行化

**Warning signs:**
- CI/本机 `brew install ffmpeg` 失败
- 检测逻辑「永远成功」
- 播放目录里出现 0 字节或时长异常的 mp4 → 被扫进来了

**Phase to address:** Phase 7（转码）— 独立于播放主线，可延后；但许可与构建成本要在 Phase 0 评估

---

## 「以为是 Bug 其实是设计如此」Top 5

> 这些不是 bug，**在文档和 UI 里说清楚就能消掉 80% 的用户投诉**。

### 1. 切换壁纸 / 全屏退出 / 解锁瞬间，壁纸会闪一下

MirageWallpaper issue #73 作者原话（维护者回复）：

> 动态壁纸都会闪一下是因为覆盖静态壁纸取渲染器刚播放壁纸时成功的第一帧，恢复实时渲染需要时间，**这不是 bug**。

同理 phosphorene #26：设成 screensaver 后会「闪一下视频再重置成系统视频」。

**处理**：写进 README / 设置项说明，不要当 bug 修。

### 2. 点开「系统设置 › 墙纸」或点菜单栏图标，壁纸会暂停

phosphene #18 已定性：WallpaperAgent 在选择器交互期间推 `mode: idle`，策略映射成 paused。**这是系统行为，不是你的 bug。**
唯一能做的是把暂停原因显示出来（wallnetic #250 的诉求）。

### 3. 显示器多 / 用 Space 时，壁纸「时有时无」

phonto #37 + wallnetic #256：Dock 在**每个 Space 各持一个**桌面层窗口，且 Space 标识是会话相关的。跨 Space 的持久配置在公开 API 下**无法可靠实现**。

**处理**：v1 只做主屏（PROJECT.md 已裁剪），并在 UI 上不承诺 Space 级配置。

### 4. 非原生格式（avi/mkv/webm）播放不了

PROJECT.md 已明确列为 Out of Scope，走转码路线。系统动态壁纸（Aerial）本身用的是 HEVC Main10 240fps（Startorch PR #63 实测：`~/Library/Application Support/com.apple.wallpaper/aerials/` 下 `manifest/entries.json` + `videos/*.mov`，~3840×2160 / ~12 Mbit/s）—— 你的 mp4 只要不是 HEVC 硬解规格就会明显更耗电。

**处理**：设置里对每个视频显示「是否硬解」，让用户自己权衡。

### 5. 换壁纸时卡顿约 15 秒

phosphene #16 实测：`teardownGrace = 15.0s` × 双屏 × 2 角色 = 8+ 并发 4K decoder 抢 VideoToolbox 解码池。若实现里保留类似宽限期，**这是必然结果而非偶发**。

**处理**：要么改成手-off 拆除（PR #16 的首选方向），要么把宽限期收到最短并在 UI 里说明。

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| 轮询 `CGWindowListCopyWindowInfo`（500ms）代替事件通知 | 少写一堆订阅 | 全天后台轮询的电量成本；TzJ2006 PR #72 明确移除了这个 timer | 调研期 demo；正式版必须换事件驱动 |
| 用 `AVPlayer.rate` 直接变速 | 3 行搞定 | **会变调**（PROJECT.md 已列为硬约束）。需显式设 `AVAudioTimePitchAlgorithm`，设非法值会抛 `NSException` | 永不 |
| 每次换片 `AVPlayerItem(url:)` 重建 | 简单 | 内存单调上涨（VideoPaper PR #7 / wallpaper-play #37） | 永不 |
| 检测转码成功靠管道退出码 | 少写代码 | **恒为 0，等于没检测** | 永不 |
| 免费 Apple ID 签名分发 | 零成本 | 7 天过期、无法公证、**拷不到别的 Mac** | 仅本机调试 |
| 转码输出直接写播放目录 | 少一次 rename | 半成品被扫进目录 → 播不了 | 永不 |
| 不写「当前暂停原因」 | 省一个 UI 控件 | 用户无法自诊断，投诉变成玄学（wallnetic #250） | 永不 |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| `SMAppService` | `register()` 不 try/catch；`status` 里有 `.disabled` | `register()` 是 throwing；status 只有 `enabled`/`notRegistered`/`requiresApproval`/`notFound` |
| `AVQueuePlayer` | 直接把新 item 入队而不先 `removeAllItems()` | `disableLooping()` → `removeAllItems()` → 再入队 |
| `AVPlayerItem.audioTimePitchAlgorithm` | 设了非法枚举值 | 会抛 `NSException`（Apple 文档明载）；只设文档列出的常量 |
| `FileManager` | 把 `URL.absoluteString`（`file://…`）喂给 `fileExists(atPath:)` | 先取 `URL.path`（VideoPaper PR #7） |
| `NSWindow.level` | 设到 `.desktopWindow` 以下 | 无公开落点，见 Pitfall 1 |
| 全屏判定 | 用 `bounds` 算覆盖率 | 用 `visibleFrame`（safe）；刘海屏 top 内缩 32pt（MirageWallpaper #73 实测日志） |
| 公证 | 用 `altool` / Xcode 13 | 2023-11-01 起不再接受；用 `notarytool` 或 Xcode 14+ |
| 子进程 | `cmd \| tail` 判断退出码 | 用 `terminationStatus` |
| 进程 | 依赖 `AVAudioSession` 做 macOS 音频路由 | 已核实 `AVAudioSession` 平台列表为 iOS/iPadOS/Mac Catalyst/tvOS/visionOS/watchOS，**不含 macOS** |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| `teardownGrace` 式延迟拆除 | 切壁纸后卡 ~15s | 手-off 拆除：新 renderer `onFirstFrameReady` 即拆旧（phosphene #16） | 双屏 / 多角色，立刻 |
| 多窗口并发解码抢 VideoToolbox 池 | 退化为软件解码，掉帧 | 限制并发 decoder 数；单显示器单角色 | 任何多屏场景 |
| 500ms 全屏轮询 | 安静时仍有可观 CPU | 改事件驱动（TzJ2006 PR #72） | 常驻即全天 |
| `preferredForwardBufferDuration` 设过大 | 解码积压、内存涨、耗电高 | 保持默认（0）让系统自选；Apple 文档明确：低值增加卡顿概率，高值增加系统资源需求 | 长视频 / 高码率 |
| 递归目录每次切文件重扫 | I/O 尖峰 | 扫描结果缓存 + 手动「重新扫描」 | 大目录 |
| 「性能档位」只有 UI 没有实际效果 | wallnetic PR #261 记录过这个：设置项存在但「no effect on playback」 | 档位必须真的门控 display-link 派发频率 | 任何「省电模式」开关 |

---

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| 为了全屏判定申请辅助功能权限 | 权限过重，且 TCC 弹窗时机不可控，用户拒绝后功能直接废 | MirageWallpaper 作者明确拒绝：「我不想因为这个功能去申请辅助功能权限」。用几何 + 事件替代 |
| 分发时未公证 | Gatekeeper 拦截，拷到别的 Mac 跑不起来 | Developer ID + `notarytool` 公证（见 Pitfall 8） |
| 误以为不上架 = 无需签名 | 拷贝即失效 | 签名是分发的前提，不是上架的前提 |

> **关于 TCC**：本项目走 `CGWindowLevelForKey` + `CGWindowListCopyWindowInfo`，**不需要**辅助功能权限也不需要屏幕录制权限。屏幕录制权限只在读取窗口**标题/内容**时才涉及，壁纸场景只需窗口几何与 layer。
> **【待验证】**：`com.apple.screenIsLocked` 分布式通知是否可作为锁屏判定的稳定手段 —— 本次未找到 Apple 官方文档明载，属未文档化用法，需 Phase 2 实测。

---

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| 不显示当前暂停原因 | 用户无法自诊断，投诉变玄学 | 菜单栏/设置里显示暂停原因（wallnetic #250） |
| 菜单显示当前文件名 | 用户已明确不要 | 不显示（PROJECT.md 已定） |
| 不显示「是否硬解」 | 用户以为省电，实际 avi/mkv 在软解 | 每个视频标注硬解状态 |
| 音效戛然而止 | 用户明确反馈「有点怪」 | 暂停/恢复加音频渐弱渐强（MirageWallpaper #73 用户建议，维护者已纳入 feature list） |
| 第三方通知音也触发暂停 | 壁纸音乐因无关音效中断 | 加可自定义的 app 白名单（同上，用户原话） |
| 「重新扫描文件夹」做成自动监听 | v1 范围外，且引入 FSEvents 复杂度 | v1 手动（PROJECT.md 已定） |

---

## "Looks Done But Isn't" Checklist

- [ ] **层级方案**：能播 ≠ 能贴在图标后面。必须验证「图标可点、可拖动、Finder 刷新后壁纸还在」
- [ ] **全屏检测**：在自己 Mac 上测通 ≠ 完成。必须在**刘海屏** + **Chrome** + **超宽屏**上各测一遍（MirageWallpaper #73 的三个失败场景）
- [ ] **播放内核**：单片能播 ≠ 列表循环不崩。必须跑 50 次切换，内存回基线 ±10%
- [ ] **暂停策略**：能暂停 ≠ 能正确恢复。必须跑 20 轮 休眠/唤醒/锁屏/解锁/插拔显示器
- [ ] **变速**：能变速 ≠ 不变调。必须实际听 0.5× / 2× 的人声
- [ ] **音频**：能出声 ≠ 睡眠时也停。必须验证睡眠/锁屏时声音停
- [ ] **自启**：能注册 ≠ 用户只点一次就成。必须验证 `requiresApproval` 分支有引导
- [ ] **分发**：本机能跑 ≠ 别的 Mac 能跑。必须在**未装开发者工具的第二台 Mac** 上验证
- [ ] **转码**：命令能跑 ≠ 装得上。`brew install ffmpeg` 在 macOS 27 上的失败需先解决
- [ ] **设置即时生效**：改了设置当场生效 ≠ 下一个视频才生效（PROJECT.md 硬约束）

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| 壁纸被系统/其他壁纸 app 盖掉 | LOW | `killall` 相关进程；关掉冲突的壁纸/屏保 app |
| 壁纸黑屏 / 灰屏 | LOW | 重启本 app；反复不愈则重启系统（VideoPaper #8 即此症状） |
| 内存泄漏已发生 | MEDIUM | 重启 app；根治靠 Pitfall 5 的 50 次切换验收 |
| 解码池耗尽 / 卡顿 | MEDIUM | 降到单屏单角色；缩短 teardown 宽限期 |
| FFmpegKit 路线走不通 | HIGH | 换 source-only 自建；或回退到「只播原生格式」并告知用户 |
| 免费 Apple ID 签名已分发出去 | HIGH | 需重新走 Developer ID + 公证；**必须提前确认，不要事后补救** |
| 签名在另一台 Mac 失效 | MEDIUM | 重新公证并 stapling |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| 1 层级方案无公开落点 | **Phase 1（层级可行性 demo）** | demo 证明图标可点/可拖/Finder 刷新后仍在 |
| 2 全屏检测误判 | Phase 1（原型）+ Phase 2（落地） | 刘海屏 / Chrome / 超宽屏三者各测一遍 |
| 3 暂停状态机打架 | Phase 2 | 优先级枚举 + 「当前暂停原因」UI 可见 |
| 4 AVQueuePlayer 崩溃 | Phase 2 | 连播/快切 50 次无异常 |
| 5 换片内存泄漏 | Phase 2 + Phase 5 | 50 次切换内存回基线 ±10% |
| 6 Space 切换丢失 | Phase 2 + Phase 5 | 多 Space + 插拔显示器；UI 不承诺 Space 级配置 |
| 7 唤醒/解锁状态不重算 | Phase 2 | 20 轮 休眠/唤醒/锁屏/解锁无黑屏灰屏 |
| 8 签名/公证/自启 | **Phase 0 决策 + Phase 6 落地** | 第二台未装开发工具的 Mac 上可运行 |
| 9 转码（FFmpegKit 退役/许可/退出码） | **Phase 0 评估 + Phase 7** | 独立构建验证 + `terminationStatus` 单测 |

---

## Gaps to Address（下次需要更深研究）

1. **【待验证】`com.apple.screenIsLocked` 分布式通知**的稳定性 —— 无 Apple 官方文档明载，需 Phase 2 实测锁屏判定
2. **【待验证】GPL v3.0 在「自用不上架」场景的实际义务边界** —— 未找到针对此场景的公开资料
3. **【待验证】macOS 27 上刘海屏 `visibleFrame` 内缩值是否恒为 32pt** —— MirageWallpaper #73 只在 M3 Air 13" / macOS 27.2b 实测过一次
4. **功耗绝对数值（AVPlayer 解码占多少电）** —— 未找到公开的一手实测数据。wallnetic PR #261 明确不承诺固定 CPU/电池节省数字，只承诺门控 display-link 派发频率
5. **phonto #37（跨 Space 失效）作者未能复现** —— 怀疑与 macOS 26.6.2 特定版本相关，根因未确定。若 Phase 2 遇到，需自己写 `CGSCopySpacesForWindows` 探针复现

---

## Sources

**一手 issue（全部经 GitHub API 实读，非记忆）**
- kageroumado/phosphene #13 #15 #16 #17 #18 #20 #21 #26 #29 #31；PR #24 #25 #30 #32
- museslabs/phonto #36 #37；PR #21 #27
- laobamac/MirageWallpaper #52 #73（含 #73 全部评论与实测日志）
- Mcrich-LLC/VideoPaper #1 #3 #6 #8；PR #4 #7
- nhiroyasu/wallpaper-play #37 #38；PR #45
- fatihkan/wallnetic #255 #256 #257 #259 #260；PR #261 #262
- TzJ2006/desktop-video-for-mac PR #72 #73 #76 #77 #78 #79 #80
- ducbao414/live-wallpaper #1 #4
- jaywcjlove/vidwall #2
- misaki1301/Startorch-Wallpaper-Engine PR #52 #53 #54 #61 #62 #63 #64

**Apple 官方文档（经 developer.apple.com 文档 JSON API 直读核实）**
- `SMAppService` / `.mainApp` / `.Status`（四个 case：enabled / notFound / notRegistered / requiresApproval；macOS 13+）
- `CGWindowLevelKey`（含 `.desktopWindow` / `.desktopIconWindow` / `.screenSaverWindow`）、`CGWindowLevel`
- `AVAudioTimePitchAlgorithm`、`AVPlayerItem.audioTimePitchAlgorithm`（非法值抛 NSException）
- `AVPlayerItem.preferredForwardBufferDuration`（macOS 10.12+；低值增卡顿、高值增资源）
- `ProcessInfo.isLowPowerModeEnabled`（macOS 12+）
- `AVAudioSession` 平台列表（**不含 macOS**）
- `NSWorkspace` / `NSApplication` 全部通知名（**无 fullscreen 通知**）
- Notarizing macOS software before distribution / Resolving common notarization issues

**本机实测（macOS 27.0.1, build 26A434, arm64）**
- `/System/Library/Frameworks/ScreenSaver.framework/PlugIns/` → `legacyScreenSaver.appex` + x86_64 版
- `~/Library/Application Support/com.apple.wallpaper/aerials/` → `manifest/entries.json`、`videos/`、`thumbnails/`
- `~/Library/Application Support/com.apple.wallpaper/Store/Index.plist` → `AllSpacesAndDisplays` / `Displays` / `Spaces` 三层结构
- Xcode **未安装**（仅 CommandLineTools）—— **建不了 app，正式开发前需先装 Xcode**

**工具状态说明**：本次 WebSearch / WebFetch 内置工具持续返回 `API Error: 400`，cs-web-fetch skill 抓 Bing 超时。改用 `curl` 直连 GitHub REST API + Apple 文档 JSON API 完成全部检索，均为一手来源。

---

*Pitfalls research for: macOS 视频动态壁纸 native app*
*Researched: 2026-10-03*
