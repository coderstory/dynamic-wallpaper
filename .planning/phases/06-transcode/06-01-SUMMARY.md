---
phase: 06-transcode
plan: 01
subsystem: transcode
tags: [ffmpeg, argv, x264, transcode, media-library, XCTest]

requires:
  - phase: 04-media-library
    provides: MediaLibrary.allowedExtensions / MediaLibrary.excludedDirectoryName / VideoAssetProbe 协议 / VideoItem（只读复用，零修改）
provides:
  - TranscodeCommand.arguments(input:output:) —— 28-token 锁定基线 argv（TEST-06 本体）
  - TranscodeCommand.displayString —— nice -n 10 审计串（TRANS-06 纯函数侧）
  - TranscodeOutputNaming —— Converted/<stem>.mp4 / .mp4.tmp / mtime 幂等跳过（TRANS-04）
  - TranscodeCandidateFilter —— mkv/avi/webm 白名单 + Converted 全等排除（TRANS-05 第一闸门）
  - ConvertedLibrary.scan + playbackItems —— D-23 播放第二入口数据侧（SC#5）
affects: [06-03 TranscodeQueue, 06-05 装配与统一校验, 06-04 转码窗口]

actuals:
  tokens: 6935
  tasks: 2
  commits: 4

tech-stack:
  added: []
  patterns:
    - 命令与执行分离：argv 纯函数构造（可单测）与 Process 执行（06-03）分文件
    - 排除规则收口单一助手（isInsideConverted），全等匹配 token 全项目唯一出现

key-files:
  created:
    - Sources/PicCore/Transcode/TranscodeCommand.swift
    - Sources/PicCore/Transcode/TranscodeOutputNaming.swift
    - Sources/PicCore/Transcode/TranscodeCandidateFilter.swift
    - Sources/PicCore/Transcode/ConvertedLibrary.swift
    - Tests/PicCoreTests/TranscodeCommandTests.swift
    - Tests/PicCoreTests/TranscodeOutputNamingTests.swift
    - Tests/PicCoreTests/TranscodeCandidateFilterTests.swift
    - Tests/PicCoreTests/ConvertedLibraryTests.swift
  modified: []

key-decisions:
  - "目录名全等判定收口在 TranscodeCandidateFilter 私有助手 isInsideConverted（模式串全文件恰好一次），candidates 与 isCandidate 复用 —— 变异 perl 命中点唯一，防两处规则漂移"
  - "TranscodeOutputNaming.convertedDirectoryName = MediaLibrary.excludedDirectoryName（引用不另写）：两个名字漂移之日就是回流闸门失效之时（D-21）"
  - "变异红灯判据读「编译器诊断形态」（error: 行但非 -[PicCoreTests.… 断言行）== 0 —— XCTest 断言失败行自带 error: 前缀，裸 grep 'error:' 对任何合法断言红恒 > 0；D-16 意图不放宽、判别更严"

patterns-established:
  - "保型变异的闭包布局：被插桩的闭包体单独成行、brace 另起一行 —— 行尾 // 注释才不会吞掉闭包右括号（D-16）"

requirements-completed: [TRANS-03, TRANS-04, TRANS-05, TEST-06]

coverage:
  - id: D1
    description: "ffmpeg argv 逐 token 构造（28 元素锁定基线）+ nice -n 10 审计串 + baseline 常量（TEST-06 / TRANS-03 参数侧）"
    requirement: TEST-06
    verification:
      - kind: unit
        ref: "Tests/PicCoreTests/TranscodeCommandTests.swift#testArgumentsMatchExpectedTokenSequenceExactly"
        status: pass
      - kind: unit
        ref: "Tests/PicCoreTests/TranscodeCommandTests.swift#testDisplayStringStartsWithNiceAndJoinsSameTokens"
        status: pass
      - kind: unit
        ref: "Tests/PicCoreTests/TranscodeCommandTests.swift#testBaselineConstantsAreCrfEighteenPresetMedium"
        status: pass
      - kind: unit
        ref: "Tests/PicCoreTests/TranscodeCommandTests.swift#testAudioMapIsOptionalAndSubtitleDataStreamsDropped"
        status: pass
    human_judgment: false
  - id: D2
    description: "产物路径推导 Converted/<stem>.mp4、.tmp 中间态、mtime 幂等跳过三态（TRANS-04）"
    requirement: TRANS-04
    verification:
      - kind: unit
        ref: "Tests/PicCoreTests/TranscodeOutputNamingTests.swift（6 条全绿：路径/怪名/tmp 后缀/跳过三态）"
        status: pass
    human_judgment: false
  - id: D3
    description: "转码候选双闸门：mkv/avi/webm 白名单（大小写不敏感）+ Converted 目录名大小写不敏感全等排除（非子串）+ 符号链接跳过 + .tmp 免疫（TRANS-05 第一闸门）"
    requirement: TRANS-05
    verification:
      - kind: unit
        ref: "Tests/PicCoreTests/TranscodeCandidateFilterTests.swift（6 条全绿，含 converted-lower 照收的反证）"
        status: pass
      - kind: unit
        ref: "变异 MUT-P6-BACKFLOW（全等→子串）→ testLowercaseConvertedDirIsAlsoExcludedNotSubstring 断言红（编译器诊断 0 条），恢复后 cmp -s 逐字节一致"
        status: pass
    human_judgment: false
  - id: D4
    description: "D-23 播放第二入口数据侧：ConvertedLibrary 扫 Converted/ 子树产出可播清单 + playbackItems 合并去重（SC#5）"
    requirement: TRANS-03
    verification:
      - kind: unit
        ref: "Tests/PicCoreTests/ConvertedLibraryTests.swift（6 条全绿：子树/缺失空/.tmp 排除/非白名单/坏文件/合并去重）"
        status: pass
    human_judgment: false

