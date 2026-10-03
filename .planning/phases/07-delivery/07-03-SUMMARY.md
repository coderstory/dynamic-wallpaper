---
phase: 07-delivery
plan: 03
subsystem: infra
tags: [launchd, soak-test, awk, macos, evidence]

requires:
  - phase: 07-delivery
    provides: "07-01 图标资产（ASSET-03 判为视觉判据、无自动门）、07-02 开机自启 user_setup（重启项与本清单互指）"
provides:
  - "scripts/soak-sampler.sh —— 单次采样，一行 11 个 key=value，SOAK_DIR/SOAK_PID 全程可注入"
  - "scripts/soak-agent.sh —— com.local.pic.soak 的 bootstrap/bootout 装卸，plist 四键无 KeepAlive"
  - "scripts/soak-analyze.sh —— 线性拟合判据，判词四态（pass/fail/invalid/insufficient）"
  - ".planning/phases/07-delivery/UAT-SOAK.md —— 7 天人工周期的一页可执行清单"
  - ".planning/phases/07-delivery/evidence/soak/ —— 真实 7 天数据的落点（空占位）"
affects: [07-delivery, SC5, PACK-04, ASSET-03]

actuals:
  tokens: 10000
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "长跑证据自检：缺口 >5% 判 invalid 作废，而不是降级继续"
    - "采样器调度交给 launchd StartInterval，不自写常驻循环；采样器死亡由缺口判据兜住"
    - "判定序 invalid → insufficient → fail → pass，「数据不算数」的形态优先于「数据不好看」"

key-files:
  created:
    - scripts/soak-sampler.sh
    - scripts/soak-agent.sh
    - scripts/soak-analyze.sh
    - .planning/phases/07-delivery/UAT-SOAK.md
  modified: []

key-decisions:
  - "plist 不用 KeepAlive：一次性脚本 + KeepAlive = 紧循环烤机。逐时唤醒是 StartInterval=3600 的职责，采样器真死了由「缺口 >5% 作废」兜住，不靠自保活"
  - "崩溃/睡眠/唤醒在 app 缺席（missing=1）的样本里照常读：它们是全局计数器，与 Pic 在不在场无关，填 0 等于往日志里写一个假的零测量，CRASH_DELTA 会据此判出一个并不存在的崩溃"
  - "invalid 必须最先判：缺口 >5% 判 invalid 而不是 insufficient ——「跑挂了却在假装跑」比「样本不够」严重得多"
  - "缺失样本里锁屏/电池等系统级读数不填 0（只填 PID 作用域的 rss/vsz/fd/alive）：会话态与全局态在 app 缺席时依然可测，填 0 会让分析器把锁屏当故障"

patterns-established:
  - "一行一事实一键（D-17）：采样行与分析器的每一行输出都是 key=value，判据全是数字，不出现形容词"
  - "常驻执行面的 plist 由代码常量生成，路径从脚本自身位置推导，stop 后 plist 与加载态双清零"

requirements-completed: [PACK-04]

coverage:
  - id: D1
    description: "采样器产出完整 11 键读数行，missing 分支留痕不静默；launchd StartInterval=3600 逐时唤醒、stop 后系统无残留"
    requirement: PACK-04
    verification:
      - kind: other
        ref: "T1 <automated>: injected SOAK_DIR/SOAK_PID 采样 + bootstrap/print/lint/bootout 序列 → SOAK_SAMPLER_OK"
        status: pass
    human_judgment: false
  - id: D2
    description: "分析器判据五方向自证：healthy=pass / growth=fail / gap=invalid / dead=fail / short=insufficient，判词不混串"
    verification:
      - kind: other
        ref: "T2 <automated>: 五份合成 soak.log 逐个分析 → SOAK_ANALYZER_OK"
        status: pass
    human_judgment: false
  - id: D3
    description: "人工周期有一页可执行清单：前置、7 天规则、20+20 轮与电池/深浅色/重启自启、结束动作、异常处置"
    verification:
      - kind: other
        ref: "T3 <automated>: UAT-SOAK.md 六小节 + 量化预期 + ASSET-03 并排项 + TCC 排查项 → UAT_SOAK_DOC_OK"
        status: pass
    human_judgment: false
  - id: D4
    description: "7 天真机在位长跑本身的验收结论（SOAK_VERDICT=pass + 20+20 轮肉眼结果）"
    verification: []
    human_judgment: true
    rationale: "7 天连续运行、锁屏/解锁、休眠/唤醒、电池让路、深浅色可见性、图标并排肉眼比对，全部依赖真人操作与肉眼判读，executor 无法代跑也无法代判"

