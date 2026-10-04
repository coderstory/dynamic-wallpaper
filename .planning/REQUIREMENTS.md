# Requirements: Pic — macOS 视频动态壁纸

**Defined:** 2026-10-03
**Core Value:** 桌面一直是活的视频，而且不偷电、不抢性能 —— 全屏 / 锁屏 / 用电池时自动让路。

---

## v1 Requirements

### 来源与媒体库 (SOURCE)

- [ ] **SOURCE-01**: 用户可以选择一个文件夹作为壁纸来源
  - 部分：机制在位（`FolderPicker.swift` 全仓唯一 NSOpenPanel，test.sh 常驻判据 ✅；`FolderRequestPolicy` 纯函数 5 用例；装配链 `requestFolderIfNeeded → persist` 写死在 AppDelegate）；缺——04-VERIFICATION SC1 PRESENT_BEHAVIOR_UNVERIFIED：首启真弹框与「选完当场起播」从未活体观测（锁屏，`rotation-wiring.log:PIC_ROT_APP_LAUNCH informational=1 reason=app-launch-blocked-by-locked-screen`）
- [x] **SOURCE-02**: 扫描时递归进入子目录
  - 证据：04-VERIFICATION Requirements Coverage ✓ SATISFIED；`MediaLibraryTests.testRecursionFindsClipThreeDirectoriesDeep`（专门用例，三层嵌套）；`MediaLibrary.swift` enumerator 递归
- [x] **SOURCE-03**: 只识别 MP4 / MOV / M4V 三种扩展名
  - 证据：04-VERIFICATION ✓ SATISFIED（白名单半句标 VERIFIED）；`testWhitelistAcceptsOnlyMp4MovM4vCaseInsensitively`（B.MOV/d.MP4 收）+ 反证 txt/mkv/avi/webm 全排除
- [x] **SOURCE-04**: 界面显示扫描到的**可用视频数量**；为 0 时显示警告空态
  - 证据：05-VERIFICATION ✓ 已验（SC-2 PASS）；`countRow` 读 `session.playableCount` + `testThreeHideStatesShareOneEmptySkin`（`LibraryState.allCases` 穷举三态一张皮）；活体 `settings-tracer.log:PIC_LIBRARY_STATE=no_playable_videos`
- [x] **SOURCE-05**: 用户可手动触发「重新扫描文件夹」
  - 证据：04-VERIFICATION ✓ SATISFIED；`AppDelegate.rescanFolderNow()` 显式 `invalidateCache`（AppDelegate.swift:479-483）+ `testSecondScanUsesCacheAndInvalidateForcesRescan` 缓存语义单测
- [ ] **SOURCE-06**: 无可用视频、或文件夹被删/移动时，**隐藏壁纸窗口，露出系统原壁纸**
  - 部分：`LibraryAvailability.evaluate` 纯函数穷举 6 用例 + `MediaCoordinator.apply` 执行层 5 用例（含 `testRecoveryFromHiddenToPlayingResumesWithoutRestart` 恢复路径）全绿；缺——04-VERIFICATION SC5 PRESENT_BEHAVIOR_UNVERIFIED：`WallpaperWindowController.hide()` 的真实 orderOut 效果与「露出系统原壁纸」需人看屏幕（探针只覆盖 attach/teardown 可见性）
- [ ] **SOURCE-07**: app 启动时读取已配置的文件夹并开始播放
  - 部分：`SettingsStore.sourceFolder` 持久化（`SettingsStoreTests` 13 条含 7 键冻结）+ 启动序列写死（bootstrap → requestFolderIfNeeded → rescanAndApply → startWallpaper）；缺——04-VERIFICATION SC4 PRESENT_BEHAVIOR_UNVERIFIED：跨进程 UserDefaults 读取 → 起播是运行时状态迁移，无活体证据（锁屏）
- [ ] **SOURCE-08**: 用户切换文件夹后，立即开始播放新文件夹的视频
  - 部分：机制已落地并有单测（`store.sourceFolder = path → rescanAndApply → setItems 重置索引 → router.start`）；用户入口按 04-VERIFICATION 明文 deferred 移交 Phase 5 的「选择…」按钮（复用同一 NSOpenPanel）；缺——换目录后当场起播未活体观测

### 播放 (PLAY)

- [x] **PLAY-01**: 视频作为桌面壁纸播放，**位于桌面图标之后**（`CGWindowLevelForKey(.desktopWindow)`）
  - 证据：02-VERDICT SC1（PASS-with-gap；缺口是人工「桌面图标可点可拖」，非本条）；`02-playback-core/evidence/order.log:SELF_LEVEL=-2147483623` < `ICON_LEVEL=-2147483603`；打包产物 `app-bundle.log:ORDER=ok`、`ALIVE_AFTER_FINDER_RESTART=1`
- [ ] **PLAY-02**: 视频按**裁剪填满**方式适配主屏（保持比例，裁掉超出部分）
  - 部分：已实现 `videoGravity = .resizeAspectFill` + 内缩几何实测（`inset.log:INSET=14/9/14/9`）；缺——02-VERDICT SC2 缺口：窗口每边比屏幕内缩 14pt/9pt 且不透明黑底，「铺满 / 无黑边」从未被目视确认
- [x] **PLAY-03**: 支持**单循环**模式
  - 证据：04-VERIFICATION ✓ SATISFIED（SC3 ✓ VERIFIED）；`RotationControllerTests.testLoopSingle` + `PlayModeTests` 5 条 + `PlaybackRouterTests` 5 条本机复跑全绿（124/124）
