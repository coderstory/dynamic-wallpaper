---
phase: 01-spike
plan: 03
subsystem: spike
tags: [appkit, cgwindowlist, geometry, fullscreen, notch, coordinate-system, spike, throwaway, macos-27]

requires:
  - phase: spike
    provides: "01-01 门禁：level=-2147483623 与按 PID 认领窗口；01-04 锁屏键 CGSSessionScreenIsLocked"
  - phase: research
    provides: "PITFALLS.md Pitfall 2（96.548% / 87.343% 与按 pid 聚合）；ARCHITECTURE.md §3.3 推荐实现"
provides:
  - FullscreenProbe.swift —— 坐标系自证 + 按 pid 聚合的覆盖率算法 + 自建全屏窗口 + synthetic 回放 + 内置几何自检
  - scenarios.sh —— 五场景驱动器，退出码即判据
  - out/fullscreen-scenarios.log —— 5 条 SCENARIO 判定 + 3 条 SELFTEST 基准 + FALSE_POSITIVE_OBSERVED
  - "COORD=confirmed —— planner 中途观察由探针自己复现并给出确认数字"
  - "FALSE_POSITIVE_OBSERVED=1 —— 本机几何判定在 ~95% 阈值下会把「铺满安全区的普通窗口」判成全屏"
affects: [05-verdict, phase-3 播放暂停策略]

actuals:
  tokens: 41000
  tasks: 2
  commits: 2

commits: 2
plan_head_before: 438b617
plan_head_after: a34c0b8

tech-stack:
  added: []
  patterns:
    - "覆盖率一律 visibleFrame 作分母、按 kCGWindowOwnerPID 聚合、阈值 0.95；per_window_best 只作反面口径打印"
    - "自排除按 PID，不按 owner 名 —— 同名可执行文件互查时按名字排除会把被测窗口一起滤掉"
    - "自建全屏窗口后必须同时读 styleMask.contains(.fullScreen) 与 CGWindowList 几何，两者是独立信号"
    - "锁屏时 CGWindowList 几何仍然真实可用，但窗口建不出来 —— 每条覆盖率数字必须带 LOCK= 上下文"

key-files:
  created:
    - .planning/spike/FullscreenProbe.swift
    - .planning/spike/scenarios.sh
    - .planning/spike/out/fullscreen-scenarios.log
  modified: []

key-decisions:
  - "坐标系陷阱由探针自证为 confirmed：Ghostty 的 CGWindowList y=33（原点左上）翻转后为 90.000，正好等于 visibleFrame.origin.y=90.0，±1pt 内命中 2/2 窗口"
  - "FALSE_POSITIVE_OBSERVED=1：Ghostty/CC Switch 把 visibleFrame 铺满（coverage=1.000）但够不到刘海区（h=833 < frame h=956），判定为非全屏，却过了 0.95 阈值 —— 阈值再往下调也救不了，因为值已经是上限"
  - "S1 记 blocked 而非 live：锁屏下 toggleFullScreen 无效（MAX_OBSERVED_FULLSCREEN=0），coverage=0.886 量的是一扇非全屏窗，对全屏检测零信息量"
  - "PITFALLS 的 0.87343 / 0.96548 只作 PRIOR= 口径说明，并用 PRIOR_DECOUPLING 反证它们不进入任何判定"

patterns-established:
  - "证据字段一律 KEY=VALUE 进日志，判据是字面量比对，不接受形容词"
  - "synthetic / blocked / live 三条 COUNT 之和必须等于 SCENARIO_COUNT，脚本末尾做结构自洽断言"
  - "bash 在 UTF-8 locale 下会把变量名后的多字节字符并入变量名 —— $VAR， 必须写 ${VAR}，"

requirements-completed: []

