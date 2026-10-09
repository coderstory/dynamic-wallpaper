import AppKit
import AVFoundation
import SwiftUI
import PicCore

/// 唯一装配点：全仓唯一把系统信号变成 `HoldReason` 的地方（单向流 `Watcher → HoldArbiter → PlayerController`）。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    /// 改名迁移必须赶在 store 读偏好**之前**：bundle id 换域后新域是空的，store 的 init
    /// 一旦先跑就会拿种子值定终身。store 是存储属性，属性初始化先于一切方法体，所以迁移
    /// 挤在同一个立即求值的初始化表达式里、先于 SettingsStore 构造执行。
    let store: SettingsStore = {
        SettingsStore.migrateLegacyPreferencesIfNeeded(defaults: .standard)
        return SettingsStore(defaults: .standard, seed: SettingsStore.Seed())
    }()
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
    /// 图片侧扫描内核。与 `library`（视频）并存且各自缓存 —— 切换来源不重扫对方的目录。
    let imageLibrary = ImageLibrary()
    /// 图片侧装载端：后台解码 → 主线程上屏，并写续播键。
    private lazy var imageLoader = ImageWallpaperLoader(controller: wallpaper, store: store)
    /// 图片侧路由器。**与 `router` 共用同一个 `rotation`**，间隔 / 模式 / 让路暂停两边因此完全一致。
    /// 切来源时必须先停掉旧的再起新的 —— 两个装载端会争抢同一个 `onAdvance`。
    lazy var imageRouter = ImagePlaybackRouter(rotation: rotation, loader: imageLoader)
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
        // 换屏重建完成 → 重上图（见 reattachWallpaperAfterRebuild）。只在这里接一次。
        wallpaper.onRebuilt = { [weak self] in self?.reattachWallpaperAfterRebuild() }

        // 任何让路（手动暂停 / 锁屏 / 全屏 / 睡眠 / 电池）都冻结轮换定时器：壁纸看不见时
        // 换片没有意义，倒计时也应静止。恢复按冻结的剩余时间续跑。
        // 进入让路的同时把当前视频与进度写进持久化 —— 单循环重启续播的写点之一。
        arbiter.onShouldPlayChange = { [weak self, rotation] playing in
            guard let self else { return }
            if playing {
                rotation.resumeRotation()
            } else {
                self.recordCurrentForResume(position: self.player.arbiterCurrentPosition())
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

    /// 换屏重建后的重上图。视频层重建时由 `attach(player:)` 自动接回同一个 player；
    /// 图片层的新窗没有任何图（`imageLayer` 是 init 固定的隐藏 + 空图），必须在这里补：
    /// 重新断言 kind，再把当前那张经现有装载端（后台解码 → 上屏 → 写键）重新贴上 ——
    /// 不重扫、不重抽签，这是最轻的重上图路径。
    private func reattachWallpaperAfterRebuild() {
        wallpaper.setKind(store.wallpaperKind)
        guard store.wallpaperKind == .image, let url = imageRouter.current else { return }
        imageLoader.showImage(url: url)
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
    /// 失败不静默：具体原因已在 `AutoStartManager.routeB` 打过 stderr，这里再落一行
    /// 让「开关拨了但没生效」在日志里有迹可循。不改 UI 契约（返回值被 UI 忽略）。
    func setLaunchAtLogin(_ enabled: Bool) {
        if enabled, !autostart.setEnabled(true) {
            FileHandle.standardError.write(Data("壁纸儿: 开机自启开启失败（原因见上一行）\n".utf8))
        }
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
        // 幂等：关闭动画未完成时重开面板会再进这里 —— 先拆掉旧引用再装，
        // 否则旧引用被覆盖后再也拆不掉（全局监听永久截事件）。
        removeMenuMonitors()
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
            requestFolder: { [weak self] in self?.requestFolderNow() },
            switchSource: { [weak self] in
                guard let self else { return }
                self.switchWallpaperKind(to: self.store.wallpaperKind == .image ? .video : .image)
            }
        )
        .environment(store)
        .environment(arbiter)
        .environment(sessionState)
    }

    /// 面板上展示的快捷键必须是真的：⌘, 开设置、⌘Q 退出。监听只在面板打开期间活着。
    private func installMenuKeyMonitor() {
        // 幂等：同 installMenuDismissMonitors —— 动画期重开时旧 monitor 还挂在属性上，
        // 不先拆就覆盖，旧 popover 的 didClose 会把**新** monitor 一并清掉。
        removeMenuMonitors()
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

    /// 拆面板期监听。安装（幂等前置）与 `popoverDidClose`（正常 teardown）共用同一份。
    private func removeMenuMonitors() {
        if let menuKeyMonitor {
            NSEvent.removeMonitor(menuKeyMonitor)
            self.menuKeyMonitor = nil
        }
        for monitor in menuDismissMonitors {
            NSEvent.removeMonitor(monitor)
        }
        menuDismissMonitors = []
    }

    func popoverDidClose(_ notification: Notification) {
        // 竞态防护：close() 动画未完成时用户再点图标会建出**新** popover 并覆盖 menuPopover。
        // 随后旧 popover 的 didClose 才回调 —— object 是旧的，此刻清状态会把新 monitor 与
        // 新 popover 一并清掉（新面板点外面收不起来、旧 monitor 永久泄漏全局截 ⌘,/⌘Q）。
        // 只清「object 就是当前面板」的那一次。
        guard (notification.object as? NSPopover) === menuPopover else { return }
        removeMenuMonitors()
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
                // 新 shell 侧栏 216 + 内容区，理想宽超过旧 900 上限，钳制放宽到 1120。
                width: max(SettingsPresentation.windowMinWidth, min(fit.width, 1120)),
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
            requestWindowFit: { [weak self] in self?.fitSettingsWindow() },
            // 顶栏切壁纸来源：复用全仓唯一的切换落点，不另写一条切换路径。
            switchSource: { [weak self] kind in self?.switchWallpaperKind(to: kind) },
            // 当前图换铺法：不重解码不重扫，把新 fit 直接送渲染层。
            applyImageFit: { [weak self] in self?.wallpaper.applyImageFit(self?.store.imageFit ?? .fill) },
            // 分辨率档位改后重扫：ImageLibrary 缓存键含 minPixels，走既有重扫路径即可。
            applyImageFilter: { [weak self] in Task { self?.rescanLibrary() } })
            .environment(store)
            .environment(arbiter)
            .environment(settingsApplier)
            .environment(sessionState)
        let win = NSWindow(contentViewController: NSHostingController(rootView: root))
        win.title = "壁纸儿"
        // hiddenTitleBar 的 AppKit 写法：标题栏透明 + contentView 占满，红绿灯仍在原位 ——
        // SettingsView.titleRow 的 76pt 左内边距就是给它们留的。
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        // 替代 SettingsView.applyWindowChrome 的 0.5s 延时 hack：窗在自家手里，创建时直接设。
        win.isMovableByWindowBackground = true
        // 初始高度只是占位：showSettings 紧接着会 fitSettingsWindow 贴到内容真实高度。
        win.setContentSize(NSSize(width: SettingsPresentation.windowWidth, height: 680))
        // 液态玻璃开启时根背景是超薄材质，窗体必须透明才能透出桌面模糊；
        // 关闭时根背景是不透明 pGround，观感不变。
        win.isOpaque = false
        win.backgroundColor = .clear
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
        // 单循环续播：退出前把当前条目落盘（正常退出是最后一个写点）。
        recordCurrentForResume(position: player.arbiterCurrentPosition())
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
        // 两种来源共用同一扇窗（视频层与图片层都在树上），翻哪一层由 `setKind` 决定。
        // 传的是 AVQueuePlayer 实例本身，不是 AVPlayerItem —— looper 的模板 item 属性在 init
        // 时就冻结，挂在 item 上「改设置立即生效」是假的。
        wallpaper.attach(player: player.player)
        wallpaper.setKind(store.wallpaperKind)

        if store.wallpaperKind == .image {
            // 图片模式：装载由 `dispatchImages` 完成（`rescanAndApply()` 已经起过一轮）。
            // 这里只把起/停决策交给仲裁器 —— 它管的是轮换定时器，与播放器无关；
            // 没有视频可播时 `setRate` 对图片没有意义，还会让空播放器空转。
            arbiter.applyCurrentDecision()
            if !arbiter.decision.shouldPlay { rotation.pauseRotation() }
            return
        }

        guard let folder = store.resolvedFolderURL(for: .video) else { return }
        // 存在性检查归 `MediaLibrary.scan`（folderMissing），本守卫只判「扫完有没有可播条目」。
        guard let report = try? await library.scan(folder: folder), !report.items.isEmpty else { return }

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
        // 按**当前来源**的目录判：拿视频目录去判图片来源会得出「已配置」的假结论，
        // 首启于图片模式时因此永远不弹框。
        let currentPath = store.wallpaperKind == .image ? store.imageFolderPath : store.sourceFolder
        guard FolderRequestPolicy.shouldRequestFolder(sourceFolder: currentPath,
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
        // 写进**当前来源**的那一个键：两个目录并存，写错一个等于配了个看不见的目录。
        let path = FolderRequestPolicy.normalizedPath(url)
        if store.wallpaperKind == .image {
            store.imageFolderPath = path
        } else {
            store.sourceFolder = path
        }
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
                if store.wallpaperKind == .image { imageLibrary.invalidateCache() } else { library.invalidateCache() }
                await rescanAndApply()
            }
        }
    }

    /// 切壁纸来源（视频 ⇄ 图片）—— **唯一的切换落点**。
    ///
    /// 顺序不可换：① 先停旧的装载端（不能让它在新的渲染层上继续回调）→ ② 翻渲染层 →
    /// ③ 失效缓存 → ④ 重扫。③④ 的顺序是跨文件不变量（`invalidateCache()` 必须排在重扫之前）。
    ///
    /// 图片目录没配时不回退到视频：用户是显式切过来的，静默弹回去会被读成「切换没生效」，
    /// 停在空态并给「改用视频壁纸」的兜底才是可解释的。
    func switchWallpaperKind(to kind: WallpaperKind) {
        guard kind != store.wallpaperKind else { return }
        let previous = store.wallpaperKind
        store.wallpaperKind = kind
        store.persist()

        if previous == .video {
            router.stop()
            player.stop()
        } else {
            imageRouter.stop()
            // 停旧装载端必须同时作废在途解码：不 invalidate 的话，切走后慢解码返回
            // 仍会把旧图送上屏、把过期 URL 写进 lastImagePath。
            imageLoader.invalidate()
            wallpaper.showImage(nil, fit: store.imageFit)
        }
        wallpaper.setKind(kind)

        Task {
            if kind == .image { imageLibrary.invalidateCache() } else { library.invalidateCache() }
            await rescanAndApply()
        }
    }

    /// 「切换目录」与「重新扫描」走**同一条**路径 —— 两处实现必然会漂。
    /// 扫描结果交给协调器后，按返回的 `LibraryState` 分派装载。
    private func rescanAndApply() async {
        sessionState.isScanning = true
        defer { sessionState.isScanning = false }
        // 模式与间隔从设置带过来（当场生效，不存第二份真相）—— 两种来源共用同一个轮换器。
        rotation.mode = store.playMode
        rotation.setInterval(store.rotationInterval)
        if store.wallpaperKind == .image {
            await rescanImagesAndApply()
            return
        }
        guard let folder = store.resolvedFolderURL(for: .video) else {
            await applyAndDispatch(scanOutcome: .success(0), folderConfigured: false, report: nil)
            return
        }
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

    /// 图片来源的「扫描 → 分派」。与视频侧**结构对称**，判定与产物都不同：
    /// 口径是总像素量、没有转码 / 降帧、也没有 `Converted/` 产物要合并。
    private func rescanImagesAndApply() async {
        guard let folder = store.resolvedFolderURL(for: .image) else {
            await applyImages(scanOutcome: .success(0), folderConfigured: false, urls: [])
            return
        }
        do {
            let report = try await imageLibrary.scan(folder: folder, minPixels: store.imageMinPixels)
            sessionState.imageTotal = report.total
            sessionState.imagePassing = report.passing
            sessionState.imageFiltered = report.filteredOut
            await applyImages(scanOutcome: .success(report.passing), folderConfigured: true,
                              urls: report.items.map(\.url))
        } catch let error as MediaLibrary.MediaLibraryError {
            await applyImages(scanOutcome: .failure(error), folderConfigured: true, urls: [])
        } catch {
            // scan 只抛 MediaLibraryError，这里是编译器要的兜底。
            await applyImages(scanOutcome: .failure(.folderUnreadable), folderConfigured: true, urls: [])
        }
    }

    private func applyImages(scanOutcome: Result<Int, MediaLibrary.MediaLibraryError>,
                             folderConfigured: Bool, urls: [URL]) async {
        let state = coordinator.apply(scanOutcome: scanOutcome, folderConfigured: folderConfigured)
        await dispatchImages(for: state, urls: urls)
        updateFolderWatch(for: state)
    }

    /// 图片侧装载分派。与 `dispatchPlayback` 同款契约：`.playing` 走 `refresh` 而不是 `start`
    /// —— 每次 `start` 都会把轮换索引打回第一张。
    private func dispatchImages(for state: LibraryState, urls: [URL]) async {
        switch state {
        case .playing:
            // 幂等：启动就是图片模式时也靠这一句把渲染层翻过来。
            wallpaper.setKind(.image)
            if !imageRouter.isStarted, let resume = imageResumeTarget(in: urls) {
                imageRouter.start(with: urls, resumingAt: resume)
            } else {
                imageRouter.refresh(with: urls)
            }
        case .folderUnconfigured, .folderMissing, .noPlayableVideos:
            imageRouter.stop()
            // 同 switchWallpaperKind：停装载端就要作废在途解码，防止停用后旧图后到上屏。
            imageLoader.invalidate()
            // 清屏而不是留着上一张：留着会让「没有可用图片」看起来像「壁纸卡住了」。
            wallpaper.showImage(nil, fit: store.imageFit)
        }
    }

    /// 图片的单张续播目标：上次显示的那张仍在清单里 → 它的 URL；不在（被删 / 换目录）→ nil。
    /// **必须与视频的 `loopSingleResumeTarget` 分开**：拿 `lastPlayedPath`（视频路径）去匹配
    /// 图片清单永远匹配不到，结果是每次启动都从第一张开始 —— 不崩，但没法解释。
    private func imageResumeTarget(in urls: [URL]) -> URL? {
        guard store.playMode == .loopSingle, !store.lastImagePath.isEmpty else { return nil }
        return urls.first { $0.path == store.lastImagePath }
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
                self.invalidateActiveLibraryCache()
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

    /// 让路 / 退出的续播写点。**按来源分派**：图片拿 `lastPlayedPath`（视频路径）去匹配
    /// 图片清单永远匹配不到，结果是每次启动都从第一张重新开始 —— 不崩，但没法解释。
    private func recordCurrentForResume(position: TimeInterval) {
        guard let url = rotation.current else { return }
        if store.wallpaperKind == .image {
            store.lastImagePath = url.path
        } else {
            store.lastPlayedPath = url.path
            store.lastPlayedPosition = position
        }
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
        invalidateActiveLibraryCache()
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

    /// 按当前来源分派扫描缓存失效。**不能只失效视频库**：图片库（`ImageLibrary`）的缓存键
    /// 只含目录 + minPixels —— 文件的增删不换键，不失效就吃旧缓存，「删除当前壁纸 /
    /// 重新扫描」在图片模式下会看似点了没反应。`requestFolderNow` 已是正确写法，三处统一走这里。
    private func invalidateActiveLibraryCache() {
        if store.wallpaperKind == .image {
            imageLibrary.invalidateCache()
        } else {
            library.invalidateCache()
        }
    }

    /// 「重新扫描」的唯一落点（菜单与设置窗共用）：显式失效缓存再重扫 ——
    /// 不失效的话菜单项会看起来「点了没反应」。
    func rescanLibrary() {
        invalidateActiveLibraryCache()
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

/// 图片侧的装载端：后台解码 → 主线程上屏 → 写续播键。
///
/// **解码必须离开主线程**：一张 4K HEIC 的解码足以卡一帧，而换图是定时触发的，
/// 卡帧会被读成「换壁纸时整个系统顿一下」。
@MainActor
private final class ImageWallpaperLoader: ImageLoading {

    private let controller: WallpaperWindowController
    private let store: SettingsStore
    /// 装载代次。`showImage` 每次自增并给在途任务捕获快照，`present` 前比对 ——
    /// 后台解码的完成顺序不保证与发起顺序一致，快速换图时慢解码后到会覆盖新图、
    /// 还把过期的 URL 写进 `lastImagePath`（下次启动续播到一张早已不在屏上的图）。
    /// 切来源 / 停用（`invalidate()`）后，在途任务同样不许落屏、不许写键。
    private var generation = 0

    init(controller: WallpaperWindowController, store: SettingsStore) {
        self.controller = controller
        self.store = store
    }

    func showImage(url: URL) {
        // `fit` 在主线程读一次再带进任务：`store` 是 @MainActor 隔离的，后台里读它就是跨隔离访问。
        let fit = store.imageFit
        generation += 1
        let issuedGeneration = generation
        Task { [weak self] in
            let image = await ImageDecoder.decodeInBackground(url)
            self?.present(image, fit: fit, url: url, generation: issuedGeneration)
        }
    }

    /// 作废所有在途解码任务（切来源 / 停用时由 AppDelegate 调）。
    func invalidate() {
        generation += 1
    }

    /// 上屏 + 写续播键。代次不一致（已被更新的一次装载 / invalidate 作废）即丢弃：
    /// 不上屏、不写键。解码失败（nil）时也**不写**键：写了等于把一张打不开的图钉成
    /// 「下次启动接着显示它」，下一次还是黑屏。
    private func present(_ image: CGImage?, fit: ImageFit, url: URL, generation issuedGeneration: Int) {
        guard issuedGeneration == self.generation else { return }
        controller.showImage(image, fit: fit)
        guard image != nil else { return }
        store.lastImagePath = url.path
        store.persist()
    }
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
