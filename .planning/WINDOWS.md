# WINDOWS —— 跨阶段缺陷登记簿

> 每条缺陷在此留档，直到有人真的修掉并把 `status` 改成 `resolved`。
> `/gsd-ship` 在存在任何 `open` 条目时不允许收口。
>
> 录入口径：**没跑过的验证**、**跳过的测试**、**留下的桩**、**与计划的偏离**。
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

### W-2026-10-03-14 · deviation · Phase 3 / Plan 03-01

- **描述**：`HoldReason` 新增 5 个 case 的 `order` 取值，与 Phase 2 文件头注释的预告不符。
- **证据**：`Sources/PicCore/State/HoldReason.swift` 的 Phase 2 注释写「Phase 3 在此新增：
  fullscreen(0) / screenLocked(1) / displayAsleep(2) / systemSleeping(3) / battery(4)」，
  而 `manualPause` 已占着 0（`HoldArbiterTests` 的幂集用例在 Phase 2 实测通过，
  `testActiveReasonsSorted` 断言 `activeReasons` 按 `order` 排好序）。
- **影响**：两个 case 共用同一个 `order` 时，`PlaybackDecision.activeReasons`
  （即 `holds.sorted()`）在这两者之间**顺序不确定** —— `Set` 的迭代顺序不由 `order` 决定，
  D-10 允许的「优先级只用于 UI 文案排序」就失效了。
- **纠正**：`order` 取值改为 `manualPause=0`（Phase 2 的值，一个字未改）、其余依次 1…5。
  实测 `HoldReason.allCases.map(\.order) == [0,1,2,3,4,5]`（单测断言），
  幂集恰 64 组（`1 << allCases.count == 64`）。**只做纯追加**：加 5 个 `case` 与 5 个 `order` 分支，
  未重命名、未重签名、未删除任何已有声明。
- **status**：resolved（值已定死并挂进单测每次重验）

### W-2026-10-03-15 · unrun-verify · Phase 3 / Plan 03-01

- **描述**：`PIC_LOCK_SIGNAL_PREFIX` 环境变量把 `LockSignalNames` 指向测试通知名，
  它是**测试脚手架，不是产品能力** —— 但它是一行留在产品源码里的开关。
- **证据**：`Sources/PicApp/AppDelegate.swift` 的 `lockSignalNames()`；
  `evidence/lock-wiring.log:LOCK_SIGNAL_REGISTERED` 记 `locked=com.local.pic.tests.lock.locked`，
  全文 `com.apple.screenIsLocked` 计数 = 0（合成事件一次都没碰系统通知名）。
- **风险**：后续读者可能把它误当成面向用户的启动参数。它不设时与系统名完全一致，
  菜单与设置里都不出现（T-03-04 已按 `W-2026-10-03-08` 的先例登记）。
- **解开条件**：Phase 5 引入 `.xcodeproj` 后把探针改成 XCUITest 的 launch argument，
  或四个 Watcher 都有稳定注入点后删掉该变量。
- **status**：open

### W-2026-10-03-16 · unrun-verify · Phase 3 / Plan 03-01

- **描述**：**真实锁屏跃迁在本会话无法观测** —— 合成通知只证明接线，不冒充系统跃迁。
- **证据**：`evidence/lock-wiring.log:LOCK_TRANSITION=unobservable reason=session_locked CGSSessionScreenIsLocked=1`；
  `LOCK_SESSION_AT_START=1 real_CGSSessionScreenIsLocked=1 session_keys=14`。
  本机会话自 `applicationDidFinishLaunching` 起一直锁着，driver 跑的 6 秒里没有跃迁可等。
- **保留的边界**：`LockWatcher.start()` 的**同步**回调已实测生效
  （`LOCK_START_SYNC_DELIVERED=1 locked=1`，且不投递任何通知就发生），
  但这只证明「订阅后立刻能用真实会话状态置位」，**不证明**跃迁时
  `com.apple.screenIsLocked` 真的会投递 —— 后者沿用 Phase 1 的结论（PDCA-A7）。
  本次合成的两次投递走的是**注入的通知中心 + 注入的通知名**，
  连「系统通知中心能否收到」这一层都没碰到。
- **影响**：PAUSE-02 / PAUSE-06 的**接线**已证明；「真实跃迁触发暂停」**未**证明。
- **解开条件**：解锁后跑 `bash scripts/probe-lock.sh` 的一个变体（或 Phase 3 的活体
  `run-probe.sh holds`，见 03-05），确认真锁/真解锁各产生一次 `holds` 变化。
- **status**：open

### W-2026-10-03-17 · deviation · Phase 3 / Plan 03-02

- **描述**：SYS-02（壁纸窗口不做 Space 级差异化处理）的 `test.sh` 判据口径从
  「token `activeSpaceDidChangeNotification` 出现 0 次」改为两条排除式判据。
- **证据**：旧判据原文 `test.sh:138-139`（Phase 3 修订前）：
  `N=$(src_count 'activeSpaceDidChangeNotification')` /
  `[ "$N" = "0" ] && ok "Sources/ 零 Space 级特殊处理（SYS-02 自动判据）"`。
  现树实测：Phase 3 开工前 `src_count` 在 `Sources/` 内计数 = 0。
  D-02 拍板后 `Sources/PicCore/System/FullscreenDetector.swift` 注册了该通知 → 计数变 1 → 旧判据转红
  → `test.sh` 以 `exit "$FAIL"` 非 0 退出 → 03-05 的 `TEST_SH_RC == 0` 与 AC 全红，
  且 03-05 的插桩反向验证基线「本来就是红的」→ `TESTSH_CRITERION_IS_BLIND` 从此不可能再转绿。
