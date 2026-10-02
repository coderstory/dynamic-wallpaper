PHASE_2_VERDICT

# Phase 2 判定：播放内核竖切

**本文件是 Phase 2 的唯一判定文件。Phase 3–7 只引用它**，不回翻四份 SUMMARY 与 git log。
判据输入全部来自 `.planning/phases/02-playback-core/evidence/` 下的原始日志，不从 SUMMARY 转述。

**产品未在解锁会话验证过。** —— 这行不加任何限定语。`evidence/gate-rerun.log` 首行
`GATE_RERUN=blocked`，`REASON=session_locked CGSSessionScreenIsLocked=1 loginwindow_pid=489`。
本文件里所有实测读数都产生于锁屏会话。

Phase 1 的门禁日志 `evidence/gate-01-locked-session.log` 是锁屏会话下的原始证据，
与本 Phase 的证据**并列保存，互不覆盖**。Phase 1 的 `01-VERDICT.md` 结论
（`GATE=A`）仍然只在其自己的适用边界内成立。

## 5 条 Success Criteria 逐条结论

判据原文见 `.planning/ROADMAP.md` Phase 2 Success Criteria 第 1–5 条。结论列只有
`PASS` / `PASS-with-gap` / `PARTIAL` / `BLOCKED` 四种取值，每行都挂一个真实证据路径与一个数字。

| SC | 结论 | 证据（文件:字段） | 数字 |
|---|---|---|---|
| SC1 菜单栏常驻图标 + Dock 无图标 + 桌面图标后有视频播放 + 点击拖动桌面图标不受影响 | **PASS-with-gap** | 自动部分：`app-bundle.log:APP_ACTIVATION_POLICY` `:LSUILEMENT` `:ORDER`；`order.log:SELF_LEVEL` `:ICON_LEVEL` | `APP_ACTIVATION_POLICY=1`（`.accessory`，0 才是 `.regular`）；`LSUIElement=true`；`SELF_LEVEL=-2147483623` < `ICON_LEVEL=-2147483603`，差 20 级；`ORDER=ok`。**缺口：「点击和拖动桌面图标不受影响」未验证** —— 需真人手点，本机无屏幕录制权限且用户不在场，见「没跑过」③ |
| SC2 裁剪填满铺满主屏、无黑边无变形；连续 5 分钟无缝循环、无黑帧无卡顿无跳帧 | **PARTIAL** | `inset.log:INSET_*` `:SCREEN_FRAME`；`loop.log:LOOP_VERDICT` `:LOOP_CYCLES` `:LOOP_SAMPLES`；`loop.log:BLACKFRAME` | 循环部分全过：`LOOP_VERDICT=pass`、`LOOP_SAMPLES=150`、`LOOP_CYCLES=37`、`LOOP_ENDED=37`、`LOOP_STALLED=0`、`LOOP_FAILED=0`、`LOOP_DURATION=300`。裁剪几何：`INSET_LEFT=14 TOP=9 RIGHT=14 BOTTOM=9`，`SCREEN_FRAME=0,0,1470,956`。**缺口：「无黑帧」未验证** —— `BLACKFRAME=blocked reason=no_screen_recording_permission`，两张抓图平均亮度停在 YUV 黑电平 16.0 / 16.0027（白对照 235，阈值 23.5），见「没跑过」① |
| SC3 菜单项暂停/继续可用且从原处续播；菜单项退出能真正结束进程 | **PASS-with-gap** | `swift test` 24 项全绿（`HoldArbiterTests` 续播锚点两用例 + `MenuBarModelTests`）；`quit.log:QUIT_HOOK_SEEN` `:QUIT_EXITED` | `Executed 24 tests, with 0 failures`；`QUIT_HOOK_SEEN=1`、`QUIT_EXITED=1`、`QUIT_WALL_SECONDS=4`。**缺口：「真人点击菜单项」这一跳未验证** —— 菜单动作本身接的是同一个 `terminateApp()`，但「真人点 → 同一条路径」需要 XCUITest 或辅助功能权限，见「没跑过」④ |
| SC4 菜单不显示当前播放的文件名，只有固定的菜单项 | **PASS** | `test.sh` 的「菜单只由 MenuItemID.allCases 遍历渲染」+「菜单结构体内零取文件名 API（MENUBAR-08）」两条源码判据；`MenuBarModelTests` 哨兵单测 | 渲染处 `Button(` 行数 = `ForEach(MenuItemID.allCases` 行数；剥注释后菜单结构体行区间内 `lastPathComponent|fileName|absoluteString` 计数 = 0。该哨兵单测在 02-03 曾反向验证改红过一次，说明它会真红 |
| SC5 切换 Space / 进台前调度后壁纸按系统默认行为表现（不消失、不报错），且未做任何 Space 级特殊处理 | **PARTIAL** | `test.sh` 的「Sources/ 零 Space 级特殊处理（SYS-02 自动判据）」；`inset.log:SCREENS_COUNT` | 自动部分：剥注释后 `Sources/` 内 `activeSpaceDidChangeNotification` 计数 = 0（D-04 / SYS-02 的自动判据，每次 `bash test.sh` 自动重验）。**缺口：「切换 Space 后壁纸不消失」未验证** —— 需真人 Mission Control 操作，本机 `SCREENS_COUNT=1`，见「没跑过」② |

