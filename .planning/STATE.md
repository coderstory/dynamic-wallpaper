---
gsd_state_version: "1.0"
milestone: v3.0
current_phase: 04
current_phase_name: 媒体库与轮换
status: executing
stopped_at: Phase 4 规划修复收尾 —— 6 plan 已修复，2 BLOCKER 修复中，修完即 execute
last_updated: "2026-10-03T09:06:50.824Z"
last_activity: 2026-10-03
last_activity_desc: Phase 04 execution started
state_head: cb9c55a62ae2b59aeebe76adca6734367eba7159
progress:
  total_phases: 7
  completed_phases: 3
  total_plans: 20
  completed_plans: 14
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-10-03)

**Core value:** 桌面一直是活的视频，而且不偷电、不抢性能 —— 全屏 / 锁屏 / 用电池时自动让路。
**Current focus:** Phase 04 — 媒体库与轮换

## Current Position

Phase: 04 (媒体库与轮换) — EXECUTING
Plan: 1 of 6
Status: Executing Phase 04
Last activity: 2026-10-03 — Phase 04 execution started

Progress: [███████░░░] 78%

## Performance Metrics

**Velocity:**
- Total plans completed: 14
- Average duration: —
- Total execution time: —

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01-spike | 5 | 5 | — |
| 02-playback-core | 4 | 4 | — |
| 03-system-events | 5 | 5 | — |

**Recent Trend:**
- Last 5 plans: —
- Trend: —

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- **窗口层级**：`CGWindowLevelForKey(.desktopWindow)` 在 Swift 可用（-2147483623），**不用** `.desktopIconWindow`（-2147483603，会盖住图标）。STACK.md 的硬编码建议已作废，ARCHITECTURE 正确
- **签名与分发**：不签名、不公证，但**要 DMG**（本机已装 `create-dmg` 1.3.0）
- **转码**：调用系统已装 `ffmpeg`；缺 ffmpeg 时降级不阻断。macOS 27 上 `brew install ffmpeg` 会失败（`lame` / `dav1d` 无 bottle），须给静态二进制等替代途径
- **最小代码量**：优先系统/框架能力；每引入抽象要说清现成的为什么不能用
- **设置窗尺寸以 UI-SPEC 为准**：780pt 固定宽 / min 680pt（FEATURES 的 460pt 已过时）
- **UI 已有可编译 spike**：`.planning/spike/SettingsSpike.swift`（自绘分段控件/滑杆/ToggleStyle/图标瓷砖发光全部实跑过）
- **test.sh 证据隔离（31b4868）**：探针产物落临时目录（`PIC_EVIDENCE_DIR`），不再覆盖 Phase 3 已提交 evidence；基线复验 50/0
- **D-14 裁定（1e6e88e）**：`no()` 文案**必须带** `ok()` 判据名（逐字相同，✅/❌ 区分）—— 04-CONTEXT 原「不要带」是反转误记，已改；W-2026-10-03-24 已入册

### Autonomous Run Directives (2026-10-03, `/gsd-autonomous`)

用户睡觉期间授权自主推进，三条硬性指令：

1. **卡住就跳过，别停** —— 任何需拍板的阻塞点（blocker / verification gaps / audit gaps）**自行裁决**，不反问。默认「跳过该阶段 / 继续不修 / 接受差距」，并记入 `## Deferred Verification` / `## Needs Human`。重试上限压缩到 1 次即跳（工作流默认 3 次）。
   **唯一例外：删除文件的操作（cleanup）必须停下来问。**

2. **每阶段完成后跑一次 PDCA 审计** —— Plan（must_haves 声称要什么）→ Do（实际产出什么）→ Check（差距）→ Act（下阶段怎么改，改动落到 CONTEXT.md / ROADMAP.md）。结果记入本文件。

3. **Phase 1 门禁证伪 → 自动转路线 B（.saver bundle）**，不回头问，做完再报。

### Phase 1 完成 · PDCA 审计结论（2026-10-03）

**判定 `GATE=A` —— 路线 A（desktop-level NSWindow）在本机成立，Phase 2 可启动。**
PDCA 全文：`.planning/phases/01-spike/01-PDCA.md`

