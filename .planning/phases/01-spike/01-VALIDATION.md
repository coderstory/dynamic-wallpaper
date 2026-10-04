---
phase: 01-spike
slug: spike
status: draft
nyquist_compliant: false
wave_0_complete: true
tasks_total: 14
tasks_verified: 13
tasks_unverified: 1
tasks_partial: 0
created: "2026-10-04"
updated: "2026-10-04"
---

# Phase 01-spike — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

## 为什么 `status: draft` / `nyquist_compliant: false`

`/gsd-validate-phase` **从未在本 Phase 上跑过**。本文件是 2026-10-04 依据既有的
PLAN / SUMMARY / VERDICT / VERIFICATION / evidence 手工补记的覆盖台账，不是 validate-phase 的产物。
按 `audit-milestone.md` §5.5（#2117），`status: draft` 表示 **NOT-VALIDATED（覆盖 TODO）**，
不是 PARTIAL，更不是合规失败。跑一次 validate-phase 才会把它提升到「已 validated」那一档（本文件不预先声称）。

**本文件的数字全部可对账**：task 数来自各 `*-PLAN.md` 的 `<task type=>` 计数；
每条判定引用的 evidence 字段都在 `.planning/spike/out/` 或 `*-SUMMARY.md` 里逐字存在。

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | 无 XCTest（spike 是 throwaway，`swiftc` 单文件编译 + bash 采集脚本） |
| **Config file** | `.planning/spike/run-gate.sh` · `menubar-check.sh` · `scenarios.sh` · `powermetrics_ab.sh` |
| **Quick run command** | `bash test.sh` |
| **Full suite command** | `bash test.sh` |
| **Estimated runtime** | ~3 秒（无 GUI 依赖） |

---

## Sampling Rate

- **After every task commit:** 跑该 task 的 `<automated>`（swiftc 编译 或 对应采集脚本）
- **After every plan wave:** `bash test.sh`
- **Before `/gsd-verify-work`:** `bash test.sh` 必须全绿
- **Max feedback latency:** < 10 秒

---

## Per-Task Verification Map

`wave_0_complete: true` 的依据：**14 / 14 个 task 在 PLAN 里都带 `<verify><automated>`**
（逐 plan 实测 `tasks == verify == automated`），因此没有任何 task 依赖 Wave 0 补测试桩。

