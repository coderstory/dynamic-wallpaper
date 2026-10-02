# Phase 2: 播放内核竖切 - Context

**Gathered:** 2026-10-03
**Status:** Ready for planning
**Mode:** mvp（vertical slice：桌面图标后面有视频在无缝循环 + 菜单栏常驻 + 三个接口定死）

> ⚠️ **本 Phase 有一个编排器代你拍板的架构决定，见 D-01。它值得你醒来复核。**

<domain>
## Phase Boundary

用户看到一个**真正的菜单栏 app** —— 桌面图标后面有视频在无缝循环播放，菜单栏能暂停/继续和退出，没有 Dock 图标。
`SettingsStore` / `HoldArbiter` / `PlayerController` 三个接口**在此定死**，后续全部阶段依赖它。

**本 Phase 不交付**：声音/速度控件（Phase 5）、文件夹选择面板（Phase 4）。开发期用 `UserDefaults` 指向一个测试目录。

**这是本项目第一次写产品代码** —— Phase 1 是 throwaway spike，产出全部在 `.planning/spike/`，不进产品库。

</domain>

<decisions>
## Implementation Decisions

### ⚠️ 编排器代拍（D-01 ~ D-03）—— 这三条你醒来后请复核

- **D-01:** 构建系统 = SwiftPM（`Package.swift`），Phase 5 引入 Xcode 工程。

理由与取舍：
- **单测需求 TEST-01~06（veto 64 组合、扫描、轮换、持久化、ffmpeg 检测、转码参数）用 `swift test` 就能满足**，不需要 Xcode 工程。`Package.swift` 约 30 行；手写 `.pbxproj` 是数千行且极易出错（本机无 xcodegen/tuist/swiftgen，装它们属于系统变更，我不便在你睡着时擅自安装）。
- **XCUITest（TEST-07~10）必须有 `.xcodeproj`** —— SwiftPM 不支持 UI 测试 target。所以 Xcode 工程是**必需的，只是延后到 Phase 5**（第一个需要 XCUITest 的阶段）再引入，而不是 Phase 2 一上来就背这个包袱。
- 迁移成本：Phase 2→4 的产品代码是普通 Swift 文件，换构建系统不改源码，只需重排目录。
- **风险**：Phase 5 要停下来建 Xcode 工程。如果你的时间表更看重「一次到位」，这个决定应该反过来 —— **这是你可以推翻的一条**。

- **D-02:** 测试语料用 ffmpeg 现生成的小视频 + 你 `~/Movies/视频壁纸` 里的真实素材抽样。

- 本机已有 `ffmpeg 9.0.2-tessus`（静态二进制）。生成几个 5–10 秒的小 mp4（可指定分辨率/帧率/有无音轨），**确定性、可复现、体积小**。
- 你的真实素材 484 个 mp4 / 约 42GB —— **绝不整个目录拿来做开发测试**（扫描 42GB 会拖慢每次迭代）。开发期固定指向一个 3–5 个文件的小目录；「递归扫描 + 大目录性能」留到 Phase 4 单独测。
- 不得把用户真实素材**复制进仓库**。

- **D-03:** 设置持久化用 `UserDefaults`，开发期默认指向测试目录。

Phase 4 才做文件夹选择面板。Phase 2 只需 `UserDefaults` 里有一个可写的 `folderBookmark`/路径字段，默认值由 dev 脚本预置。

### 继承自 Phase 1 的硬约束（已实测，不得重新推导）

- **D-04:** 层级写法照抄，不重新推导。
```swift
w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))   // -2147483623
```
`.desktopIconWindow`（-2147483603）**禁用** —— 会盖住桌面图标。

- **D-05:** 菜单栏激活策略断言值是 `1` 不是 `0`。
实测 `NSApplication.ActivationPolicy`： `regular=0` / `accessory=1` / `prohibited=2`。
Phase 1 的计划曾把 `accessory` 写成 `0` —— 那是**有 Dock 图标**的那个，照抄会造出假通过。

- **D-06:** 🔴 Phase 2 第一个任务是在解锁会话重跑门禁（PDCA-A1）。