# Metrics
duration: 11min
completed: 2026-10-03
status: complete
---

# Phase 7 Plan 03: SC5 长跑脚手架（launchd 采样器 + 分析器 + UAT-SOAK 人工清单） Summary

**每小时 launchd 采样 + 纯 awk 线性拟合判据（斜率/漂移/fd/崩溃/缺口）+ 7 天人工周期的一页清单；判据在见到真实数据之前已用五方向合成数据自证有牙齿**

## Performance

- **Duration:** 11 min
- **Started:** 2026-10-03T18:00:00Z
- **Completed:** 2026-10-03T18:11:30Z
- **Tasks:** 3
- **Files modified:** 5

## Accomplishments

- `soak-sampler.sh` 单次采样一行 11 键；`missing=1` 分支留痕不静默（app 死在 7 天里不会无声消失）
- `soak-agent.sh` 用 bootstrap/bootout 装卸 LaunchAgent，plist 四键无 KeepAlive，stop 后加载态与 plist 双清零
- `soak-analyze.sh` 把 RSS/fd 对时间做最小二乘拟合，输出全部数字化，判词四态；五份合成数据各命中预期判词，判词不混串
- `UAT-SOAK.md` 把 7 天人工周期落成一页清单，含 ASSET-03 图标并排肉眼比对与 alive 连续 0 的采样器侧前置排查纪律

## Task Commits

Each task was committed atomically:

1. **Task 1: soak-sampler.sh 单次采样 + soak-agent.sh launchd 装卸** - `0edc57d` (feat)
2. **Task 2: soak-analyze.sh 线性拟合判据，合成数据五方向自证** - `554c950` (feat)
3. **Task 3: UAT-SOAK.md 人工清单 + evidence/soak/ 就位** - `8227748` (docs)

## Files Created/Modified

- `scripts/soak-sampler.sh` - 单次采样，读数追加进 `soak.log`
- `scripts/soak-agent.sh` - LaunchAgent `com.local.pic.soak` 的 start/stop/status
- `scripts/soak-analyze.sh` - 连续性 / 斜率 / 漂移 / fd / 崩溃 / missing 判定
- `.planning/phases/07-delivery/UAT-SOAK.md` - 人工周期一页清单
- `.planning/phases/07-delivery/evidence/soak/soak.log` - 空占位，真实数据由人工周期填入

## Decisions Made

