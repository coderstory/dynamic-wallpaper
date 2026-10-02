GATE=A

# Phase 1 判定：桌面层级门禁

**本文件是 Phase 1 的唯一判定文件。** Phase 2–7 只引用本文件，不回翻四个 SUMMARY 与 git log。
判据输入全部来自 `.planning/spike/out/` 下的原始日志，不从 SUMMARY 转述。

## 门禁判定

判据写死，**只看 `gate-01.log` 的两个字段**：

```text
GATE=A  ⟸  ORDER=ok  且  FINDER_RESTART_ALIVE=1
GATE=B  ⟸  上述任一不成立
```

| 字段（`.planning/spike/out/gate-01.log`） | 原值 | 真值 |
|---|---|---|
| `ORDER` | `ok` | 真 |
| `FINDER_RESTART_ALIVE` | `1` | 真 |

两字段皆真 → **GATE=A。路线 A（desktop-level `NSWindow` 贴在桌面图标层下方）在本机成立。Phase 2 可以直接用同一套写法起产品代码；「门禁证伪则整条架构作废」这一分支没有触发，Phase 2–7 照原计划启动。**

> SC5 的 `BLOCKED` 不参与本判定。判据里没有 SC5 这一项 —— 把下面表格里 SC5 那一整行删掉后重新判定，`GATE=` 仍是 `A`。

## 5 条 Success Criteria 逐条结论

判据原文见 `.planning/ROADMAP.md` Phase 1 Success Criteria 第 1–5 条。

| SC | 结论 | 证据（文件:字段） | 数字 |
|---|---|---|---|
| SC1 层级方案成立 | PASS | `.planning/spike/out/gate-01.log:SELF_LEVEL` `:ICON_LEVEL` `:FINDER_RESTART_ALIVE` `:FRAME_LAST` | 我方 -2147483623 严格低于 Finder 图标层 -2147483603；KILLALL_RC=0、SPIKE_ALIVE=1、FINDER_RESTART_ALIVE=1、ORDER_AFTER=ok；FRAME_FIRST=1 → FRAME_LAST=225。「可点选可拖动」的人工 10 秒项未做，见「已知障碍」第 2 行 |
| SC2 层级写法定案 | PASS | `.planning/spike/out/task1-selftest.log:SOURCE_CGWindowLevelForKey_desktopWindow` `:SOURCE_hardcoded_-21474836` `:SOURCE_desktopIconWindow` | 运行值 WINDOW_LEVEL_REPORTED=-2147483623；源码计数 CGWindowLevelForKey_desktopWindow=1、hardcoded_-21474836=0、desktopIconWindow=0；COMPILE_RC=0 errors=0 |
| SC3 菜单栏路线 | PASS | `.planning/spike/out/menubar.log:MENUBAR_VERDICT` | MENUBAR_VERDICT=ok；两个变体 `VARIANT` alive=1 layer0=0；`VARIANT_PIC_MENU` policy=1；阳性对照 CONTROL_REGULARWINDOW layer0=1 |
| SC4 全屏几何原型 | **PARTIAL** —— 几何原型跑通，但 ROADMAP 点名的三个场景 **0/3 有真机样本**；且 SC4 后半句「误判方向为宁可少暂停」**已被实测证伪**，实测方向是**误暂停** | `.planning/spike/out/fullscreen-scenarios.log:SCENARIO=` — s0 live 1.000、s1 blocked 0.886、s2 synthetic 1.000、s3 synthetic 1.000、s4 synthetic 0.840 | SELFTEST_VERDICT=pass（whole=1.000 chrome=1.000 split=1.000 split_per_window_best=0.600）；FALSE_POSITIVE_OBSERVED=1；COORD=confirmed |
| SC5 锁屏触发与耗电四组 | BLOCKED | 未采集，本机无免密 sudo，powermetrics 需 root | SCREENLOCK=unknown；OPAQUE_DELTA=SKIPPED=human_checkpoint；AB_GROUPS_PLANNED=4 AB_GROUPS_MEASURED=0 |

SC5-注：SC5 的兜底产物在 `.planning/spike/out/ab-verdict.txt`，首行 `AB_STATUS=skipped reason=human_checkpoint_not_run`。SC5 的两半都不算采集完成 —— `screenIsLocked` 探针跑满 120 秒但屏幕全程已锁、无跃迁可观察，结论只能是 `SCREENLOCK=unknown`（不是 `fires`，也不是 `silent`）；四组 300 秒 A/B 一个都没量到。SC5 不参与 `GATE=` 判定，已在「已知障碍」第 7、8 行各占一行。

