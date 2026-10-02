---
phase: 01-spike
plan: 01
subsystem: spike
tags: [appkit, nswindow, cgwindowlevel, windowserver, spike, throwaway, macos-27]

requires:
  - phase: research
    provides: ARCHITECTURE.md §2.2 层级数值表与窗口配置骨架；PITFALLS.md Pitfall 1/3；SettingsSpike.swift 的 swiftc -parse-as-library 编译形态
provides:
  - WallpaperSpike.swift —— desktop-level NSWindow + 帧号叠加（throwaway）
  - WindowProbe.swift —— 按 PID 认领窗口的 CGWindowList 枚举器（throwaway）
  - run-gate.sh —— 一条命令跑完门禁证据采集，退出码即判据
  - out/gate-01.log —— 门禁 01 的原始数字日志（ORDER=ok / FINDER_RESTART_ALIVE=1 / D-08 三项）
  - 三条交给下游 plan 的实测发现（见「交给下游的实测发现」段）
affects: [02-菜单栏spike, 03-全屏几何spike, 04-播放性能spike, 05-verdict, phase-2 产品代码骨架]

actuals:
  tokens: 12800
  tasks: 3
  commits: 3

commits: 3
plan_head_before: 11aafdfb2c4c31cb86e63e6b7d11fd42dd21204d
plan_head_after: a41286eee17330ff1b935e89d17205ac60b40ac7

tech-stack:
  added: []
  patterns:
    - "层级唯一写法 NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))，源码零硬编码数字"
    - "同层级有第三方壁纸 app 常驻时，一律用 kCGWindowOwnerPID 认领自己的窗口，禁止按 layer / owner 名筛选"
    - "采集类脚本的证据必须自证：截图要与对照抓图逐字节比对，无屏幕录制权限时不得声称拿到画面"

key-files:
  created:
    - .planning/spike/WallpaperSpike.swift
    - .planning/spike/WindowProbe.swift
    - .planning/spike/run-gate.sh
  modified:
    - .gitignore

key-decisions:
  - "CADisplayLink(target:selector:) 与 preferredFramesPerSecond 在 macOS 27 SDK 上是 iOS-only，改用 NSScreen.displayLink(target:selector:) + preferredFrameRateRange"
  - "本进程拿不到任何显示刷新回调（CADisplayLink / CVDisplayLink 的 timestamp 恒为 0、NSApp.isActive 恒为 false），加 30Hz Timer 兜底驱动保证帧号仍是客观证据"
  - "截图改为「与对照抓图逐字节比对」判 blocked —— 本机无屏幕录制权限，PNG 不含画面信息"
  - "D-02 的四条强证据本门禁只拿到 ①②④，③（截图）记为已知障碍，不阻塞、不伪装"

patterns-established:
  - "证据字段一律 KEY=VALUE 写进 gate-01.log，判据全部是字面量，不接受形容词"
  - "killall Finder 只 kill 不 open，launchd 自动拉起；执行前 stderr 先打 WARN=will_restart_Finder"
  - "所有后台进程（spike + 硬编码对照变体）都进 trap，脚本退出即销毁，不留用户看不见也点不到的幽灵壁纸窗"

requirements-completed: []