- [x] **PLAY-04**: 支持**列表循环**模式
  - 证据：04-VERIFICATION ✓ SATISFIED（SC3 ✓ VERIFIED）；`RotationControllerTests.testLoopList` + `testAdvanceNowLoadsNextInLoopList`
- [x] **PLAY-05**: 支持**列表随机**模式
  - 证据：04-VERIFICATION ✓ SATISFIED（SC3 ✓ VERIFIED）；`testShuffleVisitsEveryItemExactlyOncePerRound`（一轮不重复）+ `testShuffleOrderIsIdenticalForSameSeedAndDiffersForAnotherSeed`（同 seed 可复现）
- [x] **PLAY-06**: 轮换时间可设置，**到点就切**（不等当前视频播完）
  - 证据：04-VERIFICATION ✓ SATISFIED；`testRotationElapsedAdvancesWithoutWaitingForPlayback`（到点回调推进 + 重排程，全程零播放器）+ test.sh 常驻判据「轮换器零播放进度读取」✅ ×4
- [ ] **PLAY-07**: 播放速度可调（0.5×–2×），**保持原音高**
  - 部分：区间与控件已验（`GlowSlider(value:$rateDrag, range: 0.5...2)` + `testRateBoundsAreHalfToDouble`）+ rate 当场生效有 4 条行为级单测（`testPlayingRateAppliesImmediately` 等）；缺——`PlayerController.load` 第 37 行 `audioTimePitchAlgorithm = .spectral` 在位但 `grep -rniE 'pitch|音高|不变调|变调' Tests/ UITests/` 命中 0（零测试覆盖，W-2026-10-03-33 的「单测锁」表述不实），且 0.5×/2× 人声听音从未做（05-VERIFICATION SC-4 PARTIAL）
- [x] **PLAY-08**: 声音可开关
  - 证据：05-VERIFICATION ✓ 已验；`SettingsApplier.applyMuted` → `player.isMuted`，`testVolumeAndMutedApplyWithoutGate` 直接断言 AVPlayer 读数
- [x] **PLAY-09**: 音量可调节
  - 证据：05-VERIFICATION ✓ 已验；`applyVolume` → `player.volume == 0.25` 同条行为级单测（不过 shouldPlay 门）
- [x] **PLAY-10**: **所有设置改动立即生效** —— 不允许「下次换片才生效」或「要重启」
  - 证据：05-VERIFICATION ✓ 已验；六项写入口全部 `store → apply* → persist`（onChanged 直通、onEnded 才落盘）；`testPlayingRateAppliesImmediately` / `.testRateReappliesAfterHoldReleased` / `.testHeldPlayerDoesNotGetRateApplied`

### 暂停策略 (PAUSE)

- [ ] **PAUSE-01**: 任意应用进入全屏时暂停
  - 部分：`FullscreenDetector` 合取判定（`verdict = nonGeometricActive && covering`）已实现且有单测（`FullscreenDetectorTests` 4 条 + `FullscreenGeometryTests` 5 条）；缺——03-VERDICT SC1 PARTIAL：真实全屏跃迁未观测（`FULLSCREEN_TRANSITION=unobservable`），且实测到间歇性误暂停（W-2026-10-03-23）
- [x] **PAUSE-02**: 锁屏时暂停
  - 证据：03-VERDICT SC2 活体证据——`03-system-events/evidence/holds-live.log:PIC_HOLD active=1 reason=screenLocked`、`TICK_PAUSED_LINES=7/7`（采集时真实锁屏态下播放器全程 paused）；`LockWatcher` 装配在位
- [x] **PAUSE-03**: 显示器熄屏时暂停
  - 证据：03-VERDICT SC2 活体证据——`holds-live.log:holds=(screenLocked,displayAsleep)`、`PIC_HOLD_SUMMARY ... reasons=2`（`displayAsleep` 为真实读数）；`display-sleep-signals.log:DISPLAY_START_SYNC_DELIVERED=1 displayAsleep=1`
- [ ] **PAUSE-04**: 系统睡眠时暂停
  - 部分：`DisplayWatcher` 已注册 willSleep / didWake（`display-sleep-signals.log:DISPLAY_SIGNALS_REGISTERED=1 sleep=NSWorkspaceWillSleepNotification`）且有单测；缺——真实睡眠跃迁未观测（`SYSTEM_SLEEP_TRANSITION=unobservable`，被外部 caffeinate 挡住），`systemSleeping` 从未置位
- [ ] **PAUSE-05**: 电池供电时暂停（**开关，默认关闭**）
  - 部分：开关默认关闭已实测（`power-signals.log:BATTERY_HOLD enabled=0`；`SettingsStore.pauseOnBattery` 默认 `false`；`PowerWatcherTests` 6 条）；缺——拔 / 插电源触发暂停与续播未实测（本机全程 AC，需物理动作）
- [x] **PAUSE-06**: 暂停条件解除后**从原处续播**，不从头开始
  - 证据：03-VERDICT SC5 PASS；`HoldArbiterTests.testResumeSeeksToAnchorThenClearsAnchor` / `.testAnchorWrittenOnlyOnEmptyToNonEmptyTransition` / `.testAnchorNotOverwrittenAcrossAllSixReasons`；合成路径 `lock-wiring.log:LOCK_RESUME seeks_to_anchor=1 seeks=42.000`（真实跃迁下的续播仍属 SC2 缺口，见 03-VERDICT）
- [x] **PAUSE-07**: 多个暂停条件叠加时正确仲裁（**veto set，非优先级链**）—— 例如「锁屏中退出全屏」不得误恢复播放
  - 证据：03-VERDICT SC4 PASS；`HoldArbiterTests.testShouldPlayMatchesEmptyHoldsForEverySubset`（运行时从 `allCases` 生成 64 组子集，逐组断言 `holds == subset` 与 `shouldPlay == subset.isEmpty`）+ `.testLockedThenFullscreenExitDoesNotResume`；注入式反向验证 `MUTATED_RC=1`；`swift test` 67 全绿
