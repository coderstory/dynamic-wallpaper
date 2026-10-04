---
phase: 05-settings
slug: settings
status: draft
nyquist_compliant: false
wave_0_complete: true
tasks_total: 8
tasks_verified: 5
tasks_unverified: 3
tasks_partial: 2
created: "2026-10-04"
updated: "2026-10-04"
---

# Phase 05-settings — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

## 为什么 `status: draft` / `nyquist_compliant: false`

`/gsd-validate-phase` **从未在本 Phase 上跑过**。本文件是 2026-10-04 依据 PLAN / SUMMARY /
VERIFICATION / UI-SPEC / evidence 手工补记的覆盖台账。按 `audit-milestone.md` §5.5（#2117），
`status: draft` = **NOT-VALIDATED（覆盖 TODO）**，不是合规失败。
`05-VERIFICATION.md` 自身是 `status: human_needed` / `score: 7/9 must-haves verified` ——
那是独立复核的结论，与本文件的 Nyquist 覆盖是两个维度。

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest via SwiftPM + **XCUITest via `Pic.xcodeproj`（包住 SwiftPM 包）** + 无头回归 `bash test.sh` |
| **Config file** | `Pic.xcodeproj` · `test.sh`（Phase 5 段 7 条常驻门禁）· `scripts/run-uitests.sh`（含锁屏守卫）· `scripts/probe-{settings,settings-restart,status-card}.sh` |
| **Quick run command** | `swift test --package-path . --filter SettingsApplierTests` |
| **Full suite command** | `bash test.sh` |
| **Estimated runtime** | swift test ~5 秒 · test.sh ~60 秒 · `run-uitests.sh` 需解锁会话才能真正跑 |

---

## Sampling Rate

- **After every task commit:** 该 task 的 `<automated>`（`swift build` / `swift test --filter` / 对应 probe）
- **After every plan wave:** `swift test --package-path .` 全量 + `bash test.sh` Phase 5 段
- **Before `/gsd-verify-work`:** `bash test.sh` 必须全绿；**`run-uitests.sh` 另需解锁会话**
- **Max feedback latency:** < 30 秒（探针段 `alarm 120` 封顶）

---

## Per-Task Verification Map

`wave_0_complete: true` 的依据：**8 / 8 个 task 在 PLAN 里都带 `<verify><automated>`**。

