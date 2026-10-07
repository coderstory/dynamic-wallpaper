# Pic 现状与未修问题

> **唯一一份活文档。** 历史过程报告已整体删除 —— 报告是快照，写完其中的结论就陆续失效，留着只会误导。
> 改动过程看 `git log`，逐轮「为什么这么改」看 `.workbuddy/memory/`。

## 现状快照

- 产品代码 **7365 行**（`PicCore` 纯逻辑 + `PicApp` 装配与 UI），零第三方依赖，仅 macOS 27
- 测试 **6051 行 / 344 用例，0 skipped**，`swift test` 全绿（现查：2026-10-07）
- 验收只有 XCTest 一条路（原 `scripts/` + `test.sh` + `UITests/` 那套「emit 打点 + shell grep」已整体删除）
- 构建：`swift build` 编译交付；`./build.sh` 出 .app + DMG（不签名）

## 未修问题

**无。** 最后逐条复核：2026-10-06。

原先 9 条要么已修（转码页取消/暂停、换屏重建窗口、滑杆 VoiceOver、scheduler 主线程契约、
`LineSplitter` 锁外 emit、转码途中换目录路径快照、删恒 skip 的测试），要么判定不做后移进下面
「明确不动」（首屏探测走有界并发；拔盘重生的实现方式）。已修的条目不再留在表里。

## 明确不动（复核过，别再「顺手优化」）

1. **全屏几何的内缩补偿 + 按 pid 聚合**。换「覆盖率容差」是**更差**方案：补偿后真全屏的
   coverage 正好 = 1.0，阈值才能钉死在精确 1.0；改容差（≈0.96）等于放宽阈值，正好复活
   「铺满 visibleFrame 但够不到刘海」那类假阳性。Chrome 同 pid 两扇窗必须合并求和，逐窗口必漏判。
   ⚠️ 内缩 14/9 是 **1470×956 的实测值**，换屏要重新量；量偏的表现是「真全屏没被识别」（漏暂停），
   不是误判。
2. **两个转码队列不抽公共流水线**。差异 6-7 处（终态语义、是否写帧率表、取消处置），硬抽要引
   6-7 个钩子，是 DRY 陷阱。别被「两段长得像」骗。
3. **类型化观察口保留**（`scanCount` / `loadCount` / `isReconfigurationRegistered` /
   `isSourceRegistered` / `RotationController.advances`）。它们锁的是「缓存命中 / 未重载 / 注册幂等 /
   切换原因」这类真行为，删了要拿 mock 替代 —— 代码更多，判据更弱。
   `advances` 尤其是 `reason` 的**唯一**出口，而 reason 是「单循环不重载同一片」那条修复的判据。
4. **验收不得再引入字符串打点**（`emit` / 输出行 grep）。那套体系需要产品代码常驻打点，
   比等价断言更脆弱，且会渗进交付二进制。
5. **探测并发度锁在 4、目录重生走轮询**。前者：探测受磁盘 IO 限制、本机只有一块盘，
   放开并发只会把 IO/CPU 打满而不更快（`MediaLibrary.probeConcurrency`）。后者：拔盘重生用
   3 秒轮询而非 FSEvents ——    FSEvents 要盯「不存在的路径」的父目录、还得在卷重挂后重臂 fd，
   复杂度远高于收益；而轮询只在**目录缺失期间**活着，目录正常时一次都不跑。
6. **设置窗开着时，`toggleMenuPanel` 刻意不借 `NSApp.activate`**。AppKit 的激活语义是
   「把本 app 的 main/key 窗口一并抬到最前」（`NSRunningApplication.h` 原文），借了就等于把用户
   背后开着的设置窗顶到最前。代价只有一个：那一档里 ⌘, / ⌘Q 要等用户点进面板（系统随之激活）
   才开始递送。**改回无条件 activate = 复现「点托盘图标把主窗置顶」。**
   对应的兜底关闭也因此多了一条 `didActivateApplication`（见下条）。
7. **面板的三条兜底关闭必须各订各的中心**：`didResignActive` 在 `NotificationCenter.default`，
   两条 `NSWorkspace` 的在 `NSWorkspace.shared.notificationCenter`。`NSWorkspace` 的通知**不会**
   投到 default 上 —— 订错地方不报错，只是守卫静默失效、面板悬空。
   三条都要：设置窗开着时本 app 从不激活，`didResignActive` 永远不来。

## 目录清单（哪些在 git 里、哪些不在）

| 目录 | 在 git？ | 是什么 | 删了会怎样 |
|---|---|---|---|
| `assets/` | ✅ | app 图标 10 档 + 菜单栏图标 3 档，`build.sh` 的唯一资源来源 | `./build.sh` 跑不起来 |
| `fixtures/` | ✅ | `clip-a/b.mp4` 各 2 秒（共 52K），`PlayerController` 那两条用例需要真实可解码视频 | 用例直接红（刻意不 skip） |
| `build/` `dist/` | ❌ | 构建产物（`.app` / `.dmg`） | `./build.sh` 重建 |
| `.build/` | ❌ | SwiftPM 构建缓存（本仓最大的本地目录） | 下次 `swift build/test` 从零编 |
| `cpp-singleton-logger/` | ❌ | 某轮会话交付的 C++ 单例日志器示例，刻意不纳入本仓库 | 与 Pic 无关 |

夹具重造（需要系统 `ffmpeg`）：

```bash
ffmpeg -y -f lavfi -i "testsrc=size=320x240:rate=15:duration=2"  -c:v libx264 -pix_fmt yuv420p -crf 35 -movflags +faststart fixtures/clip-a.mp4
ffmpeg -y -f lavfi -i "testsrc2=size=640x360:rate=15:duration=2" -c:v libx264 -pix_fmt yuv420p -crf 35 -movflags +faststart fixtures/clip-b.mp4
```

## 相关文档

- `CLAUDE.md` —— 写代码时遵守的规则（注释 / 设计 / 删除 / 测试 / 文档纪律、操作红线、架构约束）
- `docs/agents/*.md` —— 协作流程（issue tracker / triage 标签 / 领域文档约定）
- `.workbuddy/memory/` —— 逐轮工作流水账（含每轮「为什么这么改」），不是给人读的文档
