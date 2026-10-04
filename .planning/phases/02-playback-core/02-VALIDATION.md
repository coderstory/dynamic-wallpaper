---
phase: 02-playback-core
slug: playback-core
status: draft
nyquist_compliant: false
wave_0_complete: true
tasks_total: 13
tasks_verified: 12
tasks_unverified: 1
tasks_partial: 0
created: "2026-10-04"
updated: "2026-10-04"
---

# Phase 02-playback-core — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

## 为什么 `status: draft` / `nyquist_compliant: false`

`/gsd-validate-phase` **从未在本 Phase 上跑过**。本文件是 2026-10-04 依据既有的
PLAN / SUMMARY / VERDICT / VERIFICATION / evidence 手工补记的覆盖台账。
按 `audit-milestone.md` §5.5（#2117），`status: draft` = **NOT-VALIDATED（覆盖 TODO）**，
不是合规失败。`02-VERIFICATION.md` 自身的 `status: gaps_found` / `score: 8/11 must-haves verified`
是**独立复核**的结论，与本文件的 Nyquist 覆盖是两个维度，不互相替代。

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest via SwiftPM（`swift test`）+ 无头回归 `bash test.sh` |
| **Config file** | `Package.swift` · `test.sh` · `scripts/run-probe.sh` |
| **Quick run command** | `swift test --package-path . --filter <Suite>` |
| **Full suite command** | `bash test.sh` |
| **Estimated runtime** | swift test ~6 秒 · test.sh ~60 秒（含打包段） |

---

## Sampling Rate

- **After every task commit:** 该 task 的 `<automated>`（swift build / swift test --filter / run-probe.sh）
- **After every plan wave:** `swift test --package-path .` 全量
- **Before `/gsd-verify-work`:** `bash test.sh` 必须全绿
- **Max feedback latency:** < 30 秒（不含打包段）

---

## Per-Task Verification Map

`wave_0_complete: true` 的依据：**13 / 13 个 task 在 PLAN 里都带 `<verify><automated>`**。

| Plan | # | Task | 有 `<verify>` 判据 | 证据来源 | 结论 |
|------|---|------|------------------|---------|------|
| 02-01 | 1 | **PDCA-A1 —— 在解锁会话重跑门禁** | ✅ `test -s gate-01-locked-session.log && …` | `gate-rerun.log:REASON=session_locked` · `lock-state.txt:LOCKED=1 ONCONSOLE=1 LOGINWINDOW_PID=489` | ❌ **未验（人工）** —— 任务按 plan「屏幕锁着则如实记 BLOCKED 并继续」执行了，但**目的（解锁态复验）未达成** |
| 02-01 | 2 | SwiftPM 产品目录 + ffmpeg 现场生成语料 | ✅ `swift build --package-path .` | `BUILD_RC=0`；产品目录 14 文件 / 1279 行 / 零第三方依赖（PDCA 审计读数） | ✅ 已验 |
| 02-01 | 3 | State 层三接口（HoldArbiter / SettingsStore / MenuBarModel）+ 纯逻辑单测 | ✅ `swift test … grep 'Executed N tests, with 0 failures'` | `TEST_RC=0`；Phase 2 收口 `Executed 24 tests, with 0 failures` | ✅ 已验 |
| 02-01 | 4 | Playback 层 + `AppDelegate.wiring()` 装配点 | ✅ `swift build … grep -E 'error:'` | `BUILD_RC=0`；`app-bundle.log:APP_ACTIVATION_POLICY=1` `:LSUIElement=true` | ✅ 已验 |
| 02-02 | 1 | tracer —— 图标后有视频循环 + 菜单栏常驻 + 无 Dock 图标 | ✅ `swift build …` | `order.log:SELF_LEVEL=-2147483623` `:ICON_LEVEL=-2147483603` `:ORDER=ok`（我方严格低 20 级） | ✅ 已验 |
| 02-02 | 2 | SC2 的数字 —— 裁剪填满 + 300 秒无缝循环 + 14/9 内缩 | ✅ `run-probe.sh order && inset && loop` | `loop.log:LOOP_VERDICT=pass` `:LOOP_SAMPLES=150` `:LOOP_CYCLES=37` `:LOOP_STALLED=0` `:LOOP_FAILED=0` `:LOOP_DURATION=300`；`inset.log:INSET_LEFT=14 TOP=9 RIGHT=14 BOTTOM=9` | ✅ 已验（**「无黑帧」「铺满无黑边」两半未验**，见下） |
| 02-02 | 3 | SYS-02 落成可判定断言 + 新探针挂进 test.sh | ✅ `bash test.sh … TEST_SH_RC` | 剥注释后 `Sources/` 内 `activeSpaceDidChangeNotification` 计数 = **0**（常驻判据，每次复跑自动重验） | ✅ 已验 |
| 02-03 | 1 | 菜单三项接上 HoldArbiter（暂停继续 / 设置 / 退出） | ✅ `swift build …` | `BUILD_RC=0`；`MenuBarModelTests` 全绿 | ✅ 已验 |
| 02-03 | 2 | 「从原处续播」与「退出真正结束进程」各落原始日志 | ✅ `swift test … Executed N tests` | `quit.log:QUIT_HOOK_SEEN=1` `:QUIT_EXITED=1` `:QUIT_WALL_SECONDS=4`；`HoldArbiterTests` 续播锚点两用例 | ✅ 已验 |
| 02-03 | 3 | MENUBAR-08 哨兵单测 + 两项新探针挂进 test.sh | ✅ `cp / perl -0pi` 变异反向验证 | 该哨兵单测在 02-03 曾**反向验证改红过一次**，证明会真红 | ✅ 已验 |
| 02-04 | 1 | build.sh 改指 `Sources/` —— 产出 `.app` + DMG 并复验层级 | ✅ `bash build.sh … test -s …` | `BUILD_SH_RC=0`；`app-bundle.log:ORDER=ok` `:ORDER_AFTER=ok` `:ALIVE_AFTER_FINDER_RESTART=1` `:APP_ACTIVATION_POLICY=1` `:LSUIElement=true` `:SIGNATURE=adhoc` | ✅ 已验 |
| 02-04 | 2 | **PDCA-A4 —— `.app` 下的显示刷新回调复测** | ✅ `grep -c 'preferredFrameRateRange' FrameDriver.swift` | **`refresh.log:REFRESH_VERDICT=display_link_available` `:REFRESH_SESSION=unlocked`**；两种形态 `REFRESH_RUN_MODE=swift_run DRIVER=display_link TICK_RATE=29.9` / `app_bundle DRIVER=display_link TICK_RATE=30.3`；`tick_count=299/303` 除以 `window=10.0` 秒，**不是估计值** | ✅ 已验 —— **但 SUMMARY 与 `02-VERDICT.md` 记的是 `blocked`/`locked`，与库里的文件不符**（见下） |
| 02-04 | 3 | test.sh 收口 + 02-VERDICT 四栏诚实基线 | ✅ `bash test.sh … test "$T…"` | Phase 2 收口 **通过 32 / 失败 0 / 跳过 0**；干净环境（移走 `build/`）通过 27 / 失败 0 / 跳过 5 | ✅ 已验 |

