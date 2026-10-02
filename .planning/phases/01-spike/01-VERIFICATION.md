---
phase: 01-spike
verified: 2026-10-03T04:20:00Z
status: human_needed
score: 8/9 must-haves verified
must_haves_verified: 8
must_haves_total: 9
behavior_unverified: 2
overrides_applied: 0
covered_digest: "v2:sha256:5952d47022a9a6633d2fd81530057a41"
covered_files:
  - .planning/phases/01-spike/01-01-PLAN.md
  - .planning/phases/01-spike/01-01-SUMMARY.md
  - .planning/phases/01-spike/01-02-PLAN.md
  - .planning/phases/01-spike/01-02-SUMMARY.md
  - .planning/phases/01-spike/01-03-PLAN.md
  - .planning/phases/01-spike/01-03-SUMMARY.md
  - .planning/phases/01-spike/01-04-PLAN.md
  - .planning/phases/01-spike/01-04-SUMMARY.md
  - .planning/phases/01-spike/01-05-PLAN.md
  - .planning/phases/01-spike/01-05-SUMMARY.md
  - .planning/phases/01-spike/01-CONTEXT.md
  - .planning/phases/01-spike/01-PDCA.md
  - .planning/phases/01-spike/01-VERDICT.md
  - .planning/spike/out/gate-01.log
  - .planning/spike/out/menubar.log
  - .planning/spike/out/task1-selftest.log
  - .planning/spike/out/task3-selftest.log
  - .planning/spike/out/fullscreen-scenarios.log
  - .planning/spike/out/ab-verdict.txt
  - .planning/spike/out/lock.log
  - .planning/spike/out/cgsession-keys.txt
  - .planning/spike/out/session-lockvalue.log
  - .planning/spike/powermetrics_ab.sh
  - .planning/spike/menubar-check.sh
  - test.sh