- **保留的不变量**：Phase 2 锁的是**不变量**（不做 Space 级差异化处理），不是**具体正则**（token 出现 0 次）。
  代理失效了，**不变量本身一个字都没变**。
- **纠正（两条排除式判据）**：
  ① `src_count 'fullScreenAuxiliary' 'Sources/PicCore/Render' >= 1` —— 壁纸窗口仍走系统默认 `collectionBehavior`，不加 Space 相关位。
  ② `src_count 'kCGSSpace'` 与 `src_count 'CGSSetActiveSpace'` 全为 0 —— 产品代码零 Space **身份**读取。
- **为什么这两个 token 能守住原意**（已在本机 SDK 头文件核实，不是推断）：
  订阅 `NSWorkspace.activeSpaceDidChangeNotification` 只得到「Space 变了」这个**边沿**，通知本身不附带任何 Space 身份；
  真要按 Space 做差异化，只能去读会话字典的 Space 序号键（键名含 `kCGSSpace`），
  或调私有 `CGSSetActiveSpace` 去切 Space。判据 ② 盯的正是这两条路径。
- **插桩反向验证（已实跑）**：向 `FullscreenDetector.swift` 插一行含 `kCGSSpaceNumber` 的能编译代码 →
  `swift build` 仍 RC=0（插桩不能编译，否则 `test.sh` 会先红在 `swift build` 上，等于用编译失败冒充判据转红）
  → `test.sh` 汇总失败 ≥ 1 且「产品代码零 Space 身份读取」项 ❌ → 恢复后 `cmp -s` 一致、回到失败 0。
- **被推翻的一个 token**：修订时曾想用 `NSWorkspace.activeSpaceUserInfoKey` 作代理。
  本机 SDK 核实：`NSWorkspace.h` 中与 Space 相关的声明只有 `NSWorkspaceActiveSpaceDidChangeNotification`，
  **没有** `activeSpaceUserInfoKey` 这个成员（编译报 `type 'NSWorkspace' has no member 'activeSpaceUserInfoKey'`）。
  拿一个不存在的 API 当判据 token，这条判据会永远抓不到任何东西 —— 它会绿，但绿得没有意义。
  已改用 `kCGSSpace` / `CGSSetActiveSpace`。
- **status**：open

### W-2026-10-03-18 · deviation · Phase 3 / Plan 03-02

- **描述**：D-02 原文要求「几何外信号**必须能独立触发暂停**」，
  但 03-02 的实现把几何编进了信号字段名，合取的第二项因此不是承重项。
- **证据**：
  - D-02 原文（`03-CONTEXT.md`）：「几何信号可以保留作辅助，但**不得单独作为判定依据**；
    **几何外信号必须能独立触发暂停**」。
  - 编排器 2026-10-03 钦点的是**合取**：两个公开 `NSWorkspace` 通知与几何
    `verdict = nonGeometricActive && covering`。那个决定本身与 D-02 后半句不一致。
  - 实现形状：`FullscreenSignals` 的两个信号位叫 `spaceChangedWhileFullyCovering` /
    `frontmostAppChangedWhileFullyCovering`，都带 `WhileFullyCovering`。因此 `nonGeometricActive` 恒蕴含
    「此刻几何满覆盖」，`verdict = nonGeometricActive && covering` 的**第二项在结构上不是承重项**；
    真正承重的是第一项。
  - 后果：「信号成立但几何不足 → 判定仍为 false」这一行在当前字段命名下**不可达**。
  - `FullscreenDetectorTests` 的第 1/2 条用例证明的是「几何单独为真时判 false」，
    不是「信号单独为真时能触发」。
- **影响**：**Phase 3 交付的是「几何与几何外信号缺一不可」的合取判定，不是 D-02 字面意义的
  「信号可独立触发暂停」。** Phase 5 / Phase 7 读到 D-02 时**不得据此认为已拿到独立触发能力**。
- **解开条件**：独立触发需要另一条**不依赖几何**的信号（例如对目标应用窗口的 `AXFullScreen` 观察）。
  本 Phase 不做，也不在 Phase 3 的成功标准里。
  注：该路径需辅助功能权限，而 PITFALLS Pitfall 2 记录了同类项目为覆盖率阈值申请该权限的争议，
  本项目不申请（`03-CONTEXT.md` 的 `threat_model` 已把「EoP」列为不适用）。
- **描述 D（Plan 03-04 追加）**：`03-CONTEXT.md` 的「已冻结可直接用的接口」段把
  `SettingsStore` 转述成「**含**电池开关位」，与源码不符 —— `03-04-PLAN.md` 的 `<read_first>`
  照抄了这句。实测实施前的 `Sources/PicCore/State/SettingsStore.swift`：
  `Seed` 六个字段 = `sourceFolder` / `rate` / `volume` / `isMuted` / `playMode` / `rotationInterval`，
  `Key` 六个键 = `sourceFolderPath` / `rate` / `volume` / `muted` / `playMode` / `rotationInterval`，
  全文 `battery` 计数 **0**。
- **证据 D**：实际形状是**纯追加** —— `Seed.pauseOnBattery: Bool = false`（`init` 参数**末尾**，带默认值）、
  `Key.pauseOnBattery = "pauseOnBattery"`（第七键）、`SettingsStore.pauseOnBattery` 存储属性、
  `init` 里 `defaults.object(forKey: Key.pauseOnBattery) as? Bool ?? seed.pauseOnBattery`
  （**没有 env 这一级** —— 电源开关不是开发期覆盖项）、`persist()` 多一行。
  既有六字段 / 六键 / 六行 `defaults.set` / 三级优先解析**一个字未改**，
  `SettingsStoreTests.testExistingSeedCallSitesStillCompile` 用**位置无关的具名传参**把这条锁住。
