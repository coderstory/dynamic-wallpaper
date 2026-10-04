---
phase: 06-transcode
slug: transcode
status: draft
nyquist_compliant: false
wave_0_complete: true
tasks_total: 11
tasks_verified: 5
tasks_unverified: 6
tasks_partial: 5
created: "2026-10-04"
updated: "2026-10-04"
---

# Phase 06-transcode — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

## 为什么 `status: draft` / `nyquist_compliant: false`

`/gsd-validate-phase` **从未在本 Phase 上跑过**。本文件是 2026-10-04 依据 PLAN / SUMMARY /
VERDICT / RESEARCH / evidence 手工补记的覆盖台账。按 `audit-milestone.md` §5.5（#2117），
`status: draft` = **NOT-VALIDATED（覆盖 TODO）**，不是合规失败。
本 Phase **没有 `06-VERIFICATION.md`** —— 判定权威是 `06-VERDICT.md`，无独立第三方复核背书。

---

## 🔴 本 Phase 最重要的一件事：门禁曾经「看不见」这个功能

**`Sources/PicApp/Transcode/` 的 4 个源文件从未登记进 `project.pbxproj`，整个 Phase 期间都是如此。**

2026-10-04 本机实测对账（`Pic.xcodeproj/project.pbxproj` 里 `Transcode` 的出现次数）：

| 版本 | `grep -c Transcode project.pbxproj` |
|------|-----------------------------------|
| `909c0d2^`（修复前） | **0** |
| HEAD（`909c0d2` 修复后） | **15** |

后果（HEAD commit `909c0d2` 的原文）：

> `xcodebuild build-for-testing` **RC=65**（`cannot find 'InstallPathwaysView'` / `'TranscodeScene' in scope`），
> `scripts/run-uitests.sh` 第 2 步卡死，**W-34 解锁后依然解不开**。
> **SwiftPM 自动发现让 `swift build` / `swift test` 全绿，只有 `xcodebuild` 会红 —— 现有门禁全都看不见。**

**这意味着本 Phase 的 11 个 task 里有 6 个的读数是「结构层」的**：
它们的 `swift build` / `swift test` 全绿，是因为**SwiftPM 按目录自动发现了这些文件**，
而**真正的 app target（Xcode）连编译都过不去**。绿灯是因为门禁看不见这个功能，不是功能被验过。

`909c0d2` 已补登记 4 条 `PBXFileReference` + 新建 `Transcode` `PBXGroup`，并加了跨构建系统一致性门。
**同模式此前已发生过一次**（05-03 的 `SettingsSessionState.swift`，commit `ffd0777`）—— **Phase 6 又犯了一次。**

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest via SwiftPM（注入式变异反向验证）+ 无头回归 `bash test.sh`（Phase 6 段 16 条纯逻辑门 + 红线拆串门） |
| **Config file** | `Package.swift` · `test.sh` · `scripts/probe-transcode-tracer.sh` · `scripts/transcode-bench.sh`（**手动专用，绝不上自动路径**） |
| **Quick run command** | `swift test --package-path . --filter 'Transcode\|ConvertedLibrary\|ExternalToolLocator\|ProgressParser'` |
| **Full suite command** | `bash test.sh` |
| **Estimated runtime** | swift test ~5 秒 · test.sh ~60 秒 |

> ⚠️ **ffmpeg 红线**：用户 2026-10-03 明令 HARD STOP —— 一次 libvmaf 跑测撞到 **779.9% CPU**。
> 现在 ffmpeg 默认关闭、仅限显式 opt-in 且限载。**`bash test.sh` 的工具段零 ffmpeg 进程调用**（常驻判据）。

---

## Sampling Rate

- **After every task commit:** 该 task 的 `<automated>`（`swift build` / `swift test --filter <Suite>` / tracer 探针）
- **After every plan wave:** `swift test --package-path .` 全量 + `bash test.sh` Phase 6 段
- **Before `/gsd-verify-work`:** `bash test.sh` 必须全绿
- **Max feedback latency:** < 30 秒