| Plan | # | Task | 有 `<verify>` 判据 | 证据来源 | 结论 |
|------|---|------|------------------|---------|------|
| 05-01 | 1 | 设置窗 tracer —— 皮肤/几何/关窗不退 + 速度当场生效（shouldPlay 门）+ 证据桥 | ✅ `swift build …` + 探针 | **活体**读数 `settings-tracer.log:PIC_SETTINGS_WINDOW width=780 minWidth=680`（产品视图的 `emitWindowGeometry()` 读 `NSApp.windows` 打出，非 mock）；`settings-apply.log` 应用生效 | ✅ 已验（**关窗不退进程是运行时跃迁，零测试触达**） |
| 05-01 | 2 | `Pic.xcodeproj`（包住 SwiftPM 包）+ 首批 XCUITest + 锁屏守卫的 `run-uitests.sh` | ✅ `bash -n scripts/run-uitests.sh` + `plutil -lint project.pbxproj` | `SCRIPT_SYNTAX_RC=0`；`PLUTIL_RC=0`；**`XCODEBUILD_BUILD_RC=0`**（测试目标编译通过） | ⚠️ **已验但只到「编译通过」** —— 守卫正确挡住了：`SCREEN_LOCKED=1` → `UITEST_STATUS=blocked` |
| 05-02 | 1 | 六项全绑定 + 两条置灰联动 + 电池当场重估 | ✅ `src_count` 源码门 + `swift test` | `rotationControlsEnabled(playMode:)` / `volumeControlsEnabled(isMuted:)` 各有正反两向单测；`GlowSlider` 的 `guard isEnabled` 在 `.onChanged` **与** `.onEnded` **两处**；`GlowStepper` 走原生 `Button` → **真禁用，不是只调透明度** | ✅ 已验 |
| 05-02 | 2 | 字体系统默认落地 + 重启保留探针（TEST-04 行为面） | ✅ `swift test` + 探针 | **活体三轮** `settings-restart.log:ROUND1_SEEDED=ok` `:ROUND2_IDEMPOTENT=ok` `:ROUND3_DEFAULTS=ok`；`SettingsStoreTests` 11 条 | ✅ 已验 |
| 05-03 | 1 | 空态 / HoldReason 文案 / ffmpeg 可用性 —— 纯映射层 + 穷举单测（两条变异） | ✅ `swift test` + 变异 | `testEmptyStateBodyMatchesSpecVerbatim`（逐字相等）+ `testEmptyStateBodyIsSingleSourced`（剥注释后计数 == 1）双锁；`testThreeHideStatesShareOneEmptySkin` 穷举三态一张皮；ffmpeg 两值穷举且**零执行** | ✅ 已验 |
| 05-03 | 2 | 来源卡/维护卡/运行状态卡接线 + 空态皮 + 活体探针 | ✅ `src_count` 源码门 + `bash scripts/probe-status-card.sh` | `status-card.log:STATUS_CARD_PROBE=PASS`；活体 `settings-tracer.log:PIC_LIBRARY_STATE=no_playable_videos` | ⚠️ **已验但锁屏态副标签未活体观测** —— `LIVE_LOCK_OBSERVATION=blocked reason=screen_locked`（W-29） |
| 05-04 | 1 | **XCUITest 全套 —— 控件/联动/空态/菜单/拖速度** | ✅ `src_count` 源码门 + `run-uitests.sh` 判据 | 🔴 **`UITEST_STATUS=blocked reason=screen_locked`；日志里没有任何 `Test Case` 行** —— 10 条用例**一条都没跑** | ❌ **未验（锁屏）** |
| 05-04 | 2 | test.sh Phase 5 常驻门禁 + 人工项登记（W-33 听音）+ 三件套收口 | ✅ `bash -n test.sh` + 门禁段 | 7 条常驻门禁全 ✅：设置窗零 AVFoundation / PicCore 展示层零 UI 框架 / `NSOpenPanel` 单文件 / 电池单一落点 / ffmpeg 零执行 / `MUT-P5-` 零残留 / W 编号 `uniq -d == 0` | ✅ 已验 |

**合计：8 个 task · ✅ 已验 5 · ⚠️ 已验但只到编译 / 锁屏子项未观测 2 · ❌ 未验 1（05-04 T1，XCUITest 零执行）**

---

## Wave 0 Requirements

不需要。8 / 8 个 task 自带 `<verify><automated>`。

---

## 🔴 XCUITest 数字纠错：11 条 → **10 条**

`05-04-SUMMARY.md` 与 `W-2026-10-03-34` 的首句都写「**11 条** XCUITest」，
`05-VERIFICATION.md` Advisory #3 已判定这是**记账错一位**：

> `SettingsWindowUITests` 4 条 + `SettingsControlsUITests` 6 条 = **10 条 `func test`**

2026-10-04 本机实测复核：`grep -rn "func test" UITests/` → **10**。**「11」是错的，正确数字是 10。**
这不影响任何判定（记账数字错一位），但任何引用「11 条」的文档都应改。
（`05-VERIFICATION.md` 另记 Advisory #2：`storeKeys` 只列 7 键，而 `SettingsStore` 现有 8 键 ——
`launchAtLogin` 不会被清 → 跨用例状态串味。这是 Phase 7 引入的，不是 Phase 5 缺陷。）

---

## 🔴 查到的假绿：`05-01-SUMMARY.md` D3 声称的 e2e 证据不存在

`05-01-SUMMARY.md` 的 coverage 块 `D3`（描述含「**关窗进程不退**」）写着：

```yaml
- kind: e2e
  ref: "XCUITest testClosingWindowKeepsProcessAlive（evidence/uitest.log 中 passed，4.6s）"
  status: pass
human_judgment: false
```

**但 `evidence/uitest.log` 全文件只有两行**：

