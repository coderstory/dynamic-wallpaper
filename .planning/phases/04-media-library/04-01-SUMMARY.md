---
phase: 04-media-library
plan: 01
subsystem: media
tags: [swift, avfoundation, filemanager, swiftpm, xctest]

# Dependency graph
requires:
  - phase: 02-playback-core
    provides: PlayerController（load/looper 队列顺序）与 WallpaperWindowController（attach/teardown）—— tracer 纵向切片的末端两环
provides:
  - MediaLibrary 递归扫描内核（白名单 / Converted 精确排除 / 符号链接越界排除 / entryCap / 缓存 / scanCount）
  - VideoItem + VideoAssetProbe（可注入协议）+ AVFoundationAssetProbe（异步 loadTracks，无弃用警告）
  - MediaLibraryReport —— 七个独立计数的扫描读数（D-17）
  - scripts/make-media-fixture-tree.sh —— 幂等 fixture 树生成器
  - scripts/probe-media-library.sh + evidence/media-library.log —— tracer 活体证据（含 D-22 的 informational=1 真实目录抽样）
affects: [04-03 降级路径, 04-05 装配, 05-settings 空态显示, 06-transcode Converted 排除]

# Actuals (#2632)
actuals:
  tokens: 9772   # chars/4 over the 9 changed files（含 fixture 脚本内嵌的 ~6KB base64 种子）
  tasks: 3
  commits: 3

# Tech tracking
tech-stack:
  added: []   # 零第三方依赖不变
  patterns:
    - 可注入探针（protocol VideoAssetProbe）让单测完全不碰 AVFoundation 与 fixtures/
    - 每个过滤计数一个独立字段、探针每行一个数（D-17 拆行打点）
    - fixture 脚本内嵌可播放种子（base64 Motion-JPEG），干净 worktree 上 tracer 也有真视频可载

key-files:
  created:
    - Sources/PicCore/Media/VideoItem.swift
    - Sources/PicCore/Media/VideoAssetProbe.swift
    - Sources/PicCore/Media/MediaLibrary.swift
    - Tests/PicCoreTests/MediaFixtureTree.swift
    - Tests/PicCoreTests/MediaLibraryTests.swift
    - scripts/make-media-fixture-tree.sh
    - .planning/spike/MediaLibraryDriver.swift
    - scripts/probe-media-library.sh
    - .planning/phases/04-media-library/evidence/media-library.log
  modified: []

key-decisions:
  - "fixture 树的视频文件必须是普通文件（内嵌可播放种子），不能是符号链接：扫描器的 resourceValues 层把符号链接一律排除（T-04-01 缓解），纯占位字节又让 AVPlayerLooper 入不了队（本机实测 0）—— 两者都会让 MEDIA_TRACER_PLAN=playing 永远到不了"
  - "根不是目录时用显式 isDirectory 检查抛 .folderUnreadable：本机实测 FileManager.enumerator(at:) 对文件路径返回非 nil，仅靠『枚举器为 nil』挡不住这条错误路径"
  - "变异红日志的编译错误判别改为 :line:col: error: / error: SwiftCompile 形态：本机 XCTest 的断言失败行本身带 error: -[ 前缀，裸 grep 'error:' 计数为 0 的门对断言型红光不可满足（D-16 意图保留）"

patterns-established:
  - "变异插桩行（enumOptions 声明 / caseInsensitiveCompare 合取）必须是整语句、行尾注释式标记，编译器 var-never-mutated 警告是插桩点的预期噪声"

requirements-completed: [SOURCE-02, SOURCE-03]

