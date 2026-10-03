---
phase: 04-media-library
verified: 2026-10-03T12:45:09Z
status: human_needed
score: 1/5 must-haves verified
covered_files:
  - .planning/phases/04-media-library/04-01-PLAN.md
  - .planning/phases/04-media-library/04-01-SUMMARY.md
  - .planning/phases/04-media-library/04-02-PLAN.md
  - .planning/phases/04-media-library/04-02-SUMMARY.md
  - .planning/phases/04-media-library/04-03-PLAN.md
  - .planning/phases/04-media-library/04-03-SUMMARY.md
  - .planning/phases/04-media-library/04-04-PLAN.md
  - .planning/phases/04-media-library/04-04-SUMMARY.md
  - .planning/phases/04-media-library/04-05-PLAN.md
  - .planning/phases/04-media-library/04-05-SUMMARY.md
  - .planning/phases/04-media-library/04-06-PLAN.md
  - .planning/phases/04-media-library/04-06-SUMMARY.md
  - .planning/phases/04-media-library/evidence/media-library.log
  - .planning/phases/04-media-library/evidence/rotation-wiring.log
  - .planning/phases/04-media-library/evidence/test-sh-phase4.log
  - .planning/spike/MediaLibraryDriver.swift
  - .planning/spike/RotationWiringDriver.swift
  - Sources/PicApp/App/MenuContentView.swift
  - Sources/PicApp/AppDelegate.swift
  - Sources/PicApp/FolderPicker.swift
  - Sources/PicApp/PicApp.swift
  - Sources/PicCore/App/FolderRequestPolicy.swift
  - Sources/PicCore/App/MenuItem.swift
  - Sources/PicCore/Media/LibraryAvailability.swift
  - Sources/PicCore/Media/MediaCoordinator.swift
  - Sources/PicCore/Media/MediaLibrary.swift
  - Sources/PicCore/Media/VideoAssetProbe.swift
  - Sources/PicCore/Media/VideoItem.swift
  - Sources/PicCore/Playback/PlaybackRouter.swift
  - Sources/PicCore/Playback/PlayerController.swift
  - Sources/PicCore/Playback/RotationController.swift
  - Sources/PicCore/Playback/SystemRotationScheduler.swift
  - Sources/PicCore/Render/WallpaperWindowController.swift
  - Sources/PicCore/State/SettingsStore.swift
  - Tests/PicCoreTests/FolderRequestPolicyTests.swift
  - Tests/PicCoreTests/LibraryAvailabilityTests.swift
  - Tests/PicCoreTests/MediaCoordinatorTests.swift
  - Tests/PicCoreTests/MediaFixtureTree.swift
  - Tests/PicCoreTests/MediaLibraryTests.swift
  - Tests/PicCoreTests/MenuBarModelTests.swift
  - Tests/PicCoreTests/PlayModeTests.swift
  - Tests/PicCoreTests/PlaybackRouterTests.swift
  - Tests/PicCoreTests/PlayerControllerFreezeTests.swift
  - Tests/PicCoreTests/RotationControllerTests.swift
  - scripts/make-media-fixture-tree.sh
  - scripts/probe-media-library.sh
  - scripts/probe-rotation-wiring.sh
  - test.sh
