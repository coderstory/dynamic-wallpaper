# Roadmap: Pic

## Overview

路径是 **门禁 → 地基 → 两路并行 → 界面 → 转码 → 交付验收**。最重的风险放在最前面：Phase 1 是一次性验证 app，只回答一个问题 —— 视频能不能真的待在桌面图标**后面**。答不了「能」，整个架构作废，后面六个 Phase 全部不启动。答了「能」，Phase 2 把播放内核竖切成最小可感知价值（桌面图标后面有视频无缝循环 + 菜单栏常驻），并把 `SettingsStore` / `HoldArbiter` / `PlayerController` 三个接口在此定死。接口定死之后，Phase 3（系统事件仲裁）与 Phase 4（媒体库与轮换）**零耦合、可并行** —— 这是本项目唯一的并行机会，也是唯一的赶时间手段。Phase 5 落地 UI-SPEC 定稿的设置窗并保证所有改动当场生效；Phase 6 做全品类唯一没人做的转码（也是唯一需要额外深度研究的阶段）；Phase 7 用两条脚本收口（`build.sh` 出 DMG、`test.sh` 出验证）并跑整机长跑验收。

**构成：1 个一次性门禁 spike + 6 个产品 Phase。** 门禁是 throwaway，不进产品代码库。

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: 桌面层级门禁 spike** - 🚧 一次性验证：视频能否待在桌面图标后面（不过则后面全部作废）
- [x] **Phase 2: 播放内核竖切** - 🧱 地基：桌面壁纸 + 菜单栏常驻 + 三个核心接口定死
- [x] **Phase 3: 系统事件仲裁** - 全屏/锁屏/熄屏/睡眠/电池自动让路 + veto 仲裁 + 从原处续播（可与 Phase 4 并行）
- [ ] **Phase 4: 媒体库与轮换** - 选文件夹、递归扫描、三种模式、到点就切、失效降级（可与 Phase 3 并行）
- [ ] **Phase 5: 设置窗口与即时生效** - UI-SPEC 落地 + 改动当场生效 + 运行状态卡
- [ ] **Phase 6: 转码与独立窗口** - 调系统 ffmpeg 转 MP4，视觉无损，产物不回流
- [ ] **Phase 7: 打包、开机自启与整机验收** - build.sh / test.sh / DMG / 未签名自启实测 / 长跑验收

**执行顺序：** `1 → 2 → {3 ‖ 4} → 5 → 6 → 7`

**并行机会：Phase 3 与 Phase 4 零耦合**，只共享 Phase 2 已定死的 `MediaLibrary` / `HoldArbiter` 接口 —— 接口先定死即可并行推进。其余严格串行。

## Phase Details

### Phase 1: 桌面层级门禁 spike 🚧

**Goal:** 用几小时的一次性 throwaway app 证明「视频待在桌面图标后面」这条路线在本机成立；证伪则整个架构作废，Phase 2–7 全部不启动。
**Mode:** mvp
**Depends on**: Nothing (first phase)
**门禁证伪的处置（已拍板 2026-10-03）**: 自动转**路线 B（`.saver` 屏保 bundle）**继续做，不回头问。路线 B 在 ARCHITECTURE §2.1 标注为「ScreenSaver 路线是补充而非替代」，`.saver` bundle 存在性已实测（系统自带 saver 在 macOS 27 上仍在），权限需求同样为「无」。
**门禁验收方式（已拍板 2026-10-03）**: 「桌面图标仍可点选/可拖动」无法自动化 → 用**强证据**推进：① 我方窗口 level 严格低于 Finder 桌面图标窗口 ② `CGWindowListCopyWindowInfo` 里 Finder 图标窗口在我方之上 ③ 截图 ④ `killall Finder` 后仍在。人工 10 秒肉眼确认**补做，不阻塞** Phase 2。
**Requirements**: 无 —— 门禁阶段不交付 v1 需求。它消解的是 PLAY-01 / PLAY-02 / PAUSE-01 / PAUSE-02 / SYS-02 的**可行性风险**，这些需求由 Phase 2 / Phase 3 交付。
**Success Criteria** (what must be TRUE):
  1. 一个挂在桌面层级的带帧号彩色窗口出现后，桌面图标**可点选、可拖动**，且 `killall Finder` 后壁纸仍在 —— 层级方案成立
  2. 层级写法定案并落进骨架代码：`NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))` 编译+运行通过；`.desktopIconWindow`（差 20，会盖住图标）被显式列为禁用项
  3. `MenuBarExtra` 在 `.accessory` 激活策略 + 无 Dock 图标下实测可用；若不可用，`NSStatusItem` 退路已验证可编译
  4. 全屏检测几何原型在**刘海屏 / Chrome 全屏 / 超宽屏**三种场景各产出一次判定结果，误判方向确认为「宁可少暂停，不要误暂停」
  5. `com.apple.screenIsLocked` 在本机 macOS 27 上是否触发有明确实测结论（决定 Phase 3 走标准模式还是升级为需调研）；`isOpaque = true` 的 `powermetrics` A/B 有数字结论