# Coverage metadata (#1602)
coverage:
  - id: D1
    description: "递归扫描进入子目录：三层嵌套 sub/deep/deeper/d.MP4 与中文+空格目录 视频壁纸/e.mp4 都进 items（SOURCE-02）"
    requirement: SOURCE-02
    verification:
      - kind: unit
        ref: Tests/PicCoreTests/MediaLibraryTests.swift#testRecursionFindsClipThreeDirectoriesDeep
        status: pass
      - kind: unit
        ref: Tests/PicCoreTests/MediaLibraryTests.swift#testRecursionAlsoFindsClipUnderDirectoryWithCjkAndSpaceName
        status: pass
      - kind: other
        ref: "mutation: MUT-P4-RECURSION（加 .skipsSubdirectoryDescendants）→ 该用例转红，6 条断言失败、0 条编译错误"
        status: pass
    human_judgment: false
  - id: D2
    description: "扩展名白名单只收 mp4/mov/m4v 且大小写不敏感；txt/mkv/avi/webm 一律排除（SOURCE-03）"
    requirement: SOURCE-03
    verification:
      - kind: unit
        ref: Tests/PicCoreTests/MediaLibraryTests.swift#testWhitelistAcceptsOnlyMp4MovM4vCaseInsensitively
        status: pass
    human_judgment: false
  - id: D3
    description: "扩展名对但解不出视频轨的文件被排除（D-08）—— broken.mp4 计入 rejectedByProbe"
    verification:
      - kind: unit
        ref: Tests/PicCoreTests/MediaLibraryTests.swift#testFileWithAllowedExtensionButNoVideoTrackIsRejected
        status: pass
    human_judgment: false
  - id: D4
    description: "Converted/ 子树按目录名精确匹配整棵排除；converted-lower/keep.mp4 仍被收（TRANS-05 第一层 / D-21）"
    verification:
      - kind: unit
        ref: Tests/PicCoreTests/MediaLibraryTests.swift#testConvertedDirectorySubtreeIsExcludedByExactDirectoryName
        status: pass
      - kind: other
        ref: "mutation: MUT-P4-CONVERTED（精确匹配改子串匹配）→ 该用例转红，3 条断言失败、0 条编译错误"
        status: pass
    human_judgment: false
  - id: D5
    description: "根外符号链接排除（T-04-01）、缓存与显式失效（SOURCE-05 机制）、folderMissing/folderUnreadable 两条错误路径、entryCap 截断如实上报（T-04-02）"
    verification:
      - kind: unit
        ref: Tests/PicCoreTests/MediaLibraryTests.swift#testSymlinkPointingOutsideRootIsExcluded
        status: pass
      - kind: unit
        ref: Tests/PicCoreTests/MediaLibraryTests.swift#testSecondScanUsesCacheAndInvalidateForcesRescan
        status: pass
      - kind: unit
        ref: Tests/PicCoreTests/MediaLibraryTests.swift#testMissingFolderAndNonDirectoryRootThrowDistinctErrors
        status: pass
      - kind: unit
        ref: Tests/PicCoreTests/MediaLibraryTests.swift#testEntryCapTruncatesAndReportsSkippedByEntryCap
        status: pass
    human_judgment: false
  - id: D6
    description: "fixture 树构造脚本：幂等、结构与单测 helper 逐项一致、noperm 权限退出前复原、零整词复制命令、零真实目录字面量"
    verification:
      - kind: other
        command: "bash scripts/make-media-fixture-tree.sh 两次 → MEDIA_FIXTURE_TREE_OK（MEDIA_TREE_FILES=14 幂等相等，NOPERM_MODE=drwxr-xr-x，REALDIR_LITERAL=0，CP_CMD=0）"
        status: pass
    human_judgment: false
  - id: D7
    description: "tracer 活体证据：扫描出七个分开的过滤计数 → 首条进 PlayerController（looper 入队 3 项）→ 壁纸窗 attach 后可见、teardown 后不可见 → 缓存让 scanCount 保持 1；evidence 零媒体文件名、零 Phase 2/3 路径"
    verification:
      - kind: other
        command: "bash scripts/probe-media-library.sh → MEDIA_TRACER_EVIDENCE_OK（evidence 18 行，PLAYER_ITEMS=3，VIS_ATTACH=1，VIS_TEARDOWN=0，SCAN_COUNT=1，FILENAME_LEAK=0，FOREIGN_EVIDENCE_PATH=0）"
        status: pass
    human_judgment: false
  - id: D8
    description: "真实 42GB 目录只做一次一层非递归抽样计时并标 informational=1，不进任何判据（D-22）"
    verification:
      - kind: other
        command: "evidence/media-library.log:18 → MEDIA_REALDIR_SAMPLE informational=1 entries=484 seconds=0.0 recursion=disabled reason=D-22（本机顶层实测 484，一致）"
        status: pass
    human_judgment: false

