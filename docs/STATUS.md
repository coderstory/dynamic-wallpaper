# Pic 现状与未修问题

> **唯一一份活文档。** 2026-10-06 归并：原先 12 份过程报告（`audit-*` / `findings-*` / `*-plan`）
> 描述的多是已修或已否决的状态，留着只会误导，已整体删除。结论都在本文。
> 改动过程看 `git log`，逐轮细节看 `.workbuddy/memory/`（那是流水账，不是文档）。

## 现状快照

- 产品代码 **6281 行**（`PicCore` 纯逻辑 + `PicApp` 装配与 UI），零第三方依赖，仅 macOS 27
- 测试 **5642 行 / 324 用例，0 skipped**，`swift test` 全绿
- 验收只有 XCTest 一条路：原 `scripts/` + `test.sh` + `UITests/` 那套「emit 打点 + shell grep」
  已整体删除（详见「明确不动」第 5 条）
- 构建：`swift build` 编译交付；`./build.sh` 出 .app + DMG（不签名）

## 未修问题（已逐条对当前代码复核，仍成立）

| # | 问题 | 位置 / 判据 | 为什么还没修 |
|---|---|---|---|
| 1 | **拔盘或目录消失后再插回，不自动恢复** | `MediaLibrary` 无 FSEvents / 目录监听；恢复的唯一途径是用户手点「重新扫描」 | 需产品预期（自动恢复 vs 保持手动），且要引入一个**生命周期受管**的目录监听（换目录要重开 fd、卷重挂要重臂）。单独一遍做，别在收尾时加 |
| 2 | **首屏「壁纸出现」延迟** = 视频数 × 单文件探测 | `MediaLibrary.scan` 循环内 `await probe.metadata(entry)` 串行 | **建议不做**：并发探测会瞬时拉高 IO/CPU，对 24h 常驻未必划算；替代方案（先播第一个、其余后台补扫）是行为改动，收益不明 |

**2026-10-06 已修**（原表 1/2/4/6/7/8/9 行）：转码页补了暂停/继续/取消（取消**退回 pending 可重试**，
不引入终态 —— `enqueue` 会永久排除已进过队列的源，标终态等于取消后再也转不了）；换屏重建壁纸窗口
（订阅 `didChangeScreenParametersNotification`）；自绘滑杆补 VoiceOver（`accessibilityAdjustableAction`
+ 标签 + 读数）；`RotationScheduling` 补主线程投递契约；`LineSplitter` 改为锁外 emit；
转码途中换目录改为从同一个目录快照推路径；删掉恒 skip 的 `RealLibraryPlaybackPoolTests`
（行为已被 9 条自足用例覆盖，且它会移动用户的真实文件）。
**2026-10-06 第二轮**：删掉那份八签名编译期签名锁与它护着的两个死成员（`attach(to:)` 生产零调用、
`playerLayer` 零读取）；夹具从 3.8M 缩到 52K 并**纳入版本控制**，两条用例的 `XCTSkip` 守卫随之删除 ——
skipped 由 2 归 0，干净 clone 与 CI 上现在真跑。
**已随之消失的旧问题**（留个交代，别再从旧报告里翻出来）：删源日志里「刻意打印文件名供审计」
那 3 处随打点体系一起删了 —— 现在日志里一个文件名都没有，可审计性有轻微下降，这是删打点的既定代价。

## 明确不动（复核过，别再「顺手优化」）

1. **全屏几何的内缩补偿 + 按 pid 聚合**。换「覆盖率容差」是**更差**方案：补偿后真全屏的
   coverage 正好 = 1.0，阈值才能钉死在精确 1.0；改容差（≈0.96）等于放宽阈值，正好复活
   「铺满 visibleFrame 但够不到刘海」那类假阳性。Chrome 同 pid 两扇窗必须合并求和，逐窗口必漏判。
   ⚠️ 内缩 14/9 是 **1470×956 的实测值**，换屏要重新量；量偏的表现是「真全屏没被识别」（漏暂停），
   不是误判。
2. **两个转码队列不抽公共流水线**。差异 6-7 处（终态语义、是否写帧率表、取消处置），硬抽要引
   6-7 个钩子，是 DRY 陷阱。别被「两段长得像」骗。
3. **不要再引入「编译期签名锁」**（用协议复刻签名来锁「签名没被改」）。曾经存在的那份
   （`PlayerControllerSurface` + 空 conformance）**已删** —— 复核后确认它护住的 `attach(to:)`
   生产侧零调用、`playerLayer` 零读取，等于用测试替两个死成员续命；两个成员已一并删除。
   签名演进靠行为断言守护，不靠锁。
