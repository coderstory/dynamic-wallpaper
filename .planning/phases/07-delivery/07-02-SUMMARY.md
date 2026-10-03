---
phase: 07-delivery
plan: 02
subsystem: infra
tags: [smappservice, launchagent, launchctl, autostart, macos, userdefaults]

requires:
  - phase: 07-delivery
    provides: "07-01 的打包与打包链路（build/Pic.app + DMG），SYS-01 实测的产物来源"
provides:
  - "LaunchAgentWriter：路线 B 的 plist 生成/读回/删除（Label + ProgramArguments + RunAtLoad，无 KeepAlive）"
  - "AutoStartManager：A→B 自动降级决策内核，三注入点（registration / writer / runner）"
  - "LoginItemRegistration + ShellRunner 两个协议，让全部系统副作用在单测里可替身"
  - "SettingsStore 第 8 键 launchAtLogin（默认 false，可持久化）"
  - "AppDelegate 启动 sync + 设置窗开关的真行为接线"
  - "scripts/probe-sys01.sh：SYS-01 一次性实测探针（enable → 判路线 → 强制清理 → 恢复偏好）"
affects: [07-delivery, 07-03, 07-04, uat]

actuals:
  tokens: 7940
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "系统副作用三层注入（协议 + 替身）：注册/写盘/起进程各自一个协议，单测零真实系统状态"
    - "状态一行、路由另一行（D-17）：SMAPP_STATUS 与 SYS01_ROUTE 不合并，读数各自独立可 grep"

key-files:
  created:
    - "Sources/PicCore/System/LaunchAgentWriter.swift"
    - "Sources/PicCore/System/AutoStartManager.swift"
    - "Tests/PicCoreTests/AutoStartTests.swift"
    - "scripts/probe-sys01.sh"
  modified:
    - "Sources/PicCore/State/SettingsStore.swift"
    - "Sources/PicApp/AppDelegate.swift"
    - "Sources/PicApp/PicApp.swift"
    - "Sources/PicApp/Settings/SettingsView.swift"
    - "Tests/PicCoreTests/SettingsStoreTests.swift"
    - "Tests/PicCoreTests/PlayModeTests.swift"

key-decisions:
  - "路线 A（SMAppService）在 ad-hoc 签名的 build/Pic.app 上实测成立：SMAPP_STATUS=enabled、SYS01_ROUTE=smappservice。路线 B 保留为兜底而非备用 —— 未签名场景被实测排除，但签名身份会漂移（RESEARCH 坑 4），降级路径不能删"
  - "路线 B plist 键集锁死为 Label / ProgramArguments / RunAtLoad，源码层零 KeepAlive：壁纸 app 崩了不该被 launchd 无限拉起，且与「退出」菜单项直接冲突"
  - "SMAppService.Status 的状态 token 显式映射，不用 String(describing:) —— 实测它给的是 SMAppServiceStatus(rawValue: 1) 而不是 case 名，判据 grep 的是 SMAPP_STATUS=enabled"
  - "路线 B 的单测用真 writer 指向临时目录而不是 mock writer（LaunchAgentWriter 是 final class，且落盘内容比调用记录更难自欺）"
  - "sfltool dumpbtm 本机实测挂死（240s 窗口内零输出、退出码 142），与 RESEARCH 2026-10-03 记录的「rc=0 无需 sudo」不符 —— 探针对读不到与读到 0 分行记录（*_AVAILABLE），不合成一个数字"

patterns-established:
  - "判据的「读不到」与「读到 0」必须分两行（BTM_AVAILABLE 系列）：合成一个数字就把差别抹掉"
  - "系统状态采集脚本的清理必须与断言路径同一条，且复原动作要排在复查**之前** —— 放进 trap 就晚了"

requirements-completed: [SYS-01]