coverage:
  - id: D1
    description: "坐标系陷阱由探针自己复现并给出确认数字，不引用 planner 中途观察"
    verification:
      - kind: integration
        ref: "out/fullscreen-scenarios.log → COORD=confirmed COORD_MATCHED_WINDOWS=2 COORD_WINDOWS=2；WIN pid=1227 bounds=0.0,33.0,1470.0,833.0 flipped_y=90.000 flipped_in_visible_y=1"
        status: pass
    human_judgment: false
  - id: D2
    description: "刘海屏 / Chrome 式 / 超宽屏三场景各有一条带 coverage 的判定"
    verification:
      - kind: integration
        ref: "out/fullscreen-scenarios.log → SCENARIO=chrome-like coverage=1.000（synthetic）/ SCENARIO=ultrawind coverage=1.000（synthetic）/ SCENARIO=notch-fullscreen coverage=0.886（blocked）"
        status: pass
    human_judgment: false
  - id: D3
    description: "误判方向有数字（宁可少暂停，不要误暂停）"
    verification:
      - kind: integration
        ref: "out/fullscreen-scenarios.log → FALSE_POSITIVE_OBSERVED=1（错方向已实测出现）+ NEAR_FULLSCREEN_GUARD=pass coverage=0.840 fullscreen=false（差一点满屏不误暂停）"
        status: pass
    human_judgment: false
  - id: D4
    description: "算法按 pid 聚合而非逐窗口 edgesMatch；split 用例自证聚合生效"
    verification:
      - kind: integration
        ref: "out/fullscreen-scenarios.log → SELFTEST=split coverage=1.000 per_window_best=0.600；SELFTEST=chrome coverage=1.000 per_window_best=0.894"
        status: pass
    human_judgment: false
  - id: D5
    description: "真全屏窗口的 live 覆盖率（S1）"
    verification: []
    human_judgment: true
    rationale: "锁屏会话下 toggleFullScreen(nil) 无效（MAX_OBSERVED_FULLSCREEN=0），窗口从未进入全屏 Space。制造边沿需真人操作屏幕，用户 asleep 且被硬性禁止。记 blocked，不伪造数字。"
  - id: D6
    description: "PITFALLS 先验不得被当成算法目标值"
    verification:
      - kind: integration
        ref: "out/fullscreen-scenarios.log → PRIOR_DECOUPLING=pass（删掉 PRIOR 行后 S2/S3/S4 的 SCENARIO 行逐字节相同）"
        status: pass
    human_judgment: false

duration: 18min
completed: 2026-10-03
status: complete
---

# Phase 01 Plan 03: 全屏几何判定原型 — Summary

**在锁屏会话下跑出的诚实结论：坐标系陷阱由探针自证为 `confirmed`；算法自检三条几何全部 1.000、`split per_window_best=0.600` 证明按 pid 聚合生效；但本机实测到「铺满安全区的普通窗口」拿到 `coverage=1.000` 被判成全屏（`FALSE_POSITIVE_OBSERVED=1`）—— 误判方向被量化了，而且方向是错的那一边。真全屏的 live 样本一个都没拿到（S1 blocked），没有伪造。**

## 执行环境（决定了本 plan 的一半结论）

会话自始至终锁定，全程未锁屏也未解锁（`pmset -g assertions` → `UserIsActive 0`，前后一致）：

```
LOCK=1 source=CGSessionCopyCurrentDictionary.CGSSessionScreenIsLocked
```

`FullscreenProbe` 每条 `inspect` / `replay` 都打一行 `LOCK=`，这样日志里任何一个 coverage 数字都无法脱离锁屏上下文被单独引用。

## 五场景判定矩阵

| 场景 | source | coverage | fullscreen | 依据 |
|---|---|---|---|---|
| S0 `live-regression` | **live** | 1.000 | true | 真枚举：Ghostty pid 1227 / CC Switch pid 1228，各 `bounds=0,33,1470,833` |
| S1 `notch-fullscreen` | **blocked** | 0.886 | false | `MAX_OBSERVED_FULLSCREEN=0`，窗口从未进全屏 Space |
| S2 `chrome-like` | synthetic | 1.000 | true | 回放 Chrome 同 pid 双窗口；本机无 Chrome |
| S3 `ultrawind` | synthetic | 1.000 | true | 回放 3440×1440；本机 `screens_count=1` |
| S4 `notch-partial` | synthetic | 0.840 | false | 回放 0,33,1470,700 |