**Plans**: 5/5 plans executed
**Wave 1**
- [x] 01-01-PLAN.md — 桌面层级门禁 tracer：desktop-level NSWindow + 帧号 + 层级序/Finder 重启存活四项强证据 + D-08 两条对照路线（路线 C 私有框架 / 路线 D 硬编码 level）
- [x] 01-02-PLAN.md — `MenuBarExtra` + `.accessory` 主路线与 `NSStatusItem` 退路各跑一次并核对无 Dock 图标

**Wave 2** *(blocked on Wave 1 completion)*
- [x] 01-04-PLAN.md — WallpaperSpike 三种播放模式 + 锁屏通知探针 + `powermetrics` 四组 5 分钟 A/B（含人工 checkpoint，带 `AB_STATUS=skipped` 兜底产物）

**Wave 3** *(blocked on Wave 2 completion)*
- [x] 01-03-PLAN.md — 全屏几何原型：坐标系陷阱复现 + 三条内置几何自检（证明按 pid 聚合生效）+ 刘海屏/Chrome/超宽屏五场景各一条 coverage 数字

**Wave 4** *(blocked on Wave 3 completion)*
- [x] 01-05-PLAN.md — 门禁判定 `GATE=A|B` 收口 + `test.sh` 探针从 12 条增至 15 条

**Notes**:
- **throwaway，不进产品代码库** —— 产出是 `.planning/spike/` 下的一次性验证脚本/小 app
- `powermetrics` A/B 四组：不播 / v1 配置 / `isOpaque=false` / `AVPlayerView`，每组 5 分钟
- 顺带把路线 C / D 作为对照项
- 它本身**就是研究**，不是需要调研 —— 需要的是执行，不是 research-phase

### Phase 2: 播放内核竖切 🧱

**Goal:** 用户看到一个真正的菜单栏 app —— 桌面图标后面有视频在无缝循环播放，菜单栏能暂停/继续和退出，没有 Dock 图标；`SettingsStore` / `HoldArbiter` / `PlayerController` 三个接口在此定死，后续全部阶段依赖它。
**Mode:** mvp
**Depends on**: Phase 1（门禁通过 `GATE=A`）
**⚠ Phase 1 遗留的强制前置（PDCA-A1）**: Phase 1 的**全部**几何测量都在**锁屏会话**内完成（每条日志带 `LOCK=1`，`UserIsActive 0`）。门禁结论「路线 A 成立」的适用边界尚未在**有前台进程**的环境验证。**本 Phase 的第一个任务必须是：在解锁会话中重跑 `bash .planning/spike/run-gate.sh`，确认 `ORDER=ok` 与 `FINDER_RESTART_ALIVE=1` 仍成立。不通过则门禁结论降级为「仅锁屏会话下成立」，本 Phase 需重新评估。**
**Requirements**: PLAY-01, PLAY-02, MENUBAR-01, MENUBAR-03, MENUBAR-07, MENUBAR-08, PAUSE-08, SYS-02
**Success Criteria** (what must be TRUE):
  1. 启动后菜单栏出现常驻图标、Dock 无图标；桌面图标后面有一段视频在播放，点击和拖动桌面图标完全不受影响
  2. 视频按**裁剪填满**铺满主屏，无黑边、无变形；连续观察 5 分钟无缝循环，无黑帧、无卡顿、无跳帧
  3. 菜单项「暂停/继续」可用，且**从原处续播**不从头发；菜单项「退出」能真正结束进程
  4. 菜单**不显示当前播放的文件名**，只有固定的菜单项
  5. 切换 Space / 进台前调度后壁纸按系统默认行为表现（不消失、不报错），且未做任何 Space 级特殊处理

