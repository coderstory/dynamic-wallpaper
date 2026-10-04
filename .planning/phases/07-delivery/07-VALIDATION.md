---
phase: 07-delivery
slug: delivery
status: draft
nyquist_compliant: false
wave_0_complete: true
tasks_total: 12
tasks_verified: 8
tasks_unverified: 4
tasks_partial: 4
created: "2026-10-04"
updated: "2026-10-04"
---

# Phase 07-delivery — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

## 为什么 `status: draft` / `nyquist_compliant: false`

`/gsd-validate-phase` **从未在本 Phase 上跑过**。本文件是 2026-10-04 依据 PLAN / SUMMARY /
VERDICT / RESEARCH / UAT-SOAK / evidence 手工补记的覆盖台账。按 `audit-milestone.md` §5.5（#2117），
`status: draft` = **NOT-VALIDATED（覆盖 TODO）**，不是合规失败。
本 Phase **没有 `07-VERIFICATION.md`** —— 判定权威是 `07-VERDICT.md`，无独立第三方复核背书。

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest via SwiftPM + 打包/卸载/压力脚本 + 无头回归 `bash test.sh`（Phase 7 段 11 条通过 + 1 条 skip） |
| **Config file** | `build.sh` · `test.sh` · `scripts/{verify-packaging,verify-uninstall,stress-rotation,probe-sys01,soak-sampler,soak-analyze,soak-agent}.sh` · `create-dmg` / `hdiutil` |
| **Quick run command** | `swift test --package-path . --filter AutoStartManagerTests` |
| **Full suite command** | `bash test.sh`（一条命令跑完全部可自动化验证） |
| **Estimated runtime** | `bash test.sh` 最长段是 `build.sh`（`alarm 1200` 封顶 20 分钟） |

---

## Sampling Rate

- **After every task commit:** 该 task 的 `<automated>`（`swift test --filter` / 对应脚本）
- **After every plan wave:** `bash test.sh` 全量
- **Before `/gsd-verify-work`:** `bash test.sh` 必须全绿（`7 天长跑` 是 **skip 分支**，不算通过也不算失败）
- **Max feedback latency:** < 30 秒（打包段除外）

---

## Per-Task Verification Map

`wave_0_complete: true` 的依据：**12 / 12 个 task 在 PLAN 里都带 `<verify><automated>`**。

