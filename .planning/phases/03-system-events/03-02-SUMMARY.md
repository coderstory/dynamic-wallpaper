---
phase: 03-system-events
plan: 02
subsystem: playback-core
tags: [fullscreen-detector, d-02, d-03, d-04, sys-02, stylemask, test-03-02]
status: complete

requires: [PAUSE-01]
provides:
  - FullscreenGeometry 纯值层（零 AppKit/CoreGraphics/AVFoundation，含 14/9 内缩与左上→左下翻转）
  - FullscreenSignals 4 字段 + FullscreenVerdict.verdict（合取：D-02 的落点）
  - FullscreenDetector（3 个公开 NSWorkspace 通知 + re-evaluate()，零 AVFoundation）
  - styleMask 跨进程不可得 —— 字典键普查实测（11 键，含 tyle/ullScreen 者 0）
  - test.sh SYS-02 判据口径改为两条排除式判据
  - scripts/probe-fullscreen.sh + evidence/fullscreen-signals.log
depends_on: [03-01]
affects: [03-03, 03-04, 03-05]

tech-stack:
  added: []
  patterns:
    - 几何层纯值化：输入是传进来的数，所以锁屏会话下也能被单测全覆盖（D-09 分层前提）
    - 通知只当触发器，重算时重读当前值（与 LockWatcher 的 T-03-01 同形）
    - 合取而非阈值：coverage 顶在 1.000 上限，调阈值改不了任何事

key-files:
  created:
    - Sources/PicCore/System/FullscreenGeometry.swift
    - Sources/PicCore/System/FullscreenDetector.swift
    - Tests/PicCoreTests/FullscreenGeometryTests.swift
    - Tests/PicCoreTests/FullscreenDetectorTests.swift
    - .planning/spike/FullscreenDetectorDriver.swift
    - scripts/probe-fullscreen.sh
    - .planning/phases/03-system-events/evidence/fullscreen-signals.log
  modified:
    - test.sh
    - .planning/WINDOWS.md

decisions:
  - 几何参考值命名为 FullscreenGeometryReference.covering 并在文件头写明「它不是判定阈值」，
    避免下一个读者把它当成可调旋钮（Phase 1 栽的正是这一步）
  - FullscreenDetector 的静态枚举/键普查标 nonisolated —— @MainActor 类上的 static 默认继承隔离，
    不标则闭包默认值在非隔离上下文调不通
  - SYS-02 判据 ② 用 kCGSSpace / CGSSetActiveSpace 而非 activeSpaceUserInfoKey：
    后者在本机 SDK 里不存在（编译报 has no member），拿它当 token 会绿得没有意义 → W-17
  - D-02 的语义降级显式登记为 W-18：交付的是合取，不是「信号可独立触发」

metrics:
  duration: 518s
  completed: 2026-10-03
  tasks: 2

actuals:
  tokens: 34000
  tasks: 2
  commits: 2

commits: 2
plan_head_before: 64895969beba27f870f2aacca848a3d65f1476da
plan_head_after: fbc7e54
---

# Phase 3 Plan 02: 全屏检测 —— 把 D-02 做成可单测的合取判定 Summary

**几何单独为真时判定为 false**，并拿 Phase 1 那条实测反例（Ghostty `coverage=1.000` 但可证不是全屏）当第一个测试夹具。

## What was built

**`FullscreenGeometry`（纯值层）。** `ScreenRect` / `DesktopWindowInset` / `WindowRectSample` / `CoverageResult` + 四个静态函数。**零 AppKit、零 CoreGraphics、零 AVFoundation** —— `NSScreen` / `CGWindowList` 的读取留给探测器，这里只处理传进来的数。这样几何层在锁屏会话下也能被单测覆盖全部基准，不需要任何窗口服务器配合。Phase 1 探针的 `aggregate` 逐字照搬：按 pid 分组 → 组内逐 rect 内缩补偿 → 翻转 → 与 `visibleFrame` 求交 → 组内求和 → 除面积 → `min(1.0)` → 不同 pid 取最大。

**`FullscreenVerdict.verdict` 是合取：`s.nonGeometricActive && s.covering`。** 四个输入全部可注入，锁屏会话下四种组合一次走完。

**`FullscreenDetector`（零 AVFoundation）。** 三个公开 `NSWorkspace` 通知（Space 变更 / 应用激活 / 应用失活），每个通知只当触发器，收到后一律重算重读当前几何，不记边沿。token 数组 + `stop()` 逐个摘（T-03-08）。