**Plans**: 4/4 plans executed（串行 4 波，wave N 依赖 wave N-1 —— 本 Phase 是地基，接口必须先定死才能让 Phase 3 ‖ Phase 4 并行）

Plans:
**Wave 1**
- [x] 02-01-PLAN.md — PDCA-A1 解锁会话门禁复跑（锁屏则如实 BLOCKED）+ SwiftPM 产品骨架 + ffmpeg 测试语料 + **三个接口定稿**（`SettingsStore` / `HoldArbiter` / `PlayerController`）+ 64 子集 veto 仲裁单测

**Wave 2** *(blocked on Wave 1 completion)*
- [x] 02-02-PLAN.md — tracer 竖切：桌面层窗口 + `AVPlayerLayer` 循环 + `MenuBarExtra` 常驻（一条路走通）+ SC2 的裁剪填满与 300 秒循环数字 + 几何内缩实测 + SYS-02 零-Space-处理源码判据

**Wave 3** *(blocked on Wave 2 completion)*
- [x] 02-03-PLAN.md — 菜单三项接 `HoldArbiter`（暂停/继续、打开设置骨架、退出）+ 从原处续播的两条锚点单测 + `QUIT_EXITED=1` 进程终止证据 + MENUBAR-08 哨兵单测（菜单不出现文件名）

**Wave 4** *(blocked on Wave 3 completion)*
- [x] 02-04-PLAN.md — `build.sh` 改指 `Sources/` 产出带 `LSUIElement` 的 `.app` 与 DMG + PDCA-A4 刷新回调复测 + `test.sh` 收口 + `02-VERDICT.md` 四栏诚实基线

**Notes**:
- 分层：`State/` + `Playback/` + `Render/`；`AppDelegate.wiring()` 是唯一装配点
- 用 `AVQueuePlayer` + `AVPlayerLooper` + `AVPlayerLayer`；`audioTimePitchAlgorithm = .spectral` 显式设（默认 `.timeDomain` 会变调）；`preferredForwardBufferDuration = 3.0`；`isOpaque = true` / `hasShadow = false` / `videoGravity = .resizeAspectFill`
- `HoldArbiter` 从第一天就建成 `Set<HoldReason>` veto 集合（先只接手动暂停）—— 形状对了才不会在 Phase 3 返工
- 防 Pitfall 4：切换视频前 `disableLooping()` → `removeAllItems()` → 再入队；observer 注册/注销严格配对
- 🔴 **PDCA（Phase 2）硬约束一：四类系统检测必须走事件通知，禁止逐帧轮询。** Phase 2 实测 `.app` 下显示刷新回调**仍是降级路径**（`DRIVER=timer_fallback_hz30`，27 Hz），且 `REFRESH_SESSION=locked` 表明**无法区分「`.app` 拿不到」与「锁屏压制」**。→ 锁屏/熄屏/睡眠/全屏四类检测一律走 `DistributedNotificationCenter` / `NSWorkspace` 事件，逐帧轮询方案直接排除。
- 🔴 **PDCA（Phase 2）硬约束二：`PIC_HOLD` 是 0.5 秒轮询不是事件驱动**（`WINDOWS.md` 登记），短于 0.5 秒的暂停会漏采 → 接线时改事件驱动。
- ⚠️ **PDCA（Phase 2）**：`AppDelegate.startWallpaper()` 有直连 `player.play()` 在菜单边界外，需 Phase 3 复核（`W-2026-10-03-10`）。
- ⚠️ **PDCA（Phase 2）A6：停止用「源码字面量 grep」做判据。** Phase 1 出现 5 次、Phase 2 出现 3 次「自己的判据被自己违反」（注释里的字面量污染 `grep -c`）。Phase 3 起：判据只扫不含注释的代码，或改用行为断言（单测/探针输出）不碰源码文本。
- 🔴 **PDCA-A2 硬约束：全屏检测禁用 0.95 覆盖率阈值。** Phase 1 实测 `FALSE_POSITIVE_OBSERVED=1`：Ghostty(pid 1227) 与 CC Switch(pid 1228) 各把 `visibleFrame`(1470×833) 铺满 → `coverage=1.000` ≥ 0.95 被判成全屏，但两者 bounds 高 833 < 屏幕 frame 高 956，结构上够不到刘海，**可证不是全屏**。coverage 已顶在 **1.000 上限**，任何阈值调整都改不了。**必须二选一**：① 设计几何之外的判别信号（如 `activeSpaceDidChangeNotification` 关联 / Space 序号）；② 明确写下接受「误暂停」方向并编码进 `PauseReason`。**默认沿用 0.95 阈值 = 本 Phase 的 BLOCKER。**
- 🔴 **PDCA-A5 几何内缩**：桌面层 borderless 窗口的 `CGWindowList` bounds 有系统性 **14pt/9pt** 内缩（叠加刘海 33pt 共 47pt）。任何覆盖率/全屏几何计算必须先处理，否则真全屏永远算不到 1.000。
- ⚠️ **PDCA-A7 锁屏跃迁未验证**：`CGSSessionScreenIsLocked` 只验证了**能读出状态**（40 秒 9 次采样全为 1），**未验证跃迁时是否翻转**。Phase 3 必须实测跃迁才能写进产品代码。
- 防 Pitfall 5：文件存在性检查统一用 `URL.path`（**不要喂 `absoluteString`**）
- 防 Pitfall 7：暂停/恢复走**同一个 `re-evaluate()`** 入口
- 本 Phase 不交付：声音/速度控件（Phase 5）、文件夹选择面板（Phase 4）—— 开发期用 `UserDefaults` 直接指一个测试目录