coverage:
  - id: D1
    description: "desktop-level NSWindow 挂上桌面层并跑彩色 + 帧号叠加画面，层级写法定案"
    verification:
      - kind: integration
        ref: "swiftc -parse-as-library -target arm64-apple-macosx15.0 -o .planning/spike/out/wallpaperspike .planning/spike/WallpaperSpike.swift"
        status: pass
      - kind: integration
        ref: ".planning/spike/out/spike-stdout.txt → PIC_GATE level=-2147483623 pid=64179 mode=color frame=1"
        status: pass
    human_judgment: false
  - id: D2
    description: "WindowProbe 按 PID 认领窗口，输出 SELF_LEVEL / ICON_LEVEL / ORDER"
    verification:
      - kind: integration
        ref: ".planning/spike/out/probe-before.txt → SELF_LEVEL=-2147483623 ICON_LEVEL=-2147483603 ORDER=ok REASON="
        status: pass
    human_judgment: false
  - id: D3
    description: "killall Finder 后我方窗口仍在 Finder 图标层之下，壁纸没被 Finder 刷新吃掉"
    verification:
      - kind: integration
        ref: ".planning/spike/out/gate-01.log → FINDER_RESTART_ALIVE=1 / ORDER_AFTER=ok / KILLALL_RC=0"
        status: pass
    human_judgment: false
  - id: D4
    description: "D-08 两条对照路线各留可 grep 的数字"
    verification:
      - kind: integration
        ref: ".planning/spike/out/gate-01.log → D08_ROUTE_D_HARDCODED_LEVEL=-2147483623 / D08_ROUTE_C_FRAMEWORK_TOTAL=5 / D08_ROUTE_C_PRIVATE_FRAMEWORK_COUNT=0 / D08_ROUTE_C_CGSSESSION_LINKED=0"
        status: pass
    human_judgment: false
  - id: D5
    description: "截图证据（D-02 强证据③）"
    verification:
      - kind: integration
        ref: ".planning/spike/out/gate-01.log → SCREENSHOT=blocked reason=png_identical_to_control_capture"
        status: fail
    human_judgment: true
    rationale: "本机 screencapture 无屏幕录制权限，返回固定占位图；即使强制全屏洋红窗口在前也与空屏逐字节相同（md5 aa30b1bd89445ed437c1d362c18156b4）。该信号在无人值守条件下不可自动化，按 D-09 记为已知障碍、不阻塞，Phase 5 的 VERDICT 不得据此声称「截图证据已取得」。"
  - id: D6
    description: "桌面图标仍可点选 / 可拖动（D-02 人工 10 秒肉眼确认）"
    verification: []
    human_judgment: true
    rationale: "需真人手点，D-02 已定：事后补做，不阻塞 Phase 2。"

duration: 15min
completed: 2026-10-03
status: complete
---

# Phase 01 Plan 01: 桌面层级门禁 01 — Summary

**desktop-level NSWindow 在本机成立：level −2147483623 严格低于 Finder 桌面图标层 −2147483603，`killall Finder` 后我方窗口仍在，帧号持续递增 1→225；截图信号因本机无屏幕录制权限记为已知障碍。**

## Performance

- **Duration:** 15 min
- **Tasks:** 3/3
- **Commits:** 3
- **Gate exit code:** 0

## 门禁 01 原始数字（`.planning/spike/out/gate-01.log`）

```
ORDER=ok
ORDER_REASON=none
ORDER_AFTER=ok
SELF_LEVEL=-2147483623
ICON_LEVEL=-2147483603
SELF_LEVEL_AFTER=-2147483623
ICON_LEVEL_AFTER=-2147483603
WINDOW_LEVEL_REPORTED=-2147483623
KILLALL_RC=0
SPIKE_ALIVE=1
SCREENSHOT=blocked reason=png_identical_to_control_capture
SCREENSHOT_BYTES=106973
SCREENSHOT_EVIDENT=0
FINDER_RESTART_ALIVE=1
FRAME_ADVANCED=1
FRAME_FIRST=1
FRAME_LAST=225
FRAME_DRIVER=timer_fallback_hz30
D08_ROUTE_D_HARDCODED_LEVEL=-2147483623
D08_ROUTE_C_FRAMEWORK_TOTAL=5
D08_ROUTE_C_PRIVATE_FRAMEWORK_COUNT=0
D08_ROUTE_C_CGSSESSION_LINKED=0
```

## D-02 四条强证据的达成情况

| # | 信号 | 状态 | 数字 |
|---|------|------|------|
| ① | 我方 level 严格低于 Finder 图标层 | **取得** | −2147483623 < −2147483603 |
| ② | CGWindowList 里 Finder 图标窗在我方之上 | **取得** | probe-before/after 均含 `访达 pid=… layer=-2147483603`，且脚本按 layer 升序显式排序 |
| ③ | 截图 | **未取得（已知障碍）** | 无屏幕录制权限，`SCREENSHOT=blocked` |
| ④ | killall Finder 后仍在 | **取得** | `KILLALL_RC=0` + `FINDER_RESTART_ALIVE=1` + `ORDER_AFTER=ok` |

**门禁结论：路线 A 在本机成立**（证据①②④）。③ 缺失但不改变结论，且**不得**在任何下游文档中把 `gate-01.png` 说成桌面画面证据 —— 该 PNG 是固定占位图。

## 交给下游的实测发现