**`styleMask` 候选 ① 结构上不适用，已从推断变成实测。** 字典键普查 11 个键，含 `tyle` / `ullScreen` 的行数 **0** → `STYLEMASK_UNAVAILABLE=1 reason=not_a_key_in_CGWindowList_dictionary`。**未退回纯几何阈值**（D-02 明令）。

**`test.sh` 的 SYS-02 口径从「token 出现 0 次」改为两条排除式判据**，不变量本身一个字未改，插桩反向验证实跑。

## Verification actually run

| 项 | 结果 |
|---|---|
| `swift build` | RC=0 |
| `swift test` | **45 项全绿**（03-01 基线 36 + 本 plan 9） |
| `swift test --filter FullscreenGeometryTests` | `Executed 5 tests, with 0 failures` |
| `swift test --filter FullscreenDetectorTests` | `Executed 4 tests, with 0 failures` |
| `bash test.sh` | **通过 40 失败 0 跳过 0**（03-01 基线 39 + 新判据净增 1） |
| `bash scripts/probe-fullscreen.sh` | RC=0，`style_keys=0` |

`evidence/fullscreen-signals.log`（28 行）的关键段：

```
FULLSCREEN_SIGNALS_REGISTERED=1 space=NSWorkspaceActiveSpaceDidChangeNotification activate=NSWorkspaceDidActivateApplicationNotification deactivate=NSWorkspaceDidDeactivateApplicationNotification
SCREEN_FRAME=0.0,0.0,1470.0,956.0
VISIBLE_FRAME=0.0,90.0,1470.0,833.0
COVERAGE=1.000
COVERING=1
NON_GEOMETRIC=0
WINDOW pid=1227 owner=Ghostty layer=0 alpha=1.00 bounds=0.0,33.0,1470.0,833.0
WINDOW_DICT_KEY_COUNT=11
WINDOW_DICT_STYLE_KEY_COUNT=0
STYLEMASK_UNAVAILABLE=1 reason=not_a_key_in_CGWindowList_dictionary
FULLSCREEN_VERDICT=0 reason=geometry_without_signal coverage=1.000 non_geometric=0
FULLSCREEN_TRANSITION=unobservable reason=session_locked CGSSessionScreenIsLocked=1
```

**`COVERAGE=1.000 COVERING=1 NON_GEOMETRIC=0 → FULLSCREEN_VERDICT=0`** —— 这是 D-02 核心反例的**活体读数**，不是重放的夹具：Ghostty(pid 1227) 与 DevDesk(pid 1139) 此刻都在线，都把 `visibleFrame` 铺满，纯几何阈值在这里会判成全屏。

### 三次反向验证（真跑，不是声称）

**① 把合取改成单侧 → 测试转红。** 备份 → `perl -0pi -e 's/s\.nonGeometricActive && s\.covering/s.covering/'` → `swift test --filter FullscreenDetectorTests` RC 0 → **1**：

```
FullscreenDetectorTests.swift:37: error: -[PicCoreTests.FullscreenDetectorTests testGeometryAloneNeverTriggersFullscreen] :
  XCTAssertFalse failed - D-02：几何足够时没有几何外信号，一律不得判成全屏
```

`MUT=1 VER=3`（`perl` 确认改到了函数体，不是没匹配上）。恢复后 `cmp -s` 与备份逐字节一致。

**② 几何退化成逐窗口取最大 → 两条基准同时转红。** `perl` 把 `cov = min(1.0, sum/vArea)` 换成 `cov = min(1.0, best)`，`swift test --filter FullscreenGeometryTests` RC 0 → **1**：

```
testPerWindowBestMatchesPhaseOneBaselines : ("0.6002400960384153") is equal to ("0.6002400960384153") +/- ("0.001") - split 上两者相等说明聚合退化成了逐窗口取最大
testSelftestBaselinesWholeChromeSplit    : ("0.8943577430972389") is not equal to ("1.0") +/- ("0.005")
testSelftestBaselinesWholeChromeSplit    : ("0.6002400960384153") is not equal to ("1.0") +/- ("0.005")
```

