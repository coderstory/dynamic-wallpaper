---
gsd_state_version: "1.0"
milestone: v3.0
current_phase: 02
current_phase_name: 播放内核竖切
status: executing
stopped_at: ROADMAP.md / STATE.md / REQUIREMENTS.md Traceability 生成完毕
last_updated: "2026-10-02T22:20:20.222Z"
last_activity: 2026-10-03
last_activity_desc: Phase 01 execution started
state_head: 6a83c2f3851f4be87e5cabb0d6c6d47b3c5ecd13
progress:
  total_phases: 7
  completed_phases: 0
  total_plans: 9
  completed_plans: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-10-03)

**Core value:** 桌面一直是活的视频，而且不偷电、不抢性能 —— 全屏 / 锁屏 / 用电池时自动让路。
**Current focus:** Phase 01 — 桌面层级门禁 spike

## Current Position

Phase: 02 (播放内核竖切) — READY TO EXECUTE
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

**恢复命令：** `/gsd-verify-work 1`

---

## Session Continuity

Last session: 2026-10-03
Stopped at: ROADMAP.md / STATE.md / REQUIREMENTS.md Traceability 生成完毕
Resume file: None
