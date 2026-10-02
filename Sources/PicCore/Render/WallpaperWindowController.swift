import AppKit
import AVFoundation

/// 壁纸窗口的唯一创建点（D-10）。
///
/// 窗口**不进 SwiftUI 的 body**（ARCHITECTURE §8）：`MenuBarExtra` 只负责菜单栏图标，
/// 桌面层窗口由 `AppDelegate` 持有本控制器再建。屏幕只取 `NSScreen.main` ——
/// 多屏不在本项目范围内（DISP-01 / DISP-02 属 v2）。
public final class WallpaperWindowController {

    public private(set) var window: WallpaperWindow?

    /// 窗口持有的那个视频图层，首次 `attach` 后才有值。
    ///
    /// 计划里写的是 `private let layer: AVPlayerLayer`，改成一个可选属性：
    /// 图层由 `WallpaperWindow` 创建（它是渲染子树的根），控制器不另造一个 ——
    /// 否则同一个 player 上会挂两个 AVPlayerLayer，渲染哪一路变成不确定的事。
    /// 对外的方法签名 `attach` / `reassert` / `teardown` 一字未改。
    public private(set) var layer: AVPlayerLayer?

    public init() {}

    /// 建窗 + 挂图层 + 提到最前。第一次调用才建，之后是幂等的。
    public func attach(player: AVQueuePlayer) {
        guard window == nil else { return }
        guard let screen = NSScreen.main else {
            WallpaperWindowController.emit("PIC_NO_SCREEN reason=no_main_display")
            return
        }
        let created = WallpaperWindow(screen: screen, player: player)
        window = created
        layer = created.videoLayer
        created.orderFrontRegardless()
    }

    /// 重新断言系统默认的 Space 行为：重设集合行为后重新提到最前。
    ///
    /// **没有任何代码自动调用它** —— 没有 Space 变更订阅、没有定时器、没有 watcher。
    /// SYS-02 要的正是这个形状：按系统默认行为表现，不做差异化处理。
    /// Plan 02-04 的 `.app` 打包复测会手动调一次。
    public func reassert() {
        guard let w = window else { return }
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        w.orderFrontRegardless()
    }

    public func teardown() {
        window?.orderOut(nil)
        window = nil
        layer = nil
    }

    public static func emit(_ line: String) {
        FileHandle.standardError.write((line + "\n").data(using: .utf8)!)
    }
}