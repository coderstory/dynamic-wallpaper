# Phase 4: 媒体库与轮换 - Context

**Gathered:** 2026-10-03
**Status:** Ready for planning
**Mode:** mvp

<domain>
## Phase Boundary

用户指定一个文件夹，app 递归扫出里面所有能播的视频，按他选的模式循环/随机播放，到点就切；文件夹没了就干净地让出桌面，露出系统原壁纸。

**与 Phase 3 零耦合**（ROADMAP 明写），可并行推进，只共享 Phase 2 定死的接口。

**Phase 4 不做**：SOURCE-04（可用视频计数与空态**显示**）—— 那是 Phase 5 的界面工作；本 Phase 只做扫描与降级的**行为**。

</domain>

<decisions>
## Implementation Decisions

### 已冻结接口（Phase 2 定死 + Phase 3 已扩展，只可纯增量）

- **D-01:**  `PlayerController` 公开面：`attach` / `load` / `setRate` / `setVolume` / `setMuted` / `arbiterCurrentPosition` / `arbiterSeek` / `arbiterApply`
- **D-02:**  `HoldArbiter` 公开面：`attach` / `isManuallyPaused` / `set(_:active:)` / `applyCurrentDecision()` / `holdStatus`
- **D-03:**  `SettingsStore.Key` 现有 **7 键**：`sourceFolderPath` / `rate` / `volume` / `muted` / `playMode` / `rotationInterval` / `pauseOnBattery`。**不得重写这 7 键。**
- **D-04:**  `PlayMode` 现有 **1 个 case**：`loopSingle`。本 Phase 纯增量加 `loopList` 与 `shuffle`，**不得改 `loopSingle` 的 rawValue**（它可能已持久化到用户偏好）。

### 本 Phase 的核心行为

- **D-05:**  递归扫描用 `FileManager.enumerator`（**不是** `contentsOfDirectory` 手写递归）。
- **D-06:**  扩展名白名单 **MP4 / MOV / M4V**（SOURCE-03）。
- **D-07:**  扫描结果**做缓存** —— 递归目录会放大重扫的 I/O 代价。缓存失效条件由「重新扫描文件夹」显式触发，不做自动监听（LIB-01 是 v2）。
- **D-08:**  除扩展名白名单外，还要用 `AVURLAsset` 校验**可加载视频轨** —— 扩展名对但解不出视频轨的文件必须排除。
- **D-09:**  文件存在性检查统一用 `URL.path`，**绝不喂 `absoluteString`**（Pitfall 5）。
- **D-10:**  「到点就切」= **不等当前视频播完**（PLAY-06）。轮换计时器与播放进度**解耦**。
- **D-11:**  无可用视频、或文件夹被删/移动 → `PlayerController` 停止 + **壁纸窗口 `orderOut(nil)` 隐藏**，露出系统原壁纸。因为从不改系统壁纸、只是盖了一层，原壁纸会自然露出。**不留黑屏、不崩溃。**
- **D-12:**  首次启动直接弹 `NSOpenPanel`（SYS-03），**无引导流程**。选完立即开始播放该目录及其递归子目录。

### 继承自 Phase 1/2/3 的硬约束

- **D-13:**  🔴 **停止用「源码字面量 grep」做判据。** Phase 1 五次 + Phase 2 三次 + Phase 3 四次自伤（注释里的字面量污染 `grep -c`）。必须用 `test.sh` 的 `src_count()`（4 条 `-e`：`^\s*//`、`^\s*\*`、`^\s*/\*`、`^\s*\*/`），或改用行为断言。
- **D-14:**  ⚠️ **新判据的 `no()` 文案必须带 `ok()` 的同一句判据名（逐字相同），红绿靠 ✅ / ❌ 前缀区分。** Phase 3 连续踩了三次（03-01/03-02/03-04）—— 失败文案写成另一句，判据转红了但 `grep -c '❌ <判据名>'` 命中 0，查不到哪条红了（`test.sh:144-147` 记录 03-01 首跑事故）。做法：**判据一个不放宽，改文案**；`no()` 的判据名与 `ok()` 逐字相同，第二参数才写差异（活体代码见 `test.sh:265-268` 的 `ok "…" || no "…"`）。
- **D-15:**  ⚠️ **反向验证的插桩可能打在自己写的注释上**（03-04 踩过）。**改注释不改判据。**
- **D-16:**  ⚠️ **编译失败冒充「判据转红」是反模式**（W-17）。插桩要保证 `MUTATED_RC` 来自**断言失败**而非编译失败。
- **D-17:**  ⚠️ **一个数不能有两种读法**（03-04 踩过）。一个计数器若同时承载两种含义，读的人会误读。拆成多行分开打点。
- **D-18:**  ⚠️ **W 编号必须全 Phase 唯一**（03-03/03-04 撞过 -19）。分配不重叠号段，并加 `uniq -d` 为 0 的判据。
- **D-19:**  层级写法照抄：`NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))` = **-2147483623**；`.desktopIconWindow`（-2147483603）**禁用**。
- **D-20:**  按 **PID** 认领自己的窗口，不按 layer（本机 `FOREIGN_DESKTOP_FAMILY=7`）。
- **D-21:**  用户已拍板：**转码产物落 `<壁纸目录>/Converted/` 子目录**，扫描器**排除该目录名**即杜绝回流（TRANS-05 的防死循环）。产物本身是 MP4，天然不进「非原生格式」队列，**双保险**。
- **D-22:**  ⚠️ **递归扫描本机那个 42GB / 484 文件的目录会非常慢。** 测试**绝不可**对全目录做完整递归 —— 造一个小型 fixture 树（多子目录、深嵌套、混合扩展名、空目录、不存在路径、无权限目录）用于测试。真实目录只做**一次**抽样计时，不作为测试用例。