duration: 14 min
completed: 2026-10-03
status: complete
---

# Phase 6 Plan 1: 转码纯逻辑内核 Summary

**28-token ffmpeg argv 逐 token 构造 + Converted/ 产物命名与 mtime 幂等跳过 + 候选双闸门过滤 + D-23 播放第二入口（ConvertedLibrary），全部纯逻辑零 ffmpeg 调用，22 条单测 + 2 次变异反向验证**

## Performance

- **Duration:** 14 min
- **Started:** 2026-10-03T12:27:02Z
- **Completed:** 2026-10-03T12:41:27Z
- **Tasks:** 2 (T1 tracer + T2)
- **Files modified:** 8 (4 源 + 4 测试，全部新建)

## Accomplishments

- `TranscodeCommand.arguments` 逐 token 等于锁定基线 argv（`0:a:0?` 带问号、`-sn`/`-dn`、`+faststart`、`pipe:1`），`displayString` 以 `nice -n 10` 开头且与 argv 同 token —— TEST-06 本体，测试侧手写 28 元素期望数组（非产品代码生成）
- `TranscodeOutputNaming`：`Converted/<stem>.mp4`、`.mp4.tmp` 中间态、mtime 幂等跳过三态（产物新→跳过 / 源新→重转 / 缺失→不跳），读取失败按 false（宁可重转不误跳）
- `TranscodeCandidateFilter`：白名单 {mkv, avi, webm}、Converted 目录名大小写不敏感**全等**排除（`converted-lower/` 照收，反子串假实现）、符号链接跳过、根缺失空不抛
- `ConvertedLibrary`（D-23 载体）：扫 `Converted/` 子树产出可播 `VideoItem[]`（复用 `MediaLibrary.allowedExtensions`，`.tmp` 天然不进），`playbackItems` root 在前 converted 去重追加 —— 06-05 在 `router.start(with:)` 调用点合并
- 全套 `swift test`：**135 tests, 0 failures, 1 skipped**（113 基线 + 22 新增；skip 为既有基线行为）
- 两次变异反向验证均从**断言失败**转红（非编译失败），恢复后 `cmp -s` 逐字节一致

## Task Commits

Each task was committed atomically (TDD RED → GREEN):

1. **Task 1: TranscodeCommand + TranscodeOutputNaming** — RED `fc74707` (test) / GREEN `09669ee` (feat)
2. **Task 2: TranscodeCandidateFilter + ConvertedLibrary** — RED `9b90dfb` (test) / GREEN `28fe6ec` (feat)

**Plan metadata:** 见本 commit（docs: complete plan）

## Files Created/Modified

- `Sources/PicCore/Transcode/TranscodeCommand.swift` — argv 纯函数 enum + baseline 常量 + 审计串（注释明示不可直接执行）
- `Sources/PicCore/Transcode/TranscodeOutputNaming.swift` — 产物路径 / .tmp / mtime 幂等（不写盘，目录创建留给 06-03）
- `Sources/PicCore/Transcode/TranscodeCandidateFilter.swift` — 候选发现（全等排除收口单一助手）
- `Sources/PicCore/Transcode/ConvertedLibrary.swift` — D-23 播放第二入口（@MainActor，注入 VideoAssetProbe）
- `Tests/PicCoreTests/` 四个测试文件 — 4+6+6+6 = 22 条，文件内自带替身、临时目录自造树、零 fixtures/ 依赖

