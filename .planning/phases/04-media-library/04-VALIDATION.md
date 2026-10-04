---
phase: 04-media-library
slug: media-library
status: draft
nyquist_compliant: false
wave_0_complete: true
tasks_total: 21
tasks_verified: 18
tasks_unverified: 3
tasks_partial: 3
created: "2026-10-04"
updated: "2026-10-04"
---

# Phase 04-media-library — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

## 为什么 `status: draft` / `nyquist_compliant: false`

`/gsd-validate-phase` **从未在本 Phase 上跑过**。本文件是 2026-10-04 依据 PLAN / SUMMARY /
VERIFICATION / UAT / evidence 手工补记的覆盖台账。按 `audit-milestone.md` §5.5（#2117），
`status: draft` = **NOT-VALIDATED（覆盖 TODO）**，不是合规失败。

> 本 Phase 有 **7 个 plan** —— 比其他 phase 多一个：前 6 个是原计划，
> **`04-07` 是 `04-VERIFICATION.md` 审出 G-04-3 / G-04-3b 之后的 gap 修复 plan**。
> 21 个 task 的算法：`04-01`(3) + `04-02`(3) + `04-03`(3) + `04-04`(3) + `04-05`(3) + `04-06`(3) + `04-07`(3)。

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest via SwiftPM（fake seam + 注入式变异反向验证）+ 无头回归 `bash test.sh` |
| **Config file** | `Package.swift` · `test.sh`（Phase 4 段 11 条 evidence 门）· `scripts/probe-{media-library,rotation-wiring}.sh` |
| **Quick run command** | `swift test --package-path . --filter MediaLibraryTests` |
| **Full suite command** | `bash test.sh` |
| **Estimated runtime** | swift test ~5 秒 · test.sh ~60 秒 · 探针 `alarm 120/300` 封顶 |

---

## Sampling Rate

- **After every task commit:** 该 task 的 `<automated>`（`swift build` / `swift test --filter <Suite>` / 对应 probe）
- **After every plan wave:** `swift test --package-path .` 全量
- **Before `/gsd-verify-work`:** `bash test.sh` 必须全绿
- **Max feedback latency:** < 30 秒（探针段最长 300 秒）

---

## Per-Task Verification Map

`wave_0_complete: true` 的依据：**21 / 21 个 task 在 PLAN 里都带 `<verify><automated>`**。