```
SCENARIO_COUNT=5
LIVE_COUNT=1
SYNTHETIC_COUNT=3
BLOCKED_COUNT=1
FALSE_POSITIVE_COUNT=1
SCENARIO_MATRIX=s0=live s1=blocked s2=synthetic s3=synthetic s4=synthetic
DRIVER_STATUS=ok
```

## 算法自证（纯计算，与锁屏态无关，三条全中）

```
SELFTEST=whole  coverage=1.000 per_window_best=1.000
SELFTEST=chrome coverage=1.000 per_window_best=0.894
SELFTEST=split  coverage=1.000 per_window_best=0.600
SELFTEST_SPLIT_EXPECT_PER_WINDOW_BEST=0.600 actual=0.600
SELFTEST_FAILURES=0
```

`split` 是唯一能区分「按 pid 聚合」与「逐窗口取最大」的用例：两块各覆盖 0.600 / 0.400，合起来才 1.000。若实现退化成逐窗口取最大，这一行会输出 0.600 且 `coverage` 也变 0.600，本条立刻失败 —— 聚合是承重的，不是装饰。

`chrome` 的 `per_window_best=0.894` 与 planner 2026-10-03 的手算完全一致，是算法正确性的第二条独立佐证。

## COORD=confirmed —— planner 的中途观察被复现

探针不引用 planner 观察，自己对每个 eligible 窗口同时打两种 y：

```
WIN pid=1227 owner=Ghostty layer=0 alpha=1.00 bounds=0.0,33.0,1470.0,833.0 flipped_y=90.000 flipped_in_visible_y=1
WIN pid=1228 owner=CC Switch layer=0 alpha=1.00 bounds=0.0,33.0,1470.0,833.0 flipped_y=90.000 flipped_in_visible_y=1
COORD=confirmed COORD_MATCHED_WINDOWS=2 COORD_WINDOWS=2
```

`y_converted = screenHeight - (y + height) = 956 - (33 + 833) = 90.000`，正好落在 `visibleFrame` 的 y 区间 `[90, 923]` 内，2/2 命中。**planner 的「左上角原点」判断成立，且现在有了可复现的数字。**

## 最重要的发现：误判方向实测为「错的那一边」

```
FALSE_POSITIVE_OBSERVED=1 direction=safe_area_filled_but_not_fullscreen_scored_fullscreen pid=1227 coverage=1.000
```

这不是推测，是本机两扇真实窗口（Ghostty pid 1227、CC Switch pid 1228）：

- 它们 `bounds` 高 **833**，屏幕 `frame` 高 **956** —— 矮了 123pt，**够不到刘海区域，因此结构上不可能是真全屏**；
- 但它们把 `visibleFrame`（1470×833）铺满了，`coverage = 1.000`；
- 阈值 0.95 判 `fullscreen=true`。

**关键推论：阈值救不了这个错。** PITFALLS Pitfall 2 给的「遮盖到 95 左右就是全屏」在 `visibleFrame` 分母下已经失效 —— 值已经是上限 1.000，再怎么往下调阈值都是同一个结果。这是对一个第三方先验的**本机实测反证**。

交给 Phase 3 的含义（数字支撑，未做实现选择）：纯几何判定在本机无法区分「最大化到安全区」与「真全屏」。要落到「宁可少暂停，不要误暂停」，需要一个几何之外的判别信号（例如与 `NSWorkspace.activeSpaceDidChangeNotification` 关联），或者明确接受这个方向的误判并写进 PauseReason 枚举。

另一侧的方向是对的：

```
NEAR_FULLSCREEN_GUARD=pass coverage=0.840 fullscreen=false meaning=差一点满屏不会误暂停
```

## S1 为什么是 blocked 而不是 live

自建窗口**确实被 CGWindowList 枚举到了**（`rects=1`，`layer=0 alpha=1 is_onscreen=1`，独立诊断见 `out/diag-locked-window.txt`），但：