**③ 判据 ② 的插桩反向验证。** 往 `FullscreenDetector.swift` 插一行含 `kCGSSpaceNumber` 的**能编译**代码 → `swift build` RC=0（刻意验证过：插桩若编不过，`test.sh` 会先红在 `swift build` 那一项，等于用编译失败冒充判据转红）→ `bash test.sh` → **通过 39 失败 1**，且该项显示 `❌ 产品代码零 Space 身份读取`。恢复后 `cmp -s` 一致 → 重跑 → **通过 40 失败 0**。

### 夹具来源（无一自编）

| 断言值 | 来源 |
|---|---|
| `flip y == 90.000` | `fullscreen-scenarios.log:S0` 的 `flipped_y=90.000` |
| `whole/chrome/split global == 1.000` | 同文件 `SELFTEST_BLOCK` 三行 |
| `chrome.perWindowBest == 0.894` | `SELFTEST=chrome coverage=1.000 per_window_best=0.894` |
| `split.perWindowBest == 0.600` | `SELFTEST=split coverage=1.000 per_window_best=0.600` |
| `(14,9,1442,938) → (0,0,1470,956)` | `inset.log` 的 `SCREEN_FRAME` / `WINDOW_FRAME` / `INSET_*` 三行 |
| Ghostty pid=1227 `coverage=1.000 rects=1` | `S0` 段 `TOP_PID=1227 coverage=1.000 rects=1` |

`S1` 段（自建窗口 `coverage=0.886`）**没有**当正样本用 —— 那一段是 BLOCKED 的，`toggleFullScreen` 在锁屏会话下没生效，量的是一扇**非全屏**窗。计划已明令不许拿它当正样本，实现里也确实没碰。

## Deviations from Plan

### 🔴 W-2026-10-03-17 · deviation —— SYS-02 判据口径变更（B2）

**计划要求照做，本项没有偏离；这里记录的是「判据本身换了口径」这件事。**

旧代理 `src_count 'activeSpaceDidChangeNotification' == 0` 在 D-02 拍板后必然转红（探测器注册了这条通知），会让 `test.sh` 非 0 退出，03-05 的 `TEST_SH_RC == 0` 与 AC 全红，且 03-05 的插桩反向验证基线「本来就是红的」→ `TESTSH_CRITERION_IS_BLIND` 从此不可能再转绿。

**Phase 2 锁的是不变量（不做 Space 级差异化处理），不是具体正则。** 换成两条排除式：
① `fullScreenAuxiliary` 在 `Sources/PicCore/Render` 内 ≥ 1（壁纸窗口仍走系统默认 `collectionBehavior`）
② `kCGSSpace` 与 `CGSSetActiveSpace` 全为 0（产品代码零 Space **身份**读取）

理由已在本机 SDK 头文件核实：订阅 `activeSpaceDidChangeNotification` 只得到「Space 变了」这个边沿，通知本身不附带任何 Space 身份；真要按 Space 做差异化只能去读会话字典的 Space 序号键，或调私有 `CGSSetActiveSpace`。

**判据 ① 的反向验证本任务不做** —— 它盯的是 Phase 2 既有代码（`WallpaperWindowController.swift:43`），本 plan 不改那个文件。该条的插桩义务随 Phase 2 的 `02-02` 判据。

### 🔴 W-2026-10-03-18 · deviation —— D-02 的语义降级（W5）

**D-02 原文要求「几何外信号必须能独立触发暂停」，本 plan 交付的不是那个。**

实现把几何编进了信号字段名（`spaceChangedWhileFullyCovering` / `frontmostAppChangedWhileFullyCovering`），于是 `nonGeometricActive` 恒蕴含「此刻几何满覆盖」，`verdict = nonGeometricActive && covering` 的**第二项在结构上不是承重项**（它恒为真），真正承重的是第一项。「信号成立但几何不足 → 判定仍为 false」这一行在当前字段命名下**不可达**。

**Phase 3 交付的是「几何与几何外信号缺一不可」的合取判定（编排器 2026-10-03 钦点），不是 D-02 字面意义的「信号可独立触发暂停」。Phase 5 / Phase 7 读到 D-02 时不得据此认为已拿到独立触发能力。** 独立触发需要另一条不依赖几何的信号（例如 `AXFullScreen`），本 Phase 不做、也不在成功标准里。

`FullscreenDetectorTests` 第 1/2 条用例证明的是「几何单独为真时判 false」，**不是**「信号单独为真时能触发」—— 这一点已在 W-18 里写明，避免下游误读测试名的意图。

### Rule 1 — Bug：两条新判据的 `no()` 文案没带 `ok()` 的判据名