### 环境事实（不要重新推导）

- 本机 `~/Movies/视频壁纸` 有 **484 个 mp4 / ~42GB**；`ls` 顶层取样，**禁止递归遍历**
- 屏幕**锁着**且**显示器已熄灭**（`CGDisplay_IS_ASLEEP=1`）
- 无 `timeout` → `perl -e 'alarm N; exec @ARGV' CMD ...`
- FreeBSD grep（BRE 里 `?` 是字面量 → 用 `grep -E`）
- bash 保留 `GROUPS` 数组 → 绝不当普通变量
- 屏幕录制权限**已授权**（`screencapture` YAVG 16→242），但屏幕锁着 + 显示器熄了，抓不到真实桌面
- `Package.swift` 用 `.swiftLanguageMode(.v5)`；测试框架 **XCTest**；零第三方依赖
- 基线：`swift test` 45 tests、`bash test.sh` 通过 40 失败 0

### Claude's Discretion
- 缓存的数据结构与失效策略的具体形态
- 「立即下一个」的实现（重置计时器 vs 换片后重置）
- 扫描与播出的调度（同步扫 / 后台队列 / 惰性分页）

</decisions>

<specifics>
## Specific Ideas

**降级必须干净。** 文件夹没了不是错误弹窗，是**安静地让出桌面**。用户可能几天后才回来，发现壁纸没了 —— 那应该是自然结果，不是崩溃。

**扫描必须防死循环。** 用户已定的 `Converted/` 排除是第一道；转码产物是 MP4 进不了「非原生格式」队列是第二道。**两层都要有判据。**

**随机模式要能验证。** 「列表随机」在测试里怎么断言？纯随机会让测试不稳定 —— 需要可注入的随机源或种子，否则这条判据不可靠。

</specifics>

<canonical_refs>
## Canonical References

- `.planning/phases/03-system-events/03-VERDICT.md`（Phase 3 判定；**若尚未产出，读 `03-CONTEXT.md` 的 D-01…D-12**）
- `.planning/phases/02-playback-core/02-VERDICT.md`（Phase 2 判定）
- `Sources/PicCore/State/SettingsStore.swift` · `HoldArbiter.swift` · `HoldReason.swift`
- `Sources/PicCore/Playback/PlayerController.swift` · `Sources/PicCore/Render/WallpaperWindow*.swift`
- `.planning/WINDOWS.md`（**Phase 3 用了 -14 ~ -22；Phase 4 从 -23 起**）
- `.planning/ROADMAP.md` Phase 4 的 5 条 Success Criteria
- `.planning/REQUIREMENTS.md` 的 SOURCE-*/PLAY-03~06/MENUBAR-04/05/SYS-03

</canonical_refs>

<constraints>
## Constraints

- **最少代码**：优先系统/框架现成能力（`FileManager.enumerator` 而非手写递归）
- **零第三方依赖**
- **诚实基线**：明确区分「跑过 / 没跑过 / 应该能跑但未测 / 假定依赖」。判据不得用形容词
- **不伪造数字**：任何度量必须来自真跑过、可复现的命令
- **Phase 4 零 UI**：SOURCE-04 的计数与空态**显示**是 Phase 5 的活；本 Phase 只产出数据
- **屏幕锁着**：无法靠视觉验证的项如实标 BLOCKED + 原因，继续推进不阻塞

</constraints>