# Metrics
duration: 86 min
completed: 2026-10-03
status: complete
---

# Phase 4 Plan 1: 媒体库扫描内核 Summary

**MediaLibrary 递归扫描内核（enumerator 递归 / mp4-mov-m4v 白名单 / Converted 目录名精确排除 / 视频轨探针校验 / 缓存 / entryCap）+ 9 条单测 + 两处变异反向验证 + 幂等 fixture 树脚本 + 一条命令的 tracer 活体证据（扫描→首条→播放器→壁纸窗可见→teardown 不可见）**

## Performance

- **Duration:** 86 min
- **Started:** 2026-10-03T09:38:00Z
- **Completed:** 2026-10-03T11:04:00Z
- **Tasks:** 3（全部完成）
- **Files modified:** 9（全部新建；产品侧零改动既有文件）

## Accomplishments

- 扫描内核一次建对：`sub/deep/deeper/d.MP4`（三层嵌套）与 `视频壁纸/e.mp4`（中文+空格目录）都有专门用例；`B.MOV` / `d.MP4` 证明大小写不敏感；`converted-lower/keep.mp4` 证明排除是目录名**精确匹配**不是子串
- 两处变异反向验证均为「断言失败型红光」：`MUT-P4-RECURSION` 6 条断言失败、`MUT-P4-CONVERTED` 3 条断言失败，两者编译错误数均为 0；恢复后 `cmp -s` 逐字节一致
- tracer 活体证据齐全：`PLAYER_ITEMS=3`（等 400ms 后 looper 真入队）、`WINDOW_VISIBLE_AFTER_ATTACH=1`、`WINDOW_VISIBLE_AFTER_TEARDOWN=0`（04-03 降级路径的机器前置读数）、`SCAN_COUNT=1`（缓存生效）
- 真实目录只被一层非递归抽样计时一次（`entries=484`，与本机 2026-10-03 实测一致），标 `informational=1`，不进任何判据
- 回归：全量 `swift test` **76 tests, 0 failures**（既有 67 + 新增 9），`swift build` 退出码 0

## Task Commits

Each task was committed atomically:

1. **Task 1: MediaLibrary 扫描内核 + 9 条单测** - `01c4310` (feat)
2. **Task 2: fixture 树构造脚本** - `f7b213f` (feat)
3. **Task 3: tracer 活体证据（driver + probe + evidence）** - `da8b504` (test)

**Plan metadata:** 本 SUMMARY 提交（docs）

## Files Created/Modified

- `Sources/PicCore/Media/VideoItem.swift` - 只有一个 `url` 字段的值类型
- `Sources/PicCore/Media/VideoAssetProbe.swift` - 可注入协议 + `AVFoundationAssetProbe`（异步 `loadTracks`，无弃用警告）
- `Sources/PicCore/Media/MediaLibrary.swift` - `@MainActor` 扫描内核 + `MediaLibraryReport`（七个独立计数）+ `MediaLibraryError`；零 AppKit / 零 SwiftUI / 零 `contentsOfDirectory` / 零 `absoluteString`
- `Tests/PicCoreTests/MediaFixtureTree.swift` - 非 XCTestCase 的树构建 helper（临时目录 + 显式 remove）
- `Tests/PicCoreTests/MediaLibraryTests.swift` - 9 条行为用例 + 文件内 `FakeAssetProbe`
- `scripts/make-media-fixture-tree.sh` - 幂等 fixture 树生成器（内嵌 0.5s 48x48 Motion-JPEG 种子）
- `.planning/spike/MediaLibraryDriver.swift` - throwaway tracer 驱动（与产品源一起编译）
- `scripts/probe-media-library.sh` - 建树→编译→跑 driver→落 Phase 4 自己的 evidence→追加 D-22 抽样行
- `.planning/phases/04-media-library/evidence/media-library.log` - 18 行 tracer 读数 + 1 行 informational 抽样

