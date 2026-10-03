import AppKit
import AVFoundation
import PicCore

/// 唯一装配点（D-10）。
///
/// Phase 2 只接了三根线；Phase 3 在这里接齐四个 Watcher —— 本文件是全仓**唯一**
/// 把系统信号变成 `HoldReason` 的地方（D-09 单向流：`Watcher → HoldArbiter → PlayerController`）。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = SettingsStore(
        defaults: .standard,
        seed: SettingsStore.Seed()
    )
    let player = PlayerController()
    let arbiter = HoldArbiter()
    let wallpaper = WallpaperWindowController()
    /// Phase 5 tracer：设置「当场生效」的唯一落点（装配在 wiring 旁，D-10）。
    /// lazy：构造参数要引用上面的持有者，属性默认值里引用不了 self；访问都在主线程。
    lazy var settingsApplier = SettingsApplier(store: store, player: player, arbiter: arbiter)
    // ---- Phase 3 的四个常驻信号源 ----
    // ⚠️ 四个都必须**强持有**。谁创建谁 `stop()`：observer / IOKit run loop source /
    // 显示器重配置回调一旦没人摘就永久泄漏（T-03-03 / T-03-10 / T-03-15）。
    // 只在闭包里临时捕获不构成持有 —— 那样 `stop()` 无人可调。
    let lockWatcher = LockWatcher(names: lockSignalNames())
    let fullscreenDetector = FullscreenDetector()
    let displayWatcher = DisplayWatcher()
    let powerWatcher = PowerWatcher()
    // ---- Phase 4 的媒体库与轮换（Plan 04-01/02/03 交付，04-04 接线）----
    // ⚠️ `library` 与 `rotation` 都必须**强持有**：前者持扫描缓存，后者持
    // `onAdvance` 闭包与调度器（Timer 没人持有就被释放，T-03-03 同款）。
    let library = MediaLibrary()
    /// 面板 seam（04-04 T2）：全仓唯一碰 NSOpenPanel 的地方注入进来的句柄。
    let picker: any FolderPicker = NSOpenPanelFolderPicker()
    let rotation = RotationController(
        scheduler: SystemRotationScheduler(),
        random: SeededRandomSource(seed: UInt64(bitPattern: Int64(Date().timeIntervalSince1970)))
    )
    /// 扫描结果 → 窗口/播放器动作的唯一落点（04-03）。lazy：构造参数要包住上面
    /// 两个持有者，属性默认值里引用不了 self；每次访问都在主线程，无竞态。
    lazy var coordinator = MediaCoordinator(
        presenting: WallpaperPresenter(controller: wallpaper),
        stopping: PlaybackStopper(player: player)
    )
    /// 设置窗的会话态读数（计数 / 空态 / 扫描时间）。**不进 store**：
    /// 七键冻结，这些都不是用户设过的偏好。
    let sessionState = SettingsSessionState()
    // ---- Phase 6 的 ffmpeg 判定与转码队列（Plan 06-04 T2 交付）----
    /// 单一真相源（D-17 收编）：设置窗状态卡、维护行置灰态、转码窗徽章读的都是它。
    /// lazy：构造参数要引用上面的持有者，属性默认值里引用不了 self。
    private lazy var ffmpegLocator: ExternalToolLocator =
        ExternalToolLocator(which: ProcessWhichProbe(), fileSystem: FileManagerExecutableProbe())
    /// 转码窗徽章复用**同一个** locator —— 入口置灰与徽章不许出现两套判定（D-17）。
    var transcodeLocator: ExternalToolLocator { ffmpegLocator }
    /// 最近一次的判定结论。`refreshFFmpegAvailability()` 的唯一写入口。
    private(set) var ffmpegAvailability: FFmpegToolStatus = .unavailable
    /// 转码队列的持有者 —— 窗口与 06-05 的 `onBatchFinished` 接的是同一个实例。
    lazy var transcodeQueue: TranscodeQueue = {
        TranscodeQueue(
            runner: ProcessTranscodeRunner(),
            naming: TranscodeOutputNaming(
                root: store.resolvedFolderURL() ?? URL(fileURLWithPath: NSTemporaryDirectory())),
            availability: { [weak self] in self?.ffmpegAvailability ?? .unavailable },
            freeSpaceProvider: { url in
                (try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
                    .volumeAvailableCapacityForImportantUsage
            })
    }()
    /// 04-05 T2：轮换 → 装载的路由器。强持有（它持 `rotation.onAdvance` 闭包）；
    /// lazy：init 引用 self 的其它属性。
    private lazy var router = PlaybackRouter(
        rotation: rotation,
        loader: PlayerLoadingAdapter(player: player, arbiter: arbiter)
    )

    private var ticker: Timer?
    /// D-05：0.5 秒 `Timer` 已删。`PIC_HOLD` 改由对 `arbiter.decision` 的观察驱动，
    /// 观察者由 `armHoldObservation()` 一次性注册并在 `onChange` 里重新 arm。
    private var tickSeq = 0
#if !PIC_NO_PROBE
    private var loopProbe: LoopProbe?
#endif
    /// `observeHold()` 在本进程内被调用的次数 —— 打在**去重门之前**。
    /// D-05 唯一的机器判据：12 秒零决策变化的窗口里它必须恒为 1；
    /// 0.5 秒轮询会涨到约 24（见 `observeHold()` 的注释）。
    private var holdObserverTicks = 0
    /// Plan 02-04 T2：显示刷新驱动的**测量器**，不是渲染路径的一部分。
    /// 它回答「打包成 .app 之后本进程能不能拿到显示刷新回调」（PDCA-A4），
    /// 测满窗口即自行 invalidate，产品不留常驻定时器。
#if !PIC_NO_PROBE
    private var frameDriver: FrameDriver?
#endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        // D-05：菜单栏 app 无 Dock 图标。断言时注意 .accessory 的 rawValue 是 1 不是 0。
        // 刻意**不**调前台激活接口 —— 那会抢焦点，破坏 .accessory 的语义（Phase 1 的 MenuBarSpike 同样避开）。
        NSApp.setActivationPolicy(.accessory)
        // 生效策略当场打一行，SC1「Dock 无图标」就不靠肉眼。
        emit("ACTIVATION_POLICY_RAW=\(NSApp.activationPolicy().rawValue)")
        wiring()
        // Plan 04-04：首启按需弹文件夹选择框 + 扫描起播。必须走 Task + await ——
        // pickFolder() 的模态面板要在主 run loop 上跑，在 launch 回调里同步
        // runModal() 会让启动停在那里。插在 wiring() 之后：四个 Watcher 已同步
        // 置位，弹框期间系统信号不丢。04-05：起播改在 bootstrap 末尾
        //（先取目录、再扫描、最后 startWallpaper，顺序写死）。
        Task { await bootstrapAfterWiring() }
#if !PIC_NO_PROBE
        startFrameDriver()
        startLoopProbeIfRequested()
#endif
        startHoldObserver()
        scheduleQuitAfterIfRequested()
        openSettingsIfRequested()
        startObservability()
    }

    /// 暂停/恢复的运行期可观测性 —— 打一行 `PIC_HOLD`，让「暂停」在进程内可 grep。
    ///
    /// 这一层**不判任何东西**，只记录。播放状态仍由 `HoldArbiter` 一处决定。
    ///
    /// ⚠️ D-05：这里曾经是一个 0.5 秒轮询定时器，短于它的暂停会漏采。
    /// 现改为观察 `arbiter.decision`：菜单的点击路径不经过
    /// AppDelegate，而插一个回调进去会让「谁改播放状态」这件事多出一个入口（D-11）——
    /// 所以这一层只读，不写。
    private func startHoldObserver() {
        armHoldObservation()
    }

    /// 注册一次对 `arbiter.decision` 的观察。
    ///
    /// `withObservationTracking` 的一次性语义：变化后必须**重新 arm**，否则只报一次变化。
    /// 首次 arm 当场读一次 `decision` 并打首行 `PIC_HOLD`（`observeHold()`），
    /// 所以「启动即已处于 hold 中」也会被记录下来。
    private func armHoldObservation() {
        let arbiter = self.arbiter
        withObservationTracking {
            _ = arbiter.decision
        } onChange: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.observeHold()
                self.armHoldObservation()
            }
        }
        observeHold()
    }

    private var lastHoldSnapshot: String?

    private func observeHold() {
        // D-05 唯一的机器判据。**必须在去重门之前**：`observeHold()` 里有
        // `guard snapshot != lastHoldSnapshot else { return }`，去重门让「0.5 秒轮询」
        // 与「观察驱动」在同一判据下输出完全相同（都是 1 行），那是空判（D-07：
        // 一条从没红过的判据不证明它会红）。本行打在门外：观察器被调用几次就是几。
        holdObserverTicks += 1
        emit(String(format: "PIC_HOLD_OBSERVER_TICKS=%d", holdObserverTicks))

        let reasons = arbiter.decision.activeReasons
        // 空集必须写成 (none) 而不是空串 —— 空串会让 grep 匹配到别的行。
        let list = reasons.map { String(describing: $0) }.joined(separator: ",")
        let snapshot = list.isEmpty ? "holds=(none)" : "holds=(\(list))"
        guard snapshot != lastHoldSnapshot else { return }
        lastHoldSnapshot = snapshot

        // active / reason 都从 `decision.activeReasons` 派生（D-11 的 veto 语义）。
        // 此前 `active` 取自「是否手动暂停」那个派生量，且 `reason` 在两个分支里都写死成
        // 手动暂停 —— 只有 `.screenLocked` 生效时会打出 `active=0` 却报手动暂停的
        // 那一行，两个字段互相矛盾，`active=1 reason=screenLocked` 结构上打不出来。
        // `reason` 取 `reasons.first`（不是 `last`）：`order` 升序，用户手动暂停优先，
        // 这是 D-10 允许的「优先级只用于文案排序」的落点。
        let active = !reasons.isEmpty
        let reason = reasons.first.map { String(describing: $0) } ?? "(none)"
        // 形状与 Phase 2 定死的那一串一致（`02-03-PLAN.md:174-175`）：**resumeAt 只出现在
        // 解除分支**。恢复时锚点已被仲裁器消费掉，所以它报的是恢复前的播放位置，
        // 由 `PlayerController.arbiterCurrentPosition` 给出，不含路径与文件名。
        // 两个分支共用同一个输出格式串（那条字面量在全文件恰好 1 处，挂在 test.sh 每次重验），
        // 尾部按需拼接 —— hold 中那行不能带 resumeAt，否则下游按 `…holds=(screenLocked)$`
        // 锚定行尾的判据永远命中不了。
        var line = String(format: "PIC_HOLD active=%d reason=%@ %@", active ? 1 : 0, reason, snapshot)
        if !active {
            line += String(format: " resumeAt=%.3f", player.arbiterCurrentPosition())
        }
        emit(line)

        // D-12 的数据落点的可观测出口：`HoldStatus.summary` 的派生值 + 原因条数。
        // 紧跟在每次 `PIC_HOLD` 变化之后，不另起定时器 —— 与上面同一处去重门，
        // 因此**不改变** `PIC_HOLD_OBSERVER_TICKS` 的计数语义（D-05 的判据照旧）。
        let status = arbiter.holdStatus
        emit(String(format: "PIC_HOLD_SUMMARY summary=%@ reasons=%d",
                    status.summary ?? "(none)", status.reasons.count))
    }

    /// `--quit-after <秒>` —— **可测性用的调试开关，不是产品能力**。
    ///
    /// 存在的原因：AppKit **不为 SIGTERM 装信号处理函数**（本机实测：最小 AppKit app 收到
    /// SIGTERM 后零 delegate 回调、进程立即死亡），所以 `kill -TERM` 走不到
    /// `applicationWillTerminate`。要证明「菜单那条终止路径真的会跑完收尾并让进程消失」，
    /// 就得有一个可控输入去调**同一个** `terminateApp()`。
    ///
    /// ⚠️ 这里**不允许**再写第二遍结束进程的全局调用字面量 —— 调 `terminateApp()` 就够了，
    /// 两处将来必然会漂移。不传这个参数时本函数一行都不跑，菜单里也不出现这个开关。
    private func scheduleQuitAfterIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--quit-after"), i + 1 < args.count,
              let seconds = Double(args[i + 1]), seconds > 0 else { return }
        emit("PIC_QUIT_AFTER_SCHEDULED seconds=\(seconds)")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            MainActor.assumeIsolated { self?.terminateApp() }
        }
    }

    /// `--open-settings` —— **测试脚手架，不是产品能力**（照 `--quit-after` 先例，
    /// T-05-03 同型处置：本地单用户 app，CLI 参数本就等价于「坐在键盘前」）。
    /// XCUITest/探针没有真人点菜单栏，用它与 `PicOpenSettings` 通知走**用户路径的
    /// 两个函数**（presentSettingsWindow + MenuContentView 的 openWindow），不开第二个
    /// 入口。不传这个参数时一行都不跑，菜单里也不出现。
    private func openSettingsIfRequested() {
        guard CommandLine.arguments.contains("--open-settings") else { return }
        presentSettingsWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(name: Notification.Name("PicOpenSettings"), object: nil)
        }
    }

    /// 装配点（D-09 单向流）。每根线都只接一次，重复调用是幂等的。
    ///
    /// ⚠️ **时序契约（D-06 / `W-2026-10-03-10`）**：四根 Watcher 线必须全部落位之后，
    /// `applicationDidFinishLaunching` 才会去 `startWallpaper()`。四个 `start()`
    /// 都**同步**回调一次当前状态，所以 `startWallpaper()` 读到的 `arbiter.decision`
    /// 已经包含本会话的全部系统信号 —— 锁屏中的会话不会先播一下再被压住。
    ///
    /// ⚠️ **本方法只接线，不在这里兜底补 `set`。** 「`start()` 里同步读一次当前状态」
    /// 这条契约由各自拥有源文件的 plan 负责（03-01 的 `LockWatcher.start` + 单测 +
    /// `LOCK_START_SYNC_DELIVERED`；03-02 / 03-03 / 03-04 各自的同步重算 + 单测）。
    /// 在这里手动补一次会让同一条契约变成两处实现，并给 D-09 的单向流多一个入口。
    ///
    /// 顺序：先三个 `NSWorkspace` / IOKit 的，最后 `lockWatcher` —— 后者会立刻用
    /// 真实会话状态置位，放在最后让它读到的是前面三者已就位的最终态。
    func wiring() {
        arbiter.attach(player)
        // Phase 5：轮换接进「当场生效」的唯一落点（模式/间隔的改写从这里出去）。
        settingsApplier.attach(rotation: rotation)

        // 四根线都只做「信号 → arbiter.set(_:active:)」的固定映射，不解析任何字符串。
        fullscreenDetector.start { [arbiter] isFullscreen in
            arbiter.set(.fullscreen, active: isFullscreen)
        }
        displayWatcher.start { [arbiter] signals in
            arbiter.set(.displayAsleep, active: signals.displayAsleep)
            arbiter.set(.systemSleeping, active: signals.systemSleeping)
        }
        powerWatcher.start { [weak self] isOnBattery in
            MainActor.assumeIsolated { self?.recordPowerState(isOnBattery) }
        }
        lockWatcher.start { [arbiter] isLocked in
            arbiter.set(.screenLocked, active: isLocked)
        }
    }

    /// 最近一次已知的电源状态。设置窗的 toggle 要用它**当场**重估，
    /// 不能等下一次电源跃迁（Phase 5，PLAY-10）。
    private var lastIsOnBattery = false

    /// 电源信号 → `SettingsApplier.applyBatteryPolicy`。
    ///
    /// ⚠️ 「要不要暂停」是 `BatteryHoldPolicy` 的纯函数（D-11：开关默认关闭），
    /// 「结果喂给谁」由 applier 统一收口 —— 05-02 之前这段映射写在本文件的闭包里，
    /// 与设置窗的 toggle 会成为两个 `.battery` 写入口（T-05-06 竞态双写）。
    private func recordPowerState(_ isOnBattery: Bool) {
        lastIsOnBattery = isOnBattery
        settingsApplier.applyBatteryPolicy(isOnBattery: isOnBattery)
    }

    /// 设置窗「电池时播放」toggle 的落点：**同一个**映射，用最近一次已知的电源状态
    /// 重算一次。视图不直接持有 AppDelegate —— 经 PicApp 注入闭包调本方法。
    func reapplyBatteryHold() {
        settingsApplier.applyBatteryPolicy(isOnBattery: lastIsOnBattery)
    }

    // MARK: - Phase 6 转码入口（Plan 06-04 T2）

    /// ffmpeg 判定的**唯一**写入口（Q7 的新鲜化）：启动查一次 + 每次点「打开…」重查。
    /// 用户中途装上 ffmpeg 不用重启 app —— 但必须有一处「点之前重查」，
    /// 靠开窗时的旧读数就是 T-06-18 的陈旧值欺骗。
    func refreshFFmpegAvailability() {
        ffmpegAvailability = ffmpegLocator.locate()
        // 只打 token 不打路径（T-03-02）：路径只进窗口徽章。
        emit("PIC_FFMPEG=\(ffmpegIsAvailable ? "available" : "unavailable")")
    }

    /// 设置窗读数与入口置灰共用这一份（不出现两套判定）。
    var ffmpegIsAvailable: Bool {
        if case .available = ffmpegAvailability { return true }
        return false
    }

    /// 设置窗「维护」行「打开…」的行为侧：先重查拿新鲜判定 —— 可用就调 `openWindow`
    /// 开窗并返回 true，不可用返回 false 让视图弹三途径安装说明。
    /// 分派留在装配层：置灰态与徽章读的是同一份 `ffmpegAvailability`，不在视图里判。
    @discardableResult
    func openTranscodeWindow(_ openWindow: () -> Void) -> Bool {
        refreshFFmpegAvailability()
        if case .available = ffmpegAvailability {
            openWindow()
            return true
        }
        return false
    }

    /// `PIC_LOCK_SIGNAL_PREFIX` —— **测试脚手架，不是产品能力**（`W-2026-10-03-15`）。
    ///
    /// 非空时把 `LockSignalNames` 的两个名字换成 `"<prefix>locked"` / `"<prefix>unlocked"`，
    /// 于是探针可以投合成事件而不碰系统通知名（那会让同机其它壁纸 app 一起暂停）。
    /// 不设这个变量时与系统名完全一致，不出现在菜单与设置里。
    private static func lockSignalNames() -> LockSignalNames {
        guard let prefix = ProcessInfo.processInfo.environment["PIC_LOCK_SIGNAL_PREFIX"],
              !prefix.isEmpty else { return .system }
        return LockSignalNames(locked: "\(prefix)locked", unlocked: "\(prefix)unlocked")
    }

    /// Plan 02-04 T2：把 Phase 1 的显示刷新降级观察搬进产品。
    ///
    /// ⚠️ **这一根线不接渲染**。`FrameDriver` 只数 tick、打两行
    /// `REFRESH_DRIVER=` / `REFRESH_TICK_RATE=`；播放推进由 `AVPlayer` 自己的
    /// 时间戳负责，窗口合成由 WindowServer 负责。把它接进渲染路径会造出一个
    /// 假的「画面在动」信号（Phase 1 正是因此才降级）。
    ///
    /// `NSScreen.main` 在本机单屏下唯一（`inset.log:SCREENS_COUNT=1`）；
    /// 多屏时每个屏各一个 displayLink，本 Phase 不展开 —— Phase 3 接
    /// `DisplayWatcher` 时再一并处理。
    #if !PIC_NO_PROBE
    private func startFrameDriver() {
        guard let screen = NSScreen.main else {
            emit("REFRESH_DRIVER=no_screen")
            return
        }
        let driver = FrameDriver()
        frameDriver = driver
        driver.attach(to: screen)
    }
