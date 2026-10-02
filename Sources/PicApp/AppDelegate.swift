import AppKit
import AVFoundation
import PicCore

/// 唯一装配点（D-10）。
///
/// 本 Phase 只接三根线：播放层挂载、仲裁器接播放端、菜单的暂停/继续。
/// **不接**全屏/锁屏/电源/显示器 watcher（Phase 3）、**不接**扫描与轮换（Phase 4）。
/// 渲染层（桌面层窗口 + AVPlayerLayer）由 Plan 02-02 建好后经 `attachPlayerLayer` 注进来。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = SettingsStore(
        defaults: .standard,
        seed: SettingsStore.Seed()
    )
    let player = PlayerController()
    let arbiter = HoldArbiter()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // D-05：菜单栏 app 无 Dock 图标。断言时注意 .accessory 的 rawValue 是 1 不是 0。
        NSApp.setActivationPolicy(.accessory)
        wiring()
    }

    /// 装配点（D-10）。每根线都只接一次，重复调用是幂等的。
    func wiring() {
        arbiter.attach(player)
    }

    /// 渲染层建好 AVPlayerLayer 后注进来（Plan 02-02 调用）。
    func attachPlayerLayer(_ layer: AVPlayerLayer) {
        player.attach(to: layer)
    }

    /// 全仓唯一的「结束进程」落点 —— AppKit 全局对象只有 PicApp 层该碰它，
    /// `MenuBarModel` 只调闭包。Plan 02-03 的定时器复用本方法，不重复写字面量。
    @objc func terminateApp() {
        NSApp.terminate(nil)
    }
}