- [x] **PAUSE-08**: 用户可从菜单栏手动暂停/继续
  - 证据：02-VERDICT SC3（PASS-with-gap）；`MenuBarModelTests.testPerformPauseResumeGoesThroughArbiterNotDirectly` + `HoldArbiterTests.testManualPauseResumesFromAnchorNotFromZero`（`.manualPause` 经 veto 集合生效、从锚点续播）

### 菜单栏 (MENUBAR)

- [x] **MENUBAR-01**: 菜单栏常驻图标
  - 证据：02-VERDICT SC1；`app-bundle.log:APP_ACTIVATION_POLICY=1`（`.accessory`）+ 打包 `LSUIElement=true`；Phase 1 `spike/out/menubar.log:MENUBAR_VERDICT=ok`（状态项路线 + 阳性对照）
- [ ] **MENUBAR-02**: 关闭设置窗口只隐藏窗口，**进程不退出**
  - 部分：代码在位（`PicApp.swift` `.onDisappear { appDelegate.hideSettingsAndRestorePolicy() }` → `AppDelegate.swift:369` `setActivationPolicy(.accessory)`；全仓 `NSApp.terminate` 只在 `terminateApp()` 一处，无 `terminateAfterLastWindowClosed`）；缺——05-VERIFICATION 真相 #8 PRESENT_BEHAVIOR_UNVERIFIED：运行期状态跃迁零测试触达，`SettingsWindowUITests.testClosingWindowKeepsProcessAlive` 因锁屏从未跑过（W-2026-10-03-34）
- [x] **MENUBAR-03**: 菜单项 —— 暂停/继续
  - 证据：02-VERDICT SC3；`MenuBarModelTests.testPerformPauseResumeGoesThroughArbiterNotDirectly`（点击经仲裁器进入 `.manualPause` 并推送决策）+ `.testMenuItemIDsAreExactlyTheThreeFixedItems`
- [x] **MENUBAR-04**: 菜单项 —— 立即下一个
  - 证据：04-VERIFICATION ✓ SATISFIED；`MenuItemID` 五项 allCases 遍历 + `testPerformNextVideoCallsOnlyItsInjectedClosure` + 装配链 `MenuContentView → MenuBarModel.perform → AppDelegate.nextVideoNow`（SC3 ✓ VERIFIED）
- [x] **MENUBAR-05**: 菜单项 —— 重新扫描文件夹
  - 证据：04-VERIFICATION ✓ SATISFIED；菜单项 + 装配链 `rescanFolderNow → invalidateCache → rescanAndApply`（SC3 ✓ VERIFIED，`test.sh` 常驻判据）
- [x] **MENUBAR-06**: 菜单项 —— 打开设置
  - 证据：05-VERIFICATION ✓ 已验（真相 #2 ✓ VERIFIED）；`MenuItemID.openSettings` 标签逐字「打开设置」+ `MenuShortcut(",", modifiers:.command)` + `MenuBarModelTests.testLabelsHaveExactlyFiveEntriesInEveryState` 锁 5 项与顺序；局限已登记：XCUITest 不发真实 ⌘,，按键响应面只有代码证据
- [x] **MENUBAR-07**: 菜单项 —— 退出
  - 证据：02-VERDICT SC3；`MenuBarModelTests.testPerformQuitCallsInjectedClosureOnlyOnce`；`quit.log:QUIT_HOOK_SEEN=1`、`QUIT_EXITED=1`（进程真实退出）
- [x] **MENUBAR-08**: 菜单**不显示当前播放的文件名**
  - 证据：02-VERDICT SC4 PASS；`MenuBarModelTests.testLabelsNeverContainAnyMediaFileName`（哨兵 `clip-sentinel.mp4` 计数 0）+ `.testLabelsHaveExactlyThreeEntriesInEveryState`；`test.sh` 两条源码判据（`Button(` 行数 = `ForEach(MenuItemID.allCases` 行数；菜单结构体内取文件名 API 计数 = 0）

### 系统集成 (SYS)

- [ ] **SYS-01**: 支持开机自启（**需用户手动设置一次**）—— ⚠️ 未签名 app 上 `SMAppService` 行为待实测，退路是 `LaunchAgent` plist
  - 部分：机制面已实测（`sys01.log:SYS01_ACTIVE_ROUTE=smappservice` / `SYS01_SMAPP_STATUS=enabled` / `SYS01_ROUTE=smappservice`，路线 A 成立；退路 B 的 plist 生成/删除/A→B 落回有单测 + 两次变异反向验证）；缺——`SYS01_REBOOT_CONFIRMED=pending_human`：装 DMG 版并重启后自启是否真在位从未验证（07-VERDICT SC3 PARTIAL / PENDING-HUMAN）
- [ ] **SYS-02**: 多 Space / 台前调度下**跟随系统默认行为**，不做差异化处理
  - 部分：已证明「零 Space 级特殊处理」（`test.sh` 剥注释后 `activeSpaceDidChangeNotification` 计数 = 0；`collectionBehavior` 四项在位）；缺——02-VERDICT SC5 PARTIAL：真实切 Space / 台前调度下「壁纸不消失」未验证（本机单屏且会话锁定）
- [ ] **SYS-03**: 首次启动直接弹出文件夹选择框
  - 部分：`FolderRequestPolicy` 纯函数 5 用例 + 首启接线（`bootstrapAfterWiring → requestFolderIfNeeded`）已核；缺——与 SOURCE-01 同一缺口（04-VERIFICATION SC1）：首启真弹框未活体观测，`rotation-wiring.log` 自标 informational

