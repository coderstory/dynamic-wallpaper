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

### W-2026-10-03-07 · unrun-verify · Phase 2 / Plan 02-03

- **描述**：「**点菜单栏图标退出**」这一半未被自动验证 —— 需要真人点击。
- **证据**：本机无 `.xcodeproj` 故无 XCUITest（D-01），会话锁定、屏幕录制无权限。
  已自动证明的只有两段：① 菜单 `.quit` 的动作就是 `terminateApp()`（`test.sh` 判据
  「菜单结构体内零 AVPlayer 直连」+ `MenuBarModelTests.testPerformQuitCallsInjectedClosureOnlyOnce`）
  ② `NSApp.terminate` 那条路径会跑完 `applicationWillTerminate` 并让进程真正消失
  （`evidence/quit.log` 的 `QUIT_HOOK_SEEN=1` / `QUIT_EXITED=1`）。
  **未证明**的是「真人点击菜单项 → 同一条路径」这一跳。
- **解开条件**：Phase 5 引入 `.xcodeproj` 后写一个 XCUITest 点击菜单项；
  或在解锁会话由真人手动点一次并对照 `PIC_TERMINATED pid=` 行。
- **status**：open

### W-2026-10-03-08 · unrun-verify · Phase 2 / Plan 02-03

- **描述**：`--quit-after <秒>` 是**测试脚手架**，不是产品能力，但它是一行留在产品源码里的启动参数。
- **证据**：`Sources/PicApp/AppDelegate.swift` 的 `scheduleQuitAfterIfRequested()`；
  它在 `evidence/quit.log` 里以 `QUIT_TRIGGER=--quit-after 3 启动参数（测试脚手架，不是产品能力）` 显式登记。
- **风险**：后续读者可能把它误当成面向用户的启动参数。它不传参时一行都不跑，菜单里也不出现。
- **解开条件**：XCUITest 可用后（见 W-2026-10-03-07）即可删除该函数与探针的 `--quit-after` 那一轮。
- **status**：open

### W-2026-10-03-09 · deviation · Phase 2 / Plan 02-03

- **描述**：T1 的 AC「全仓 `NSApp.terminate(nil)` 字面量恰好 1 处」在开工时**不成立** —— 02-02 遗留了第二处。
- **证据**：02-02 的 `Sources/PicCore/Playback/LoopProbe.swift` 观察跑完后自己调了一次结束进程，
  与 `AppDelegate.terminateApp()` 并列。开工时 `grep -rn 'NSApp.terminate' Sources/` 得 **2** 处。
- **纠正**：**改源码不放宽判据**。`LoopProbe` 改为构造时注入 `terminate` 闭包，
  由 `AppDelegate` 把自己的 `terminateApp()` 注进去。实测收敛为 **1** 处
  （`test.sh` 的「结束进程的全局调用全仓唯一落点」每次自动重验）。
- **status**：resolved（判据已成立；留档防止 Phase 3/4 在别处再写一遍）

### W-2026-10-03-10 · todo · Phase 2 / Plan 02-03

- **描述**：`AppDelegate.startWallpaper()` 起播时有一处 `player.player.play()` 直连播放器。
- **证据**：`Sources/PicApp/AppDelegate.swift` 起播序列 `load` → `play` → `setRate/Volume/Muted`。
  它**不是菜单动作**，且发生在任何 watcher 存在之前，所以不归 T-02-08 那条判据管
  （`test.sh` 的「菜单侧零 AVPlayer 直连」的范围因此是 `MenuContentView.swift` 单文件）。
- **风险**：Phase 3 接入锁屏 / 全屏等 watcher 后，如果「起播」与「watcher 首次置位」的时序反了，
  可能在已 hold 的情况下先 `play()` 一下才被压住。
- **解开条件**：Phase 3 接 watcher 时复核这条起播路径，必要时改为经仲裁器起播。
- **status**：open

---

### W-2026-10-03-11 · unrun-verify · Phase 2 / Plan 02-04

