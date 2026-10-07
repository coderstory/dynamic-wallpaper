import AppKit
import AVFoundation
import SwiftUI
import PicCore

/// 唯一装配点：全仓唯一把系统信号变成 `HoldReason` 的地方（单向流 `Watcher → HoldArbiter → PlayerController`）。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
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
    /// 屏幕参数变更的订阅。与四个 Watcher 同一条纪律：谁创建谁注销。
    private var screenObserver: NSObjectProtocol?
    // rotation 必须强持有，它持 onAdvance 闭包与 Timer 调度器
    let library = MediaLibrary()
    /// 拔盘 / 目录消失后的重生看护。只在 `folderMissing` 期间活着（见 `updateFolderWatch`）。
    private let folderWatch = FolderReappearanceWatcher()
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
    /// 装载适配器单列出来是为了注 `onLoaded` 出参（单循环续播的持久化写点）。
    private lazy var router: PlaybackRouter = {
        let adapter = PlayerLoadingAdapter(player: player, arbiter: arbiter)
        adapter.onLoaded = { [weak self] url in self?.recordNowPlaying(url) }
        return PlaybackRouter(rotation: rotation, loader: adapter)
    }()

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

    // ── 菜单栏自绘面板（原型 D）──
    // NSStatusItem + NSPopover，替代 SwiftUI MenuBarExtra：原生 .menu 样式没有自绘空间
    // （图标行 / 危险色 / 倒计时环全画不了），设计稿的面板只能 AppKit 这条路走。
    private var statusItem: NSStatusItem?
    private var menuPopover: NSPopover?
    /// 面板打开期间的 ⌘, / ⌘Q 监听。popoverDidClose 必拆 —— 留着会全局截键。
    private var menuKeyMonitor: Any?
    /// 面板兜底关闭的观察者。popoverDidClose 必拆。
    /// 每条自带投递中心：`NSWorkspace` 的通知只走它自己的中心，
    /// 拿 `default` 去 removeObserver 是拆不掉的（也收不到）。
    private var popoverDismissObservers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    /// 面板打开期间的「点外面就收」监听：**别的 app / 桌面走全局，本 app 自己的窗口走本地**。
    /// 全局监听收不到「发给本 app 的事件」（NSEvent.h 原文），所以少了本地那条，
    /// 点自己那扇没激活的设置窗时面板不关。popoverDidClose 必拆。
    private var menuDismissMonitors: [Any] = []
    /// 设置窗由本类 AppKit 直管。SwiftUI Window 场景的 `openWindow` 依赖场景上下文，
    /// NSPopover 的内容视图拿不到 —— 这是拆掉 MenuBarExtra 的连带迁移。
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 刻意不调前台激活接口：那会抢焦点，破坏 .accessory 的语义
        NSApp.setActivationPolicy(.accessory)
        setupMenuBar()
        installPopoverDismissGuards()
        // 每次启动对齐一次偏好与系统登录项：false 时是幂等清理，true 时重新注册
        autostart.setEnabled(store.launchAtLogin)
        wiring()
        // 必须走 Task + await：模态面板要在主 run loop 上跑，同步 runModal() 会卡住启动。
        // 插在 wiring() 之后：四个 Watcher 已同步置位，弹框期间系统信号不丢。
        Task { await bootstrapAfterWiring() }
        // 冷启动窗口：这一小段时间内的激活属于「启动本身」，之后每次激活都按「用户点图标」处理。
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.isColdLaunchActivation = false
        }
    }

    /// 装配点（单向流）。每根线只接一次。
    /// 顺序：三个 `NSWorkspace` / IOKit 的在前，`lockWatcher` 最后 —— 它立刻用真实会话状态置位。
    func wiring() {
        arbiter.attach(player)
        // 轮换接进「当场生效」的唯一落点（模式/间隔的改写从这里出去）。
        settingsApplier.attach(rotation: rotation)

        // 任何让路（手动暂停 / 锁屏 / 全屏 / 睡眠 / 电池）都冻结轮换定时器：壁纸看不见时
        // 换片没有意义，倒计时也应静止。恢复按冻结的剩余时间续跑。
        // 进入让路的同时把当前视频与进度写进持久化 —— 单循环重启续播的写点之一。
        arbiter.onShouldPlayChange = { [weak self, rotation] playing in
            guard let self else { return }
            if playing {
                rotation.resumeRotation()
            } else {
                if let url = rotation.current?.url {
                    self.store.lastPlayedPath = url.path
                    self.store.lastPlayedPosition = self.player.arbiterCurrentPosition()
                    self.store.persist()
                }
                rotation.pauseRotation()
            }
        }

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
        // 屏幕参数变更：窗口 frame 在创建时就固化了，不重建就停在旧屏尺寸上（换主屏 / 改分辨率 /
        // 合盖接显示器都会触发）。投递中心必须是 NotificationCenter.default —— 这条由 AppKit 在
        // 本进程投递，不在 NSWorkspace 的中心上。
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildWallpaperForCurrentScreen() }
        }
    }

    /// 换屏 → 用当前 `NSScreen.main` 重建壁纸窗口。重建动作在控制器里（它知道自己的 frame 从哪来）。
    private func rebuildWallpaperForCurrentScreen() {
        wallpaper.rebuildForCurrentScreen(player: player.player)
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

    /// 打开设置窗的前置动作：`.accessory` 的 app 不会被激活，弹出的窗口拿不到焦点。
    /// 策略切换**只在本文件发生**。
    @objc func presentSettingsWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    // ── 菜单栏面板的生命周期 ──

    private func setupMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            // 与 MenuBarExtra 时代同一加载纪律：显式 NSImage + isTemplate ——
            // 字符串名 Image("…") 解析不到散装 PNG，会渲染成全透明空槽。
            let img = Bundle.main.image(forResource: "menubar-v1Template") ?? NSImage()
            // 散装 PNG 的点尺寸不可靠（rep 选中哪档就按哪档像素当点用），显式定 22pt：
            // 画布字形放大 1.15 后占画布 ~65% 高，22pt 渲染 ≈ 14pt 字形高，与邻居看齐。
            img.size = NSSize(width: 22, height: 22)
            img.isTemplate = true
            button.image = img
            button.action = #selector(toggleMenuPanel(_:))
            button.target = self
            // 左右键弹同一面板：右击菜单栏图标是用户肌肉记忆，不能没反应。
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
    }

    /// 面板兜底关闭：`.transient` 只覆盖「点击面板外」这一种失去方式，Cmd-Tab 切走、
    /// 点别的 app、进全屏 / 切 Space 都不产生点击 —— 面板就悬在那。三种失去方式各订一条：
    ///
    /// - `didResignActive`：本 app 借过激活时的那条路（见 `toggleMenuPanel`）。
    /// - `activeSpaceDidChange` / `didActivateApplication`：都订在 **NSWorkspace 自己的中心**上，
    ///   不是 `NotificationCenter.default`（订错地方的表现是守卫静默失效，面板悬空）。
    ///   设置窗开着时 `toggleMenuPanel` 不借激活，`didResignActive` 永远不会来，
    ///   只剩 `didActivateApplication` 这条能把面板收掉。
    ///   自己激活不算失去（面板点进来时系统会激活本 app），按 pid 滤掉。
    private func installPopoverDismissGuards() {
        let center = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        popoverDismissObservers = [
            (center, center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.closeMenuPanelIfShown() }
            }),
            (workspace, workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.closeMenuPanelIfShown() }
            }),
            (workspace, workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                let activated = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                MainActor.assumeIsolated {
                    guard activated?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
                    self?.closeMenuPanelIfShown()
                }
            }),
        ]
    }

    private func closeMenuPanelIfShown() {
        if menuPopover?.isShown == true { menuPopover?.close() }
    }

    /// 面板打开期间装两条鼠标监听（成对拆在 `popoverDidClose`）。
    /// 存在的理由：设置窗开着时 `toggleMenuPanel` 不借激活，`.transient` 那套就失效了
    /// —— AppKit 只在 app 活跃时才把「点了面板外」递进来，面板会一直悬着（用户实测）。
    /// 全局监听只收别的 app 的事件，所以本 app 自己的窗口必须再补一条本地监听。
    private func installMenuDismissMonitors() {
        let panelWindow = { [weak self] in self?.menuPopover?.contentViewController?.view.window }
        let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.closeMenuPanelIfShown() }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                let window = event.window
                // 点面板内放过：SwiftUI 要收这一下。
                // 点托盘图标也放过：交给 `toggleMenuPanel` 自己判 —— 这里先关掉的话，
                // 随后那一下 mouseUp 会判成「没有面板」，把面板重开。
                if window !== panelWindow() && window !== self?.statusItem?.button?.window {
                    self?.closeMenuPanelIfShown()
                }
            }
            return event
        }
        menuDismissMonitors = [global, local].compactMap { $0 }
    }

    @objc private func toggleMenuPanel(_ sender: NSStatusBarButton) {
        if let menuPopover, menuPopover.isShown {
            menuPopover.close()
            return
        }
        let popover = NSPopover()
        // .transient = 点外部自动关，与原生菜单同语义。
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: makeMenuPanel())
        menuPopover = popover
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        // 借激活只为面板本身（⌘, / ⌘Q 的本地键监听、hover）。但 AppKit 的激活语义是
        // 「把本 app 的 main/key 窗口一并抬到最前」—— 设置窗开着时用户只是看面板，
        // 背后那个窗不该跳到最前。所以**只有屏幕上没有本 app 的窗口时才借激活**；
        // 代价是那一档里 ⌘, / ⌘Q 要等用户点进面板（系统激活）之后才递送。
        if settingsWindow?.isVisible != true {
            NSApp.activate(ignoringOtherApps: true)
        }
        installMenuKeyMonitor()
        installMenuDismissMonitors()
    }

    private func makeMenuPanel() -> some View {
        MenuPanelView(
            rotation: rotation,
            dismiss: { [weak self] in self?.menuPopover?.close() },
            terminate: { [weak self] in self?.terminateApp() },
            openSettings: { [weak self] tab in self?.showSettings(tab: tab) },
            nextVideo: { [weak self] in self?.nextVideoNow() },
            rescanFolder: { [weak self] in self?.rescanLibrary() },
            deleteCurrent: { [weak self] in self?.deleteCurrentWallpaperNow() },
            requestFolder: { [weak self] in self?.requestFolderNow() }
        )
        .environment(store)
        .environment(arbiter)
        .environment(sessionState)
    }

    /// 面板上展示的快捷键必须是真的：⌘, 开设置、⌘Q 退出。监听只在面板打开期间活着。
    private func installMenuKeyMonitor() {
        menuKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  let key = event.charactersIgnoringModifiers else { return event }
            switch key {
            case ",":
                self.menuPopover?.close()
                self.showSettings(tab: 0)
                return nil
            case "q":
                self.terminateApp()
                return nil
            default:
                return event
            }
        }
    }

    func popoverDidClose(_ notification: Notification) {
        if let menuKeyMonitor {
            NSEvent.removeMonitor(menuKeyMonitor)
            self.menuKeyMonitor = nil
        }
        for monitor in menuDismissMonitors {
            NSEvent.removeMonitor(monitor)
        }
        menuDismissMonitors = []
        menuPopover = nil
        // 归还为面板借的激活。close() 动画完成才回调 —— 此刻设置窗可能已被行动作打开，
        // 它在台前时不能 deactivate（会把用户刚叫出来的窗又压下去）。
        if settingsWindow?.isVisible != true {
            NSApp.deactivate()
        }
    }

    // ── 设置窗（AppKit 直管）──

    /// 打开设置窗并落地到指定页（0 播放 / 1 片库 / 2 通用）。
    /// 落地页走 sessionState.requestedTab 一次性通道：窗未开由 onAppear 消费，窗已开由 onChange 消费。
    func showSettings(tab: Int) {
        sessionState.requestedTab = tab
        presentSettingsWindow()
        if settingsWindow == nil {
            settingsWindow = makeSettingsWindow()
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        fitSettingsWindow()
    }

    /// 把窗口尺寸贴合到内容理想尺寸（三页高度各不相同，切换页签时也会重贴）。
    /// 刻意手写而不用 NSHostingController.sizingOptions = .preferredContentSize ——
    /// 那个机制在倒计时环每秒刷新时会在 sizeThatFits 里重入约束更新，AppKit 直接抛异常
    /// （实测崩溃 Pic-2026-10-07-102958.ips）。这里改在布局周期外异步读 fittingSize，没有重入。
    private func fitSettingsWindow() {
        DispatchQueue.main.async { [weak self] in
            guard let win = self?.settingsWindow, let view = win.contentView else { return }
            let fit = view.fittingSize
            // 布局未完成时 fittingSize 是假小值，不采纳。
            guard fit.height > 100 else { return }
            let maxH = (NSScreen.main?.visibleFrame.height ?? 900) - 60
            win.setContentSize(NSSize(
                width: max(SettingsPresentation.windowMinWidth, min(fit.width, 900)),
                height: max(320, min(fit.height, maxH))))
        }
    }

    private func makeSettingsWindow() -> NSWindow {
        let root = SettingsView(
            requestFolder: { [weak self] in self?.requestFolderNow() },
            rescanLibrary: { [weak self] in self?.rescanLibrary() },
            reapplyBatteryHold: { [weak self] in self?.reapplyBatteryHold() },
            setLaunchAtLogin: { [weak self] in self?.setLaunchAtLogin($0) },
            transcodeViewModel: transcodeViewModel,
            fpsViewModel: fpsTranscodeViewModel,
            refreshFFmpeg: { [weak self] in self?.refreshFFmpegAvailability() },
            rotation: rotation,
            requestWindowFit: { [weak self] in self?.fitSettingsWindow() })
            .environment(store)
            .environment(arbiter)
            .environment(settingsApplier)
            .environment(sessionState)
        let win = NSWindow(contentViewController: NSHostingController(rootView: root))
        win.title = "动态壁纸"
        // hiddenTitleBar 的 AppKit 写法：标题栏透明 + contentView 占满，红绿灯仍在原位 ——
        // SettingsView.titleRow 的 76pt 左内边距就是给它们留的。
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        // 替代 SettingsView.applyWindowChrome 的 0.5s 延时 hack：窗在自家手里，创建时直接设。
        win.isMovableByWindowBackground = true
        // 初始高度只是占位：showSettings 紧接着会 fitSettingsWindow 贴到内容真实高度。
        win.setContentSize(NSSize(width: SettingsPresentation.windowWidth, height: 700))
        win.contentMinSize = NSSize(width: SettingsPresentation.windowMinWidth, height: 320)
        win.delegate = self
        win.center()
        return win
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === settingsWindow else { return }
        settingsWindow = nil
        // 与旧 onDisappear 同一个落点：关窗即回 .accessory，不留 Dock 图标。
        hideSettingsAndRestorePolicy()
    }

    /// 设置窗关闭时把策略改回 `.accessory` —— 少了这一句，Dock 图标会永久留下。
    /// 异常路径也走这一个入口，不留半开状态。
    @objc func hideSettingsAndRestorePolicy() {
        NSApp.setActivationPolicy(.accessory)
    }

    // ── 从启动台 / Dock 点图标 ──
    //
    // Pic 是 LSUIElement 菜单栏 app：自己没有任何窗口。用户在启动台点图标只会「激活」这个进程，
    // 没人接住这个动作 —— 表现就是「点了没反应」。这里补两条入口把它翻译成「把设置窗叫出来」。

    /// 冷启动后的首次激活要放过：那是双击 App 启动本身，不是「点图标叫窗口」。
    /// 1.2s 后无条件作废：万一冷启动那次激活压根没回调，也不会把用户的第一次点击吞掉。
    private var isColdLaunchActivation = true
    /// `showSettings` 会 `NSApp.activate`，激活回调是异步回来的 —— 不加这道闸会在
    /// 「窗口还没 order-front」时重入一次 present。
    private var isPresentingSettings = false

    /// Dock 点已运行的 app 走这条。启动台点图标是否也走这里在 LSUIElement 下不确定，
    /// 所以另有 `applicationDidBecomeActive` 兜底，两条都指向同一个动作。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        presentSettingsOnExternalActivate()
        return false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if isColdLaunchActivation {
            isColdLaunchActivation = false
            return
        }
        presentSettingsOnExternalActivate()
    }

    private func presentSettingsOnExternalActivate() {
        // 面板与设置窗的激活都带着可见 UI，靠这两个条件挡掉；重入另由 isPresentingSettings 挡。
        // 判面板用 `menuPopover == nil` 而不是 `isShown`：前者同步成立（`show()` 之前就已赋值），
        // `isShown` 要等面板真正上屏 —— 点托盘那一下的激活若卡在中间，会把设置窗叫出来。
        guard !isPresentingSettings,
              settingsWindow?.isVisible != true,
              menuPopover == nil else { return }
        isPresentingSettings = true
        defer { isPresentingSettings = false }
        // 面板点「去片库转码」时可能带着落地页请求，别把它覆盖成播放页。
        showSettings(tab: sessionState.requestedTab ?? 0)
    }

    /// 全仓唯一的「结束进程」落点。菜单 quit 调本方法，不写第二遍字面量。
    @objc func terminateApp() {
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 单循环续播：退出前把当前视频与进度落盘（正常退出是最后一个写点）。
        if let url = rotation.current?.url {
            store.lastPlayedPath = url.path
            store.lastPlayedPosition = player.arbiterCurrentPosition()
            store.persist()
        }
        // 与 wiring() 里的四个 start() 加一条订阅严格配对
        lockWatcher.stop()
        fullscreenDetector.stop()
        displayWatcher.stop()
        powerWatcher.stop()
        folderWatch.stop()
        for observer in popoverDismissObservers {
            observer.center.removeObserver(observer.token)
        }
        popoverDismissObservers = []
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
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
        // **重启于暂停态**（重启那一刻正锁屏 / 全屏 / 电池让路）：watcher 置位发生在
        // router.start 之前，onShouldPlayChange 的跃迁已经错过、冻结钩子接不住 ——
        // 这里补一刀：让路状态起动的轮换直接冻结，菜单环静止，与运行中进入让路同语义。
        if !arbiter.decision.shouldPlay {
            rotation.pauseRotation()
        }
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
            await applyAndDispatch(scanOutcome: .success(0), folderConfigured: false, report: nil)
            return
        }
        // 模式与间隔从设置带过来（当场生效，不存第二份真相）。
        rotation.mode = store.playMode
        rotation.setInterval(store.rotationInterval)
        do {
            let report = try await library.scan(folder: folder)
            sessionState.playableCount = report.playableCount
            await applyAndDispatch(scanOutcome: .success(report.playableCount),
                                   folderConfigured: true, report: report)
        } catch let error as MediaLibrary.MediaLibraryError {
            await applyAndDispatch(scanOutcome: .failure(error), folderConfigured: true, report: nil)
        } catch {
            // scan 只抛 MediaLibraryError，这里是编译器要的兜底；真到了这一步按「目录读不了」处理。
            await applyAndDispatch(scanOutcome: .failure(.folderUnreadable),
                                   folderConfigured: true, report: nil)
        }
    }

    /// `apply` → 分派 → 看护。三件事必须捆在一起：分开写时，总会有一条分支漏掉看护 ——
    /// 漏掉的表现是「拔盘再插回，界面永远停在缺失态」。
    private func applyAndDispatch(scanOutcome: Result<Int, MediaLibrary.MediaLibraryError>,
                                  folderConfigured: Bool,
                                  report: MediaLibraryReport?) async {
        let state = coordinator.apply(scanOutcome: scanOutcome, folderConfigured: folderConfigured)
        await dispatchPlayback(for: state, report: report)
        updateFolderWatch(for: state)
    }

    /// 目录缺失时才开看护，其余状态一律停 —— 看护只在坏状态下活着，目录正常时一次都不跑。
    private func updateFolderWatch(for state: LibraryState) {
        guard state == .folderMissing else {
            folderWatch.stop()
            return
        }
        // 路径在**发起等待时**取一次快照：回调里再取会拿到换目录之后的值，等于盯错了目录。
        let folderPath = store.resolvedFolderURL()?.path
        folderWatch.awaitReturn(
            isBack: { folderPath.map { FileManager.default.fileExists(atPath: $0) } ?? false },
            onReturned: { [weak self] in
                guard let self else { return }
                // 与「重新扫描」同一条语义：先失效缓存再重扫，否则拿回的是缺失态那一轮的 report。
                self.library.invalidateCache()
                Task { await self.rescanAndApply() }
            })
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
            let items = await mergedPlaybackItems(report)
            // 单循环续播：**首次**起转时从上次播放的视频与进度接着来
            // （文件已不在清单里 / 非单循环模式 → 走普通 start）。
            // 之后的重扫走 refresh，不打断当前播放。
            if !router.isStarted, let resume = loopSingleResumeTarget(in: items) {
                router.start(with: items, resumingAt: resume.url)
                if resume.position > 0 {
                    player.arbiterSeek(to: resume.position)
                }
            } else {
                router.refresh(with: items)
            }
        case .folderUnconfigured, .folderMissing, .noPlayableVideos:
            router.stop()
        }
    }

    /// 单循环续播目标：上次播放的文件仍在清单里 → (url, position)；不在（被删/换目录）→ nil。
    private func loopSingleResumeTarget(in items: [VideoItem]) -> (url: URL, position: TimeInterval)? {
        guard store.playMode == .loopSingle, !store.lastPlayedPath.isEmpty else { return nil }
        guard let url = items.first(where: { $0.url.path == store.lastPlayedPath })?.url else { return nil }
        return (url, max(0, store.lastPlayedPosition))
    }

    /// 记录「正在播哪个」—— 单循环续播的持久化写点。每次装载都走这（轮换换片也是装载），
    /// 进度归零：真进度在让路 / 退出时写（见 onShouldPlayChange 与 applicationWillTerminate）。
    private func recordNowPlaying(_ url: URL) {
        store.lastPlayedPath = url.path
        store.lastPlayedPosition = 0
        store.persist()
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
        // 不显示文件名：与菜单同一隐私纪律 —— 片库文件名多为无语义串，显示出来只有噪音。
        alert.informativeText = "当前壁纸将移入废纸篓，播放会切到下一个。可在废纸篓中找回。"
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
    /// 装载完成出参（装配层注入，单循环续播的持久化写点）。
    var onLoaded: ((URL) -> Void)?

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
        onLoaded?(url)
    }
}
