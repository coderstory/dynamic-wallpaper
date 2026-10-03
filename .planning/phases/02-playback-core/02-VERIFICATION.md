---
phase: 02-playback-core
verified: 2026-10-03T00:00:00Z
status: gaps_found
score: 8/11 must-haves verified
covered_files:
  - .planning/phases/02-playback-core/02-VERDICT.md
  - .planning/phases/02-playback-core/02-PDCA.md
  - .planning/phases/02-playback-core/02-0*-PLAN.md
  - .planning/phases/02-playback-core/02-0*-SUMMARY.md
  - .planning/phases/02-playback-core/02-CONTEXT.md
  - .planning/WINDOWS.md
  - .planning/ROADMAP.md
  - .planning/REQUIREMENTS.md
  - test.sh
  - build.sh
  - scripts/run-probe.sh
  - Package.swift
  - Sources/PicApp/AppDelegate.swift
  - Sources/PicApp/PicApp.swift
  - Sources/PicApp/App/MenuContentView.swift
  - Sources/PicApp/Resources/Info.plist
  - Sources/PicCore/App/MenuItem.swift
  - Sources/PicCore/State/SettingsStore.swift
  - Sources/PicCore/State/HoldArbiter.swift
  - Sources/PicCore/State/HoldReason.swift
  - Sources/PicCore/State/PlaybackDecision.swift
  - Sources/PicCore/Playback/PlayerController.swift
  - Sources/PicCore/Playback/LoopProbe.swift
  - Sources/PicCore/Playback/WindowProbe.swift
  - Sources/PicCore/Playback/FrameDriver.swift
  - Sources/PicCore/Render/WallpaperWindow.swift
  - Sources/PicCore/Render/WallpaperWindowController.swift
  - Tests/PicCoreTests/HoldArbiterTests.swift
  - Tests/PicCoreTests/MenuBarModelTests.swift
  - Tests/PicCoreTests/SettingsStoreTests.swift
  - .planning/phases/02-playback-core/evidence/*.log
probes_executed: none (只读核对；未重跑 run-gate.sh / run-probe.sh / menubar-check.sh)
deferred: []

gaps:
  - truth: "VERDICT 的证据引用必须与它引用的文件一致（项目自订标准：每行挂一个真实证据路径与一个数字）"
    status: failed
    reason: "打包产物探针那一行把 order.log 的数字挂到了 app-bundle.log 上，写成『在打包产物上再测一次，仍是 0』；该文件实际读数是 1。"
    artifacts:
      - path: ".planning/phases/02-playback-core/02-VERDICT.md"
        issue: "第 123 行（W-2026-10-03-05 行）与第 46 行（跑过表 app-bundle 行）都写 FOREIGN_SAME_LEVEL=0 / FOREIGN_DESKTOP_FAMILY=7；evidence/app-bundle.log 第 12-14 行是 FOREIGN_SAME_LEVEL=1 / FOREIGN_OWNERS=Pic / FOREIGN_DESKTOP_FAMILY=8"
    missing:
      - "把该行改写成 app-bundle.log 的真实读数；若 `=1` 来自另一个残留的 Pic 进程（W-2026-10-03-05 恰好就是这条窗口），需说明它是探针 artifact 还是真实共存风险"

  - truth: "VERDICT 引用的日志行必须能在被引文件里逐字找到"
    status: failed
    reason: "刷新回调一节把两行当作逐字日志引用，但 refresh.log 里没有这两行；ticks 数字取自另一场运行（loop.log）。"
    artifacts:
      - path: ".planning/phases/02-playback-core/02-VERDICT.md"
        issue: "第 93-94 行引用 `REFRESH_RUN_MODE=swift_run DRIVER=timer_fallback_hz30 TICK_RATE=27.2` 与 app_bundle 同款；evidence/refresh.log 第 1、3 行是 TICK_RATE=27.1 与 27.0，第 2、4 行 tick_count=271 与 270。27.2/272 来自 evidence/loop.log:REFRESH_TICK_RATE / REFRESH_TICK_COUNT，是 loop 那一场的数字"
      - path: ".planning/WINDOWS.md"
        issue: "W-2026-10-03-11 同一处引用 TICK_RATE=27.2 / REFRESH_TICK_COUNT=272 指认 refresh.log，同样对不上"
    missing:
      - "改成 refresh.log 的 27.1/271 与 27.0/270；DRIVER 结论（两种形态都是 timer_fallback_hz30）不受影响，可以保留"
      - "说明 27.2/272 是 loop.log 那一场的数字，别让它冒充 refresh 那一场"

  - truth: "跑过栏的产物体量必须与磁盘上的产物一致"
    status: failed
    reason: "DMG 体积写成 141K，与 dist/ 下实际文件以及同 Phase 的 PDCA 都不一致。"
    artifacts:
      - path: ".planning/phases/02-playback-core/02-VERDICT.md"
        issue: "第 48 行写「DMG 141K」；dist/Pic-0.1.0.dmg 实测 149464 bytes（≈146 KiB）；02-PDCA.md 写的是 149 KB，test.sh 本次实跑也读到 149464"
    missing:
      - "改成实测值 149464 bytes（PDCA 的 149 KB 口径一致）"

  - truth: "SC2 的缺口清单要列全"
    status: failed
    reason: "SC2 一行只把「无黑帧」列为缺口，但「裁剪填满 / 无黑边 / 无变形」同样没有任何观测证据；而同一行引用的内缩数字恰恰说明窗口没有铺满屏幕。"
    artifacts:
      - path: ".planning/phases/02-playback-core/02-VERDICT.md"
        issue: "SC2 行把 INSET_LEFT=14 TOP=9 RIGHT=14 BOTTOM=9、SCREEN_FRAME=0,0,1470,956 列在通过侧。inset.log:7 的 WINDOW_FRAME=14,9,1442,938 —— 窗口比屏幕每边小 14/9pt，而这扇窗 isOpaque=true + backgroundColor=.black，那圈区域若有就是黑的。'铺满/无黑边'从未被看过"
    missing:
      - "把「无黑边 / 无变形」也写进 SC2 的缺口（代码层 resizeAspectFill 只能说明意图，说明不了结果），或明确写「由 resizeAspectFill 的语义保证，未肉眼复核」"

  - truth: "承接 WINDOWS.md 的那张表要与自己那句『一条都没有关闭』对得上"
    status: failed
    reason: "VERDICT 小节标题写「10 条窗口全部仍在 open，本 Phase 一条都没有关闭」，紧接着的表里 W-2026-10-03-09 标 resolved；且该表只覆盖 W-01…W-10，W-11/12/13 散在正文。"
    artifacts:
      - path: ".planning/phases/02-playback-core/02-VERDICT.md"
        issue: "第 114 行 vs 第 127 行；WINDOWS.md 的 ## resolved 段写「（暂无）」，而 W-09 / W-13 在 open 段内被标 resolved"
    missing:
      - "改成「10 条中 9 条仍 open，W-09 本 Phase 重验通过已 resolved」，并把 W-11/12/13 补进同一张表或改标题为「前 10 条」"

  - truth: "交给 Phase 3 的幂集子集数不能算错"
    status: failed
    reason: "Phase 3 加 5 个 HoldReason case 后是 6 个 case，幂集是 2^6=64；下游硬约束里写的是 32。"
    artifacts:
      - path: ".planning/phases/02-playback-core/02-01-SUMMARY.md"
        issue: "第 287 行与第 370 行（给下游的硬约束第 1 条）都写「自动从 2 个子集扩到 32 个」；同一份文件第 283 行写的是「幂集 2^6 = 64 子集」，02-VERDICT.md 与 02-PDCA.md 也都写 64。错误源自 02-01-PLAN.md:263"
    missing:
      - "把两处 32 改成 64（HoldArbiterTests 是运行时 `1 << all.count` 生成的，加完就是 64）"

---

advisory:
  - finding: "test.sh 的剥注释过滤器只处理行首注释，行尾注释仍会污染计数"
    category: other
    reason: "已实测复现：在 HoldReason.swift 某行代码后加 `// ... activeSpaceDidChangeNotification`，剥注释后计数 = 1，判据立刻假红。MenuContentView.swift 文件头写着「菜单定义一律单行，注释一律行首」当作缓解，但那是纪律不是机制，没有任何东西强制它"
    evidence_status: "已复现（本次实测）"
  - finding: "src_count 数的是『行数』不是『出现次数』，NSApp.terminate 唯一落点那条可被绕过"
    category: other
    reason: "实测：把两处 NSApp.terminate 写在同一行 → 行计数 = 1 → 判据判绿。判据要表达的是『恰好一处调用』，表达出来的却是『恰好一行含这个词』"
    evidence_status: "已复现（本次实测）"
  - finding: "菜单 Button/ForEach 那条判据完全不过滤注释"
    category: other
    reason: "实测：把 MenuContentView.swift 第 9 行注释里的 `Button` 改成 `Button(`，Button( 行数 2 vs ForEach 行数 1 → 判红，纯注释触发。第 9 行现在离这条判据只有一对括号"
    evidence_status: "已复现（本次实测）"
  - finding: "MENUBAR-08 那条 sed 区间判据在 struct 改名后会恒绿"
    category: other
    reason: "实测：把 `struct MenuContentView` 改名后，sed 取到空区间 → PN=0 → 判绿。判据自己的注释说「刻意不把范围缩到扫不到东西的形式」，但没有对『区间取空』本身做断言"
    evidence_status: "已复现（本次实测）"
  - finding: "Sources/ 里 1279 行有 493 行（38.5%）是测量脚手架，其中 LoopProbe 会打进交付的 .app 二进制"
    category: other
    reason: "LoopProbe 206 + WindowProbe 167 + FrameDriver 120。VERDICT 为 FrameDriver 写了「纯测量器、不接渲染路径」的论证，但没提 LoopProbe/WindowProbe 也在产品树里。Phase 1 的先例是把一次性探针放 .planning/spike/ 不进产品库。CONTEXT 的「最少代码」约束在这里有一条没被点名的例外"
    evidence_status: "已核对（行数与文件清单）"
  - finding: "REQUIREMENTS.md 的 Traceability 表里 Phase 2 的 8 条需求仍是 Pending，复选框全未勾"
    category: other
    reason: "Phase 2 已执行完毕但没有回写。与 Phase 1 同期状态一致（Phase 1 本就不交付需求），属记账缺口不是需求缺口"
    evidence_status: "已核对"
  - finding: "PIC_SOURCE_FOLDER 环境变量未被登记为攻击面"
    category: security
    reason: "任何能拉起 Pic 的进程都能把壁纸目录指到任意路径，产品随即枚举该目录。风险低（不写不删），但 security_enforcement=true 的 Phase 里它没出现在任何 threat 段。`PIC_LOOP_SECONDS` 同理"
    evidence_status: "已核对（grep 定位 env 读取点）"
  - finding: "PlayerController 没有 stop()，而 ROADMAP Phase 4 的 Notes 已经指名要它"
    category: other
    reason: "Phase 4 Notes：「无可用视频 / 文件夹失效 → `PlayerController.stop()` + `orderOut(nil)`」。orderOut 那一半（WallpaperWindowController.teardown）已在，stop() 没有。属新增而非改签名，所以不推翻「接口定死」，但 VERDICT 把 PlayerController 写成已定稿时没标这条已知缺口"
    evidence_status: "已核对（符号检索）"
  - finding: "refresh 探针的会话锁定判定 fail-open"
    category: other
    reason: "run-probe.sh:454-459 靠 ioreg 的 CGSSessionScreenIsLocked 单个键；键不存在时落入 `*)` 分支判成 unlocked。本次在本 agent 沙箱里 ioreg 读不到该键（可能是沙箱限制，也可能是该键并非稳定暴露）。失败方向是乐观方向 —— 边界声明会被悄悄丢掉而不是误加"
    evidence_status: "本次未能独立复现锁态（沙箱内 ioreg 不返回该键）；按指示不重跑探针，采信 evidence/refresh.log 的 REFRESH_SESSION=locked"
---

human_verification:
  - test: "解锁会话后跑 bash .planning/spike/run-gate.sh"
    expected: "ORDER=ok 且 FINDER_RESTART_ALIVE=1 在有前台进程的会话下仍成立；不成立则 Phase 1 的 GATE=A 降级为「仅锁屏会话下成立」"
    why_human: "屏幕锁着，门禁入口本身拒绝执行（gate-rerun.log: GATE_RERUN=blocked）。约 1 分钟，脚本无需改"
  - test: "解锁会话后跑 bash scripts/run-probe.sh refresh"
    expected: "区分「.app 形态也拿不到显示刷新回调」与「锁屏会话压制了显示回调」—— 这两种情况现在给不出不同答案"
    why_human: "REFRESH_SESSION=locked，本次测量原理上无法区分两个假设。约 35 秒，脚本无需改"
  - test: "肉眼确认：桌面图标后面确实有画面在动；菜单栏常驻图标在位；点选与拖动桌面图标不受影响"
    expected: "三条同时成立"
    why_human: "screencapture 无屏幕录制权限 + 会话锁定 + 需真人手点，三重挡住。Phase 1 的做法是推门禁不强求人工，此处同理但要真做"
  - test: "真人点一次菜单栏图标的「暂停 / 继续」，看是否从原处续播；再点一次「退出」，看进程是否消失"
    expected: "暂停后画面停住、继续后从暂停处恢复（非从头）；退出后进程真的没了"
    why_human: "无 .xcodeproj 故无 XCUITest（D-01 的代价），无辅助功能权限。自动侧两段已证：菜单 .quit 接的就是 terminateApp()，且 NSApp.terminate 路径跑完 applicationWillTerminate 且进程消失。缺的正是「真人点击 → 同一条路径」这一跳"
  - test: "Mission Control 手动切一次 Space"
    expected: "壁纸不消失、不报错"
    why_human: "本机 SCREENS_COUNT=1 且会话锁定，结构上无法复现。collectionBehavior 四项在位且零 Space 订阅，只能说明按系统默认走"
---

deferred_notes: []

---

# Phase 02 独立复核报告

**Phase Goal:** 用户看到一个真正的菜单栏 app —— 桌面图标后面有视频在无缝循环播放，菜单栏能暂停/继续和退出，没有 Dock 图标；`SettingsStore` / `HoldArbiter` / `PlayerController` 三个接口在此定死。
**复核性质:** 独立复核，不是重跑。Phase 2 已执行完毕，本次只做只读核对。
**Verdict:** 目标结构上达成，三接口真的定死，4 项 BLOCKED 没有一项被粉饰成实测通过。但 **VERDICT 与产物之间有 6 处对不上**，按本项目自订标准（每行挂一个真实证据路径与一个数字）这属于必须修的缺口。

---

## 一、Goal 逐条对产物核

| # | Goal 分句 | 结论 | 产物证据 |
|---|---|---|---|
| G1 | 桌面图标后面有视频在无缝循环播放 | **结构达成，肉眼未证** | `order.log:SELF_LEVEL=-2147483623` < `ICON_LEVEL=-2147483603`（差 20 级）、`ORDER=ok`、`OWNED_WINDOW_COUNT=1`；`loop.log:LOOP_VERDICT=pass / SAMPLES=150 / ENDED=37 == CYCLES=37 / STALLED=0 / FAILED=0 / DURATION=300`（150 个采样点全部 `status=playing items>=1`）。没有任何一帧像素被看到过 —— `BLACKFRAME=blocked reason=no_screen_recording_permission` |
| G2 | 菜单栏能暂停/继续 | **自动部分达成** | `swift test` 实测 `Executed 24 tests, with 0 failures`；`HoldArbiterTests.testResumeSeeksToAnchorThenClearsAnchor` / `testManualPauseResumesFromAnchorNotFromZero` / `testAnchorNotOverwrittenBySecondHold` 钉死续播锚点；`PIC_HOLD active=1 reason=manualPause holds=(manualPause)` 运行期可观测。真人点击未测 |
| G3 | 菜单栏能退出、真结束进程 | **自动部分达成** | `quit.log:QUIT_HOOK_SEEN=1 / QUIT_EXITED=1 / QUIT_WALL_SECONDS=4`；`grep -rn 'NSApp.terminate' Sources/` 实测恰好 1 处（`AppDelegate.swift:144`），test.sh 每次自动重验 |
| G4 | 没有 Dock 图标 | **达成（两条独立证据）** | 运行期 `app-bundle.log:APP_ACTIVATION_POLICY=1`（`.accessory`，0 才是 `.regular`）；打包期 `LSUIElement=true`（`plutil -extract raw` 读出字面量 `true`） |
| G5 | 三个接口定死 | **达成** | 见下第二节 |

---

## 二、三个接口真的「定死」了吗

逐个读真实签名，不是读 SUMMARY 的转述。

### `SettingsStore`（`Sources/PicCore/State/SettingsStore.swift`，103 行）
- 公开面：`Seed`（6 字段，全有默认值）、`Key`（6 个字面量常量）、`envSourceFolderKey`、6 个可变属性、`init(defaults:seed:)`、`resolvedFolderURL() -> URL?`、`fileExists(at:) -> Bool`、`persist()`。
- **不是空壳**：三级优先（env > UserDefaults > seed）真实现了；`persist()` 六个键全写；`fileExists` 走 `url.path`（Pitfall 5 正确）。
- 增长归属已登记：`PlayMode` 只 1 个 case，`Seed` 第 4 行注释写明「Phase 4 只新增 case，不动 `SettingsStore` 的签名」；02-01-SUMMARY 的「接口定死的确切边界」表把 PlayMode 归属写为 Phase 4。

### `HoldArbiter`（`HoldArbiter.swift` 65 行 + `HoldReason.swift` 19 + `PlaybackDecision.swift` 14 + `PlaybackTarget` 协议 11 行）
- 公开面：`decision`、`isManuallyPaused`（派生量，**不是**独立真相源）、`init(target:)`、`attach(_:)`、`set(_:active:)`。
- 四个不变式全部落地且有单测：veto 集合（D-11）、幂等（不变式 4）、锚点只在 ∅→非∅ 写入（D-15）、解除时 seek 回锚点后清空。
- 幂集测试是**运行时** `1 << all.count` 生成的 —— Phase 3 加 case 后自动扩，测试代码一个字不改。这是本 Phase 做得最扎实的一处。
- 增长归属已登记：`HoldReason` 源码注释逐个点名 Phase 3 的 5 个 case；02-01-SUMMARY + ROADMAP 同步。

### `PlayerController`（`PlayerController.swift`，82 行）
- 公开面：`player`、`attach(to:)`、`load(url:)`、`setRate/setVolume/setMuted`、三个 `PlaybackTarget` 方法。
- D-12/D-13/D-14 全部照抄 Phase 1 已跑通的形状：`AVQueuePlayer` + `AVPlayerLooper`、`audioTimePitchAlgorithm=.spectral` 显式设、`preferredForwardBufferDuration=3.0` 挂在 item 上、`disableLooping()→removeAllItems()→入队` 顺序正确（行 42/43/44）、`rate/volume` 挂 player 不挂 item。
- **一处已知缺口**（不推翻「定死」，属新增）：ROADMAP Phase 4 的 Notes 已经指名 `PlayerController.stop()`，产品里没有。`orderOut(nil)` 那一半（`WallpaperWindowController.teardown`）已在。

### 判定
**三个接口确实定死了，且没有「以后再定」的空壳** —— 每个方法都有真实实现，不是 stub。枚举成员按阶段增长有明确归属登记（`HoldReason`→Phase 3，`PlayMode`→Phase 4），登记出现在源码注释、SUMMARY、ROADMAP 三处。
唯一非「以后再定」的空壳是 `WallpaperWindowController.reassert()` —— 5 行 public 方法，**全树无调用者**，存在的理由是给 Phase 4 的 `activeSpaceDidChangeNotification` 预留。文件自己的注释写明了「没有任何代码自动调用它」。Phase 4 一旦加上那个订阅，test.sh 的 SYS-02 判据会按设计变红（ROADMAP Phase 4 Notes 已预告）。

---

## 三、VERDICT 有没有夸大

### 4 项 BLOCKED：没有一项被说成实测通过 —— 逐项核对通过

| 已知 BLOCKED | VERDICT 的呈现 | 判定 |
|---|---|---|
| SC2 无黑帧 | SC2 行「缺口：『无黑帧』未验证」+ 没跑过①栏 + W-2026-10-03-01 | ✅ 如实 |
| SC5 切 Space 不消失 | SC5 行「缺口：『切换 Space 后壁纸不消失』未验证」+ 没跑过②栏 + W-02 | ✅ 如实 |
| SC1 点选/拖动桌面图标 | SC1 行「缺口：『点击和拖动桌面图标不受影响』未验证」+ 没跑过③栏 | ✅ 如实 |
| SC3 真人点菜单退出 | SC3 行「缺口：『真人点击菜单项』这一跳未验证」+ 没跑过④栏 + W-07 | ✅ 如实 |

`GATE_RERUN=blocked`、`REFRESH_SESSION=locked`、DMG 不可复现也都在正文如实呈现，没有被降级成脚注。

### 但 VERDICT 与产物有 6 处对不上

| # | 位置 | VERDICT 写的 | 产物实际 | 性质 |
|---|---|---|---|---|
| 1 | 第 123 行（W-05 行）+ 第 46 行（跑过表） | `app-bundle.log:FOREIGN_SAME_LEVEL=0`、`FOREIGN_DESKTOP_FAMILY=7`，并称「在打包产物上再测一次，**仍是 0**」 | 第 12-14 行：`FOREIGN_SAME_LEVEL=1`、`FOREIGN_OWNERS=Pic`、`FOREIGN_DESKTOP_FAMILY=8` | **实质不一致**：打包产物上的读数与 swift run 那场不同，VERDICT 把它抹平成「仍是 0」 |
| 2 | 第 93-94 行（刷新回调表） | 两轮都 `TICK_RATE=27.2`、`272 tick / 10.0s`，并逐字引用 `REFRESH_RUN_MODE=swift_run DRIVER=timer_fallback_hz30 TICK_RATE=27.2` 与 app_bundle 同款 | `refresh.log:1` = `TICK_RATE=27.1`（271），`:3` = `TICK_RATE=27.0`（270）。这两行**在 refresh.log 里根本不存在**；27.2/272 出自 `loop.log:REFRESH_TICK_RATE` / `REFRESH_TICK_COUNT`，是 loop 那一场的数字 | **引用了不存在的日志行 + 跨场次取数**。DRIVER 结论（两种形态都是 `timer_fallback_hz30`）不受影响 |
| 3 | 第 48 行（跑过表） | DMG `141K` | `dist/Pic-0.1.0.dmg` = 149464 bytes；02-PDCA 写 149 KB；test.sh 本次实跑也读到 149464 | 陈旧数字 |
| 4 | 第 24 行（SC2 行） | 缺口只列「无黑帧」；`INSET_LEFT=14 TOP=9 RIGHT=14 BOTTOM=9`、`SCREEN_FRAME=0,0,1470,956` 列在**通过侧** | `inset.log:7` `WINDOW_FRAME=14,9,1442,938` —— 窗口比屏每边小 14/9pt，而这扇窗 `isOpaque=true` + `backgroundColor=.black`。「铺满 / 无黑边 / 无变形」同样没有观测证据，被引用的内缩数字反而指向「没铺满」 | **缺口清单不全**（方向是少报不是多报，但 SC2 行的通过侧引用了一个反向指标） |
| 5 | 第 114 行 vs 第 127 行 | 小节写「10 条窗口全部仍在 `open`，本 Phase 一条都没有关闭」 | 表里 W-2026-10-03-09 标 `resolved（本 Phase 重验通过）`；WINDOWS.md 的 `## resolved` 段写「（暂无）」 | 自相矛盾 + 账目不一致 |
| 6 | 第 114 行 | 「WINDOWS.md 里 Phase 2 的 10 条窗口」 | 实际 13 条（W-11/12/13 由 02-04 新增，见于正文但不在该表） | 表不全 |

### SC2 / SC5 的 PARTIAL 标签是否名副其实

**都名副其实，且是保守方向。**
- SC2 = PARTIAL：循环部分真过（`LOOP_VERDICT=pass`，判据是 `endedCount == cycles && failedCount == 0 && samples>=140 && 每次 status==playing && items>=1`，四条独立取数）。「无黑帧」原理上不可测（`screencapture` 权限）。PARTIAL 正确，只是缺口少列了一条（见上表 #4）。
- SC5 = PARTIAL：自动那半真过（剥注释后 `Sources/` 内 `activeSpaceDidChangeNotification` = 0，本次实跑 test.sh 确认；`collectionBehavior` 四项在位）。人工那半被 BLOCKED。PARTIAL 正确。

### 放大系数评级

SC2 的 PASS 侧（循环）与 SC5 的 PASS 侧（零特殊处理）没有粉饰。
SC1 的 `PASS-with-gap` **没有夸大标签，但缺口枚举不全**：SC1 原句含「菜单栏出现常驻图标」与「桌面图标后面有**一段视频在播放**」，这两跳没有任何观测证据（菜单栏图标只有源码 `MenuBarExtra` + 激活策略两条，没有「图标出现过」的读数），但都没进缺口栏。SC3 的 `PASS-with-gap` 缺口枚举是完整的。

---

## 四、PDCA 的 C1 是否被如实呈现 —— 是

| 检查项 | 结果 |
|---|---|
| VERDICT 文件头是否写明「产品未在解锁会话验证过」且无限定语 | ✅ 第 8-10 行逐字：「**产品未在解锁会话验证过。** —— 这行不加任何限定语。」 |
| 是否点出首行 `GATE_RERUN=blocked` | ✅ 并附 `REASON=session_locked CGSSessionScreenIsLocked=1 loginwindow_pid=489` |
| 是否声明「本文件里所有实测读数都产生于锁屏会话」 | ✅ 第 10 行 |
| `refresh.log` 的 `REFRESH_SESSION=locked` 边界有没有被写足 | ✅ 「一条必须写明的发现」一节明确写「无法区分『.app 也拿不到』与『锁屏会话压制了』」，并说「它不是『打包成 .app 就该有』，也不是『.app 也没用』，而是『这一条在锁屏会话下测不出来』」—— 这是本 Phase 写得最克制的一段 |
| 假定依赖栏有没有把门禁边界限定住 | ✅ 「假定它**只在锁屏会话下成立**。Phase 2 没有拿到任何解锁态的层级读数」 |
| PDCA C1 与 VERDICT 是否一致 | ✅ 一致。PDCA C1 额外点出「这是正确的做法，但缺口本身没变」，没有把它降级成形式主义 |

**本次独立核对**：`.planning/spike/out/gate-01.log` 实测 `md5 = af32978a623e67d8afe9842368a47b8d`，与 `evidence/gate-01-locked-session.md5` 记录一致 → Phase 1 门禁日志全程未被改写 ✓。`pgrep -x loginwindow` = **489**，与 `gate-rerun.log` / `lock-state.txt` 记录的 pid 一致。本 agent 沙箱内 `ioreg -n Root -d1 -a` 不返回 `CGSSessionScreenIsLocked` 键，**无法独立复现当前锁态**；按指示不重跑探针，采信落盘的 `REFRESH_SESSION=locked`。（另记：run-probe.sh:454-459 的锁态判定在键缺失时 fail-open 判成 `unlocked`，方向偏乐观。）

---

## 五、`test.sh` 的 32 项：真绿、无副作用、A6 脆弱点仍在

### 32 项实跑复核 —— 通过
```
bash test.sh  →  通过 32  失败 0  跳过 0   （本次实跑，退出码 0）
swift test    →  Executed 24 tests, with 0 failures  （9 仲裁 + 7 菜单 + 8 设置）
swift build -c release → Build complete!
```
32 的构成可逐项对上：3 工具链 + 1 spike 编译 + 5 API 探针 + 3 运行时值 + 2 spike 门禁 + 12 产品代码 + 1 渲染 + 5 打包产物 = 32。VERDICT 说的「把 `build/` 移走 → 通过 27 / 跳过 5」在算术上自洽（32−5=27），未复跑（会破坏产物）。

### 副作用 —— 无
`bash test.sh` 只做：`xcode-select -p` / `command -v`（读）、`swiftc -typecheck`（临时目录）、`swift build` / `swift test`（写 `.build/`）、渲染探针输出 PNG 到 `$TMP`、`plutil` / `codesign -dv`（读）、`stat` / `ls`（读）。**不起 GUI 进程、不 kill Finder、不碰系统偏好**。单测的 `UserDefaults` 用 `UserDefaults(suiteName: "pic.tests.<UUID>")` 且 `tearDown` 调 `removePersistentDomain`；`PIC_SOURCE_FOLDER` 的 `setenv` 在 `setUp`/`tearDown` 双向 `unsetenv` —— 我逐行核对过，**不污染真实域 `com.local.pic`，也不污染同进程后续用例**。

### A6（停止用源码字面量 grep 做判据）—— 脆弱点仍在，本 Phase 未落实
本次实测复现 4 个脆弱点，**没有一个被 Phase 2 修掉**：

| # | 脆弱点 | 复现方式 | 结果 |
|---|---|---|---|
| F1 | `src_count` 的过滤器只剥**行首**注释（`-e '^[[:space:]]*//'` 等四条），行尾注释不剥 | 在 `HoldReason.swift` 某行代码后加 `// ... activeSpaceDidChangeNotification` | 剥注释后计数 = **1** → 判红。纯注释触发 |
| F2 | `src_count` 数的是**行数**不是**出现次数** | 把两处 `NSApp.terminate` 写在同一行 | 行计数 = **1** → 「结束进程的全局调用全仓唯一落点」判**绿**。判据可被绕过 |
| F3 | 菜单 `Button(` / `ForEach` 那条**完全不过滤注释** | 把 `MenuContentView.swift:9` 注释里的 `Button` 改成 `Button(` | Button( 行数 **2** vs ForEach 行数 **1** → 判红。第 9 行现在离这条判据只有一对括号 |
| F4 | MENUBAR-08 的 `sed -n '/struct MenuContentView/,/^}/p'` 区间无自检 | 把 `struct MenuContentView` 改名 | 区间取空 → `PN=0` → 判**绿**。判据注释自称「刻意不把范围缩到扫不到东西的形式」，但没有对「区间取空」本身断言 |

**这不构成 Goal 失败**（32 项确实全绿、判据确实在检查它声称在检查的东西）。但 A6 在 ROADMAP 里写的是「Phase 3 起：判据只扫不含注释的代码，或改用行为断言」—— **Phase 2 自己没先做**，而 F1/F3 正是 Phase 1 五次、Phase 2 三次自伤的同一个形状。**建议 Phase 3 的第一条判据改造就是把这 4 个点修掉**，否则第 9 次自伤只是时间问题。

---

## 六、最小代码方针 / 抽象 / 依赖 / 仓库卫生

| 检查 | 结论 |
|---|---|
| 零第三方依赖 | ✅ **真的零**。`Package.swift` 的 `dependencies: []`；`Sources/` 全树 import 只有 `Foundation` / `AppKit` / `AVFoundation` / `CoreGraphics` / `QuartzCore` / `Observation` / `SwiftUI`，全是系统框架 |
| 有无不必要抽象 / 协议 / 泛型 | 基本没有。唯一的协议 `PlaybackTarget`（3 方法）有正当理由（`HoldArbiter` 不能 import AVFoundation，单测要假播放端）。无泛型。`SettingsStore.Seed` 用默认参数代替了另一个 init，是合理的 |
| 1279 行 / 14 文件做 5 SC + 8 需求 | **偏重**。其中测量脚手架 493 行（38.5%）：`LoopProbe` 206 + `WindowProbe` 167 + `FrameDriver` 120。`LoopProbe` 会**打进交付的 `.app` 二进制**（`PicCore` 是 `PicApp` 的依赖）。Phase 1 的先例是把一次性探针放 `.planning/spike/` 不进产品库 —— 这里破了先例，而 CONTEXT 的「最少代码」约束没有为它点名例外。VERDICT 为 `FrameDriver` 写了「纯测量器、不接渲染路径」的论证（本次核对：`FrameDriver.swift` 剥注释后 `AVPlayerLayer` = 0 ✓，全树引用仅自身声明 + AppDelegate 持有 ✓），但**没有对 `LoopProbe` / `WindowProbe` 做同样的交代** |
| 铁律 3（区分跑过 / 没跑过 / 应该能跑但未测 / 假定依赖） | ✅ 四份 SUMMARY 全部有这四栏（`诚实基线` 段），VERDICT 有完整四栏表，`WINDOWS.md` 的录入口径也是这四类 |
| 铁律 4（形容词充当证据） | ⚠️ 大体守住（PDCA C5 记录了 1 次自己踩自己的反形容词门并已修）。本次未发现新的形容词充当证据。**但上面第三节的 6 处不一致正是「证据漂移」这一类 —— 与形容词无关，是引用与产物对不上** |
| 构建产物是否进仓库 | ✅ **没有**。`.gitignore` 覆盖 `build/` `dist/` `.build/` `fixtures/`；`git ls-files` 里零个 `build/` `dist/` `.app` `.dmg` `.o` 二进制 |

---

## 七、安全面（本 Phase 真实风险，不凑数）

| 面 | 结论 |
|---|---|
| `--quit-after` 不得成为产品能力 | ✅ **未扩大**。`grep -rn 'CommandLine.arguments' Sources/` = 2 处：`AppDelegate.swift:87`（`--quit-after`）与 `WindowProbe.swift:150`（**在 `#if PIC_WINDOW_PROBE_MAIN` 内，产品构建被条件编译剥掉** —— 已核对第 144/167 行）。产品构建里它确实是唯一的启动参数钩子，与 W-2026-10-03-08 的登记一致。不传参时 `scheduleQuitAfterIfRequested()` 第一个 guard 就 return，菜单里也不出现该开关 |
| 窗口标题泄露文件名 | ✅ `Sources/` 内 `kCGWindowName` = 0（test.sh 每次自动重验）。`Window("Pic 设置", id: "settings")` 无文件名；`MenuBarExtra("Pic", ...)` 无文件名；`emit()` 全部走 stderr 且不含路径（`PIC_HOLD ... resumeAt=%.3f` 只有秒数）。`SettingsSkeletonView` 显示源目录路径 —— 但那是用户主动打开的设置窗，菜单栏那一侧永远不出现，MENUBAR-08 允许 |
| MENUBAR-08 是否有牙齿 | ✅ 哨兵法是真的：`testLabelsNeverContainAnyMediaFileName` 断言标签串里 `.mp4` 出现 0 次、哨兵文件名 0 次、源目录全路径 0 次、目录名 0 次，且跑「暂停 / 播放 / 已设置路径」三种状态。再用 `Button(` == `ForEach(MenuItemID.allCases` 那条判据堵住「手写 Button 绕过模型」的口子。组合是成立的 |
| 不签名 / 不公证 | ✅ ad-hoc（`Signature=adhoc`、`Authority=Developer ID` 无匹配）、`Info.plist` 零 `UsageDescription`、已登记为已知且接受 |
| 本地文件访问（用户视频目录） | ⚠️ 产品只 `contentsOfDirectory` + `fileExists`，不写不删。真正的面是 `PIC_SOURCE_FOLDER` 环境变量：任何能拉起 Pic 的进程都能把壁纸目录指到任意路径，产品随即枚举它。风险低，但 security_enforcement=true 的 Phase 里它没出现在任何 threat 段 |

---

## 八、判定与理由

**`status: gaps_found`**

不是因为 Goal 没达成 —— Goal 结构上达成了，三接口真的定死，4 项 BLOCKED 无一粉饰，C1 如实呈现，32 项真绿且无副作用。

是因为 **VERDICT 与产物之间有 6 处对不上**，其中 2 处是实质性的：

1. **打包产物探针那行把 `order.log` 的数字挂到了 `app-bundle.log` 上**，并写成「在打包产物上再测一次，**仍是 0**」。该文件实际是 `FOREIGN_SAME_LEVEL=1` / `FOREIGN_OWNERS=Pic` / `FOREIGN_DESKTOP_FAMILY=8`。而 W-2026-10-03-05 恰好就是「本机常驻同层壁纸 app」这条窗口 —— 打包产物上的读数与 swift run 那场**不同**，这个变化被抹平了。（`=1` 的成因可能是另一个残留 Pic 进程，也可能是探针 artifact；两者都需要写清楚，但都不是 0。）

2. **刷新回调一节逐字引用了两行 `refresh.log` 里不存在的日志行**，并把 `loop.log` 那一场的 `27.2 / 272` 当作 `refresh.log` 两轮共用的数字（实际 27.1/271 与 27.0/270）。同处数字在 `WINDOWS.md:W-2026-10-03-11` 也传抄了一份。DRIVER 结论本身没错，错的是引用与取数。

按本项目自订标准（VERDICT 自己写的「每行都挂一个真实证据路径与一个数字」）与全局铁律 4，这两处必须修 —— 它们属于「自己的证据引用和自己的产物对不上」，与已经登记在案的 8 次自伤同一个类别，而 Phase 2 的判定文件本身又新增了 2 例。

其余 4 处（DMG 141K、SC2 缺口少列一条、W-09 resolved 与「一条都没关闭」自相矛盾、W-11/12/13 不在该表）是陈旧数字与记账不一致，同批修掉即可。

**修完这 6 处之后**，本 Phase 的诚实度就与它的实际质量匹配：目标达成、4 项 BLOCKED 如实、C1 如实、接口定死。此时状态应转为 `human_needed` —— 文件里有 5 项待真人条目（解锁门禁、解锁刷新复测、肉眼三条、真人点菜单两次、切 Space），`passed` 的语义（无需任何人工介入）与内容矛盾。

**给 Phase 3 的三条硬要求**（前两条 Phase 2 已经欠着）：
1. 先修 test.sh 的 F1-F4 四个脆弱点（剥行尾注释 / 数出现次数而非行数 / 菜单判据也过滤注释 / sed 区间加自检），否则 A6 只是写在 ROADMAP 里的一句话。
2. `PlayerController` 需要补一个 `stop()`（Phase 4 的 Notes 已经指名）。
3. `WallpaperWindowController.reassert()` 目前零调用者；Phase 4 一旦接上 `activeSpaceDidChangeNotification`，test.sh 的 SYS-02 判据会按设计变红 —— 届时要么改判据要么改产品，**不要为了让判据变绿而把 Phase 4 的 re-assert 订阅删掉**。

---

_Verified: 2026-10-03 · 独立复核（只读核对，未重跑任何 GUI 探针）_
_Verifier: Claude (gsd-verifier)_