### 转码 (TRANS)

- [x] **TRANS-01**: 检测系统 PATH 中的 `ffmpeg`
  - 证据：06-VERDICT SC#1 自动面 PASS；`ExternalToolLocatorTests` 6 条三态决策表（`testAvailableWhenHomebrewPathExists` / `testAvailableWhenWhichSucceeds` / `testUnavailableWhenNothingFound` / `testGuiMinimalPathStillFindsHomebrewInstall`）+ `FFmpegAvailabilityTests` 6 条；A5「GUI app 拿 launchd 最小 PATH，which 会漏」已证；活体 `status-card.log:FFMPEG_SELF_CONSISTENT=ok available=1 label=可用`
- [ ] **TRANS-02**: `ffmpeg` 缺失时**转码入口置灰**并提示安装途径；其余功能不受影响
  - 部分：结构判据全过（06-04 D2/D3：三途径标记 `pathway:brew` / `pathway:static` / `pathway:source` 各 1 处、xattr 清隔离 / brew install ffmpeg / evermeet / --build-from-source 文案在位、入口 `opacity 0.34` 置灰但可点、`refreshFFmpegAvailability=3`）；缺——06-VERDICT SC#1 行为面 + 人工清单②：挪走 ffmpeg 后看三途径弹层从未做过（须复原并重查）；另 05 遗留的 `SettingsControlsUITests.swift:157` 断言 `isEnabled == false` 已与产品代码矛盾（05-VERIFICATION Advisory #1，解锁重跑前必修）
- [ ] **TRANS-03**: 把 MKV / AVI / WebM 等非原生格式转成 MP4（H.264），**画质视觉无损**
  - 部分：参数侧已锁死（`TranscodeCommandTests` argv 逐 token + 基线 CRF 18 / preset medium + `PIC_TRC_ARGV_TOKENS=28`）；缺——06-VERDICT SC#3 **PARTIAL**：画质侧 BLOCKED(manual)，`scripts/transcode-bench.sh` 的 SSIM/VMAF 实测从未运行（零 ffmpeg 红线），阈值 SSIM≥0.98 / VMAF≥95 是行业经验值 `[ASSUMED]` 非本机实测
- [x] **TRANS-04**: 转码产物输出到**用户选择的壁纸目录内**，原视频保留不删
  - 证据：06-VERDICT SC#4 **PASS**；`TranscodeOutputNamingTests` 6 条（路径/怪名/.tmp 后缀/幂等跳过三态）+ `testSuccessfulJobRenamesTmpToMp4AndKeepsSource`；活体 `transcode-tracer.log:PIC_TRC_SOURCE_INTACT=1 PIC_TRC_TMP_GONE=1 PIC_TRC_PRODUCT_EXISTS=1`
- [x] **TRANS-05**: 转码产物**不会被再次扫描**成待转码输入（防死循环）
  - 证据：06-VERDICT SC#5 **PASS**（数据侧 + 装配侧）；`TranscodeCandidateFilterTests` 6 条（大小写不敏感全等排除，含 `converted-lower` 照收的反证）+ 变异 `MUT-P6-BACKFLOW`（全等→子串）断言红 + 恢复逐字节一致；`transcode-tracer.log:PIC_TRC_REFILTER_CANDIDATES=0 PIC_TRC_SECOND_PASS_SKIPPED=1 PIC_TRC_RUNNER_CALLS_TOTAL=1`
- [ ] **TRANS-06**: 转码窗口显示任务队列、进度、以及将要执行的实际命令（可审计）
  - 部分：结构与纯逻辑已过（转码窗四要素结构判据 commandDisplay=1 / Converted=1 / 保留=1 / 待转码=5 + `TranscodeQueueTests` 6 条 + `ProgressParserTests` 5 条 + `TranscodeMainActorFreezeTests` 主 actor 冻结回归门，实测 run 期间进度 130~170）；缺——06-VERDICT 人工清单①「开转码窗目视」从未做过：结构有断言、屏上像素无

### 设置界面 (UI)

- [x] **UI-01**: 设置窗口按 `.planning/UI-SPEC.md` 实现（B1 深海皮肤 + L4 双列布局）
  - 证据：05-VERIFICATION 真相 #1 ✓ VERIFIED（SC-1 前半）；活体探针 `settings-tracer.log:PIC_SETTINGS_WINDOW width=780 minWidth=680`（产品视图 `emitWindowGeometry()` 读 `NSApp.windows`，非 mock）+ `testWindowConstantsMatchContract` 锁 780/680 + B1 令牌 `pBg #0A1826` / `pWarn #F5B544` 与 UI-SPEC §3 逐字一致 + `grep NavigationSplitView|NSSplitView|sidebar Sources/PicApp/` 命中 0
- [x] **UI-02**: 空态显示警告色并给出明确文案「壁纸已隐藏，桌面显示的是系统原壁纸」
  - 证据：05-VERIFICATION ✓ 已验（SC-2 **PASS**）；`SettingsPresentation.emptyStateBody` 全仓唯一一份，`testEmptyStateBodyMatchesSpecVerbatim` 逐字相等 + `testEmptyStateBodyIsSingleSourced`（剥注释后计数 == 1）双锁 + `testThreeHideStatesShareOneEmptySkin` 穷举三态一张皮；`SettingsView.swift` 空态分支 `Tile(symbol:"exclamationmark", warn:true)` + `foregroundStyle(isEmpty ? Color.pWarn : Color.pAccent)`
