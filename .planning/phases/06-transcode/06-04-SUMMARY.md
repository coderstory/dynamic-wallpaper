---
phase: 06-transcode
plan: "04"
subsystem: ui
tags: [swift, swiftui, transcode, window, ffmpeg, install-pathways, locator, d-17]

# Dependency graph
requires:
  - phase: 06-transcode
    provides: TranscodeQueue（06-03：jobs / onJobsChanged / commandDisplay / run）+ ExternalToolLocator + FFmpegToolStatus（06-02）+ TranscodeCandidateFilter / TranscodeOutputNaming（06-01）
  - phase: 05-settings
    provides: SettingsView 的「维护」行「打开…」按钮 seam（05-03 建为 `.disabled(true)` 占位）+ SettingsComponents 深色令牌与字体入口 + App/FFmpegAvailability.swift 的状态卡消费面
provides:
  - TranscodeWindowView —— UI-SPEC §8 转码窗四要素（ffmpeg 徽章含路径 / 队列表文件名·格式·大小·进度·状态 / 底部可复制实际命令 / 产物规则三句）+ 工具行
  - TranscodeViewModel —— ObservableObject 包队列回调，PicCore 分层不破
  - InstallPathwaysView —— 三条安装途径逐条 + 不内置不下载尾注 + 重新检测
  - TranscodeScene —— SwiftUI Window(id "transcode", 640pt)，onAppear 重查 + 载候选
  - AppDelegate：ffmpegLocator / ffmpegAvailability / refreshFFmpegAvailability() / openTranscodeWindow() / transcodeQueue / transcodeLocator
  - App/FFmpegAvailability.swift 收编为 ExternalToolLocator 的薄委托（D-17 单一真相源）