**合计：13 个 task · ✅ 已验 12 · ❌ 未验 1（02-01 T1 解锁态门禁复跑）**

> 🔴 **02-04 T2 的数字要特别当心。** `02-VERDICT.md` 与 `02-04-SUMMARY.md` 写的是
> 「`.app` 下**仍然**拿不到显示刷新回调 / `FRAME_DRIVER=timer_fallback_hz30`」，
> 并据此给 Phase 3 留了一条硬约束：「🔴 四类系统检测必须走事件通知，禁止逐帧轮询 —— Phase 2 实测 `.app` 下刷新回调仍是 `timer_fallback_hz30`」。
> **这条硬约束的前提已被推翻**：commit `6116186` 在解锁会话复跑后，
> `evidence/refresh.log` 两形态都是 `DRIVER=display_link`、`REFRESH_VERDICT=display_link_available`。
> 该日志自己的 `IMPACT_ON_PHASE3` 行也写着「两种形态都能拿到 display_link」。
> **Phase 3 的「禁止逐帧轮询」结论仍然有效**（那是架构决定），但**它引用的实测依据已不成立**。

---

## Wave 0 Requirements

不需要。13 / 13 个 task 自带 `<verify><automated>`。

---

## ⚠️ 证据被后续 commit 覆盖 —— 判读本文件前必读

**commit `6116186`（2026-10-03 12:04）重跑探针并覆盖了 6 份 evidence 日志**，含本 Phase 的
`evidence/refresh.log`。重跑是在**解锁会话**（`CGSSessionScreenIsLocked=0`）、
屏幕录制权限已授权之后做的。因此库里的文件与 SUMMARY / `02-VERDICT.md` 引用的值**已经不同**：

| 字段 | SUMMARY / VERDICT 记的值 | 库里 `evidence/refresh.log` 当前值 |
|------|------------------------|--------------------------------|
| `REFRESH_VERDICT` | `blocked` | **`display_link_available`** |
| `REFRESH_SESSION` | `locked` | **`unlocked`** |
| 两形态 `DRIVER` | `timer_fallback_hz30` | **`display_link`**（`swift_run` 29.9Hz / `app_bundle` 30.3Hz） |

同一 commit 还覆盖了 Phase 1 的 `.planning/spike/out/gate-01.log`
（`SCREENSHOT` 从 `blocked` 变 `ok bytes=1142104`、`FRAME_DRIVER` 从 `timer_fallback_hz30` 变 `displaylink`）。
**锁屏会话的原值仍逐字保存在 `evidence/gate-01-locked-session.log`**（本 Phase 目录内），
其 `gate-01-locked-session.md5` 是当时的 md5 锚点。

> **结论**：`02-VERDICT.md` 与 `02-04-SUMMARY.md` 相对在库 evidence 已 **stale**。
> 判读本 Phase 时，**以 `evidence/*.log` 的当前值为准**，`VERDICT` 作为当时的快照保留。