covered_digest: "v2:sha256:c738fde177d82ded146a4fbb5e660c6bd5b7af6e9c36cbd31585cc925617f9c9"
behavior_unverified: 4
behavior_unverified_items:
  - truth: "SC1 —— 首次启动直接弹出文件夹选择框，选完立即开始播放递归子目录视频"
    test: "清掉 defaults（或新用户）启动 app，观察是否无引导直接弹 NSOpenPanel；选定含嵌套子目录的文件夹"
    expected: "面板立即出现；选完目录后该目录及递归子目录的视频当场起播"
    why_human: "装配链（bootstrapAfterWiring → requestFolderIfNeeded → rescanAndApply → router.start）只在源码层核过、各环节单测绿；app 级活体证据因锁屏未采集（PIC_ROT_APP_LAUNCH informational=1 reason=app-launch-blocked-by-locked-screen），且 NSOpenPanel 弹出与真实播放是 GUI 运行时行为"
  - truth: "SC2 后半句 —— 扩展名对但解不出视频轨的文件被排除（真实 AVFoundationAssetProbe 路径）"
    test: "生成 fixtures 后以 MEDIA=present 跑媒体库探针（或对含 broken.mp4 的目录做一次真扫描）"
    expected: "ASCII 文本内容的 broken.mp4 不进 items，MEDIA_TRACER_PROBE_REJECTED ≥ 1"
    why_human: "单测的 broken.mp4 排除用的是 FakeAssetProbe（证明 MediaLibrary 服从探针拒绝）；已入库 evidence 是 MEDIA=absent + 全收 FakeProbe 跑的（PROBE_REJECTED=0）。真实 AVFoundationAssetProbe 拒绝坏文件这条路径没有任何测试或活体证据跑过"
  - truth: "SC4 —— 下次启动自动读取已配置文件夹并开始播放"
    test: "配置好目录并确认在播后退出，重新启动 app"
    expected: "不弹面板，直接读取已配置目录并开始播放"
    why_human: "启动序列顺序（bootstrap → requestFolderIfNeeded → rescanAndApply → startWallpaper）写死在 AppDelegate 且各 PicCore 环节有单测，但 AppDelegate 装配本身无测试、无活体证据（锁屏）；跨进程的 UserDefaults 读取 → 起播是运行时状态迁移"
  - truth: "SC5 —— 无可用视频/文件夹被删后壁纸窗口隐藏、露出系统原壁纸（真实窗口层）"
    test: "播放中把源文件夹改名/移走，触发重新扫描；观察桌面"
    expected: "壁纸窗口撤下、系统原壁纸露出，无黑屏、不崩溃；文件夹恢复 + 重新扫描后壁纸回来"
    why_human: "决策纯函数（6 用例）与协调器执行（5 用例，含恢复路径）用的是 fake presenting/stopping；WallpaperWindowController.hide() 的真实 orderOut 效果与「露出系统原壁纸」是屏幕级运行时行为，探针 evidence 只覆盖 attach/teardown 可见性，未覆盖 hide()"
deferred:
  - truth: "SOURCE-08 —— 用户切换文件夹后立即播放新目录（用户侧入口）"
    addressed_in: "Phase 5"
    evidence: "Phase 5 Notes 明示「本 Phase 的『选择…』按钮复用同一个 NSOpenPanel」；04-04-SUMMARY:285 记录「SOURCE-08 的入口在设置窗，机制已就位」。机制（store.sourceFolder = path → rescanAndApply → setItems 重置索引 → router.start）已在本 Phase 落地并有单测"
  - truth: "SC3 —— 三种模式 / 轮换时间的用户切换界面"
    addressed_in: "Phase 5"
    evidence: "Phase 5 Success Criteria 3「单循环 → 轮换时间整行置灰」隐含模式切换控件在设置窗；Phase 4 只交付引擎（模式语义 + 当场生效已由 testModeAndIntervalChangesTakeEffectOnNextAdvance 锁住）"