### Phase 3: 系统事件仲裁（veto 状态机）

**Goal:** 壁纸在用户不需要的时候自动让路，且**每次暂停都能说出为什么** —— 各类系统事件各自独立可测，多条件叠加时按 veto 集合正确仲裁，解除后从原处续播。
**Mode:** mvp
**Depends on**: Phase 2（接口）· **与 Phase 4 零耦合，可并行**
**Requirements**: PAUSE-01, PAUSE-02, PAUSE-03, PAUSE-04, PAUSE-05, PAUSE-06, PAUSE-07
**Success Criteria** (what must be TRUE):
  1. 任意应用进入全屏 → 壁纸暂停；退出全屏 → 从暂停处续播（不从头）；**刘海屏 / Chrome / 超宽屏**三种场景各验证一遍
  2. 锁屏 / 显示器熄屏 / 系统睡眠 三类事件各自触发暂停，解除后各自正确续播
  3. 「电池供电时暂停」开关**默认关闭**；打开后拔电源暂停、插回续播
  4. **veto 仲裁正确**：锁屏状态下退出全屏，壁纸**不**恢复播放；多条件叠加时只有集合清空才续播
  5. 续播锚点不漂移：锚点在 `holds` 由空变非空时写入、由非空变空时消费，叠加暂停期间不被二次覆盖

**Plans**: 5/5 plans executed

**Wave 1**
- [x] 03-01-PLAN.md — tracer：HoldReason 补到 6 case（幂集恰 64）+ LockWatcher 端到端接进 HoldArbiter + `PIC_HOLD` 改事件驱动 + `test.sh` 第一批判据

**Wave 2** *(blocked on Wave 1 —— 三个 plan 各自独占源文件/脚本/evidence，零文件重叠，可并行)*
- [x] 03-02-PLAN.md — 全屏检测：几何（14/9 内缩 + 坐标翻转）与几何外信号**缺一不可**的合取判定 + `styleMask` 不可得实测
- [x] 03-03-PLAN.md — 熄屏（`CGDisplayIsAsleep` + 重配置回调）与睡眠（`willSleep`/`didWake`）两个独立 reason
- [x] 03-04-PLAN.md — 电池：IOKit `ps/` 事件源 + `SettingsStore.pauseOnBattery`（**默认关闭**，纯追加）

**Wave 3** *(blocked on Wave 2 completion)*
- [x] 03-05-PLAN.md — 装配四根 Watcher 线 + D-12 的 `HoldStatus` 数据落点 + D-06 起播路径收口 + 活体 evidence + `03-VERDICT.md`