Phase 1 的**全部**测量都在**锁屏会话**内完成（`UserIsActive 0`、`loginwindow` PID 489 自采集起未变）。门禁结论「路线 A 成立」的适用边界**未在有前台进程的环境验证**。

**开工第一步：`bash .planning/spike/run-gate.sh`，确认 `ORDER=ok` 与 `FINDER_RESTART_ALIVE=1` 在解锁会话下仍成立。**
不通过 → 门禁结论降级为「仅锁屏会话下成立」，本 Phase 需重新评估路线。

> 注：屏幕当前锁着（你已睡）。若醒来时仍锁着，此项如实标 BLOCKED 继续，**但必须在 SUMMARY 里写明「产品未在解锁会话验证过」**。

- **D-07:** macOS 27 的 API 变更（Phase 1 实测）。
- `CADisplayLink(target:selector:)` 与 `preferredFramesPerSecond` 标 `API_UNAVAILABLE(macos)` —— 写出来编不过。用 `NSScreen.displayLink` + `preferredFrameRateRange`。
- `AVPlayer.preferredForwardBufferDuration` **不存在** —— 它是 `AVPlayerItem` 的属性。
- `AVPlayerItem` 无 `rate`/`defaultRate` —— 速度在 `AVPlayer` 上。

- **D-08:** 桌面层窗口有系统性几何内缩。 —— Phase 2 只做**实测记录**（02-02 T2 产出 `evidence/inset.log`），不据此断言；真正需要据此判定的是 Phase 3 的全屏几何。borderless 桌面层窗口的 `CGWindowList` bounds 比 `NSScreen.frame` 内缩 **14pt/9pt**（叠加刘海 33pt 共 47pt）。Phase 2 若要用覆盖率判断什么，必须先处理这个内缩。

- **D-09:** 本机装了 4 个同类动态壁纸 app（`Dynamic Wallpaper` / `Hanami Live Wallpaper` / `Wallpaper Monster` / `DevDesk`）。**2026-10-03 编排器更正**：先前依据 Phase 1 转述的「至少一个常驻在 `-2147483623`」**未能复现** —— Phase 2 T2 实测 `FOREIGN_SAME_LEVEL=0`、`FOREIGN_OWNERS=none`、`FOREIGN_DESKTOP_FAMILY=7`；`pgrep` 显示 4 个 app 中**只有 `DevDesk` 在运行**，其余 3 个未运行。**结论修正**：共存风险比原先记录的**低**，但「桌面族里确实还有 7 扇别人的窗口」是事实。**D-09 的可执行部分不变**：按 PID 认领自己的窗口（本机确实存在其他桌面族窗口，按 layer 认领仍会认错），验收仍留意 z-order 竞争。

### 架构（ROADMAP 已定，照抄）

- **D-10:** 分层 `State/` + `Playback/` + `Render/`；`AppDelegate.wiring()` 是**唯一装配点**。

- **D-11:** `HoldArbiter` 从第一天就建成 `Set<HoldReason>` veto 集合（先只接手动暂停）—— 形状对了才不会在 Phase 3 返工。
**不要用优先级链做决策**（锁屏 + 全屏反例：优先级链会在退出全屏时误恢复播放）。

- **D-12:** 播放内核用 `AVQueuePlayer` + `AVPlayerLooper` + `AVPlayerLayer`。
- `audioTimePitchAlgorithm = .spectral` **显式设** —— macOS 12+ 默认 `.timeDomain` 会变调。
- `isOpaque = true` / `hasShadow = false` / `videoGravity = .resizeAspectFill`

- **D-13:** ** ⚠️ **`rate` / `volume` 必须挂 `AVPlayer`，不能挂 `AVPlayerItem`。
`AVPlayerLooper` 的模板 item 属性在 init 时就冻结，挂 item 会让「改设置立即生效」（PLAY-10）变成假的。Phase 2 就要按这个形状写，别等 Phase 5 返工。

- **D-14:** 防 Pitfall 4：切换视频前 `disableLooping()` → `removeAllItems()` → 再入队；observer 注册/注销严格配对。
防 Pitfall 5：文件存在性检查统一用 `URL.path`（**不要喂 `absoluteString`**）。
防 Pitfall 7：暂停/恢复走**同一个 `re-evaluate()`** 入口。