human_verification:
  - test: "首启弹框 + 选完立即播（SC1）"
    expected: "无引导直接弹文件夹选择框；选含递归子目录视频的文件夹后当场起播"
    why_human: "GUI 运行时行为；活体证据因锁屏未采集"
  - test: "真实探针拒绝坏文件（SC2 后半句）"
    expected: "文本内容的 broken.mp4 被排除，PROBE_REJECTED ≥ 1"
    why_human: "所有自动化证据用的都是 FakeAssetProbe；真实 AVFoundation 探针从未对坏文件跑过"
  - test: "菜单「立即下一个」端到端（SC3）"
    expected: "播放中点击后当场换片，不出现绕过仲裁器把已暂停播放器拉起的情况"
    why_human: "菜单点击 → 闭包注入 → 轮换推进在模型层有单测，但真实菜单交互是 GUI 行为"
  - test: "重启自动播放（SC4）"
    expected: "已配置目录时重启不弹框、直接起播"
    why_human: "跨进程持久化 + 启动装配是运行时状态迁移"
  - test: "删目录降级 + 恢复（SC5）"
    expected: "壁纸窗口隐藏露出系统原壁纸（无黑屏、不崩）；恢复目录 + 重新扫描后壁纸回来"
    why_human: "窗口层 orderOut 与视觉结果需要真人看屏幕"
---

# Phase 4: 媒体库与轮换 Verification Report

**Phase Goal:** 用户指定一个文件夹，app 递归扫出里面所有能播的视频，按他选的模式循环/随机播放，到点就切；文件夹没了就干净地让出桌面，露出系统原壁纸。
**Verified:** 2026-10-03T12:45:09Z
**Status:** human_needed
**Re-verification:** No — initial verification

> **MVP mode 格式提示（不阻塞）**：本 phase 在 ROADMAP 标 `Mode: mvp`，但 goal 不是标准 User Story 格式（"As a …, I want to …, so that …"）。goal 本身是用户流描述，本报告按其用户流 + SC1-5 做了 User Flow Coverage；若要走严格 MVP 校验格式，可运行 `/gsd mvp-phase 4` 重排 goal。

## 实测复跑（2026-10-03，本机）

| 命令 | 结果 | 状态 |
| --- | --- | --- |
| `swift test` | Executed 124 tests, 0 failures | ✓ PASS（基线 113 + 11 条 Phase 6 新增 = 超集全绿） |
| `bash test.sh` | 通过 69 / 失败 0 / 跳过 0 | ✓ PASS（与 04-06 基线一致） |

注：`swift test` 的 124 对 evidence 里记录的 113 —— 差值 11 条是 Phase 6（06-01/06-02）已合入本分支的 TranscodeCandidateFilter / ConvertedLibrary / ProgressParser / ExternalToolLocator 用例；Phase 4 的全部用例仍在且全绿。Phase 4 源码零 ffmpeg（ffmpeg 只出现在 `Sources/PicCore/Transcode/`，属 Phase 6）。

## User Flow Coverage

用户流：指定文件夹 → 递归扫出可播视频 → 按模式循环/随机、到点就切 → 文件夹没了干净让出桌面。

| 步骤 | Expected | Evidence | 状态 |
| --- | --- | --- | --- |
| 指定一个文件夹 | 首启无引导直接弹 NSOpenPanel；之后经设置窗切换（Phase 5 入口） | AppDelegate.swift:380-422 `bootstrapAfterWiring`/`requestFolderIfNeeded`；FolderRequestPolicy.swift（纯函数）；FolderPicker.swift（全仓唯一 NSOpenPanel，test.sh 常驻判据 ✅） | ⚠️ 装配已核 + 单测绿，app 级活体未采（锁屏） |
| 递归扫出能播的视频 | 三层嵌套、大小写扩展名、Converted/ 排除、坏文件排除、缓存 | MediaLibrary.swift（enumerator 递归 + 白名单 + 精确目录名排除 + symlink 越界 + probe + 缓存）；MediaLibraryTests 9 条全绿 | ⚠️ 白名单/递归/缓存已验；真实探针拒坏文件未跑过（见 SC2） |
| 按模式循环/随机、到点就切 | 三模式语义正确、同 seed 可复现、到点推进不等播完 | RotationController.swift + RotationControllerTests 7 条、PlayModeTests 5 条、PlaybackRouterTests 5 条全绿；test.sh「轮换器零播放进度读取」4 项常驻 ✅ | ✓ |
| 文件夹没了干净让出桌面 | 窗口隐藏露系统原壁纸、不黑屏不崩、可恢复 | LibraryAvailability.swift（纯函数）+ MediaCoordinator.swift + WallpaperWindowController.hide()/show()（orderOut 保留窗口）；LibraryAvailabilityTests 6 + MediaCoordinatorTests 5 全绿 | ⚠️ 决策与执行层已验；真实窗口层/视觉未验 |