- [x] **UI-03**: 两条置灰联动 —— 单循环时轮换时间置灰；声音关闭时音量置灰
  - 证据：05-VERIFICATION ✓ 已验（SC-3 **PASS** —— 是真禁用不是只调透明度）；纯函数 `rotationControlsEnabled(playMode:) = playMode != .loopSingle` 与 `volumeControlsEnabled(isMuted:) = !isMuted` 各有正反两向单测；`GlowStepper` 走原生 `Button`；`GlowSlider` 自绘 `DragGesture` 读 `@Environment(\.isEnabled)`，`onChanged` 与 `onEnded` **两处**都 `guard isEnabled else { return }`
- [x] **UI-04**: 设置窗显示**运行状态** —— 当前是否暂停、**暂停原因**（全屏/锁屏/熄屏/睡眠/电池）、ffmpeg 可用性。veto set 仲裁下用户需知道卡在哪个原因上
  - 证据：05-VERIFICATION ✓ 已验（SC-5 **PASS**）；`testHoldReasonLabelsCoverAllSixCasesVerbatim` 6 条文案逐字锁且两两不同 + `testJoinedReasonsSortsByOrderBeforeJoining`（`screenLocked+manualPause` → 「手动暂停、屏幕已锁定」）+ ffmpeg 两值穷举且 `Process(`/`NSTask` 剥注释后计数 0/0；活体 `status-card.log:FFMPEG_SELF_CONSISTENT=ok`

### 打包分发 (PACK)

- [ ] **PACK-01**: 打包为 **DMG**（内含 `.app`）—— **不签名、不公证**。用本机已装的 `create-dmg`
  - 部分：DMG 确实产出且可校验（`packaging.log:PACK_HDIUTIL_VERIFY=ok` / `PACK_MOUNT_BINARY_MD5_MATCH=1` / `PACK_DMG_APP_COUNT=1`；两遍构建二进制 md5 逐字相同 `a42bfb65…`、plist md5 相同 `23bfbbf4…`、`PACK_REPEAT_CONSISTENT=1`；不签名不公证 `Signature=adhoc` / `TeamIdentifier=not set`）；缺——需求原文的「**用本机已装的 `create-dmg`**」这一半在本机**从未成立**：三次构建全部走 hdiutil 降级（`PACK_DMG_ROUTE_A/B=hdiutil_fallback`，AppleEvent -1743），窗口布局 / 图标位置 / Applications 拖入快捷方式零证据（07-VERDICT SC1 PASS-with-gap）
- [x] **PACK-02**: 不做 App Store 上架（允许使用非公开 API）
  - 证据：07-VERDICT「打包形态面（PACK-02）」跑过；`packaging.log:PACK_SPCTL_RC=3`（预期拒绝）/ `PACK_NO_APPSTORE_ARTIFACTS=1` / `PACK_PKG_COUNT=0` / `PACK_APP_SANDBOX_ENTITLEMENTS=0`；`Signature=adhoc` / `TeamIdentifier=not set`（允许非公开 API，未上架）
- [x] **PACK-03**: 提供 `build.sh` —— 一条命令完成编译 + 打包 `.app` + 生成 DMG
  - 证据：07-VERDICT SC1「交付构建」行；`bash build.sh` 实跑产出 `build/Pic.app` + `build/PicProbe.app` + `dist/Pic-0.1.0.dmg`，一条命令零手工；剥离判据成对成立 `PROBE_SYMBOLS_PIC=0` / `PROBE_SYMBOLS_PROBE=195`（正控非零）
- [x] **PACK-04**: 提供 `test.sh` —— 一条命令跑完所有可自动化的验证
  - 证据：07-VERDICT SC2 **PASS**；`bash test.sh` 实跑 通过 102 / 失败 0 / 跳过 1，退出码 0（跳过项 = 7 天长跑，人工周期）；`probe-strip.log:PROBE_STRIP_DELIVERY_SYMBOLS=0`

### 视觉资产 (ASSET)

- [x] **ASSET-01**: 设计 **app 图标** —— macOS 风格圆角方图标，需产出 1024×1024 源图 + `AppIcon.appiconset` 全套尺寸（16/32/128/256/512 及 @2x）
  - 证据：07-01-SUMMARY D4 ✓ pass；`find build/Pic.iconset -name 'icon_*.png'` → **10**（16/32/128/256/512 及 @2x 全套）→ `iconutil` → `Pic.icns` 1,651,170 字节；`plutil -extract CFBundleIconFile raw` 两侧均输出 `Pic`（构建产物与真相源一致）+ test.sh 常驻门「app 图标 CFBundleIconFile=Pic 且 Pic.icns 非空」✅
- [ ] **ASSET-02**: 设计 **菜单栏（托盘）图标** —— 必须是 **template image**（纯黑 + alpha，由系统自动适配深浅色菜单栏），16×16pt / 32×32@2x。要在 16px 下依然可辨认
  - 部分：template image 面已由活体读数证实（`Bundle.image(forResource: 'menubar-v1Template')` → `ICON_LOADED=true TEMPLATE=true REPS=3 SIZE=16×16pt`，即 16×16pt / 32×32@2x 三档）+ test.sh 常驻门「菜单栏图标用 v1（menubar-v1 在位、v2 零残留）」✅；缺——需求原文的「要在 **16px 下依然可辨认**」无任何读数（屏上像素未目视）
- [ ] **ASSET-03**: 两套图标视觉上同源 —— 一眼能看出是同一个 app
  - 部分：自动侧只证了「两套图标出自同一 `tools/make-icons.swift` + 同一手绘语言 + v1 构图一致」；缺——07-VERDICT 明确 **PENDING-HUMAN**：唯一真判据是 UAT-SOAK 的「app 图标与菜单栏图标**并排**肉眼比对」记录，该记录不存在；VERDICT 原文「同一生成器 ≠ 视觉同源」（`drawAppIcon` 与 `drawMenuBar` 是两个函数）