warnings:
  - id: W1
    severity: medium
    title: "「每条日志带 LOCK=1」与日志实际内容不符（VERDICT L134 + STATE.md L86）"
    detail: "实测 `grep -c '^LOCK='` 的逐文件结果：fullscreen-scenarios.log=5，gate-01.log=0，menubar.log=0，task1-selftest.log=0，task3-selftest.log=0，lock.log=0，ab-verdict.txt=0。承载 GATE=A 全部分量的 gate-01.log 不带任何会话锁标记。"
    not_material_because: "括号里的实质主张「本 Phase 全部测量都在锁屏会话内完成」经独立核实为真：loginwindow 当前仍在跑且 PID=489，与 ab-verdict.txt 记录的 SCREEN_LOCKED_CORROBORATION=loginwindow_pid_489 同 PID；session-lockvalue.log 9 次采样（19:24:45Z–19:25:25Z）CGSSessionScreenIsLocked 全为 1；锁定时刻 2026-10-02T17:26:17Z 早于全部采集窗口（gate 18:54Z–scenarios 19:43Z）。该句方向偏保守（多说了限制），不构成粉饰。"
    fix: "把两处的「（每条日志带 LOCK=1）」改为「（仅 fullscreen-scenarios.log 带 LOCK=1；gate-01.log / menubar.log 不带，锁屏状态由 ab-verdict.txt 的 loginwindow PID 与 session-lockvalue.log 反证）」。"
  - id: W2
    severity: low
    title: "ab-blocker-evidence.txt 被 VERDICT 引用但不在 git index"
    detail: "VERDICT L88「`ab-blocker-evidence.txt` 两条 rc=1」用的是裸文件名，没有 .planning/spike/out/ 前缀，因此逃过了 01-05-SUMMARY 声明的「8 条引用路径逐条查 git 索引」。实测 disk=ok repo=NO。"
    not_material_because: "同两条证据逐字复制在已入库的 ab-verdict.txt 里（AB_BLOCKER_EVIDENCE=sudo_-n_true_rc_1_msg_... 与 AB_BLOCKER_EVIDENCE=powermetrics_rc_1_msg_\"must be invoked as the superuser\"），引用链未断。"
    fix: "把该引用改成 `.planning/spike/out/ab-verdict.txt`（该文件同时含 out/ab-blocker-evidence.txt 这一指向行），或把裸文件 force-add 入库。"
  - id: W3
    severity: medium
    title: "menubar.log 的 menubarExtra=ok 是硬编码字面量，不是测量值"
    detail: ".planning/spike/MenuBarSpike.swift:45 与 MenuBarFallback.swift:38 写死 `menubarExtra=ok` / `menubarExtra=fallback`，无论 MenuBarExtra 是否真的工作都会打印 ok。"
    not_material_because: "menubar-check.sh:181 的 variant_pass() 只匹配 `policy=$EXPECT_POLICY ok=true`，不看 menubarExtra；VERDICT 全文也从未引用该字段（grep 命中 0）。SC3 的结论链（alive=1 / layer0=0 / policy=1 / 阳性对照 layer0=1）全部是真测量。"
    fix: "Phase 2 不得把 menubar.log 的 menubarExtra=ok 当作「菜单栏图标已确认渲染」的证据；该确认仍在 human_verification 清单第 4 项。"
  - id: W4
    severity: medium
    title: "SC4 的 PASS 是全文最软的一个标签"
    detail: "ROADMAP 点名的三个场景零个拿到真机样本：刘海屏=blocked（BLOCKED_REASON=toggleFullScreen_had_no_effect_while_session_locked）、Chrome=synthetic（no_google_chrome_installed）、超宽屏=synthetic（screens_count=1）。PDCA-C3 把同一条记为 🟡。SC4 的后半句「误判方向确认为『宁可少暂停，不要误暂停』」实际被证伪——实测方向是误暂停。"
    not_material_because: "VERDICT 未把任何 synthetic/blocked 说成实测：SC4 证据格逐条标 source（s0 live / s1 blocked / s2-s4 synthetic），「实测」二字只用在 S0 那个真 live 的假阳性上；已知障碍表另有 3 行专述这三个场景；硬约束 #2 把 FALSE_POSITIVE_OBSERVED=1 升级成 Phase 3 的强制项；ROADMAP Phase 2 Notes 已写入 PDCA-A2。下游无被误导风险。"
    fix: "可选：把 SC4 结论格改为「PARTIAL：0/3 指定场景有真机样本；误判方向实测为误暂停（非目标方向）」，与 PDCA-C3 的 🟡 对齐。"
  - id: W5
    severity: low
    title: "SC2 数字格引用的 WINDOW_LEVEL_REPORTED 实际在 gate-01.log，不在其证据格文件里"
    detail: "SC2 证据格指向 task1-selftest.log，数字格写「运行值 WINDOW_LEVEL_REPORTED=-2147483623」；该字段只存在于 gate-01.log，task1-selftest.log 里是 MODE_v1_GATE=... level=-2147483623 / PROBE_modes_SELF_LEVEL=。"
    not_material_because: "「层级写法定案」段已正确标注来源为 gate-01.log:SELF_LEVEL，且两处数值同为 -2147483623，无矛盾。"
  - id: W6
    severity: info
    title: "已知障碍表里的 BLOCKED_REASON 是前缀截断"
    detail: "VERDICT 写 BLOCKED_REASON=no_google_chrome_installed / =toggleFullScreen_had_no_effect_while_session_locked；日志原值后面还跟了 _scenarios=synthetic probe_path=... 与 max_observed_fullscreen=0 等字段。不是错引，但按前缀匹配会漏字段。"
  - id: W7
    severity: info
    title: "01-05-SUMMARY 的「8 条引用路径」实为 9 条"
    detail: "实测 `.planning/spike/out/` 前缀引用路径去重后 9 条（多出 task3-selftest.log 或 cgsession-keys.txt 之一类），9/9 全部 disk=ok repo=yes。SUMMARY 少数了一条，但方向是少报不是多报，不构成夸大。"
  - id: W8
    severity: info
    title: "仓库内有已入库的编译二进制，但都不是 Phase 1 产物"
    detail: "`.planning/spike/picspike` 与 `.planning/spike/render` 被 git 跟踪（`git ls-files` 可见），但来自 Phase 1 开工前的 d82cae1（10-03 00:42，UI 设置窗 spike）。Phase 1 自己产出的 out/* 二进制（fullscreenprobe / lockprobe / menubarspike / wallpaperspike / windowprobe / lockval / diag-locked-window）与全部 PNG 均未入库，符合「证据是日志、二进制不入库」的纪律（commit d507c8b / 84b1dd2 明确写了这条）。"
  - id: W9
    severity: info
    title: "阶段追踪未翻页"
    detail: "ROADMAP L17 仍是 `- [ ] Phase 1`；.planning/state.json 的 phases[0].status 仍是 \"pending\"，next.reason 仍是 \"executing\"。属流程记账，非 Goal 达成问题。"