## Goal Achievement — Observable Truths（ROADMAP SC1-5）

| # | Truth | 状态 | Evidence |
| --- | --- | --- | --- |
| 1 | SC1 首启直接弹文件夹选择框（无引导）；选完立即播放递归子目录视频 | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | 装配链完整（applicationDidFinishLaunching → Task{bootstrapAfterWiring} → requestFolderIfNeeded → rescanAndApply → startWallpaper，顺序写死）；FolderRequestPolicyTests 5 条、MediaLibraryTests 递归 2 条、PlaybackRouterTests.testStartLoadsFirstItem 全绿。app 级活体证据因锁屏未采集（rotation-wiring.log 自标 informational） |
| 2 | SC2 只识别 MP4/MOV/M4V，且排除扩展名对但解不出视频轨的文件 | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | 白名单半句 ✓ VERIFIED（testWhitelistAcceptsOnlyMp4MovM4vCaseInsensitively，B.MOV/d.MP4 收、txt/mkv/avi/webm 排除）。坏文件半句：MediaLibrary 服从探针拒绝已验（testFileWithAllowedExtensionButNoVideoTrackIsRejected，FakeAssetProbe），但真实 AVFoundationAssetProbe 从未对坏文件跑过 —— 单测全用 fake，evidence 是 MEDIA=absent + 全收 FakeProbe（PROBE_REJECTED=0） |
| 3 | SC3 三种模式切换当场生效；到点就切不等播完；「立即下一个」即时生效 | ✓ VERIFIED | 行为级单测全绿：testLoopSingle/LoopList/ShuffleVisitsEveryItemExactlyOncePerRound、testShuffleOrderIsIdenticalForSameSeedAndDiffersForAnotherSeed、testRotationElapsedAdvancesWithoutWaitingForPlayback（到点回调推进 + 重排程，全程零播放器）、testModeAndIntervalChangesTakeEffectOnNextAdvance、testAdvanceNowLoadsNextInLoopList。结构保证：RotationController 零 player 引用（test.sh 4 项常驻判据 ✅）。菜单→闭包链模型层已测（testPerformNextVideoCallsOnlyItsInjectedClosure）；真实菜单点击列入人工项 |
| 4 | SC4 下次启动自动读取已配置文件夹并播放；换文件夹立即播新目录；「重新扫描」可用且结果被缓存 | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | 机制全在：SettingsStore.sourceFolder 持久化（SettingsStoreTests 13 条含 7 键冻结）、启动序列先取目录再扫描最后起播、rescanFolderNow() 显式 invalidateCache（AppDelegate.swift:479-483）、缓存语义 testSecondScanUsesCacheAndInvalidateForcesRescan 绿。app 级重启自动播无活体证据；换文件夹的用户入口（设置窗按钮）按计划移交 Phase 5（deferred） |
| 5 | SC5 无可用视频/文件夹被删被移 → 壁纸窗口隐藏露出系统原壁纸（不留黑屏不崩溃） | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | 决策纯函数穷举（LibraryAvailabilityTests 6 条）；执行层 stop+hide+恢复（MediaCoordinatorTests 5 条含 testRecoveryFromHiddenToPlayingResumesWithoutRestart）；hide()=orderOut 保留窗口、show()=orderFrontRegardless（WallpaperWindowController.swift:54-63）与 teardown 销毁语义并存；PlayerControllerFreezeTests 锁八个既有签名 + stop()。真实窗口 orderOut 效果与「露出系统原壁纸」需真人看屏幕（探针只覆盖 attach/teardown 可见性） |