### 测试覆盖 (TEST)

用户要求：**单测和 UI 测试覆盖全部功能。** 但「全部功能」里有一半在技术上无法自动化，必须分清。

#### 可自动化 —— 单元测试

- [x] **TEST-01**: 暂停仲裁状态机 **全组合覆盖** —— 6 个输入（全屏 / 锁屏 / 熄屏 / 睡眠 / 电池 / 用户手动）× 开闭 = **64 种组合**逐一断言。这是全项目最核心也最易错的逻辑（PAUSE-07）
  - 证据：03-VERDICT SC4 PASS；`Executed 67 tests, with 0 failures`；`HoldArbiterTests.testAllCasesCountIsSixAndPowersetIsSixtyFour` + `.testShouldPlayMatchesEmptyHoldsForEverySubset`（运行时从 `allCases` 生成 64 组，逐组断言 `holds == subset` 与 `shouldPlay == subset.isEmpty`）；反向注入验证 `MUTATED_RC=1`
- [ ] **TEST-02**: 媒体库扫描 —— 递归子目录、格式白名单过滤、**转码产物排除**（TRANS-05 的防死循环）、空目录、文件夹不存在、无权限
  - 部分：递归子目录 / 白名单 / **转码产物排除** / 文件夹不存在 / entryCap / 缓存均有用例（`MediaLibraryTests` 9 条 + `TranscodeCandidateFilterTests` 6 条 + `LibraryAvailabilityTests` 6 条）；缺——04-VERIFICATION Warning：需求点名的「**空目录扫描**」与「**无权限**（errorHandler continue）」两条路径无用例
- [x] **TEST-03**: 轮换逻辑 —— 单循环 / 列表循环 / 列表随机三种模式；到点就切（PLAY-06）；随机不重复直到走完一轮
  - 证据：04-VERIFICATION ✓ SATISFIED；`RotationControllerTests` 7 条覆盖三模式 + 一轮不重复 + 同 seed 可复现，`testRotationElapsedAdvancesWithoutWaitingForPlayback` 锁到点就切，`PlayModeTests` 5 条 + `PlaybackRouterTests` 5 条
- [x] **TEST-04**: 设置持久化 —— 存取、默认值、**改动立即生效**（PLAY-10 的断言点）
  - 证据：05-VERIFICATION ✓ 已验；活体三轮 `settings-restart.log:ROUND1_SEEDED=ok ROUND2_IDEMPOTENT=ok ROUND3_DEFAULTS=ok`（锚点 `PIC_SETTINGS_BOOT`，值全部来自 store）+ `SettingsStoreTests` 11 条含 `testPersistWritesBackToDefaults`；改动立即生效的断言点由 PLAY-10 的 4 条行为级单测承担
- [x] **TEST-05**: ffmpeg 检测与降级 —— PATH 有 / 没有 / 不可执行三种情况的界面状态
  - 证据：三种情况均有注入式单测：PATH 有（`testAvailableWhenHomebrewPathExists` / `testAvailableWhenIntelBrewPathExists` / `testAvailableWhenWhichSucceeds`）、没有（`testUnavailableWhenNothingFound`）、不可执行（`testNotExecutableProbePathIsSkippedNotFatal`，跳过不判死）；界面侧 `FFmpegAvailability.label` 两值穷举 + 活体 `status-card.log:FFMPEG_SELF_CONSISTENT=ok available=1 label=可用`
- [x] **TEST-06**: 转码参数构造 —— 给定输入文件，断言生成的 `ffmpeg` 命令行参数正确
  - 证据：`TranscodeCommandTests` 4 条：`testArgumentsMatchExpectedTokenSequenceExactly`（逐 token）+ `testDisplayStringStartsWithNiceAndJoinsSameTokens` + `testBaselineConstantsAreCrfEighteenPresetMedium` + `testAudioMapIsOptionalAndSubtitleDataStreamsDropped`；`transcode-tracer.log:PIC_TRC_ARGV_TOKENS=28`（06-VERDICT SC#3 参数侧 PASS）

#### 可自动化 —— UI 测试（XCUITest）

- [ ] **TEST-07**: 设置窗全部控件可交互 —— 分段控件、步进器、滑杆、开关、按钮
  - 部分：14 个 `accessibilityIdentifier` 全在位（源码层 ✓：8 interactive + 1 conditional + 4 display + transcode-open）；缺——hittable / disabled 断言只在**未跑的** XCUITest 里（`uitest.log:SCREEN_LOCKED=1 → UITEST_STATUS=blocked reason=screen_locked`，W-2026-10-03-34），且其中 1 条断言已与 Phase 6 后的产品代码矛盾（05-VERIFICATION Advisory #1）
- [ ] **TEST-08**: 两条置灰联动 —— 选「单循环」后轮换时间不可点；关「声音」后音量不可点（UI-03）
  - 部分：联动机制是真禁用已验（两条纯函数正反单测 + `GlowSlider` 的 `guard isEnabled` onChanged/onEnded 两处 + `GlowStepper` 走原生 Button）；缺——需求要的「以**交互不生效**为准」的证据行断言只在未跑的 XCUITest 里
- [ ] **TEST-09**: 空态 —— 扫描到 0 个视频时显示警告色与指定文案（UI-02）
  - 部分：文案面已锁死（`testEmptyStateBodyMatchesSpecVerbatim` 逐字相等 + `testEmptyStateBodyIsSingleSourced` 全仓唯一）+ 三态一张皮穷举单测 + 活体 `PIC_LIBRARY_STATE=no_playable_videos`；缺——XCUITest 空目录 `staticText` 逐字相等断言未跑，且产品 SettingsView 从未被任何自动路径渲染（test.sh 渲染的是 spike），屏上效果未目视