- **描述 E（Plan 03-04 追加）：W 编号段本身冲突。**
  `03-05-PLAN.md` 的 AC（第 293 行）写「`-19` 归 03-04」，而 `03-03` 在 wave 2 里**已经**
  用掉了 `### W-2026-10-03-19`。同一个号被两个 plan 各自声明，且 03-05 的另一条 AC 要求
  `grep -oE '^### W-2026-10-03-[0-9]+' | sort | uniq -d` 的输出**为空**（每个编号只出现一次）。
  两条 AC 在事实上互斥。
- **纠正（PLAN_DEVIATION，判据未放宽）**：**不新建第二个 `-19` 标题**，而是把 03-04 的两条
  追加进**这一个** `-19` 条目（描述 D / E）。理由：
  ① `uniq -d` 为空是 03-05 的硬判据，新建标题会让它当场转红；
  ② `03-04-PLAN.md` 自己那条 AC 也要求「该号不被 03-01/02/03/05 复用」—— 被 03-03 复用是**既有事实**，
     删掉 03-03 的条目等于改别的 plan 的产物，本 plan 无权做；
  ③ 号段表写在 03-05 里，而实际取号是各 plan 各自进行 —— 真正的错在号段表发布得太晚。
  → **03-04 的两条 deviation 与 03-03 的三条共用同一个编号，靠「描述 A…E」分区**，
     标题改为 `Phase 3 / Plan 03-03 + 03-04`。**改的是登记的归口，不是判据。**
- **影响**：**产品行为零影响**。描述 D 是上下文转述与源码的措辞差异（「追加」vs「已有」），
  既有六个调用点不受影响；描述 E 是登记簿自身的编号治理问题。
- **解开条件 D**：无需解锁。描述 E 由 03-05 收口时统一核号段（`-19` 一号两用已在上文留档，
  `-20`~`-23` 仍由 03-05 独占）。
- **status**：open

### W-2026-10-03-19 · deviation · Phase 3 / Plan 03-03 + 03-04

- **描述 A**：计划的威胁模型 T-03-10 写「`CGDisplayRegisterReconfigurationCallback` 一旦注册就**绑定在 `CGMainDisplayID()` 上**」—— 本机 SDK 实测**不成立**。
- **证据 A**：`CGDisplayConfiguration.h:235` 的真实声明是
  `CGError CGDisplayRegisterReconfigurationCallback(CGDisplayReconfigurationCallBack __nullable callback, void * __nullable userInfo)`
  —— **没有 display 参数**，注册与摘除都是**进程级**的。实测 `REGISTER_RC=0 success=true`、`REMOVE_RC=0`。
  `.planning/research/ARCHITECTURE.md` §4 引的同一行号也只说「显示器热插拔 / 配置变更」，没提按屏注册。
- **保留的不变量**：摘不掉 = 进程内永久泄漏，注册与注销必须严格配对 —— 这条一个字没变，改的只是「按什么粒度摘」。
  `DisplayWatcher.stop()` 走 `CGDisplayRemoveReconfigurationCallback`，`DisplayWatcherTests.testStartRecomputesOnceSynchronously` 断言 `unregisterCount == 1`。
- **描述 B**：计划 `<verify>` 的注入式反向验证 perl **在本仓的代码形状下无法编译**。
- **证据 B**：原 perl 把 `public var displayAsleep: Bool` 换成计算属性 `Bool { systemSleeping }`。
  `DisplaySignals` 必须有显式 `init`（否则 `currentSignals()` 构造不出两个字段的值），而该 init 里 `self.displayAsleep = displayAsleep`
  对计算属性赋值是编译错误 → 编译失败会冒充「判据转红」，正是 W-2026-10-03-17 已经点名过的反模式。
- **纠正（判据的**意图**一个字没改）**：把耦合点从「字段声明」移到「init 赋值体」——
  `self.displayAsleep = displayAsleep` → `self.displayAsleep = systemSleeping`。计划 `<action>` 第 6 条本来就写了两个可选口径
  （「把两个字段合并成一个共用字段**或**把仲裁侧改成一次性清空两个 reason 的语义」），本实现取编译得通的那一个。
- **影响**：`testWakingWithDisplayStillAsleepDoesNotResume` 在注入后**转红**（实测 `MUTATED_RC=1`，失败行含
  `holds ("[]") is not equal to ("[HoldReason.displayAsleep]")`），恢复后 `cmp -s` 与备份逐字节一致。
- **描述 C**：熄屏跃迁与睡眠跃迁在本会话**观测不到**；`willSleep` 观察者的投递延迟未实测。
- **证据 C**：`evidence/display-sleep-signals.log` 的 `DISPLAY_SLEEP_TRANSITION=unobservable` 与 `SYSTEM_SLEEP_TRANSITION=unobservable`
  两行（`reason=session_locked CGSSessionScreenIsLocked=1 loginwindow_pid=489`）；同一份日志里
  `CGDisplay_IS_ASLEEP=1`、`DISPLAY_RECONFIG_CALLBACKS_FIRED=0`、`POWER_PREVENT_SYSTEM_SLEEP=1`
  （外部 `caffeinate -i -t 300` 正挡着系统睡眠）。
  ⚠️ 另有一条未实测项：两个 `NSWorkspace` 观察者用 `queue: .main`（与 `FullscreenDetector` 同形），
  `willSleep` 的异步投递与进程真正进入睡眠之间的间隔本会话量不到。
