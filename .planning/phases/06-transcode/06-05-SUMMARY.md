---
phase: 06-transcode
plan: 05
subsystem: infra
tags: [ffmpeg, transcode, assembly, gate, verdict]

requires:
  - phase: 04-media-library
    provides: MediaLibrary 扫描缓存语义 + PlaybackRouter 装载分派（D-21 Converted/ 全排除）
  - phase: 06-transcode (06-01/03/04)
    provides: ConvertedLibrary / TranscodeQueue.onBatchFinished / 转码窗与 ffmpeg 判定入口
provides:
  - AppDelegate 的播放清单合并入口（D-23 落地）：router.start 两处调用点统一吃「root items + Converted items 去重」
  - 转码排空钩子：onBatchFinished → invalidateCache() → rescanAndApply()（SC#5 的 app 级闭环）
  - scripts/transcode-bench.sh —— C7 的手动 SSIM/VMAF 实测入口（MANUAL ONLY，-t 5 -threads 2）
  - test.sh 的 Phase 6 段 16 条纯逻辑门 + ffmpeg 红线拆串门（工具段 ffmpeg -version 调用移除）
  - 06-VERDICT.md 五条 SC 诚实判定 + GPL Blocker 关闭 + 人工清单四项 + A1–A9 假定表
  - W-2026-10-03-34（D-23 裁决入册）
affects: [07-packaging, transcode, playback, gating]

actuals:
  tokens: 24100
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "红线门用拆串构造自防自匹配：模式在文件里以 \"a\"\"b\" 两段字面存在，bash 拼接后才成目标串"
    - "判据只读已入库 evidence，不重跑探针（Phase 4 p4_line 纪律的延续）"

key-files:
  created:
    - scripts/transcode-bench.sh
    - .planning/phases/06-transcode/06-VERDICT.md
  modified:
    - Sources/PicApp/AppDelegate.swift
    - test.sh
    - .planning/WINDOWS.md

key-decisions:
  - "D-23 落地：产物仍留 Converted/（D-21 不动），ConvertedLibrary 作播放第二入口，合并发生在 router.start 调用点 —— 不动 04-01 的全排除契约"
  - "dispatchPlayback 的入参由 [VideoItem] 改为 MediaLibraryReport? —— 只换 .playing 分支的数据来源，分派结构一个分支没动"
  - "transcodeQueue.onBatchFinished 挂在 lazy var 的构造闭包内（唯一建队列处），不是 bootstrapAfterWiring —— 漏挂的表象是「转完了但清单里没新片」且不报错"
  - "test.sh 不重跑 transcode 探针，只读已入库 evidence 的四行"

patterns-established:
  - "拆串红线门：判据模式在源文件里写成 \"transcode\"\"-bench\"，joined 字面计数恒为 0；变异插入 joined 字面两条计数同时转 1"
  - "no() 文案带 ok() 的同一句判据名（D-14），本段全部照此写"

requirements-completed: [TRANS-03, TRANS-04, TRANS-05, TRANS-06]