affects: [06-05（onBatchFinished → rescanAndApply 装配 SC#5；ConvertedLibrary 合并；test.sh Phase 6 段收口）, 07-delivery]

actuals:
  tokens: 9429
  tasks: 2
  commits: 2

tech-stack:
  added: []
  patterns:
    - 「打开…」的条件分派留在装配层（AppDelegate 返回 Bool），视图只管把 openWindow 动作递进去 —— 视图不持有 AppDelegate（D-10）
    - 收编的最短形态：判定一行映射（`if case .available = status { return true }`）+ 生产件工厂 + 文案；不建协议、不建包装层

key-files:
  created:
    - Sources/PicApp/Transcode/TranscodeWindowView.swift
    - Sources/PicApp/Transcode/TranscodeViewModel.swift
    - Sources/PicApp/Transcode/InstallPathwaysView.swift
    - Sources/PicApp/Transcode/TranscodeScene.swift
  modified:
    - Sources/PicCore/App/FFmpegAvailability.swift（收编重接线）
    - Tests/PicCoreTests/FFmpegAvailabilityTests.swift（改注入 locator 假件）
    - Sources/PicApp/AppDelegate.swift（持有者 + bootstrap 重查 + 入口分派）
    - Sources/PicApp/PicApp.swift（scene 注册 + 闭包注入）
    - Sources/PicApp/Settings/SettingsView.swift（维护行接线 + 弹层挂载点）
    - Sources/PicApp/Transcode/TranscodeScene.swift（T2 改签名：三件依赖注入）

key-decisions:
  - "收编的最短形态是**判定投影**（`FFmpegAvailability.available(FFmpegToolStatus) -> Bool`）+ 生产 locator 工厂，不是删文件重接线：调用点有两处（状态卡文案 + 入口置灰），留一行投影比让它们各自 `if case` 更短，且 `label(available:)` 的 Phase 5 消费面逐字不动"
  - "入口条件分派返回 `Bool` 而不是直接 present sheet：开窗是 SwiftUI `openWindow` 环境值（视图侧），可用性判定是装配层职责 —— 分派留在 AppDelegate，视图只递 openWindow 闭包并按返回值决定是否弹层"
  - "设置窗的 ffmpeg 读数与徽章共用**同一个 locator 实例**（AppDelegate.transcodeLocator），但各自在需要时点 `.locate()`（设置窗 body 读、窗口 onAppear 读）—— 判定逻辑一份、调用时机两处，避免陈旧值"

patterns-established:
  - "判定收编的验证形态：变异判定投影的 `true` → `false`，命名用例红 + 0 编译器诊断 + 恢复后 `cmp -s` 逐字节一致（Phase 5/06-02/06-03 第四次沿用）"
  - "本 plan 的 `<automated>` 块 `cd /Users/coderstory/dev/pic` 指向主检出 —— worktree 执行必须重锚（06-01/02/03 同一课的第四次）"

requirements-completed: [TRANS-02, TRANS-06]

coverage:
  - id: D1
    description: "转码窗四要素：ffmpeg 徽章（available 含路径 / unavailable 警告 + 途径入口）、队列表（文件名·格式·大小·进度条·状态 token）、底部可复制实际命令、产物规则三句 + 工具行（重扫 / 开始转码）"
    requirement: TRANS-06
    verification:
      - kind: other
        ref: "结构判据（剥注释后 Sources/PicApp/Transcode/）：commandDisplay=1、Converted=1、保留=1、待转码=5、ObservableObject=1、onJobsChanged=1、import PicCore=1、NSOpenPanel=0、Timer/scheduledTimer=0"
        status: pass
      - kind: other
        ref: "swift build RC=0（新增四文件零编译错误零新告警）"
        status: pass
    human_judgment: false
  - id: D2
    description: "三途径安装弹层逐条在场（brew + macOS 27 警示 + --build-from-source 变通 / evermeet 静态二进制 + xattr 清隔离 / 源码编译），各带 pathway:* 字符串字面量标记，明示 App 不内置不下载，含「重新检测」"
    requirement: TRANS-02
    verification:
      - kind: other
        ref: "结构判据（剥注释后 InstallPathwaysView.swift）：pathways=1/1/1（各恰好一次）、xattr=1、brew install ffmpeg=1、evermeet=1、build-from-source=1"
        status: pass
    human_judgment: false
  - id: D3
    description: "入口条件分派：启动查一次 + 每次点击先重查；可用开 640pt 转码窗，不可用按钮 opacity 0.34 置灰但可点 → 弹三途径；PIC_FFMPEG token 行可 grep；队列持有者就位"
    requirement: TRANS-02
    verification:
      - kind: other
        ref: "结构判据（剥注释后 AppDelegate.swift）：refreshFFmpegAvailability=3（定义 + bootstrap + 入口）、ProcessWhichProbe=1、FileManagerExecutableProbe=1、PIC_FFMPEG=1、case .available=2、openWindow=2；PicApp.swift TranscodeScene=1"
        status: pass
      - kind: other
        ref: "转码入口零非注释 .disabled（剥注释后 SettingsView.swift 计数 0）；菜单侧 MenuContentView/MenuItem 转码字样 0；四根 Watcher 线 = 4、setActivationPolicy = 3（与开工基线一致）"
        status: pass
    human_judgment: false
  - id: D4
    description: "D-17 收编：Phase 5 状态卡的 PATH-only 判定消除，判定收敛为 ExternalToolLocator 薄委托；label 文案与 PIC_FFMPEG available=<0|1> label=… 证据行格式不变；FFmpegAvailabilityTests 收编后仍绿"
    verification:
      - kind: unit
        ref: "Tests/PicCoreTests/FFmpegAvailabilityTests.swift —— Executed 6 tests, with 0 failures（全部注入 locator 假件，不依赖本机 PATH/文件系统）"
        status: pass
      - kind: other
        ref: "变异 MUT-P6-AVAILABLE（available() 的 true → false）：MUTATED_RC=1、3 断言红（testExplicitProbePathIsReportedAvailable / testGuiMinimalPathStillFindsHomebrewInstall / testWhichFallbackIsReportedAvailable）、编译器诊断 0、恢复后 cmp -s 逐字节一致、复绿"
        status: pass
      - kind: other
        ref: "结构判据（剥注释后 App/FFmpegAvailability.swift）：ExternalToolLocator=2、ProcessWhichProbe=1、label(available:=1；全量 swift test 190 tests, 2 skipped, 0 failures"
        status: pass
    human_judgment: false
  - id: D5
    description: "UI 行为验证：点击弹层 / 开窗 / 队列进度条刷新（开窗看徽章 → 临时改名 ffmpeg 二进制再看置灰与弹层 → 复原，约 2 分钟）"
    verification: []
    human_judgment: true
    rationale: "本 plan 无 XCUITest 基建可用（05-04 的 XCUITest 只覆盖设置窗既有控件，且跑 XCUITest 需手动）。自动判据止于编译 + 结构 —— 点击/弹层/开窗的**行为**无自动化断言，登记为 06-05 VERDICT 的人工清单项"

# Metrics
duration: 34 min
completed: 2026-10-04
status: complete
---

# Phase 6 Plan 04: 转码 UI 与入口接线 Summary

**独立转码窗口（徽章 / 队列表 / 可审计命令 / 产物规则）+ 三途径安装弹层 + 设置窗入口的条件分派（置灰 0.34 但可点），并把 Phase 5 的 PATH-only ffmpeg 判定收编进 `ExternalToolLocator` 消掉两套真相**

## Performance

- **Duration:** 34 min
- **Started:** 2026-10-04T00:41Z
- **Completed:** 2026-10-04T01:15Z
- **Tasks:** 2
- **Files modified:** 9（4 新建 + 5 修改）

## Accomplishments

- **转码窗四件**（`Sources/PicApp/Transcode/`）：`TranscodeWindowView` 按 UI-SPEC §8 落齐徽章（available 含路径 / unavailable 警告 + 「安装途径…」入口）、队列表（文件名·格式·大小·进度条·受控状态 token 含 failed reason）、底部可复制的实际命令（running 优先、其次点选）、产物规则三句、工具行（重扫 / 开始转码）；`TranscodeViewModel` 包 `onJobsChanged` 回调 → `@Published jobs`，`refresh()` 是开窗/点击/弹层按钮三处共用的新鲜化出口；`InstallPathwaysView` 三途径逐条带 pathway:* 字面量标记；`TranscodeScene` 为 `Window(id:"transcode")` 640pt，onAppear 重查 + 载候选。零常驻动画、令牌与组件全部复用设置窗那一套。
- **入口链路**：AppDelegate 持 `ffmpegLocator` / `ffmpegAvailability` / `refreshFFmpegAvailability()`（bootstrap 末尾追加启动那一次）；设置窗「打开…」先重查拿新鲜判定 → 可用开转码窗、不可用返回 false 让设置窗弹三途径；不可用态**只用 opacity 0.34**（`.help` 写明原因），**不用 `.disabled(true)`** —— 否则点击被吃掉、SC#1 的「给出多条安装途径」那半句永不成立。`transcodeQueue` 持有者就位（onBatchFinished 的 rescan 留给 06-05）。
- **D-17 收编**：`App/FFmpegAvailability.swift` 的 PATH 目录扫描删除，判定收敛为一行投影（`FFmpegAvailability.available(FFmpegToolStatus)`）+ 生产 locator 工厂 + 原文案；`SettingsView` 不再自己扫 PATH，改读 AppDelegate 持有的同一份读数。GUI app 的 launchd 最小 PATH（不含 `/opt/homebrew/bin`）下「明明装了 ffmpeg 却报未安装」的两套判定消除。
- **Phase 5 消费面零破坏**：`label(available:)` 的「可用/未安装」逐字不变；`PIC_FFMPEG available=<0|1> label=…` 证据行格式不变（05-03/05-04 的 probe 与判据照旧成立）；`FFmpegAvailabilityTests` 6 条改注入 locator 假件（文件内自带 FakeWhich/FakeFS，不跨文件引用 06-02 替身），不依赖本机 PATH/文件系统。
- **变异反向验证**：`available()` 的 `true` → `false`，3 条命名用例红、0 编译器诊断；恢复后 `cmp -s` 逐字节一致、复绿。

## Task Commits

1. **Task 1: 转码窗口四件 + 三途径安装弹层** - `2e16ffc` (feat)
2. **Task 2: 入口接线 + 收编 Phase 5 判定为单一真相源** - `9d18a81` (feat)

**Plan metadata:** 本 commit（docs: complete plan）

## Files Created/Modified

- `Sources/PicApp/Transcode/TranscodeWindowView.swift`（新）— 窗口主体：徽章 / 队列表 / 底部命令 / 产物规则 / 工具行
- `Sources/PicApp/Transcode/TranscodeViewModel.swift`（新）— ObservableObject 包队列回调，零 AppKit 依赖
- `Sources/PicApp/Transcode/InstallPathwaysView.swift`（新）— 三途径安装说明 + pathway:* 标记 + 重新检测
- `Sources/PicApp/Transcode/TranscodeScene.swift`（新，T2 改签名）— Window(id:"transcode") 640pt + onAppear 重查
- `Sources/PicApp/AppDelegate.swift`（改）— ffmpegLocator / ffmpegAvailability / refreshFFmpegAvailability() / openTranscodeWindow() / transcodeQueue / transcodeLocator
- `Sources/PicApp/PicApp.swift`（改）— TranscodeScene 注册 + 设置窗三闭包注入
- `Sources/PicApp/Settings/SettingsView.swift`（改）— 维护行接线（去 disabled、加 opacity/help）+ 途径弹层 sheet 挂载点 + ffmpeg 行改读注入读数
- `Sources/PicCore/App/FFmpegAvailability.swift`（改）— 收编：PATH 扫描删除，判定收敛为 locator 的薄委托
- `Tests/PicCoreTests/FFmpegAvailabilityTests.swift`（改）— 6 条改注入 locator 假件

## Decisions Made

- **收编的最短形态是「判定投影」而非删文件重接线**：调用点有两处（状态卡文案 + 入口置灰），留一行 `if case .available = status { return true }` 比让两处各自 `if case` 更短，也保住 `label(available:)` 的 Phase 5 消费面逐字不动；生产 locator 工厂放 `FFmpegAvailability.productionLocator()`（判定层唯一生产构造点），不建协议/包装层/适配框架。
- **入口分派返回 Bool 而非直接 present sheet**：开窗是 SwiftUI `openWindow` 环境值（视图侧），可用性判定是装配层职责 —— 分派留在 AppDelegate，视图只递 openWindow 闭包并按返回值决定是否弹层。
- **设置窗读数与转码窗徽章共用同一个 locator 实例**（`AppDelegate.transcodeLocator`），判定逻辑一份、调用时机两处（设置窗 body 读 / 窗口 onAppear 读）—— 避免了缓存带来的陈旧值。

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - 判据缺陷] `FFmpegAvailabilityTests` 的 5 条原用例在收编后按字面不可满足**
- **Found during:** Task 2 收编设计
- **Issue:** 原用例全部走 `resolve(searchPaths:)` 注入临时目录 + 权限位（05-03 的形态）。收编后 PATH 目录扫描被删除，`searchPaths` 这个注入面不存在了 —— 逐条保留等于把已删除的判定重新写回测试里
- **Fix:** 按计划 T2 action 明写的口径落实同一意图（注入 locator 假件、保持不依赖本机 PATH/文件系统、用例数与断言口径尽量不变）：5 条 → 5 条等价映射（显式路径可用 / 无命中不可用 / 执行位不合格不可用 / which 兜底可用 / GUI 最小 PATH 下显式探测仍命中 = D-17 收编的核心判据）+ label 文案 = 6 条，用例数与 Phase 5 持平
- **Files modified:** Tests/PicCoreTests/FFmpegAvailabilityTests.swift
- **Verification:** `Executed 6 tests, with 0 failures`；变异 available() 3 断言红（其中 testGuiMinimalPathStillFindsHomebrewInstall 正是收编核心判据）
- **Committed in:** 9d18a81