计划给的 `no()` 文案是「产品代码开始读 Space 身份」，判据名是「产品代码零 Space 身份读取」。插桩反向验证的 `grep -c '❌ 产品代码零 Space 身份读取'` **命中 0** —— 判据确实转红了（汇总 39 通过 1 失败、那一行确实是 ❌），但 grep 查不到「是哪一条红了」。

这正是 **03-01 SUMMARY 里记的那条教训**，我在同一 phase 又踩了一次。**改的是文案不是判据**：两条的 `no()` 都改成带 `ok()` 的同一句判据名，并在判据上方写明这条纪律与原因。改完复跑，`grep -c` 命中 **1**，汇总仍是 39 通过 1 失败 —— 判据一个没放宽。

### Rule 3 — Bug：`re-evaluate` 里的连字符

`-` 在 Swift 标识符里是减号，`self?.re-evaluate(...)` 报 `expected '(' in argument list`。计划正文写的就是这个名字，用反引号 `` `re-evaluate` `` 保住（与 `LockWatcher` 的 `currentLockState()` 同一层考虑：计划里出现过的名字不轻易改名，否则计划与实现的对照要重做一遍）。

### Rule 3 — Bug：`@MainActor` 类的 static 方法继承了隔离

`FullscreenDetector` 是 `@MainActor final class`，它的 `static func currentWindowSamples()` 跟着继承隔离，于是闭包默认值（nonisolated 上下文）调不通，报 `call to main actor-isolated static method`。给四个纯读取的静态方法加 `nonisolated` —— 它们只读 `CGWindowList`，不碰任何 actor 状态。

### 计划事实更正：通知名的实际取值

计划 AC 写「`space=` 字段的值是 `activeSpaceDidChangeNotification`」。**实际 rawValue 是 `NSWorkspaceActiveSpaceDidChangeNotification`**（C 常量名，`NSWorkspace.h:339` 声明 `NSWorkspaceActiveSpaceDidChangeNotification`）。驱动打印的是 `rawValue` 而非成员名 —— 打印 rawValue 更能证明订阅的是**系统真通知**而不是一个字符串常量。判据改为核对 rawValue。

### 对计划的一处加严

`FullscreenGeometryTests` 的第 3 条在计划要求的两个 `perWindowBest` 断言之外，加了一条 `XCTAssertNotEqual(split.global, split.perWindowBest)`，并**实跑反向验证**：把 `cov` 改成逐窗口取最大后这条立刻红。没有这条时，perWindowBest 断言在退化实现下仍会绿（退化后 `global` 恰好等于 `perWindowBest = 0.600`，断言的是 `0.600`），等于空判。

## Known Stubs

无。`FULLSCREEN_SIGNAL_ONLY` **不是桩**，是按计划实现的条件行（触发前提：至少发生一次 Space 切换或应用激活通知）。

## Unverified（如实登记）

| 项 | 状态 | 登记 |
|---|---|---|
| **真实全屏跃迁触发暂停** | `FULLSCREEN_TRANSITION=unobservable reason=session_locked CGSSessionScreenIsLocked=1` | 见下 |
| **`nonGeometricActive == true` 的活体路径** | 本会话恒 0 | 见下 |
| `FULLSCREEN_SIGNAL_ONLY` 条件行 | 本会话跑不出 | 见下 |
| SYS-02 判据 ① 的插桩反向验证 | 随 Phase 2 `02-02`，本 plan 不覆盖 | `W-2026-10-03-17` |

**本会话屏幕锁着且无 Space / 应用切换，`non_geometric` 恒为 0。** 三项「跑不出」是同一根因：

- **真实全屏跃迁**：无法观测。已跑通的只有「注册成功 + 同步重算」—— `FULLSCREEN_SIGNALS_REGISTERED=1` 打出了三个确切 rawValue，`FULLSCREEN_OBSERVERS_REMOVED=1` 证明 `stop()` 把三个 token 都摘了。**PAUSE-01 的接线已证明，真实跃迁触发暂停未证明。**
- **`nonGeometricActive == true` 的活体路径**：信号位的语义是「本次重算由哪个通知触发 + 此刻几何如何」。本会话无跃迁 ⇒ `trigger` 恒为 `.start` ⇒ 两个信号位恒 false。合取的第一项从未在活体上为真过。
- **`FULLSCREEN_SIGNAL_ONLY`**：要求「信号成立但几何不足」，两个条件本会话一个都不满足。**逻辑已实现**（`re-evaluate()` 里 `nonGeometricActive && !covering` 时 emit），**行未落 evidence**。按计划要求，它**不得**进 AC 必达行清单 —— 否则会有人为了让判据变绿去制造事件。