coverage:
  - id: D1
    description: "router.start 的两个调用点统一吃 Converted 合并清单（D-23 落地）"
    requirement: TRANS-05
    verification:
      - kind: unit
        ref: "Tests/PicCoreTests/ConvertedLibraryTests.swift —— playbackItems(root:converted:) 去重与排序"
        status: pass
      - kind: other
        ref: "bash test.sh —— 「播放清单走 Converted 合并入口（SC#5）」剥注释后 mergedPlaybackItems 计数 ≥ 2"
        status: pass
      - kind: other
        ref: "grep 裸形态 —— AppDelegate.swift 剥注释后 'router.start(with: report.items)' 计数 = 0"
        status: pass
    human_judgment: false
  - id: D2
    description: "转码排空后 invalidateCache → rescanAndApply，新产物当轮进播放轮换"
    requirement: TRANS-05
    verification:
      - kind: unit
        ref: "swift test 全量 —— 190 tests, 2 skipped, 0 failures"
        status: pass
      - kind: other
        ref: "bash test.sh —— 「转码排空钩子已装配」onBatchFinished ≥ 1、「排空后显式失效扫描缓存」invalidateCache ≥ 1"
        status: pass
      - kind: other
        ref: "行号序判据 —— handleTranscodeBatchFinished 的 invalidateCache 行 334 < rescanAndApply 行 336"
        status: pass
    human_judgment: true
    rationale: "代码装配与顺序已被机器判据锁死，但「排空后 UI 上真的多了一个新片」是活体行为，本会话未开转码窗转码过任何文件"
  - id: D3
    description: "手动 bench 脚本就位（C7 的 SSIM/VMAF 实测流程）"
    requirement: TRANS-04
    verification:
      - kind: other
        ref: "bash -n scripts/transcode-bench.sh —— SYNTAX_RC=0；MANUAL ONLY / -t 5 / -threads 2 / head -n 3 / 16 18 20 / medium slow / libvmaf / BENCH_PROGRESS_RAW / rosetta / baselineCRF 十项计数全 ≥ 1，find 计数 0，test.sh 非注释提及恰好 1"
        status: pass
    human_judgment: true
    rationale: "只过了语法与结构门。ffmpeg 调用、SSIM/VMAF 解析、BENCH_RECOMMEND 的判定一行都没执行过 —— 用户红线禁止自动化跑，且跑前需向用户确认 CPU 占用"
  - id: D4
    description: "test.sh Phase 6 段 16 条纯逻辑门 + ffmpeg 红线拆串门；工具段零 ffmpeg 进程调用"
    requirement: TRANS-04
    verification:
      - kind: other
        ref: "bash test.sh —— 全量 RC=0，通过 79 / 失败 0 / 跳过 5（基线 63，+16）"
        status: pass
      - kind: other
        ref: "拆串红线门变异 —— 插入 joined 字面后 bench 引用与编码形态计数同时转 1（判据非空）"
        status: pass
      - kind: unit
        ref: "swift test --filter 'Transcode|ConvertedLibrary|ExternalToolLocator|ProgressParser' —— Executed 40 tests, with 0 failures"
        status: pass
    human_judgment: false
  - id: D5
    description: "06-VERDICT.md：五条 SC 诚实判定 + GPL Blocker 关闭 + 人工清单四项 + A1–A9 假定表"
    requirement: TRANS-06
    verification:
      - kind: other
        ref: "grep —— VERDICT 含 PARTIAL/BLOCKED(manual) 字样、GPL 关闭声明、五条 SC 各有判定、人工清单四项"
        status: pass
    human_judgment: false
  - id: D6
    description: "SC#3 的画质侧：视觉无损（人眼基本看不出差异）"
    requirement: TRANS-04
    verification: []
    human_judgment: true
    rationale: "本 Phase 从未运行 bench，无任何 SSIM/VMAF 读数。参数侧（argv 形状 + CRF18/medium 基线）已锁死，但『画质达标』这件事没有被证明过 —— 阈值 0.98/95 本身也只是行业经验值 [ASSUMED]"

duration: 22min
completed: 2026-10-04
status: complete
---

# Phase 6 Plan 05: 转码装配收口 Summary

**D-23 的播放合并装进 `router.start`（转完即播 app 级闭环），一份永不进自动路径的手动 SSIM/VMAF bench 脚本，test.sh 收 16 条纯逻辑门并把工具段最后那次 ffmpeg 调用摘掉**

## Performance

- **Duration:** 22 min
- **Started:** 2026-10-04T01:38:07+08:00
- **Completed:** 2026-10-04T02:00:00+08:00
- **Tasks:** 3
- **Files modified:** 5（401 insertions / 14 deletions）

## Accomplishments

- **SC#5 的 app 级闭环成立**：`AppDelegate.mergedPlaybackItems(_:)` 成为播放清单的唯一产出处，
  `router.start(with:)` 的**两处**调用点（`startWallpaper` 与 `dispatchPlayback`）全部改走它；
  裸形态 `router.start(with: report.items)` 剥注释后计数为 **0**。
  排空钩子 `onBatchFinished → invalidateCache() → rescanAndApply()` 补上最后一跳 ——
  少这一步，`MediaLibrary` 的内存缓存会让新产物永远看不见，且**不报错**。
- **ffmpeg 红线在字母义上收口**：工具段残留的 `$(ffmpeg -version …)` 调用本体移除（判据名「ffmpeg 可用」
  逐字保留，D-14），红线拆串门锁住「joined 字面计数为 0 且拆串形态在场」。变异验证过：插入 joined 字面两条计数同时转 1。
- **C7 的终值流程就位**：`scripts/transcode-bench.sh` 手动可跑 —— CRF 16/18/20 × preset medium/slow
  全矩阵、SSIM+VMAF 双度量、Rosetta 折损警示、`BENCH_PROGRESS_RAW` 微秒核对项、采纳指引指向 `TranscodeCommand` 常量。