**2. [Rule 2 - 缺失关键] 计划 files_modified 漏列 `Sources/PicApp/Settings/SettingsView.swift`**
- **Found during:** Task 2 入口接线
- **Issue:** 计划 T2 action ④ 明写「『维护』行『打开…』的条件分派（本 task 核心，落在 Phase 5 的 seam 上）」，而那个 seam（`.disabled(true)` 的占位按钮）就在 SettingsView.swift 里 —— 但 frontmatter 的 files_modified 没列它。不改这个文件，SC#1 的两半句（去 disabled + 给途径）一条都落不了
- **Fix:** 改 SettingsView.swift，范围压到最小：维护行一行按钮（去 `.disabled(true)`、加 `.opacity` + `.help`、接分派）+ 新增两个闭包参数与一个 `@State` + 途径弹层 sheet 挂载点 + ffmpeg 行改读注入读数；其余（T4 的空态、运行状态卡、六项真绑定、两条置灰联动）一个字符未动
- **Files modified:** Sources/PicApp/Settings/SettingsView.swift
- **Verification:** 编译 RC=0；`swift test` 190 全绿；剥注释后 SettingsView 内 `.disabled(true)` 计数 0；既有判据（`Button("…") {}` 计数、空态文案单源）未被触碰
- **Committed in:** 9d18a81