- **影响**：PAUSE-03 / PAUSE-04 的**接线**已证明（`start()` 同步重算实测生效，`DISPLAY_START_SYNC_DELIVERED=1 displayAsleep=1`）；
  「真实跃迁触发暂停 / 唤醒后立刻恢复」**未**证明。已可证明的还有一条**本机独有的强事实**：显示器此刻就是熄着的（`CGDisplay_IS_ASLEEP=1`），
  只等跃迁的实现会永远看不到这一位 —— 启动即重算那条契约在本机不是形式主义。
- **解开条件**：解锁会话后重跑 `bash scripts/probe-display.sh`（约 10 秒，脚本无需修改），需在**熄屏 / 点亮 / 睡眠 / 唤醒**四个跃迁下各观察到一次回调；
  `willSleep` 那条投递延迟交 Phase 7 的 20 轮休眠/唤醒一起量。
- **status**：open

---

## Phase 3 的 W 编号分配表（Plan 03-05 收口）

| 编号 | 归属 | 类别 | 内容 |
|---|---|---|---|
| `-14` ~ `-16` | 03-01 T1 | deviation / unrun-verify | `order` 取值更正 / `PIC_LOCK_SIGNAL_PREFIX` 是脚手架 / 锁屏真实跃迁未观测 |
| `-17` | 03-02 T2 | deviation | SYS-02 判据口径由「token 出现 0 次」改为排除式（B2） |
| `-18` | 03-02 T2 | deviation | D-02 语义降级：交付的是合取判定，不是「信号可独立触发暂停」（W5） |
| `-19` | 03-03 + 03-04 | deviation | 描述 A…E：SDK 与计划两处事实更正 + 注入式变异改点 + 跃迁未观测 + SettingsStore 是纯追加 + **号段一号两用** |
| `-20` | **本 plan T2** | unrun-verify | Phase 3 四类跃迁未观测（锁屏跃迁 / 熄屏 / 睡眠 / 拔电源），逐条列解开条件 |
| `-21` | **本 plan T2** | deviation | 起播路径的设置落位必须门在 `decision.shouldPlay` 后（`setRate` 会复活播放，B1） |
| `-22` | **本 plan T2** | resolved | `W-2026-10-03-10` 的直连 `player.player.play()` 已换成 `arbiter.applyCurrentDecision()` |

`-19` 由 03-03 与 03-04 共用是**既有事实**（见该条描述 E）。`-20` ~ `-22` 由 03-05 独占，
无第二个 plan 声明。本 plan 未新建 `-19`，也未改动 `-14` ~ `-19` 的任何既有条目正文。

### W-2026-10-03-20 · unrun-verify · Phase 3 / Plan 03-05

- **描述**：Phase 3 的四类系统跃迁在本会话**一条都没观测到**，合并登记，逐条给解开条件。
- **证据**：`evidence/holds-live.log` 的 `LOCK_STATE_AT_START=1 source=CGSessionCopyCurrentDictionary.CGSSessionScreenIsLocked loginwindow_pid=489`
  与 `LOCK_READ_RAW=LOCKED=1 KEYS=14` —— **会话全程锁着**，`com.apple.screenIsLocked` 没有跃迁可等；
  `evidence/display-sleep-signals.log` 的 `DISPLAY_SLEEP_TRANSITION=unobservable` 与
  `SYSTEM_SLEEP_TRANSITION=unobservable`（各带 `reason=session_locked CGSSessionScreenIsLocked=1 loginwindow_pid=489`）；
  `evidence/power-signals.log` 的 `POWER_TRANSITION=unobservable reason=requires_physical_unplug … action=unplug_power_cord_required`；
  `evidence/fullscreen-signals.log` 的 `FULLSCREEN_TRANSITION=unobservable reason=session_locked`。
- **已证实的部分（本条不否认）**：`holds-live.log` 里的 hold 是**真实系统信号驱动的**，
  不是合成通知 —— `PIC_HOLD active=1 reason=screenLocked holds=(screenLocked,displayAsleep)`
  与 `PIC_HOLD_SUMMARY summary=锁屏,显示器熄屏 reasons=2`，且 `TICK_PAUSED_LINES=7`。
  两个 reason 都是「启动即同步重算」读到的当前态（锁屏会话 + 显示器已熄），**跃迁本身**仍未观测。
- **逐条解开条件**：
  | 跃迁 | 为什么观测不到 | 解开条件 |
  |---|---|---|
  | 锁屏跃迁 | 会话自始至终 `CGSSessionScreenIsLocked=1`，无 lock→unlock 边沿 | 解锁会话后重跑 `bash scripts/probe-lock.sh`，需看到一次真实的 locked→unlocked 投递与 `seeks` 回锚点 |
  | 显示器熄屏 | `CGDisplay_IS_ASLEEP=1` 是**稳态**，点亮那一下没发生 | 点亮显示器后重跑 `bash scripts/probe-display.sh`，需在 熄屏→点亮 两个跃迁下各见一次回调 |
  | 系统睡眠 | 外部 `caffeinate` 挡着（`POWER_PREVENT_SYSTEM_SLEEP=1`），且 `willSleep` 的投递延迟本会话量不到 | 撤掉 `caffeinate` 并在解锁会话下进入睡眠；投递延迟交 Phase 7 的 20 轮休眠/唤醒 |
  | 拔电源 | 本机在 AC 上（`pmset -g batt` = `AC Power`），本会话无物理动作 | 真拔一次电源线后重跑 `bash scripts/probe-power.sh`（开关需为打开态） |