**Score:** 1/5 truths verified（4 条 present + wired，行为未活体验证）

### Deferred Items（Step 9b — 后续 phase 明确接管，不算 gap）

| # | Item | Addressed In | Evidence |
| --- | --- | --- | --- |
| 1 | SOURCE-08 用户切换文件夹的入口（设置窗「选择…」按钮） | Phase 5 | Phase 5 Notes「本 Phase 的『选择…』按钮复用同一个 NSOpenPanel」；04-04-SUMMARY:285「SOURCE-08 的入口在设置窗，机制已就位」 |
| 2 | 模式/轮换时间的用户切换界面 | Phase 5 | Phase 5 SC3「单循环 → 轮换时间整行置灰」；Phase 4 只交付引擎，当场生效语义已由单测锁定 |

## Required Artifacts

全部 6 个 plan 的 artifacts 均存在、实质、有测试或判据接线：

| Artifact | 状态 | Details |
| --- | --- | --- |
| `Sources/PicCore/Media/MediaLibrary.swift`（176 行） | ✓ VERIFIED | 递归/白名单/Converted/symlink/entryCap/缓存全实现，9 条单测 |
| `Sources/PicCore/Media/VideoAssetProbe.swift` / `VideoItem.swift` | ✓ VERIFIED | 可注入 seam；真实探针行为见 SC2 保留项 |
| `Sources/PicCore/Playback/RotationController.swift`（198 行） | ✓ VERIFIED | 三模式 + 洗牌袋 + 注入调度/随机源，7 条单测 |
| `Sources/PicCore/Playback/SystemRotationScheduler.swift` | ✓ VERIFIED | 主 runloop 定时器，schedule 内先 cancel |
| `Sources/PicCore/Media/LibraryAvailability.swift` / `MediaCoordinator.swift` | ✓ VERIFIED | 纯函数决策 6 用例 + 执行层 5 用例（含恢复） |
| `Sources/PicCore/Playback/PlaybackRouter.swift` | ✓ VERIFIED | onAdvance→VideoLoading seam，5 条单测 |
| `Sources/PicCore/App/MenuItem.swift` / `FolderRequestPolicy.swift` | ✓ VERIFIED | 5 菜单项全 allCases 遍历；纯函数 5 用例 |
| `Sources/PicApp/FolderPicker.swift` | ✓ VERIFIED | 全仓唯一 NSOpenPanel（test.sh 常驻判据 ✅） |
| `Sources/PicApp/AppDelegate.swift`（530 行） | ✓ WIRED | 唯一装配点：bootstrap 顺序、rescanAndApply、dispatchPlayback、nextVideoNow、rescanFolderNow、三个 seam 适配器 |
| `test.sh` Phase 4 两段 | ✓ VERIFIED | 19 项新门禁全绿（源码层 8 + evidence 层 11） |
| `evidence/{media-library,rotation-wiring,test-sh-phase4}.log` | ✓ VERIFIED | 关键行齐全，零媒体文件名泄漏 |

## Key Link Verification

| From | To | Via | 状态 |
| --- | --- | --- | --- |
| 菜单点击 | RotationController.advanceNow | MenuContentView → MenuBarModel.perform → AppDelegate.nextVideoNow | ✓ WIRED（模型层单测 + 装配源码核） |
| RotationController.onAdvance | PlayerController.load | PlaybackRouter → PlayerLoadingAdapter（load 后重放仲裁决策） | ✓ WIRED（PlaybackRouterTests + 适配器源码） |
| 扫描结果 | 窗口/播放器动作 | MediaLibrary.scan → LibraryAvailability.evaluate → MediaCoordinator.apply → hide/stop 或 show+router.start | ✓ WIRED（MediaCoordinatorTests + dispatchPlayback 源码） |
| 首启 | 弹框→起播 | applicationDidFinishLaunching → Task{bootstrapAfterWiring()} → requestFolderIfNeeded → rescanAndApply → startWallpaper | ✓ WIRED（顺序写死在源码；app 级行为归人工项） |
| 重新扫描 | 缓存失效+重扫 | rescanFolderNow → invalidateCache → rescanAndApply | ✓ WIRED |