**Notes**:
- 4 个 Watcher（`FullscreenDetector` / `LockWatcher` / `PowerWatcher` / `DisplayWatcher`）**只产出 `HoldReason`，不直接碰播放器**；单向流 `Watcher → HoldArbiter → PlayerController`
- **不要用优先级链做决策**（本域反模式 2：锁屏 + 全屏反例）；优先级只用于 UI 文案排序
- 事件驱动，不要 500ms 轮询（轮询只在调研期 demo 可接受）
- 必须对外暴露「当前为什么暂停」—— 这是 UI-04 的落点
- 纯逻辑单测：`HoldArbiter` 不 import AVFoundation，毫秒级；另加启动时层级常量单测锁死魔法数字
- ⚠️ 若 Phase 1 的锁屏通知实测失败，本 Phase **升级为需要 research**（真正的降级方案未找到公开资料）
- ⚠️ **规划期已记的两处计划事实更正**（已进 `03-01` / `03-04` 的任务文本）：① `HoldReason.swift` 的 Phase 2 注释给 `fullscreen` 的 `order = 0` 与 `manualPause` 撞值，会让 `activeReasons` 排序不确定 —— 03-01 取 1…5，`manualPause` 的 0 不动；② CONTEXT 称 `SettingsStore` 已含 battery 开关位，实际没有 —— 03-04 以带默认值的参数**纯追加**

### Phase 4: 媒体库与轮换

**Goal:** 用户指定一个文件夹，app 递归扫出里面所有能播的视频，按他选的模式循环/随机播放，到点就切；文件夹没了就干净地让出桌面，露出系统原壁纸。
**Mode:** mvp
**Depends on**: Phase 2（接口）· **与 Phase 3 零耦合，可并行**
**Requirements**: SOURCE-01, SOURCE-02, SOURCE-03, SOURCE-05, SOURCE-06, SOURCE-07, SOURCE-08, PLAY-03, PLAY-04, PLAY-05, PLAY-06, MENUBAR-04, MENUBAR-05, SYS-03
**Success Criteria** (what must be TRUE):
  1. **首次启动直接弹出文件夹选择框**（无引导流程）；选完立即开始播放该目录及其**递归子目录**里的视频
  2. 只识别 MP4 / MOV / M4V，且排除扩展名对但解不出视频轨的文件
  3. 三种模式（单循环 / 列表循环 / 列表随机）切换当场生效；轮换时间**到点就切**不等当前视频播完；菜单项「立即下一个」即时生效
  4. 下次启动自动读取已配置文件夹并开始播放；换文件夹后立即播新目录；菜单项「重新扫描文件夹」可用，且扫描结果被缓存而非每次切片重扫
  5. 目录里没有可用视频、或文件夹被删/被移动 → **壁纸窗口隐藏，露出系统原壁纸**（不留黑屏、不崩溃）

**Plans**: 7 plans
- [x] 04-01-PLAN.md
- [x] 04-02-PLAN.md
- [x] 04-03-PLAN.md
- [x] 04-04-PLAN.md
- [x] 04-05-PLAN.md
- [x] 04-06-PLAN.md
- [ ] 04-07-PLAN.md — gap 修复：SC3 单循环下「立即下一个」按 reason 前进 + 切换空帧消除（G-04-3 / G-04-3b）

**Notes**:
- `FileManager.enumerator` 递归扫描 + 扩展名过滤 + `AVURLAsset` 校验可加载视频轨
- 防 Pitfall 5：扫描结果**做缓存**（递归目录会放大重扫的 I/O 代价）
- 防 Pitfall 6：订阅 `NSWorkspace.activeSpaceDidChangeNotification` 主动 re-assert；**不承诺 Space 级持久配置**
- 无可用视频 / 文件夹失效 → `PlayerController.stop()` + `orderOut(nil)`；因为从不改系统壁纸、只是盖了一层，原壁纸会自然露出
- SOURCE-04（计数与空态**显示**）归 Phase 5 —— 它的呈现形态由 UI-SPEC §6 定义，属于界面工作；行为部分（扫描、降级）留在本 Phase

### Phase 5: 设置窗口与即时生效