---

## Per-Task Verification Map

`wave_0_complete: true` 的依据：**11 / 11 个 task 在 PLAN 里都带 `<verify><automated>`**。

| Plan | # | Task | 有 `<verify>` 判据 | 证据来源 | 结论 |
|------|---|------|------------------|---------|------|
| 06-01 | 1 | TranscodeCommand（argv 逐 token 构造 + 审计展示串）+ TranscodeOutputNaming（`.tmp` 中间态 / mtime 幂等跳过） | ✅ `swift build … swift test --filter` + 变异 | `MUT-P6-PRESET` 变异真红（**红光来自断言不是编译失败**）；`PIC_TRC_ARGV_TOKENS=28` | ✅ 已验 |
| 06-01 | 2 | TranscodeCandidateFilter（mkv/avi/webm 白名单 + Converted 精确排除 + 符号链接跳过）+ ConvertedLibrary（D-23 第二入口 + 合并函数） | ✅ `swift test --filter` | 还原后复跑 `Executed 6 tests, 0 failures` | ✅ 已验 |
| 06-02 | 1 | ExternalToolLocator —— 显式路径探测 + `which` 兜底的注入式决策表（TEST-05 三态） | ✅ `swift test` + 变异 `MUT-P6-DETECT` | 变异真红，**4 条断言**同时失败；`124 tests, 0 failures` | ✅ 已验 |
| 06-02 | 2 | ProgressParser —— `-progress pipe:1` 的 key=value 解析 + end 标志 + **微秒语义**的百分比换算 | ✅ `swift test` + 变异 `MUT-P6-PROGRESS` | 变异在微秒语义那条用例上真红；0 compiler diagnostics | ✅ 已验 |
| 06-03 | 1 | TranscodeQueue（串行状态机 + 预检 + tmp→rename + 进度）+ ProcessTranscodeRunner（nice / terminationStatus / stdout 进度） | ✅ `swift test --filter TranscodeQueueTests` | `TranscodeQueueTests` 6 条（单列门）；`TranscodeMainActorFreezeTests` 1 条 —— **修 BLOCKER 前实测 0，修后 130~170** | ⚠️ **已验但读数已 stale** —— commit `565ae4d` 把 `runner.run` 改成 async **发生在这次读数之后** |
| 06-03 | 2 | 执行 tracer 活体证据 —— 候选 → 命令 → 假 runner 队列 → Converted 产物可播 → 不回流 → 幂等 | ✅ `PIC_TRC_*` 16 键逐条 grep | `PIC_TRC_RUNNER_CALLS_TOTAL=1`（证明不重复烤机）`:SOURCE_INTACT=1` `:TMP_GONE=1` `:PRODUCT_EXISTS=1` `:REFILTER_CANDIDATES=0` `:CONVERTED_PLAYABLE=1` `:SECOND_PASS_SKIPPED=1` `:JOB_STATE=succeeded` | ⚠️ **已验但从未在 `565ae4d` 之后重新生成** —— `test.sh` 的门 ⑥ 是**重读已入库的文件**，回归不会转红 |
| 06-04 | 1 | 转码窗四件 —— TranscodeWindowView + TranscodeViewModel + InstallPathwaysView + TranscodeScene | ✅ `src_count` 源码门 | 结构门全过 | ⚠️ **已验但只是结构层** —— **这 4 个文件整个 Phase 都不在 `project.pbxproj` 里**；屏上像素零读数（人工项①） |
| 06-04 | 2 | 入口接线 —— AppDelegate 持 availability + 「维护」行条件分派 + 收编 Phase 5 判定为单一真相源 | ✅ `src_count` 源码门 + `swift test` | `GATES refresh=3 which=1 … gate=421 < rate=422`；`ExternalToolLocatorTests` + `FFmpegAvailabilityTests` 6 条 | ⚠️ **已验但只是结构层** —— 同上；「入口置灰 + 三途径弹层」的**活体行为未验**（人工项②） |
| 06-05 | 1 | 装配闭环 —— `router.start` 入参合并（D-23）+ `onBatchFinished → invalidateCache + rescan`（SC#5 app 级） | ✅ `swift test` + 行号序判据 | `invalidateCache` 行 334 **<** `rescanAndApply` 行 336；三条 `test.sh` 门 ✅ | ⚠️ **已验但只是结构层** —— 「排空后 UI 上真的多了一个新片」是活体行为，**本会话未开转码窗转码过任何文件** |
| 06-05 | 2 | **`scripts/transcode-bench.sh` —— 手动 SSIM/VMAF 实测** | ✅ `bash -n` + 10 项 token 计数门 | 只过了语法与结构门 | ❌ **未验（人工 + 用户红线）** —— **ffmpeg 调用、SSIM/VMAF 解析、`BENCH_RECOMMEND` 的 awk 判定一行都没执行过** |
| 06-05 | 3 | test.sh Phase 6 段（16 条纯逻辑门 + 红线拆串门）+ 工具段简化 + 06-VERDICT + W-34 入册 | ✅ `bash -n test.sh` + 门禁段 | `bash test.sh` **通过 79 / 失败 0 / 跳过 5**（基线 63，**+16**）；拆串红线门变异真转红（判据非空） | ✅ 已验 |