**SC1 / SC2 / SC3 都不写 `PASS`。** 它们的自动部分过了，但人工部分没过，
按 Phase 1 SC4 翻车的教训（`01-VERDICT.md` 自述「VERDICT overstated its LOCK= evidence chain,
SC4 relabelled PARTIAL」），缺口必须落在结论列里，不能塞进脚注。

## 四栏口径

## 跑过

| 项 | 命令 | 产物 | 数字 |
|---|---|---|---|
| 解锁会话门禁复跑（PDCA-A1） | `bash .planning/spike/run-gate.sh` | `evidence/gate-rerun.log` | `GATE_RERUN=blocked`；`CGSSessionScreenIsLocked=1`；`loginwindow_pid=489` —— 锁屏，未复跑成功 |
| 产品代码编译 | `swift build` | 终端输出 | `Build complete!`；`swift build -c release` 亦通过 |
| 产品单测 | `swift test` | 终端输出 | `Executed 24 tests, with 0 failures` |
| 层级序 + 按 PID 认领 | `bash scripts/run-probe.sh order` | `evidence/order.log` | `ORDER=ok`、`REASON=none_all_four_criteria_met`、`SELF_LEVEL=-2147483623`、`ICON_LEVEL=-2147483603`、`SELF_LEVEL_CROSSCHECK=agree`、`WINDOWS_TOTAL=17`、`OWNED_WINDOW_COUNT=1`、`FOREIGN_SAME_LEVEL=0`、`FOREIGN_DESKTOP_FAMILY=7`、`PID_CLAIM_REQUIRED_BAND=1` |
| 几何内缩实测（D-08） | `bash scripts/run-probe.sh inset` | `evidence/inset.log` | `INSET_LEFT=14`、`INSET_TOP=9`、`INSET_RIGHT=14`、`INSET_BOTTOM=9`、`SCREEN_FRAME=0,0,1470,956`、`WINDOW_FRAME=14,9,1442,938`、`SCREENS_COUNT=1` |
| 300 秒无缝循环 | `bash scripts/run-probe.sh loop` | `evidence/loop.log` | `LOOP_VERDICT=pass`、`LOOP_SAMPLES=150`、`LOOP_CYCLES=37`、`LOOP_ENDED=37`、`LOOP_ENDED_PER_CYCLE=1.000`、`LOOP_STALLED=0`、`LOOP_FAILED=0`、`LOOP_DURATION=300`、`LOOP_POS_MONOTONIC=0` |
| 优雅终止收尾 | `bash scripts/run-probe.sh quit` | `evidence/quit.log` | `QUIT_HOOK_SEEN=1`、`QUIT_EXITED=1`、`QUIT_WALL_SECONDS=4`、`SIGTERM_HOOK_SEEN=0`（观测值，不作断言） |
| 打包产物层级复验 + ad-hoc 签名 | `bash scripts/run-probe.sh app` | `evidence/app-bundle.log` | `ORDER=ok`、`ORDER_AFTER=ok`、`KILLALL_RC=0`、`ALIVE_AFTER_FINDER_RESTART=1`、`APP_ACTIVATION_POLICY=1`、`LSUIElement=true`、`PLIST_USAGE_DESCRIPTION_COUNT=0`、`IDENTIFIER=com.local.pic`、`SIGNATURE=adhoc`、`AUTHORITY_DEV_ID=0`、`FOREIGN_SAME_LEVEL=0` |
| 显示刷新驱动复测（PDCA-A4） | `bash scripts/run-probe.sh refresh` | `evidence/refresh.log` | `swift_run` 与 `app_bundle` 两轮的 `DRIVER` **都是** `timer_fallback_hz30`，`TICK_RATE=27.2`（`REFRESH_TICK_COUNT=272` / `REFRESH_WINDOW_SECONDS=10.0`）；`REFRESH_VERDICT=blocked`、`REFRESH_SESSION=locked` |
| 打包 | `bash build.sh` | `build/Pic.app`、`dist/Pic-0.1.0.dmg` | `.app` 二进制 393872→403696 bytes（随源码变化）；`DMG` 141K；`Signature=adhoc`、`Identifier=com.local.pic` |
| 无头回归 | `bash test.sh` | 终端输出 | `通过 32  失败 0  跳过 0`；把 `build/` 移走后的干净环境：`通过 27  失败 0  跳过 5`，退出码仍为 0 |