## 层级写法定案（Phase 2 照抄，不要重新推导）

**唯一写法：**

```swift
w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
```

实测值 **-2147483623**，来源 `.planning/spike/out/gate-01.log:SELF_LEVEL`，同一值亦见 `WINDOW_LEVEL_REPORTED`。
AppKit 无 `NSDesktopWindowLevel` 常量，`CGWindowLevelForKey` 是唯一来源（D-05）。

**禁用项：**

| 项 | 实测值 | 禁用理由 | 该值在本文件里的唯一出处 |
|---|---|---|---|
| `CGWindowLevelForKey(.desktopIconWindow)` | -2147483603 | 与桌面层差 20 级，会盖住桌面图标 | `.planning/spike/out/gate-01.log:ICON_LEVEL` —— 此处只为对比而列出 |

**禁用硬编码字面量：** 骨架代码里 `-21474836` 出现次数必须为 0 —— `.planning/spike/out/task1-selftest.log:SOURCE_hardcoded_-21474836=0`。

**`.accessory` 的 rawValue 是 1，不是 0。** `.planning/spike/out/menubar.log:ACTIVATION_POLICY_RAW` 原值 `regular=0 accessory=1 prohibited=2`。0 是 `.regular` —— 恰是「有 Dock 图标」的那一个。照抄「policy=0」会把 `.regular` 判成 `.accessory`，凭空造出一个通过。

**刷新驱动写法定案：** macOS 27 SDK 上 `CADisplayLink(target:selector:)` 与 `preferredFramesPerSecond` 标 `API_UNAVAILABLE(macos)`，用 `NSScreen.displayLink` + `preferredFrameRateRange`。

### D-08 两条对照路线的处置结论

两条都是**部分确认**，成立范围如实界定，未夸大。

**路线 C（`CGSSession` 私有框架）—— 禁用。**
原值（`.planning/spike/out/gate-01.log`）：`D08_ROUTE_C_FRAMEWORK_TOTAL=5`、`D08_ROUTE_C_PRIVATE_FRAMEWORK_COUNT=0`、`D08_ROUTE_C_CGSSESSION_LINKED=0`。
这**只**证明「零私有框架即可过门禁」；它**不**证明「私有框架会坏」。

**路线 D（硬编码 WindowServer level 数字）—— 禁用。**
原值（`.planning/spike/out/gate-01.log`）：`D08_ROUTE_D_HARDCODED_LEVEL=-2147483623`。
这**只**证明「今天硬编码的数值与 `CGWindowLevelForKey` 的返回值一致」；它**不**证明「该数值在未来 macOS 上不变」。禁用的理由是**该数值未文档化、不受支持**，不是「今天跑不通」。

## 已知障碍

按 D-09「无法解决的跳过」登记。没有一条阻塞下游。