| Plan | # | Task | 有 `<verify>` 判据 | 证据来源 | 结论 |
|------|---|------|------------------|---------|------|
| 01-01 | 1 | WallpaperSpike —— desktop-level 窗口 + 彩色 + 帧号 | ✅ `swiftc -parse-as-library …` | `task1-selftest.log:COMPILE_RC=0 errors=0`；`gate-01.log:FRAME_FIRST=1 → FRAME_LAST=260` `:FRAME_ADVANCED=1` | ✅ 已验 |
| 01-01 | 2 | WindowProbe —— 按 PID 枚举产出 SELF/ICON/ORDER | ✅ `swiftc …` | `gate-01.log:SELF_LEVEL=-2147483623` `:ICON_LEVEL=-2147483603` `:ORDER=ok` `:ORDER_AFTER=ok` | ✅ 已验 |
| 01-01 | 3 | run-gate.sh —— 一次跑完门禁证据采集 | ✅ `bash .planning/spike/run-gate.sh` | `gate-01.log:FINDER_RESTART_ALIVE=1` `:KILLALL_RC=0` `:SPIKE_ALIVE=1` `:SCREENSHOT=ok bytes=1142104`；退出码 0 | ✅ 已验（**四条强证据 ①②③④ 全部取得**，见下「证据被后续 commit 覆盖」） |
| 01-02 | 1 | MenuBarExtra 主路线 `.accessory` | ✅ `swiftc … menubarspike` | `menubar.log:VARIANT=menubarspike alive=1 layer0=0` | ✅ 已验 |
| 01-02 | 2 | NSStatusItem 退路 | ✅ `swiftc … menubarfallback` | `menubar.log:VARIANT=menubarfallback alive=1 layer0=0` | ✅ 已验 |
| 01-02 | 3 | menubar-check.sh 客观核对「无 Dock 图标」 | ✅ `bash menubar-check.sh` | `menubar.log:MENUBAR_VERDICT=ok`；阳性对照 `CONTROL_REGULARWINDOW layer0=1`（证探测器非瞎） | ✅ 已验 |
| 01-03 | 1 | FullscreenProbe 坐标系 + 覆盖率算法 | ✅ `swiftc … fullscreenprobe` | `fullscreen-scenarios.log:SELFTEST_VERDICT=pass`（whole/chrome/split = 1.000） | ✅ 已验 |
| 01-03 | 2 | scenarios.sh 五场景各一条判定 | ✅ `bash scenarios.sh` | `fullscreen-scenarios.log:SCENARIO_COUNT=5 LIVE_COUNT=1 SYNTHETIC_COUNT=3 BLOCKED_COUNT=1` | ✅ 已验（5/5 都出了判定行；**但 3 场景是 synthetic、1 场景 blocked**） |
| 01-04 | 1 | WallpaperSpike 补齐三个播放模式 | ✅ `swiftc …` | `task1-selftest.log:SOURCE_CGWindowLevelForKey_desktopWindow=1` `:SOURCE_hardcoded_-21474836=0` `:SOURCE_desktopIconWindow=0` | ✅ 已验 |
| 01-04 | 2 | LockProbe —— `com.apple.screenIsLocked` 实测探针 | ✅ `swiftc … lockprobe` | `lock.log` 122 行 `:LOCKPROBE_DONE events=0 locked=0 seconds=120` | ✅ 已验（**跑了 120 秒，结论只能是 `SCREENLOCK=unknown`**） |
| 01-04 | 3 | powermetrics_ab.sh 四组驱动 + `--dry-run` 自检 | ✅ `bash powermetrics_ab.sh --dry-run` | `task3-selftest.log`；四组命令逐字核对（`AB_GROUPS` 改名后 = 4 组） | ✅ 已验 |
| 01-04 | 4 | **人工跑 20 分钟 A/B + 锁屏往返** | ✅ `grep -qxE 'AB_STATUS=(completed\|skipped reason=.*)'` | `ab-verdict.txt:AB_STATUS=skipped reason=human_checkpoint_not_run` · `AB_GROUPS_MEASURED=0` · `SCREENLOCK=unknown` · `OPAQUE_DELTA=SKIPPED=human_checkpoint` | ❌ **未验（人工）** |
| 01-05 | 1 | 写 01-VERDICT.md —— 门禁判定 + 5 条 SC | ✅ `test -f .planning/phases/01-spike/01-VERDICT.md` | 文件存在；`GATE=A` 由 `ORDER=ok` + `FINDER_RESTART_ALIVE=1` 两字段直接推出 | ✅ 已验 |
| 01-05 | 2 | test.sh 加 spike 门禁探针（无 GUI 依赖） | ✅ `bash test.sh` | Phase 1 收口时 `通过 15 失败 0`；**2026-10-04 全量复跑 `通过 104 失败 0 跳过 1`** | ✅ 已验 |

**合计：14 个 task · ✅ 已验 13 · ❌ 未验 1（01-04 Task 4，人工 checkpoint）**

---

## Wave 0 Requirements

不需要。14 / 14 个 task 在 PLAN 里都自带 `<verify><automated>`，无 MISSING 引用。

---

## ⚠️ 证据被后续 commit 覆盖 —— 判读本文件前必读

**commit `6116186`（2026-10-03 12:04，标题是 transcoding/VMAF 的事）重跑了探针并覆盖了 6 份 evidence 日志**，
其中包括本 Phase 的 `.planning/spike/out/gate-01.log` 与 Phase 2 的 `evidence/refresh.log`、
以及 Phase 3 的 4 份日志。**重跑是在解锁会话（`CGSSessionScreenIsLocked=0`）、屏幕录制权限已授权之后做的。**

因此在库证据与 `01-VERDICT.md` / `01-01-SUMMARY.md` 引用的值**已经不同**：

| 字段 | VERDICT / SUMMARY 引用的值（锁屏会话） | 在库 `gate-01.log` 当前值（解锁会话复跑） |
|------|--------------------------------------|------------------------------------------|
| `SCREENSHOT` | `blocked reason=png_identical_to_control_capture` | **`ok bytes=1142104`**（`SCREENSHOT_EVIDENT=1`；`MD5=7efbe61f…` ≠ `CONTROL_MD5=a593fe8e…`） |
| `FRAME_DRIVER` | `timer_fallback_hz30` | **`displaylink`** |
| `D08_ROUTE_C_FRAMEWORK_TOTAL` | `5` | **`7`** |
| `FRAME_LAST` | `225` | **`260`** |

**后果（必须记住，不得当成「截图一直拿到了」或「截图一直没拿到」）：**

- **门禁强证据③（截图）在锁屏会话下确实 blocked，但在解锁复跑后已取得。** 锁屏会话的原值仍逐字保存在
  `.planning/phases/02-playback-core/evidence/gate-01-locked-session.log`
  （`SCREENSHOT=blocked reason=png_identical_to_control_capture` / `FRAME_DRIVER=timer_fallback_hz30`）。