```
S1_FINAL_FULLSCREEN=0
S1_MAX_OBSERVED_FULLSCREEN=0
BLOCKED_REASON=toggleFullScreen_had_no_effect_while_session_locked max_observed_fullscreen=0 final_fullscreen=0 window_bounds=73.0,47.0,1324.0,862.0 window_never_reached_screen_frame coverage_below_threshold=0.886 LOCK=1
```

`toggleFullScreen(nil)` 在锁屏会话下没有生效，窗口从未进入全屏 Space。所以 `coverage=0.886` 量的是**一扇非全屏窗**，对「全屏检测是否有效」零信息量 —— 记 `blocked`，不记 `live`。

制造 `unlocked→locked` / `locked→unlocked` 边沿需要真人操作屏幕，用户 asleep 且被硬性禁止，故未尝试（`BLOCKED_WHY_NOT_LOCK_THE_SCREEN=` 已落日志）。

**S1 待人工在场时补做**：解锁后重跑 `bash .planning/spike/scenarios.sh`，S1 会自动从 `blocked` 翻成 `live` 或给出真实 `FULLSCREEN_CONFIRMED`。脚本不需要改。

## 先验未被当成判据（反证）

```
PRIOR=0.87343 method=naive_single_rect_over_display_bounds formula=1470x835_div_1470x956 source=miragewallpaper-73 target_for_this_plan=no
PRIOR=0.96548 method=single_rect_over_display_bounds formula=1470x923_div_1470x956 source=miragewallpaper-73 this_plan_denominator=visibleFrame maps_to=1.000
PRIOR_DECOUPLING=pass evidence=recomputing_S2_S3_S4_without_PRIOR_lines_yields_byte_identical_scenario_lines
```

`PRIOR_DECOUPLING` 是重跑同一批 replay、把两条先验完全剔除后，`SCENARIO=` 行与日志里已落的值**逐字节相同**。脚本内还有一条 `awk` 断言强制 `PRIOR=0.87343` 必须在 `SCENARIO=chrome-like` 的下一行、`0.96548` 再下一行。

## 偏离计划的记录

**PLAN_DEVIATION=01 [Rule 1 缺陷，本 plan 引入并当场修掉] 自排除条件写错了**
计划写「owner 名 != 进程名」。S1 被测窗口来自**同一个可执行文件**（`fullscreenprobe`），按名字排除会把被测窗口一起滤掉 —— 实测 `TOP_PID=… rects=0`、`COORD_WINDOWS=0`。改为按 `ProcessInfo.processIdentifier` 排除（同时也正是编排器硬性指令「一律按 PID 认领」）。修正前后 S0 的数字完全不变，纯粹是 S1 才暴露。

**PLAN_DEVIATION=02 [实施细节] 观察「是否真进了全屏」的 API 不是计划写的那个**
计划未指定 API。`NSWindow` 没有 `isFullScreen` 属性（首次编译 `error: value of type 'NSWindow' has no member 'isFullScreen'`）。实际用 `styleMask.contains(.fullScreen)`，并以 0.25 秒轮询 10 秒记录 `MAX_OBSERVED_FULLSCREEN`。

**PLAN_DEVIATION=03 [实施细节] S1 用「就绪等待」替代盲等 sleep 5**
锁屏下 stdout 缓冲与窗口对象生命周期不同步，固定 `sleep 5` 不可靠。改为最多等 10 秒直到 `SPAWN_FULLSCREEN=` 出现就立刻测量（窗口只活 10 秒，早量早留证），实测 `S1_WAIT_TICKS=1`。不改变任何数字。

**PLAN_DEVIATION=04 [环境事实，与计划携带的事实并存不冲突] 自建窗口的内缩量**
计划携带 01-01 的事实是「桌面层 borderless 窗口系统性内缩 14pt/9pt」。本次测的是 `.fullSizeContentView` 的 **normal 层**窗口，内缩为 **73pt/47pt**（`bounds=73,47,1324,862`）。两类窗口的样式不同，本 plan **不推断**二者是否同源，只如实记录实测值。