| Plan | # | Task | 有 `<verify>` 判据 | 证据来源 | 结论 |
|------|---|------|------------------|---------|------|
| 04-01 | 1 | MediaLibrary 扫描内核 —— 递归 / 白名单 / Converted 排除 / 视频轨校验 / 缓存 | ✅ `swift build … swift test --filter MediaLibraryTests` + 源码层门 | `testRecursionFindsClipThreeDirectoriesDeep`（三层嵌套专门用例）；`testWhitelistAcceptsOnlyMp4MovM4vCaseInsensitively`；`testFileWithAllowedExtensionButNoVideoTrackIsRejected`（FakeAssetProbe） | ✅ 已验（**但真实 `AVFoundationAssetProbe` 从未跑过**，见下） |
| 04-01 | 2 | fixture 树构造脚本（多子目录 / 深嵌套 / Converted / 空目录 / 无权限 / 中文空格 / 符号链接） | ✅ `perl -e 'alarm 120' …` | `D=.planning/spike/media-fixture` 构造判据全过 | ✅ 已验 |
| 04-01 | 3 | tracer 活体证据 —— 扫描 → 取第一条 → load → 窗口可见 → teardown 后不可见 | ✅ `perl -e 'alarm 300' bash scripts/probe-media-library.sh` | `media-library.log` 存在，但 **`MEDIA=absent` + `PROBE_REJECTED=0`** —— 全程用 FakeProbe | ⚠️ **已验但只有 fake 面** —— 真实 `AVFoundationAssetProbe` 未被驱动 |
| 04-02 | 1 | PlayMode 纯增量到三个 case（`loopSingle` rawValue 一字未改） | ✅ 源码层门 + `swift test --filter` | `RotationControllerTests` 三模式全绿；`loopSingle` rawValue 冻结判据 ✅ | ✅ 已验 |
| 04-02 | 2 | RotationController —— 三模式 + 注入式调度器 + 可播种随机源 | ✅ 源码层门（类型签名里拿不到 `PlayerController`） | `test.sh` 常驻判据「轮换器零播放进度读取」×4 ✅（AVPlayer / arbiterCurrentPosition / currentTime / AVPlayerItemDidPlayToEndTime 全 0） | ✅ 已验 |
| 04-02 | 3 | RotationControllerTests —— 一轮无重复 + 到点就切 + 播种可复现 + **两处变异反向验证** | ✅ `perl -0pi` 变异 → `swift test` → 还原 `cmp` | 变异真红、恢复后逐字节一致 | ✅ 已验 |
| 04-03 | 1 | LibraryAvailability 纯函数决策 + `WallpaperWindowController hide()/show()` | ✅ `swift test --filter LibraryAvailabilityTests` | `LibraryAvailabilityTests` 6 条穷举全绿；`hide()`=orderOut 保留窗口 / `show()`=orderFrontRegardless | ✅ 已验（**真实 orderOut 效果需人看屏幕**） |
| 04-03 | 2 | `PlayerController.stop()` 纯增量 + 用协议形状把 D-01 八个签名锁成编译期判据 | ✅ `swift test --filter PlayerControllerFreezeTests` | `PlayerControllerFreezeTests` 锁八个既有签名 + `stop()` | ✅ 已验 |
| 04-03 | 3 | MediaCoordinator —— 扫描结果 → 窗口/播放器动作的唯一落点（fake seam + 一处变异） | ✅ `swift test` + 变异 | `MediaCoordinatorTests` 5 条，含 `testRecoveryFromHiddenToPlayingResumesWithoutRestart` | ✅ 已验 |
| 04-04 | 1 | 菜单从三项扩到五项 —— 模型层纯增量 + 渲染层零手写 Button | ✅ `swift test --filter MenuBarModelTests` + 源码门 | 渲染处 `Button(` 行数 = `ForEach(MenuItemID.allCases` 行数；5 项与顺序被锁 | ✅ 已验 |
| 04-04 | 2 | FolderRequestPolicy 纯函数 + FolderPicker 协议 + `NSOpenPanelFolderPicker`（唯一碰面板处） | ✅ `swift test --filter FolderRequestPolicyTests` | `FolderRequestPolicyTests` 5 条；`test.sh` 判据 `NSOpenPanel(` 全仓 = 1 ✅ | ✅ 已验 |
| 04-04 | 3 | AppDelegate 接线 —— 首启弹框 / 选定即持久化并起播 / 换目录换片 / 两个菜单动作 | ✅ 源码层门（G1..G9 + 行号序） | 全部判据 ✅ | ⚠️ **已验但只有源码层** —— app 级活体（真弹框、真起播）未观测 |
| 04-05 | 1 | PlaybackRouter —— 把 `onAdvance` 接到可注入 `VideoLoading` seam | ✅ 14 项源码门 + 变异 `MUT-P4-LOAD` | `PlaybackRouterTests` 5 条；`SRC_GATES` 14 项全过；变异真红（`ROUTER_TEST_IS_BLIND` 未触发） | ✅ 已验 |
| 04-05 | 2 | AppDelegate 装配 —— 起播挪到 bootstrap 之后 / `onAdvance` 真的驱动装载 / 降级态停装载 | ✅ 源码门 `GATES startfunc=1 … gate_line < rate_line` | 全部 ✅；全量 `swift test` 绿 | ✅ 已验 |
| 04-05 | 3 | 活体证据 —— 轮换装配链运行时读数 | ✅ `perl -e 'alarm 300' bash scripts/probe-rotation-wiring.sh` | `rotation-wiring.log:PIC_ROT_EVIDENCE items=3` `:PIC_ROT_LOOPLIST_ORDER=ok` `:PIC_ROT_SHUFFLE_ROUND_UNIQUE=3` `:PIC_ROT_EMPTY_LOADS=0` | ⚠️ **已验但应用级启动路径自标 informational** —— `PIC_ROT_APP_LAUNCH informational=1 scope=piccore-chain reason=app-launch-blocked-by-locked-screen` |
| 04-06 | 1 | test.sh 追加 Phase 4 源码层门禁（分层 / 面板唯一落点 / 轮换器零播放进度） | ✅ `bash -n test.sh` + 源码门 | 常驻判据每次 `bash test.sh` 自动重验 | ✅ 已验 |
| 04-06 | 2 | test.sh 追加 Phase 4 evidence 门禁（两份日志关键行存在性 + 媒体文件名零泄漏） | ✅ `sed -n '/── P…'` 分段判据 | `p4_line` × 11 项 ✅；零文件名泄漏 | ✅ 已验 |
| 04-06 | 3 | 全量校验 —— `swift test` 全绿 + `bash test.sh` FAIL=0，读数落 evidence | ✅ `swift test … && bash test.sh` | `evidence/test-sh-phase4.log`；Phase 4 收口 `124/124 pass` + `69 pass / 0 fail / 0 skip` | ✅ 已验 |
| 04-07 | 1 | `PlayerController.load` 单落点交接 —— 先插后扫，消除空队列帧（G-04-3b） | ✅ `swift test --filter PlayerControllerFreezeTests` + 12 项函数体计数 | `PC_LOAD_SINGLE_HANDOFF_OK`；`insert=1 remove=1 removeAllItems(load)=0` | ✅ 已验 |
| 04-07 | 2 | `RotationController.advance(reason:)` —— `userRequested` 在 `loopSingle` 下也前进（G-04-3） | ✅ 12 项源码门 | `ROTATION_REASON_AWARE_OK`；解耦 6 项全 0 | ✅ 已验 |
| 04-07 | 3 | 用例按 reason 分流 + 两条新用例 + **两处变异反向验证** | ✅ `perl -0pi` × 2 → 变异红 → `cmp` 还原 | `Executed 9 tests, with 0 failures` ×2；`MUT-P4-USERREQ` / `MUT-P4-LOADSWAP` 两处各自真红；`GAP_FIX_TEST_SUITE_OK` | ✅ 已验 |