coverage:
  - id: D1
    description: "路线 B 的 plist 生成（Label/ProgramArguments/RunAtLoad，零 KeepAlive）与删除"
    verification:
      - kind: unit
        ref: "Tests/PicCoreTests/AutoStartTests.swift#testPlistHasLabelRunAtLoadAndNoKeepAlive"
        status: pass
      - kind: unit
        ref: "Tests/PicCoreTests/AutoStartTests.swift#testWriterRemoveDeletesPlist"
        status: pass
      - kind: other
        ref: "变异①（插入 KeepAlive）→ 该用例红，红光为断言失败（RED1_DIAG=0）"
        status: pass
    human_judgment: false
  - id: D2
    description: "A 失败自动落 B，失败形态逐字可 grep"
    verification:
      - kind: unit
        ref: "Tests/PicCoreTests/AutoStartTests.swift#testRouteAFailureFallsBackToLaunchAgentWriter"
        status: pass
      - kind: other
        ref: "变异②（routeB 写盘短路）→ 该用例红，红光为断言失败（RED2_DIAG=0）"
        status: pass
    human_judgment: false
  - id: D3
    description: "requiresApproval 留在路线 A 并引导用户，不落 B"
    verification:
      - kind: unit
        ref: "Tests/PicCoreTests/AutoStartTests.swift#testRouteARequiresApprovalStaysOnRouteAAndOpensSettings"
        status: pass
    human_judgment: false
  - id: D4
    description: "禁用清两路 + app 移动后路径漂移被重写"
    verification:
      - kind: unit
        ref: "Tests/PicCoreTests/AutoStartTests.swift#testDisableCleansBothRoutes"
        status: pass
      - kind: unit
        ref: "Tests/PicCoreTests/AutoStartTests.swift#testStalePlistPathIsRewrittenOnEnable"
        status: pass
    human_judgment: false
  - id: D5
    description: "SettingsStore 第 8 键默认 false、可持久化、round-trip"
    verification:
      - kind: unit
        ref: "Tests/PicCoreTests/SettingsStoreTests.swift#testLaunchAtLoginDefaultsFalseAndRoundTrips"
        status: pass
      - kind: integration
        ref: "swift test --filter SettingsStoreTests → Executed 14 tests, with 0 failures"
        status: pass
    human_judgment: false
  - id: D6
    description: "既有 7 键零改动（D-03 的可执行代理仍然有效）"
    verification:
      - kind: integration
        ref: "Tests/PicCoreTests/PlayModeTests.swift#testPersistWritesExactlyTheSevenKnownKeys（expected 只加 Key.launchAtLogin 一项 → 8 元素）"
        status: pass
    human_judgment: false
  - id: D7
    description: "SYS-01 机制结论：未签名 app 上开机自启真的被建立"
    verification:
      - kind: integration
        ref: "bash scripts/probe-sys01.sh → SYS01_ACTIVE_ROUTE=smappservice / SYS01_SMAPP_STATUS=enabled"
        status: pass
    human_judgment: false
  - id: D8
    description: "重启后真的自启（持久性结论）"
    verification: []
    human_judgment: true
    rationale: "需要真人重启机器，且必须在 DMG 装出的 .app 上做 —— 开发期每次 build 的 ad-hoc 签名都不同，BTM 的身份追踪会失效。已登记为 frontmatter 的 user_setup 人工项，evidence 记为 SYS01_REBOOT_CONFIRMED=pending_human"

# Metrics
duration: 63min
completed: 2026-10-04
status: complete
---

# Phase 7 Plan 02: SYS-01 开机自启双路线 Summary

**未签名 app 上的开机自启从悬项变成实测结论：路线 A（SMAppService）在 ad-hoc 签名的 build/Pic.app 上注册成功（`SMAPP_STATUS=enabled`），路线 B（LaunchAgents plist）作为自动降级兜底保留并被 7 条单测锁死**

## Performance

- **Duration:** 63 min
- **Started:** 2026-10-03T17:21Z
- **Completed:** 2026-10-03T18:24Z
- **Tasks:** 3
- **Files modified:** 11

## Accomplishments

- **SYS-01 有了实测结论**：路线 A 在 ad-hoc 签名下**成立** —— `SMAPP_STATUS=enabled` / `SYS01_ROUTE=smappservice`。这是 RESEARCH 里「无公开资料、必须实测」的那个最大悬项（W-2026-10-03-39）。
- **双路线内核可注入、全分支单测锁死**：A 抛错→自动落 B 且失败形态可 grep；`requiresApproval` 留在 A 并引导；禁用清两路；app 移动重写 plist。
- **第 8 键纯增量**：既有 7 键一个字符未动，D-03 的可执行代理（`testPersistWritesExactlyTheSevenKnownKeys`）仍然有效且已同步到 8 元素。
- **探针零脏状态**：跑完后 BTM 计数、plist、defaults 三项全部回基线，登录项与用户偏好均复原。
- **两处变异反向验证**：KeepAlive 插入 / routeB 写盘短路，各自让对应用例转红，且红光来自断言失败而非编译失败（D-16），恢复后逐字节一致。

## Task Commits

Each task was committed atomically:

1. **Task 1: LaunchAgentWriter + AutoStartManager + 7 条单测** - `6315e56` (feat)
2. **Task 2: SettingsStore 第 8 键 + AppDelegate sync + 设置开关接线** - `a2f1e5b` (feat)
3. **Task 3: probe-sys01.sh + evidence/sys01.log** - `cb426f9` (test)

