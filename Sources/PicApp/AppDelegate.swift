import AppKit
import PicCore

/// 唯一装配点（D-10）。
/// Plan 02-01 的 T2 只放空壳；T4 在此写 wiring()。
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 全仓唯一一处 `NSApp.terminate(nil)`（AppKit 全局对象只有 PicApp 层该碰）。
    @objc func terminateApp() {
        NSApp.terminate(nil)
    }
}