- **影响**：PAUSE-01 / PAUSE-03 / PAUSE-04 / PAUSE-05 的**接线**已证（四个 `start()` 的同步重算都生效，
  活体 hold 由真实读数产生），**跃迁触发**未证。四条 SC 的结论因此含 `BLOCKED` 分量，见 `03-VERDICT.md`。
- **status**：open

### W-2026-10-03-21 · deviation · Phase 3 / Plan 03-05

- **描述**：**起播路径的设置落位必须整段门在 `decision.shouldPlay` 后面。**
  这是本 Phase 最容易被后人「顺手清理」掉的一条门控，必须留档。
- **依据**：`PlayerController.setRate(_:)` 的实现就是 `player.rate = r`（`Sources/PicCore/Playback/PlayerController.swift:51`）。
  SDK `AVPlayer.h:150` 明文：「Setting the rate to a non-zero value causes the value of `timeControlStatus`
  to become either `WaitingToPlayAtSpecifiedRate` or `Playing`.」本机实测：pause 之后置 rate=1.0，
  `timeControlStatus` 在 0.25 秒内由 `.paused`(0) 变 `.playing`(1)。
- **为什么必须门**：把菜单边界外的 `player.player.play()` 换成 `arbiter.applyCurrentDecision()`
  （D-06）**只是第一步**。`setRate` 本身就是一根能恢复播放的线 —— 不门住它，锁屏会话下起播照样走，
  活体判据 `^TICK … status=paused` 命中数为 **0**。⚠️ 该现象的病因**独立于 D-06 的时序**：
  不要去调 `startWallpaper()` 与 `wiring()` 的先后，那是错修法。
- **证据**：`Sources/PicApp/AppDelegate.swift` 里 `if arbiter.decision.shouldPlay {`（行 296）
  < `player.setRate(store.rate)`（行 297）；`bash test.sh` 的判据
  「起播路径的 setRate 门在 shouldPlay 之后（W-2026-10-03-21 / B1）」；
  `HoldStatusTests.testSetRateOnStartPathIsGatedByShouldPlay` 的两次变异都转红
  （删门控 → 编译失败；把门控换成恒真 → `XCTAssertEqual failed: ("1") is not equal to ("0")`）。
- **活体证据**：`evidence/holds-live.log` 的 `TICK_PAUSED_LINES=7`、`TICK_LINES=7` —— 已 hold 时播放器全程是 `paused`。
- **影响**：**零**。门控只在 `shouldPlay == false` 时生效，此时按 D-13 本来也不该落位速率。
- **status**：open（留档防 Phase 4~7 清理）

### W-2026-10-03-22 · resolved · Phase 3 / Plan 03-05

- **描述**：`W-2026-10-03-10` 登记的 `AppDelegate.startWallpaper()` 起播直连 `player.player.play()` 已收口。
- **证据**：`Sources/PicApp/AppDelegate.swift` 的起播序列现为
  `arbiter.applyCurrentDecision()` → `player.setVolume(store.volume)` → `player.setMuted(store.isMuted)`
  → `if arbiter.decision.shouldPlay { player.setRate(store.rate) }`；
  剥注释后 `player.player.play()` 计数 = **0**、`player.player.pause()` 计数 = **0**
  （`bash test.sh` 的「起播路径零播放器直连」每次重验）；
  `arbiter.applyCurrentDecision()` 计数 = **1**，且出现在 `player.setVolume(` **之前**（D-13 仍成立）。
- **活体证据**：`evidence/holds-live.log` 的 `PIC_HOLD active=1 reason=screenLocked holds=(screenLocked,displayAsleep)`
  与同窗口 7 条 `status=paused` —— 「已 hold 却先播一下」在真实锁屏会话下没有发生。
- **新增成员的边界**：`HoldArbiter.applyCurrentDecision()` **不碰续播锚点、不触发 seek**
  （单测 `testApplyCurrentDecisionForwardsCurrentDecisionWithoutTouchingAnchor`：设锚点 33.0 后调用它，
  `target.seeks` 仍为空，随后解除时 `seeks == [33.0]`）。若它 seek 到锚点，锁屏起播会把播放头拽回暂停处。
- **原窗口的风险描述**（「可能在已 hold 的情况下先 `play()` 一下才被压住」）已不成立。
- **status**：resolved


### W-2026-10-03-23 · deviation · Phase 3 / Plan 03-05

- **描述**：**装配之后，`FullscreenDetector` 在本机会间歇性把 `.fullscreen` 置位，导致壁纸被误暂停。**
  这条在 03-05 之前**在产品里结构上不可达** —— `FullscreenDetector` 从未被 `start()` 过；
  本 plan 在 `wiring()` 里接上第一根线之后，它才第一次在产品里生效。
- **证据**：`evidence/fullscreen-falsepositive.log`。一次插桩观测（临时在 `HoldArbiter.set()` 的
  `target?.arbiterApply` 之前打一行 `DBG_SET`，插桩已移除）读到
  `DBG_SET after=fullscreen before=` → 同一轮 `PIC_HOLD` 由 `holds=(none)` 变为 `holds=(fullscreen)`，
  该轮 `TICK` 为 playing 4 / paused 1。**命中频率：3 轮中 1 轮；随后 5 轮复跑均未复现**
  （`PAUSED_TICKS` 全 0）。如实结论：**间歇性，本会话给不出稳定复现率。**