behavior_unverified_items:
  - truth: "SC1 的 killall Finder 存活 + 层级序在有前台 GUI 进程的解锁会话中同样成立"
    test: "在解锁、有前台进程的状态下跑一次 `bash .planning/spike/run-gate.sh`，读 gate-01.log 的 ORDER / ORDER_AFTER / FINDER_RESTART_ALIVE 三个字段。"
    expected: "ORDER=ok、ORDER_AFTER=ok、FINDERER_RESTART_ALIVE=1，与锁屏会话下的既有值一致。不一致则门禁结论降级为「仅锁屏会话下成立」。"
    why_human: "本次复核不得重跑 run-gate.sh —— 它会 spawn GUI 进程、killall Finder、打断用户桌面；且前置条件（解锁会话）本身需要真人在场。已由 PDCA-A1 写进 ROADMAP Phase 2 作为第一个强制前置任务。"
  - truth: "SC3 的菜单栏图标确实出现在菜单栏、5 条菜单可点开"
    test: "跑 `bash .planning/spike/menubar-check.sh`，用眼睛看菜单栏图标并点开菜单。"
    expected: "菜单栏出现常驻图标且 Dock 无图标；点开后渲染出设置/暂停/退出等菜单项。"
    why_human: "menubar.log 自己写了 NOTE2=dock_absence_is_not_visually_confirmed_this_spike_makes_no_screenshot_claim；menubarExtra=ok 是硬编码字面量（W3），policy=1 + layer0=0 只是可自动核对的代理。本机无屏幕录制权限，无法用截图替代肉眼。"
human_verification:
  - test: "SC5 后半 —— 跑 `bash .planning/spike/powermetrics_ab.sh`（四组 × 300 秒，约 21 分钟），中途需输入 sudo 密码。"
    expected: "ab-verdict.txt 从 AB_STATUS=skipped 变为实测 OPAQUE_DELTA=<mW 数字>、AB_GROUPS_MEASURED=4。当前为 0。"
    why_human: "powermetrics must be invoked as the superuser；sudo -n true rc=1（无免密 sudo）。已在 ab-blocker-evidence.txt 与 ab-verdict.txt 留证。"
  - test: "SC5 前半 —— 真人手动锁屏保持约 10 秒再解锁，同时跑 LockProbe 观察跃迁。"
    expected: "com.apple.screenIsLocked 发出 locked/unlocked 之一，或明确不发。当前结论是 SCREENLOCK=unknown（探针跑满 120 秒但屏幕全程已锁，LOCKPROBE_DONE events=0）。"
    why_human: "制造 unlocked→locked 边沿需要真人操作物理屏幕；无人值守重试被明令禁止。"
  - test: "D-02 人工 10 秒 —— 确认桌面图标可点选、可拖动，且壁纸确实在图标后面。"
    expected: "点击与拖拽桌面图标完全正常，壁纸窗口始终在其后方。"
    why_human: "无任何自动信号能覆盖这个动作。CONTEXT D-02 与 ROADMAP 门禁验收方式均已拍板「事后补做，不阻塞 Phase 2」；VERDICT 已知障碍第 2 行已如实登记为不阻塞。"
  - test: "PDCA-A1 —— 在解锁会话重跑 run-gate.sh（同 behavior_unverified_items 第 1 项）。"
    expected: "见上。"
    why_human: "见上。已写进 ROADMAP Phase 2 的强制前置。"
---

# Phase 1 Verification: 桌面层级门禁 spike

**Phase Goal:** 用几小时的一次性 throwaway app 证明「视频待在桌面图标后面」这条路线在本机成立；证伪则整个架构作废，Phase 2–7 全部不启动。
**Verified:** 2026-10-03T04:20:00Z
**Status:** `human_needed`（Goal 已达成且无粉饰；SC5 与 4 项人工项待真人补做）