4. **类型化观察口保留**（`scanCount` / `loadCount` / `isReconfigurationRegistered` /
   `isSourceRegistered` / `RotationController.advances`）。它们锁的是「缓存命中 / 未重载 / 注册幂等 /
   切换原因」这类真行为，删了要拿 mock 替代 —— 代码更多，判据更弱。
   `advances` 尤其是 `reason` 的**唯一**出口，而 reason 是「单循环不重载同一片」那条修复的判据。
5. **验收不得再引入字符串打点**（`emit` / 输出行 grep）。那套体系需要产品代码常驻打点，
   比等价断言更脆弱，且会渗进交付二进制。

## 目录清单（哪些在 git 里、哪些不在）

2026-10-06 清过一轮：`ffmpeg-kit-next/`(17M) / `.planning/`(12M) / 旧 `build/`+`dist/`(21M) /
散落截图与 `.DS_Store` 已**移入废纸篓**（不是真删，要恢复直接拖回）。

清理时暴露并修掉一个**既有缺陷**：`build.sh` 的 app 图标与菜单栏图标原本取自 gitignored 的
`.planning/design/assets/` —— 等于**干净 clone 上 `./build.sh` 必然失败**，交付构建不可复现。
已把那 13 个资源搬进受版本控制的 `assets/`，并把 `build.sh` 指过去。

| 目录 | 在 git？ | 是什么 | 删了会怎样 |
|---|---|---|---|
| `assets/` | ✅ | app 图标 10 档 + 菜单栏图标 3 档，`build.sh` 的唯一资源来源 | `./build.sh` 跑不起来 |
| `fixtures/` | ✅ | `clip-a/b.mp4` 各 2 秒（共 52K），`PlayerController` 那两条用例需要真实可解码视频 | 用例直接红（刻意不 skip） |
| `build/` `dist/` | ❌ | 构建产物（`.app` / `.dmg`） | `./build.sh` 重建 |
| `.build/` | ❌ | SwiftPM 构建缓存（约 190M，本仓最大的本地目录） | 下次 `swift build/test` 从零编，约 1~2 分钟 |
| `cpp-singleton-logger/` | ❌ | 某轮会话交付的 C++ 单例日志器示例，刻意不纳入本仓库 | 与 Pic 无关 |

⚠️ `fixtures/real-*.mp4` 是 3 个**指向使用者真实片库的软链**（不是夹具），已在 `.gitignore` 隔离。
删不删见下面「待你决定」第 2 条。

夹具重造（需要系统 `ffmpeg`）：

```bash
ffmpeg -y -f lavfi -i "testsrc=size=320x240:rate=15:duration=2"  -c:v libx264 -pix_fmt yuv420p -crf 35 -movflags +faststart fixtures/clip-a.mp4
ffmpeg -y -f lavfi -i "testsrc2=size=640x360:rate=15:duration=2" -c:v libx264 -pix_fmt yuv420p -crf 35 -movflags +faststart fixtures/clip-b.mp4
```

**顺带修掉一个测试侧泄漏**：`UserDefaults(suiteName:)` 的域文件不会因 `removePersistentDomain`
消失（cfprefsd 把空域写回磁盘），于是**每个用例在 `~/Library/Preferences/` 留一个 plist** ——
实测已积压 3029 个 / 12M，占该目录九成。已加 `Tests/PicCoreTests/TestDefaults.swift`
（清内存态 + 删域文件，带 `pic.tests.` 前缀守卫），实测跑完 324 个用例净增 3 个（此前约 +324 个）。

## 待你决定（都在仓库外或属流程约定，我不擅自动）

1. **历史积压的 3029 个测试 plist 还没清** —— `~/Library/Preferences/pic.tests.*.plist`，12M，
   占该目录九成。模式与真实偏好（`com.local.pic.plist`）不可能混淆，一条命令能清，但它在你的用户目录里。
2. **`fixtures/real-*.mp4` 那 3 个软链删不删** —— 使用者 `RealLibraryPlaybackPoolTests` 上一轮已删、
   代码里零引用，已是孤儿；已在 `.gitignore` 隔离，所以留着也不影响提交。删的只是软链，不碰你的真实视频。
3. **`docs/agents/domain.md` 里那句约定没有落点** —— 它写「共用根目录一份 `CONTEXT.md`，架构决策放
   `docs/adr/`」，但两者都不存在，且与「`STATUS.md` 是唯一活文档」相冲。要么建这两个位置，
   要么把那句约定删掉。那是协作流程的契约文件（不是代码），改它可能让工具侧找不到预期文件，故没动。

## 相关文档

- `CLAUDE.md` —— 写代码时遵守的规则（注释 / 设计 / 删除 / 测试 / 文档纪律、操作红线、架构约束）
- `docs/agents/*.md` —— 协作流程（issue tracker / triage 标签 / 领域文档约定）
- `.workbuddy/memory/` —— 逐轮工作流水账（含每轮「为什么这么改」），不是给人读的文档