| Plan | # | Task | 有 `<verify>` 判据 | 证据来源 | 结论 |
|------|---|------|------------------|---------|------|
| 07-01 | 1 | 探针剥离 + 交付构建 + DMG —— `#if !PIC_NO_PROBE` 贯穿源码到产物 | ✅ `perl -e 'alarm 1200' bash build.sh` | `probe-strip.log:PROBE_STRIP_DELIVERY_SYMBOLS=0`；`packaging.log:PACK_REPEAT_CONSISTENT=1`（二进制 md5 两遍同为 `a42bfb65…`、plist md5 两遍同为 `23bfbbf4…`）`:PACK_HDIUTIL_VERIFY=ok` `:PACK_MOUNT_BINARY_MD5_MATCH=1` `:PACK_DMG_APP_COUNT=1` | ⚠️ **已验但 `create-dmg` 主路未走** —— `PACK_DMG_ROUTE_A/B=hdiutil_fallback`（需人给终端授予「自动化 → Finder」权限，AppleEvent -1743） |
| 07-01 | 2 | `PicProbe.app` 第二产物 + `run-probe.sh` 的 `APP_BIN` 迁移 | ✅ `bash build.sh` + `RUNPROBE_PICPROBE_REFS` | `DMG_APPS=1 PROBE_APP=0`（交付产物里**没有**探针产物）；`RUNPROBE_PICPROBE_REFS≥1` | ⚠️ **已验但读数只在散文里** —— `fixtures/` 不在 worktree（gitignored），影响 `run-probe.sh app` 一组读数（`ORDER=fail` / `SELF_LEVEL=none`，随 session 锁定态变化） |
| 07-01 | 3 | 图标集成 —— `iconutil` 出 `.icns` + `CFBundleIconFile` + 菜单栏 Template 图 | ✅ `bash build.sh` + 图标判据 | `Pic.icns=1,651,170 B`；`ICON_LOADED=true REPS=3` | ⚠️ **已验但 ASSET-03 的并排肉眼比对未做** —— 视觉判据，executor 不能代判 |
| 07-02 | 1 | LaunchAgentWriter + AutoStartManager —— 可注入双路线决策内核，7 条单测 + 两处变异 | ✅ `swift test --filter AutoStartManagerTests` + 变异 | `AUTOSTART_CORE_OK`；`RED1_DIAG=0 RED2_DIAG=0`（红光来自断言不是编译失败） | ✅ 已验 |
| 07-02 | 2 | 接线 —— `SettingsStore` 第 8 键 `launchAtLogin` + AppDelegate 启动 sync + Phase 5 开关接真行为 | ✅ `src_count` 源码门 + `swift test` | `Executed 14 tests, with 0 failures`；守卫测试非同义反复 | ✅ 已验 |
| 07-02 | 3 | `probe-sys01.sh` 一次性实测 —— A 判据 / 自动落 B / 强制清理 / 恢复偏好 | ✅ `perl -e 'alarm …' bash scripts/probe-sys01.sh` | `PROBE_RC=0`；7 个键齐备；`ACTIVE_ROUTE=smappservice` `:SYS01_SMAPP_STATUS=enabled`（路线 A 成立） | ⚠️ **已验但重启后自启 `SYS01_REBOOT_CONFIRMED=pending_human`** —— 需装 DMG 版并**重启机器**，07-02 已登记为 `user_setup` 项 |
| 07-03 | 1 | `soak-sampler.sh` 单次采样 + `soak-agent.sh` launchd 装卸（StartInterval 3600） | ✅ `SOAK_DIR=… bash scripts/soak-sampler.sh` + 装卸判据 | `LINE1_OK=1`；`PRINT_AFTER_STOP_RC=113`（agent 停后 sampler 正确退出） | ✅ 已验（**`alive=1` 那条路径从未被走过** —— 因为没真跑过 soak） |
| 07-03 | 2 | `soak-analyze.sh` —— 线性拟合斜率 + 连续性 + 漂移 + missing 判定，四个方向合成数据自证 | ✅ 合成数据跑五方向 | `healthy=pass` / `growth=fail` / `gap=invalid` / …；slope `0.07` | ✅ 已验（**合成数据自证有牙齿，真实数据一行都没有**） |
| 07-03 | 3 | `UAT-SOAK.md` 人工清单 —— 7 天周期、20+20 轮、电池让路、深浅色确认、结束动作 | ✅ `test -f UAT-SOAK.md` + 内容 grep | 清单文件存在且逐项 grep 通过 | ✅ 已验（**这是「清单已交付」，不是「7 天已跑」**） |
| 07-04 | 1 | `PIC_ROT_ADVANCES_TOTAL` 退出计数 + `stress-rotation.sh` —— 50 次换片、RSS 回基线 ±10% | ✅ `bash scripts/stress-rotation.sh` | `STRESS_ADVANCES=100`（≥50）；`STRESS_RSS_DRIFT_PCT=-1.8%`（\|漂移\| ≤ 10%）；`STRESS_TERMINATE_PATH=applicationWillTerminate`；`STRESS_DEFAULTS_RESTORED=1`；`STRESS_VERDICT=pass` | ✅ 已验 |
| 07-04 | 2 | `verify-packaging.sh` + `verify-uninstall.sh` —— 一致性锚 `.app`、DMG 挂载校验、ad-hoc 正向断言、四项残留复查为 0 | ✅ 两个脚本 + 10 个键 | 10 个键全在；四项残留复查（域 / plist / LaunchAgent / BTM）全 = 0 | ⚠️ **已验但两个分支从未跑过，且没有键要求它们跑** —— `DISABLEBOTH=0` `ROUTE_A=0` `DMG_ROUTE=0`；`sourceFolderPath` 为空的危险输入未被真实触发 |
| 07-04 | 3 | test.sh Phase 7 判据段 + 07-VERDICT —— 一条命令全绿，四栏诚实基线 | ✅ `perl -e 'alarm 1200' bash test.sh` | Phase 7 段 **11 条通过 + 1 条 skip**；对账：基线 86/0/5 → 补 `build/` 后 91/0/0 → 加本 Phase 段 102/0/1 | ✅ 已验 |