**最重要的未闭合项（PDCA-C1）**：Phase 1 的**全部**测量都在**锁屏会话**内完成（`UserIsActive 0`，`loginwindow` PID 489 自采集起未变）。注意：逐行自带 `LOCK=` 标注的只有 `fullscreen-scenarios.log` 与 `ab-verdict.txt`，其余日志靠上述三处独立佐证。门禁结论的适用边界**未在有前台进程的环境验证** → 已列为 **Phase 2 的第一个强制前置任务**（ROADMAP Phase 2 已写死）。

**已落进 ROADMAP 的硬约束：**
- Phase 2：解锁会话重跑 `run-gate.sh` 为强制前置；层级写法照抄 VERDICT；`.accessory` 断言用 1；用 `NSScreen.displayLink`
- Phase 3：🔴 **禁用 0.95 覆盖率阈值**（`FALSE_POSITIVE_OBSERVED=1` 已证伪）；🔴 处理 14pt/9pt 几何内缩；⚠️ 锁屏跃迁必须实测

**Phase 1 零交付项：** SC5 整条 BLOCKED（`AB_GROUPS_MEASURED=0`，`SCREENLOCK=unknown`）。

### Phase 2 完成 · PDCA 审计结论（2026-10-03）

**Phase 2 目标达成**：产品代码 14 文件 / 1279 行 / 零第三方依赖；`test.sh` 15 → **32 项全绿**；`swift test` **24 项**；DMG 打包成功；三接口（`SettingsStore` / `HoldArbiter` / `PlayerController`）已冻结供 Phase 3–7 依赖。
PDCA 全文：`.planning/phases/02-playback-core/02-PDCA.md` · VERDICT：同目录 `02-VERDICT.md`

**SC 结论：** SC1 PASS-with-gap · SC2 PARTIAL · SC3 PASS-with-gap · SC4 PASS · SC5 PARTIAL（4 项 BLOCKED 全是环境限制，非疏漏）

**移交 Phase 3 的硬约束（已写进 ROADMAP）：**
1. 🔴 四类系统检测**必须走事件通知**，禁止逐帧轮询 —— Phase 2 实测 `.app` 下刷新回调仍是 `timer_fallback_hz30`
2. 🔴 `PIC_HOLD` 是 0.5 秒轮询，短暂停会漏采 → 改事件驱动
3. 🔴 全屏检测**禁用 0.95 阈值**（Phase 1 已证伪）
4. 🔴 桌面层窗口 14pt/9pt 内缩必须处理
5. ⚠️ **停止用「源码字面量 grep」做判据** —— 8 次自伤的共同根因，Phase 3 起改行为断言

### Phase 3 完成 · PDCA 审计结论（2026-10-03）

**Plan**：4 个 Watcher 各自独立可测 + veto 集合仲裁 + 解除后从原处续播；5 条 SC 全绿；零 UI。
**Do**：5 plan 全执行；veto 仲裁 + 4 个事件 Watcher（Lock / Display / Power / Fullscreen）装配完成；幂集测试自动从 2 扩到 **64 组**；判定口径落地为 `verdict = nonGeometricActive && covering`；`test.sh` **50 项全绿**、`swift test` **67 tests 全绿**。
**Check**：SC4 PASS（veto 仲裁 + 注入式反向验证转红）· SC5 PASS（续播锚点不漂移）· SC1 / SC2 / SC3 **PARTIAL** —— 自动部分全过，但**真实跃迁那一跳未观测**（屏幕全程锁着，四条 `*_TRANSITION=unobservable`；拔电源需物理动作）。缺口全部落在结论列，未塞脚注。
**Act**：缺口移交 Phase 4/7 并写进 ROADMAP —— ① 四类跃迁（`-20`）解锁后重跑三探针；② 全屏误暂停（`-23`）改判定口径前先重采 `probe-fullscreen.sh`；③ 判据禁裸 `grep -c`（累计自伤 12 次），`no()` 文案不得含 `ok()` 判据名。
PDCA 全文：`.planning/phases/03-system-events/03-PDCA.md` · VERDICT：同目录 `03-VERDICT.md`

### 🚫 ffmpeg / 转码类测试：可跑，但**必须手动**（用户 2026-10-03 拍板）

**规则：允许执行，但绝不允许进入常规测试路径。**

