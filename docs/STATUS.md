# Pic 现状与未修问题

> **唯一一份活文档。** 历史过程报告已整体删除 —— 报告是快照，写完其中的结论就陆续失效，留着只会误导。
> 改动过程看 `git log`，逐轮「为什么这么改」看 `.workbuddy/memory/`。

## 现状快照

- 产品代码 **8873 行**（`PicCore` 纯逻辑 + `PicApp` 装配与 UI），零第三方依赖，仅 macOS 27
- 测试 **6980 行 / 全量 406 用例**：本机沙箱 396 绿（5 个进程类 10 例会挂起，见下）；CI 全量 406
- 验收两条路：`swift test`（PicCoreTests）+ `xcodebuild test`（PicUITests，XCUITest 由
  Pic.xcodeproj 承载；**无 GUI 会话跑不了**——系统自动化认证被拒，需真机跑一次）
- 构建：`swift build` 编译交付；`./build.sh` 出 .app + DMG（不签名）；版本经 `PIC_VERSION`
  注入并同步进 bundle（Info.plist 里的 0.1.0 只是开发期缺省）

## 未修问题（2026-10-09 全量审查后用户拍板：P0×1 + P1×11 已修，以下 P2 暂不修）

1. **图片模式「删除当前壁纸」借道共享轮换器**取当前 URL（经 VideoItem 包回），能用但语义绕；菜单项可见性只判 `!isEmpty` 不分 kind。
2. **MediaLibrary / ImageLibrary 首段枚举同步跑在 MainActor**（上限 5000 条 + resourceValues），大盘目录首次扫描可能卡主线程一拍。
3. **ImageWallpaperLoader 解码乱序已有 generation 防护，但 ImageLibrary.scan 仍每次全量**——无增量扫描。
4. **LockWatcher 观察者闭包强捕获 self**（与 DisplayWatcher 的 `[weak self]` 风格不一致）；存续期依赖 stop() 配对。
5. **DisplayWatcher CG 注册失败时全局表残留闭包**，stop() 不清（弱引用不悬垂，泄漏不配对）。
6. **PowerWatcher start 先置 isRunning**，source 注册失败永久失聪且不上报（连 stderr 都没有）。
7. **SettingsStore env 覆盖值经 persist() 固化进 UserDefaults**——开发会话一次 persist 后顶掉用户真实目录。
8. **SettingsView 音量滑杆 onChanged 是无效往返换算**（死代码）；QueueRow 在 body 里逐任务 stat 盘。
9. **ExternalToolLocator 探测表缺 MacPorts 路径**（/opt/local/bin/ffmpeg）。
10. **FFmpegAvailabilityTests 与 ExternalToolLocatorTests 覆盖高度重复**（两套同形 Fake）。
11. **PicUITests 5 用例从未真正执行过**（沙箱无 GUI 会话；断言本身未经验证）——真机首跑前别当成已验收。

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
8. **面板还挂着两条鼠标监听（全局 + 本地），是第 6 条的承重补偿，不是过度防御**。
   `.transient` 只在 app 活跃时才收到「点了面板外」；第 6 条让 app 不再激活，那套就失效，
   面板会一直悬着（用户实测）。全局监听**收不到发给本 app 的事件**（`NSEvent.h` 原文），
   所以点自己那扇没激活的设置窗要靠本地监听 —— 两条缺一，各自漏一半。
   本地监听里「面板内」与「状态栏图标」两种点击必须放过：前者归 SwiftUI，后者若要关掉，
   随后的 mouseUp 会把面板判成「没有面板」再重开一次。
9. **EXIF 口径成对契约**：显示用**摆正后**像素（`ImageDecoder` 经 `WithTransform` 摆正），
   档位判定用**存储**像素（宽高互换乘积不变）。两处成对注释在 decode 与 probe——只改一边
   就会出现「显示横躺」或「档位误判」，别当 bug 修回单边。
10. **液态玻璃关闭分支必须与平面路径逐字节一致**（`CardSurface` 读环境量 `\.cardSurfaceGlass`，
    默认 false）。这是「默认关 = 老用户零视觉变化」的硬承诺，别在关闭分支加任何透明度/阴影。
11. **转码进程不加 watchdog**（用户拍板 2026-10-09）：ffmpeg 挂死靠用户取消兜底；取消竞态已在
    spawn 前同锁复查封死。
12. **设置窗四个来源/档位/适配控件的判定阈值都存绝对值**（imageMinPixels 存像素不存下标、
    wallpaperKind/imageFit 存 rawValue），读不到就吸附/回落——加档位不迁移是这个设计的全部意义。

## 目录清单（哪些在 git 里、哪些不在）

| 目录 | 在 git？ | 是什么 | 删了会怎样 |
|---|---|---|---|
| `assets/` | ✅ | app 图标 10 档 + 菜单栏图标 3 档，`build.sh` 的唯一资源来源 | `./build.sh` 跑不起来 |
| `fixtures/` | ✅ | `clip-a/b.mp4` 各 2 秒（共 52K），`PlayerController` 那两条用例需要真实可解码视频 | 用例直接红（刻意不 skip） |
| `Tests/PicUITests/` | ✅ | XCUITest 5 用例；target 由 `Pic.xcodeproj` 手写承载，SwiftPM 不支持 macOS UI 测试 | xcodebuild test 少一条验收路 |
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
