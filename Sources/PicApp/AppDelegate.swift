import AppKit
import AVFoundation
import PicCore

/// 唯一装配点：全仓唯一把系统信号变成 `HoldReason` 的地方（单向流 `Watcher → HoldArbiter → PlayerController`）。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = SettingsStore(
        defaults: .standard,
        seed: SettingsStore.Seed()
    )
    let player = PlayerController()
    let arbiter = HoldArbiter()
    let wallpaper = WallpaperWindowController()
    /// 设置「当场生效」的唯一落点。lazy：构造参数要引用上面的持有者，属性默认值里引用不了 self。
    lazy var settingsApplier = SettingsApplier(store: store, player: player, arbiter: arbiter)
    // ⚠️ 四个 Watcher 都必须**强持有**。谁创建谁 `stop()`：observer / IOKit run loop source /
    // 显示器重配置回调一旦没人摘就永久泄漏。只在闭包里临时捕获不构成持有 —— 那样 `stop()` 无人可调。
    let lockWatcher = LockWatcher(names: lockSignalNames())
    let fullscreenDetector = FullscreenDetector()
    let displayWatcher = DisplayWatcher()
    let powerWatcher = PowerWatcher()
    // ⚠️ `library` 与 `rotation` 都必须**强持有**：前者持扫描缓存，后者持
    // `onAdvance` 闭包与调度器（Timer 没人持有就被释放）。
    let library = MediaLibrary()
    /// 面板 seam：全仓唯一碰 NSOpenPanel 的地方注入进来的句柄。
    let picker: any FolderPicker = NSOpenPanelFolderPicker()
    let rotation = RotationController(
        scheduler: SystemRotationScheduler(),
        random: SeededRandomSource(seed: UInt64(bitPattern: Int64(Date().timeIntervalSince1970)))
    )
    /// 扫描结果 → 窗口/播放器动作的唯一落点。lazy：构造参数要包住上面的持有者，
    /// 属性默认值里引用不了 self；每次访问都在主线程，无竞态。
    lazy var coordinator = MediaCoordinator(
        presenting: WallpaperPresenter(controller: wallpaper),
        stopping: PlaybackStopper(player: player)
    )
    /// 设置窗的会话态读数（计数 / 空态 / 扫描时间）。**不进 store**：这些都不是用户设过的偏好。
    let sessionState = SettingsSessionState()
    /// 单一真相源：设置窗状态卡、维护行置灰态、转码窗徽章读的都是它。
    /// 生产件走 `FFmpegAvailability.productionLocator()` —— 判定层唯一的生产构造点。
    private lazy var ffmpegLocator: ExternalToolLocator = FFmpegAvailability.productionLocator()
    /// 转码窗徽章复用**同一个** locator —— 入口置灰与徽章不许出现两套判定。
    var transcodeLocator: ExternalToolLocator { ffmpegLocator }
    /// 最近一次的判定结论。`refreshFFmpegAvailability()` 的唯一写入口。
    private(set) var ffmpegAvailability: FFmpegToolStatus = .unavailable
    /// 转码队列的持有者。排空钩子挂在这里（不是别的 lazy 属性里）：漏挂的表象是
    /// 「转完了但清单里没有新片」，而清单那条路本身不报错，只有这个闭包在。
    lazy var transcodeQueue: TranscodeQueue = {
        let queue = TranscodeQueue(
            runner: ProcessTranscodeRunner(),
            naming: TranscodeOutputNaming(
                root: store.resolvedFolderURL() ?? URL(fileURLWithPath: NSTemporaryDirectory())),
            availability: { [weak self] in self?.ffmpegAvailability ?? .unavailable },
            freeSpaceProvider: { url in
                (try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
                    .volumeAvailableCapacityForImportantUsage
            })
        queue.onBatchFinished = { [weak self] in
            MainActor.assumeIsolated { self?.handleTranscodeBatchFinished() }
        }
        return queue
    }()
    /// 轮换 → 装载的路由器。强持有（它持 `rotation.onAdvance` 闭包）；lazy：init 引用 self 的其它属性。
    private lazy var router = PlaybackRouter(
        rotation: rotation,
        loader: PlayerLoadingAdapter(player: player, arbiter: arbiter)
    )

    /// 转码视图模型。2026-10-04 起转码并入设置窗（第二个 TAB），不再有独立 scene，
    /// 所以持有者从 `TranscodeScene` 的壳挪到这里 —— `@StateObject` 只能挂 View，
    /// 而 viewModel 的生命周期必须跟着 AppDelegate（否则窗口一开一关就重建、队列状态丢失）。
    lazy var transcodeViewModel = TranscodeViewModel(
        queue: transcodeQueue,
        locator: transcodeLocator,
        wallpaperRootProvider: { [weak self] in self?.store.resolvedFolderURL() },
        sourcePicker: picker
    )

    /// 开机自启的唯一写入口。
    ///
    /// ⚠️ 必须**强持有** —— emit 闭包捕获了 `self` 的 `emit(_:)`，让它随用随建会出现「实例被回收后闭包仍活着」的窗口。
    /// lazy：构造参数要引用 `self.emit`，属性默认值里引用不了 self。
    private lazy var autostart = AutoStartManager { [weak self] line in self?.emit(line) }

    private var ticker: Timer?
    /// `PIC_HOLD` 由对 `arbiter.decision` 的观察驱动，观察者由 `armHoldObservation()`
    /// 一次性注册并在 `onChange` 里重新 arm。
    private var tickSeq = 0
#if !PIC_NO_PROBE
    private var loopProbe: LoopProbe?
#endif
    /// `observeHold()` 在本进程内被调用的次数 —— 打在**去重门之前**：12 秒零决策变化的
    /// 窗口里它必须恒为 1；0.5 秒轮询会涨到约 24。
    private var holdObserverTicks = 0
    /// 显示刷新驱动的**测量器**，不是渲染路径的一部分。它回答「打包成 .app 之后本进程
    /// 能不能拿到显示刷新回调」，测满窗口即自行 invalidate，产品不留常驻定时器。
#if !PIC_NO_PROBE
    private var frameDriver: FrameDriver?
#endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 断言时注意 .accessory 的 rawValue 是 1 不是 0。
        // 刻意**不**调前台激活接口 —— 那会抢焦点，破坏 .accessory 的语义。
        NSApp.setActivationPolicy(.accessory)
        // 生效策略当场打一行，「Dock 无图标」就不靠肉眼。
        emit("ACTIVATION_POLICY_RAW=\(NSApp.activationPolicy().rawValue)")
        // 每次启动对齐一次用户偏好与系统登录项状态：偏好为 false 时 disableBoth 是
        // 幂等清理（app 被移动过 / plist 残留），为 true 时重新注册，顺带改回路径漂移。
        // ⚠️ 刻意不嵌进 startWallpaper() —— 那条路径有「一字不动」约束。
        autostart.setEnabled(store.launchAtLogin)
        wiring()
        // 首启按需弹文件夹选择框 + 扫描起播。必须走 Task + await —— pickFolder() 的模态面板
        // 要在主 run loop 上跑，在 launch 回调里同步 runModal() 会让启动停在那里。
        // 插在 wiring() 之后：四个 Watcher 已同步置位，弹框期间系统信号不丢。
        // 起播改在 bootstrap 末尾（先取目录、再扫描、最后 startWallpaper，顺序写死）。
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
    /// 这一层**不判任何东西**，只记录。播放状态仍由 `HoldArbiter` 一处决定。
    /// ⚠️ 这里曾经是一个 0.5 秒轮询定时器，短于它的暂停会漏采。现改为观察
    /// `arbiter.decision`：菜单的点击路径不经过 AppDelegate，而插一个回调进去会让
    /// 「谁改播放状态」这件事多出一个入口 —— 所以这一层只读，不写。
    private func startHoldObserver() {
        armHoldObservation()
    }

    /// 注册一次对 `arbiter.decision` 的观察。
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
        // **必须在去重门之前**：`observeHold()` 里有 `guard snapshot != lastHoldSnapshot else { return }`，
        // 去重门让「0.5 秒轮询」与「观察驱动」在同一判据下输出完全相同（都是 1 行），那是空判
        // （一条从没红过的判据不证明它会红）。本行打在门外：观察器被调用几次就是几。
        holdObserverTicks += 1
        emit(String(format: "PIC_HOLD_OBSERVER_TICKS=%d", holdObserverTicks))

        let reasons = arbiter.decision.activeReasons
        // 空集必须写成 (none) 而不是空串 —— 空串会让 grep 匹配到别的行。
        let list = reasons.map { String(describing: $0) }.joined(separator: ",")
        let snapshot = list.isEmpty ? "holds=(none)" : "holds=(\(list))"
        guard snapshot != lastHoldSnapshot else { return }
        lastHoldSnapshot = snapshot

        // active / reason 都从 `decision.activeReasons` 派生。此前 `active` 取自「是否手动暂停」
        // 那个派生量，且 `reason` 在两个分支里都写死成手动暂停 —— 只有 `.screenLocked` 生效时
        // 会打出 `active=0` 却报手动暂停的那一行，两个字段互相矛盾。
        // `reason` 取 `reasons.first`（不是 `last`）：`order` 升序，用户手动暂停优先。
        let active = !reasons.isEmpty
        let reason = reasons.first.map { String(describing: $0) } ?? "(none)"
        // **resumeAt 只出现在解除分支**。恢复时锚点已被仲裁器消费掉，所以它报的是恢复前的
        // 播放位置，由 `PlayerController.arbiterCurrentPosition` 给出，不含路径与文件名。
        // 两个分支共用同一个输出格式串（那条字面量在全文件恰好 1 处，挂在 test.sh 每次重验），
        // 尾部按需拼接 —— hold 中那行不能带 resumeAt，否则下游按 `…holds=(screenLocked)$`
        // 锚定行尾的判据永远命中不了。
        var line = String(format: "PIC_HOLD active=%d reason=%@ %@", active ? 1 : 0, reason, snapshot)
        if !active {
            line += String(format: " resumeAt=%.3f", player.arbiterCurrentPosition())
        }
        emit(line)

        // `HoldStatus.summary` 的派生值 + 原因条数。紧跟在每次 `PIC_HOLD` 变化之后，不另起定时器
        // —— 与上面同一处去重门，因此**不改变** `PIC_HOLD_OBSERVER_TICKS` 的计数语义。
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
    /// ⚠️ 这里**不允许**再写第二遍结束进程的全局调用字面量 —— 两处将来必然会漂移。
    /// 不传这个参数时本函数一行都不跑，菜单里也不出现这个开关。
    private func scheduleQuitAfterIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--quit-after"), i + 1 < args.count,
              let seconds = Double(args[i + 1]), seconds > 0 else { return }
        emit("PIC_QUIT_AFTER_SCHEDULED seconds=\(seconds)")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            MainActor.assumeIsolated { self?.terminateApp() }
        }
    }

    /// `--open-settings` —— **测试脚手架，不是产品能力**（照 `--quit-after` 先例：
    /// 本地单用户 app，CLI 参数本就等价于「坐在键盘前」）。
    /// XCUITest/探针没有真人点菜单栏，用它与 `PicOpenSettings` 通知走**用户路径的
    /// 两个函数**（presentSettingsWindow + MenuContentView 的 openWindow），不开第二个入口。
    /// 不传这个参数时一行都不跑，菜单里也不出现。
    private func openSettingsIfRequested() {
        guard CommandLine.arguments.contains("--open-settings") else { return }
        presentSettingsWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(name: Notification.Name("PicOpenSettings"), object: nil)
        }
    }

    /// 装配点（单向流）。每根线都只接一次，重复调用是幂等的。
    ///
    /// ⚠️ **时序契约**：四根 Watcher 线必须全部落位之后，`applicationDidFinishLaunching`
    /// 才会去 `startWallpaper()`。四个 `start()` 都**同步**回调一次当前状态，所以
    /// `startWallpaper()` 读到的 `arbiter.decision` 已经包含本会话的全部系统信号 ——
    /// 锁屏中的会话不会先播一下再被压住。
    ///
    /// ⚠️ **本方法只接线，不在这里兜底补 `set`。** 「`start()` 里同步读一次当前状态」
    /// 这条契约由各自拥有源文件的 plan 负责（各自的单测锁着）。在这里手动补一次会让同一条
    /// 契约变成两处实现，并给单向流多一个入口。
    ///
    /// 顺序：先三个 `NSWorkspace` / IOKit 的，最后 `lockWatcher` —— 后者会立刻用
    /// 真实会话状态置位，放在最后让它读到的是前面三者已就位的最终态。
    func wiring() {
        arbiter.attach(player)
        // 轮换接进「当场生效」的唯一落点（模式/间隔的改写从这里出去）。
        settingsApplier.attach(rotation: rotation)

        // 四根线都只做「信号 → arbiter.set(_:active:)」的固定映射，不解析任何字符串。
        fullscreenDetector.start { [arbiter] isFullscreen in
            MainActor.assumeIsolated { arbiter.set(.fullscreen, active: isFullscreen) }
        }
        displayWatcher.start { [arbiter] signals in
            arbiter.set(.displayAsleep, active: signals.displayAsleep)
            arbiter.set(.systemSleeping, active: signals.systemSleeping)
        }
        powerWatcher.start { [weak self] isOnBattery in
            MainActor.assumeIsolated { self?.recordPowerState(isOnBattery) }
        }
        lockWatcher.start { [arbiter] isLocked in
            MainActor.assumeIsolated { arbiter.set(.screenLocked, active: isLocked) }
        }
    }

    /// 最近一次已知的电源状态。设置窗的 toggle 要用它**当场**重估，不能等下一次电源跃迁。
    private var lastIsOnBattery = false

    /// 电源信号 → `SettingsApplier.applyBatteryPolicy`。
    ///
    /// ⚠️ 「要不要暂停」是 `BatteryHoldPolicy` 的纯函数（开关默认关闭），
    /// 「结果喂给谁」由 applier 统一收口 —— 此前这段映射写在本文件的闭包里，
    /// 与设置窗的 toggle 会成为两个 `.battery` 写入口。
    private func recordPowerState(_ isOnBattery: Bool) {
        lastIsOnBattery = isOnBattery
        settingsApplier.applyBatteryPolicy(isOnBattery: isOnBattery)
    }

    /// 设置窗「电池时播放」toggle 的落点：**同一个**映射，用最近一次已知的电源状态重算一次。
    /// 视图不直接持有 AppDelegate —— 经 PicApp 注入闭包调本方法。
    func reapplyBatteryHold() {
        settingsApplier.applyBatteryPolicy(isOnBattery: lastIsOnBattery)
    }

    /// 设置窗「开机自启」toggle 的行为侧：拨动即刻落系统侧（A→B 决策在 `AutoStartManager` 内），
    /// 状态与状态行由那一层打。
    /// 视图不持有 AppDelegate，经 PicApp 注入闭包调本方法 —— 与 `reapplyBatteryHold()`
    /// 同一条装配通道，不开第二条。
    func setLaunchAtLogin(_ enabled: Bool) {
        autostart.setEnabled(enabled)
    }

    // MARK: - ffmpeg 判定与转码队列

    /// ffmpeg 判定的**唯一**写入口：启动查一次 + 每次点「打开…」重查。
    /// 用户中途装上 ffmpeg 不用重启 app —— 但必须有一处「点之前重查」，
    /// 靠开窗时的旧读数就是陈旧值欺骗。
    func refreshFFmpegAvailability() {
        ffmpegAvailability = ffmpegLocator.locate()
        // 会话态回填（设置窗卡片读这里，可观察 → 刷新即重渲染）。
        sessionState.ffmpegAvailable = ffmpegIsAvailable
        // 只打 token 不打路径：路径只进窗口徽章。
        emit("PIC_FFMPEG=\(ffmpegIsAvailable ? "available" : "unavailable")")
    }

    /// 设置窗读数与入口置灰共用这一份（不出现两套判定）。
    var ffmpegIsAvailable: Bool {
        if case .available = ffmpegAvailability { return true }
        return false
    }

    /// 设置窗「维护」行「打开…」的行为侧：先重查拿新鲜判定 —— 可用就调 `openWindow` 开窗并
    /// 返回 true，不可用返回 false 让视图弹三途径安装说明。
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

    /// `Converted/` 的独立扫描器（播放第二入口）。与 `library` 同隔离域。
    /// 刻意不复用 `MediaLibrary` 的缓存 —— 它的扫描结果被 `excludedByConverted` 全排除。
    private lazy var convertedLibrary = ConvertedLibrary()

    /// 播放清单合并的**唯一**入口：根扫描 items 在前、`Converted/` 产物按序追加、
    /// 按 path 去重。转码产物因此当轮就能进轮换，不必回根目录再生成一份。
    /// 转换侧扫不出来一律吞成空数组 —— 播不了新片不该打断正在播的旧片。
    private func mergedPlaybackItems(_ report: MediaLibraryReport?) async -> [VideoItem] {
        let root = report?.items ?? []
        guard let folder = store.resolvedFolderURL() else { return root }
        let converted = (try? await convertedLibrary.scan(folder: folder)) ?? []
        return ConvertedLibrary.playbackItems(root: root, converted: converted)
    }

    /// 转码队列排空 → 新产物当轮进播放清单。
    /// ⚠️ 失效缓存必须**同步**排在重扫之前：`MediaLibrary.scan` 默认吃内存缓存，
    /// 不失效的话重扫拿回的是上一轮的 report，新 MP4 永远看不见（静默失效，不报错）。
    private func handleTranscodeBatchFinished() {
        library.invalidateCache()
        emit("PIC_TRC_RESCAN=1")
        Task { await rescanAndApply() }
    }

    /// `PIC_LOCK_SIGNAL_PREFIX` —— **测试脚手架，不是产品能力**。
    ///
    /// 非空时把 `LockSignalNames` 的两个名字换成 `"<prefix>locked"` / `"<prefix>unlocked"`，
    /// 于是探针可以投合成事件而不碰系统通知名（那会让同机其它壁纸 app 一起暂停）。
    /// 不设这个变量时与系统名完全一致，不出现在菜单与设置里。
    private static func lockSignalNames() -> LockSignalNames {
        guard let prefix = ProcessInfo.processInfo.environment["PIC_LOCK_SIGNAL_PREFIX"],
              !prefix.isEmpty else { return .system }
        return LockSignalNames(locked: "\(prefix)locked", unlocked: "\(prefix)unlocked")
    }

    /// ⚠️ **这一根线不接渲染**。`FrameDriver` 只数 tick、打两行 `REFRESH_DRIVER=` /
    /// `REFRESH_TICK_RATE=`；播放推进由 `AVPlayer` 自己的时间戳负责，窗口合成由 WindowServer
    /// 负责。把它接进渲染路径会造出一个假的「画面在动」信号。
    ///
    /// `NSScreen.main` 在本机单屏下唯一（`inset.log:SCREENS_COUNT=1`）；多屏时每个屏各一个
    /// displayLink，本 Phase 不展开。
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

    /// 打开设置窗的前置动作：`.accessory` 的 app 没有 Dock 图标也不会被激活，
    /// 直接 `openWindow` 出来的窗口拿不到焦点。策略切换**只在本文件发生**。
    @objc func presentSettingsWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 设置窗关闭时把策略改回 `.accessory` —— 少了这一句，Dock 图标会永久留下。
    /// 异常路径（窗口被系统回收）也走这一个入口，不留半开状态。
    @objc func hideSettingsAndRestorePolicy() {
        NSApp.setActivationPolicy(.accessory)
    }

    /// 全仓唯一的「结束进程」落点。菜单的 quit 闭包与 `--quit-after` 的定时器都调本方法，
    /// 谁都不许再写第二遍那一句字面量。
    @objc func terminateApp() {
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Pitfall 4：observer / run loop source / 重配置回调的注册与注销严格配对。四个 Watcher
        // 在 `wiring()` 里 start，这里就摘四个 —— 两侧成对。
        lockWatcher.stop()
        fullscreenDetector.stop()
        displayWatcher.stop()
        powerWatcher.stop()
        emit("PIC_TERMINATED pid=\(ProcessInfo.processInfo.processIdentifier) reason=application_will_terminate")
        // 退出快照：自动轮换的累计切换数。**只在退出这一条路径上打** —— nextVideoNow() 里的
        // PIC_ROT_ADVANCES= 是菜单手动 next 专用，两者读同一个 rotation.advances.count
        // 但触发点与语义不同（压测全程无人点菜单，短的那条不 emit）。
        // ⚠️ 反直觉陷阱：PIC_ROT_ADVANCES 是本键的**前缀**，将来数「手动 next 打点」那条线
        // 必须写成带等号的 'PIC_ROT_ADVANCES=\('，裸 token 会被这里 +1。
        emit(String(format: "PIC_ROT_ADVANCES_TOTAL=%d", rotation.advances.count))
    }

    // MARK: - 竖切主体

    /// 异步化 + 走 `MediaLibrary.scan` + `router.start`。装载分派由 router 内部的 `onAdvance`
    /// 完成（内部装载 `items[0]` 并重放仲裁决策）。
    private func startWallpaper() async {
        // 这一段只打印**原因类别**，绝不打印媒体路径。
        guard let folder = store.resolvedFolderURL() else {
            emit("PIC_NO_SOURCE reason=folder_unresolved")
            return
        }
        // 装载前的存在性检查由 `MediaLibrary.scan`（folderMissing）+ 探针负责；
        // 本守卫只判「扫完有没有可播条目」。
        guard let report = try? await library.scan(folder: folder), !report.items.isEmpty else {
            emit("PIC_NO_SOURCE reason=no_mp4_in_folder")
            return
        }

        // 传的是 AVQueuePlayer 实例本身，不是 AVPlayerItem —— looper 的模板 item 属性在 init
        // 时就冻结，挂在 item 上「改设置立即生效」是假的。
        wallpaper.attach(player: player.player)
        // `Converted/` 产物与根扫描清单合并后才进轮换（转码产物首启即可播）。
        router.start(with: await mergedPlaybackItems(report))
        emit("PIC_ROT_START=1")
        // 起播决策**只**从仲裁器出，零播放器直连。四个 Watcher 的 start() 已在 wiring() 里
        // 同步置位，所以此刻 decision 已含本会话的全部系统信号 —— 锁屏中的会话不会先播一下再被压住。
        arbiter.applyCurrentDecision()
        // 设置必须挂在 player 上（不是 item）、且在起播决策**之后**落位。
        //
        // 🔴 但 `setRate` 整段门在「应当播放」之后。这不是风格偏好：
        // `PlayerController.setRate(r)` 的实现就是 `player.rate = r`，SDK `AVPlayer.h:150`
        // 明文 —— 设置非零 rate 会让 `timeControlStatus` 变成 `.waitingToPlayAtSpecifiedRate`
        // 或 `.playing`。本机实测：pause() 之后置 rate=1.0，`timeControlStatus` 在 0.25 秒内
        // 由 `.paused`(0) 变 `.playing`(1)。无条件调用它，已 hold 的播放器会被重新拉起。
        //
        // ⚠️ 这条门控是最容易被后人「顺手清理」掉的一行，判据与证据见
        // `HoldStatusTests.testSetRateOnStartPathIsGatedByShouldPlay`（含删除该门控的变异验证）。
        player.setVolume(store.volume)
        player.setMuted(store.isMuted)
        if arbiter.decision.shouldPlay {
            player.setRate(store.rate)
        }
    }

    /// 每 2 秒打一行播放推进读数，是 300 秒循环探针与验收脚本共同的原始数据源；位置是否在
    /// 推进由采样判定。
    /// 本 Phase 不放刷新驱动（实测本进程拿不到任何显示刷新回调，
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

    // MARK: - 菜单动作与首启引导

    /// 首启引导：装上状态打点，然后「按需弹框 → 扫描起播」。
    /// 取消 / 被拒时不再扫描：取消分支已经打过未配置那一行读数，再扫只会对同一件事打第二遍
    /// （一个数不两种读法）。
    private func bootstrapAfterWiring() async {
        // 正常扫描路径的状态变更由协调器打（冻结的出口）。会话态也在**这个 handler** 里更新 ——
        // 打点处仍是恰好 2 处（取消分支 + 这里），再开一处会让取消分支语义漂成两个真相源。
        coordinator.onStateChange = { [weak self] state in
            self?.emit("PIC_LIBRARY_STATE=" + LibraryAvailability.token(state))
            self?.sessionState.update(state: state)
        }
        guard await requestFolderIfNeeded() else { return }
        await rescanAndApply()
        // 顺序写死 —— 先取目录、再扫描、最后起播。反序会让首次启动在没有目录/扫描结果时
        // 先走一遍 PIC_NO_SOURCE。
        await startWallpaper()
        emitBootSettings()
        // 启动查一次 ffmpeg。追加在既有步骤之后，不动上面写死的顺序。
        refreshFFmpegAvailability()
    }

    /// `PIC_SETTINGS_BOOT`：启动时把 7 键里的 6 个可调值各打一次（重启回读锚点）。
    /// 值全部来自 store —— 探针 seed 什么、这里就回读什么。一行、每个值只出现一次。
    private func emitBootSettings() {
        emit("PIC_SETTINGS_BOOT rate=\(store.rate) volume=\(store.volume) muted=\(store.isMuted ? 1 : 0) playMode=\(store.playMode.rawValue) rotationInterval=\(Int(store.rotationInterval)) pauseOnBattery=\(store.pauseOnBattery ? 1 : 0)")
    }

    /// 该不该弹文件夹选择框由 FolderRequestPolicy 纯函数决定。
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
            // 取消路径直接 return false，不调 coordinator.apply —— 这一行是取消路径记录该 token
            // 的唯一方式（与上面的 onStateChange 处理器各有独立语义）。
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
        // 面板是模态窗口：.accessory 的 app 弹它之前必须激活（单点），弹完必须恢复 ——
        // 少了恢复这一步，Dock 图标会永久留下。
        presentSettingsWindow()
        let url = await picker.pickFolder()
        hideSettingsAndRestorePolicy()
        guard let url else { return .cancelled }
        guard FolderRequestPolicy.isAcceptableSelection(url) else { return .rejected }
        store.sourceFolder = FolderRequestPolicy.normalizedPath(url)
        store.persist()
        // 只打 PICKED=1，不打路径（目录路径不进日志，设置窗是唯一例外）。
        emit("PIC_FOLDER_PICKED=1")
        return .accepted
    }

    /// 设置窗「选择…」的行为侧：与首启引导走**同一个**面板落点，选完立即重扫。
    /// 取消不动现状 —— 当前文件夹继续生效，因此不发任何状态行。
    func requestFolderNow() {
        Task {
            if await pickFolder() == .accepted { await rescanAndApply() }
        }
    }

    /// 「切换目录」与「重新扫描」走**同一条**路径 —— 两处实现必然会漂。
    /// 扫描结果交给协调器后，按返回的 `LibraryState` 分派装载（`.playing` → `router.start`；
    /// 三个隐藏态 → `router.stop`）。
    private func rescanAndApply() async {
        sessionState.isScanning = true
        defer { sessionState.isScanning = false }
        guard let folder = store.resolvedFolderURL() else {
            await dispatchPlayback(for: coordinator.apply(scanOutcome: .success(0),
                                                          folderConfigured: false), report: nil)
            return
        }
        // 模式与间隔从设置带过来（当场生效，不存第二份真相）。同步后打一行模式读数（只打 token）。
        rotation.setMode(store.playMode)
        rotation.setInterval(store.rotationInterval)
        emit("PIC_ROT_MODE=\(store.playMode.rawValue)")
        do {
            let report = try await library.scan(folder: folder)
            sessionState.playableCount = report.playableCount
            await dispatchPlayback(for: coordinator.apply(scanOutcome: .success(report.playableCount),
                                                           folderConfigured: true),
                                   report: report)
        } catch let error as MediaLibrary.MediaLibraryError {
            await dispatchPlayback(for: coordinator.apply(scanOutcome: .failure(error),
                                                           folderConfigured: true), report: nil)
        } catch {
            // scan 只抛 MediaLibraryError，这里是编译器要的兜底；真到了这一步
            // 说明出了没料到的错误，按「目录读不了」处理（隐藏 + 让出桌面）。
            await dispatchPlayback(for: coordinator.apply(scanOutcome: .failure(.folderUnreadable),
                                                           folderConfigured: true), report: nil)
        }
    }

    /// `LibraryState` → 装载分派。只看 `coordinator.apply` 的返回值，不在 AppDelegate
    /// 再判一次「有没有视频」（那会与 `LibraryAvailability` 的纯函数决策漂成两处）。
    ///
    /// ⚠️ 入参是 `report` 不是 `items`：`Converted/` 产物不在 `report.items` 里
    /// （那棵目录整棵排除），合并只在装载这一处发生。
    /// 分派结构一个分支都没动 —— 只换了 `.playing` 分支的数据来源。
    private func dispatchPlayback(for state: LibraryState, report: MediaLibraryReport?) async {
        switch state {
        case .playing:
            router.start(with: await mergedPlaybackItems(report))
        case .folderUnconfigured, .folderMissing, .noPlayableVideos:
            emit("PIC_ROT_STOP=1")
            router.stop()
        }
    }

    /// 「立即下一个」的行为侧：只叫轮换器，不碰 player、不碰 arbiter —— 换片由
    /// onAdvance → 装载完成（菜单动作不得绕过仲裁器把已 hold 的播放器重新拉起）。
    func nextVideoNow() {
        emit("PIC_MENU_ACTION=next_video")
        rotation.advanceNow()
        emit("PIC_ROT_ADVANCES=\(rotation.advances.count)")
    }

    /// 「删除当前壁纸」的行为侧：**先切下一个，再把刚才在播的那个移进废纸篓**。
    ///
    /// ⚠️ **顺序不可调换**。反了会删掉正在播的文件 —— 播放器还挂着它的句柄，
    /// 表现是「桌面定格 + 下一轮扫描才发现少了一个」。所以这里先把 url 存成局部常量，
    /// 再 advance，**最后**才动手删。
    ///
    /// 用废纸篓（`trashItem`）而非 `removeItem`：误删可从访达恢复，
    /// 删壁纸这种不可逆动作必须留退路。
    ///
    /// 删完必须失效扫描缓存 —— 否则清单里还留着那个已不存在的路径，
    /// 下次轮换会反复装载失败。
    func deleteCurrentWallpaperNow() {
        emit("PIC_MENU_ACTION=delete_current")

        // ① 先记住「删谁」—— advance 之后 router.current 就换成下一个了。
        guard let victim = router.current?.url else {
            emit("PIC_DELETE_SKIPPED=no_current")
            return
        }
        // ② 再切下一个。轮换器持有 items 快照，切片发生在这一句。
        rotation.advanceNow()

        // ③ 最后才动文件。
        do {
            try FileManager.default.trashItem(at: victim, resultingItemURL: nil)
            emit("PIC_DELETE_OK name=\(victim.lastPathComponent)")
        } catch {
            // 移入废纸篓失败（权限 / 文件已被外部移动 / 卷只读）——不动清单，
            // 下次扫描自然会收敛。发信号让 evidence 可追。
            emit("PIC_DELETE_FAIL name=\(victim.lastPathComponent) err=\(error.localizedDescription)")
            return
        }

        // ④ 清单里那条路径已失效 —— 显式失效 + 重扫，否则下次轮换会装载不存在的文件。
        library.invalidateCache()
        Task { await rescanAndApply() }
    }

    /// 「重新扫描」的唯一落点（菜单与设置窗共用）：显式失效缓存再重扫 ——
    /// 不失效的话菜单项会看起来「点了没反应」。单次 Task 串行：连点不会并发扫两遍；
    /// 每次点击都打一行读数，重复点击在 evidence 里可数。
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

// MARK: - seam 的产品侧适配

/// `WallpaperPresenting` 的极薄适配。刻意**不**给 `WallpaperWindowController`
/// 直接加 conformance —— 那会让 PicCore 的类型背上协议依赖，而判据锁着
/// MediaCoordinator.swift 零 AppKit；适配留在装配层。
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

/// `VideoLoading` 的产品侧适配。刻意不给 `PlayerController` 直接加 conformance ——
    /// 那会让 PicCore 的类型背上 PicApp 的 seam 语义（分层纪律）。
    /// 两件事、顺序不可换：先装载，再重放仲裁决策 —— `load(url:)` 会重置队列，不重放的话
    /// 一个处于 hold 的会话会在换片后「先播一下」再被压住（起播路径防的事，轮换路径同样要防）。
    /// 走 `arbiter` 而不是 `player.arbiterApply(_:)`，让「决策从哪来」只有一处。
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