1. **桌面层窗口有系统性 14pt/9pt 内缩** → 交给 Phase 03。
   任何用 `NSWindow(contentRect: NSScreen.main.frame, styleMask: [.borderless])` 建在 `-2147483623` 的窗口，`CGWindowList` 报出的 bounds 都是 `14,9,1442,938`，而 `NSScreen.main.frame` 是 `0,0,1470,956`。用一个 15 行的独立二进制复现，排除了 spike 自身代码的因素。Finder 图标窗也报同一个 `14,9,1442,938`。**全屏覆盖率/几何判定必须先处理这个内缩，否则「窗口 bounds == 屏幕 bounds」的写法必然误判。**

2. **`CADisplayLink` 在 macOS 27 SDK 上是 iOS-only** → 交给 Phase 02/03/04。
   `CADisplayLink.init(target:selector:)` 与 `preferredFramesPerSecond` 均标 `API_UNAVAILABLE(macos)`，头文件指路 `NSView/NSWindow/NSScreen.displayLink(target:selector:)`；帧率用 `preferredFrameRateRange`。Phase 2 的产品代码照抄这个写法。

3. **本进程拿不到任何显示刷新回调** → 交给 Phase 04（AVPlayerLayer 播放）与 Phase 05（VERDICT）。
   `CADisplayLink` 与 `CVDisplayLink` 的 `timestamp` 恒为 `0`，`NSApp.isActive` 恒为 `false`（即使显式调用过 `activate(ignoringOtherApps: true)`），而 `Timer` 正常。spike 因此带一个 30Hz `Timer` 兜底驱动（`FRAME_DRIVER=timer_fallback_hz30`）。**这是无 GUI 前台会话上下文的进程的特征，不代表打包成 .app 后仍然如此** —— Phase 2 起真实 bundle 后必须复测，VERDICT 不得把本条的降级证据当成产品行为。

4. **本机 `screencapture` 无屏幕录制权限** → 交给 Phase 03/05。
   强制一个全屏洋红 normal 层窗口在前，抓图与空屏抓图**逐字节相同**（md5 `aa30b1bd89445ed437c1d362c18156b4`）。run-gate.sh 已内建对照抓图自检，后续任何依赖截图的探针都应照抄这个判法。

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `CADisplayLink(target:selector:)` / `preferredFramesPerSecond` 在 macOS 27 SDK 上不可用**
- **Found during:** Task 1 verify
- **Issue:** 编译器报 `error: 'init(target:selector:)' is unavailable in macOS` 与 `error: 'preferredFramesPerSecond' is unavailable in macOS`（`API_UNAVAILABLE(macos)`）。
- **Fix:** 改用 `NSScreen.displayLink(target: selector:)`（头文件明确指路），帧率改用 `preferredFrameRateRange`。层级写法、窗口配置、画面逻辑均未动。
- **Files modified:** `.planning/spike/WallpaperSpike.swift`
- **Commit:** `ea1a1e7`

**2. [Rule 3 - Blocking] 两处类型窄化编译错误**
- **Found during:** Task 2 verify
- **Issue:** `ProcessInfo.processInfo.processIdentifier` 在 macOS 返回 `Int32`，不能赋给 `Int`；`CGWindowListCopyWindowInfo` 的数值字段是 `NSNumber`，`kCGWindowOwnerPID as? Int` 不成立。
- **Fix:** 前者显式 `Int(...)`；后者统一走 `NSNumber.intValue`。
- **Files modified:** `.planning/spike/WindowProbe.swift`
- **Commit:** `a248812`

**3. [Rule 2 - Missing critical functionality] 帧号「在动」缺客观证据通道**
- **Found during:** Task 1
- **Issue:** plan 要求 stdout **只打一次** `PIC_GATE`，但 Task 1 的 done 项要求「连续 3 秒内 `frame=` 数字持续变化」，两者无法同时从 stdout 验证；success_criteria 第 4 条也要求帧号变化是客观证据。
- **Fix:** 帧号每 tick 写 **stderr**（`TICK frame=<n>`），stdout 保持只有一行 `PIC_GATE`。run-gate.sh 从 stderr 取 `FRAME_FIRST` / `FRAME_LAST` / `FRAME_ADVANCED`，本次为 1 → 225。
- **Files modified:** `.planning/spike/WallpaperSpike.swift`, `.planning/spike/run-gate.sh`
- **Commit:** `ea1a1e7`, `a41286e`

