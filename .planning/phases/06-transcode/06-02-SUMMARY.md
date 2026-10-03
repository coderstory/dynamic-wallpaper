---
phase: 06-transcode
plan: "02"
subsystem: testing
tags: [ffmpeg, transcode, process, xctest, pure-logic]

# Dependency graph
requires:
  - phase: 04-media-library
    provides: XCTest 纯逻辑测试纪律（D-13…D-18）与零三方依赖测试基建
provides:
  - ExternalToolLocator 三态检测决策表（FFmpegToolStatus + WhichProbing/ExecutableFileProbing seam + ProcessWhichProbe/FileManagerExecutableProbe 生产件）
  - ProgressParser（-progress pipe:1 的 key=value 解析、out_time_ms 微秒语义、end 标志、clamp 百分比）
affects: [06-transcode (06-03 TranscodeQueue, 06-04 UI 置灰, 06-05 装配)]

# Actuals (#2632) — pairs with the plan's `estimate` to calibrate future estimates.
actuals:
  tokens: 44000
  tasks: 2
  commits: 4

# Tech tracking
tech-stack:
  added: []
  patterns:
    - 检测/解析层全 seam 注入（WhichProbing / ExecutableFileProbing），Process 只允许出现在生产 probe 件里
    - 微秒语义钉在字段名上（Snapshot.outTimeUs 对 ffmpeg 的 out_time_ms 历史误命名）

key-files:
  created:
    - Sources/PicCore/Transcode/ExternalToolLocator.swift
    - Sources/PicCore/Transcode/ProgressParser.swift
    - Tests/PicCoreTests/ExternalToolLocatorTests.swift
    - Tests/PicCoreTests/ProgressParserTests.swift
  modified: []

key-decisions:
  - "FFmpegToolStatus 命名（非 FFmpegAvailability）—— 避 Phase 5 同 target 撞型（checker B1 / D-17）"
  - "RED_COMPILE 判据勘误：裸 'error:' 计数在本工具链上必含 XCTest 断言失败行（'error: -[...' 形态），改按「剔除 'error: -[' 后为 0」验证同一意图（红非来自编译失败），判据未放宽"

patterns-established:
  - "Seam 协议不标 @MainActor、由持有者负责隔离（照 HoldArbiter 写法）"
  - "保型变异：for path in [String]()（循环变量保留、集合清空），D-16"

requirements-completed: [TRANS-01, TRANS-06, TEST-05]

# Coverage metadata (#1602)
coverage:
  - id: D1
    description: "ExternalToolLocator 三态决策表：显式路径（/opt/homebrew/bin、/usr/local/bin 逐字在表）可执行即 available、不可执行跳过不判死、which 兜底、全空 unavailable；GUI 最小 PATH 下显式探测仍命中（P1 锁死）"
    requirement: TRANS-01
    verification:
      - kind: unit
        ref: "Tests/PicCoreTests/ExternalToolLocatorTests.swift#testAvailableWhenHomebrewPathExists"
        status: pass
      - kind: unit
        ref: "Tests/PicCoreTests/ExternalToolLocatorTests.swift#testAvailableWhenIntelBrewPathExists"
        status: pass
      - kind: unit
        ref: "Tests/PicCoreTests/ExternalToolLocatorTests.swift#testAvailableWhenWhichSucceeds"
        status: pass
      - kind: unit
        ref: "Tests/PicCoreTests/ExternalToolLocatorTests.swift#testUnavailableWhenNothingFound"
        status: pass
      - kind: unit
        ref: "Tests/PicCoreTests/ExternalToolLocatorTests.swift#testNotExecutableProbePathIsSkippedNotFatal"
        status: pass
      - kind: unit
        ref: "Tests/PicCoreTests/ExternalToolLocatorTests.swift#testGuiMinimalPathStillFindsHomebrewInstall"
        status: pass
    human_judgment: false
  - id: D2
    description: "ProgressParser：-progress pipe:1 样本块解析出 frame/outTimeUs（微秒语义）/end 标志，未知键与垃圾行容忍不崩；百分比 = 微秒换算秒 ÷ 时长并 clamp 0...1，时长缺失/为 0/无时间 → nil"
    requirement: TRANS-06
    verification:
      - kind: unit
        ref: "Tests/PicCoreTests/ProgressParserTests.swift#testParsesSampleChunkIntoSnapshot"
        status: pass
      - kind: unit
        ref: "Tests/PicCoreTests/ProgressParserTests.swift#testProgressEndFlagDetected"
        status: pass
      - kind: unit
        ref: "Tests/PicCoreTests/ProgressParserTests.swift#testUnknownKeysAndGarbageLinesTolerated"
        status: pass
      - kind: unit
        ref: "Tests/PicCoreTests/ProgressParserTests.swift#testPercentComputesRatioWithMicrosecondSemantics"
        status: pass
      - kind: unit
        ref: "Tests/PicCoreTests/ProgressParserTests.swift#testPercentNilWhenDurationMissingOrZeroOrNoTimeYet"
        status: pass
    human_judgment: false

