---
gsd_state_version: "1.0"
milestone: v3.0
current_phase: 03
current_phase_name: 系统事件仲裁
status: executing
stopped_at: ROADMAP.md / STATE.md / REQUIREMENTS.md Traceability 生成完毕
last_updated: "2026-10-03T02:14:58.253Z"
last_activity: 2026-10-03
last_activity_desc: Phase 01 execution started
state_head: 62dfd18b283160416489125da64f0eec43553fb6
progress:
  total_phases: 7
  completed_phases: 0
  total_plans: 14
  completed_plans: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-10-03)

**Core value:** 桌面一直是活的视频，而且不偷电、不抢性能 —— 全屏 / 锁屏 / 用电池时自动让路。
**Current focus:** Phase 01 — 桌面层级门禁 spike

## Current Position

Phase: 03 (系统事件仲裁) — READY TO EXECUTE
Plan: 1 of 5
Status: Ready to execute
Last activity: 2026-10-03 — Phase 01 execution started

Progress: [░░░░░░░░░░] 0%

## Performance Metrics

**Velocity:**
- Total plans completed: 0
- Average duration: —
- Total execution time: 0.0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

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

### 🚫 硬件负载红线（用户 2026-10-03 叫停）

**转码 / VMAF 类实测默认不执行。** 一次 libvmaf 测量（`n_threads=8`）跑出 **779.9% CPU**，用户反馈「电脑都发烫」。

| 规则 | 说明 |
|---|---|
| 默认**不跑** | Phase 6 的 CRF/VMAF 实测不自动执行 |
| 需要时降载 | `-t 5`（5 秒片段）+ `-threads 2`，且**必须后台 + 可中断** |
| 跑之前先问 | 任何预期 CPU > 100% 的命令，执行前先向用户确认 |
| 已清理 | 779.9% 的 ffmpeg 进程已 kill；`/tmp/crfwork` 残留 222MB 待用户决定 |

**替代方案**：Phase 6 的「视觉无损」参数改用**保守默认值 + 显式标注「未实测」**，或在用户明确许可的低载配置下测。

### Pending Todos

None yet.

### Blockers/Concerns

- **Phase 1 是门禁**：层级方案证伪则整个架构作废，Phase 2–7 不得启动
- **未签名 app 上 `SMAppService` 行为【待验证】** —— SYS-01 最大不确定点，Phase 7 必须实测；退路是 `~/Library/LaunchAgents/` plist
- **Phase 6 需深度 research** —— 「视觉无损」的 CRF/preset/编码器未定、产物命名规则待设计（防扫描死循环）、GPL v3.0 自用义务边界【待验证】
- **`com.apple.screenIsLocked` 未文档化** —— 靠 Phase 1 实测；失效则 Phase 3 升级为需 research（真正降级方案未找到公开资料）
- **PROJECT.md 介绍段仍写着「签名 .app」** —— 与已定的「不签名 + DMG」不一致，属文档陈旧待修

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

---

## Session Continuity

Last session: 2026-10-03
Stopped at: ROADMAP.md / STATE.md / REQUIREMENTS.md Traceability 生成完毕
Resume file: None

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