- **诚实基线**：`06-VERDICT.md` 的 SC#3 判 **PARTIAL / BLOCKED(manual)** —— 「人眼基本看不出差异」
  在本 Phase **没有任何读数证明过**，四项人工清单逐字保留为人工项。

## Task Commits

1. **Task 1: 装配闭环（router.start 合并 + 排空钩子）** - `b1f8811` (feat)
2. **Task 2: 手动 transcode-bench.sh** - `cba3279` (feat)
3. **Task 3: test.sh Phase 6 段 + VERDICT + W-34** - `94317cf` (feat)

## Files Created/Modified

- `Sources/PicApp/AppDelegate.swift` — `convertedLibrary` 持有者、`mergedPlaybackItems(_:)`、
  `handleTranscodeBatchFinished()`（含 `PIC_TRC_RESCAN=1`）、`dispatchPlayback` 入参改为 report、
  `transcodeQueue` 构造闭包内挂 `onBatchFinished`
- `scripts/transcode-bench.sh` — 手动 bench（新建，可执行）
- `test.sh` — 工具段简化 + Phase 6 段 16 条门
- `.planning/phases/06-transcode/06-VERDICT.md` — 判定文件（新建）
- `.planning/WINDOWS.md` — 追加 `W-2026-10-03-34`

## Decisions Made

- **合并发生在调用点，不改扫描器**：`MediaLibrary` 的 `excludedByConverted` 全排除契约一个字没动
  （D-21 + 04-01 fixture）。代价是播放清单有两路来源，收益是防回流的第一层完好。
- **`dispatchPlayback` 的入参由 `items: [VideoItem]` 改为 `report: MediaLibraryReport?`**：
  `Converted/` 产物不在 `report.items` 里，合并只在装载这一处发生。分派结构
  （`.playing` → start / 三隐藏态 → stop）一个分支没动。
- **钩子挂在 lazy var 构造闭包内**（唯一建队列处），而不是 `bootstrapAfterWiring`：
  漏挂的表象是「转完了但清单里没有新片」，而清单那条路本身不报错。
- **test.sh 不重跑 transcode 探针**，只读已入库 evidence 的四行 —— 照 Phase 4 的 `p4_line` 纪律。

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] 计划的 W 编号自查判据不可满足（`uniq -d` 恒非 0）**
- **Found during:** Task 3
- **Issue**：plan 要求 `grep -oE 'W-2026-10-03-[0-9]+' WINDOWS.md | sort | uniq -d` 为空。
  实测**基线文件已有 12 条** —— W 条目之间存在正常的正文交叉引用（如 W-07 的「解开条件」里引用 W-07 自己），
  这类引用让字面计数必然重复。按字面执行会得到一个恒红的判据（D-07 空判的反面：一红到底的空判）。
- **Fix**：改按**标题行**判重（`grep -oE '^### W-…'`），基线与入册后均为 **0**；
  `-34` 在标题层未占用，已核对（最高编号为 30/48/49，34 空缺）。正文交叉引用**未删** —— 删了会断掉解开条件的指向。
- **Files modified:** 无（只改执行时的核查方式，WINDOWS.md 内容按 plan 写）
- **Verification**：`heading_dup=0`（入册后）；字面 `uniq -d` 仍为 12，与基线**完全一致** —— 未新增重号。
- **Committed in:** `94317cf`

**2. [Rule 1 - Bug] plan 的工具段简化会把 D-14 判据名改掉**
- **Found during:** Task 3
- **Issue**：plan 只说「把 `$(ffmpeg -version …)` 去掉」，但 `no()` 侧原文是 `no "ffmpeg 缺失"`，
  两侧判据名不同名 —— 改完 `ok()` 会写「ffmpeg 可用」而 `no()` 还写「ffmpeg 缺失」，
  下游在红日志里 `grep -c '❌ ffmpeg 可用'` 命中 0（正是 03-01/03-02/03-04 连续踩三次的那个坑）。
- **Fix**：`no()` 侧判据名一并改为「ffmpeg 可用」，差异信息移进第二参数。
- **Files modified:** `test.sh:26`
- **Verification**：剥注释后 `ffmpeg 可用` 计数 = 1（单一句判据名）；`command -v ffmpeg` 存在性探测保留。
- **Committed in:** `94317cf`

