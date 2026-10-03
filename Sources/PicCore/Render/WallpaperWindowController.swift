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

    /// 降级的**保留**语义：只 `orderOut(nil)` 把窗口从屏幕上撤下，`window` 与
    /// `layer` 原样保留 —— 与 `teardown()` 的**销毁**语义（`orderOut` + 置 nil）
    /// 并存且不冲突。SOURCE-06 的恢复路径依赖这对 `hide()` / `show()`：文件夹
    /// 恢复后 `show()` 能把同一个窗口原样叫回来，不需要重建。
    ///
    /// `window == nil`（还没 attach 过 / 已 teardown）时是安全空操作。
    /// 不碰 `collectionBehavior` 与 `level` —— 那两件事的唯一落点是 `reassert()`。
    public func hide() {
        window?.orderOut(nil)
    }

    /// `hide()` 的逆操作：把保留着的窗口重新提到最前。`window == nil` 时空操作，
    /// **不隐式 attach** —— 隐式 attach 会把「窗口建不出来」这个真实故障吞掉
    /// （`attach(player:)` 已经在 `NSScreen.main == nil` 时打了 `PIC_NO_SCREEN`，
    /// `show()` 不该绕过这条）。
    public func show() {
        window?.orderFrontRegardless()
    }

    public func teardown() {
        window?.orderOut(nil)
        window = nil
        layer = nil
    }

    public static func emit(_ line: String) {
        FileHandle.standardError.write((line + "\n").data(using: .utf8)!)
        mirror(line)
    }

    /// `PIC_EVIDENCE_FILE` 证据桥（Phase 5 / Plan 05-01）：非空时把每行 mirror 进
    /// 文件，让 XCUITest 与探针的读数可 grep。**未设该变量时行为与原实现逐字节
    /// 一致**（只写 stderr）。惰性取值一次（static let）；失败静默 —— 证据桥是
    /// 观测面，不允许它影响产品路径。
    private static let evidenceFileURL: URL? = {
        guard let path = ProcessInfo.processInfo.environment["PIC_EVIDENCE_FILE"],
              !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }()

    private static func mirror(_ line: String) {
        guard let url = evidenceFileURL else { return }
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            guard fm.createFile(atPath: url.path, contents: nil) else { return }
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: (line + "\n").data(using: .utf8)!)
    }
}