## 没跑过

| 项 | 为什么没跑 | 证据 |
|---|---|---|
| SC2 的「无黑帧」 | 本机终端/CLI 无屏幕录制权限，`screencapture` 取回的帧不含桌面内容。判据在**原理上**无法进行，不是脚本没写 | `loop.log:BLACKFRAME=blocked reason=no_screen_recording_permission`；`capture_a_yavg=16`、`capture_b_yavg=16.0027`、`white_control_yavg=235`、`threshold=23.5` —— 两张都停在 YUV 黑电平 16 上 |
| SC5 的「切换 Space 后壁纸不消失」 | 需真人 Mission Control 操作与多 Space 环境；本机单屏且会话锁定 | `inset.log:SCREENS_COUNT=1`；`gate-rerun.log:REASON=session_locked` |
| SC1 的「点击和拖动桌面图标不受影响」 | 需真人手点；本 Phase 无屏幕录制权限可作旁证，且用户不在场 | 无自动信号能覆盖「手点」这个动作；本文件不给它编数字 |
| SC3 的「真人点菜单栏图标退出」 | 无 `.xcodeproj` 故无 XCUITest（D-01），无辅助功能权限 | `WINDOWS.md:W-2026-10-03-07` 已登记。已自动证明的两段：① 菜单 `.quit` 的动作就是 `terminateApp()`（`MenuBarModelTests.testPerformQuitCallsInjectedClosureOnlyOnce`）② `NSApp.terminate` 路径跑完 `applicationWillTerminate` 且进程消失（`quit.log:QUIT_HOOK_SEEN=1` / `QUIT_EXITED=1`）。未证明的是「真人点击 → 同一条路径」这一跳 |
| `powermetrics` 四组 A/B 的 mW 数字 | Phase 1 的 `AB_GROUPS_MEASURED=0` 从未被解封（本机无免密 sudo），本 Phase 无新增数字 | `01-VERDICT.md:SC5` 行 `AB_GROUPS_PLANNED=4 AB_GROUPS_MEASURED=0` |
| 解锁会话下的门禁复跑 | 屏幕锁着。**不重试到出结果为止** —— 用户已授权「无法解决的跳过」 | `gate-rerun.log`；`lock-state.txt:LOCKED=1 ONCONSOLE=1 LOGINWINDOW_PID=489` |

## 逻辑可行但本 Phase 未测

| 项 | 逻辑依据 | 本 Phase 未测什么 |
|---|---|---|
| Phase 3 的 4 个 watcher 接口能接进 `HoldArbiter` | `HoldArbiter` 已建成 `Set<HoldReason>` veto 集合，`HoldReason` 只有 `.manualPause` 一个 case；接 4 个 watcher 是往同一个集合里加 case | 没接、没测。多 reason 叠加（6 reason × 64 子集）属 Phase 3 的 TEST-01，**本 Phase 不冒充已验证** |
| Phase 4 的 `MediaLibrary` 能喂 `PlayerController.load(url:)` | `PlayerController.load(url:)` 接口已定稿；当前 `AppDelegate.startWallpaper()` 只做「非递归枚举 + 按文件名排序取首个 mp4」 | 只播过单文件。递归扫描、三种轮换模式、失效降级全部未测 |
| `WallpaperWindowController` 在真实 Space 切换下不消失 | `collectionBehavior` 四项（`.canJoinAllSpaces` / `.stationary` / `.ignoresCycle` / `.fullScreenNone`）在位，且 `Sources/` 内 `activeSpaceDidChangeNotification` 计数为 0，结构上依赖系统默认行为 | 本机单屏 + 会话锁定，**真实 Space 切换一次都没复现过** |
| `.app` 形态下的 `FrameDriver` 或许能拿到 display_link | Phase 1 的降级发生在 `swift run`（无 bundle id、无 `Info.plist`）下；打包成 `.app` 后它是一个真正的前台应用 | 本机实测**没能证明**：两种形态的 `DRIVER` 都是 `timer_fallback_hz30`。见下方「一条必须写明的发现」 |

