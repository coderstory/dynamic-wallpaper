---
phase: 06-transcode
plan: "03"
subsystem: transcode
tags: [transcode, process, queue, nice, terminationStatus, xctest, tracer]

# Dependency graph
requires:
  - phase: 06-transcode
    provides: TranscodeCommand.arguments/displayString + TranscodeOutputNaming + TranscodeCandidateFilter + ConvertedLibrary（06-01）与 ExternalToolLocator/FFmpegToolStatus + ProgressParser（06-02）
provides:
  - TranscodeQueue —— 串行执行队列（四道预检 + tmp→rename + 进度 + onJobsChanged/onBatchFinished 回调）
  - TranscodeRunning 协议 + ProcessTranscodeRunner（/usr/bin/nice -n 10 前缀、stdout 逐行、退出只认 terminationStatus）
  - 执行 tracer 活体证据（PIC_TRC_* 16 行：转完 → 可播 → 不回流 → 幂等跳过）
affects: [06-04 转码窗口（onJobsChanged / jobs / FFmpegToolStatus 置灰）, 06-05 装配（onBatchFinished → rescanAndApply，SC#5）]

# Actuals (#2632) — pairs with the plan's `estimate` to calibrate future estimates.
actuals:
  tokens: 8366
  tasks: 2
  commits: 3

# Tech tracking
tech-stack:
  added: []
  patterns:
    - 执行层协议不标 @MainActor、持有者（@MainActor TranscodeQueue）负责隔离 —— 照 HoldArbiter/06-02 seam 写法
    - readabilityHandler + NSLock 行切分器 + 收尾 drain：半行不丢、handler 置 nil 防泄漏后管道残量仍被读
    - 进度回调 Task { @MainActor } 跳岛：runner 在后台线程发线，percent 更新回主 actor

key-files:
  created:
    - Sources/PicCore/Transcode/TranscodeQueue.swift
    - Sources/PicCore/Transcode/ProcessTranscodeRunner.swift
    - Tests/PicCoreTests/TranscodeQueueTests.swift
    - Tests/PicCoreTests/ProcessTranscodeRunnerTests.swift
    - .planning/spike/TranscodeTracerDriver.swift
    - scripts/probe-transcode.sh
    - .planning/phases/06-transcode/evidence/transcode-tracer.log
  modified: []

key-decisions:
  - "RED commit 形态 = 测试 + 类型骨架 stub（enqueue 真建 job、run 空）—— RED 红在断言（10 断言失败、0 编译错误），Swift 上纯测试文件编译不过属 INVALID_RED（沿 06-02 先例）"
  - "enqueue 去重只对「仍在排队」的 job（pending/running）：已终态的同路径允许再入队、由 skipDecision 走幂等路径 —— 这是二次入队判 skipped（driver 步骤 13）得以成立的前提"
  - "rename 用 remove+moveItem（计划二选一之一）：replaceItemAt 对目标不存在时的行为不定，remove+move 确定性可测"
  - "driver 的 REFILTER 读数 = candidates 再过 skipDecision：裸 candidates 对已转码源恒非空（TRANS-04 源保留），「回流」的定义是「还会被再次转码」（见 Deviations #4）"

patterns-established:
  - "保型变异行：`if status == 0 {` 单独成行、无尾随代码 —— 行尾 // MUT-P6-RENAME 不吞后续 token（D-16）"
  - "probe 脚本 SRC 清单必须含常量宿主：跨文件引用的 static 常量（MediaLibrary.excludedDirectoryName）让宿主文件成为隐藏编译依赖"

requirements-completed: [TRANS-03, TRANS-04, TRANS-05, TRANS-06]

# Coverage metadata (#1602)
coverage:
  - id: D1
    description: "TranscodeQueue 串行状态机四路径：成功（tmp→rename、源保留）、失败（清 tmp、无半成品、受控 reason）、幂等跳过（零 runner 调用）、双预检（磁盘/可用性零 spawn）（TRANS-03/TRANS-04 执行侧）"
    requirement: TRANS-03
    verification:
      - kind: unit
        ref: "Tests/PicCoreTests/TranscodeQueueTests.swift#testSuccessfulJobRenamesTmpToMp4AndKeepsSource"
        status: pass
      - kind: unit
        ref: "Tests/PicCoreTests/TranscodeQueueTests.swift#testFailedJobCleansTmpAndMarksFailed"
        status: pass
      - kind: unit
        ref: "Tests/PicCoreTests/TranscodeQueueTests.swift#testUpToDateProductIsSkippedWithoutRunner"
        status: pass
      - kind: unit
        ref: "Tests/PicCoreTests/TranscodeQueueTests.swift#testJobsRunSeriallyInEnqueueOrder"
        status: pass
      - kind: unit
        ref: "Tests/PicCoreTests/TranscodeQueueTests.swift#testInsufficientDiskSpaceFailsBeforeRunner"
        status: pass
      - kind: unit
        ref: "Tests/PicCoreTests/TranscodeQueueTests.swift#testUnavailableFFmpegFailsWithoutSpawn"
        status: pass
      - kind: unit
        ref: "变异 MUT-P6-RENAME（== 翻向 !=）→ testSuccessfulJobRenamesTmpToMp4AndKeepsSource 等 4 断言红（0 编译器诊断），恢复后 cmp -s 逐字节一致、复绿"
        status: pass
    human_judgment: false
  - id: D2
    description: "ProcessTranscodeRunner：/usr/bin/nice -n 10 前缀 spawn、stdout 逐行喂回调（不丢半行）、退出判定只认 terminationStatus（C10/C11）"
    requirement: TRANS-03
    verification:
      - kind: unit
        ref: "Tests/PicCoreTests/ProcessTranscodeRunnerTests.swift#testRunnerReportsProgressLinesAndExitStatusViaShellStub（/bin/sh printf 桩，零 ffmpeg）"
        status: pass
      - kind: unit
        ref: "结构判据：剥注释后 /usr/bin/nice ≥1、terminationStatus ≥1、waitUntilExit ≥1、sh -c ==0、管道字符 ==0、absoluteString ==0"
        status: pass
    human_judgment: false
  - id: D3
    description: "执行 tracer 活体证据：候选→argv 28 token→假 runner 队列→Converted 产物可播（D-23 第二入口）→回流闭环（再过滤 0）→二次入队 skipped 零 spawn→onBatchFinished 每轮排空恰一次（TRANS-05/TRANS-06）"
    requirement: TRANS-05
    verification:
      - kind: manual_procedural
        ref: "bash scripts/probe-transcode.sh → .planning/phases/06-transcode/evidence/transcode-tracer.log（16 行 PIC_TRC_* 全绿：CANDIDATES=1 ARGV_TOKENS=28 RUNNER_CALLS=1 REFILTER=0 SECOND_PASS_SKIPPED=1 RUNNER_CALLS_TOTAL=1 BATCH_FINISHED=2；Movies=0、ffmpeg 执行行=0、PIC_EVIDENCE_DIR 重定向可用）"
        status: pass
    human_judgment: false

# Metrics
duration: 10 min
completed: 2026-10-03
status: complete
---

# Phase 6 Plan 03: 转码执行层与活体证据 Summary

**串行 TranscodeQueue（四道预检 + tmp→rename + 进度链）与 ProcessTranscodeRunner（nice 前缀 / terminationStatus 唯一成败判据 / stdout 逐行），7 条零 ffmpeg 单测 + 变异反向验证，外加一条 driver 把 06-01+06-02+06-03 全部纯件串成「转完 → 可播 → 不回流 → 幂等」的活体证据**

## Performance

- **Duration:** 10 min（12:52–13:02 UTC）
- **Started:** 2026-10-03T12:52:46Z
- **Completed:** 2026-10-03T13:02:40Z
- **Tasks:** 2（T1 TDD RED→GREEN + 变异；T2 driver/probe/evidence）
- **Files modified:** 7（2 源 + 2 测试 + driver + probe 脚本 + evidence，全部新建）

## Accomplishments

- **TranscodeQueue**（`@MainActor`，照 `MediaLibrary` 持有者隔离）：串行 for-drain、四道预检（可用性 → 幂等 skipDecision → mkdir Converted → 磁盘余量 < 源大小）、成功 tmp→rename（rename 失败清 tmp 标 `output_conflict`）、失败删 tmp 标 `exit_nonzero`、reason 全部受控 token；`onBatchFinished` 排空恰一次（driver 实测每轮各一次）
- **ProcessTranscodeRunner**：`/usr/bin/nice -n 10 <tool> <argv>`（argv 数组直接给 nice，零 shell 拼接）、stdout `readabilityHandler` + NSLock 行切分器（半行不丢）+ 收尾 drain（handler 置 nil 后管道残量仍被读）、退出只认 `terminationStatus`、stderr 整根吞掉
- **7 条单测全绿零 ffmpeg**：队列 6 条（FakeRunner 进程外零调用）+ runner 1 条（`/bin/sh` printf 桩，C6 合规注释钉在测试上方）；全套回归 **153 tests, 0 failures, 1 skipped**（146 基线 + 7 新增，skip 为既有基线行为）
- **变异 MUT-P6-RENAME**（`if status == 0` 翻向 `!=`）：4 断言红、`testSuccessfulJobRenamesTmpToMp4AndKeepsSource` 在失败列表、0 编译器诊断；恢复后 `cmp -s` 逐字节一致、复绿
- **执行 tracer 活体证据**（16 行 `PIC_TRC_*`）：mkv 候选 1 → argv 28 token → 审计串 ok → 假 runner 1 次调用 → 产物存在/.tmp 消失/源原状 → succeeded → `ConvertedLibrary` 判可播 1、合并 2（D-23 第二入口）→ 再过滤 0（回流闭环）→ 二次入队 skipped 且累计 runner 调用仍 1 → `onBatchFinished` 2 次；evidence 零 ffmpeg 执行行、零真实目录（Movies=0）、`PIC_EVIDENCE_DIR` 重定向可用

## Task Commits

Each task was committed atomically (TDD: RED → GREEN):

1. **Task 1 RED: 7 条测试 + 类型骨架 stub** - `bce4b9b` (test)
2. **Task 1 GREEN: 队列 + runner 实现** - `fc90b78` (feat)
3. **Task 2: driver + probe + evidence** - `c0696d3` (feat)

**Plan metadata:** 本 commit（docs: complete plan）

## Files Created/Modified

- `Sources/PicCore/Transcode/TranscodeQueue.swift` — TranscodeRunning 协议 + TranscodeJob/State + AVAssetDurationProvider + 串行队列（本文件是 Transcode/ 唯一 `import AVFoundation`）
- `Sources/PicCore/Transcode/ProcessTranscodeRunner.swift` — 生产执行件 + 私有 LineSplitter（只 import Foundation）
- `Tests/PicCoreTests/TranscodeQueueTests.swift` — 6 条 + 文件内 FakeRunner
- `Tests/PicCoreTests/ProcessTranscodeRunnerTests.swift` — 1 条 sh 桩 + 线程安全 LineBox
- `.planning/spike/TranscodeTracerDriver.swift` — throwaway driver（16 行读数）
- `scripts/probe-transcode.sh` — SRC 逐列编译 → driver → Phase 6 evidence
- `.planning/phases/06-transcode/evidence/transcode-tracer.log` — 18 行活体读数

## Decisions Made

- enqueue 去重只作用于「仍在排队」（pending/running）的 job —— 终态 job 同路径再入队走 skipDecision 幂等路径（driver 步骤 13 的前提）
- rename 采用 remove+moveItem（计划允许的两个方案之一），确定性可测
- 队列审计串 `commandDisplay` 入队时算好、输出位用 temporaryURL（与实际执行的 argv 一致）；duration 在 job 开始时取一次缓存
- RED 骨架的 enqueue 真建 job、run() 空 —— RED 全部红在断言（10 断言失败、0 编译错误）

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - 判据缺陷] 测试文件「剥注释后 ffmpeg 计数 == 0」按字面不可满足**
- **Found during:** Task 1 结构门禁（GREEN 后）
- **Issue:** 计划自己的公开面强制了三处非注释 `ffmpeg` 字样 —— `TranscodeRunning.run(ffmpegPath:)` 协议标签（符号表逐字规定，FakeRunner 实现与测试调用点都必须写）、受控 reason token `"ffmpeg_unavailable"`（计划规定的枚举值）。剥注释后字面计数恒 ≥2，判据按字面永假
- **Fix:** 按计划 T2 自己的口径（「`ffmpeg -` 与 `nice -n 10 ffmpeg` **执行形态**计数为 0」）落实同一意图：两个测试文件剥注释后执行形态计数 == 0（实测 0），且逐行枚举核对全部 3 处字样均为协议标签 / reason token（T1:23、T1:176、T2:42）。判据意图（测试不 exec ffmpeg）未放宽
- **Files modified:** 无
- **Verification:** `grep -v 剥注释 | grep -cE 'ffmpeg -|nice -n 10 ffmpeg'` 两文件均 0；字样逐行列表见上
- **Committed in:** N/A（验证口径，记录于本 SUMMARY）