- **成因（属 03-02 的判定口径，非本 plan 引入）**：03-02 的合取判定是
  `verdict = nonGeometricActive && covering`。本机 Ghostty 恒覆盖（Phase 1 已记
  `FALSE_POSITIVE_OBSERVED=1`，`fullscreen-signals.log:COVERAGE=1.000`）→ `covering` 恒真；
  前台应用一变 `nonGeometricActive` 即真 → 误判。D-02 要求「几何之外信号必须能独立触发暂停」，
  该要求已满足；但**反向**的误暂停方向本会话被实测到了。
- **未修的原因**：改判定口径属 D-02 的架构决策，且需要重新采集真实跃迁样本来选判别信号 ——
  本会话无跃迁可采，**改了就是在没有证据的情况下改架构**。留档交给能采集跃迁的阶段。
- **对判据的影响**：`evidence/holds-live.log` 的第一条 `PIC_HOLD` 在锁屏会话下是
  `holds=(screenLocked,displayAsleep)` 而**不是** `holds=(screenLocked)` —— 本会话锁屏与熄屏两个
  真实信号同时成立。多出来的 `displayAsleep` 属**真实读数**（`CGDisplay_IS_ASLEEP=1`，见
  `display-sleep-signals.log`），**未**为了凑单 reason 去改产品。
- **附：本条与计划 AC 的编号不一致**。`03-05-PLAN.md` 的 `<action>` 说追加 `-20`（四类跃迁未观测）、
  `-21`（B1）、`-22`（W-10 resolved），而同一份计划的 AC 又要求存在 `-23` 并称其为
  「四类跃迁未观测汇总」。两条在同一份文件里互斥。处置：内容按 `<action>` 的三段写入
  `-20` / `-21` / `-22`（与 `W-2026-10-03-19` 描述 E 里「`-20`~`-23` 仍由 03-05 独占」一致），
  **四类跃迁的汇总就在 `-20`**；`-23` 另记本条这一项**本 plan 新发现、计划里没有的**事实。
  两条 AC 都满足（`-23` 存在、`-22` 为 resolved、`uniq -d` 为空），且没有把内容抄两遍。
- **status**：open


### W-2026-10-03-24 · deviation · Phase 4 规划修复第 2 轮

- **描述**：**D-14 的标题句在 `04-CONTEXT.md` 里被记成了「新判据的 `no()` 文案里不要带 `ok()` 的
  同一句判据名」—— 这是反转误记。** 正确规则相反：`no()` 文案**必须带** `ok()` 的同一句判据名
  （逐字相同），红绿靠 ✅ / ❌ 前缀区分。
- **证据**：`test.sh:144-147` 记录 03-01 首跑事故 —— 失败文案写成另一句，下游 `grep -c '❌ <判据名>'`
  命中 0，查不到哪条红了；`test.sh:265-268` 的活体代码就是 `ok "…" || no "…"` 同句。Phase 3 的
  `03-01 / 03-02 / 03-04` 连续三次踩的是**同一个**反转记法：判据转红了但按标题句去 grep 永远命中 0。
- **影响与处置**：4 个 Phase 4 plan（`04-01`~`04-04`）与 `04-CONTEXT.md` 的 D-14 条在规划修复第 2 轮
  统一改写为「必须带」；证据直接引 `test.sh:144-147` 与 `test.sh:265-268`，不再引本条的窗口号。
  做法保留：**判据不放宽，改文案**（`no()` 的判据名与 `ok()` 逐字相同，第二参数才写差异）。
- **status**：resolved


### W-2026-10-03-25 · unrun-verify · Phase 5 / Plan 05-01

- **描述**：`scripts/run-uitests.sh` 的**锁屏 BLOCKED 分支**在本会话从未走到（`SCREEN_LOCKED=0`，
  会话全程解锁），故 XCUITest 在锁屏条件下的行为**未被验证**。该分支是照 Phase 2/3 的 BLOCKED
  先例建的护栏，不是本 plan 的产品交付面。
- **证据**：`.planning/phases/05-settings/evidence/uitest.log` 的 `SCREEN_LOCKED=0` +
  `UITEST_STATUS=passed`；脚本第 4 分支 `if [ "$LOCKED" = 1 ]` 的 grep 守卫
  （`grep -q 'W-2026-10-03-25' .planning/WINDOWS.md`）在本条目入库前会打
  `W_ENTRY_MISSING` 并退出非 0 —— 那条守卫**本身**已被实际走过一次（首跑时本条目还不存在）。
- **影响**：解锁会话下 3 条 XCUITest 全绿已证明；锁屏会话下的「blocked 而非 failed」这一半
  仍是**未跑**的分支。
- **解开条件**：锁屏后重跑 `bash scripts/run-uitests.sh`，期望读到
  `UITEST_STATUS=blocked reason=screen_locked` 且退出码 0。
- **status**：open


### W-2026-10-03-48 · unrun-verify · Phase 5 / Plan 05-01

- **描述**：`scripts/run-uitests.sh` 的**屏幕录制未授权 SKIPPED 分支**在本会话从未走到
  （实测 `CGPreflightScreenCaptureAccess()` 为已授权，`SCREEN_CAPTURE_AUTHORIZED=1`）。
  该分支是照锁屏分支的同纪律护栏 —— 不硬闯 macOS 的「打开系统设置」授权链。
- **证据**：`evidence/uitest.log` 的 `SCREEN_CAPTURE_AUTHORIZED=1`；脚本第 4b 分支
  `if [ "$CAP" = 0 ]` 与锁屏分支同形（同样先 grep W-2026-10-03-48，缺条目则
  `W_ENTRY_MISSING` 退出非 0）。