## Files Created/Modified

- `Sources/PicCore/System/LaunchAgentWriter.swift` - 路线 B plist 生成/读回/删除，目录可注入
- `Sources/PicCore/System/AutoStartManager.swift` - A→B 决策内核 + `LoginItemRegistration` / `ShellRunner` 两个协议
- `Tests/PicCoreTests/AutoStartTests.swift` - 7 条用例，Fake 三件套，全不碰真实系统状态
- `Sources/PicCore/State/SettingsStore.swift` - 第 8 键 `launchAtLogin`（Key / Seed / 属性 / load / persist）
- `Sources/PicApp/AppDelegate.swift` - `autostart` 持有 + 启动 sync + `setLaunchAtLogin(_:)` 行为侧
- `Sources/PicApp/Settings/SettingsView.swift` - 开关绑 store（原为本地 `@State`），经闭包落行为
- `Sources/PicApp/PicApp.swift` - 注入 `setLaunchAtLogin` 闭包（沿既有装配通道）
- `Tests/PicCoreTests/SettingsStoreTests.swift` - +1 条 round-trip
- `Tests/PicCoreTests/PlayModeTests.swift` - `expected` 集合 +1 项（7→8），其余 7 键名一字未改，函数名未改
- `scripts/probe-sys01.sh` - 一次性实测探针
- `.planning/phases/07-delivery/evidence/sys01.log` - 实测证据

## Decisions Made

1. **路线 B 保留而非删除** —— 未签名场景已实测排除路线 A 的失败，但签名身份在开发期每次 build 都漂（RESEARCH 坑 4），降级路径不能因为「当前测出来没走」就拆掉。
2. **状态 token 显式映射** —— `String(describing:)` 对从 ObjC 导入的 `SMAppService.Status` 给的是 `SMAppServiceStatus(rawValue: 1)` 而非 case 名（实测），判据 grep 的是 `SMAPP_STATUS=enabled`。
3. **路线 B 单测用真 writer 指向临时目录** —— `LaunchAgentWriter` 是 `final class` 无法替身化；且「文件真在不在、内容对不对」比「mock 记下了一次调用」更难自欺。
4. **BTM 读数与可用性分行** —— 见下节「Issues Encountered」。

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] 探针的三处真 bug（均在 T3 执行期发现并修）**

- **Found during:** Task 3
- **Issue / Fix:**
  - `env VAR=x alarm 60 "$APP"` —— `env` 只能 exec 真实可执行文件，shell 函数不在 PATH 里，**app 根本没起来**，日志安静地少掉所有 `SYS01_*` 行（空 evidence = 假绿灯）。改为 `alarm 60 env VAR=x "$APP" …`，并补一道 `SYS01_APP_EMITTED_LINES` 的可执行门把「app 没打任何行」与「这一行没有」分开。
  - `grep -c 'launchAtLogin' backup || echo 0` —— 零命中时 `grep -c` 退出码是 1，`|| echo 0` 拼成两行，永远不等于 `"0"`，判据自己恒红。改为与第 1 步记下的基线值直接比对。
  - 偏好复原放进 trap —— 但 trap 在 exit 时才跑，第 6 步的比对早就出结果了；且 `defaults import` 是**合并不是替换**，基线里没有该键时它不会自己消失。改为在第 5 步（复查之前）显式 `defaults delete`。
- **Files modified:** `scripts/probe-sys01.sh`
- **Verification:** 每修一处重跑探针，直到 `PROBE_RC=0` 且 `SYS01_PREFS_RESTORED=1`、`SYS01_CLEANUP_PLIST=matches_baseline`
- **Committed in:** `cb426f9`

**2. [Rule 1 - Bug] `statusToken` 用 `String(describing:)` 产不出判据要的 token**

- **Found during:** Task 1（首次 `swift test --filter AutoStartTests` 2 条红）
- **Issue:** `SMAppService.Status` 是 ObjC 导入枚举，`String(describing:)` 给 `SMAppServiceStatus(rawValue: 1)`
- **Fix:** 显式 `switch` 映射成 `enabled` / `requiresApproval` / `notRegistered` / `notFound`
- **Files modified:** `Sources/PicCore/System/AutoStartManager.swift`
- **Verification:** 7/7 绿；实测脚本确认 `/tmp/statcheck` 的输出形态
- **Committed in:** `6315e56`

**3. [Rule 3 - Blocking] 计划的 `<automated>` 全部指向主 checkout**

