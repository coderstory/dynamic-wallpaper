import AppKit
import AVFoundation
import PicCore

/// 唯一装配点（D-10）。
///
/// 本 Phase 只接 Phase 2 已有的三根线：播放层挂载、仲裁器接播放端、菜单的暂停/继续。
/// **不接**全屏/锁屏/电源/显示器 watcher（Phase 3）、**不接**扫描与轮换（Phase 4）。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = SettingsStore(
        defaults: .standard,
        seed: SettingsStore.Seed()
    )
    let player = PlayerController()
    let arbiter = HoldArbiter()
    let wallpaper = WallpaperWindowController()
    /// 必须**强持有**：否则没人调 `stop()`，observer 泄漏（T-03-03）。
    let lockWatcher = LockWatcher(names: lockSignalNames())

    private var ticker: Timer?
    /// D-05：0.5 秒 `Timer` 已删。`PIC_HOLD` 改由对 `arbiter.decision` 的观察驱动，
    /// 观察者由 `armHoldObservation()` 一次性注册并在 `onChange` 里重新 arm。
    private var tickSeq = 0
    private var loopProbe: LoopProbe?
    /// `observeHold()` 在本进程内被调用的次数 —— 打在**去重门之前**。
    /// D-05 唯一的机器判据：12 秒零决策变化的窗口里它必须恒为 1；
    /// 0.5 秒轮询会涨到约 24（见 `observeHold()` 的注释）。
    private var holdObserverTicks = 0
    /// Plan 02-04 T2：显示刷新驱动的**测量器**，不是渲染路径的一部分。
    /// 它回答「打包成 .app 之后本进程能不能拿到显示刷新回调」（PDCA-A4），
    /// 测满窗口即自行 invalidate，产品不留常驻定时器。
    private var frameDriver: FrameDriver?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // D-05：菜单栏 app 无 Dock 图标。断言时注意 .accessory 的 rawValue 是 1 不是 0。
        // 刻意**不**调前台激活接口 —— 那会抢焦点，破坏 .accessory 的语义（Phase 1 的 MenuBarSpike 同样避开）。
        NSApp.setActivationPolicy(.accessory)
        // 生效策略当场打一行，SC1「Dock 无图标」就不靠肉眼。
        emit("ACTIVATION_POLICY_RAW=\(NSApp.activationPolicy().rawValue)")
        wiring()
        startFrameDriver()
        startWallpaper()
        startLoopProbeIfRequested()
        startHoldObserver()
        scheduleQuitAfterIfRequested()
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

    /// 装配点（D-10）。每根线都只接一次，重复调用是幂等的。
    ///
    /// ⚠️ 顺序（D-06 / `W-2026-10-03-10`）：`lockWatcher.start` 必须跑在
    /// `startWallpaper()` 之前 —— `start()` 会**同步**回调一次当前锁屏状态，
    /// 本会话自起播起屏幕一直锁着，没有跃迁可等。反了的话 `holds` 在起播那一刻是空集。
    func wiring() {
        arbiter.attach(player)
        lockWatcher.start { [arbiter] isLocked in
            arbiter.set(.screenLocked, active: isLocked)
        }
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
    private func startFrameDriver() {
        guard let screen = NSScreen.main else {
            emit("REFRESH_DRIVER=no_screen")
            return
        }
        let driver = FrameDriver()
        frameDriver = driver
        driver.attach(to: screen)
    }

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
        lockWatcher.stop()   // Pitfall 4：observer 注册与注销严格配对（T-03-03）
        emit("PIC_TERMINATED pid=\(ProcessInfo.processInfo.processIdentifier) reason=application_will_terminate")
    }

    // MARK: - 竖切主体

    private func startWallpaper() {
        // T-02-06：这一段只打印**原因类别**，绝不打印媒体路径。
        guard let folder = store.resolvedFolderURL() else {
            emit("PIC_NO_SOURCE reason=folder_unresolved")
            return
        }
        // 与 spike 的取法同一写法：非递归枚举 + 按文件名排序取首。
        guard let url = firstVideoURL(in: folder) else {
            emit("PIC_NO_SOURCE reason=no_mp4_in_folder")
            return
        }
        // D-14 / Pitfall 5：存在性一律查裸路径形式，喂 URL 的字符串形式会恒为 false。
        guard store.fileExists(at: url) else {
            emit("PIC_NO_SOURCE reason=file_missing")
            return
        }

        // D-13：传的是 AVQueuePlayer 实例本身，不是 AVPlayerItem ——
        // looper 的模板 item 属性在 init 时就冻结，挂在 item 上「改设置立即生效」是假的。
        wallpaper.attach(player: player.player)
        player.load(url: url)
        // 03-05 替换：这一行直连播放器，绕过仲裁器（D-06 / W-2026-10-03-10）。
        // Phase 3 已保证 `lockWatcher.start` 的同步回调在 `startWallpaper()` 之前跑完，
        // 所以此刻 `arbiter.decision.holds` 已可能非空 —— 03-05 把这行换成
        // `arbiter.applyCurrentDecision()`。本 plan 保留原样以免抢下一个 plan 的口径。
        player.player.play()
        // 设置在起播之后落位：挂在 player 上的速度/音量必须在播放中改才生效（D-13）。
        player.setRate(store.rate)
        player.setVolume(store.volume)
        player.setMuted(store.isMuted)
    }

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
        emit("TICK seq=\(tickSeq) pos=\(pos) status=\(LoopProbe.statusToken(player.player.timeControlStatus)) items=\(player.player.items().count)")
    }

    /// `scripts/run-probe.sh loop` 设 `PIC_LOOP_SECONDS=300` 才启动 300 秒观察；
    /// 不设这个变量时代码一行都不跑，tracer 与日常开发零开销。
    private func startLoopProbeIfRequested() {
        guard let raw = ProcessInfo.processInfo.environment[LoopProbe.secondsEnvKey],
              let seconds = Int(raw), seconds > 0 else { return }
        let probe = LoopProbe(player: player.player, durationSeconds: seconds) { [weak self] in
            MainActor.assumeIsolated { self?.terminateApp() }
        }
        loopProbe = probe
        probe.start()
    }

    private func emit(_ line: String) {
        WallpaperWindowController.emit(line)
    }
}