**3. [Rule 3 - Blocking] 两个 `<automated>` 块的 `cd /Users/coderstory/dev/pic` 指向主检出**
- **Found during:** Task 1 verify 执行前
- **Issue:** 在 worktree 执行会验错检出（06-01/02/03 同一课的第四次）
- **Fix:** 命令根重锚本 worktree（默认 cwd 即 worktree 根），判据本体一字未改
- **Files modified:** 无
- **Verification:** 全部判据在本 worktree 上跑过并过
- **Committed in:** N/A

---

**Total deviations:** 3 auto-fixed（1 判据缺陷、1 缺失关键文件、1 环境适配）
**Impact on plan:** 零生产代码语义偏移、零 scope 蔓延；改动落在 9 个文件域内（files_modified 八项 + 计划 action ④ 强制要求的 SettingsView）。计划的全部行为判据与结构判据原样通过。

## Issues Encountered

- `SettingsView` 接线时手滑删掉了 sheet modifier 的两个收尾花括号（Edit 的 old_string 少带一层），编译当场报错，补回即过 —— 未进入任何提交
- `InstallPathwaysView.onRecheck` 传入 `refreshFFmpeg` 时类型不匹配（`() -> Bool` vs `() -> Void`），调用点显式 `_ =` 丢弃返回值；类型契约保持两侧一致而非再加一层适配

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- **06-05 可直接消费**：`transcodeQueue.onBatchFinished` 已就位（等接 `invalidateCache → rescanAndApply`）；`router.start` 的合并清单由 `ConvertedLibrary` + `playbackItems(root:converted:)` 提供；`PIC_FFMPEG=<available|unavailable>` 是 token 行可直接进 test.sh Phase 6 段
- **`swift test` 全绿基线：190 tests, 2 skipped, 0 failures**（后续 plan 的红灯归因以此为参照）
- **人工验证清单移交 06-05 VERDICT**（约 2 分钟）：开设置窗 → 转码行「打开…」应开 640pt 窗且徽章显示路径；把 ffmpeg 二进制临时改名 → 按钮变 0.34 置灰但仍可点 → 点击应弹三途径弹层（含 xattr 清隔离命令）；装回后点「重新检测」→ 徽章转绿。本 plan 未跑 XCUITest 也未改 settings window 的既有控件
- 本 plan 零 ffmpeg 调用（C6）；未跑 `bash test.sh`（按波次纪律，统一校验在 06-05）

## Self-Check: PASSED

- [x] `swift build` RC=0（新增四文件零新告警）
- [x] 全量 `swift test`：190 tests, 2 skipped, 0 failures
- [x] `swift test --filter FFmpegAvailabilityTests`：6 tests, 0 failures
- [x] T1 结构门禁：piccore=1 observable=1 hook=1 cmd=1 xattr=1 brew=1 evermeet=1 bfs=1 pathways=1/1/1 panel=0 timer=0 rules=1/1/5
- [x] T2 结构门禁：refresh=3 which=1 fs=1 probe_line=1 dispatch=2 scene=2 loc_delegate=2 loc_probe=1 label=1 picscene=1 gate=421 < rate=422
- [x] 转码入口零非注释 `.disabled(true)`；opacity 0.34 在场
- [x] 菜单零转码项；四根 Watcher 线 4、setActivationPolicy 3（与开工基线一致）；B1 门行号序未破
- [x] 变异 MUT-P6-AVAILABLE：3 断言红、0 编译器诊断、恢复后 cmp -s 逐字节一致、复绿
- [x] 全量测试日志零 `ffmpeg -i` / `libx264` 执行痕迹

---
*Phase: 06-transcode*
*Completed: 2026-10-04*