- **`01-VERDICT.md` 与 `01-01-SUMMARY.md` 现在是 stale 的** —— 它们引用的 `SCREENSHOT=blocked`
  已不是库里的值。这是里程碑审计记的「4 处文档声称与事实不符」之一。
- `01-VERDICT.md` 的「交给下游硬约束 #3」（刷新回调拿不到、Phase 2 必须复测）同样已被这次复跑推翻。

---

## 未覆盖项（诚实说明）

**`bash test.sh` 全绿 ≠ 本 Phase 14 个 task 都已验。** 以下 6 项**从未取得读数**
（截图一项已于上方说明被解锁复跑解除，故不再计入）：

| # | 未覆盖项 | 为什么自动化不了 | 证据 |
|---|---------|----------------|------|
| 1 | **`powermetrics` 四组 × 300 秒 A/B 的 mW 数字**（0/4 组） | 本机无免密 sudo；硬约束 `powermetrics must be invoked as the superuser` | `ab-verdict.txt:AB_GROUPS_PLANNED=4 AB_GROUPS_MEASURED=0` · `ab-blocker-evidence.txt` 两条 `rc=1` |
| 2 | **`com.apple.screenIsLocked` 跃迁**（`fires` / `silent` 二选一） | 探针真跑满 120 秒，但屏幕全程已锁，无跃迁边沿可观察 | `ab-verdict.txt:SCREENLOCK=unknown` · `lock.log:LOCKPROBE_DONE events=0` · `SCREEN_WAS_LOCKED_AT_PROBE_START=1` |
| 3 | **D-02 人工 10 秒：桌面图标可点选、可拖动** | 无自动信号能覆盖「手点」这个动作（D-02 已拍板事后补做，不阻塞） | 无 |
| 4 | **菜单栏图标肉眼确认 + 点开后 5 条菜单渲染** | 需人看屏幕；VERIFICATION 另记 W3：`menubarExtra=ok` 是**硬编码打印**，不是测量值 | `menubar.log:NOTE2=dock_absence_is_not_visually_confirmed_this_spike_makes_no_screenshot_claim` |
| 5 | **Chrome 真全屏 / 超宽屏 / 真全屏 live 样本 S1** | 本机无 Chrome、单屏（`SCREENS_COUNT=1`） | `fullscreen-scenarios.log:BLOCKED_REASON=no_google_chrome_installed` / `=no_ultrawide_display_attached_screens_count=1` / `=toggleFullScreen_had_no_effect_while_session_locked` |
| 6 | **纯几何全屏判定在本机会误判**（`FALSE_POSITIVE_OBSERVED=1`，方向 = **误暂停**，与 SC4 想要的相反） | 实测事实，不是缺口 —— Phase 3 被强制要求引入几何之外的判别信号 | `fullscreen-scenarios.log:FALSE_POSITIVE_OBSERVED=1 direction=safe_area_filled_but_not_fullscreen_scored_fullscreen pid=1227 coverage=1.000` |

---

## 全量复跑读数（2026-10-04 本机实测）

| 命令 | 读数 |
|------|------|
| `swift test` | `Executed 199 tests, with 0 failures` · exit 0 |
| `bash test.sh` | **通过 104 · 失败 0 · 跳过 1** · exit 0（跳过项 = Phase 7 的 7 天长跑） |

**注意读数的边界**：上面两行是**今天**的全项目基线，**不是 Phase 1 当时的读数**。
Phase 1 收口时是 `test.sh` 通过 15。两者不可混为一谈，也**不可**用今天的全绿倒推
Phase 1 那些「需要 root / 需要真人手点 / 需要 20 分钟 A/B」的项已经解决。

---

## Validation Sign-Off

- [x] 所有 task 都有 `<automated>` verify（14/14）
- [x] 无连续 3 个 task 缺 automated verify
- [x] Wave 0 无 MISSING 引用 → `wave_0_complete: true`
- [x] 无 watch-mode 标志
- [x] 未覆盖项已逐条列出（6 项：4 项人工 + 1 项环境 + 1 项已证伪的判据方向）
- [x] **已登记 `01-VERDICT.md` / `01-01-SUMMARY.md` 相对在库 evidence 已 stale**（见「证据被后续 commit 覆盖」）
- [ ] **把 frontmatter 的 `nyquist_compliant` 翻成 `true` —— 未达成。** 需先解除 6 项未覆盖（尤其 #1 powermetrics、#2 锁屏跃迁），再实跑 `/gsd-validate-phase`

**Approval:** pending —— `/gsd-validate-phase 1` 从未跑过