# Metrics
duration: 10 min
completed: 2026-10-03
status: complete
---

# Phase 6 Plan 02: 转码检测与进度解析（纯逻辑件）Summary

**ExternalToolLocator 三态决策表（显式双路径 + which 兜底，GUI PATH 陷阱锁死）与 ProgressParser（out_time_ms 微秒语义 + clamp 百分比），11 条注入式单测全绿，两次保型变异反向验证通过**

## Performance

- **Duration:** 10 min（executor 执行段）
- **Started:** 2026-10-03T12:25:45Z
- **Completed:** 2026-10-03T12:35:20Z
- **Tasks:** 2（均 TDD：RED → GREEN）
- **Files modified:** 4（全部新建）

## Accomplishments
- **T1 ExternalToolLocator**：`FFmpegToolStatus`（命名避开 Phase 5 撞型）+ `WhichProbing`/`ExecutableFileProbing` seam + 决策表（显式路径表逐字含 `/opt/homebrew/bin/ffmpeg` 与 `/usr/local/bin/ffmpeg`、不可执行跳过不判死、which 兜底、全空 unavailable）+ `ProcessWhichProbe`（退出判定只认 `terminationStatus`，C10）与 `FileManagerExecutableProbe` 生产件。6 条用例全注入假件，零真跑 which。
- **T2 ProgressParser**：`parseLine`（首个 `=` 切分）/`parseChunk`（三键后值覆盖、垃圾行静默忽略）/`percent`（微秒换算 `1_000_000.0` 全文件恰一次、clamp 0...1、时长缺失 → nil）。5 条用例样本串硬编码，零 ffmpeg 零正则。
- **变异反向验证 ×2**：`MUT-P6-DETECT`（保型清空探测循环）→ 4 断言失败且 `testGuiMinimalPathStillFindsHomebrewInstall` 与 `testAvailableWhenHomebrewPathExists` 均红；`MUT-P6-PROGRESS`（`1_000_000.0`→`1_000.0`）→ `testPercentComputesRatioWithMicrosecondSemantics` 红（1.0 ≠ 0.25，clamp 后）。两者红均来自断言失败非编译失败；恢复后 `cmp -s` 逐字节一致，复跑全绿。
- **全套回归**：`swift test` 124 tests（113 基线 + 11 新增）、0 failures、1 skipped（既有 skip），零 ffmpeg 调用、零真跑 which（C6）。

## Task Commits

Each task was committed atomically (TDD: RED → GREEN):

1. **Task 1 RED: ExternalToolLocator 决策表 6 条** - `515234b` (test)
2. **Task 1 GREEN: 三态决策表实现** - `1987749` (feat)
3. **Task 2 RED: ProgressParser 5 条用例** - `4a9e2da` (test)
4. **Task 2 GREEN: 解析与换算实现** - `893386d` (feat)

**Plan metadata:** 本 commit（docs: complete plan）

## Files Created/Modified
- `Sources/PicCore/Transcode/ExternalToolLocator.swift` — FFmpegToolStatus + 双 seam 协议 + 决策表 + ProcessWhichProbe/FileManagerExecutableProbe 生产件（只 import Foundation）
- `Sources/PicCore/Transcode/ProgressParser.swift` — Snapshot + parseLine/parseChunk/percent（只 import Foundation，零正则）
- `Tests/PicCoreTests/ExternalToolLocatorTests.swift` — 6 条决策表用例 + 文件内 FakeWhich/FakeFS
- `Tests/PicCoreTests/ProgressParserTests.swift` — 5 条用例，样本串硬编码

