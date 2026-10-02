# WINDOWS —— 跨阶段缺陷登记簿

> 每条缺陷在此留档，直到有人真的修掉并把 `status` 改成 `resolved`。
> `/gsd-ship` 在存在任何 `open` 条目时不允许收口。
>
> 录入口径：**没跑过的验证**、**跳过���测试**、**留下的桩**、**与计划的偏离**。
> 证据文件里不许有形容词 —— 每条都要能指回一个文件或一条命令。

---

## open

### W-2026-10-03-01 · unrun-verify · Phase 2 / Plan 02-02

- **描述**：`evidence/loop.log:BLACKFRAME=blocked reason=no_screen_recording_permission` —— SC2「无黑帧」未被证明。
- **证据**：两张屏取回的平均亮度都停在 YUV 黑电平 16.0（白对照 235，阈值 23），即取回的帧没有任何桌面内容。本机拿不到桌面真实像素，黑帧判定在原理上无法进行。
- **影响**：ROADMAP Phase 2 SC2 后半句「无黑帧」**没有**被本 Phase 证明。
- **解开条件**：给终端/CLI 授屏幕录制权限后重跑 `bash scripts/run-probe.sh loop`，脚本无需修改；或在能看屏幕的会话里人工观察 5 分钟。
- **status**：open

### W-2026-10-03-02 · unrun-verify · Phase 2 / Plan 02-02

- **描述**：SC5「切换 Space 后壁纸不消失」未被验证。
- **证据**：需要真人 Mission Control 操作与多 Space 环境；本机 `screens_count=1`（`evidence/inset.log:SCREENS_COUNT`）且会话锁定。
- **影响**：SC5 的前半句「未做任何 Space 级特殊处理」已由 `test.sh` 的源码断言自动覆盖（`Sources/` 内 `activeSpaceDidChangeNotification` 计数 0）；后半句是 BLOCKED。
- **解开条件**：Plan 02-04 打包成 `.app` 后由真人手动切一次 Space；或接入多显示器环境。
- **status**：open

### W-2026-10-03-03 · unrun-verify · Phase 2 / Plan 02-01 继承

- **描述**：D-06 / PDCA-A1 的解锁会话门禁复跑仍未闭合，`GATE=A` 的适用边界仍限定在锁屏会话。
- **证据**：`.planning/phases/02-playback-core/evidence/gate-rerun.log` 首行 `GATE_RERUN=blocked`；`lock-state.txt` 记 `LOCKED=1`。
- **解开条件**：解锁后跑 `bash .planning/spike/run-gate.sh`（约 1 分钟，脚本无需修改）。
- **status**：open

### W-2026-10-03-04 · deviation · Phase 2 / Plan 02-02

- **描述**：计划的循环判据①原写 `endedCount == 0`，在本机被实测证伪并已纠正为 `endedCount == cycles`。
- **证据**：`evidence/loop-run1-original-criterion.log` —— 第一轮 `LOOP_ENDED=37`、`LOOP_CYCLES=37`、`LOOP_STALLED=0`、`LOOP_FAILED=0`、150 个采样点全部 `status=playing`。`AVPlayerLooper` 靠这条通知换片，每圈一次是正常的。
- **纠正**：`Sources/PicCore/Playback/LoopProbe.swift` 的判据①改为「失败数为 0 且播完次数等于循环圈数」，并在文件头写明纠正理由。**产物数值未做任何改动。**
- **status**：open（作为流程缺陷留档，防止 Phase 3/4 再抄一次错的判据）

### W-2026-10-03-05 · deviation · Phase 2 / Plan 02-02

- **描述**：D-09「本机常驻 4 个同类壁纸 app，至少一个同处桌面层」在本锁屏会话未复现。
- **证据**：`evidence/order.log:FOREIGN_SAME_LEVEL=0`、`FOREIGN_OWNERS=none`；但同层族（±64 级）内有 `FOREIGN_DESKTOP_FAMILY=7` 个外来窗口，`PID_CLAIM_REQUIRED_BAND=1`。
- **保留真值**：不把 0 改写成 1。按 PID 认领的纪律照旧，产品代码不依赖这个数字。
- **status**：open（Phase 3 起在解锁会话复测）

### W-2026-10-03-06 · deviation · Phase 2 / Plan 02-02

- **描述**：计划 `success_criteria` 要求「`Sources/` 全树 `CGWindowLevelForKey` 0 次」，与 D-04 钦定的唯一层级写法直接冲突。
- **证据**：`Sources/PicCore/Render/WallpaperWindow.swift` 里 `level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))` 是 D-04 钦定写法，实测 `SELF_LEVEL=-2147483623`、`ORDER=ok`。要求该符号 0 次会把正确写法判成违规。
- **纠正**：按 T3 的五条源码断言执行（其中不含 `CGWindowLevelForKey` 全树计数），且该符号的 **0 次** 约束只作用于 `Sources/PicCore/Playback/WindowProbe.swift` 单文件 —— 已实测 0 次。
- **status**：open（防止 Phase 3/4 再抄一次自相矛盾的判据）

---

## resolved

（暂无）