**Goal:** 用户有一个按 UI-SPEC 定稿的设置窗；所有可调项改完**当场生效**；扫不到视频时界面明确告诉他壁纸已隐藏；任何时候都能看到「现在为什么暂停」。
**Mode:** mvp
**Depends on**: Phase 2（`SettingsStore`）· Phase 3（暂停原因）· Phase 4（可调项）
**Requirements**: SOURCE-04, UI-01, UI-02, UI-03, UI-04, PLAY-07, PLAY-08, PLAY-09, PLAY-10, MENUBAR-02, MENUBAR-06
**Success Criteria** (what must be TRUE):
  1. 菜单栏「打开设置」打开**780pt 固定宽 / min 680pt**、B1 深海 + L4 双列、无侧边栏的设置窗（按 `.planning/UI-SPEC.md`）；关闭窗口只隐藏，**进程不退出、图标仍在**
  2. 空态：可用视频计数为 0 时数字转警告黄 + 感叹号瓷砖 + 文案「没找到能播的文件。壁纸已隐藏，桌面显示的是系统原壁纸。」
  3. 两条置灰联动正确且**禁用交互**（非只调透明度）：单循环 → 轮换时间整行置灰；声音关闭 → 音量滑杆置灰
  4. 速度（0.5×–2×，**保持原音高** —— 实际听 0.5× / 2× 的人声确认不变调）与声音开关/音量**改动当场生效**，不重启、不等下次换片，且重启 app 后保留
  5. 运行状态卡显示：当前是否暂停 + **暂停原因**（全屏/锁屏/熄屏/睡眠/电池）+ ffmpeg 可用性

**Plans**: 2/4 plans executed (pending)（串行 4 波，wave N 依赖 wave N-1）

**Wave 1**
- [x] 05-01-PLAN.md — xcodeproj + 设置窗 tracer：SettingsPresentation / SettingsApplier / SettingsView / SettingsComponents 骨架与菜单栏「打开设置」接线

**Wave 2** *(blocked on Wave 1 completion)*
- [x] 05-02-PLAN.md — 六项绑定 + 置灰联动：速度/声音/音量等改动当场生效（`rate` / `volume` 挂 `AVPlayer`）+ 单循环→轮换时间、声音关→音量两条禁用交互置灰

**Wave 3** *(blocked on Wave 2 completion)*
- [ ] 05-03-PLAN.md — 空态 + 运行状态卡：计数 0 警告黄空态瓷砖、暂停原因（全屏/锁屏/熄屏/睡眠/电池）与 ffmpeg 可用性展示

**Wave 4** *(blocked on Wave 3 completion)*
- [ ] 05-04-PLAN.md — XCUITest + 门禁收口：SettingsWindowUITests / SettingsControlsUITests + `run-uitests.sh` 进 `test.sh`

**UI hint**: yes
**Notes**:
- 起点不是零：`.planning/spike/SettingsSpike.swift` 已编译渲染；UI-SPEC §11 记录了踩过并修掉的 2 个坑（卡片 `clipShape` 裁掉图标砖发光 → 改 `background` + `overlay` 描边；写死高度留白 → 改 `.fixedSize`）
- 两处必要自造成本（自绘滑杆、自绘分段控件）—— 字体用系统默认（2026-10-03 拍板，不打包 IBM Plex Mono），不再新增自造组件
- `rate` / `volume` 挂 `AVPlayer`，**不挂 `AVPlayerItem`**（looper 副本初始化时冻结，挂 item 会让「立即生效」变成假的）
- `audioTimePitchAlgorithm` 变更**需要重建 `AVPlayerItem`**（少数改不了 live 对象的例外）—— 重建后 seek 回 resumeAnchor
- 发光 = 阴影 + 模糊，吃 GPU；设置窗偶尔开无妨，**不要做成常驻动画**，并尊重 `prefers-reduced-motion`
- 首次启动弹框已在 Phase 4；本 Phase 的「选择…」按钮复用同一个 `NSOpenPanel`
- 开机自启开关按 UI-SPEC 渲染，**行为接线在 Phase 7**（SYS-01）
- 不需要外部 research（UI-SPEC 已定稿）；但需要 `/gsd-ui-phase` 把 UI-SPEC 转成 UI 契约

### Phase 6: 转码与独立窗口 ⚠️