## 假定依赖

| 项 | 假定内容 | 未验证之处 |
|---|---|---|
| 门禁结论 `GATE=A` 的适用边界 | 假定它**只在锁屏会话下成立**。Phase 2 没有拿到任何解锁态的层级读数 | 未在解锁会话重跑 `run-gate.sh`。若解锁后 `ORDER` 或 `FINDER_RESTART_ALIVE` 不成立，Phase 1 的 `GATE=A` 需降级 |
| 第三方壁纸 app 的窗口层级 | 假定本机有同处 `-2147483623` 的常驻窗口（D-09 的原始依据，编排器实测） | 本会话未复现：`order.log:FOREIGN_SAME_LEVEL=0`、`FOREIGN_OWNERS=none`，但同层族（±64 级）内 `FOREIGN_DESKTOP_FAMILY=7`。**不把 0 改写成 1。**产品代码按 PID 认领，不依赖这个数字 |
| `screencapture` 的权限状态 | 假定它不可用 —— 已知返回固定占位图 / 无桌面内容 | 从未申请过该权限。下游任何依赖截图的判定都要先解这一项 |
| `hdiutil` 产出的 DMG 可复现 | 假定它**不可复现** —— 四次独立 `build.sh` 的 DMG md5 全部不同 | 已排除的只有「我们的输入不是确定性产物」：`app-bundle.log:DMG_REPRODUCIBLE_NOTE_2` 记两个 DMG 内的 `Pic.app` 逐字节相同（二进制 md5 `662e6321…`、Info.plist md5 `f85a5701…`）。把源树 mtime 全部 pin 成同一时刻后，相隔 2 秒的两次 `hdiutil create` 仍产出不同 md5（`9e20b8a9…` vs `936dab1c…`），故 mtime 不是唯一变量。**未定位到 UDIF 容器内具体哪几个字节在变** |
| 打包产物在本机右键打开时的 Gatekeeper 行为 | 假定它会提示（ad-hoc 签名 + 未公证） | 本 Phase 未把 `.app` 拖进 `/Applications` 走一次真实的双击路径。T-02-12 已把它登记为「已知且已接受」 |

## 一条必须写明的发现：`.app` 下**仍然**拿不到显示刷新回调

这是本 Phase 唯一推翻 Phase 1 隐含假设的测量，如实记，不粉饰成「正常」。

Phase 1 把帧号当「画面在动」的证据时，测到的是降级路径
（`FRAME_DRIVER=timer_fallback_hz30`），并留下一条硬约束：*「本 Phase 的降级证据不等于
产品行为。显示刷新回调在本进程拿不到，打包成 `.app` 后必须复测。」*

本 Phase 复测了（`evidence/refresh.log`）：

| 运行模式 | `DRIVER` | `TICK_RATE` | 证据 |
|---|---|---|---|
| `swift_run` | `timer_fallback_hz30` | 27.2（272 tick / 10.0s 窗口） | `REFRESH_RUN_MODE=swift_run DRIVER=timer_fallback_hz30 TICK_RATE=27.2` |
| `app_bundle` | `timer_fallback_hz30` | 27.2（272 tick / 10.0s 窗口） | `REFRESH_RUN_MODE=app_bundle DRIVER=timer_fallback_hz30 TICK_RATE=27.2` |

`REFRESH_VERDICT=blocked`，`REFRESH_BLOCKED_REASON=no_display_link_in_any_mode`，
`REFRESH_SESSION=locked`。

**结论的边界必须一起读：** 会话锁着（`REFRESH_SESSION=locked`），所以这次测量
**无法区分**两件事 ——「`.app` 形态也拿不到显示刷新回调」与「锁屏会话压制了显示回调」。
两者在解锁会话下会给出不同答案，而解锁后本机读不到答案。**它不是「打包成 `.app` 就该有」，
也不是「`.app` 也没用」，而是「这一条在锁屏会话下测不出来」。**