## Data-Flow Trace (Level 4)

| 值 | 来源 | 状态 |
| --- | --- | --- |
| report.items（播放列表） | FileManager.enumerator 实遍历 + probe | ✓ FLOWING |
| LibraryState | LibraryAvailability.evaluate（扫描结果实时输入） | ✓ FLOWING |
| 轮换下一条 | RotationController.advance（无静态回退） | ✓ FLOWING |
| store.sourceFolder | NSOpenPanel 选择 → persist → resolvedFolderURL | ✓ FLOWING（无硬编码路径） |
| 唯一静态默认 | PlayMode 默认 .loopSingle / interval 300（Seed，合法默认值，可被持久化值覆盖） | ✓ 合法 |

## Test Quality Audit

| 维度 | 结果 |
| --- | --- |
| 禁用测试 | 0（全仓无 .skip/xit/ignore/pending） |
| 循环测试 | 0（fixture 期望值手写：items==6、rejected==1 等，非系统自生成） |
| 断言强度 | 值级/行为级为主（XCTAssertEqual 具体值、期望序列 [1,0,1,2]），无「只判存在」的空判据 |
| 变异反向验证 | 04-02 两处、04-03 一处、04-05 一处（各 SUMMARY 记录，判据名依赖 nextIndex/bag/refillBag 等冻结名） |
| 数量 | Phase 4 新增 47 个测试函数，全部在本机复跑中通过 |

## Probe Execution（Step 7c）

| Probe | 命令 | 结果 | 状态 |
| --- | --- | --- | --- |
| scripts/probe-media-library.sh | （未复跑） | — | ? SKIP |
| scripts/probe-rotation-wiring.sh | （未复跑） | — | ? SKIP |

SKIP 理由：本次验证红线为「只读源码，可跑 swift test / test.sh」；两个探针会在工作树建/删 fixture 目录、收紧权限，且媒体库探针要起真实 NSWindow（锁屏环境下不可靠）。作为替代：test.sh 的「Phase 4：探针 evidence」11 项常驻门禁对已入库 evidence 关键行做了存在性 + 零文件名泄漏校验，本机复跑全绿。

## Requirements Coverage（16/16 有交代）

| Requirement | Source Plan | 状态 | Evidence |
| --- | --- | --- | --- |
| SOURCE-01 | 04-04 | ✓ SATISFIED | FolderPicker + requestFolderIfNeeded + persist（app 级弹框归人工项） |
| SOURCE-02 | 04-01 | ✓ SATISFIED | testRecursionFindsClipThreeDirectoriesDeep（专门用例） |
| SOURCE-03 | 04-01 | ✓ SATISFIED | 白名单大小写不敏感用例 + 反证（txt/mkv/avi/webm） |
| SOURCE-05 | 04-04 | ✓ SATISFIED | rescanFolderNow 显式 invalidateCache；缓存语义单测 |
| SOURCE-06 | 04-03 | ✓ SATISFIED（逻辑层） | 纯函数 6 用例 + 协调器 5 用例；视觉结果归人工项 |
| SOURCE-07 | 04-05 | ✓ SATISFIED（机制） | 启动序列 + SettingsStore 持久化；重启活体归人工项 |
| SOURCE-08 | 04-04 | ◐ PARTIAL→deferred | 机制就位（换目录即 setItems 重置 + 起新播）；用户入口移交 Phase 5（有明文记录） |
| PLAY-03/04/05 | 04-02 | ✓ SATISFIED | 三模式行为单测 + 同 seed 可复现判据 |
| PLAY-06 | 04-02 | ✓ SATISFIED | testRotationElapsedAdvancesWithoutWaitingForPlayback + 轮换器零播放进度常驻判据 |
| MENUBAR-04 | 04-04 | ✓ SATISFIED | 菜单项 + advanceNow 链；点击活体归人工项 |
| MENUBAR-05 | 04-04 | ✓ SATISFIED | 菜单项 + invalidateCache 重扫链 |
| SYS-03 | 04-04 | ✓ SATISFIED | FolderRequestPolicy 纯函数 5 用例 + 首启接线 |
| TEST-02 | 04-01 | ◐ PARTIAL | 递归/白名单/转码产物排除/目录不存在/entryCap 有用例；**空目录扫描与无权限（errorHandler continue）两子项无用例**（代码路径在：空目录→0 items→noPlayableVideos；无权限→errorHandler 返回 true 继续）—— 见 Gaps/Warnings |
| TEST-03 | 04-02 | ✓ SATISFIED | 三模式/到点就切/随机一轮不重复全覆盖 |

