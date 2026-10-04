---
phase: 03-system-events
slug: system-events
status: draft
nyquist_compliant: false
wave_0_complete: true
tasks_total: 10
tasks_verified: 9
tasks_unverified: 1
tasks_partial: 0
created: "2026-10-04"
updated: "2026-10-04"
---

# Phase 03-system-events — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

## 为什么 `status: draft` / `nyquist_compliant: false`

`/gsd-validate-phase` **从未在本 Phase 上跑过**。本文件是 2026-10-04 依据 PLAN / SUMMARY /
VERDICT / evidence 手工补记的覆盖台账。按 `audit-milestone.md` §5.5（#2117），
`status: draft` = **NOT-VALIDATED（覆盖 TODO）**，不是合规失败。

> 本 Phase **没有 `03-VERIFICATION.md`** —— 它在 GSD 的 `gsd-verifier` 体系之前就关闭了
> （`v3.0-MILESTONE-AUDIT.md` §2 记作「历史关闭，验证文件早于 GSD 体系」）。
> 因此本 Phase 的判定权威是 `03-VERDICT.md` + `03-PDCA.md`，没有独立第三方复核背书。

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest via SwiftPM（幂集穷举 + 注入式反向验证）+ 无头回归 `bash test.sh` |
| **Config file** | `Package.swift` · `test.sh` · `scripts/probe-{lock,fullscreen,display,power}.sh` · `scripts/run-probe.sh holds` |
| **Quick run command** | `swift test --package-path . --filter HoldArbiterTests` |
| **Full suite command** | `bash test.sh` |
| **Estimated runtime** | swift test ~5 秒 · test.sh ~60 秒 |

---

## Sampling Rate

- **After every task commit:** 该 task 的 `<automated>`（swift build / swift test --filter / 对应 probe）
- **After every plan wave:** `swift test --package-path .` 全量 + 对应 probe
- **Before `/gsd-verify-work`:** `bash test.sh` 必须全绿
- **Max feedback latency:** < 30 秒（probe 段 `perl -e 'alarm 120…'` 封顶 120 秒）

---

## Per-Task Verification Map

`wave_0_complete: true` 的依据：**10 / 10 个 task 在 PLAN 里都带 `<verify><automated>`**。