| 障碍 | 证据 | 处置 | 是否阻塞 |
|---|---|---|---|
| 截图证据取不到：本机 `screencapture` 无屏幕录制权限，返回固定占位图 | `gate-01.log:SCREENSHOT=blocked reason=png_identical_to_control_capture`；`SCREENSHOT_MD5` 与 `SCREENSHOT_CONTROL_MD5` 同为 `aa30b1bd…`，`SCREENSHOT_EVIDENT=0` | D-02 强证据③ 记 blocked，不参与门禁退出码；下游任何文档不得把 `gate-01.png` 当画面证据 | 否 |
| 桌面图标「可点选可拖动」未验证（需真人手点） | 无自动信号能覆盖这个动作 | **事后补做，不阻塞**（D-02 已定）；Phase 2 打包成 `.app` 后用真人 10 秒确认一次 | 否 |
| Chrome 全屏场景是 synthetic 回放（本机未装 Chrome） | `fullscreen-scenarios.log:BLOCKED_REASON=no_google_chrome_installed` | 记 synthetic，不记 live | 否 |
| 超宽屏场景是 synthetic 回放（本机 `screens_count=1`） | `fullscreen-scenarios.log:BLOCKED_REASON=no_ultrawide_display_attached_screens_count=1` | 记 synthetic，不记 live | 否 |
| 真全屏窗口的 live 覆盖率取不到（S1） | `fullscreen-scenarios.log:S1_MAX_OBSERVED_FULLSCREEN=0`、`BLOCKED_REASON=toggleFullScreen_had_no_effect_while_session_locked` | 记 blocked。人工在场解锁后重跑 `bash .planning/spike/scenarios.sh`，脚本无需修改 | 否 |
| **纯几何全屏判定在本机会误判**（本 Phase 最有后果的一条） | `fullscreen-scenarios.log:FALSE_POSITIVE_OBSERVED=1 direction=safe_area_filled_but_not_fullscreen_scored_fullscreen pid=1227 coverage=1.000` | Phase 3 必须引入几何之外的判别信号，或明确接受这一误判方向并写进 PauseReason。见下节第 2 条 | 否（不阻塞 Phase 2） |
| `screenIsLocked` 的跃迁触发未观察到 | `ab-verdict.txt:SCREENLOCK=unknown`；`lock.log` 的 `LOCKPROBE_DONE events=0 locked=0 seconds=120`，屏幕自探针开始前约 110 分钟即已锁（`SCREEN_WAS_LOCKED_AT_PROBE_START=1`） | 需要一次真人手动锁屏 10 秒再解锁；不得在无人值守时重试到出结果为止 | 否 |
| `powermetrics` 四组 300 秒 A/B 未采集 | `ab-verdict.txt:AB_STATUS=skipped reason=human_checkpoint_not_run`；`ab-blocker-evidence.txt` 两条 rc=1 | 真人在场跑一次 `bash .planning/spike/powermetrics_ab.sh`（约 21 分钟）即可解封；四组命令已在 `--dry-run` 里逐字核对过 | 否 |
| plan 04 用 bash 数组变量 `GROUPS` 存四组，与 bash 保留变量冲突（当前用户的 gid 列表） | `--dry-run` 曾打出 16 组 gid；改名 `AB_GROUPS` 后为 4 组（commit `f19a99c`） | 本 Phase 已修掉；登记在此以免下游复踩 | 否 |

## 四栏口径

### 跑过

| 项 | 命令 | 产物 |
|---|---|---|
| 桌面层级门禁（D-02 四条强证据取到 ①②④） | `bash .planning/spike/run-gate.sh` | `.planning/spike/out/gate-01.log`（退出码 0） |
| 菜单栏两条路线 + 阳性对照 | `bash .planning/spike/menubar-check.sh` | `.planning/spike/out/menubar.log` |
| 四组播放模式 + 源码计数判据 | `swiftc` 编译 + 四种 `--mode` 各跑一次 | `.planning/spike/out/task1-selftest.log` |
| 全屏五场景 + 三条几何自检 | `bash .planning/spike/scenarios.sh` | `.planning/spike/out/fullscreen-scenarios.log` |
| 锁屏探针 120 秒 | `swiftc` 编译 `.planning/spike/LockProbe.swift` 后运行 | `.planning/spike/out/lock.log`（122 行） |
| A/B 脚本 `--dry-run` 与解析自检 | `bash .planning/spike/powermetrics_ab.sh --dry-run` | `.planning/spike/out/task3-selftest.log` |
| `CGSSession` 键表与锁屏值采样 | 独立探针 | `.planning/spike/out/cgsession-keys.txt`、`session-lockvalue.log` |
| 无头回归脚本 | `bash test.sh` | 终端输出，通过 15 失败 0 |

### 没跑过

| 项 | 为什么没跑 |
|---|---|
| `powermetrics` 四组 300 秒 A/B 的 mW 数字 | 本机无免密 sudo；0 组采集 |
| `com.apple.screenIsLocked` 的跃迁触发（`fires` 与 `silent` 二选一） | 探针真跑了 120 秒，但屏幕全程已锁，无跃迁可观察 |
| Chrome 真全屏、超宽屏真机、真全屏 live 样本 S1 | 本机无 Chrome、只有一块屏、会话全程锁定 |
| D-02 人工 10 秒点击与拖拽 | 需真人手点，用户不在场 |
| 菜单栏图标的肉眼确认、点开后 5 条菜单的渲染 | 本 Phase 用 `policy=1` + `layer0=0` 作可自动核对的代理，本机无屏幕录制权限 |
| 打包成 `.app` 后的显示刷新回调复测 | 本进程拿不到任何刷新回调（`FRAME_DRIVER=timer_fallback_hz30`），打包产物不存在 |
| 屏保启动时桌面层窗口的表现 | 未实测 |

### 逻辑可行但本 Phase 未测