无 ORPHANED 需求：REQUIREMENTS.md 映射到 Phase 4 的 16 个 ID 全部出现在各 plan 的 requirements 字段。

### Decision Coverage（软门禁，不阻塞）

22 条决策中 21 条在交付物中可循；D-20（按 PID 认领窗口，不按 layer，Phase 1/2/3 继承约束）未在 Phase 4 产物中出现 —— 属继承约束，Phase 4 窗口逻辑未触碰认领策略，软警告记录在案。

## Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| --- | --- | --- | --- | --- |
| （无） | — | 零 TBD/FIXME/XXX/TODO/PLACEHOLDER；零空实现；零 console-only；零禁用测试 | — | — |

## Behavioral Spot-Checks

| Behavior | Command | Result | 状态 |
| --- | --- | --- | --- |
| swift test 全量 | `swift test` | 124/124 pass, 0 failures | ✓ PASS |
| test.sh 全量门禁 | `bash test.sh` | 69 pass / 0 fail / 0 skip | ✓ PASS |
| Media/ 零 AppKit/SwiftUI | test.sh 常驻判据 | ✅ ×2 | ✓ PASS |
| 轮换器零播放进度读取 | test.sh 常驻判据（AVPlayer/arbiterCurrentPosition/currentTime/AVPlayerItemDidPlayToEndTime） | ✅ ×4 | ✓ PASS |
| 面板唯一落点 | test.sh 常驻判据（NSOpenPanel( 全仓 =1） | ✅ | ✓ PASS |
| Phase 4 evidence 关键行 | test.sh p4_line ×11 | ✅ | ✓ PASS |

## Human Verification Required

见 frontmatter `human_verification`（5 项：SC1 首启弹框即播 / SC2 真实探针拒坏文件 / SC3 菜单立即下一个端到端 / SC4 重启自动播 / SC5 删目录降级与恢复）。其中 SC2 那项也可机械化补齐：加一条用真实 AVFoundationAssetProbe 对文本 .mp4 的用例，或生成 fixtures 后以 MEDIA=present 复跑媒体库探针。

## Gaps Summary

无 BLOCKER。四条 SC 因「锁屏导致 app 级活体证据未采集」处于 present+wired、行为未活体验证状态（PicCore 侧全部有行为级单测且本机复跑全绿），按流程路由人工验证。两个 Warning 级保留项：

1. **TEST-02 子项缺测**（⚠️ Warning）：空目录扫描、无权限 errorHandler 路径无用例。建议在 Phase 5/6 补测或并入探针。
2. **REQUIREMENTS.md 状态滞后**（ℹ️ Info）：Phase 4 的 16 行仍标 Pending（Phase 2/3 有 Done/Partial 惯例，建议随本验证更新）。

另记：evidence/media-library.log 的 MEDIA_TRACER_ROOT 指向执行时的 agent worktree 路径（历史事实，不影响判据）。

---

_Verified: 2026-10-03T12:45:09Z_
_Verifier: Claude (gsd-verifier)_