| Plan | # | Task | 有 `<verify>` 判据 | 证据来源 | 结论 |
|------|---|------|------------------|---------|------|
| 03-01 | 1 | 锁屏端到端 —— HoldReason 补到 6 case + LockWatcher 接进 HoldArbiter + PIC_HOLD 改事件驱动 | ✅ `swift build … && swift test` | `BUILD_RC=0`；`HoldReason` 6 个 case 在运行时生成幂集 | ✅ 已验 |
| 03-01 | 2 | TEST-01 核心资产 —— 幂集恰 64 组 + 锁屏退出全屏不恢复 + 注入式反向验证 | ✅ `cp … perl -0pi … swift test`（变异） | `testAllCasesCountIsSixAndPowersetIsSixtyFour`；反向验证 `MUTATED_RC=1`（真红） | ✅ 已验 |
| 03-02 | 1 | FullscreenGeometry —— 坐标系翻转 + 14/9 内缩补偿 + 按 pid 聚合 | ✅ `swift build … swift test --filter` | `FullscreenGeometryTests` 5 条全绿；四条 Phase 1 基准逐条对齐 | ✅ 已验 |
| 03-02 | 2 | FullscreenVerdict —— 几何与信号缺一不可 + 接两个公开通知 + styleMask 实测 | ✅ `swift build … probe-fullscreen.sh` | 结构 ✅；`fullscreen-signals.log:FULLSCREEN_VERDICT=0 reason=not_covering` `:STYLEMASK_UNAVAILABLE=1` | ⚠️ **已验但真实跃迁未观测** —— `FULLSCREEN_TRANSITION=unobservable reason=session_unlocked CGSSessionScreenIsLocked=0` |
| 03-03 | 1 | DisplayWatcher —— 熄屏 + 睡眠两个独立 reason | ✅ `swift build …` | `DisplayWatcherTests` 全绿；`DISPLAY_RECONFIG_CALLBACKS_FIRED=0` | ✅ 已验 |
| 03-03 | 2 | 熄屏与睡眠的信号实测 —— 注册成功 + 当前读数 + 两行 unobservable | ✅ `perl -e 'alarm 120' bash scripts/probe-display.sh` | `display-sleep-signals.log:DISPLAY_SLEEP_TRANSITION=unobservable` `:SYSTEM_SLEEP_TRANSITION=unobservable` | ⚠️ **已验但跃迁未发生** —— 显示器本就熄着（`CGDisplay_IS_ASLEEP=1`）；睡眠被 `caffeinate -i -t 300` 挡着 |
| 03-04 | 1 | PowerWatcher + BatteryHoldPolicy 纯函数 + `pauseOnBattery`（默认关闭） | ✅ `swift build …` | `PowerWatcherTests` 6 条；`BATTERY_HOLD enabled=0 verdict=0` | ✅ 已验 |
| 03-04 | 2 | 电源来源实测 —— IOKit 读数 + run loop source 注册 | ✅ `perl -e 'alarm 120' bash scripts/probe-power.sh` | `power-signals.log:IS_ON_BATTERY=0` `:POWER_SOURCE_VALUE=AC Power` `:INTERNAL_BATTERY_PRESENT=1` | ⚠️ **已验但跃迁需物理动作** —— `POWER_TRANSITION=unobservable reason=requires_physical_unplug action=unplug_power_cord_required` |
| 03-05 | 1 | 装配四个 Watcher + D-12 HoldStatus 落点 + D-06 起播路径收口 | ✅ `swift build … swift test` | `BUILD_RC=0`；起播路径 `player.player.play()/pause()` 计数各 = 0 | ✅ 已验 |
| 03-05 | 2 | 活体 evidence（真实系统信号）+ test.sh 全量判据 + 03-VERDICT | ✅ `run-probe.sh holds … bash test.sh` | 🔴 **plan 判据要求 `holds=(screenLocked)` 且 `summary=锁屏 reasons=1`；实测是 `holds=(screenLocked,displayAsleep)` / `summary=锁屏,显示器熄屏 reasons=2` —— 两条 grep 均返回 0，命中 `fails_when ②`**（显示器当时也是熄着的）。`03-05-SUMMARY.md:84-85` 如实写明该 AC 未达成，未粉饰 | ❌ **未验** —— 唯一一条真正没过的 task 判据（`PIC_HOLD_OBSERVER_TICKS=1` 与 `test.sh 通过 50 失败 0` 那两半过了） |

**合计：10 个 task · ✅ 已验 9 · ❌ 未验 1（`03-05` T2，plan 判据两条 grep 均返回 0）**

> ⚠️ 另有 3 个 task（`03-02` T2、`03-03` T2、`03-04` T2）的 verify **执行时通过了**，
> 但**今天拿库里的 evidence 重跑它们的判据会红** —— 因为 `6116186` 覆盖了日志（见下节）。
> 例如 `03-04` T2 的判据要 `^POWER_SOURCE_KEY=AC Power$`，库里实际是
> `POWER_SOURCE_KEY=Power Source State`（值在下一行 `POWER_SOURCE_VALUE=AC Power`）。
> 这不是执行时的失败，是**证据不可复现**。

---

## Wave 0 Requirements

不需要。10 / 10 个 task 自带 `<verify><automated>`。

---

## ⚠️ 证据被后续 commit 覆盖 —— 判读本文件前必读

**commit `6116186`（2026-10-03 12:04）重跑探针，覆盖了本 Phase 的 4 份 evidence 日志**
（`fullscreen-signals.log` / `display-sleep-signals.log` / `lock-wiring.log` / `power-signals.log`），
重跑是在**解锁会话**下做的。**结论没变，但原因字段变了** —— 而且 `lock-wiring.log` 出现了自相矛盾的一行：