| 项 | 逻辑依据 | 本 Phase 未测什么 |
|---|---|---|
| 用 `NSWorkspace.activeSpaceDidChangeNotification` 或 Space 序号做几何之外的全屏判别信号 | 公开 API，与 `CGWindowList` 几何正交 | 没实现，也没测 |
| `CGSSessionCopyCurrentDictionary().CGSSessionScreenIsLocked` 作锁屏状态源 | 公开 API 路径；本机 40 秒 9 次采样全为 1 | 只验证了能读出状态，**未**验证跃迁时会翻转 |
| 多 Space 下的 `.canJoinAllSpaces`、台前调度（Mission Control）、Stage Manager、虚拟桌面 | ARCHITECTURE 的待验证清单，与本 Phase 的窗口配置同源 | 四项全未测 |
| `.saver` bundle 能否显示视频 | ARCHITECTURE §2.3 标为待验证；机制在本机存活 | 未建 bundle，未测 |
| 随本机另有四个同类动态壁纸 app 常驻在同层级时的 z-order 竞争 | 编排器实测至少一个常驻在 -2147483623 | 本 Phase 一律按 PID 认领自己的窗口，未做竞争测试 |

### 假定依赖

| 项 | 假定内容 | 未验证之处 |
|---|---|---|
| `screencapture` 的屏幕录制权限状态 | 假定它不可用 —— 已知返回固定占位图（与对照抓图 md5 逐字节相同） | 没有申请过该权限。下游任何依赖截图的判定都要先解这一项 |
| `powermetrics` 的 root 凭据 | 假定它拿不到 —— `sudo -n true` 与 `powermetrics` 两条都 rc=1 | 未输入过密码，不知道补上密码后四组 300 秒能否跑完 |
| `CGWindowListCopyWindowInfo` 在无 GUI 前台会话下的行为 | 本 Phase 全部测量都在锁屏会话内完成。**带 `LOCK=` 标注的只有 `fullscreen-scenarios.log`（6 处）与 `ab-verdict.txt`（1 处）；`gate-01.log` / `menubar.log` / `task1-selftest.log` / `lock.log` 不含该字段** —— 锁定上下文由 `SCREEN_WAS_LOCKED_AT_PROBE_START=1`、`loginwindow` PID 489、`UserIsActive 0` 三处独立佐证，非逐行自带 | 有前台进程时的窗口列表行为未验证 |
| 第三方壁纸 app 的窗口层级 | 假定其中至少一个常驻在 -2147483623（编排器实测） | 未逐个复测四个 app 的层级 |

## 交给下游的三条硬约束

1. **Phase 2 可以启动。** `GATE=A`，「门禁证伪 → 架构作废」没有触发。层级写法照抄「层级写法定案」段，`.accessory` 断言用 1，`CADisplayLink` 改 `NSScreen.displayLink`。

2. **Phase 3 的全屏检测不能只靠几何 —— 这是本 Phase 最具后果的一条。** `FALSE_POSITIVE_OBSERVED=1` 不是推断：Ghostty（pid 1227）与 CC Switch（pid 1228）两扇真实窗口各自把 `visibleFrame`（1470×833）铺满 → `coverage=1.000` ≥ 0.95 阈值被判成 `fullscreen=true`，但两者的 bounds 高 833 小于屏幕 frame 高 956，结构上够不到刘海区，**可证不是全屏**。coverage 已经顶在 1.000 这个上限，**任何阈值调整都改不了这个结果**。Phase 3 必须二选一：设计一个几何之外的判别信号，或明确写下接受「误暂停」这一方向的错误并编码进 PauseReason —— 不能默认沿用 0.95 阈值。

3. **本 Phase 的降级证据不等于产品行为。** 显示刷新回调在本进程拿不到（`FRAME_DRIVER=timer_fallback_hz30`），Phase 2 打包成 `.app` 后必须复测；`CGSSessionScreenIsLocked` 只验证了能读出状态，跃迁时是否翻转未验证，Phase 3 必须实测后者才能写进产品代码。

## 复现命令

```bash
bash .planning/spike/run-gate.sh        # → out/gate-01.log，决定 GATE=A/B
bash .planning/spike/menubar-check.sh   # → out/menubar.log，决定 SC3
bash .planning/spike/scenarios.sh       # → out/fullscreen-scenarios.log，决定 SC4
bash test.sh                            # 无头回归，通过 15 失败 0
```