**2. [Rule 1 - 判据缺陷] 变异红日志 `grep -c 'error:' == 0` 对合法断言红恒 > 0**
- **Found during:** Task 1 变异反向验证
- **Issue:** XCTest 断言失败行自带 `error: -[PicCoreTests.…]` 前缀 —— 与 06-01 Deviation #3、06-02 Deviation #1 同一已知缺陷（计划判据沿用了它）
- **Fix:** 沿既有勘误口径：`error:` 行中非 `error: -[` 形态（编译器诊断）计数 == 0。实测红日志 0 条编译器诊断、4 条断言失败
- **Files modified:** 无
- **Verification:** MUTATED_RC=1、4 XCTAssert、编译器诊断 0、命名用例在失败列表、恢复后 cmp -s 一致
- **Committed in:** N/A

**3. [Rule 3 - Blocking] probe SRC 清单漏列 `Sources/PicCore/Media/MediaLibrary.swift`**
- **Found during:** Task 2 编译前（清单核对）
- **Issue:** 计划的 SRC 逐列清单没有 MediaLibrary.swift，但 `ConvertedLibrary`、`TranscodeOutputNaming`、`TranscodeCandidateFilter` 三个 06-01 文件全部引用 `MediaLibrary.excludedDirectoryName` / `allowedExtensions` —— 按计划清单编译必失败（正是计划自己警告的「SRC 漏列」事故形态）
- **Fix:** SRC 补列 `Sources/PicCore/Media/MediaLibrary.swift`，其余照计划逐列、零通配
- **Files modified:** scripts/probe-transcode.sh
- **Verification:** probe 一次编译通过（PROBE_COMPILE_RC 未出现）、两轮 RC=0
- **Committed in:** c0696d3