- **触发背景（如实记录）**：本 plan 首版的 `testCommandCommaOpensSettings` 向系统发送了
  真实 `⌘,` 按键。本 app 是 `.accessory` 菜单栏 app，无 key window 时该按键被系统接管，
  **实测误开了「系统设置」** —— 污染用户机器。该用例已改写为「点菜单栏图标 → 断言菜单项
  逐字是「打开设置 ⌘,」→ 点它开窗」，不再发系统级按键（见 `W-2026-10-03-49`）。
- **影响**：解锁 + 已授权会话下测试可跑已证明；未授权会话下「skipped 而非硬闯弹窗」这一半
  仍是**未跑**的分支。
- **解开条件**：在 系统设置 → 隐私与安全性 → 屏幕录制 里撤销本终端/Xcode 的授权后重跑
  `bash scripts/run-uitests.sh`，期望读到
  `UITEST_STATUS=skipped reason=screen_capture_unauthorized` 且退出码 0。
- **status**：open


### W-2026-10-03-49 · unrun-verify · Phase 5 / Plan 05-01

- **描述**：**`⌘,` 的实际按键响应未被 XCUITest 证明。** 计划要求用
  `app.typeKey(",", modifiers: .command)` 验证，实际该写法在本机会**误开「系统设置」**
  （accessory app 无 key window，系统接管该快捷键），既证不了产品、又在污染用户机器。
- **证据**：`evidence/uitest.log` 首版 `testCommandCommaOpensSettings` 连续三轮「通过」，但
  通过时开的是系统设置而非产品窗口 —— 该「绿」不成立，已弃用；改为
  `testSettingsMenuItemRendersShortcutAndOpensWindow`（点菜单栏图标 → 断言菜单项逐字是
  「打开设置 ⌘,」→ 点它开窗），**在本条目入库后未重跑**（见本 SUMMARY「Issues Encountered」）。
- **已证明的替代面**：菜单里「打开设置 ⌘,」的**逐字文案与快捷键渲染**由
  `MenuContentView` 的 `MenuShortcut` ViewModifier 单点产出（`keyboardShortcut(",", modifiers: .command)`，
  全仓 1 处），XCUITest 断言菜单项文案即覆盖该渲染契约。
- **影响**：MENUBAR-06 的「键盘等价键真的能开窗」这一跳**未证明**；其余行为属性
  （780 宽、关窗进程不退）已证明。
- **解开条件**：在 XCUITest 里让 app 先获得 key window（例如经 `--open-settings` 开窗后
  关闭，让 app 短暂持有一个窗口再发按键），或由真人在解锁会话手动按一次 ⌘, 对照设置窗打开。
  **在能不发系统级按键的前提下证明它之前，不要恢复 `typeKey(",")` 那条用例。**
- **status**：open


### W-2026-10-03-28 · unrun-verify · Phase 5 / Plan 05-02

- **描述**：**「改值 → 重启 → 回读」的交互半边未被自动验证。** 探针
  `scripts/probe-settings-restart.sh` 覆盖的是 **seeding 路径**（进程名域写值 → 起进程 →
  `PIC_SETTINGS_BOOT` 逐字回读 → 清场后回默认值，三轮全绿）；真人/XCUITest 在设置窗里
  拖一次滑杆、翻一次分段、关一次开关，再重启回读的那条路径**本轮没跑**
  （05-01 的 XCUITest 从未达绿，见 `evidence/uitest.log` 与本 plan 的 Issues）。
  连带地，`PIC_SETTINGS_APPLY key=…` 在**运行期**的触发行数为 0 ——
  apply 由控件事件驱动，无人交互就不会触发。
- **证据**：`evidence/settings-restart.log` 三轮 `ROUND1_SEEDED=ok` /
  `ROUND2_IDEMPOTENT=ok` / `ROUND3_DEFAULTS=ok`；
  `evidence/settings-apply.log` 的 `APPLY_EMIT_SITES=6`（emit 落点在位）/
  `APPLY_RUNTIME_LINES=0`（运行期未触发，如实记 0 而不是省略）。
  值断言不在探针层，在 `SettingsApplierTests` 四条（applyMode / applyInterval /
  applyBatteryPolicy 两个方向）。
- **影响**：PLAY-08/09/10「改完当场生效 + 重启保留」的**机制面与持久面**已证明；
  **UI 事件 → apply** 这一跳只有代码形态与单测层的机制证明，没有运行期证据行。
  两条置灰联动的交互断言同理（XCUITest 面归 05-04）。
- **解开条件**：解锁且屏幕录制已授权的会话里跑 `bash scripts/run-uitests.sh`，
  用例覆盖「改值 → 断言控件读数 → 退出进程 → 重启 → 断言回读」，
  或由真人在设置窗手动改一项后重启对照。解锁条件与守卫分支见 `W-2026-10-03-25`
  与 `W-2026-10-03-48`。
- **status**：open


### W-2026-10-03-29 · unrun-verify · Phase 5 / Plan 05-03

- **描述**：**SC-5 ③ 的活体目视未做** —— 锁屏态打开设置窗看到「屏幕已锁定」副标签这一跳，
  本会话全程屏幕锁定（`evidence/status-card.log:LOCK_STATE_AT_PROBE=1`），无法开窗目视。
- **证据**：`evidence/status-card.log` 的 `LIVE_LOCK_OBSERVATION=blocked reason=screen_locked`；
  `LIB_STATE_EMPTY=ok` / `FFMPEG_SELF_CONSISTENT=ok` 说明探针其余部分在本会话照跑。
  探针的 blocked 分支先 grep 本条目存在，缺条目即 `LIVE_LOCK_W_ENTRY_MISSING` 退出非 0
  —— 守卫本身走的是同 W-2026-10-03-25 的形状。