## Decisions Made
- RED commit 采用「测试 + 全类型骨架 stub（locate() 返回 .unavailable / 三函数返回 nil）」形态：Swift 上纯测试文件编译不过属 INVALID_RED，骨架保证 RED 红在断言上（T1：5 失败 1 通过；T2：4 失败 1 通过，nil 路径用例先行通过）。
- 其余照计划：`FFmpegToolStatus` 命名、探测顺序、微秒字段名 `outTimeUs`、`for path in Self.probePaths` 逐字形状（变异 perl 依赖）。

## TDD Gate Compliance

| Gate | T1 | T2 | 证据 |
|------|----|----|------|
| RED | ✓ | ✓ | `test(06-02):` ×2，断言失败（T1 5 failures / T2 4 failures），非编译失败 |
| GREEN | ✓ | ✓ | `feat(06-02):` ×2，6/6 与 5/5 全绿 |
| REFACTOR | — | — | GREEN 即终形，无可清理项，未产生 commit（可选门） |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - 判据缺陷] RED_COMPILE 裸 `error:` 计数在本工具链上不可满足**
- **Found during:** Task 1 / Task 2 变异反向验证
- **Issue:** 计划 `<automated>` 的 `grep -c 'error:' == 0` 意图是「红来自断言失败而非编译失败」（D-16），但 XCTest 断言失败行本身即 `<file>:<line>: error: -[TestClass testMethod] : XCTAssert… failed` 形态 —— 任何真实的断言红都含 `error:`，裸计数恒 > 0，判据按字面永假。
- **Fix:** 按同一意图改验证口径：`grep 'error:' | grep -v 'error: -\[' | wc -l == 0`（两个变异 red.log 实测均为 0，即零编译错误；XCTest 失败行全被剔除）。判据未放宽 —— 编译错误（`error: cannot convert` / `error: SwiftCompile` / `error: Build failed` 形态，RED 首跑编译错时实测出现）仍会被抓住。
- **Files modified:** 无源码改动，仅验证口径（本 SUMMARY 与 GREEN commit message 记录）
- **Verification:** T1 red.log：4 条 `error:` 全为 `error: -[…])`，剔除后 0；T2 red.log：1 条同形态，剔除后 0
- **Committed in:** 893386d（commit message 记录）

**2. [Rule 1 - 测试编译] T2 测试 4 首跑可选值 accuracy 重载编译错**
- **Found during:** Task 2 RED 首跑
- **Issue:** `XCTAssertEqual(result, 0.25, accuracy:)` 的 `result` 是 `Double?`，该重载要非可选 `Double`，编译不过（INVALID_RED 形态）。
- **Fix:** `guard let result else { XCTFail(...); return }` 解包后再比；判据不变（仍锁 0.25 ± 0.0001），且 nil 时显式转红。
- **Files modified:** Tests/PicCoreTests/ProgressParserTests.swift
- **Verification:** 修后 RED 红在断言上（4 failures）；GREEN 5/5
- **Committed in:** 4a9e2da（RED commit 内）

---

**Total deviations:** 2 auto-fixed（2 × Rule 1 判据/测试编译缺陷）
**Impact on plan:** 均为验证口径/测试作者期修正，零生产代码语义偏移，无 scope creep。计划的产品判据（决策表行为、微秒换算、变异红）全部原样通过。

## Issues Encountered
- `<automated>` 块的 `cd /Users/coderstory/dev/pic` 是规划期主 checkout 路径 —— 按编排者指示（Wave 1-4 教训 #8）重锚到本 worktree 根执行，命令体逐字不变。
- Bash 沙箱拒跑过长复合命令：验证块按步骤拆分执行（预备/构建/绿跑/门禁/变异/红跑/恢复/复绿），每步输出与计划判据一一对应。

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- 06-03（TranscodeQueue）可直接消费：`ExternalToolLocator.locate() → FFmpegToolStatus` 拒绝起跑；stdout 行 → `ProgressParser.parseChunk → percent(snapshot:durationSeconds:)` 喂进度条。
- 06-04 据此置灰转码入口（Phase 5 的 FFmpegAvailability PATH-only 判定收编为本 locator 薄委托，D-17）。
- 本 plan 零 ffmpeg 调用、零真跑 which；活体装配与 `PIC_TRC_*` 证据行在 06-03/06-05。
- ⚠️ 按计划未跑 `bash test.sh`（统一校验在 06-05）。

---
*Phase: 06-transcode*
*Completed: 2026-10-03*
