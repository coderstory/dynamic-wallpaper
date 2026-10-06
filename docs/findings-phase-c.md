# Phase C 发现清单

> 深度审计主线 Phase C：并发交错 + 播放切换稳定性 + 隐私。

## C.1 锁屏瞬间删壁纸

### 结论：无新问题，且因 A2-1 修复而受益

`deleteCurrentWallpaperNow` 时序：记 victim → 确认 → `advanceNow`（切下一个）→ `trashItem`（删旧片）。

`advanceNow` 触发的换片走 `onAdvance → loadPlayback → invalidateResumeAnchor + applyCurrentDecision`：
- `invalidateResumeAnchor` 清掉锚点，避免「删壁纸换片」破坏续播锚点
- `applyCurrentDecision` 走仲裁器决策，处于 hold 时不拉起播放器

即「锁屏瞬间删壁纸」这个交错，A2-1 的修复恰好覆盖了。无额外问题。

## C.2 转码中换目录

### 发现 C2-1（🔵 Nit）：tmp 与产物跨目录 move 的边缘健壮性

- **位置**：`TranscodeQueue.runJob` :197（temporaryURL 求值）与 :215（outputURL 求值）
- **现象**：`temporaryURL` 在 job 开始求值（旧目录），`outputURL` 在完成后重新求值（新目录）。转码过程中换目录，`moveItem(旧目录/tmp, 新目录/xxx.mp4)` 同卷是 rename 成功、跨卷失败 → `output_conflict`。
- **判断**：失败是安全失败（源保留、不丢数据），转码几十分钟窗口内恰好换目录是边缘场景。不构成需修的 bug。
- **可选**：若想更稳，可在 job 开始时同时固化 outputURL，与 temporaryURL 用同一个 root 快照。

## C.3 锚点错位

### 结论：已被 A2-1 覆盖（不重复）

hold 期间轮换定时器换片 → 旧锚点失效，已在 Phase A 的 `invalidateResumeAnchor` 修复。

## C.4 隐私日志纪律

### 结论：无隐私泄漏问题（通过）

日志泄漏文件名的只有 3 处，全在 `deleteCurrentWallpaperNow`：`PIC_DELETE_CANCELLED/OK/FAIL` 打印 `victim.lastPathComponent`。

- 这是**刻意的**：删除动作需要可审计（日志记录「删了哪个文件」供用户核对），且打印的是 `lastPathComponent`（仅文件名，不含路径），隐私风险极低。
- 其余所有 `emit` 均遵守「不打印路径/文件名」的纪律（注释明言「这一段只打印原因类别，绝不打印媒体路径」）。