## Decisions Made

- **fixture 树的视频文件 = 普通文件 + 内嵌可播放种子**（偏离计划的「符号链接」写法，见 Deviation 3）：符号链接被扫描器的 resourceValues 层排除、纯占位字节让 looper 入不了队，两者都让 tracer 的 `playing` 判据永远到不了。种子是一次性用 AVAssetWriter 生成的 4.5KB Motion-JPEG（**不是 ffmpeg、不是转码测试**，不进任何自动验证路径），base64 内嵌进脚本，干净 worktree 上可复现
- **`folderUnreadable` 用显式 isDirectory 检查**（见 Deviation 2）：本机实测枚举器对文件路径返回非 nil
- **变异红日志的编译错误判别改为编译器诊断形态**（见 Deviation 4）：本机 XCTest 断言失败行自带 `error:` 前缀
- `noperm/hidden.mp4` 建为普通占位文件（而非指向缺席 fixtures 的悬空符号链接）：判据 `test -e` 对悬空符号链接为假

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] 计划的 `items.count == 5` 与自身用例清单矛盾**
- **Found during:** Task 1（写测试前核算期望读数）
- **Issue:** 计划期望读数写 `items.count == 5`（a/B.MOV/c/d/converted-lower-keep），但同一份表的 `视频壁纸/e.mp4` 行写着「收」，且 test 2 明确断言它在 items 里 —— 8 个过扩展名的文件减去 Converted 1 个、probe 拒 1 个，得 6 而非 5
- **Fix:** test 1 断言 `items.count == 6`；判据不放宽（8/1/1 三个读数原样锁住），只修正这处算术
- **Files modified:** Tests/PicCoreTests/MediaLibraryTests.swift
- **Verification:** 9 条全绿；`acceptedByExtension==8`、`excludedByConverted==1`、`rejectedByProbe==1` 均按计划数字断言
- **Committed in:** 01c4310

**2. [Rule 1 - Bug] 文件路径根挡不出 `.folderUnreadable`**
- **Found during:** Task 1（实现前实证）
- **Issue:** 计划的机制是「`enumerator == nil` → 抛 `.folderUnreadable`」，但本机实测 `FileManager.enumerator(at:)` 对**文件**路径返回非 nil 的枚举器 —— test 8 的第二条会拿不到错误
- **Fix:** 存在性检查之后加显式 `fileExists(atPath:isDirectory:)` 检查，非目录即抛 `.folderUnreadable`；枚举器为 nil 仍抛同一条错误（无权限目录的另一只手）
- **Files modified:** Sources/PicCore/Media/MediaLibrary.swift
- **Verification:** test 8 两条错误路径各自命中确切 case
- **Committed in:** 01c4310

**3. [Rule 1 - Bug] fixture 树视频文件按计划写成符号链接会让 tracer 拿不到任何条目**
- **Found during:** Task 2 前的实证（AVPlayerLooper 对占位文件 400ms 后 `items().count == 0`）
- **Issue:** 计划让脚本「从 fixtures/clip-*.mp4 建符号链接」做视频文件；但扫描器第 4 步（resourceValues）把符号链接一律排除（T-04-01 缓解本身），且干净 worktree 上 fixtures/ 不存在时这些链接全部悬空；纯占位字节又让 AVPlayerLooper 入不了队 —— `MEDIA_TRACER_PLAN=playing` / `PLAYER_ITEMS>=1` / `VISIBLE_AFTER_ATTACH=1` 三条判据全部到不了
- **Fix:** 七个视频文件写成普通文件，内容为脚本内嵌的 4.5KB Motion-JPEG 种子（`base64 -D` 解码，非整词复制命令，机械判据 `\bcp\b`==0 仍过）。种子是一次性 AVAssetWriter 生成 —— **不是 ffmpeg、不是转码**；两种 MEDIA 模式（真/假探针）下 tracer 都能走通
- **Files modified:** scripts/make-media-fixture-tree.sh
- **Verification:** `MEDIA_TRACER_PLAYABLE=8`、`PLAYER_ITEMS=3`；`MEDIA_FIXTURE_TREE_OK` 全过
- **Committed in:** f7b213f