**4. [Rule 2 - Missing critical functionality] 显示刷新回调在本机不触发，需兜底驱动**
- **Found during:** Task 1
- **Issue:** spike 跑起来后 stdout/stderr 全空。逐项排查：`NSScreen` / `NSView` / `NSWindow` 三种 `displayLink` 的 `timestamp` 恒为 `0.0`、`isPaused` 恒为 `false`；`CVDisplayLink` 同样 0 次回调；`Timer` 正常；`NSApp.isActive` 恒为 `false`（含显式 `activate`）；窗口本身 `isVisible=true` 且在活动 Space。
- **Fix:** 保留 `displayLink` 为首选驱动（与 Phase 2 同一写法），加 1 秒看门狗：没收到 tick 就退到 30Hz `Timer` 驱动同一个 `step()`，并打 `DRIVER=timer_fallback_hz30`。**没有伪造帧号 —— 每个 tick 仍然真的自增、真的改颜色、真的改文字。**
- **Files modified:** `.planning/spike/WallpaperSpike.swift`
- **Commit:** `ea1a1e7`

**5. [Rule 2 - Missing critical functionality] 截图判据不足，会把占位图当成证据**
- **Found during:** Task 3
- **Issue:** plan 只判「非零退出 / 文件不存在 / 字节数 0」三条。本机 `screencapture -x` 在没有屏幕录制权限时**返回成功并产出 106973 字节的固定占位图**，三条全过 → 会得出 `SCREENSHOT=ok`，而该 PNG 不含任何画面信息。已实测确认：spike 在屏与不在屏的两张抓图逐字节相同；再强制一个全屏洋红 normal 层窗口在前，抓图仍与空屏逐字节相同。
- **Fix:** run-gate.sh 增加对照抓图 —— spike 停掉后再拍一张 `gate-01-control.png`，两张 md5 相同即判 `SCREENSHOT=blocked reason=png_identical_to_control_capture`，并落 `SCREENSHOT_EVIDENT=0` / `SCREENSHOT_MD5` / `SCREENSHOT_CONTROL_MD5`。按 D-09，截图不参与退出码。
- **Files modified:** `.planning/spike/run-gate.sh`
- **Commit:** `a41286e`

**6. [Rule 1 - Spec bug] plan 中 D-08 路线 D 的验收正则在本机 grep 上恒为 0**
- **Found during:** Task 3 acceptance
- **Issue:** 验收命令写的是 `grep -c '^D08_ROUTE_D_HARDCODED_LEVEL=-?[0-9]\+$'`。macOS 的 FreeBSD grep 在 **BRE** 下把 `?` 当字面量（GNU 扩展是 `\?`），`-?` 实际要求匹配一个减号加一个问号，**该正则永远不可能匹配**。其中 `\+` 部分是可以的（FreeBSD grep 兼容该扩展）。
- **Fix:** 日志里的值本身是对的（`D08_ROUTE_D_HARDCODED_LEVEL=-2147483623`），是**验收正则写错了**。按原意用等价的 ERE 复核：`grep -cE '^D08_ROUTE_D_HARDCODED_LEVEL=-?[0-9]+$'` → `1`。**没有为了让正则过而改动产物值。**
- **Files modified:** 无（仅记录）
- **Commit:** —

### Known Obstacles（已知障碍，按 D-09「无法解决的跳过」记录，不阻塞流水线）

| 障碍 | 实测证据 | 影响 | 处置 |
|------|---------|------|------|
| 无屏幕录制权限 | 强制洋红全屏窗口抓图与空屏抓图 md5 均为 `aa30b1bd89445ed437c1d362c18156b4` | D-02 强证据③（截图）未取得 | 记 blocked；门禁退出码不受影响（①②④ 已足够） |
| 桌面图标可点选/可拖动未验证 | 需真人手点 | D-02 人工 10 秒确认 | D-02 已定：事后补做，不阻塞 Phase 2 |
| 显示刷新回调不可用 | `CADisplayLink`/`CVDisplayLink` timestamp 恒 0，`NSApp.isActive` 恒 false | 帧驱动降级为 30Hz Timer | 已兜底；Phase 2 打包成 .app 后必须复测 |

## Verification