**Goal:** 用户能把 mkv/avi/webm 转成能硬解的 MP4，画质视觉无损，产物落在壁纸目录内且不会被当成新的待转码输入；没有 ffmpeg 时功能降级而不是阻断。
**Mode:** mvp
**Depends on**: Phase 4（`MediaLibrary`）
**Requirements**: TRANS-01, TRANS-02, TRANS-03, TRANS-04, TRANS-05, TRANS-06
**Success Criteria** (what must be TRUE):
  1. 能检测 PATH 中的 `ffmpeg`；检测不到时转码入口**置灰**并给出**多条**安装途径（含 `brew install ffmpeg` 与**静态二进制** —— macOS 27 上 brew 会因 `lame` / `dav1d` 无 bottle 直接失败），其余壁纸功能不受影响
  2. 转码窗口显示任务队列、进度、以及**将要执行的实际命令**（可审计）
  3. MKV / AVI / WebM 转成 MP4（H.264）后能被硬解播放，与源片对比**人眼基本看不出差异**
  4. 产物落在**用户选择的壁纸目录内**，原视频保留不删
  5. 产物**不会被再次扫描**成待转码输入（反复扫描不产生死循环），半成品 `.tmp` 不进播放目录，转完的 MP4 立即可被壁纸播到

**Plans**: 3/5 plans executed (pending)（wave 1 双并行 → 2 → 3 → 4 串行）

**Wave 1** *(06-01 与 06-02 零文件重叠，可并行)*
- [x] 06-01-PLAN.md — 参数构造内核：TranscodeCommand（实际命令可审计）/ TranscodeOutputNaming（`Converted/` 产物命名）/ TranscodeCandidateFilter / ConvertedLibrary，纯逻辑 + 单测
- [x] 06-02-PLAN.md — 检测 + 进度解析：ExternalToolLocator（PATH 探测 `ffmpeg`，检测不到多条安装途径）+ ProgressParser

**Wave 2** *(blocked on Wave 1 completion)*
- [x] 06-03-PLAN.md — 执行层 + 活体：TranscodeQueue + ProcessTranscodeRunner（`terminationStatus` 退出码、`.tmp` 再 rename）+ tracer 驱动脚本

**Wave 3** *(blocked on Wave 2 completion)*
- [ ] 06-04-PLAN.md — 独立转码窗口：TranscodeWindowView / TranscodeViewModel / InstallPathwaysView —— 队列、进度、将要执行的实际命令展示

**Wave 4** *(blocked on Wave 3 completion)*
- [ ] 06-05-PLAN.md — 装配收口：AppDelegate 接线 + `transcode-bench.sh` + `test.sh` 判据 + `06-VERDICT.md`

**UI hint**: yes
**Notes**:
- **产物目录（已拍板 2026-10-03）**：`<壁纸目录>/Converted/`。扫描器排除该目录名即杜绝回流（TRANS-05）；产物本身是 MP4，天然不进「非原生格式」队列，双保险
- ⚠️ **阻塞项（开工前必须解）**：「视觉无损」的 CRF / preset / 编码器未定（libx264 vs libx265 vs svt-av1 vs VideoToolbox hw）；产物命名 / 目录规则待设计（防扫描死循环）；GPL v3.0 在自用场景的义务边界【待验证】→ **本 Phase 需要深度 research-phase**
- 本机现实：`which ffmpeg` 曾为 not found；最终用 evermeet.cx 静态二进制装成 9.0.2 —— 安装提示不能只写 brew 一条
- 退出码必须用 `Process.terminationStatus`，**绝不用管道**（`cmd | tail` 恒返回 0，等于没检测）
- 输出写 `xxx.tmp` 再 rename；先检查剩余空间；转码与播放不抢资源（`nice` 或串行化）
- **转码窗口是全 app 唯一允许出现列表的地方**（用户否掉的是浏览式列表；任务队列是操作产物）—— 写进计划，否则会被当 scope creep 砍掉
- 参考 `.planning/UI-SPEC.md` §8

### Phase 7: 打包、开机自启与整机验收