- **Found during:** T1 验证
- **Issue:** 三条 verify 都以 `cd /Users/coderstory/dev/pic` 开头 —— 那是**主 checkout**，不在本 agent 的 worktree 内。照抄会去验证错误的代码树，且 worktree-path-safety step 0c 要求在此停下。
- **Fix:** 不改判据逻辑，只把根换成 worktree 根（`WT=/Users/coderstory/dev/pic/.claude/worktrees/agent-ac2e85e3a97ec3728`），其余命令逐字保留
- **Files modified:** 无（仅本次执行的临时脚本）
- **Verification:** 三条 verify 的实质输出（`AUTOSTART_CORE_OK` / `AUTOSTART_WIRING_OK` / `SYS01_PROBE_OK`）全部打出
- **Committed in:** N/A

**Total deviations:** 3 auto-fixed (2 bug, 1 blocking)
**Impact on plan:** 全部是正确性修复，零范围蔓延。计划的判据逻辑一条未放松 —— 变异门、源码层门、清理门都按原样跑并原样通过。

## Issues Encountered

- **`sfltool dumpbtm` 在本机挂死** —— RESEARCH 1.3 记录 2026-10-03「rc=0、无需 sudo、正常输出」。2026-10-04 复测：沙箱内外均挂死，240s 窗口内**零输出**、退出码 142（被 alarm 杀掉），试过 25s / 100s / 240s 三档，另有一个首次调用残留的 sfltool 进程被 kill 后仍复现。
  - **处置**：路线 A 的结论**没有**建立在 BTM 上，而是建立在 app 侧 `SMAPP_STATUS=enabled`（这是 `SMAppService` 自己对注册状态的权威回答）+ 系统侧无 LaunchAgent plist/`launchctl print` rc=113（路线 B 确实没被启用）两侧。探针把 `*_BTM_AVAILABLE=0` 与 `*_BTM=0` **分行**记录 —— 读不到与读到 0 是两件事，合成一个数字就是把差别抹掉（D-17）。
  - **这意味着**：RESEARCH 1.3 那条「本机已验证」需要标注为**已失效**，BTM 侧的佐证在本机拿不到。
- **重启自启未验证** —— 按计划的诚实边界，`SYS01_REBOOT_CONFIRMED=pending_human`。机制结论（注册成功）与持久性结论（重启真的起来）分开记，且必须在 DMG 装出的 .app 上做（开发期签名漂移会让 BTM 追踪失效）。
- **执行期的一次手动注册已当场撤销** —— 诊断 `dumpbtm` 挂死时手动起了一次 app，它真的把登录项注册上了。已用 `launchAtLogin=false` + 再起一次 app 触发 `disableBoth` 撤销，并逐项复查（plist 无、launchctl rc=113、偏好域无该键、无残留进程）。

## 对 05-02 的有意覆盖

05-02 把设置窗的「开机自启」规划为**本地 `@State`、不写 store 不持久化**（理由是当时 7 键冻结）。本 plan 改为真持久化是**故意的覆盖**：

- 不持久化 ⇒ 用户拨开的开关重启即落回 false，「开机自启」这项判据无从谈起；
- 改动位置：`Sources/PicApp/Settings/SettingsView.swift`（删 `@State private var launchAtLogin`，改为 `store.launchAtLogin` 的 Binding）；未新建第二条装配通道，行为侧经 PicApp 注入的 `setLaunchAtLogin` 闭包走 AppDelegate，与 `reapplyBatteryHold` 同款。

## User Setup Required

**需要真人重启一次**（已登记为 PLAN frontmatter 的 `user_setup`）：

1. 从 `dist/Pic-0.1.0.dmg` 安装到 /Applications，打开一次，在设置里拨开「开机自启」
2. 若系统判定需手动批准：系统设置 → 登录项与扩展 里批准一次
3. 重启，确认 Pic 自启且菜单栏图标在位
4. 把结果（SYS01_REBOOT_CONFIRMED=1/0 与路线名）补记进 `.planning/phases/07-delivery/evidence/sys01.log`

## Next Phase Readiness

- SYS-01 的**机制面**已闭合（有实测结论 + 有可审计证据 + 有回归网）；**持久面**待上面的人工项
- 07-03 / 07-04 可直接依赖 `SettingsStore.Key.launchAtLogin` 与 `AutoStartManager`
- RESEARCH 1.3 的 `sfltool dumpbtm` 记录需要更新为「2026-10-04 复测挂死」
- 探针可重复运行（幂等，退出后系统状态回基线）

---
*Phase: 07-delivery*
*Completed: 2026-10-04*