---

## 未覆盖项（诚实说明）

**`test.sh` 全绿 ≠ 13 个 task 全已验。** 以下 6 项从未取得读数：

| # | 未覆盖项 | 为什么自动化不了 | 证据 |
|---|---------|----------------|------|
| 1 | **SC2「无黑帧」** | 采集时本机无屏幕录制权限，`screencapture` 取回的帧不含桌面内容 —— **判据在原理上无法进行**，不是脚本没写 | `loop.log:BLACKFRAME=blocked reason=no_screen_recording_permission`；`capture_a_yavg=16` / `capture_b_yavg=16.0027` / `white_control_yavg=235` / `threshold=23.5` —— 两张都停在 YUV 黑电平 16 |
| 2 | **SC2「铺满 / 无黑边」** | **独立于 #1 的第二项缺口，不可与 #1 合并陈述** —— 窗口每边比屏幕小 14pt（横）/ 9pt（竖），`isOpaque=true` 且背景黑，黑边是否存在从未被看过 | `inset.log:INSET_LEFT=14 INSET_RIGHT=14 INSET_TOP=9 INSET_BOTTOM=9` `:WINDOW_FRAME=14,9,1442,938` |
| 3 | **SC5「切换 Space 后壁纸不消失」** | 需真人 Mission Control 操作 + 多 Space 环境 | `inset.log:SCREENS_COUNT=1`；`gate-rerun.log:REASON=session_locked` |
| 4 | **SC1「点击和拖动桌面图标不受影响」** | 需真人手点 | 无自动信号能覆盖「手点」 |
| 5 | **SC3「真人点菜单栏图标退出」** | 本 Phase 无 `.xcodeproj` 故无 XCUITest（D-01），无辅助功能权限 | 已自动证明两段：① 菜单 `.quit` 的动作就是 `terminateApp()`（`MenuBarModelTests.testPerformQuitCallsInjectedClosureOnlyOnce`）；② `NSApp.terminate` 路径跑完 `applicationWillTerminate` 且进程消失（`quit.log:QUIT_HOOK_SEEN=1` / `QUIT_EXITED=1` / `QUIT_MODE=graceful_request`，且 `SIGTERM_HOOK_SEEN=0` 证不是被信号杀掉）。**未证明的是「真人点击 → 同一条路径」这一跳** |
| 6 | **解锁会话下的门禁复跑（PDCA-A1）** | 屏幕锁着。**未重试到出结果为止**（用户已授权「无法解决的跳过」） | `gate-rerun.log:GATE_RERUN=blocked` `:REASON=session_locked CGSSessionScreenIsLocked=1 loginwindow_pid=489` · `lock-state.txt:LOCKED=1 ONCONSOLE=1 LOGINWINDOW_PID=489` |
| 7 | **`powermetrics` 四组 A/B 的 mW 数字**（继承 Phase 1） | `AB_GROUPS_MEASURED=0` 从未被解封 | `01-VERDICT.md:SC5` 行 · `ab-verdict.txt` |

> **#1 / #2 的状态更新（2026-10-03）**：屏幕录制权限**已授权**（YAVG 16 → 242），
> 但 in-repo 的 `loop.log` / `inset.log` 是**授权前**的产物，`BLACKFRAME=blocked` 仍逐字存在。
> 且 STATE.md 明确：**屏幕仍锁着**，所以「铺满无黑边」「图标点选」即使能截图，也仍需解锁会话才能测到真实桌面内容。
> **这两项至今没有跑过。**

---

## 全量复跑读数（2026-10-04 本机实测）

| 命令 | 读数 | Phase 2 当时读数 |
|------|------|----------------|
| `swift test` | `Executed 199 tests, with 0 failures` · exit 0 | `Executed 24 tests, with 0 failures` |
| `bash test.sh` | **通过 104 · 失败 0 · 跳过 1** · exit 0（跳过 = Phase 7 的 7 天长跑） | 通过 32 / 失败 0 / 跳过 0 |

**读数边界**：今天的全绿是**全项目**基线，不能倒推 Phase 2 的 7 项未覆盖已解决。

---

## Validation Sign-Off

- [x] 所有 task 都有 `<automated>` verify（13/13）
- [x] 无连续 3 个 task 缺 automated verify
- [x] Wave 0 无 MISSING 引用 → `wave_0_complete: true`
- [x] 无 watch-mode 标志
- [x] 未覆盖项已逐条列出（7 项，含 6 项人工 / 环境阻塞 + 1 项继承 Phase 1）
- [x] **已登记 `02-VERDICT.md` / `02-04-SUMMARY.md` 相对在库 evidence 已 stale**（PDCA-A4 的 `blocked` → 库里 `display_link_available`）
- [ ] **把 frontmatter 的 `nyquist_compliant` 翻成 `true` —— 未达成。** `02-VERIFICATION.md` 另记 6 处「VERDICT 与产物对不上」+ A6 脆弱点（源码字面量 grep 判据）未落实

**Approval:** pending —— `/gsd-validate-phase 2` 从未跑过