## Threat Flags

| Flag | File | Description |
|------|------|-------------|
| threat_flag: spoofing | `Sources/PicCore/System/FullscreenDetector.swift` | T-03-02 已 mitigate：绝不读窗口标题键。枚举输出字段白名单为 `pid/owner/layer/alpha/bounds`；evidence 日志实测 `kCGWindowName`/`/Users/`/`.mp4` 计数 0；`test.sh` 的全仓判据 `src_count 'kCGWindowName' Sources == 0` 保持绿。**注**：`WINDOW_DICT_KEY=kCGWindowName` 一行会出现在 evidence 里 —— 那是**键名普查**打印的键名本身（证明该键存在而我们不取它的值），不含任何用户数据 |
| threat_flag: tampering | `Sources/PicCore/System/FullscreenDetector.swift` | T-03-07：把 `verdict` 改回 `s.covering` 会复活 Phase 1 的假阳性。缓解：纯静态函数 + 四输入全可注入 + 两条用例直接覆盖 + **注入式反向验证实跑已转红** |
| threat_flag: elevation_of_privilege | `Sources/PicCore/System/FullscreenDetector.swift` | 本 plan **刻意不走 AX API** —— PITFALLS Pitfall 2 记录了同类项目为覆盖率阈值申请辅助功能权限的争议。`test.sh` 的「Info.plist 无任何 UsageDescription」保持绿 |

## Self-Check: PASSED

- 文件全部存在：`Sources/PicCore/System/FullscreenGeometry.swift`、`Sources/PicCore/System/FullscreenDetector.swift`、`Tests/PicCoreTests/FullscreenGeometryTests.swift`、`Tests/PicCoreTests/FullscreenDetectorTests.swift`、`.planning/spike/FullscreenDetectorDriver.swift`、`scripts/probe-fullscreen.sh`、`.planning/phases/03-system-events/evidence/fullscreen-signals.log` ✓
- 提交全部存在：`10811ab`、`fbc7e54` ✓
- 四条 Phase 1 基准逐条对齐：`flip 90.000` / `whole=chrome=split 1.000` / `0.894` / `0.600` ✓
- 内缩 `(14,9,1442,938)` → `(0,0,1470,956)` 精确相等（无容差）✓
- `verdict` 改成 `s.covering` 后 `testGeometryAloneNeverTriggersFullscreen` 转红 ✓，恢复后 `cmp -s` 一致 ✓
- `FullscreenDetector.swift` 剥注释（4 条 `-e`）后 `AVFoundation|AVPlayer|kCGWindowName` 计数 0 ✓
- `FullscreenGeometry.swift` 剥注释后 `import (AppKit|CoreGraphics|AVFoundation)` 计数 0、`AVFoundation|AVPlayer` 计数 0、`0.95` 计数 0 ✓
- `test.sh` 旧代理行已删（`grep -c "src_count 'activeSpaceDidChangeNotification'"` = 0），两条排除式判据在位且插桩后转红 ✓
- `.planning/WINDOWS.md` 含 `W-2026-10-03-17` 与 `W-2026-10-03-18`，两条 `status` 均为 `open` ✓
- evidence 无 `FULLSCREEN_SIGNAL_ONLY` 行、无媒体路径 ✓
- 三处临时变异全部撤销，`cmp -s` 与备份逐字节一致 ✓
- `STATE.md` / `ROADMAP.md` **未改动** ✓

## Next

- **03-03 / 03-04**：往 `HoldReason` 已建好的 `battery` / `displayAsleep` / `systemSleeping` 三个 case 上接检测逻辑，纯增量，不动 `order`。
- **03-05**（装配点）：把 `FullscreenDetector` 接进 `HoldArbiter`（`.fullscreen`）；`startWallpaper()` 的 `play()` → `arbiter.applyCurrentDecision()`（D-06 / `W-2026-10-03-10`）；`HoldStatus` / `PIC_HOLD_SUMMARY`；D-05 的**行为**判据。⚠️ 03-05 若在变异后的红日志里 `grep -c '❌ 产品代码零 Space 身份读取'` 命中 0，先看 `test.sh` 的 `no()` 文案有没有带上 `ok()` 的判据名。