| 项 | 规定 |
|---|---|
| **可以跑** | 需要确定转码参数时，手动单独执行 |
| **禁止进入** | `test.sh` / `swift test` / 任何会被验证流程自动调用的路径 |
| **原因** | 一次 libvmaf 测量（`n_threads=8`）跑出 **779.9% CPU**，用户反馈「电脑都发烫」。`test.sh` 每次校验都跑 —— 转码测试若在里面，等于**每次校验都烤一次机** |
| **落地形态** | 独立脚本（如 `scripts/transcode-bench.sh`），**只能手动调用**，不挂 `test.sh` |
| **降载要求** | 手动跑时用 `-t 5`（5 秒片段）+ `-threads 2`，后台可中断 |
| **跑之前先问** | 任何预期 CPU > 100% 的命令，执行前先向用户确认 |

**给后续 Phase 的硬约束**：Phase 6 落地转码功能时，**不得**把任何 ffmpeg 调用写进 `test.sh` 或单测；需要断言转码行为时，断言的是**参数构造**（纯字符串/纯逻辑），**不是实际转码**。

### Pending Todos

None yet.

### Blockers/Concerns

- **Phase 1 是门禁**：层级方案证伪则整个架构作废，Phase 2–7 不得启动
- **未签名 app 上 `SMAppService` 行为【待验证】** —— SYS-01 最大不确定点，Phase 7 必须实测；退路是 `~/Library/LaunchAgents/` plist
- ~~**Phase 6 需深度 research**~~ —— **已解决（Phase 6 RESEARCH.md，2026-10-03，commit `2690614`）**：① CRF/preset/编码器已定 —— libx264 CRF 18 + preset medium（终值走本机 SSIM/VMAF 实测，手动）；② 产物命名已定 —— 不加后缀，目录隔离（`Converted/`）+ MP4 原生双闸门；③ GPL v3 已关 —— 自用零义务（GPLv3 §2 逐字引用）；DMG 分发也无义务（子进程 = separate works）
- **`com.apple.screenIsLocked` 未文档化** —— 靠 Phase 1 实测；失效则 Phase 3 升级为需 research（真正降级方案未找到公开资料）

## Deferred Items

Items acknowledged and deferred at milestone close, most recent first:

| Category | Item | Status | Deferred At | Milestone |
|----------|------|--------|-------------|-----------|
| 显示 | DISP-01 多显示器铺满 / DISP-02 每屏独立配置 | v2 | 2026-10-03 | v1 |
| 媒体库 | LIB-01 自动监听文件夹 / LIB-02 失效自动恢复 | v2 | 2026-10-03 | v1 |
| 界面 | UI2-01 浅色主题 / UI2-02 滑杆自绘摆脱系统外观 | v2 | 2026-10-03 | v1 |
| 转码 | TR2-01 队列持久化断点续传 / TR2-02 批量并发控制 | v2 | 2026-10-03 | v1 |

## Deferred Verification

| Phase | State | Resume |
|-------|-------|--------|
| 01 | verification_deferred_human | 见下 —— 四项需真人在场，共约 22 分钟 |
| 04 | verification_deferred_human | 5 项需解锁会话 —— 见 `04-UAT.md`（SC1 首启即播 / SC2 真探针拒坏文件 / SC3 立即下一个 / SC4 重启自动播 / SC5 删目录降级恢复） |
| 05 | verification_deferred_human | 见下 —— 一项**永远无法自动化**的听音 + 一批解锁会话重跑项 |

**Phase 1 待人工补跑清单（自动化无法覆盖，已核实为硬约束非疏漏）：**

| # | 事项 | 成本 | 为什么自动化不了 |
|---|------|------|-----------------|
| 1 | `bash .planning/spike/powermetrics_ab.sh` —— 四组 × 5 分钟功耗 A/B | ~21 分钟 | `powermetrics must be invoked as the superuser`；`sudo -n true` 返回 `a password is required` |
| 2 | 锁屏 / 解锁各一次，观察 `com.apple.screenIsLocked` 与 `CGSSessionScreenIsLocked` 是否跃迁 | 10 秒 | 需要真实的锁屏跳变，无人值守时屏幕全程已锁 |
| 3 | 人工确认桌面图标可点选、可拖动，且壁纸在图标后面 | 10 秒 | 需真人手点（D-02 已定为「事后补做，不阻塞」） |
| 4 | 在**解锁会话**中重跑 `run-gate.sh` | ~1 分钟 | 屏幕当前锁着（PDCA-C1）；**这条同时是 Phase 2 的强制前置** |