| 检查 | 结果 |
|------|------|
| `bash .planning/spike/run-gate.sh` 退出码 | `0` |
| `gate-01.log` 含 `ORDER=ok` + `FINDER_RESTART_ALIVE=1` | 通过 |
| `gate-01.log` 含 `SELF_LEVEL=-2147483623` + `ICON_LEVEL=-2147483603` | 通过 |
| `gate-01.log` 含 `KILLALL_RC=` + `SPIKE_ALIVE=1` | 通过 |
| `gate-01.log` 含且仅含一行 `^SCREENSHOT=` | 通过（1 行） |
| `D08_ROUTE_C_FRAMEWORK_TOTAL` 为 ≥1 整数 | 通过（`5`） |
| `D08_ROUTE_C_PRIVATE_FRAMEWORK_COUNT=0` | 通过 |
| `D08_ROUTE_C_CGSSESSION_LINKED=0` | 通过 |
| `D08_ROUTE_D_HARDCODED_LEVEL=<整数>` | 值通过（`-2147483623`）；plan 的 BRE 正则本身不可满足，见 Deviation 6 |
| `.planning/spike/HardcodedLevelVariant.swift` 不在仓库 | 通过（生成于 `mktemp -d`，trap 销毁） |
| `.gitignore` 含 `^\.planning/spike/out/$` | 通过（1 行） |
| `pgrep -f 'out/wallpaperspike'` / `pgrep -f 'HardcodedLevelVariant'` | 均为空 |
| `WallpaperSpike.swift` 中 `-21474836` 字面量计数 | `0` |
| `WallpaperSpike.swift` 中 `desktopIconWindow` 计数 | `0` |
| `WallpaperSpike.swift` 中 `CGWindowLevelForKey(.desktopWindow)` 计数 | `1` |
| `WallpaperSpike.swift` 中 `UserDefaults.standard.set` / `defaults write` 计数 | `0` |
| `WindowProbe.swift` 中 `kCGWindowName` 计数 | `0` |
| 无残留窗口（本次排查用的 /tmp 诊断二进制均已 kill） | 通过 |

## Threat Model 落实

| Threat | 处置 | 证据 |
|--------|------|------|
| T-01-01 Tampering（改用户系统设置） | mitigated | 源码 grep `UserDefaults.standard.set` / `defaults write` / `NSWorkspace.shared.open` / `/Library` 均为 0；spike 只读窗口元数据 |
| T-01-02 DoS（killall Finder / 幽灵桌面层窗口） | mitigated | 执行前 stderr 打 `WARN=will_restart_Finder`；spike 与硬编码对照变体都进 trap 并显式 kill；`pgrep` 复核无残留 |
| T-01-03 信息泄露（窗口标题含用户文件名） | mitigated | `WindowProbe.swift` 中 `kCGWindowName` 计数为 0；输出仅 layer/owner/pid/bounds |
| T-01-11 Repudiation（结论可复核） | mitigated | 判据全是 `gate-01.log` 里的字面量；`bash .planning/spike/run-gate.sh` 可原样重跑复现 |

## Self-Check: PASSED

- [x] `.planning/spike/WallpaperSpike.swift` 存在且已编译运行
- [x] `.planning/spike/WindowProbe.swift` 存在且已编译运行
- [x] `.planning/spike/run-gate.sh` 存在且退出码 0
- [x] `.gitignore` 含 `.planning/spike/out/`
- [x] 三个提交 `ea1a1e7` / `a248812` / `a41286e` 均存在于 `11aafdf..HEAD`
- [x] `.planning/STATE.md` 与 `.planning/ROADMAP.md` 未被本 plan 修改（STATE.md/config.json 的脏状态来自 02:36–02:37 的 planning 阶段，早于本 plan 首次写入 02:40:34）

## 未做 / 明确留给下游

- **未创建任何产品目录结构**（无 `Sources/`、`Pic/`、`Package.swift`、`.xcodeproj`）—— 符合编排器硬性指令 1。
- **未生成 `SKELETON.md`** —— 符合编排器硬性指令 3。
- **未跑 research-phase**（D-09）。
- **未做 `powermetrics` A/B**（D-07，属 Plan 01-04；本机无免密 sudo，编排器已定为 `verification_deferred_human`）。
- **`--mode v1 / transparent / avplayerview` 仍是 `PIC_ABORT=mode_not_implemented:<mode>` + `exit(3)`** —— 按 plan 设计，由 Phase 04 填充，**不是 stub**，是显式失败。