```
SCREEN_LOCKED=1
UITEST_STATUS=blocked reason=screen_locked
```

**没有任何 `Test Case` 行**，更没有「passed，4.6s」。该 XCUITest **一次都没跑过**。
而且这一条标的是 `human_judgment: false` —— 它**没有**被标成需人工，因此不会被下游流程捞出来。

对照：同一份 SUMMARY 的 `D5` 诚实地写了「**未跑**：改写提交在 ffd0777，本 plan 未重跑 UI 测试」，
`status: unknown` + `human_judgment: true`。**同一文件里一条诚实、一条假绿，不一致。**

**后果**：`D3` 的描述里「关窗进程不退」这半句，正是 Human #6 登记的人工项；
而 SUMMARY 的 coverage 块却用一条不存在的 e2e 证据把它记成了 `pass`。
**本文件不采信该条 `status: pass`。** 这是里程碑审计记的「4 处文档声称与事实不符」之一，
建议单独修 `05-01-SUMMARY.md`。

---

## 未覆盖项（诚实说明）

**`bash test.sh` 7 条 Phase 5 门禁全绿 + `swift test` 198 全绿 ≠ 8 个 task 都已验，更 ≠ 5 条 SC 达成。**
`05-VERIFICATION.md` 的判定是 **`status: human_needed`**、**6 项人工验证**。

| # | 未覆盖项 | 为什么自动化不了 | 证据 |
|---|---------|----------------|------|
| 1 | 🔴 **XCUITest 10 条一条都没跑** | 锁屏。`run-uitests.sh` 的守卫把它挡成 blocked。**测试目标编译通过（`XCODEBUILD_BUILD_RC=0`），但一条用例都没执行过** | `UITEST_STATUS=blocked reason=screen_locked` · `SCREEN_LOCKED=1`；日志无任何 `Test Case` 行 |
| 2 | 🔴 **SC-4「0.5×/2× 保持原音高」** | **自动化零覆盖这条。** `.spectral` 在 `PlayerController.swift:37` 是**纯源码形态，没有一条测试断言它** —— `grep -rniE "pitch\|音高\|不变调\|变调" Tests/ UITests/` **命中 0**。能测的只有相邻的「速度当场生效」（`SettingsApplierTests` 8 条），**那证的不是音高** | `05-VERIFICATION.md` Advisory #4（ℹ️ Info「静默失效风险」）· W-2026-10-03-33 |
| 3 | **SC-4 听音** —— 以 0.5× 与 2× 各播一段**含人声**的素材 | **这一项原理上没有断言能表达。** 纯音乐 / 无人声素材不算 | W-33 |
| 4 | **空态目视** —— 计数 0 时确认警告黄数字、感叹号瓷砖、逐字文案、重扫按钮可点 | 活体目视。文案常量已双锁 + 穷举单测，缺的只是「屏上真的长这样」 | `05-VERIFICATION.md` Human #3 |
| 5 | **布局目视** —— B1 深海 + L4 双列（左：来源/播放，右：电源与系统/维护/运行状态）+ 无侧边栏 | 活体目视。`NavigationSplitView`/`NSSplitView`/`sidebar` 在 `Sources/PicApp/` 命中 0 ✅（结构已证），但**排版像素无机器读数** | Human #4 |
| 6 | **锁屏态副标签** —— 运行状态卡标题「已暂停」+ 副标签逐字「屏幕已锁定」 | 活体目视；原因→文案的映射已由 6 条穷举单测逐字锁死 | W-29 · `status-card.log:LIVE_LOCK_OBSERVATION=blocked reason=screen_locked` |
| 7 | **关窗路径** —— 进程不退、菜单栏图标仍在、Dock 无图标 | 运行期状态跃迁，零测试触达 | Human #6（`behavior_unverified` 真相 #8） |
| 8 | **产品设置窗渲染无机器读数** | `test.sh` 的「设置窗渲染成功」那一段渲的是 **`.planning/spike/SettingsSpike.swift`**（`Render.swift` 里的 `SettingsSpike()`），**不是**产品 `Sources/PicApp/Settings/SettingsView.swift` —— 后者要 8 个注入闭包 + 4 个 `@Environment` 对象，全项目零 `ImageRenderer` 调用点，本段渲不了 | `05-VERIFICATION.md` Anti-Patterns：`test.sh` 35, 698 行（ℹ️ Info）。产品 UI 视觉面只能活体目视 |
| 9 | **解锁重跑前必须先修的过期断言** | `SettingsControlsUITests.swift:157` 的 `XCTAssertFalse(el("transcode-open").isEnabled)` 与产品代码矛盾（Phase 6 已改成「视觉置灰但仍可点」）。**不修就重跑会以 failed 收场而非 passed**，直接卡住 W-34 的解开条件 | `05-VERIFICATION.md` Advisory #1 |