- **描述**：PDCA-A4 —— 打包成 `.app` 之后，本进程**仍然**拿不到显示刷新回调。
- **证据**：`evidence/refresh.log`。`swift_run` 与 `app_bundle` 两轮的 `DRIVER` **都是**
  `timer_fallback_hz30`。`swift_run`：`TICK_RATE=27.1`（`tick_count=271` / `window=10.0`）；
  `app_bundle`：`TICK_RATE=27.0`（`tick_count=270` / `window=10.0`）；两轮 `wait_seconds=16`。
  （`27.2` / `272` 是 `loop.log` 的值，2026-10-03 校验时发现此处曾误抄，已更正。）
  `REFRESH_VERDICT=blocked`、`REFRESH_BLOCKED_REASON=no_display_link_in_any_mode`。
- **保留的边界**：`REFRESH_SESSION=locked`。本次测量**无法区分**「`.app` 也拿不到」与
  「锁屏会话压制了显示回调」—— 两者在解锁会话下会给出不同答案，而解锁后本机读不到答案。
  不把它写成「打包成 `.app` 就该有」，也不写成「`.app` 也没用」。
- **影响**：Phase 1 的硬约束第 3 条（「本 Phase 的降级证据不等于产品行为」）**没有**被解除。
  Phase 3 的锁屏 / 熄屏 / 睡眠 / 电源四类检测必须走事件通知，不得逐帧轮询。
- **解开条件**：解锁会话后重跑 `bash scripts/run-probe.sh refresh`（约 35 秒，脚本无需修改）。
- **status**：open

### W-2026-10-03-12 · deviation · Phase 2 / Plan 02-04

- **描述**：`build.sh` 重复执行产出的 DMG **不是**逐字节可复现的（计划预留了这条口径，要求如实记录）。
- **证据**：`evidence/app-bundle.log`。四次独立 `build.sh` 的 DMG md5 全部不同
  （`9b4c7e31…` / `1e685a43…` / `166e336a…` / `e391cb5f…`）。已排除「我们的输入不是确定性产物」：
  两个 DMG 内的 `Pic.app` 逐字节相同（MacOS 二进制 md5 `662e632168d66ff79f7892e932b695fa`、
  Info.plist md5 `f85a5701cdcd2be959c437c92976393d`），差异在 UDIF 容器层。
- **进一步排除**：把源树 mtime 全部 pin 成同一时刻后，相隔 2 秒的两次 `hdiutil create`
  仍产出不同 md5（`9e20b8a9…` vs `936dab1c…`），故 mtime 不是唯一变量。**未定位到容器内具体哪几个字节在变。**
- **影响**：ROADMAP Phase 7 SC1 若要求「重复执行结果一致」，判据必须落在 **`.app` 内容的 md5** 上，
  不能落在 DMG 容器的 md5 上。
- **status**：open（交给 Phase 7 定口径）

### W-2026-10-03-13 · deviation · Phase 2 / Plan 02-04（已修）

- **描述**：`test.sh` 在 UTF-8 locale 下运行时会**按字节偏移丢掉 2 字节**，
  且丢点与脚本内容无关 —— 同一份脚本在 C locale 下输出逐字节有效。
- **证据**：最小复现（33 行中文填充 + 一行含 `…行数 $MF）` 的 `ok`）在 UTF-8 locale 下把
  `1）`（`31 EF BC 89`）变成 `¼`（丢掉 `31 EF`），同一脚本在 `LC_ALL=C` 下不丢。
  `evidence/app-bundle.log` 同批的 `test.sh` 输出在 UTF-8 locale 下于 offset 1681 出现同一损坏。
- **后果**：`bash test.sh` 的输出里只要有一个非法字节，`grep` 就会中止整份文件 ——
  「test.sh 的输出能不能被 grep」不可靠，判据会假红。这条曾让 02-04 的
  「干净环境输出含 `跳过`」判据无法通过。
- **纠正**：`test.sh` 内 `export LC_ALL=C`，只固定脚本自身的字节处理，
  **不改变任何一条判据的语义**。修后实测：默认 UTF-8 环境跑 `bash test.sh` → `通过 32  失败 0  跳过 0`，
  输出逐字节有效，`grep -c '跳过'` 命中。
- **status**：resolved（Phase 3/4 若新增中文输出脚本，同样需要这一行）

## resolved

- **W-2026-10-03-09** · `NSApp.terminate` 第二处 —— 本 Phase 已收敛为 1 处并挂进 `test.sh` 每次重验
- **W-2026-10-03-13** · `test.sh` UTF-8 locale 下按字节偏移丢 2 字节 —— 已用 `export LC_ALL=C` 修复，未改判据语义