- **plist 无 KeepAlive**（plan 必定的修正）：StartInterval=3600 已保证逐时唤醒；KeepAlive 配一次性脚本 = 跑完立刻被拉起 = 紧循环烤机。采样器死亡由「缺口 >5% 作废」兜住，而不是靠保活掩盖。
- **缺失样本里的全局计数器照常读**（plan 未规定，按数据真实性定）：`crashes`/`sleeps`/`wakes`/`batt`/`locked` 是全局或会话级读数，与 Pic 在不在场无关。填 0 等于往日志里写一个假的零测量 —— `CRASH_DELTA` 会据此判出一个并不存在的崩溃。只有 PID 作用域的 `rss`/`vsz`/`fd`/`alive` 在 app 缺席时无法测得，填 0 并以 `missing=1` 标记。
- **判定序 invalid 先于 insufficient**：plan 已定「invalid 必须最先判」，实现照此。实测证明这条序有意义 —— gap 序列（11 行跨 24 小时）先撞 `n < 24` 会判 insufficient，而它真正的问题是「跑挂了却在假装跑」。

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] fd 斜率算式误用 RSS 求和**
- **Found during:** Task 2 (首次跑 healthy 合成数据)
- **Issue:** 最小二乘里 fd 斜率的分子用了 `st*sf`（RSS 的和）而非 fd 的和，`FD_SLOPE_PER_DAY` 打出 `-25081387421.11` 这种量级荒谬的值 —— 而判据是「>24 判 fail」，一个巨大的**负**数恰好躲过阈值，fd 泄漏会静默通过。
- **Fix:** 分开累加 `sr`（rss 和）与 `sf`（fd 和），fd 分子改用 `st*sf`。顺带把漂移判定改用已算好的 `drift` 变量，避免重复计算与除零。
- **Files modified:** `scripts/soak-analyze.sh`
- **Verification:** healthy 修正后 `FD_SLOPE_PER_DAY=0.33`（fd 50±1 的噪声量级）；变异抬高斜率阈值后 growth 仍被漂移判据独立兜住
- **Committed in:** `554c950` (part of task commit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** 修正的是判据本身的算式错误，不改设计、不扩范围。

## Issues Encountered

- **执行环境处于锁屏态**（`locked=1`），采样器两次截图因此都为空 → `alive=0`。这是预期形态（UAT-SOAK 已写明 `locked=1` 时的 `alive=0` 交给分析器区分），但它同时意味着 T1 的 TDD 验证没有真正走通「画面在变 → alive=1」这条路径。该路径的真实性依赖真机 7 天人工周期，如实登记为未实测。
- **plan 的 `<automated>` 命令里写死了 `cd /Users/coderstory/dev/pic`**（主 checkout）。本 executor 在隔离 worktree 里执行，按 worktree 路径安全规程（step 0c）改为在 worktree 根跑同一命令序列，判据内容未改。

## User Setup Required

**7 天在位是人工周期，executor 只交付脚手架与判据。** 执行入口见
`.planning/phases/07-delivery/UAT-SOAK.md`：

- 前置：`bash build.sh` → 从 `dist/Pic-0.1.0.dmg` 装 Pic.app 到 /Applications 并启动
- `bash scripts/soak-agent.sh start`，确认 `launchctl print gui/$(id -u)/com.local.pic.soak` 退出 0
- 7 天内按 UAT-SOAK.md 完成人工轮次（20 轮锁屏/解锁 + 20 轮休眠/唤醒、电池让路一次、深浅色肉眼确认、图标并排比对）
- 结束：`bash scripts/soak-agent.sh stop && bash scripts/soak-analyze.sh .planning/phases/07-delivery/evidence/soak/soak.log`，结果抄进 `evidence/soak/FINAL.md`
- 与 07-02 的重启自启项互指，两项一起做，只重启一次机器

**预期成本**：机器在位 7 天 + 人工轮次合计约 40 分钟。

## What Was NOT Run（诚实基线）

- **7 天长跑本体未跑** —— 人工周期，非 executor 职责。`SOAK_VERDICT=pass` 目前**没有**真实数据支撑，只有合成数据支撑判据本身。
- **`alive=1` 这条路径未实测** —— 执行环境锁屏，见 Issues Encountered。
- **launchd 逐时唤醒（StartInterval 真正跑满一小时）未实测** —— 只验证了 bootstrap 生效、print 可查、bootout 清干净；没有等待一个完整周期验证第二次采样由 launchd 发起。
- **非锁屏态下 `screencapture` 的 TCC 行为未实测** —— launchd 拉起的进程是否继承屏幕录制授权，正是 UAT-SOAK 异常处置里要求人工复现的那一条。

## Verification Results

| 检查 | 结果 |
|---|---|
| T1 采样器 11 键行（注入 SOAK_DIR/SOAK_PID） | PASS — `LINE1_OK=1` |
| T1 缺失 PID → `missing=1` 留痕 | PASS — `MISSING_LINES>=1` |
| T1 start 后 launchctl print / plutil -lint / KeepAlive=0 / StartInterval>=1 | PASS — rc=0 / OK / 0 / 1 |
| T1 stop 后加载态与 plist 双清零 | PASS — `PRINT_AFTER_STOP_RC=113`、plist absent |
| T1 两脚本零 `launchctl load/unload` | PASS — 0 / 0 |
| T1 默认 SOAK_DIR 未被 RunAtLoad 污染 | PASS — `REAL_SOAK_DIR_LINES=0` |
| T2 五方向判词 | PASS — healthy=pass / growth=fail / gap=invalid / dead=fail / short=insufficient |
| T2 healthy 斜率 <1.0、CRASH_DELTA=0、cont=ok | PASS — 0.07 / 0 / ok |
| T2 变异反向验证判据有牙齿 | PASS — 放宽缺口阈值 → gap 不再 invalid；去掉 missing 分支 → dead 判 pass |
| T3 UAT-SOAK 六小节 + 命令拼法 + 四个量化预期 | PASS — sections=9、全部计数 >=1 |
| T3 ASSET-03 并排项 + TCC 排查项 | PASS — appicon/menubar/sidebyside/tcc 均 >=1 |
| T3 evidence/soak/ 目录就位 | PASS |
| swift test 全绿（190 基线） | PASS — Executed 190 tests, 2 skipped, 0 failures |

## Next Phase Readiness

- SC5 的自动化半边就绪：判据全部数字化且已自证有牙齿，7 天数据一到就能直接出结论
- 自动化侧无未完项；剩余全部集中在人工周期（见 User Setup Required 与 What Was NOT Run）
- 与 07-02 零文件重叠，同 wave 并行安全；与本 plan 零产品源码改动

---
*Phase: 07-delivery*
*Completed: 2026-10-03*