`IMPACT_ON_PHASE3=显示刷新回调不可用；Phase 3 的锁屏/熄屏检测必须走事件通知而非逐帧轮询`。

产品侧的处置：`Sources/PicCore/Playback/FrameDriver.swift` 是**纯测量器**，不接任何渲染路径
（剥注释后该文件内 `AVPlayerLayer` 计数 = 0），测满 10 秒窗口即自行 `invalidate()`，
不留常驻 30Hz 定时器。它在 `Sources/` 全树只有两处引用 —— 自身的类型声明与
`AppDelegate` 的持有，判据：`grep -rl 'FrameDriver' Sources/ --include='*.swift' | grep -vE 'AppDelegate\.swift$|Playback/FrameDriver\.swift$'`
输出为空。

## 承接 WINDOWS.md 的十条已知窗口

`WINDOWS.md` 里 Phase 2 的 10 条窗口**全部仍在 `open`**，本 Phase 一条都没有关闭。
逐条对应如下：

| 窗口 | 本 Phase 的动作 | 状态 |
|---|---|---|
| W-2026-10-03-01 无黑帧 | 复跑 `run-probe.sh loop`，`BLACKFRAME=blocked` 依旧，`capture_a_yavg=16` | open（SC2 缺口） |
| W-2026-10-03-02 Space 切换 | 未动。本机 `SCREENS_COUNT=1`，无法复现 | open（SC5 缺口） |
| W-2026-10-03-03 门禁复跑 | 复跑入口即 `run-gate.sh`，脚本无需修改；本机仍锁屏 | open |
| W-2026-10-03-04 循环判据①被证伪 | 已按纠正后的判据取数：`LOOP_VERDICT=pass`、`LOOP_ENDED=37 == LOOP_CYCLES=37` | open（留档防 Phase 3/4 复抄） |
| W-2026-10-03-05 `FOREIGN_SAME_LEVEL=0` | 在打包产物上再测一次，仍是 0：`app-bundle.log:FOREIGN_SAME_LEVEL=0`、`FOREIGN_DESKTOP_FAMILY=7` | open |
| W-2026-10-03-06 层级判据自相矛盾 | 本 Phase 的源码判据不含全树 `CGWindowLevelForKey` 计数，与 D-04 一致 | open（留档） |
| W-2026-10-03-07 真人点菜单退出 | 复跑 `run-probe.sh quit`，两段自动证据仍成立（`QUIT_HOOK_SEEN=1`/`QUIT_EXITED=1`）；真人那一跳仍未测 | open |
| W-2026-10-03-08 `--quit-after` 是测试脚手架 | **本 Phase 保留它但未扩大它**：`quit.log:QUIT_TRIGGER=--quit-after 3 启动参数（测试脚手架，不是产品能力）`。它仍是 Phase 2 全树唯一的启动参数钩子 | open（XCUITest 可用后删除） |
| W-2026-10-03-09 `NSApp.terminate` 第二处 | 本 Phase 改 `build.sh` / 新增 `FrameDriver` 后重验：`grep -rn 'NSApp.terminate' Sources/` 仍为 **1** | resolved（本 Phase 重验通过） |
| W-2026-10-03-10 `startWallpaper()` 直连 `player.play()` | **未改动，也未复核**。Phase 3 接 watcher 时必须一并复核起播与 watcher 首次置位的时序 | open |

## Phase 2 的 8 个 requirement 覆盖对照