## Decisions Made

- 目录名全等判定收口 `isInsideConverted` 私有助手（模式串全文件唯一出现），`candidates`/`isCandidate` 复用 —— 见 key-decisions
- `convertedDirectoryName` 直接引用 `MediaLibrary.excludedDirectoryName`，不另写字面量
- 遵循计划：不做探针、不做缓存、不做配置化（baselineCRF/baselinePreset 命名成 baseline 供 C7 bench 同 commit 改值）

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] MUT-P6-BACKFLOW 首次变异吞掉闭包右括号（编译失败冒充红灯）**
- **Found during:** Task 2（变异反向验证）
- **Issue:** GREEN 初版把闭包写成单行 `{ $0.caseInsensitiveCompare(...) == .orderedSame }`，行尾插桩 `// MUT-P6-BACKFLOW` 把同一行的闭包 `}` 注释掉 → 编译失败，正是 D-16 反模式
- **Fix:** 按计划「单独一行闭包体」原意重排 —— 闭包体独立成行、brace 另起一行；变异后仍编译、`testLowercaseConvertedDirIsAlsoExcludedNotSubstring` 断言红
- **Files modified:** `Sources/PicCore/Transcode/TranscodeCandidateFilter.swift`
- **Verification:** 变异 RC=1、命名用例红、编译器诊断 0 条；恢复后 cmp -s 一致、恢复后再绿（Executed 6 tests, 0 failures）
- **Committed in:** `28fe6ec`（Task 2 GREEN commit 内）

**2. [Rule 3 - Blocking] verify 块 `cd /Users/coderstory/dev/pic` 指向主检出**
- **Found during:** Task 1 verify 执行前
- **Issue:** 计划 `<automated>` 块以 `cd /Users/coderstory/dev/pic` 开头 —— 在 worktree 执行会验错检出（step 0c / wave-1..4 已知课）
- **Fix:** 按既有纪律把命令根重锚到本 worktree（`--package-path .` 从 worktree 根跑），判据本体一字未改
- **Files modified:** 无（执行环境适配）
- **Verification:** 全部判据在本 worktree 上跑过并过
- **Committed in:** N/A（无代码改动）

**3. [Rule 3 - Blocking] 计划的「RED_COMPILE = grep -c 'error:' == 0」字面不可满足**
- **Found during:** Task 1 变异验证
- **Issue:** XCTest 的断言失败行自带 `error:` 前缀（`: error: -[PicCoreTests.…] : XCTAssertEqual failed`），任何合法断言红都会让裸 `grep -c 'error:'` > 0 —— 计划判据按字面跑会把正确红灯误判为「测试瞎或变异编译失败」
- **Fix:** 判据意图（D-16：红来自断言非编译）用更严判别器落实：`error:` 行中**非** `-[PicCoreTests.…]` 形态（即编译器诊断形态）的计数 == 0。两处变异红日志实测：Task 1 编译器诊断 0 条（3 条 error: 全是断言行），Task 2 同样 0 条。判据未放宽，判别收紧
- **Files modified:** 无
- **Verification:** 见上；SUMMARY 记录供 06-05 统一校验作者知情
- **Committed in:** N/A

---

**Total deviations:** 3 auto-fixed（1 bug、2 blocking/环境与判据形态适配）
**Impact on plan:** 无 scope 蔓延；全部改动仍在 files_modified 八文件域内。

## Issues Encountered

- TranscodeCandidateFilterTests 初版 `var url = root` 从 IUO 推断成 `URL?` 编译失败（RED 阶段，提交前修正为 `var url: URL = root`）—— 不影响 RED 证据：RED commit 里全部失败为断言失败、0 编译错误
- 06-02 并行 worktree 无文件冲突（本 plan 未触 ExternalToolLocator/ProgressParser）

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- 06-03 `TranscodeQueue` 可直接消费本 plan 的三个纯函数件：`TranscodeCandidateFilter.candidates(in:)` → `TranscodeOutputNaming.outputURL/temporaryURL/skipDecision` → `TranscodeCommand.arguments`
- 06-05 装配侧：`ConvertedLibrary.scan + playbackItems` 在 `router.start(with:)` 调用点合并（D-23 / W-2026-10-03-34 注册由 06-05 做）
- `swift test` 全绿基线现为 **135**（后续 plan 的红灯归因以此为参照）
- 本 plan 零 ffmpeg 调用（C6 红线遵守）；未跑 `bash test.sh`（按波次纪律，统一校验在 06-05）

---
*Phase: 06-transcode*
*Completed: 2026-10-03*