- [ ] **TEST-10**: 菜单栏 —— 5 个菜单项存在且可点（MENUBAR-03~07）
  - 部分：`MenuBarModelTests` 锁 5 项文案/顺序 + 哨兵 `clip-sentinel.mp4` 计数 0（模型层 ✓，与 MENUBAR-08 同款判据）；缺——需求要的「5 个菜单项**存在且可点**」的 hittable 断言未跑（W-2026-10-03-31 已登记）

#### ⚠️ 无法自动化 —— 必须人工 / 真机验证

**这部分不能算进自动化覆盖率，也不应该假装能测。** 它们是系统级行为，XCTest 碰不到：

| 项 | 为什么测不了 |
|---|---|
| 桌面图标之后的渲染（PLAY-01） | 需要真实 WindowServer 与 Finder 图层，XCUITest 只能看到自己的 app |
| 桌面图标仍可点、可拖、Finder 刷新后仍在 | 同上，且需要人在桌面上实际操作 |
| 全屏检测准确性（PAUSE-01） | 需要真实的全屏应用（Chrome / 视频播放器），且**刘海屏阈值需人工标定**（实测 Chrome 全屏只覆盖 87.343%） |
| 锁屏 / 熄屏 / 睡眠暂停（PAUSE-02~04） | 需要真实系统电源事件 |
| 电池供电暂停（PAUSE-05） | 需要拔电源 |
| 耗电与发烫 | 需要 `powermetrics` 长时间实测 |
| 多 Space / 台前调度（SYS-02) | 需要真实 Space 切换 |
| 开机自启（SYS-01） | 需要重启；且**未签名 app 的 `SMAppService` 行为本身就待验证** |

→ 这些项的验收方式写进 `.planning/` 的 UAT 清单，由人工执行，而不是塞进 `test.sh`。

---

## v2 Requirements

### 显示

- **DISP-01**: 多显示器全部铺满
- **DISP-02**: 每块屏幕可独立配置文件夹与播放参数

### 媒体库

- **LIB-01**: 自动监听文件夹内容变化，无需手动重新扫描
- **LIB-02**: 文件夹失效后的自动恢复（重新挂载、iCloud 下载完成等）

### 界面

- **UI2-01**: 浅色主题变体
- **UI2-02**: 滑杆自绘（完全贴合设计，摆脱系统外观）

### 转码

- **TR2-01**: 转码队列持久化与断点续传
- **TR2-02**: 批量转码的并发控制

---

## Out of Scope

| 功能 | 原因 |
|---|---|
| 视频文件列表 / 缩略图浏览 | 用户明确不要。转码窗口的任务队列是唯一例外，且它不是浏览器 |
| AVI / MKV / WebM 直接播放 | 走转码路线；原生只播硬解友好的三种格式 |
| 网页壁纸 / 摄像头壁纸 | 需要 `WKWebView` 或摄像头权限，与「不偷电」的核心价值冲突 |
| 壁纸库 / 账号 / 云同步 | 引入账号体系与订阅，与自用工具的定位冲突 |
| 锁屏视频壁纸 | 与「锁屏时暂停」的核心需求**直接互斥** |
| App Store 上架 | 需要沙盒，会砍掉桌面层级方案 |
| 代码签名 / 公证 | 用户明确不需要 —— 但 **DMG 打包要做** |
| 视频内容本身（播放列表 UI、播放历史、收藏） | 这是壁纸工具，不是播放器 |
| 多显示器每屏独立配置 | v1 只做主屏，见 v2 |