> **关于 status 取值的说明：** 派单里写「若 Goal 达成且无粉饰，`status: passed`，并把 SC5 与人工项列进 `human_needed` 明细」。本次取 `human_needed` 而非 `passed`，因为本 frontmatter 里有 6 项待真人条目（4 项 `human_verification` + 2 项 `behavior_unverified_items`），而 `passed` 的语义是「无需任何人工介入」—— 写 `passed` 会告诉下游「没有遗留人工工作」，与文件内容自相矛盾。Goal 达成与无粉饰这两个前提本身是成立的，结论没有任何打折；变的只是路由标记。
**Re-verification:** No — 首次独立复核
**复核性质:** 独立复核，不重跑 `run-gate.sh` / `menubar-check.sh` / `scenarios.sh`（会 spawn GUI、killall Finder、打断用户桌面）。所有数字核对到日志原文，测试只跑只读的 `bash test.sh`。

## 核心结论

**Goal 达成。** `GATE=A` 确由 `ORDER=ok ∧ FINDER_RESTART_ALIVE=1` 两个字段推出，判据是 01-05-PLAN.md L87-88 写死的（不是执行者事后自拟的），`gate-01.log` 里两个字段原值逐字对上。「门禁证伪 → 架构作废」分支未触发，Phase 2–7 可按原计划启动。

**没有把回放/合成数据说成实测。** 这是本次复核最重的一项检查，结论是干净的：全文没有任何一处把 synthetic 或 blocked 的数字表述为实测。T-01-13（"synthetic 数字被当成实测结论引用"）在 plan 里被显式建模，落地为 `source=synthetic|blocked|live` 标签加 `LIVE_COUNT=1 / SYNTHETIC_COUNT=3 / BLOCKED_COUNT=1` 三个计数，SC4 证据格逐条标 source，「实测」二字只用在 S0 那个真 live 的假阳性上。

**SC5 BLOCKED 被如实呈现，且是环境限制不是疏漏。** 证据格按 plan 要求只写「未采集 + 一句话原因」、零个路径，兜底产物引用下沉到 `SC5-注：` 脚注行（恰好 1 行）；已知障碍表另占两行。`powermetrics must be invoked as the superuser` 有原始 rc=1 输出留证。