**合计：11 个 task · ✅ 已验 9 · ⚠️ 已验但只有结构层 / 读数已 stale 5（06-03 T1、06-03 T2、06-04 T1、06-04 T2、06-05 T1）· ❌ 未验 1（06-05 T2 bench）**

---

## Wave 0 Requirements

不需要。11 / 11 个 task 自带 `<verify><automated>`。

---

## 未覆盖项（诚实说明）

**`bash test.sh` 通过 79 全绿 ≠ 11 个 task 都已验，更 ≠ 画质达标。**
`06-VERDICT.md` 的「人工清单」逐字写着：「以下四项**没有任何自动读数**，逐字保留为人工项，**不得记作 PASS**」。

| # | 未覆盖项 | 为什么自动化不了 | 证据 |
|---|---------|----------------|------|
| 1 | 🔴 **`scripts/transcode-bench.sh` 的 SSIM/VMAF 实测从未运行** | 只过了 `bash -n` 与 token 计数门。**真跑路径（ffmpeg 调用、SSIM/VMAF 解析、`BENCH_RECOMMEND` 的 awk 判定）一行都没执行过** | `06-VERDICT.md:SC#3` —— 阈值 **SSIM≥0.98 / VMAF≥95 是 `[ASSUMED]` 行业经验值，不是本机实测**；`06-05-SUMMARY.md` D3 `rationale` |
| 2 | **开转码窗目视** —— 徽章文案、队列条目、命令展示是否成行 | 结构有断言，**屏上像素无** | `06-VERDICT.md` 人工清单① |
| 3 | **入口置灰 + 三途径弹层** —— 临时 `mv /opt/homebrew/bin/ffmpeg{,.bak}` → 打开设置窗维护行应弹出三途径安装说明 → 复原后**重查**徽章应回到「可用」 | 需活体操作；**验完必须复原并重查** | `06-VERDICT.md` 人工清单② |
| 4 | **跑 bench 决定 CRF/preset 终值** | 同 #1。跑前先确认 CPU 占用（STATE.md 规则）；改了必须同 commit 更新 `TranscodeCommandTests` 测试 3 | `06-VERDICT.md` 人工清单③ |
| 5 | **核对 videotoolbox 可用性（不转码不烤机）** | 人工 `ffmpeg -h encoder=h264_videotoolbox` 确认 A3 的假定 | `06-VERDICT.md` 人工清单④ |
| 6 | **SC#2 队列串行 + 进度实时刷新 + 命令可审计展示的活体行为** | 自动侧（纯逻辑 + 桩）已过，**活体行为未验** | `06-05-SUMMARY.md` D2 `human_judgment: true` |
| 7 | **SC#5 转完即播的活体一跳** | 「排空后 UI 上真的多了一个新片」需开窗转码 | `06-05-SUMMARY.md` D2 `rationale` |
| 8 | 🔴 **`565ae4d` 之后的读数全部 stale** | `runner.run` 改 async 发生在 `PIC_TRC_*` 采集之后；`test.sh` 门 ⑥ 重读已入库文件，**回归不会转红** | `565ae4d` · `06-VERDICT.md` 记 `run 未返回时 percent 已送达` 修前 0 / 修后 130~170 |