**4. [Rule 1 - 判据缺陷] `PIC_TRC_REFILTER_CANDIDATES` 裸 `candidates(in:)` 恒 1，判据按字面不可满足**
- **Found during:** Task 2 driver 编写前（设计核对）
- **Issue:** TRANS-04 规定源文件保留不删（driver 步骤 8 `SOURCE_INTACT=1` 同锁），而 06-01 的 `TranscodeCandidateFilter` 语义已被其 6 条测试锁定为「扩展名白名单 + Converted 排除」，不看产物新鲜度 —— 转码后源 mkv 仍会被裸 `candidates(in:)` 收到，恒为 1，与「须 0」矛盾
- **Fix:** 按判据意图（「回流」= 还会被再次转码）改为两道闸门联合判定：`candidates(in:).filter { !naming.skipDecision(source: $0) }` → 0。防死循环的本体证据链完整：filter+skip 联合 0（步骤 12）、二次入队 skipped（步骤 13）、累计 runner 调用仍 1（步骤 14）三行互相印证
- **Files modified:** .planning/spike/TranscodeTracerDriver.swift（读数构成，非产品代码）
- **Verification:** evidence `PIC_TRC_REFILTER_CANDIDATES=0` 且 `SECOND_PASS_SKIPPED=1`、`RUNNER_CALLS_TOTAL=1`
- **Committed in:** c0696d3