**合计：12 个 task · ✅ 已验 8 · ⚠️ 已验但有未跑分支 / 未观测项 4（`07-01` T1/T2/T3、`07-02` T3、`07-04` T2）· ❌ 完全未验 0**

---

## ⚠️ 三条「不可能失败」的门（判读时必须知道）

本 Phase 有 3 个 verify 判据**在结构上就不可能转红**，绿灯不携带信息：

| 判据 | 为什么不可能失败 | 性质 |
|------|----------------|------|
| `07-03` T3 —— `test -f UAT-SOAK.md` | 只检查清单文件存在。**清单存在 ≠ 7 天已跑** | 交付物存在性门 |
| `07-02` T3 —— `test "$(grep -cE '^SYS01_REBOOT_CONFIRMED=pending_human$' …)" -eq 1` | **字面量 `pending_human` 就是要求通过的值** —— 这是刻意的「诚实基线」设计：把「还没重启验证」写进判据 | 诚实基线门（设计如此，**不是假绿**） |
| `07-04` T2 —— `DISABLEBOTH` / `ROUTE_A` / `DMG_ROUTE` | 这三个键在 PLAN 与实际日志里**都返回 0**，即**根本没有对应的键要求它们跑** | 🔴 门禁设计缺口 |

前两条是**有意的诚实设计**，第三条是**门禁缺口** —— 性质不同，不要混为一谈。

---

## Wave 0 Requirements

不需要。12 / 12 个 task 自带 `<verify><automated>`。

---

## 未覆盖项（诚实说明）

**`bash test.sh` 通过 102 全绿 ≠ 12 个 task 都已验，更 ≠ 5 条 SC 达成。**
`07-VERDICT.md` 的「没跑过」段逐条列出 **7 项**：

| # | 未覆盖项 | 为什么自动化不了 | 证据 |
|---|---------|----------------|------|
| 1 | 🔴 **SC5 的 7 天在位长跑** | **人工周期** —— 机器得在、app 得开着、不主动重启。采样器与判据 07-03 已建好并用五份合成数据自证有牙齿，但**真实数据一行都没有** | `evidence/soak/soak.log` **0 字节**；`SOAK_VERDICT` **不存在**。`test.sh` 里它是 **skip 分支** —— **既不被自动判据卡死，也不被算成已通过** |
| 2 | **SC4 后半的 20 轮休眠/唤醒/锁屏/解锁** | 需真人操作（**唤醒必须真人开盖/按键**），本会话不可代做 | `UAT-SOAK.md` 人工轮次表；**一条都未执行** |
| 3 | **SC3 的重启后自启确认** | 需装 DMG 版并**重启机器**，07-02 已登记为 `user_setup` 项 | `sys01.log:SYS01_REBOOT_CONFIRMED=pending_human` |
| 4 | **ASSET-03 的并排肉眼比对** | 视觉判据，executor 不能代判 | `UAT-SOAK.md` 人工轮次表；**该记录不存在** |
| 5 | **SC1 的 `create-dmg` 主路** | 需人给终端授予「自动化 → Finder」权限（AppleEvent **-1743**） | `packaging.log:PACK_DMG_ROUTE_A/B=hdiutil_fallback` |
| 6 | **卸载脚本的危险输入** | `sourceFolderPath` 为空的路径**未被真实触发** | `07-04-PLAN.md` 中 `DISABLEBOTH=0` / `ROUTE_A=0` —— 键不存在，无法要求它跑 |
| 7 | **继承自 07-01 的缺口** | `fixtures/` 不在 worktree（gitignored），影响 `run-probe.sh app` 一组读数 | 07-01-SUMMARY「Issues Encountered」 |

### 🔴 继承自 Phase 6 的 5 项人工项（`07-VERDICT.md` 逐字登记，Phase 7 **未解除**）