### 本 Phase 的 5 条 SC 判定（逐字取自 `06-VERDICT.md`）

| SC | 判定 | 要点 |
|----|------|------|
| SC#1 检测 ffmpeg 存在性；不可用时入口置灰并给出安装途径 | **PASS（自动面）/ 待人工（行为面）** | 6 条单测 + 2 条 `test.sh` 门；三途径标记 `pathway:brew/static/source` 各 1 处。**行为面未做** |
| SC#2 队列串行 + 进度实时刷新 + 命令可审计展示 | **PASS（自动面）/ 待人工（行为面）** | 队列 6 条 + freeze 门（实测 137）+ runner 总调用 1 次。**活体未做** |
| SC#3 视觉无损（人眼基本看不出差异） | **PARTIAL —— 参数侧 PASS，画质侧 BLOCKED(manual)** | argv 28 token 已锁死；**SSIM/VMAF 无数值**，阈值本身也只是 `[ASSUMED]` |
| SC#4 产物落壁纸目录内（原视频保留不删） | **PASS** | `SOURCE_INTACT=1` / `TMP_GONE=1` / `PRODUCT_EXISTS=1` |
| SC#5 不回流 + 不污染播放源 + 转完即播 | **PASS（数据侧 + 装配侧）/ 画面侧待人工** | 回流 0 / 可播 1 / 二次跳过 1 / runner 总调用 1 |

**参数侧 PASS ≠ 画质达标。这两件事必须分开陈述。**

---

## 全量复跑读数（2026-10-04 本机实测）

| 命令 | 读数 | Phase 6 当时读数 |
|------|------|----------------|
| `swift test` | `Executed 199 tests, with 0 failures` · exit 0 | `190 tests, 2 skipped, 0 failures` |
| `bash test.sh` | **通过 104 · 失败 0 · 跳过 1** · exit 0（跳过 = Phase 7 的 7 天长跑） | 通过 79 / 失败 0 / 跳过 5 |

> 本次复跑发生在 `909c0d2`（pbxproj 补登记）**之后**，所以今天的 `swift test` 199 全绿
> **覆盖到了**转码 UI 的源文件 —— 这是 HEAD 才有的保证，Phase 6 执行期间没有这个保证。

---

## Validation Sign-Off

- [x] 所有 task 都有 `<automated>` verify（11/11）
- [x] 无连续 3 个 task 缺 automated verify
- [x] Wave 0 无 MISSING 引用 → `wave_0_complete: true`
- [x] 无 watch-mode 标志（ffmpeg 默认关闭、限载 opt-in）
- [x] 未覆盖项已逐条列出（8 项）
- [x] **已登记 pbxproj BLOCKER**：Phase 6 期间转码 UI 不在 app target 里，6 个 task 的读数只是结构层
- [ ] **`565ae4d` 之后未重采 `PIC_TRC_*` 读数**，`test.sh` 门 ⑥ 重读旧文件，回归不会转红
- [ ] **把 frontmatter 的 `nyquist_compliant` 翻成 `true` —— 未达成。** 需先跑一次 bench 取得 SSIM/VMAF 读数（需用户解除 ffmpeg 红线），再实跑 `/gsd-validate-phase`

**Approval:** pending —— `/gsd-validate-phase 6` 从未跑过