> **四个探针本次均未重跑** —— 重跑会覆盖已入库的 evidence（`test.sh` 的 `p4_line` 纪律：探针重跑会覆盖已入库 evidence）。
> 本文件引用的是入库 verdict，并已回到生成它们的源码逐条复核。

### 本 Phase 的 5 条 SC 判定（逐字取自 `05-VERIFICATION.md`）

| SC | 判定 | 要点 |
|----|------|------|
| SC-1 设置窗 780/680 + B1+L4+无侧边栏；关窗只隐藏、进程不退出 | **PARTIAL** | 几何与皮肤有活体读数 `width=780 minWidth=680` + 无侧边栏（命中 0）；**「关窗只隐藏、进程不退出、图标仍在」这半句是运行期状态跃迁，零测试触达** |
| SC-2 空态警告黄 + 感叹号瓷砖 + 逐字文案 | **PASS** | 文案常量双锁 + 三态一张皮穷举单测 + 产品视图分支代码在位；**屏上渲染未目视（记为人工项，非判定缺口）** |
| SC-3 两条置灰联动**禁用交互** | **PASS** | 纯函数正反两向单测 + `GlowSlider` 的 `guard isEnabled`（onChanged/onEnded 两处）+ `GlowStepper` 走原生 Button → **真禁用，不是只调透明度** |
| SC-4 0.5×–2× 保音高 + 改动当场生效 + 重启保留 | **PARTIAL** | 当场生效（4 条行为级单测）与重启保留（三轮活体）都 PASS；**「保持原音高」只到代码，零测试覆盖，且人声听音从未做** |
| SC-5 运行状态卡：暂停 + 原因 + ffmpeg 可用性 | **PASS** | 6 条原因文案逐字锁 + 多原因排序/连接单测 + ffmpeg 两值穷举且零执行 + 活体 `FFMPEG_SELF_CONSISTENT=ok`；锁屏态副标签未活体观测（W-29，人工项） |

**2 PASS / 3 PARTIAL / 0 FAIL —— 三条 PARTIAL 的成因全部是「环境锁屏 + 听感」，无一是产品代码缺失。**

---

## 全量复跑读数（2026-10-04 本机实测）

| 命令 | 读数 | Phase 5 当时读数 |
|------|------|----------------|
| `swift test` | `Executed 199 tests, with 0 failures` · exit 0 | `Executed 198 tests, with 0 failures` |
| `bash test.sh` | **通过 104 · 失败 0 · 跳过 1** · exit 0（跳过 = Phase 7 的 7 天长跑） | `通过 102 失败 0 跳过 1` |

---

## Validation Sign-Off

- [x] 所有 task 都有 `<automated>` verify（8/8）
- [x] 无连续 3 个 task 缺 automated verify
- [x] Wave 0 无 MISSING 引用 → `wave_0_complete: true`
- [x] 无 watch-mode 标志
- [x] 未覆盖项已逐条列出（9 项）
- [x] **已登记 XCUITest 数字纠错：11 → 10 条**，且 10 条零执行
- [ ] **把 frontmatter 的 `nyquist_compliant` 翻成 `true` —— 未达成。** 需先在解锁会话修 Advisory #1 后重跑 `run-uitests.sh`（10 条全过），再做 SC-4 听音，再实跑 `/gsd-validate-phase`

**Approval:** pending —— `/gsd-validate-phase 5` 从未跑过