| ID | 交付 plan | 自动证据 |
|---|---|---|
| PLAY-01 | 02-02 T1/T3、02-04 T1 | `order.log:SELF_LEVEL=-2147483623` < `ICON_LEVEL=-2147483603`；打包产物上 `app-bundle.log:ORDER=ok`；`test.sh` 判据「Sources/ 无硬编码桌面层级字面量（D-04）」 |
| PLAY-02 | 02-02 T2 | `videoGravity = .resizeAspectFill`（源码判据）+ `inset.log` 四个内缩整数 14/9/14/9 |
| MENUBAR-01 | 02-02 T1（运行期）、**02-04 T1（打包期）** | 运行期 `app-bundle.log:APP_ACTIVATION_POLICY=1`；打包期 `LSUIElement=true`（`plutil -extract` 读出字面量 `true`） |
| MENUBAR-03 | 02-03 T1 | `HoldArbiterTests` 续播锚点两用例 + `MenuBarModelTests.testPerformQuitCallsInjectedClosureOnlyOnce` |
| MENUBAR-07 | 02-03 T2/T3 | `quit.log:QUIT_HOOK_SEEN=1` / `QUIT_EXITED=1`；`test.sh` 判据「结束进程的全局调用全仓唯一落点」= 1 |
| MENUBAR-08 | 02-03 T3 | 哨兵单测 + `test.sh` 两条源码判据（`Button(` 行数 = `ForEach(MenuItemID.allCases` 行数；菜单结构体行区间内取文件名 API 计数 = 0） |
| PAUSE-08 | 02-01 T3、02-03 T1/T2 | `.manualPause` 经 `HoldArbiter` 的 Set 生效；02-01 T3 幂集测试覆盖当期 `allCases` 的 2^n 子集（n=1 → 2）+ 锚点写/清；02-03 T2 锚点不被二次覆盖。**多 reason 叠加（6 reason × 64 子集）属 Phase 3 的 TEST-01，本 Phase 不冒充已验证** |
| SYS-02 | 02-02 T3 | `collectionBehavior` 四项在位 + `test.sh` 判据「Sources/ 零 Space 级特殊处理」计数 = 0 |

## 交给下一阶段必须处理什么

**Phase 3 之前（阻塞级）**

1. **在解锁会话重跑 `bash .planning/spike/run-gate.sh`。** 约 1 分钟，脚本无需修改。
   不重跑的话，Phase 1 的 `GATE=A` 与 Phase 2 的全部层级读数都只在锁屏会话下成立。
2. **给终端 / CLI 授屏幕录制权限**（或由真人在解锁会话观察 5 分钟），
   解开 SC2 的「无黑帧」缺口。
3. **真人手动切一次 Space**，解开 SC5 的缺口。

**Phase 3 内（必做，接口已定）**

4. **`REFRESH_VERDICT=blocked` → 逐帧轮询这条路作废。** 锁屏 / 熄屏 / 睡眠 / 电源
   四类检测必须走事件通知（`CGSSessionCopyCurrentDictionary` / `NSWorkspace` 通知 /
   `IOKit` 电源通知），不能靠「每帧看一眼」。这是本 Phase 交给 Phase 3 最硬的一条。
5. **PDCA-A2 的 0.95 覆盖率阈值仍未解。** Phase 1 实测 `FALSE_POSITIVE_OBSERVED=1`
   （Ghostty pid 1227 / CC Switch pid 1228 的 `coverage=1.000`），且 coverage 已顶在 1.000 上限，
   任何阈值调整都改不了。Phase 3 必须二选一：几何之外的判别信号，或明确接受误暂停方向并写进 `PauseReason`。
6. **PDCA-A7 锁屏跃迁未验证** —— 只验证了能读出状态，跃迁时是否翻转未验证。Phase 3 必须实测。
7. **复核 W-2026-10-03-10**：`AppDelegate.startWallpaper()` 里的 `player.player.play()`
   直连，在 watcher 接入后是否会造成「已 hold 却先 play 一下」。

**Phase 5 内（工具链级）**

8. **引入 `.xcodeproj`**，解开 W-2026-10-03-07（真人点菜单退出）与 W-2026-10-03-08
   （删除 `--quit-after` 脚手架）。D-01 的形状在此兑现：源码是普通 Swift 文件，
   从 SwiftPM 换到 Xcode 工程不改源码，只重排目录；但 XCUITest 必须有工程文件。

**Phase 7 内**

9. **`build.sh` / `test.sh` 的口径在本 Phase 收口。** DMG 的 md5 不可复现这件事
   （四次构建四个值）已如实记录；若 Phase 7 的验收需要「重复执行结果一致」，
   判据应落在 `.app` 内容的 md5 上（本 Phase 实测逐字节一致），而不是 DMG 容器的 md5。

## 复现命令

```bash
swift build
swift test
bash scripts/run-probe.sh order      # → evidence/order.log
bash scripts/run-probe.sh inset      # → evidence/inset.log
bash scripts/run-probe.sh loop       # → evidence/loop.log（跑满 300 秒）
bash scripts/run-probe.sh quit       # → evidence/quit.log
bash build.sh                        # → build/Pic.app + dist/Pic-0.1.0.dmg
bash scripts/run-probe.sh app        # → evidence/app-bundle.log（会 killall Finder）
bash scripts/run-probe.sh refresh    # → evidence/refresh.log（两轮各 16 秒）
bash test.sh                         # 通过 32 失败 0
```