**4. [Rule 1 - Bug] 变异红日志的 `error:` 计数门在本机 XCTest 输出格式下不可满足**
- **Found during:** Task 1 自动判据首跑（`RECURSION_TEST_IS_BLIND_OR_MUTATION_COMPILED` 误报）
- **Issue:** 计划要求红日志里 `error:` 计数 == 0 以证明「红来自断言而非编译失败」；但本机 swift 6.4 的 XCTest **断言失败行本身**带 `error: -[...] : XCTAssert...` 前缀 —— 断言型红光的 `error:` 计数恒 ≥ 1，门永远红
- **Fix:** 编译错误判别改为编译器诊断的独有形态（`:line:col: error:` 两个数字段，或 `error: SwiftCompile`）；XCTest 断言行是 `:line: error:` 单数字段，不命中。两处变异的红日志按新判别均为 0 条编译错误、6/3 条断言失败 —— D-16 的意图（红来自断言）完整保留
- **Files modified:** 仅本执行的 verify 脚本（.build 下，未入库）；产品与测试代码未动
- **Verification:** `MEDIA_LIBRARY_CORE_OK` 全过
- **Committed in:** 不适用（判据适配，无源码变更）

**5. [Rule 3 - Blocking] 计划 `<automated>` 命令硬编码主检出路径**
- **Found during:** Task 1 执行前
- **Issue:** 三个 task 的 `<automated>` 均以 `cd /Users/coderstory/dev/pic` 开头 —— 在本 worktree 里执行会校验**主检出**的代码（worktree-path-safety #4767 明确要防的缺陷）
- **Fix:** 全部 verify 以 `cd "$(git rev-parse --show-toplevel)"` 重定根到本 worktree，命令体逐字不变；外层 `perl -e 'alarm ...; exec @ARGV'` 包装换成探针脚本**内部的**同款 alarm 包装（挂死保护等价，沙箱拒绝不透明 exec 形态）
- **Files modified:** 无入库文件变更
- **Verification:** 三个 verify 各自打出 OK 行
- **Committed in:** 不适用

---

**Total deviations:** 5 auto-fixed（3 处 Rule 1 计划事实错误 + 1 处 Rule 1 判据环境适配 + 1 处 Rule 3 执行环境适配）
**Impact on plan:** 全部为让计划的**判据本身**可达成而修，无一放宽判据、无一改产物读数去凑判据。产品代码仅 Deviation 2 一处必要增强。

## Issues Encountered

- `swift build` 首跑报「closure 里引用 `lastError` 需要显式 `self`」—— 加 `self.` 后过；属常规 Swift 语法修正，不算偏离
- `MediaLibrary.swift:92` 有 `var enumOptions` never-mutated 编译警告 —— **故意保留**：那一行是变异①的插桩点（`var` 是 perl 替换的目标形状）
- 屏幕锁着不影响本 plan：全部判据都是命令行可验证的读数，无需目视

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- `MediaLibrary` 公开面已冻结（符号清单见 04-01-PLAN.md「Artifacts」节），04-03（降级）与 04-05（装配）可直接消费
- 04-03 降级的机器前置读数已备好：`MEDIA_TRACER_WINDOW_VISIBLE_AFTER_TEARDOWN=0` 证明 teardown 路径在位
- fixture 树可重复生成（`bash scripts/make-media-fixture-tree.sh`），probe 一条命令重采证据
- 遗留（登记不阻塞）：计划文本自身的 `items.count == 5` 笔误与「视频文件用符号链接」的矛盾已在本 plan 修正，后续 plan 若引用这两个数字请以本 SUMMARY 为准
- `bash test.sh` 统一校验在 04-06（本 plan 未跑，按计划的 wave 纪律）

---
*Phase: 04-media-library*
*Completed: 2026-10-03*