| 文件 | 库里当前值 | `03-VERDICT.md` 引用的值 |
|------|-----------|------------------------|
| `fullscreen-signals.log` | `FULLSCREEN_TRANSITION=unobservable reason=session_unlocked CGSSessionScreenIsLocked=0` · `FULLSCREEN_VERDICT=0 reason=not_covering coverage=0.014` | `reason=session_locked CGSSessionScreenIsLocked=1` · `reason=geometry_without_signal coverage=1.000` |
| `display-sleep-signals.log` | `*_TRANSITION=unobservable reason=session_unlocked CGSSessionScreenIsLocked=0` | `reason=session_locked CGSSessionScreenIsLocked=1` |
| `lock-wiring.log` | 🔴 `LOCK_TRANSITION=unobservable reason=session_locked CGSSessionScreenIsLocked=0` —— **reason 说 locked，读数说未锁，自相矛盾** | `reason=session_locked CGSSessionScreenIsLocked=1` |
| `power-signals.log` | `POWER_TRANSITION=unobservable reason=requires_physical_unplug CGSSessionScreenIsLocked=0` | `… CGSSessionScreenIsLocked=1` |

**读法**：这四条**仍然是 `unobservable`** —— 在解锁会话下重跑，跃迁**依然没发生**
（没有应用进全屏、显示器没熄、系统没睡、没拔电源）。所以 §未覆盖项 的 7 条**一条都没解除**。
变的只是「为什么没观测到」：从「屏幕锁着观测不到」变成了「事件在探测窗口内压根没发生」。

`fullscreen-signals.log` 的窗口集也变了 —— 从锁屏时的 4 扇（Ghostty / CC Switch / 音乐 / DevDesk）
变成解锁后的 5 扇真实桌面窗口（Ghostty / CC Switch / 微信 / Microsoft Edge / Pic），
`COVERAGE` 从 `1.000` 降到 `0.014`，`FULLSCREEN_VERDICT` 的原因码从 `geometry_without_signal`
变成 `not_covering`。**两次都没有任何一个窗口被判成全屏**，因此
「纯几何全屏判定会误暂停」这个 Phase 1 结论，在解锁会话下**没有得到反证，也没有得到证实**。

---

## 未覆盖项（诚实说明）

**`test.sh` 通过 50 全绿 ≠ SC1/SC2/SC3 达成。** `03-VERDICT.md`「没跑过」段逐条列出 **7 项**：

| # | 未覆盖项 | 为什么自动化不了 | 证据 |
|---|---------|----------------|------|
| 1 | **SC1 的真实全屏跃迁 + 刘海屏 / Chrome / 超宽屏三场景各一遍** | 本机无 Chrome、单屏。**未合成**系统跃迁去凑。解锁复跑后跃迁仍未发生 | `fullscreen-signals.log:FULLSCREEN_TRANSITION=unobservable reason=session_unlocked CGSSessionScreenIsLocked=0`（VERDICT 引的是被覆盖前的 `session_locked` 版） |
| 2 | **SC2 的锁屏跃迁（lock → unlock）** | 会话没有边沿可等。合成通知那条只验接线，不冒充真实跃迁 | `lock-wiring.log:LOCK_TRANSITION=unobservable`（该行 reason 与读数自相矛盾，见上节） |
| 3 | **SC2 的熄屏跃迁与睡眠跃迁** | 显示器**已经是熄着的**（`pmset displaysleep 5` 的稳态），点亮那一下没发生；睡眠被 `caffeinate -i -t 300` 挡着 | `display-sleep-signals.log:DISPLAY_SLEEP_TRANSITION=unobservable reason=session_unlocked` `:SYSTEM_SLEEP_TRANSITION=unobservable`；`DISPLAY_RECONFIG_CALLBACKS_FIRED=0` |
| 4 | **SC1 的反向实测：全屏误暂停的复现率** | 观测到但**给不出稳定复现率** —— 一次插桩 3 轮中 1 轮读到，随后 5 轮复跑均未复现。**未为了让它非 0 去制造应用切换事件** | `evidence/fullscreen-falsepositive.log`；登记为 `W-2026-10-03-23` |
| 5 | **SC3 的拔电源 / 插回电源** | 本机全程在 AC 上，需物理动作。**未制造** | `power-signals.log:POWER_TRANSITION=unobservable reason=requires_physical_unplug` `:PMSET_CROSSCHECK=Now drawing from 'AC Power'` |
| 6 | **SC2「解除后各自正确续播」的活体一跳** | 依赖 #2 #3 的跃迁。锚点逻辑本身已由单测与合成路径证明（`LOCK_RESUME seeks_to_anchor=1 seeks=42.000`），但**真实跃迁下的续播**未观测 | `lock-wiring.log:LOCK_ANCHOR_PRESERVED=1`（合成路径） |
| 7 | **四个 Watcher 常驻的泄漏证据** | 需要长跑（Phase 7 的 20 轮休眠/唤醒 + 7 天）。本 Phase 只证明**注册与注销成对**：`LOCK_STOP` / `DISPLAY_STOP_UNREGISTERED=1` / `POWER_STOP_UNREGISTERED=1` / `FULLSCREEN_OBSERVERS_REMOVED=1` | `test.sh` 每次重验；泄漏证据交 Phase 7 |