#endif

    /// 渲染层建好 AVPlayerLayer 后注进来（Plan 02-04 打包复测时调用）。
    /// 本 plan 不调它：`attach(player:)` 已经把同一个 player 交给窗口侧的图层，
    /// 两处都设 player 只会让「接缝在哪」变得不可判定。
    func attachPlayerLayer(_ layer: AVPlayerLayer) {
        player.attach(to: layer)
    }

    /// 打开设置窗的前置动作：`.accessory` 的 app 没有 Dock 图标也不会被激活，
    /// 直接 `openWindow` 出来的窗口拿不到焦点。策略切换**只在本文件发生**（T-02-09）。
    @objc func presentSettingsWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 设置窗关闭时把策略改回 `.accessory` —— 少了这一句，Dock 图标会永久留下。
    /// 异常路径（窗口被系统回收）也走这一个入口，不留半开状态。
    @objc func hideSettingsAndRestorePolicy() {
        NSApp.setActivationPolicy(.accessory)
    }

    /// 全仓唯一的「结束进程」落点。菜单的 quit 闭包与 `--quit-after` 的定时器
    /// 都调本方法，谁都不许再写第二遍那一句字面量。
    @objc func terminateApp() {
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Pitfall 4：observer / run loop source / 重配置回调的注册与注销严格配对
        // （T-03-03 / T-03-10 / T-03-15）。四个 Watcher 在 `wiring()` 里 start，
        // 这里就摘四个 —— 两侧成对，长跑期的泄漏证据在 Phase 7。
        lockWatcher.stop()
        fullscreenDetector.stop()
        displayWatcher.stop()
        powerWatcher.stop()
        emit("PIC_TERMINATED pid=\(ProcessInfo.processInfo.processIdentifier) reason=application_will_terminate")
    }

    // MARK: - 竖切主体

    /// 04-05 T2：异步化 + 走 `MediaLibrary.scan` + `router.start`。装载分派由
    /// router 内部的 `onAdvance` 完成（内部装载 `items[0]` 并重放仲裁决策）。
    /// 末尾段（`arbiter.applyCurrentDecision()` → `setVolume`/`setMuted` →
    /// `shouldPlay` 门）一个字符未动（B1 / W-2026-10-03-21）。
    private func startWallpaper() async {
        // T-02-06：这一段只打印**原因类别**，绝不打印媒体路径。
        guard let folder = store.resolvedFolderURL() else {
            emit("PIC_NO_SOURCE reason=folder_unresolved")
            return
        }
        // 04-05：装载前的存在性检查由 `MediaLibrary.scan`（folderMissing）+
        // 探针负责；本守卫只判「扫完有没有可播条目」。
        guard let report = try? await library.scan(folder: folder), !report.items.isEmpty else {
            emit("PIC_NO_SOURCE reason=no_mp4_in_folder")
            return
        }

        // D-13：传的是 AVQueuePlayer 实例本身，不是 AVPlayerItem ——
        // looper 的模板 item 属性在 init 时就冻结，挂在 item 上「改设置立即生效」是假的。
        wallpaper.attach(player: player.player)
        router.start(with: report.items)
        emit("PIC_ROT_START=1")
        // D-06 / W-2026-10-03-10：起播决策**只**从仲裁器出，零播放器直连。
        // 四个 Watcher 的 start() 已在 wiring() 里同步置位，所以此刻 decision 已含
        // 本会话的全部系统信号 —— 锁屏中的会话不会先播一下再被压住。
        arbiter.applyCurrentDecision()
        // D-13：设置必须挂在 player 上（不是 item）、且在起播决策**之后**落位。
        //
        // 🔴 但 `setRate` 整段门在「应当播放」之后（W-2026-10-03-21）。这不是风格偏好：
        // `PlayerController.setRate(r)` 的实现就是 `player.rate = r`（PlayerController.swift:51），
        // SDK `AVPlayer.h:150` 明文 —— 设置非零 rate 会让 `timeControlStatus` 变成
        // `.waitingToPlayAtSpecifiedRate` 或 `.playing`。本机实测：pause() 之后置 rate=1.0，
        // `timeControlStatus` 在 0.25 秒内由 `.paused`(0) 变 `.playing`(1)。
        // 无条件调用它，已 hold 的播放器会被重新拉起，活体判据 `TICK … status=paused` 命中数为 0。
        //
        // ⚠️ 这条门控是本 Phase 最容易被后人「顺手清理」掉的一行，判据与证据见
        // `HoldStatusTests.testSetRateOnStartPathIsGatedByShouldPlay`（含删除该门控的变异验证）。
        player.setVolume(store.volume)
        player.setMuted(store.isMuted)
        if arbiter.decision.shouldPlay {
            player.setRate(store.rate)
        }
    }

    /// Phase 2 的同步取片路径。04-05 起 `startWallpaper()` 走 `MediaLibrary.scan`，
    /// 本函数保留不删（不为此消警告去动别处）。
    private func firstVideoURL(in folder: URL) -> URL? {
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return items
            .filter { $0.pathExtension.lowercased() == "mp4" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .first
    }

    /// ② T2 的 300 秒循环探针与 T3 的验收脚本共同的原始数据源：
    /// 每 2 秒打一行播放推进读数。位置是否在推进由 T2 的采样判定，
    /// 本 Phase 不放刷新驱动（Phase 1 实测本进程拿不到任何显示刷新回调，
    /// `FRAME_DRIVER=timer_fallback_hz30`，再放一遍只会制造一个假的「在刷新」信号）。
    private func startObservability() {
        let t = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func tick() {
        tickSeq += 1
        let seconds = player.player.currentTime().seconds
        let pos = seconds.isFinite ? String(format: "%.3f", seconds) : "nan"
#if !PIC_NO_PROBE
        emit("TICK seq=\(tickSeq) pos=\(pos) status=\(LoopProbe.statusToken(player.player.timeControlStatus)) items=\(player.player.items().count)")
#endif
    }

    /// `scripts/run-probe.sh loop` 设 `PIC_LOOP_SECONDS=300` 才启动 300 秒观察；
    /// 不设这个变量时代码一行都不跑，tracer 与日常开发零开销。
    #if !PIC_NO_PROBE
    private func startLoopProbeIfRequested() {
        guard let raw = ProcessInfo.processInfo.environment[LoopProbe.secondsEnvKey],
              let seconds = Int(raw), seconds > 0 else { return }
        let probe = LoopProbe(player: player.player, durationSeconds: seconds) { [weak self] in
            MainActor.assumeIsolated { self?.terminateApp() }
        }
        loopProbe = probe
        probe.start()
    }
#endif

    private func emit(_ line: String) {
        WallpaperWindowController.emit(line)
    }

    // MARK: - Phase 4 菜单动作与首启引导（Plan 04-04 T3）

    /// 首启引导：装上状态打点，然后「按需弹框 → 扫描起播」。
    /// 取消 / 被拒时不再扫描：取消分支已经打过未配置那一行读数，
    /// 再扫只会对同一件事打第二遍（D-17：一个数不两种读法）。
    private func bootstrapAfterWiring() async {
        // 正常扫描路径的状态变更由协调器打（04-03 冻结的出口）。
        // 会话态也在**这个 handler** 里更新 —— 打点处仍是恰好 2 处（取消分支 +
        // 这里），再开一处会让 04-04 的取消分支语义漂成两个真相源。
        coordinator.onStateChange = { [weak self] state in
            self?.emit("PIC_LIBRARY_STATE=" + LibraryAvailability.token(state))
            self?.sessionState.update(state: state)
        }
        guard await requestFolderIfNeeded() else { return }
        await rescanAndApply()
        // 04-05（SC4）：顺序写死 —— 先取目录、再扫描、最后起播。反序会让首次
        // 启动在没有目录/扫描结果时先走一遍 PIC_NO_SOURCE。
        await startWallpaper()
        emitBootSettings()
        // 启动查一次 ffmpeg（Q7）。追加在既有步骤之后，不动 04-05 写死的顺序。
        refreshFFmpegAvailability()
    }

    /// `PIC_SETTINGS_BOOT`：启动时把 7 键里的 6 个可调值各打一次（TEST-04 的
    /// 重启回读锚点）。值全部来自 store —— 探针 seed 什么、这里就回读什么。
    /// 一行、每个值只出现一次（D-17）。
    private func emitBootSettings() {
        emit("PIC_SETTINGS_BOOT rate=\(store.rate) volume=\(store.volume) muted=\(store.isMuted ? 1 : 0) playMode=\(store.playMode.rawValue) rotationInterval=\(Int(store.rotationInterval)) pauseOnBattery=\(store.pauseOnBattery ? 1 : 0)")
    }

    /// 该不该弹文件夹选择框由 FolderRequestPolicy 纯函数决定（SYS-03 / SOURCE-07）。
    /// 取消不是错误：安静返回 false —— 不弹错误窗、不崩、不重试。
    private func requestFolderIfNeeded() async -> Bool {
        let env = ProcessInfo.processInfo.environment[SettingsStore.envSourceFolderKey]
        guard FolderRequestPolicy.shouldRequestFolder(sourceFolder: store.sourceFolder,
                                                       envOverride: env) else {
            return true
        }
        emit("PIC_FOLDER_REQUEST_REASON=unconfigured")
        switch await pickFolder() {
        case .accepted:
            return true
        case .cancelled:
            emit("PIC_FOLDER_PICK_CANCELLED=1")
            // 取消路径直接 return false，不调 coordinator.apply —— 这一行是取消
            // 路径记录该 token 的唯一方式（与上面的 onStateChange 处理器各有独立语义）。
            emit("PIC_LIBRARY_STATE=" + LibraryAvailability.token(.folderUnconfigured))
            return false
        case .rejected:
            emit("PIC_FOLDER_PICK_REJECTED=1")
            return false
        }
    }

    private enum FolderPickOutcome { case accepted, cancelled, rejected }

    /// 弹面板 → 校验 → 写盘。**不**扫描、不发状态行：取消的语义由调用方决定
    /// （首启的取消 = 从没配过；设置窗的取消 = 保持现状，两者不能共用同一行）。
    private func pickFolder() async -> FolderPickOutcome {
        // 面板是模态窗口：.accessory 的 app 弹它之前必须激活（T-02-09 的单点），
        // 弹完必须恢复 —— 少了恢复这一步，Dock 图标会永久留下（T-04-20）。
        presentSettingsWindow()
        let url = await picker.pickFolder()
        hideSettingsAndRestorePolicy()
        guard let url else { return .cancelled }
        guard FolderRequestPolicy.isAcceptableSelection(url) else { return .rejected }
        store.sourceFolder = FolderRequestPolicy.normalizedPath(url)
        store.persist()
        // 只打 PICKED=1，不打路径（T-03-02：目录路径不进日志，设置窗是唯一例外）。
        emit("PIC_FOLDER_PICKED=1")
        return .accepted
    }

    /// 设置窗「选择…」的行为侧（SOURCE-07）：与首启引导走**同一个**面板落点，
    /// 选完立即重扫。取消不动现状 —— 当前文件夹继续生效，因此不发任何状态行。
    func requestFolderNow() {
        Task {
            if await pickFolder() == .accepted { await rescanAndApply() }
        }
    }

    /// 「切换目录」与「重新扫描」走**同一条**路径 —— 两处实现必然会漂。
    /// 04-05：扫描结果交给协调器后，按返回的 `LibraryState` 分派装载
    /// （`.playing` → `router.start`，SC1/SC4；三个隐藏态 → `router.stop`）。
    private func rescanAndApply() async {
        sessionState.isScanning = true
        defer { sessionState.isScanning = false }
        guard let folder = store.resolvedFolderURL() else {
            dispatchPlayback(for: coordinator.apply(scanOutcome: .success(0),
                                                    folderConfigured: false), items: [])
            return
        }
        // 模式与间隔从设置带过来（当场生效，不存第二份真相）。04-05：同步后打
        // 一行模式读数（只打 token，D-17 / T-03-02）。
        rotation.setMode(store.playMode)
        rotation.setInterval(store.rotationInterval)
        emit("PIC_ROT_MODE=\(store.playMode.rawValue)")
        do {
            let report = try await library.scan(folder: folder)
            sessionState.playableCount = report.playableCount
            dispatchPlayback(for: coordinator.apply(scanOutcome: .success(report.playableCount),
                                                    folderConfigured: true),
                             items: report.items)
        } catch let error as MediaLibrary.MediaLibraryError {
            dispatchPlayback(for: coordinator.apply(scanOutcome: .failure(error),
                                                    folderConfigured: true), items: [])
        } catch {
            // scan 只抛 MediaLibraryError，这里是编译器要的兜底；真到了这一步
            // 说明出了没料到的错误，按「目录读不了」处理（隐藏 + 让出桌面）。
            dispatchPlayback(for: coordinator.apply(scanOutcome: .failure(.folderUnreadable),
                                                    folderConfigured: true), items: [])
        }
    }

    /// 04-05 T2 ③：`LibraryState` → 装载分派。只看 `coordinator.apply` 的返回值，
    /// 不在 AppDelegate 再判一次「有没有视频」（那会与 `LibraryAvailability` 的
    /// 纯函数决策漂成两处）。
    private func dispatchPlayback(for state: LibraryState, items: [VideoItem]) {
        switch state {
        case .playing:
            router.start(with: items)
        case .folderUnconfigured, .folderMissing, .noPlayableVideos:
            emit("PIC_ROT_STOP=1")
            router.stop()
        }
    }

    /// 「立即下一个」的行为侧（MENUBAR-04）：只叫轮换器，不碰 player、不碰
    /// arbiter —— 换片由 onAdvance → 装载完成（T-04-22：菜单动作不得绕过仲裁器
    /// 把已 hold 的播放器重新拉起）。04-05：换片已接上，打一行切换计数。
    func nextVideoNow() {
        emit("PIC_MENU_ACTION=next_video")
        rotation.advanceNow()
        emit("PIC_ROT_ADVANCES=\(rotation.advances.count)")
    }

    /// 「重新扫描」的唯一落点（MENUBAR-05 与设置窗共用）：显式失效缓存再重扫 ——
    /// 不失效的话菜单项会看起来「点了没反应」。单次 Task 串行：连点不会并发扫
    /// 两遍；每次点击都打一行读数，重复点击在 evidence 里可数（T-04-21）。
    func rescanLibrary() {
        library.invalidateCache()
        Task { await rescanAndApply() }
    }

    /// 菜单侧薄壳：只多打一行菜单动作读数（设置窗不经过菜单，故不打）。
    func rescanFolderNow() {
        emit("PIC_MENU_ACTION=rescan_folder")
        rescanLibrary()
    }
}

// MARK: - 04-03 seam 的产品侧适配（Plan 04-04 T3）

/// `WallpaperPresenting` 的极薄适配。刻意**不**给 `WallpaperWindowController`
/// 直接加 conformance —— 那会让 PicCore 的类型背上协议依赖，而 04-03 的判据
/// 锁着 MediaCoordinator.swift 零 AppKit；适配留在装配层（D-10 唯一装配点）。
@MainActor
private final class WallpaperPresenter: WallpaperPresenting {
    private let controller: WallpaperWindowController

    init(controller: WallpaperWindowController) { self.controller = controller }

    func show() { controller.show() }
    func hide() { controller.hide() }
}

/// `PlaybackStopping` 的极薄适配，包住 04-03 纯增量的 `stop()`。
@MainActor
private final class PlaybackStopper: PlaybackStopping {
    private let player: PlayerController

    init(player: PlayerController) { self.player = player }

    func stopPlayback() { player.stop() }
}

/// `VideoLoading` 的产品侧适配（Plan 04-05 T2）。刻意不给 `PlayerController` 直接加
/// conformance —— 那会让 PicCore 的类型背上 PicApp 的 seam 语义（04-03 分层纪律）。
/// 两件事、顺序不可换：先装载，再重放仲裁决策 —— `load(url:)` 会重置队列，不重放
/// 的话一个处于 hold 的会话会在换片后「先播一下」再被压住（B1 在起播路径防的事，
/// 轮换路径同样要防）。走 `arbiter` 而不是 `player.arbiterApply(_:)`，让「决策从
/// 哪来」只有一处。
@MainActor
private final class PlayerLoadingAdapter: VideoLoading {
    private let player: PlayerController
    private let arbiter: HoldArbiter

    init(player: PlayerController, arbiter: HoldArbiter) {
        self.player = player
        self.arbiter = arbiter
    }

    func loadPlayback(url: URL) {
        player.load(url: url)
        arbiter.applyCurrentDecision()
    }
}