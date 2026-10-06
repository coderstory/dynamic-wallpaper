# Phase D 发现清单

> 深度审计主线 Phase D：常驻成本 + UX + 注释合理性。

## D.1 常驻隐性成本

### 发现 D1-1（🔵 Minor）：扫描串行探测导致首屏延迟

- **位置**：`MediaLibrary.scan` :136 `for` 循环内 `await probe.metadata(entry)`
- **现象**：每个视频串行开 `AVURLAsset` 读视频轨/帧率/时长。几百个视频的片库，总时间 = 单文件 × 文件数，是「壁纸开始播放」的主要延迟。
- **判断**：`scan` 是 async 的、`@MainActor` 上 `await` 不阻塞 UI（菜单栏图标仍秒开），延迟的是「壁纸出现」时间。Minor 而非 Critical。
- **方案**（可选）：探测并发化（`withTaskGroup` 分批），或「先播第一个、其余后台补扫」。但需权衡：并发开 AVURLAsset 会瞬时拉高 IO/CPU，对 24h 常驻 app 未必划算。

### `which` 的 waitUntilExit（确认非问题）

- `ExternalToolLocator.locate()` 先查显式路径（`/opt/homebrew/bin/ffmpeg`、`/usr/local/bin/ffmpeg`），命中即短路返回，不走到 `which`。仅两处都不存在时才 `which ffmpeg`（几 ms 瞬时），启动路径的同步阻塞可忽略。

### release 版 2 秒定时器（已修，P2-5）

- `startObservability`/`tick` 已整体包进 `#if !PIC_NO_PROBE`，交付二进制不再每 2 秒空转。

## D.2 UX

- 菜单「暂停」语义、转码队列无取消、自绘滑杆无 VoiceOver——这些在 P3 已列，属已知待办，不重复。
- 深度审计未发现新的 UX 问题（Phase A 的 A1-1 已顺带修了菜单 pause/resume 的真相源分散）。

## D.3 注释合理性

- 注释精简是审计后的修复项（任务 #34），将在主线审计收口后统一执行。
- 前六轮 + 本轮已修 B3-1（deletesSource 漂移）、删 65 处 MARK、补 2 处注释精度（A3-1）。