**5. [Rule 3 - Blocking] `<automated>` 块 `cd /Users/coderstory/dev/pic` 指向主检出**
- **Found during:** Task 1 verify 执行前
- **Issue:** 在 worktree 执行会验错检出（wave 1-4 已知课，06-01/06-02 均已记）
- **Fix:** 命令根重锚本 worktree（默认 cwd 即 worktree 根，`--package-path .` 照跑），判据本体一字未改
- **Files modified:** 无
- **Verification:** 全部判据在本 worktree 上跑过并过
- **Committed in:** N/A

---

**Total deviations:** 5 auto-fixed（3 判据缺陷、2 blocking/清单与环境适配）
**Impact on plan:** 零生产代码语义偏移、零 scope 蔓延；全部改动仍在 files_modified 七文件域内。计划的全部行为判据（四路径、串行、变异红、16 行读数）原样通过。

## Issues Encountered

- RED 骨架 init 首写笔误（`freeSpace` ↔ `freeSpaceProvider`）编译失败一次，提交前修正 —— RED commit 里全部失败仍为断言失败、0 编译错误
- 沙箱拒跑 `perl -e 'alarm …; exec @ARGV'` 包装与长复合命令：probe 直跑 `bash scripts/probe-transcode.sh`（alarm 纪律在脚本内部对 swiftc/driver 生效）、验证块按步骤拆分执行
- `PIC_TRC_LINES=15`（emit 前计数，与 04-01 MediaLibraryDriver 同语义）；判据只要求该行恰一行存在，日志总行数 18 ≥ 16

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- 06-04 直接可用：`queue.jobs` / `onJobsChanged`（UI 钩子）、`FFmpegToolStatus` 置灰、`commandDisplay` 审计串、受控失败 reason
- 06-05 装配侧：`onBatchFinished → rescanAndApply`（SC#5）；`PIC_EVIDENCE_DIR` 重定向已验证不覆盖入库证据
- `swift test` 全绿基线现为 **153**（后续 plan 的红灯归因以此为参照）
- 本 plan 零 ffmpeg 调用（C6）；未跑 `bash test.sh`（按波次纪律，统一校验在 06-05）
- 真转码只存在于 06-05 的手动 bench（`-t 5 -threads 2`）

## Self-Check: PASSED

- [x] `swift build` RC 0
- [x] TranscodeQueueTests `Executed 6 tests, with 0 failures`；ProcessTranscodeRunnerTests `Executed 1 test, with 0 failures`
- [x] 源文件结构门禁全过（UI/Combine 零 import、nice/terminationStatus/waitUntilExit ≥1、零 shell 拼接/absoluteString）
- [x] 测试文件执行形态 ffmpeg == 0（字面门禁不可满足，见 Deviation #1）
- [x] 变异 MUT-P6-RENAME：标记恰 1 次、断言红非编译红、恢复 cmp -s 一致、复绿
- [x] probe 两轮 RC 0；evidence 16 行读数齐全且关键闭环 REFILTER=0 / CONVERTED_PLAYABLE=1 / SECOND_PASS_SKIPPED=1 / RUNNER_CALLS_TOTAL=1 / BATCH_FINISHED=2
- [x] evidence Movies=0、ffmpeg 执行行=0；脚本零 test.sh 引用；PIC_EVIDENCE_DIR 重定向可用
- [x] 全量 `swift test`：153 tests, 0 failures, 1 skipped（146 基线 + 7 新增）

---
*Phase: 06-transcode*
*Completed: 2026-10-03*