**Phase 2 新增（用户 2026-10-03 拍板）：**

| # | 事项 | 成本 | 说明 |
|---|------|------|------|
| 5 | ~~申请屏幕录制权限~~ **✅ 已授权 2026-10-03** | — | 实测确认：`screencapture` YAVG 从 Phase 1/2 的 **16（纯黑占位图）** 变为 **242（真实画面）**；全屏抓图两次 md5 不同（`b500e322…` / `d76028fe…`）而占位图恒为 `aa30b1bd…`。**解锁三项自动验证** | 系统设置 → 隐私与安全性 → 屏幕录制 → 加入终端/Pic。**未授予前，`无黑帧` / `铺满无黑边` / `图标点选拖动` 三项永远无法自动验证** |
| 6 | 交付物剥离测量脚手架的实现 | 编码任务 | 已拍板，落在 Phase 4 或 7 的 `build.sh`；判据 = 打进 `.app` 的二进制不得含探针符号 |

**恢复命令：** `/gsd-verify-work 1`

**Phase 5 待人工补跑清单（05-04 登记，与 `.planning/WINDOWS.md` 的 W 登记簿双记账）：**

| # | 事项 | 对应 W | 解锁条件 | 为什么自动化不了 |
|---|------|--------|---------|-----------------|
| 7 | **听 0.5× 与 2× 的人声，确认不变调** | W-33 | 真人在场，任意解锁会话 | **这一项原理上没有断言能表达。** 自动化只证明了两件事：音轨的 `.spectral` 在 item 创建时已落位（Phase 2 冻结面，单测锁）、`rate` 改动当场落到播放器（`PIC_SETTINGS_APPLY key=rate … applied=1`）。**参数设对了 ≠ 听过了** —— 用无人声或纯音乐素材不算 |
| 8 | 解锁会话重跑 `bash scripts/run-uitests.sh`（TEST-07/08/09/10 + G-04-3 + 拖速度共 11 条） | W-34（整体未跑）/ W-31（菜单实点）/ W-32（拖动漂移） | 解锁 | 本会话 `SCREEN_LOCKED=1`，XCUITest 跑前就被守卫挡成 `blocked`。**测试目标编译已通过（`XCODEBUILD_BUILD_RC=0`），但一条用例都没执行过** |
| 9 | 锁屏态打开设置窗目视「屏幕已锁定」副标签 | W-29 | 锁屏 + 能看见屏幕 | 活体目视；原因→文案的映射已由穷举单测逐字锁死，缺的只是「屏上真的出现这行字」 |

⚠️ 第 8 项的重跑**不需要改任何判据**：`run-uitests.sh` 会数出 `UITEST_SKIPPED=`，
逐条核对 skip 串里的 W 号在登记簿里找得到，找不到就 `W_FOR_SKIP_MISSING` 非 0 退出 ——
「没跑过」不允许静默冒充通过。

---

## Session Continuity

Last session: 2026-10-03
Stopped at: Phase 4 wave 1 执行中（04-01 worktree，T1 已提交 `01c4310`）；并行：Phase 5 规划（planner 运行中，UI-SPEC 契约 `fcb3e96`+`8f2d727`）；Phase 6 规划（planner 运行中，RESEARCH `2690614`）。并发上限 10。
Resume file: `.planning/phases/04-media-library/.continue-here.md`

---

## 屏幕录制权限已授权（2026-10-03）

| 项 | 授权前 | 授权后 |
|---|---|---|
| `screencapture` YAVG | **16**（纯黑电平 = 占位图） | **242**（真实画面） |
| 全屏抓图 md5 | 恒为 `aa30b1bd…`（固定占位图） | 两次抓图 `b500e322…` / `d76028fe…`（内容在变） |

**解锁的三项自动验证**（Phase 1/2 期间因无权限只能人工肉眼验）：
1. SC2「无黑帧」— Phase 2 的 `BLACKFRAME=blocked` 可解除
2. SC2「铺满 / 无黑边」— 窗口每边 14pt/9pt 内缩是否露出黑边，现在可测
3. SC1「桌面图标可点选拖动」— 可用合成点击 + 截图旁证

⚠️ **仍未解除**：屏幕锁着，所以「铺满无黑边」「图标点选」这两项即使能截图，也仍需解锁会话才能测到真实桌面内容。