1. **SC#3 的画质侧** —— `scripts/transcode-bench.sh` 的 SSIM/VMAF 实测**从未运行**（零 ffmpeg 红线）。参数侧 PASS ≠ 画质达标。阈值 SSIM≥0.98 / VMAF≥95 仍是 `[ASSUMED]` 行业经验值。
2. **转码窗的活体目视** —— 徽章文案、队列条目、命令展示是否成行（结构有断言，屏上像素无）。
3. **入口置灰 + 三途径弹层** —— 临时挪走 ffmpeg 可执行文件后打开设置窗验证（**须复原并重查**）。
4. **SC#2 的行为面** —— 队列串行 + 进度实时刷新 + 命令可审计展示，自动侧已过，**活体行为未验**。
5. **SC#4 的听音（W-33）** —— 变速后的保音高效果**无自动读数**。

### 本 Phase 的 5 条 SC 判定（逐字取自 `07-VERDICT.md`）

| SC | 判定 | 要点 |
|----|------|------|
| SC1 `build.sh` 一条命令跑完编译 → `.app` → DMG；零手工步骤，**重复执行结果一致** | **PASS-with-gap** | 一致性 PASS（二进制/plist md5 两遍逐字相同）；**缺口「用 `create-dmg` 主路」未做** |
| SC2 `test.sh` 一条命令跑完全部可自动化验证；全绿退 0，任一失败退非 0 | **PASS** | 通过 102 / 失败 0 / 跳过 1（跳过 = 7 天长跑，人工周期） |
| SC3 未签名 app 的开机自启有**实测结论**并落地 | **PARTIAL（机制面）/ PENDING-HUMAN（重启后）** | `ACTIVE_ROUTE=smappservice`（路线 A 成立）；**装版重启后自启是否真在位，从未验证** |
| SC4 压力验收：连续换片 50 次内存回基线 ±10%；**20 轮**休眠/唤醒/锁屏/解锁 100% 正确 | **PASS（前半）/ PENDING-HUMAN（后半）** | 前半 `STRESS_ADVANCES=100` / `RSS_DRIFT=-1.8%`；**后半人工轮次一条都没执行** |
| SC5 长跑验收：DMG 装出的 `.app` 连续运行 **≥7 天**不重启、不崩溃、内存无单调上涨 | **PENDING-HUMAN** | `soak.log` **空占位 0 字节**；`SOAK_VERDICT` **不存在** |

**5 项 PENDING-HUMAN 里没有一项被算成 PASS。**

---

## 全量复跑读数（2026-10-04 本机实测）

| 命令 | 读数 | Phase 7 当时读数 |
|------|------|----------------|
| `swift test` | `Executed 199 tests, with 0 failures` · exit 0 | — |
| `bash test.sh` | **通过 104 · 失败 0 · 跳过 1** · exit 0 | 通过 102 / 失败 0 / 跳过 1 |

**跳过的 1 项就是 7 天长跑**（`⏭️ 7 天长跑（人工周期，SOAK_VERDICT 未收口）`）。
它**既不算通过也不算失败** —— 这是本 Phase 最诚实的一个设计：
一个「还没跑但必须记着」的项目，在回归里显式占一行 skip，而不是悄悄消失。

---

## Validation Sign-Off

- [x] 所有 task 都有 `<automated>` verify（12/12）
- [x] 无连续 3 个 task 缺 automated verify
- [x] Wave 0 无 MISSING 引用 → `wave_0_complete: true`
- [x] 无 watch-mode 标志
- [x] 未覆盖项已逐条列出（7 项本 Phase + **5 项继承自 Phase 6**）
- [x] **已登记 3 条「不可能失败」的门**，并区分「有意的诚实设计」与「门禁设计缺口」
- [ ] **7 天长跑 = 人工周期，从未开跑**（`soak.log` 0 字节，`SOAK_VERDICT` 不存在）
- [ ] **把 frontmatter 的 `nyquist_compliant` 翻成 `true` —— 未达成。** 需先跑完 7 天 + 20 轮人工周期，再实跑 `/gsd-validate-phase`

**Approval:** pending —— `/gsd-validate-phase 7` 从未跑过