**合计：21 个 task · ✅ 已验 18 · ⚠️ 已验但只有 fake / 源码层、无活体面 3（`04-01` T3、`04-04` T3、`04-05` T3）· ❌ 完全未验 0**

> ⚠️ 的 3 个 task **verify 判据本身跑了并留下了读数** —— 那些读数**就是**「fake 全绿 / 只有源码层 / 自标 informational」。
> 它们计为「已验」是因为判据确实跑过；但它们对应的**活体行为面从未被证明**，已进下方未覆盖清单。

---

## Wave 0 Requirements

不需要。21 / 21 个 task 自带 `<verify><automated>`。

---

## 未覆盖项（诚实说明）

**`04-06` 的「全量校验」全绿 ≠ 21 个 task 都已验，更 ≠ 5 条 SC 达成。**
`04-VERIFICATION.md` 的判定是 **`score: 1/5 must-haves verified`**，`status: human_needed`。
四条 SC 是 `PRESENT_BEHAVIOR_UNVERIFIED` —— **present + wired，行为未活体验证**，成因是锁屏。

| # | 未覆盖项 | 为什么自动化不了 | 证据 |
|---|---------|----------------|------|
| 1 | **SC1 首启真弹框 + 选完当场递归起播** | 装配链写死且有单测，但 app 级活体证据因锁屏未采集 | `rotation-wiring.log:PIC_ROT_APP_LAUNCH informational=1 reason=app-launch-blocked-by-locked-screen` |
| 2 | **SC2 真实 `AVFoundationAssetProbe` 拒坏文件** | **单测全用 fake**；真实探针从未对坏文件跑过 | `media-library.log:MEDIA=absent` `:PROBE_REJECTED=0`（全收 FakeProbe）。白名单半句 ✅ VERIFIED，坏文件半句未验 |
| 3 | **SC3 菜单「立即下一个」端到端** | 模型层已测（`testPerformNextVideoCallsOnlyItsInjectedClosure`），**真实菜单点击那一跳**需人点 | 列入人工项 |
| 4 | **SC4 跨进程重启后自动读取目录并播放** | 机制全在（`SettingsStore.sourceFolder` 持久化 + 13 条单测 + 启动序列写死），但**跨进程 UserDefaults → 起播**是运行时状态迁移，无活体证据 | `04-VERIFICATION.md` SC4 行 |
| 5 | **SC5 真实窗口 `orderOut` 效果 / 「露出系统原壁纸」** | 探针只覆盖 attach/teardown 可见性；**「看起来是不是系统原壁纸」需人看屏幕** | `WallpaperWindowController.swift:54-63` |
| 6 | **两个探针本次未复跑** | 验证红线为「只读源码，可跑 swift test / test.sh」；探针会建/删 fixture 目录、收紧权限，且媒体库探针要起真实 NSWindow（锁屏下不可靠） | `04-VERIFICATION.md` Probe Execution：两探针均 `? SKIP` |
| 7 | **TEST-02 两个子项缺测**（空目录扫描 / 无权限 errorHandler 路径） | 未写用例 | `04-VERIFICATION.md` Gaps Summary Warning 1 |
| 8 | **G-04-3b 的主观观感待用户复测** | 空队列帧从结构上消除了，但「看不出空帧」是观感 | `04-UAT.md:resolved_gaps_note` |