---

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| SOURCE-01 | Phase 4 | Partial — 机制 + 纯函数单测在位，缺首启弹框活体观测（04-VERIFICATION SC1） |
| SOURCE-02 | Phase 4 | Done |
| SOURCE-03 | Phase 4 | Done |
| SOURCE-04 | Phase 5 | Done |
| SOURCE-05 | Phase 4 | Done |
| SOURCE-06 | Phase 4 | Partial — 决策纯函数 6 用例 + 协调器 5 用例，缺真实窗口 hide() 与「露出系统原壁纸」目视（04-VERIFICATION SC5） |
| SOURCE-07 | Phase 4 | Partial — 持久化 + 启动序列已证，缺跨进程重启后起播活体证据（04-VERIFICATION SC4） |
| SOURCE-08 | Phase 4 | Partial — 机制就位并有单测，入口 deferred 至 Phase 5「选择…」按钮，换目录起播未活体观测 |
| PLAY-01 | Phase 2 | Done |
| PLAY-02 | Phase 2 | Partial — 裁剪填满 + 内缩几何已实测，缺「铺满 / 无黑边」目视确认（02-VERDICT SC2） |
| PLAY-03 | Phase 4 | Done |
| PLAY-04 | Phase 4 | Done |
| PLAY-05 | Phase 4 | Done |
| PLAY-06 | Phase 4 | Done |
| PLAY-07 | Phase 5 | Partial — 区间与当场生效已验，`.spectral` 零测试覆盖 + 人声听音从未做（05-VERIFICATION SC-4，W-33） |
| PLAY-08 | Phase 5 | Done |
| PLAY-09 | Phase 5 | Done |
| PLAY-10 | Phase 5 | Done |
| PAUSE-01 | Phase 3 | Partial — 合取判定 + 单测已实现，缺真实全屏跃迁观测，存在间歇误暂停（03-VERDICT SC1，W-2026-10-03-23） |
| PAUSE-02 | Phase 3 | Done |
| PAUSE-03 | Phase 3 | Done |
| PAUSE-04 | Phase 3 | Partial — willSleep / didWake 已注册 + 单测，缺真实睡眠跃迁（systemSleeping 未置位） |
| PAUSE-05 | Phase 3 | Partial — 开关默认关闭已实测，缺拔 / 插电源触发暂停与续播（本机全程 AC） |
| PAUSE-06 | Phase 3 | Done |
| PAUSE-07 | Phase 3 | Done |
| PAUSE-08 | Phase 2 | Done |
| MENUBAR-01 | Phase 2 | Done |
| MENUBAR-02 | Phase 5 | Partial — `.onDisappear` → `.accessory` 代码在位，进程不退出是运行期跃迁零测试触达（05-VERIFICATION 真相 #8，W-34） |
| MENUBAR-03 | Phase 2 | Done |
| MENUBAR-04 | Phase 4 | Done |
| MENUBAR-05 | Phase 4 | Done |
| MENUBAR-06 | Phase 5 | Done |
| MENUBAR-07 | Phase 2 | Done |
| MENUBAR-08 | Phase 2 | Done |
| SYS-01 | Phase 7 | Partial — 机制面实测 `ACTIVE_ROUTE=smappservice`，重启后持久化 pending_human（07-VERDICT SC3） |
| SYS-02 | Phase 2 | Partial — 零 Space 特殊处理已证，缺真实切 Space / 台前调度验证（02-VERDICT SC5） |
| SYS-03 | Phase 4 | Partial — `FolderRequestPolicy` 5 用例 + 首启接线已核，缺首启真弹框活体观测（同 SC1） |
| TRANS-01 | Phase 6 | Done |
| TRANS-02 | Phase 6 | Partial — 三途径弹层结构判据全过，入口置灰的活体行为面未做（06-VERDICT 人工清单②） |
| TRANS-03 | Phase 6 | Partial — 参数侧 PASS，画质侧 BLOCKED(manual)：SSIM/VMAF 从未实测（06-VERDICT SC#3） |
| TRANS-04 | Phase 6 | Done |
| TRANS-05 | Phase 6 | Done |
| TRANS-06 | Phase 6 | Partial — 队列/进度/命令结构与纯逻辑已过，转码窗活体目视未做（06-VERDICT 人工清单①） |
| UI-01 | Phase 5 | Done |
| UI-02 | Phase 5 | Done |
| UI-03 | Phase 5 | Done |
| UI-04 | Phase 5 | Done |
| PACK-01 | Phase 7 | Partial — DMG 产出且可校验，`create-dmg` 主路三次构建全部 hdiutil 降级，布局未验（07-VERDICT SC1） |
| PACK-02 | Phase 7 | Done |
| PACK-03 | Phase 7 | Done |
| PACK-04 | Phase 7 | Done |
| ASSET-01 | Phase 7 | Done |
| ASSET-02 | Phase 7 | Partial — template image + 三档尺寸活体读数在位，16px 可辨认无读数 |
| ASSET-03 | Phase 7 | Partial — 只证「同一生成器」；并排肉眼比对记录不存在（07-VERDICT PENDING-HUMAN） |
| TEST-01 | Phase 3 | Done |
| TEST-02 | Phase 4 | Partial — 递归/白名单/回流排除/目录不存在有例，空目录与无权限两子项缺测（04-VERIFICATION Warning） |
| TEST-03 | Phase 4 | Done |
| TEST-04 | Phase 5 | Done |
| TEST-05 | Phase 6 | Done |
| TEST-06 | Phase 6 | Done |
| TEST-07 | Phase 5 | Partial — 14 identifier 源码层在位，hittable/disabled 断言只在未跑的 XCUITest（W-34） |
| TEST-08 | Phase 5 | Partial — 真禁用机制已验，「交互不生效」证据行断言未跑（W-34） |
| TEST-09 | Phase 5 | Partial — 文案逐字单测已锁，空目录 XCUITest 断言未跑 + 屏上未目视（W-34） |
| TEST-10 | Phase 5 | Partial — 5 项文案/顺序已锁，hittable 断言未跑（W-31） |

**Coverage:**
- v1 requirements: 64 total
- Mapped to phases: 64
- Unmapped: 0
- Phase 1（桌面层级门禁 spike）不交付需求 —— 它是 throwaway 验证阶段，消解 PLAY-01 / PLAY-02 / PAUSE-01 / PAUSE-02 / SYS-02 的可行性风险

---

## 需求来源

需求不是凭空列的，每条都有出处：

| 来源 | 覆盖的 REQ |
|---|---|
| 用户原始描述（首条消息 + 后续补充） | SOURCE-01~08, PLAY-01,03~10, PAUSE-01~06, MENUBAR-01~08, SYS-01,03, TRANS-01~04 |
| 用户问答中确认 | PLAY-02（裁剪填满）, PLAY-06（到点就切）, PLAY-07（保持原音高）, PAUSE-05（开关默认关）, SYS-02（跟随系统）, TRANS-03（视觉无损） |
| 调研发现（ARCHITECTURE / PITFALLS） | PLAY-01（层级常量）, PAUSE-07（veto set 仲裁）, TRANS-05（防扫描死循环） |
| UI-SPEC 定稿 | UI-01~03, SOURCE-04（视频计数） |
| 用户补充（2026-10-03）—— 要 DMG、要两条脚本 | PACK-01（由「.app」改为「DMG」）, PACK-03（build.sh）, PACK-04（test.sh） |

---

*Requirements defined: 2026-10-03*
*Last updated: 2026-10-04 after phase 4–7 closed (Traceability synced to VERDICT/VERIFICATION, 64/64 mapped)*