**铁律 3/4 遵守到位。** 四栏口径小节标题逐字为 `跑过` / `没跑过` / `逻辑可行但本 Phase 未测` / `假定依赖`（L93/106/118/128，各恰好 1 行）；反形容词门实测返回 `0`。

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | SC1 层级方案成立 | ✓ VERIFIED | `gate-01.log`: `ORDER=ok` `ORDER_AFTER=ok` `SELF_LEVEL=-2147483623` < `ICON_LEVEL=-2147483603` `KILLALL_RC=0` `SPIKE_ALIVE=1` `FINDER_RESTART_ALIVE=1` `FRAME_FIRST=1`→`FRAME_LAST=225`。D-02 四条强证据取到 ①②④，③（截图）记 blocked，01-01-SUMMARY L150 的四格表也逐格标注 |
| 2 | SC2 层级写法定案 | ✓ VERIFIED | `task1-selftest.log`: `SOURCE_CGWindowLevelForKey_desktopWindow=1` / `SOURCE_hardcoded_-21474836=0` / `SOURCE_desktopIconWindow=0` / `COMPILE_RC=0 errors=0`；`gate-01.log: WINDOW_LEVEL_REPORTED=-2147483623`；VERDICT 禁用项表列 `.desktopIconWindow`。本次另跑 `bash test.sh` 独立复现：`desktopWindow = -2147483623`、`与图标层差 20`、`screenSaverWindow = 1000` 全绿 |
| 3 | SC3 菜单栏路线 | ✓ VERIFIED | `menubar.log`: `MENUBAR_VERDICT=ok`；`VARIANT=menubarspike alive=1 layer0=0`、`VARIANT=menubarfallback alive=1 layer0=0`；`VARIANT_PIC_MENU ... policy=1`；阳性对照 `CONTROL_REGULARWINDOW layer0=1`（证探测器非瞎）。判据代码 `menubar-check.sh:181 variant_pass()` 只匹配 `policy=<accessory> ok=true`，全是真测量（见 W3） |
| 4 | SC4 全屏几何原型 | ✓ VERIFIED (with W4) | `fullscreen-scenarios.log`: `SCENARIO_COUNT=5 LIVE_COUNT=1 SYNTHETIC_COUNT=3 BLOCKED_COUNT=1`；逐场景 coverage 1.000/0.886/1.000/1.000/0.840 与 VERDICT 逐字一致；`SELFTEST_VERDICT=pass`；`FALSE_POSITIVE_OBSERVED=1`（live）；`COORD=confirmed`。**误判方向实测为「误暂停」，与 SC4 想要确认的方向相反** —— VERDICT 硬约束 #2 已把它升级为 Phase 3 强制项，未淡化 |
| 5 | SC5 锁屏触发与耗电四组 | ✗ NOT MET (BLOCKED) · 已如实呈现 | `ab-verdict.txt`: `AB_STATUS=skipped` / `SCREENLOCK=unknown` / `OPAQUE_DELTA=SKIPPED=human_checkpoint` / `AB_GROUPS_PLANNED=4 AB_GROUPS_MEASURED=0`。两半皆零交付。硬约束证据 `powermetrics must be invoked as the superuser`（rc=1）。**这不是疏漏，是环境限制** → 走 human_verification，不计为 phase gap |
| 6 | `GATE=A` 由两个字段直接推出，无自由裁量 | ✓ VERIFIED | 判据写死于 `01-05-PLAN.md:87-88`（执行前即锁定）；`gate-01.log` 两字段原值 `ok` / `1` 逐字对上。VERDICT L24 另做了一次「删掉 SC5 整行重新判定仍为 A」的自洽声明 |
| 7 | 不得把 synthetic/blocked 说成实测 | ✓ VERIFIED | 模式扫描 `实测.{0,12}(synthetic\|回放\|合成)` 全文仅 2 命中，均为 plan 的要求句与 threat 描述本身，无一处违反。T-01-13 的落地机制（source 标签 + 三计数）在日志中齐备 |
| 8 | throwaway 纪律：产出全在 `.planning/spike/`，无产品脚手架 | ✓ VERIFIED | `Sources/` `Pic/` `Package.swift` `Pic.xcodeproj` 全部不存在。`git ls-files` 全表扫描，仓库内只有 `build.sh`（Phase 1 前的 dc450cc，00:47）+ `test.sh` + `tools/make-icons.swift` + `.planning/**`。Phase 1 自产的 out/* 二进制与全部 PNG 均未入库 |
| 9 | 铁律 3/4：四栏口径齐备、不用形容词留证 | ✓ VERIFIED | 四标题逐字命中 L93/106/118/128；反形容词门 `grep -v '^> ' … \| grep -cE '正常\|良好\|看起来\|没问题\|差不多\|应该能\|预计'` 实测 `0` |

**Score:** 8/9 truths verified. 1 truth (SC5) 未达成且属环境限制 → human_verification。

### 1/2 门禁推导链（问题①的直接回答）

`01-05-PLAN.md:87-88` 在执行前就把判据写死为 `GATE=A ← gate-01.log 里 ORDER=ok 且 FINDER_RESTART_ALIVE=1`，L93 另加硬约束「判据**只**看这两个字段，与 SC5 无关」。VERDICT L13-15 逐字复现该布尔式，两字段原值 `ok` / `1` 与 `gate-01.log` 完全一致。**推导链成立，且判据非事后自拟** —— 这点很重要，它排除了「为让门禁通过而事后放宽判据」的可能。

需要指出的是：判据只编码了 D-02 四条强证据的 ②④，①（level 严格低于）虽成立但不在布尔式里，③（截图）因无屏幕录制权限未取到。这是 plan 定的口径，VERDICT 未隐瞒（D-02 四条取到 ①②④ 在「跑过」表与已知障碍表各写一次）。

### 2 证据引用完整性（问题②的直接回答）

VERDICT 引用的全部 `.planning/spike/out/` 前缀路径 **9 条，逐条 `ls` + `git ls-files` 双查，9/9 disk=ok repo=yes**：

```
ab-verdict.txt  cgsession-keys.txt  fullscreen-scenarios.log  gate-01.log
lock.log  menubar.log  session-lockvalue.log  task1-selftest.log  task3-selftest.log
```

字段级核对：SC1/SC2/SC3/SC4/SC5/D-08/硬约束三节引用的每一个字段名，逐个 `grep` 回日志，**全部命中且值一致**（含 `FRAME_FIRST=1 → FRAME_LAST=225`、`ACTIVATION_POLICY_RAW regular=0 accessory=1 prohibited=2`、`D08_ROUTE_C_FRAMEWORK_TOTAL=5` 等细节）。

两处例外见 W2（`ab-blocker-evidence.txt` 裸名引用未入库）与 W6（BLOCKED_REASON 前缀截断），均不破坏引用链。

### 3 VERDICT 有没有夸大（问题③的直接回答）

**没有。** 三项逐一查过：

- **合成数据当实测**：无。`SCENARIO_MATRIX=s0=live s1=blocked s2=synthetic s3=synthetic s4=synthetic` 在日志里，SC4 证据格逐条标 source，已知障碍表另有 3 行专述这三个场景并写明「记 synthetic，不记 live」「记 blocked」。
- **SC5 BLOCKED**：如实呈现，且呈现方式比 plan 要求更严（证据格零路径、引用下沉脚注）。
- **`FALSE_POSITIVE_OBSERVED=1`**：不但没淡化，还被列为**「本 Phase 最有后果的一条」**、升级为交给下游的硬约束 #2，并在 ROADMAP Phase 2 Notes 里落成 PDCA-A2（含 pid 1227 / 1228、1470×833 vs frame 高 956、coverage 已顶在 1.000 上限所以调阈值无用等完整论证）。

唯一偏软的是 SC4 那个孤零零的 `PASS` 记号（W4）—— 0/3 指定场景有真机样本，且 SC4 后半句的方向被证伪。但因全部数字都带 source 标签、且约束已升级到 Phase 2/3，下游不存在被误导的路径。

### 4 锁屏会话前提（问题④的直接回答）

**C1 成立，且比 PDCA 说的更硬。** 独立复核结果：

| 证据 | 实测 |
|---|---|
| `loginwindow` 进程 | **仍在跑，PID=489** —— 与 `ab-verdict.txt` 里 `SCREEN_LOCKED_CORROBORATION=loginwindow_pid_489_UserIsActive_0` 同 PID，说明自采集起会话**从未解锁过** |
| `session-lockvalue.log` | 9 次采样（19:24:45Z–19:25:25Z）`CGSSessionScreenIsLocked=1` 全 1，`CGSSessionScreenLockedTime=1790961977` 恒定 |
| 锁定时刻 vs 采集窗口 | 锁定 `2026-10-02T17:26:17Z`；gate 采集 ~18:54Z，scenarios 19:43Z —— **全部在锁后** |
| 当前屏幕数 | `system_profiler` 计数 = 1，与 `no_ultrawide_display_attached_screens_count=1` 一致 |

**VERDICT 确实承认了这一条**：L134「假定依赖」第 3 行 ——「`CGWindowListCopyWindowInfo` 在无 GUI 前台会话下的行为 / 本 Phase 全部测量都在锁屏会话内完成 / **有前台进程时的窗口列表行为未验证**」，并已由 PDCA-A1 写进 ROADMAP Phase 2 作为**第一个强制前置任务**（不通过则门禁结论降级为「仅锁屏会话下成立」）。

⚠️ 但该行的括号「（每条日志带 `LOCK=1`）」**与日志实际内容不符**（W1）：实测只有 `fullscreen-scenarios.log` 带 `LOCK=`（5 次），承载 GATE=A 全部分量的 `gate-01.log`、`menubar.log`、`task1-selftest.log`、`task3-selftest.log`、`lock.log`、`ab-verdict.txt` **全部为 0**。实质主张为真（见上表），但它把一条不存在的证据链写成了存在，且同一句话在 `STATE.md:86` 又抄了一遍。这是本次复核发现的**唯一一处 VERDICT 与日志的字面不一致**。方向偏保守（多说了限制），不构成粉饰，判定为 WARNING 而非 BLOCKER —— 但建议改掉，因为一份专门讲可复核性的文件里，夸大战内证据的自证力是它最不该犯的错。

### 5 test.sh（问题⑤的直接回答）

本次**实跑** `bash test.sh`：**通过 15 失败 0**，与 VERDICT L104/L151 的声明逐字一致。逐项点数也对：工具链 3 + 编译 1 + 关键 API 5 + 运行时值 3 + spike 门禁探针 2 + 渲染 1 = 15。

**副作用审查**：新增的「spike 门禁探针」段两条 probe 均为纯 `swiftc -typecheck`，写入 `$TMP` 临时文件；渲染段产物写 `$TMP/out.png`，`trap` 退出时清理。全脚本无 `sudo` / `screencapture` / `killall` / GUI 脚本名。按 T-01-16 的验收命令实测：

```
sed -n '/spike 门禁探针/,/── 渲染/p' test.sh | grep -cE 'sudo|screencapture|run-gate|menubar-check|scenarios\.sh|powermetrics|killall'   →  0
```

**反形容词门实测返回 0**，无新增探针引入副作用。

## Requirements Coverage

本 Phase `requirements: []` —— 门禁阶段不交付 v1 需求（ROADMAP 明写：「无 —— 门禁阶段不交付 v1 需求」）。**这不是缺口**，验收锚点是 ROADMAP 的 5 条 Success Criteria，已在 Goal Achievement 表逐条判定。不报 BLOCKER。

## Security Gate

`security_enforcement=true`、`security_asvs_level=1`、`security_block_on=high`。5 个 plan 各有 `<threat_model>`，共 18 条 threat（T/E/I/R 四类齐备）。按要求核对 spike 的 4 项真实风险是否覆盖到位，**未凑数造 threat**：

| 真实风险 | Threat | 处置 |
|---|---|---|
| 改系统设置 | T-01-04（激活策略/Info.plist，accept，理由=不组装 .app bundle 不写 Info.plist）、T-01-01（禁 `UserDefaults` / `defaults write` / `NSWorkspace.open` / 任何 `/Library`） | 覆盖 |
| killall Finder 打断工作 | T-01-02（DoS，medium，mitigate：执行前 stderr 打 `WARN=will_restart_Finder`，只 kill 不 `open`） | 覆盖 |
| sudo 提权（唯一 high） | T-01-08（**本 Phase 唯一 high**，mitigate：**绝不用 `sudo bash` 跑整个脚本**，只对 powermetrics 单次调用提权，脚本本身不以 root 运行） | 覆盖 |
| 截图泄露窗口标题 | T-01-03 / T-01-06（禁输出 `kCGWindowName`）/ T-01-17（VERDICT 只引用结论字段不带敏感元数据） | 覆盖 |

额外两条与本次复核直接相关、且已被验证落地的：
- **T-01-13**「synthetic 数字被当成实测结论引用」—— 落地机制（`source=` 标签 + `LIVE/SYNTHETIC/BLOCKED_COUNT`）在 `fullscreen-scenarios.log` 中齐备，本次逐条核对通过。
- **T-01-16**「test.sh 被塞进有副作用的探针」—— 本次实跑该验收命令，返回 0。

**安全门通过。**

## Scope Discipline

| 检查 | 结果 |
|---|---|
| 无产品目录结构 | ✓ `Sources/` `Pic/` `Package.swift` `Pic.xcodeproj` 均不存在 |
| 产出全在 `.planning/spike/` | ✓ 5 个脚本 + 7 个 Swift 源 + out/ 日志，全在该目录下 |
| 编译二进制未入库 | ✓ Phase 1 自产的 out/* 二进制全部未入库；仓库内仅 `picspike` / `render` 两个已入库二进制，来自 Phase 1 开工前的 d82cae1（W8） |
| **D-02** 桌面图标可点选不得作阻塞验收 | ✓ VERDICT L82「事后补做，不阻塞（D-02 已定）」，已知障碍表「是否阻塞=否」；SC1 行也明写「人工 10 秒项未做」 |
| **D-09** 不跑 research-phase | ✓ `.planning/research/` 最后一次提交 00:43，Phase 1 计划创建于 01:32，执行期（01:32–03:54）零 research 提交 |
| 铁律 3/4 不美化进度 | ✓ 四栏口径齐备（标题逐字命中）；反形容词门 0；SC5 BLOCKED 未被包装成 PASS |

## Anti-Patterns Found

对 Phase 1 涉及的脚本与 Swift 源做 stub 扫描，发现 **1 处硬编码字面量**，已记为 W3，**不构成任何 VERDICT 结论的支撑**：

```
.planning/spike/MenuBarSpike.swift:45      print("PIC_MENU policy=\(policy) ok=\(ok) menubarExtra=ok dock=hidden_by_policy")
.planning/spike/MenuBarFallback.swift:38   print("PIC_MENU policy=\(policy) ok=\(ok) menubarExtra=fallback dock=hidden_by_policy")
```

`menubarExtra=ok` / `=fallback` 无条件打印 `ok`，不是测量值。同行的 `policy=\(policy)`（`setActivationPolicy` 后的 `rawValue` 回读）与 `ok=\(ok)`（其返回值）是真测量，且 `menubar-check.sh:181` 的判据只认这两个。VERDICT 全文未引用 `menubarExtra`（grep 命中 0），SC3 结论链不受污染。**但它是一个 Phase 2 的陷阱**：谁要是从日志里读到 `menubarExtra=ok` 就以为菜单栏图标已验证，会踩空。

其余扫描（`return null` / `TODO` / `FIXME` / `XXX` / `= []` / `= {}` / console.log-only / empty handler）**在 Phase 1 的脚本与 Swift 源中零命中**。证据文件中未发现任何债务标记（`TBD` / `FIXME` / `XXX`）。

## Warnings Summary

共 9 条，全部为 WARNING 级，均不阻塞 Goal。完整内容见 frontmatter `warnings:` 块。

- **W1（medium）** 「每条日志带 LOCK=1」与日志实际内容不符 —— 唯一一处 VERDICT 与日志的字面不一致。实质主张为真，但自证力被夸大，且同样的句子在 `STATE.md:86` 抄了一遍。**建议修**。
- **W3（medium）** `menubarExtra=ok` 是硬编码字面量，不支撑任何结论，但会被 Phase 2 误读。
- **W4（medium）** SC4 的 `PASS` 是全文最软标签（0/3 指定场景有真机样本；方向被证伪）。因全部数据带 source 标签 + 约束已升级至 Phase 2/3，下游无误导风险。
- W2 / W5 / W7（low）引用精度类问题，均不破坏引用链。
- W6 / W8 / W9（info）前缀截断、Phase 1 前遗留二进制、阶段追踪未翻页。

## Human Verification Required

4 项，全部已由 VERDICT / PDCA / ROADMAP 如实登记为不阻塞或已派给下游：

1. **SC5 后半 —— `powermetrics` 四组 300 秒 A/B**（约 21 分钟，需输入 sudo 密码）
   - 期望：`AB_GROUPS_MEASURED` 从 0 变 4，`OPAQUE_DELTA` 出一个 mW 数字
   - 为何需人：硬约束 `powermetrics must be invoked as the superuser`，`sudo -n true` rc=1
2. **SC5 前半 —— 真人手动锁屏 10 秒再解锁**（观察 `screenIsLocked` 跃迁）
   - 期望：`fires` 或 `silent` 二选一；当前是 `SCREENLOCK=unknown`
   - 为何需人：制造跃迁边沿必须真人操作物理屏幕，无人值守重试被明令禁止
3. **D-02 人工 10 秒 —— 确认桌面图标可点选、可拖动**
   - 期望：点击与拖拽完全正常，壁纸确实在图标后面
   - 为何需人：无自动信号覆盖；D-02 已拍板事后补做不阻塞
4. **菜单栏图标肉眼确认 + 5 条菜单渲染**
   - 期望：菜单栏出现常驻图标、Dock 无图标、点开后菜单渲染
   - 为何需人：`menubar.log` 自带 `NOTE2=dock_absence_is_not_visually_confirmed_this_spike_makes_no_screenshot_claim`；`menubarExtra=ok` 是硬编码（W3）

另有 2 项已升级为 `behavior_unverified_items`，其中 **PDCA-A1（解锁会话重跑 `run-gate.sh`）已写进 ROADMAP Phase 2 作为第一个强制前置任务**，不在本 Phase 遗留。

## Gaps Summary

**无 gaps。** Goal「证明路线 A 在本机成立」已达成，`GATE=A` 推导链成立且判据执行前即写死；未发现任何一处把回放/合成数据说成实测；`01-VERDICT.md` 与 `gate-01.log` / `menubar.log` / `task1-selftest.log` / `fullscreen-scenarios.log` / `ab-verdict.txt` / `lock.log` 逐字段一致；9 条引用证据路径 9/9 在库。

SC5 未达成，但属**预先授权的环境限制**（`powermetrics` 需 root），非执行疏漏，且按 plan 要求以最严格的方式呈现（证据格零路径、引用下沉脚注、已知障碍表两行）。按 ROADMAP「无法解决的跳过」口径登记并转人工，不计为 phase gap。

9 条 WARNING 见上，其中 W1 建议修（一条文档级不实陈述），W3 / W4 建议在 Phase 2 开工前知会下游。

---

_Verified: 2026-10-03T04:20:00Z_
_Verifier: Claude (gsd-verifier) · 独立复核，未重跑任何 GUI 脚本_