**Goal:** 产出用户真的能装能用的东西 —— 一条命令构建出 DMG，一条命令跑完所有自动化验证，未签名 app 上的开机自启有明确结论，整机长跑验收通过。
**Mode:** mvp
**Depends on**: Phase 3 · Phase 4 · Phase 5 · Phase 6
**Requirements**: SYS-01, PACK-01, PACK-02, PACK-03, PACK-04
**Success Criteria** (what must be TRUE):
  1. `build.sh` 一条命令跑完：编译 → 产出 `.app` → 用 `create-dmg` 生成 DMG；零手工步骤，重复执行结果一致
  2. `test.sh` 一条命令跑完所有可自动化验证（编译检查 + 可脚本化单测/验收项）；全绿退出 0，任一失败退出非零
  3. 未签名 app 的开机自启有**实测结论**并落地：「需手动设一次」的 `requiresApproval` 分支有引导；若 `SMAppService` 在未签名 app 上不可用，退路是写 `~/Library/LaunchAgents/` plist，开关仍能真实生效
  4. 压力验收：连续换片 **50 次内存回到基线 ±10%**；连续 **20 轮 休眠/唤醒/锁屏/解锁** 播放状态 100% 正确、无黑屏灰屏
  5. 长跑验收：DMG 装出的 `.app` 连续运行 **≥7 天**不重启、不崩溃、内存无单调上涨；电池供电时按设置正确让路，且整段时间内看不出壁纸在播视频

**Plans**: TBD
- [x] 07-01-PLAN.md
- [ ] 07-02-PLAN.md
- [ ] 07-03-PLAN.md
- [ ] 07-04-PLAN.md

**Notes**:
- **不签名、不公证**（用户已定），但**要 DMG**；本机已装 `create-dmg` 1.3.0（`/opt/homebrew/bin/create-dmg`）—— 打包是小任务，不是大 Phase
- 两个脚本尽量短：能用 `xcodebuild` / `swiftc` / `create-dmg` 现成命令解决的不要自己写逻辑（最小代码量方针）
- PACK-02 是约束不是工作项：不做上架动作、不需要沙盒
- ⚠️ SYS-01 是本 Phase 最大不确定点（未签名 app 上 `SMAppService` 行为待实测）
- 主屏、非 App Store、可用非公开 API —— 边界在此封板

## Requirement Coverage

**64 / 64 v1 需求已映射 —— 无孤儿、无重复。**

| Phase | Requirements | Count |
|-------|--------------|-------|
| 1 | —（门禁，不交付需求） | 0 |
| 2 | PLAY-01, PLAY-02, MENUBAR-01, MENUBAR-03, MENUBAR-07, MENUBAR-08, PAUSE-08, SYS-02 | 8 |
| 3 | PAUSE-01 ~ PAUSE-07, TEST-01 | 8 |
| 4 | SOURCE-01, SOURCE-02, SOURCE-03, SOURCE-05, SOURCE-06, SOURCE-07, SOURCE-08, PLAY-03 ~ PLAY-06, MENUBAR-04, MENUBAR-05, SYS-03, TEST-02, TEST-03 | 16 |
| 5 | SOURCE-04, UI-01 ~ UI-04, PLAY-07 ~ PLAY-10, MENUBAR-02, MENUBAR-06, TEST-04, TEST-07, TEST-08, TEST-09, TEST-10 | 16 |
| 6 | TRANS-01 ~ TRANS-06, TEST-05, TEST-06 | 8 |
| 7 | SYS-01, PACK-01, PACK-02, PACK-03, PACK-04, ASSET-01, ASSET-02, ASSET-03 | 8 |

两处与调研建议不同，都是「一条需求只能绑一个 Phase」的直接结果，已显式记录：

- **SOURCE-04（计数 + 空态显示）** 从 Phase 4 挪到 Phase 5 —— 它的呈现形态由 UI-SPEC §6 定义，属于界面工作；扫描与降级的**行为**部分留在 Phase 4
- **PAUSE-08 + MENUBAR-03（菜单栏手动暂停/继续）** 从 Phase 3 挪到 Phase 2 —— Phase 2 就要建 `HoldArbiter` 并先接手动暂停，它是第一个能交付这两条的 Phase

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 → 6 → 7
（Phase 3 与 Phase 4 可并行推进；其余严格串行）

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. 桌面层级门禁 spike | 5/5 | Done| 2026-10-03 |
| 2. 播放内核竖切 | 4/4 | Done| 2026-10-03 |
| 3. 系统事件仲裁 | 5/5 | Done | 2026-10-03 |
| 4. 媒体库与轮换 | 6/7 | In Progress|  |
| 5. 设置窗口与即时生效 | 2/4 | In Progress|  |
| 6. 转码与独立窗口 | 3/5 | In Progress|  |
| 7. 打包、开机自启与整机验收 | 1/4 | In Progress|  |

---

*Roadmap created: 2026-10-03*