**PLAN_DEVIATION=05 [仓库流程] 提交落在 `master`**
本 plan 的 GSD 通用规程要求拒绝在受保护分支上提交；编排器的 `<sequential_execution>` 明确要求「用普通 git 提交（带 hook）、不要 `--no-verify`」，且 01-01 / 01-02 / 01-04 三个 plan 的提交均在 `master`。以编排器指令为准。

**PLAN_DEVIATION=06 [仓库流程] 证据日志用 `git add -f` 强制入库**
`.gitignore` 第 4 行忽略 `.planning/spike/out/`（本 phase 前两个 plan 均沿用该约定）。但本 plan 的**交付物就是这份日志**，不入会随 clone 丢失，故只对 `out/fullscreen-scenarios.log` 单个文件强制入库，其余编译产物与诊断文件保持忽略。

**未发生**：认证门、无包管理器安装、无产品目录结构、无 Xcode 工程、无 `SKELETON.md`、无 `killall Finder`、无锁屏/解锁。

## Tracer 反馈门

Task 1 是 `type="tracer"`。门在 Task 2 的 `<verify>`（`bash .planning/spike/scenarios.sh`，端到端重编译 + 重跑 + 结构自洽断言）处闭合，退出码 0。连跑两次并把 pid / 时间戳归一化后 `diff` 为空 —— **除 pid 与时间戳外逐行相同**，coverage 与判定值全部稳定。人工目视环节在锁屏下不可能执行，已记为 D5 已知障碍，未以任何方式假装完成。

## 自检

- [x] `.planning/spike/FullscreenProbe.swift` 编译通过（`swiftc -parse-as-library -target arm64-apple-macosx15.0`，`COMPILE=ok`）
- [x] `grep -c 'kCGWindowName'`（去注释后）= 0（T-01-06）
- [x] `edgesMatch` 出现 0 次；`kCGWindowOwnerPID` / `kCGWindowAlpha` 各 2 次
- [x] `SCREEN` 行 `visible=` 第四字段 = `833.0`
- [x] 日志恰好 1 行 `COORD=`（`confirmed`）
- [x] 日志恰好 3 行 `SELFTEST=`，`coverage` 全 1.000，`split per_window_best=0.600`
- [x] 日志恰好 5 行 `SCENARIO=`，各含 `coverage=` 与 `fullscreen=`
- [x] `SYNTHETIC_COUNT + LIVE_COUNT + BLOCKED_COUNT = 3 + 1 + 1 = 5 = SCENARIO_COUNT`
- [x] `grep -c 'source=live'` = 1 = `LIVE_COUNT`；`grep -c 'source=synthetic'` = 3 = `SYNTHETIC_COUNT`
- [x] `SCENARIO=notch-partial` 的 `fullscreen=false`
- [x] `PRIOR=0.87343` 含 `target_for_this_plan=no`，且紧邻 `SCENARIO=chrome-like`
- [x] `bash .planning/spike/scenarios.sh` 退出码 0
- [x] 无残留进程（`pgrep -fl fullscreenprobe` → none）；未触碰 `loginwindow`；锁屏状态前后一致
- [x] `STATE.md` / `ROADMAP.md` 未被本 plan 修改

## 交给 Phase 3 / VERDICT 的五条

1. **`visibleFrame` + 按 pid 聚合的算法在本机成立**，三条内置几何自证，`split per_window_best=0.600` 是聚合承重的硬证据。
2. **坐标系陷阱已确认**：`CGWindowList` 左上角原点、`NSScreen` 左下角原点，翻转公式固定为 `y_converted = screenHeight - (y + height)`。
3. **纯几何判定在本机不足以支撑全屏检测**：一扇只铺满安全区的普通窗口拿到 1.000 并被判成全屏，阈值 0.95 无效。误判方向已确认为「误暂停」这一侧。
4. **真全屏样本仍是空白**，S1 需人工在场解锁后重跑同一脚本补做（脚本无需修改）。
5. **PITFALLS 的 0.87343 / 0.96548 不可与本 plan 的数字并列比较** —— 前者是 `bounds` 分母 + 逐窗口，后者是 `visibleFrame` 分母 + 按 pid 聚合。