- **已证明的替代面**：原因→文案的映射（`screenLocked` → 「屏幕已锁定」）由
  `SettingsPresentation.holdReasonLabel` 的穷举单测逐字锁定（全 6 case，两两不同）；
  「有原因则标题已暂停 + 副标签非空」的分支由 `joinedReasons` 的空集/单条/多条三条用例覆盖。
  **数据链与文案都钉住了，只有「屏上真的出现这行字」未目视。**
- **影响**：UI-04（SC-5）的机制面与文案面已证明；渲染面缺一次活体确认。
- **解开条件**：解锁会话里打开设置窗目视一次；或 05-04 用 XCUITest 注入合成锁事件
  （`PIC_LOCK_SIGNAL_PREFIX`，见 `scripts/probe-lock.sh`）复跑并断言
  `status-paused` 行的副标签逐字等于「屏幕已锁定」。
- **status**：open


### W-2026-10-03-30 · deviation · Phase 5 / Plan 05-03

- **描述**：运行状态卡的 ffmpeg 行**只报可用性**，不显示版本串（UI-SPEC §7 表里的
  「9.0.2 · 可用」在本 Phase 落成「可用」/「未安装」两个值）。
- **证据**：UI-SPEC §12 明写「状态卡只报可用性」，完整安装指引与版本串归 Phase 6（TRANS-02）；
  `Sources/PicCore/App/FFmpegAvailability.swift` 剥注释后 `Process(` 计数 0 —— Phase 5
  **零 ffmpeg 执行**（主会话硬红线：ffmpeg 类调用绝不进自动路径，本机也无 timeout 机制），
  不跑它就拿不到版本号。`evidence/status-card.log:FFMPEG_SELF_CONSISTENT=ok available=1 label=可用`。
- **影响**：用户看不到「装的是哪个版本」。本 Phase 转码入口是 disabled 占位、
  不执行 ffmpeg，所以拿不到版本号不造成功能缺口 —— 是一处**已知不完整**而非缺陷。
- **解开条件**：Phase 6 TRANS-02 真正与 ffmpeg 交互时，把
  `FFmpegAvailability.label(available:)` 扩成带版本的形态；届时
  `Sources/PicCore/Transcode/ExternalToolLocator.swift` 的 `locate()`（已拿到
  `available(path:)`）收编本判定为薄委托，避免出现两个 ffmpeg 探测真相源。
  **06-05 复核：判定侧已收编（06-04 的 `FFmpegToolStatus` 单一真相源），但版本串
  仍未显示（`grep -n version` 在 `ExternalToolLocator` 与三个 Transcode 视图里命中 0）
  —— 本条按原口径保持 open，Phase 6 不改它的状态。**
- **status**：open


### W-2026-10-03-34 · decision · Phase 6 / Plan 06-05

- **描述**：**D-23 的裁决** —— 04-01 的 `MediaLibrary` 把 `Converted/` 整棵排除
  （`excludedByConverted` 是全排除，fixture 表明示），而 ROADMAP Phase 6 的 SC#5 又要求
  「转完即播」。两条都照字面做会互斥：产物永远不在 `report.items` 里。
  裁决 = **产物仍留 `Converted/`（D-21 不动）+ 新开 `ConvertedLibrary` 作播放第二入口 +
  在 `router.start(with:)` 的调用点把两侧清单合并去重**。
- **替代方案与否决理由**：
  ①「把 `Converted/` 从排除名单里删掉」—— 否决：`TranscodeCandidateFilter` 与
     `MediaLibrary` 共享同一套扩展名白名单，删了就无法区分「源」与「产物」，
     转码产物会重新进候选队列，防回流的第一层直接失效。
  ②「转完后把产物挪回根目录」—— 否决：源与产物同名会互相覆盖，且用户原始素材目录
     被 app 写入是不可逆的副作用（TRANS-04「源保留不删」也会被打破）。
- **证据**：`04-01-PLAN.md` 的 fixture 表 `Converted/out.mp4` 期望「整棵排除」；
  `Sources/PicCore/Media/MediaLibrary.swift:32` 的 `excludedDirectoryName = "Converted"`；
  ROADMAP Phase 6 SC#5 原文；合并纯函数在
  `Sources/PicCore/Transcode/ConvertedLibrary.swift:52`（`playbackItems(root:converted:)`，
  按 `url.path` 去重、root 序在前）。
- **影响**：06-01 建 `ConvertedLibrary`；**06-05 T1 落装配** —— `AppDelegate` 的
  `mergedPlaybackItems(_:)` 成为播放清单的唯一产出处，`router.start(with:)` 的两个调用点
  （`startWallpaper` 与 `dispatchPlayback`）全部改走它；
  `transcodeQueue.onBatchFinished` → `invalidateCache()` → `rescanAndApply()` 补上
  「排空后当轮进清单」的最后一跳（少这一步，缓存会让新产物永远看不见，且不报错）。
- **status**：resolved


## resolved

- **W-2026-10-03-09** · `NSApp.terminate` 第二处 —— 本 Phase 已收敛为 1 处并挂进 `test.sh` 每次重验
- **W-2026-10-03-13** · `test.sh` UTF-8 locale 下按字节偏移丢 2 字节 —— 已用 `export LC_ALL=C` 修复，未改判据语义
- **W-2026-10-03-14** · `HoldReason.order` 与 Phase 2 注释预告冲突 —— 已改为 1…5 并挂进单测每次重验