### Scope discipline notes（非 deviation，但记录在案）

- **`absoluteString` == 0 判据未在 Phase 6 段重复**：plan 的分层计数清单列了它，但它在既有
  「产品代码」段已对全 `Sources/` 判过一次。重复挂会出现两个真相源、且该门再也不会变红。判据未放宽，是不新增。
- **W-2026-10-03-30 未改状态**：初稿曾把它翻成 resolved，复核时发现「版本串仍未显示」
  （`grep -n version` 在 `ExternalToolLocator` 与三个 Transcode 视图里命中 0）——
  解开条件只满足了一半，且该条属 Phase 5 范围。已还原为 open 并附一条复核说明。

---

**Total deviations:** 2 auto-fixed（1 missing critical / 1 bug）
**Impact on plan:** 两处都是把 plan 里会恒红或会失效的判据改成真能判的形态，无功能范围扩张。
plan 要求的 W-34 编号本身可用（标题层无重号），入册内容未改。

## Issues Encountered

- `dispatchPlayback` 改 async 后，`rescanAndApply` 的 4 个调用点需要 `await` —— 编译器直接给了行号
  （594 / 606），改法即 plan 允许的「跟随该函数现状的最小改法」，无回退重试。
- 执行期发现 Swift 的 `swift test --filter 'A|B|C'` 在本仓的过滤语义下正好覆盖 40 条，
  与 plan 写死的数字一致；`TranscodeQueueTests` 单列正好 6 条。**门禁数字未改一个。**

## User Setup Required

**需要一次人工动作（不阻塞本 plan 完成判定）**：C7 的转码参数实测。
跑 `bash scripts/transcode-bench.sh`（**跑前先向用户确认 CPU 占用** —— STATE.md 的 ffmpeg 红线），
结束后按 `BENCH_RECOMMEND` 决定是否改 `Sources/PicCore/Transcode/TranscodeCommand.swift` 的
`baselineCRF` / `baselinePreset`；改了必须同 commit 更新 `TranscodeCommandTests` 测试 3。

另有三项人工清单见 `06-VERDICT.md`（开窗目视 / 入口置灰三途径 / bench 终值 / videotoolbox 核对），
共约 5 分钟。

## Next Phase Readiness

- **Phase 7（打包分发）**：Phase 6 的全部自动门已闭合并挂在 `test.sh` 上，Phase 7 可直接复用。
  `test.sh` 现为**通过 79 / 失败 0 / 跳过 5**。
- **GPL Blocker 已关闭**：自用 + 子进程架构下零义务。若 Phase 7 把 ffmpeg 静态二进制**打进 DMG**，
  该结论立即失效，须重新评估（VERDICT 里已写明这条边界）。
- **已知未闭合项**：
  - SC#3 画质侧 BLOCKED(manual) —— bench 未跑，「视觉无损」无读数支撑。
  - 装配门（`mergedPlaybackItems` / `onBatchFinished` / `invalidateCache`）锁的是**结构**，
    「排空后 UI 上真的多一个新片」这一跳未活体验证。
  - `W-2026-10-03-30` 仍 open（ffmpeg 版本串未显示）。

---

## Self-Check: PASSED

- [x] 三个 task 各自的 `<acceptance_criteria>` 全绿（逐条跑过并记录）
- [x] `swift build` RC=0；`swift test` 全量 RC=0（190 tests, 2 skipped, 0 failures）
- [x] `bash test.sh` RC=0，**通过 79 / 失败 0 / 跳过 5**（基线 63，+16），Phase 2–5 段零转红
- [x] `bash -n test.sh` 与 `bash -n scripts/transcode-bench.sh` 均 RC=0；bench 可执行位在
- [x] 红线门变异验证：插入 joined 字面后两条计数同时转 1（判据非空）
- [x] 装配门变异验证：删掉 `invalidateCache` 后该门计数转 0（判据非空）
- [x] `06-VERDICT.md` 含五条 SC 判定 + GPL 关闭 + 人工清单四项 + A1–A9 状态表；SC#3 如实 PARTIAL
- [x] `W-2026-10-03-34` 在册；标题层重号 0；字面 `uniq -d` 与基线一致（12 → 12，未新增）
- [x] bench 脚本**未运行**（零 ffmpeg 执行）
- [x] STATE.md / ROADMAP.md 未改（本次 dispatch 明令不更新）

---
*Phase: 06-transcode*
*Plan: 05*
*Completed: 2026-10-04*