### 本 Phase 的 5 条 SC 判定（逐字取自 `03-VERDICT.md`）

| SC | 判定 | 要点 |
|----|------|------|
| SC1 任意应用全屏 → 暂停 / 退出 → 从暂停处续播 | **PARTIAL** | 合取判定跑通（`FULLSCREEN_VERDICT=0 reason=geometry_without_signal`），**真实跃迁未观测** |
| SC2 锁屏 / 熄屏 / 睡眠三类事件各自暂停并各自续播 | **PARTIAL** | 锁屏与熄屏**有活体证据**；睡眠与解除后的续播未观测 |
| SC3 「电池供电时暂停」默认关闭；打开后拔电暂停、插回续播 | **PARTIAL** | 默认关闭 + 判定逻辑已过；**拔/插电源均未实测** |
| SC4 veto 仲裁正确（锁屏态退出全屏不恢复；多条件叠加才续播） | **PASS** | 6 case → 恰 **64** 组幂集，运行时从 `allCases` 生成；注入式反向验证 `MUTATED_RC=1` |
| SC5 续播锚点不漂移 | **PASS** | 6 reason 逆序解除下 `seeks == [42.0]`（一条 seek，锚点未被二次覆盖） |

**3 PARTIAL / 2 PASS —— 3 条 PARTIAL 的成因全部是「真实跃迁未观测」，无一是产品代码缺失。**

---

## 全量复跑读数（2026-10-04 本机实测）

| 命令 | 读数 | Phase 3 当时读数 |
|------|------|----------------|
| `swift test` | `Executed 199 tests, with 0 failures` · exit 0 | `Executed 67 tests, with 0 failures` |
| `bash test.sh` | **通过 104 · 失败 0 · 跳过 1** · exit 0 | 通过 50 / 失败 0 / 跳过 0 |

> **⚠️ 噪声说明（2026-10-04，非回归）**：今天跑 `test.sh` 时 Phase 3 四条
> （LOCK / FULLSCREEN / DISPLAY / POWER）后跟 `⚠️ 该 evidence 的读数与入库版本不同`。
> 已证为**环境噪声** —— stash 掉当日全部改动回到干净 HEAD 复跑，四条同样带 ⚠️；
> 两次产物 `cmp` 逐字节一致。成因是当前会话锁定态与 Phase 3 入库时不同。判据仍全 ✅，非回归。

---

## Validation Sign-Off

- [x] 所有 task 都有 `<automated>` verify（10/10）
- [x] 无连续 3 个 task 缺 automated verify
- [x] Wave 0 无 MISSING 引用 → `wave_0_complete: true`
- [x] 无 watch-mode 标志
- [x] 未覆盖项已逐条列出（7 项，含 4 项需真实跃迁 / 1 项需物理动作 / 1 项需长跑）
- [ ] **本 Phase 无 `03-VERIFICATION.md`** —— 缺独立第三方复核（`gsd-verifier`）背书
- [ ] **把 frontmatter 的 `nyquist_compliant` 翻成 `true` —— 未达成。** 需先在解锁会话重采四类跃迁，再实跑 `/gsd-validate-phase`

**Approval:** pending —— `/gsd-validate-phase 3` 从未跑过
