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
    /// 设置「当场生效」的唯一落点。
    lazy var settingsApplier = SettingsApplier(store: store, player: player, arbiter: arbiter)
    // 四个 Watcher 必须强持有，谁创建谁 stop()，否则回调永久泄漏
    let lockWatcher = LockWatcher()
    let fullscreenDetector = FullscreenDetector()
    let displayWatcher = DisplayWatcher()
    let powerWatcher = PowerWatcher()
    // rotation 必须强持有，它持 onAdvance 闭包与 Timer 调度器
    let library = MediaLibrary()
    /// 面板 seam：全仓唯一碰 NSOpenPanel 的地方注入进来的句柄。
    let picker: any FolderPicker = NSOpenPanelFolderPicker()
    let rotation = RotationController(
        scheduler: SystemRotationScheduler(),
        random: SeededRandomSource(seed: UInt64(bitPattern: Int64(Date().timeIntervalSince1970)))
    )
    /// 扫描结果 → 窗口/播放器动作的唯一落点。
    lazy var coordinator = MediaCoordinator(
        presenting: WallpaperPresenter(controller: wallpaper),
        stopping: PlaybackStopper(player: player)
    )
    /// 设置窗的会话态读数（计数 / 空态 / 扫描时间）。不进 store —— 不是用户设过的偏好。
    let sessionState = SettingsSessionState()
    /// ffmpeg 判定的单一真相源：设置窗状态卡、维护行置灰态、徽章读的都是它。
    private lazy var ffmpegLocator: ExternalToolLocator = FFmpegAvailability.productionLocator()
    var transcodeLocator: ExternalToolLocator { ffmpegLocator }
    /// 最近一次的判定结论。`refreshFFmpegAvailability()` 的唯一写入口。
    private(set) var ffmpegAvailability: FFmpegToolStatus = .unavailable
    /// 转码队列的持有者。排空钩子挂在这里，漏挂的表现是转完了但清单里没有新片。
    lazy var transcodeQueue: TranscodeQueue = {
        let queue = TranscodeQueue(
            runner: ProcessTranscodeRunner(),
            // 闭包而非值：换目录后必须跟着走，否则产物写进已经不再使用的旧目录。
            naming: TranscodeOutputNaming(
                rootProvider: { [weak self] in self?.store.resolvedFolderURL()
                    ?? URL(fileURLWithPath: NSTemporaryDirectory()) }),
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
    /// 轮换 → 装载的路由器。强持有，它持 rotation.onAdvance 闭包。
    private lazy var router = PlaybackRouter(
        rotation: rotation,
        loader: PlayerLoadingAdapter(player: player, arbiter: arbiter)
    )

    /// 转码视图模型。生命周期必须跟着 AppDelegate —— `@StateObject` 只能挂 View。
    lazy var transcodeViewModel = TranscodeViewModel(
        queue: transcodeQueue,
        locator: transcodeLocator,
        wallpaperRootProvider: { [weak self] in self?.store.resolvedFolderURL() },
        sourcePicker: picker
    )

    /// 降帧队列。必须强持有，被回收等于静默停工。目录此刻取不到就退到临时目录：
    /// 队列在 `scan()` 之前不会真读它。
    lazy var fpsTranscodeQueue: FpsTranscodeQueue = {
        let queue = FpsTranscodeQueue(
            runner: ProcessTranscodeRunner(),
            // 闭包而非值：同上，换目录后必须扫新目录、产物落新目录。
            rootProvider: { [weak self] in self?.store.resolvedFolderURL()
                ?? URL(fileURLWithPath: NSTemporaryDirectory()) },
            availability: { [weak self] in self?.ffmpegAvailability ?? .unavailable },
            freeSpaceProvider: { url in
                (try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
                    .volumeAvailableCapacityForImportantUsage
            },
            specProvider: { url in await AVFoundationAssetProbe().metadata(url) })
        // 必须挂：不失效缓存 + 重扫，降完帧壁纸还在播旧片
        queue.onBatchFinished = { [weak self] in
            MainActor.assumeIsolated { self?.handleFpsBatchFinished() }
        }
        return queue
    }()

    lazy var fpsTranscodeViewModel = FpsTranscodeViewModel(
        queue: fpsTranscodeQueue,
        locator: transcodeLocator
    )

    /// 降帧批次完成 → 失效扫描缓存并重扫，让播放池换上一对一替换后的派生片。
    private func handleFpsBatchFinished() {
        library.invalidateCache()
        Task { await rescanAndApply() }
    }

    /// 开机自启的唯一写入口。
    private lazy var autostart = AutoStartManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 刻意不调前台激活接口：那会抢焦点，破坏 .accessory 的语义
        NSApp.setActivationPolicy(.accessory)
        // 每次启动对齐一次偏好与系统登录项：false 时是幂等清理，true 时重新注册
        autostart.setEnabled(store.launchAtLogin)
        wiring()
        // 必须走 Task + await：模态面板要在主 run loop 上跑，同步 runModal() 会卡住启动。
        // 插在 wiring() 之后：四个 Watcher 已同步置位，弹框期间系统信号不丢。
        Task { await bootstrapAfterWiring() }
    }

    /// 装配点（单向流）。每根线只接一次。
    /// 顺序：三个 `NSWorkspace` / IOKit 的在前，`lockWatcher` 最后 —— 它立刻用真实会话状态置位。
    func wiring() {
        arbiter.attach(player)
        // 轮换接进「当场生效」的唯一落点（模式/间隔的改写从这里出去）。
        settingsApplier.attach(rotation: rotation)

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

    /// 电源信号 → `SettingsApplier.applyBatteryPolicy`。判定在 `BatteryHoldPolicy` 纯函数里，
    /// `.battery` 的写入口只此一处。
    private func recordPowerState(_ isOnBattery: Bool) {
        lastIsOnBattery = isOnBattery
        settingsApplier.applyBatteryPolicy(isOnBattery: isOnBattery)
    }

    /// 设置窗「电池时播放」toggle 的落点：用最近一次已知电源状态重算同一套映射。
    func reapplyBatteryHold() {
        settingsApplier.applyBatteryPolicy(isOnBattery: lastIsOnBattery)
    }

    /// 设置窗「开机自启」toggle 的行为侧：拨动即刻落系统侧，状态由 `AutoStartManager` 打。
    func setLaunchAtLogin(_ enabled: Bool) {
        autostart.setEnabled(enabled)
    }

    /// ffmpeg 判定的**唯一**写入口：启动查一次 + 每次点「打开…」重查。
    func refreshFFmpegAvailability() {
        ffmpegAvailability = ffmpegLocator.locate()
        // 会话态回填，设置窗卡片可观察。
        sessionState.ffmpegAvailable = ffmpegIsAvailable
    }

    /// 设置窗读数与入口置灰共用这一份（不出现两套判定）。
    var ffmpegIsAvailable: Bool {
        ffmpegAvailability.isAvailable
    }

    /// 设置窗「维护」行「打开…」的行为侧：先重查，可用就开窗返回 true，
    /// 不可用返回 false 让视图弹三途径安装说明。
    @discardableResult
    func openTranscodeWindow(_ openWindow: () -> Void) -> Bool {
        refreshFFmpegAvailability()
        if case .available = ffmpegAvailability {
            openWindow()
            return true
        }
        return false
    }

    /// `Converted/` 的独立扫描器。不复用 `MediaLibrary` 的缓存 —— 它的扫描结果被
    /// `excludedByConverted` 全排除。
    private lazy var convertedLibrary = ConvertedLibrary()

    /// 播放清单合并的**唯一**入口：根扫描在前、`Converted/` 产物追加。走 `PlaybackPool` 是因为
    /// 降帧产物要一对一顶替原片，纯 path 去重会让同段素材播两遍。转换侧扫不出来吞成空数组。
    private func mergedPlaybackItems(_ report: MediaLibraryReport?) async -> [VideoItem] {
        let root = report?.items ?? []
        guard let folder = store.resolvedFolderURL() else { return root }
        let converted = (try? await convertedLibrary.scan(folder: folder)) ?? []
        return PlaybackPool.build(root: root, converted: converted,
                                  table: FrameRateTable.load())
    }

    /// 转码队列排空 → 新产物当轮进播放清单。失效缓存必须**同步**排在重扫之前：
    /// `MediaLibrary.scan` 默认吃内存缓存，不失效拿回的是上一轮的 report。
    private func handleTranscodeBatchFinished() {
        library.invalidateCache()
        Task { await rescanAndApply() }
    }

    /// 打开设置窗的前置动作：`.accessory` 的 app 不会被激活，`openWindow` 出来的窗口拿不到焦点。
    /// 策略切换**只在本文件发生**。
    @objc func presentSettingsWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 设置窗关闭时把策略改回 `.accessory` —— 少了这一句，Dock 图标会永久留下。
    /// 异常路径也走这一个入口，不留半开状态。
    @objc func hideSettingsAndRestorePolicy() {
        NSApp.setActivationPolicy(.accessory)
    }

    /// 全仓唯一的「结束进程」落点。菜单 quit 调本方法，不写第二遍字面量。
    @objc func terminateApp() {
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 与 wiring() 里的四个 start() 严格配对
        lockWatcher.stop()
        fullscreenDetector.stop()
        displayWatcher.stop()
        powerWatcher.stop()
    }

    /// 异步化 + 走 `MediaLibrary.scan` + `router.start`。装载分派由 router 内部的 `onAdvance`
    /// 完成（内部装载 `items[0]` 并重放仲裁决策）。
    private func startWallpaper() async {
        guard let folder = store.resolvedFolderURL() else { return }
        // 存在性检查归 `MediaLibrary.scan`（folderMissing），本守卫只判「扫完有没有可播条目」。
        guard let report = try? await library.scan(folder: folder), !report.items.isEmpty else { return }

        // 传的是 AVQueuePlayer 实例本身，不是 AVPlayerItem —— looper 的模板 item 属性在 init
        // 时就冻结，挂在 item 上「改设置立即生效」是假的。
        wallpaper.attach(player: player.player)
        // 启动路径上 `rescanAndApply()` 已经通过 `dispatchPlayback` 起过一轮了，
        // 这里再 start 一次会把首条重新装载一遍 —— 随机模式下还会重新抽签，观感是开场闪一下。
        if !router.isStarted {
            // `Converted/` 产物与根扫描清单合并后才进轮换。
            router.start(with: await mergedPlaybackItems(report))
        }
        // 起播决策**只**从仲裁器出。四个 Watcher 已在 wiring() 里同步置位，
        // 此刻 decision 已含本会话的全部系统信号。
        arbiter.applyCurrentDecision()
        // 设置必须挂在 player 上（不是 item）、且在起播决策**之后**落位。
        // setRate 必须门在「应当播放」之后：非零 rate 会让已 hold 的播放器重新拉起。
        // 但**两个分支都要记住速度** —— 启动即处于 hold 时也必须记下，否则解锁后
        // `arbiterApply` 回放的是默认 1.0，用户设的速度在第一次锁屏前一直是错的。
        player.setVolume(store.volume)
        player.setMuted(store.isMuted)
        if arbiter.decision.shouldPlay {
            player.setRate(store.rate)
        } else {
            player.setDesiredRate(store.rate)
        }
    }

    /// 首启引导：装会话态的写入落点，然后「按需弹框 → 扫描起播」。取消 / 被拒时不扫描。
    private func bootstrapAfterWiring() async {
        // 状态变更与会话态都只在这个 handler 里更新。
        coordinator.onStateChange = { [weak self] state in
            self?.sessionState.update(state: state)
        }
        guard await requestFolderIfNeeded() else { return }
        await rescanAndApply()
        // 顺序写死：先取目录、再扫描、最后起播。反序会让首次启动在没有目录时先走一遍空态。
        await startWallpaper()
        // 启动查一次 ffmpeg。追加在既有步骤之后，不动上面写死的顺序。
        refreshFFmpegAvailability()
    }

    /// 该不该弹文件夹选择框由 FolderRequestPolicy 纯函数决定。
    /// 取消不是错误：安静返回 false —— 不弹错误窗、不崩、不重试。
    private func requestFolderIfNeeded() async -> Bool {
        let env = ProcessInfo.processInfo.environment[SettingsStore.envSourceFolderKey]
        guard FolderRequestPolicy.shouldRequestFolder(sourceFolder: store.sourceFolder,
                                                       envOverride: env) else {
            return true
        }
        switch await pickFolder() {
        case .accepted:
            return true
        // 取消与拒绝同解：都不是错误，安静返回 false。
        case .cancelled, .rejected:
            return false
        }
    }

    private enum FolderPickOutcome { case accepted, cancelled, rejected }

    /// 弹面板 → 校验 → 写盘。**不**扫描、不发状态行：取消的语义由调用方决定
    /// （首启的取消 = 从没配过；设置窗的取消 = 保持现状）。
    private func pickFolder() async -> FolderPickOutcome {
        // 模态面板：.accessory 的 app 弹它之前必须激活（单点），弹完必须恢复 ——
        // 少了恢复这一步，Dock 图标会永久留下。
        presentSettingsWindow()
        let url = await picker.pickFolder()
        hideSettingsAndRestorePolicy()
        guard let url else { return .cancelled }
        guard FolderRequestPolicy.isAcceptableSelection(url) else { return .rejected }
        store.sourceFolder = FolderRequestPolicy.normalizedPath(url)
        store.persist()
        return .accepted
    }

    /// 设置窗「选择…」的行为侧：与首启引导走**同一个**面板落点，选完立即重扫。
    /// 取消不动现状 —— 当前文件夹继续生效。
    func requestFolderNow() {
        Task {
            if await pickFolder() == .accepted {
                // 换目录后必须失效缓存再重扫。`scan` 的缓存现在按目录判等（换目录自然失效），
                // 这里显式失效是纵深：让「切换目录」与「重新扫描」走同一条语义，不依赖缓存判等这一个闸。
                library.invalidateCache()
                await rescanAndApply()
            }
        }
    }

    /// 「切换目录」与「重新扫描」走**同一条**路径 —— 两处实现必然会漂。
    /// 扫描结果交给协调器后，按返回的 `LibraryState` 分派装载。
    private func rescanAndApply() async {
        sessionState.isScanning = true
        defer { sessionState.isScanning = false }
        guard let folder = store.resolvedFolderURL() else {
            await dispatchPlayback(for: coordinator.apply(scanOutcome: .success(0),
                                                          folderConfigured: false), report: nil)
            return
        }
        // 模式与间隔从设置带过来（当场生效，不存第二份真相）。
        rotation.setMode(store.playMode)
        rotation.setInterval(store.rotationInterval)
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
            // scan 只抛 MediaLibraryError，这里是编译器要的兜底；真到了这一步按「目录读不了」处理。
            await dispatchPlayback(for: coordinator.apply(scanOutcome: .failure(.folderUnreadable),
                                                           folderConfigured: true), report: nil)
        }
    }

    /// `LibraryState` → 装载分派。只看 `coordinator.apply` 的返回值，不在这里再判「有没有视频」。
    /// 入参是 `report` 不是 `items`：`Converted/` 产物不在 `report.items` 里，合并只在这一处。
    ///
    /// `.playing` 走 `refresh` 而不是 `start`：重扫每天都发生（改个设置、转完一个批次、
    /// 菜单「重新扫描」），而每次 `start` 都会把轮换索引打回第一条 —— 用户看到的症状是
    /// 「壁纸突然跳回某个视频从头播」。`refresh` 只在「正在播的那条已经不在了」时才重开一轮。
    private func dispatchPlayback(for state: LibraryState, report: MediaLibraryReport?) async {
        switch state {
        case .playing:
            router.refresh(with: await mergedPlaybackItems(report))
        case .folderUnconfigured, .folderMissing, .noPlayableVideos:
            router.stop()
        }
    }

    /// 「立即下一个」的行为侧：只叫轮换器，不碰 player、不碰 arbiter —— 换片由
    /// onAdvance → 装载完成（菜单动作不得绕过仲裁器把已 hold 的播放器重新拉起）。
    func nextVideoNow() {
        rotation.advanceNow()
    }

    /// 「删除当前壁纸」的行为侧：**先切下一个，再把刚才在播的那个移进废纸篓**。
    /// **顺序不可调换**。反了会删掉正在播的文件 —— 播放器还挂着它的句柄。
    /// 用废纸篓（`trashItem`）而非 `removeItem`：误删可从访达恢复。
    func deleteCurrentWallpaperNow() {
        // ① 先记住「删谁」—— advance 之后 router.current 就换成下一个了。
        guard let victim = router.current?.url else { return }
        // ② 二次确认。放在这里而不是菜单侧：菜单只是转交意图，任何调用方都得过这道门。
        guard confirmTrashWallpaper(victim) else { return }
        // ③ 再切下一个。轮换器持有 items 快照，切片发生在这一句。
        rotation.advanceNow()

        // ④ 最后才动文件。
        do {
            try FileManager.default.trashItem(at: victim, resultingItemURL: nil)
        } catch {
            // 移入废纸篓失败（权限 / 文件已被外部移动 / 卷只读）——不动清单，下次扫描自然会收敛。
            return
        }

        // 删掉的可能是降帧产物（产物顶替原片后，播放池里那条就是产物）。
        // 表行此刻仍写着 `.done`，不去对账的话这条素材会以未降帧的原片形态一直播着 ——
        // 下一次降帧扫描才会纠正，而用户可能根本不打开那个 tab。
        var table = FrameRateTable.load()
        try? table.reconcileWithDerivatives()

        // ⑤ 必须失效缓存 —— 否则清单里那条路径已不存在，下次轮换会装载失败。
        library.invalidateCache()
        Task { await rescanAndApply() }
    }

    /// 删除前的二次确认。`NSAlert` 而非 SwiftUI sheet：菜单是 `MenuBarExtra`，弹层挂不上去，
    /// 所以临时提策略、弹完恢复，与 `presentSettingsWindow` 同一套做法。
    /// 「移到废纸篓」刻意不做默认按钮（`alertStyle = .warning` 时首按钮才是默认），
    /// 回车 = 取消：误按回车不该删文件。
    private func confirmTrashWallpaper(_ url: URL) -> Bool {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        defer { NSApp.setActivationPolicy(.accessory) }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "删除当前壁纸？"
        alert.informativeText = "「\(url.lastPathComponent)」将移入废纸篓，播放会切到下一个。"
        alert.addButton(withTitle: "移到废纸篓")
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// 「重新扫描」的唯一落点（菜单与设置窗共用）：显式失效缓存再重扫 ——
    /// 不失效的话菜单项会看起来「点了没反应」。
    func rescanLibrary() {
        library.invalidateCache()
        Task { await rescanAndApply() }
    }
}


/// `WallpaperPresenting` 的极薄适配。刻意**不**给 `WallpaperWindowController`
/// 直接加 conformance —— 那会让 PicCore 的类型背上 AppKit 依赖。
@MainActor
private final class WallpaperPresenter: WallpaperPresenting {
    private let controller: WallpaperWindowController

    init(controller: WallpaperWindowController) { self.controller = controller }

    func show() { controller.show() }
    func hide() { controller.hide() }
}

/// `PlaybackStopping` 的极薄适配。
@MainActor
private final class PlaybackStopper: PlaybackStopping {
    private let player: PlayerController

    init(player: PlayerController) { self.player = player }

    func stopPlayback() { player.stop() }
}

/// `VideoLoading` 的产品侧适配。刻意不给 `PlayerController` 直接加 conformance ——
/// 那会让 PicCore 的类型背上 PicApp 的 seam 语义。
/// 两件事、顺序不可换：先装载，再重放仲裁决策 —— 不重放的话，一个处于 hold 的会话
/// 会在换片后「先播一下」再被压住。走 `arbiter` 而不是 `player.arbiterApply(_:)`，
/// 让「决策从哪来」只有一处。
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
        // 换片后旧锚点失效：轮换在 hold 期间仍会到点换片，此时锁屏记下的 resumeAnchor
        // 指向旧片位置，解锁 seek 会把新片硬拽到错误时间点。装载后先解绑锚点再重放决策。
        arbiter.invalidateResumeAnchor()
        arbiter.applyCurrentDecision()
    }
}