### ⚠️ `04-UAT.md` 内部数字自相矛盾（判读时注意）

`04-UAT.md` 的 Summary 块写 `passed: 4 / pending: 0`，
但它自己的 Tests 段里 **Test 2 / 3 / 4 / 5 全是 `result: [pending]`**，只有 Test 1 是 `result: pass`。
**两者对不上。** 本文件采信 `04-VERIFICATION.md`（`1/5` verified、4 条 `PRESENT_BEHAVIOR_UNVERIFIED`），
不采信 UAT 的 `passed: 4`。这两份文件的数字需要在解锁会话后重新对账。

### 本 Phase 的 5 条 SC 判定（逐字取自 `04-VERIFICATION.md`）

| SC | 判定 | 要点 |
|----|------|------|
| SC1 首启弹框选目录后立即递归播放 | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | 装配链完整 + 单测全绿；app 级活体未采集 |
| SC2 只识别 MP4/MOV/M4V，且排除解不出视频轨的文件 | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | **白名单半句 ✅ VERIFIED**；坏文件半句只验到 fake |
| SC3 三种模式当场生效；到点就切；「立即下一个」即时生效 | **✓ VERIFIED** | 行为级单测全绿（含 `testRotationElapsedAdvancesWithoutWaitingForPlayback`）；结构保证轮换器零 player 引用 |
| SC4 重启自动读已配置目录并播；换目录立即换新片；「重新扫描」可缓存 | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | 机制 + 单测全绿；app 级重启自动播无活体证据 |
| SC5 无可用视频/文件夹被删 → 隐藏壁纸窗口露出系统原壁纸 | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | 纯函数 6 条 + 执行层 5 条全绿；真实 orderOut 效果需人看屏幕 |

**1 VERIFIED / 4 PRESENT_BEHAVIOR_UNVERIFIED —— 四条的成因全部是「锁屏导致 app 级活体证据未采集」，无一是代码缺失。**

---

## 全量复跑读数（2026-10-04 本机实测）

| 命令 | 读数 | Phase 4 当时读数 |
|------|------|----------------|
| `swift test` | `Executed 199 tests, with 0 failures` · exit 0 | `124/124 pass` |
| `bash test.sh` | **通过 104 · 失败 0 · 跳过 1** · exit 0（跳过 = Phase 7 的 7 天长跑） | `69 pass / 0 fail / 0 skip` |

---

## Validation Sign-Off

- [x] 所有 task 都有 `<automated>` verify（21/21，含 gap 修复的 `04-07` 3 条）
- [x] 无连续 3 个 task 缺 automated verify
- [x] Wave 0 无 MISSING 引用 → `wave_0_complete: true`
- [x] 无 watch-mode 标志
- [x] 未覆盖项已逐条列出（8 项）
- [ ] **两个探针本次未复跑** —— 本文件依赖入库 evidence，未重新采集活体读数
- [ ] **`04-UAT.md` 与 `04-VERIFICATION.md` 数字矛盾**，待解锁会话后对账
- [ ] **把 frontmatter 的 `nyquist_compliant` 翻成 `true` —— 未达成。** 需先补 5 项 app 级活体证据，再实跑 `/gsd-validate-phase`

**Approval:** pending —— `/gsd-validate-phase 4` 从未跑过
