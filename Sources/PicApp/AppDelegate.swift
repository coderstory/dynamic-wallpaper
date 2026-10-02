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

    private var ticker: Timer?
    private var tickSeq = 0
    private var loopProbe: LoopProbe?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // D-05：菜单栏 app 无 Dock 图标。断言时注意 .accessory 的 rawValue 是 1 不是 0。
        // 刻意**不**调前台激活接口 —— 那会抢焦点，破坏 .accessory 的语义（Phase 1 的 MenuBarSpike 同样避开）。
        NSApp.setActivationPolicy(.accessory)
        // 生效策略当场打一行，SC1「Dock 无图标」就不靠肉眼。
        emit("ACTIVATION_POLICY_RAW=\(NSApp.activationPolicy().rawValue)")
        wiring()
        startWallpaper()
        startLoopProbeIfRequested()
        startObservability()
    }

    /// 装配点（D-10）。每根线都只接一次，重复调用是幂等的。
    func wiring() {
        arbiter.attach(player)
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