### 其他

- **D-15:** 续播锚点只在 `holds` 由 `∅ → 非∅` 转换时写入（叠加暂停期间不被二次覆盖）。Phase 2 只接手动暂停，但锚点机制先建对。


### Claude's Discretion
- 三个接口的具体方法签名与文件切分粒度
- 测试视频的具体参数（时长/分辨率/帧率）
- 是否用 `NSHostingView` 承载 SwiftUI 设置窗（Phase 2 只需最小骨架）

</decisions>

> **D-16（流程决策，非可追踪的实现决策）**：本 Phase 不跑 research-phase —— 已由「未派发 researcher」这个动作本身履行，故不出现在任何 plan 的 must_haves 中。技术事实来自 `01-VERDICT.md` 与本文件 `<gate_findings>`。

<specifics>
## Specific Ideas

**最小可感知价值 = 桌面图标后面有视频在无缝循环 + 菜单栏能暂停/继续和退出。** 不要在这个 Phase 加任何 UI 复杂度 —— 设置窗只要一个能打开的骨架，控件留给 Phase 5。

**三个接口在此定死，后续全部阶段依赖它** —— 这是本 Phase 除播放本身之外的第二产出。

</specifics>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

- `.planning/phases/01-spike/01-VERDICT.md` — **Phase 2 只引用它，不回翻 SUMMARY 与 git log**
- `.planning/phases/01-spike/01-CONTEXT.md` 的 `<gate_findings>` 段 — 4 条实测发现
- `.planning/spike/WallpaperSpike.swift` — 已验证可跑的桌面层窗口实现（**照抄它的窗口配置**）
- `.planning/spike/MenuBarSpike.swift` — 已验证的 `.accessory` + `MenuBarExtra` 骨架
- `.planning/spike/WindowProbe.swift` — 按 PID 认领窗口的正确写法
- `.planning/research/PITFALLS.md` — 尤其 Pitfall 4/5/7（`AVPlayerLooper` / `URL.path` / 单一 re-evaluate 入口）
- `.planning/ROADMAP.md` Phase 2 的 5 条 Success Criteria
- `test.sh` / `build.sh` — 现有工具链，15 项检查全绿

</canonical_refs>

<existing_artifacts>
## 已有的可复用资产

- **`.planning/spike/WallpaperSpike.swift`** —— 桌面层窗口 + 帧号覆盖层，已跑通 `ORDER=ok` / `FINDER_RESTART_ALIVE=1`
- **`.planning/spike/MenuBarSpike.swift`** / `MenuBarFallback.swift` —— 两条菜单栏路线都验证过
- **`.planning/spike/WindowProbe.swift`** —— 按 PID 枚举窗口
- **`test.sh`** —— 15 项检查全绿，新探针往这里挂
- **`build.sh`** —— 已验证的 DMG 流水线（swiftc → .app bundle → codesign adhoc → hdiutil）
- **`ffmpeg 9.0.2`** —— 现成可用的测试视频生成器
- **`~/Movies/视频壁纸`** —— 484 个真实 mp4 / 约 42GB（**抽样用，不整个拿来做开发测试，不复制进仓库**）
- **工具链**：Xcode 27.0（Build 27A266a）、Swift 6.4、ffmpeg 9.0.2-tessus

</existing_artifacts>

<constraints>
## Constraints

- **不签名、不公证**（已定），但**要 DMG**
- **最少代码**：优先系统/框架现成能力。每引入一层抽象都要能说清现成的为什么不能用
- **不做产品脚手架以外的膨胀**：不建 CI、不建文档站、不做错误处理框架
- **诚实基线**：明确区分「跑过 / 没跑过 / 应该能跑但未测 / 假定依赖」。验收判据不得用主观语言
- **不伪造数字**：任何度量必须来自真跑过的命令，可复现
- **屏幕可能仍锁着** —— 若视觉相关项做不了，如实标 BLOCKED 继续，不阻塞

</constraints>
