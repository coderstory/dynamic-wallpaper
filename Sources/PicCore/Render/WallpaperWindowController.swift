import AppKit
import AVFoundation

/// 壁纸窗口的唯一创建点。
///
/// 窗口**不进 SwiftUI 的 body**：`MenuBarExtra` 只负责菜单栏图标，桌面层窗口由
/// `AppDelegate` 持有本控制器再建。屏幕只取 `NSScreen.main` —— 多屏不在本项目范围内。
///
/// 整类标 `@MainActor`：本类只做窗口操作，而 AppKit 那套（建窗 / `orderFrontRegardless` /
/// `collectionBehavior`）全是 MainActor 隔离的。不标的话每一处调用都是一条并发告警，
/// 而且真从后台线程调过去就是 UB。
@MainActor
public final class WallpaperWindowController {

    public private(set) var window: WallpaperWindow?

    /// 窗口持有的那个视频图层，首次 `attach` 后才有值。**刻意做成可选属性**而非
    /// `let`：图层由 `WallpaperWindow` 创建（它是渲染子树的根），控制器不另造一个 ——
    /// 否则同一个 player 上会挂两个 AVPlayerLayer，渲染哪一路变成不确定的事。
    public private(set) var layer: AVPlayerLayer?

    /// 图片图层，首次 `attach` 后才有值。与 `layer` 同款可选语义：图层由窗口创建。
    public private(set) var imageLayer: WallpaperImageLayer?

    public init() {}

    /// 换屏重建完成后的回调。**调用方 = AppDelegate**：新窗口的 `imageLayer.isHidden`
    /// 是 init 固定的默认隐藏、且没有任何图 —— 重建后当前若处于图片模式，接线方必须按
    /// store 重新断言 kind 并把当前图重新贴上。控制器不知道 store，这个职责留在调用侧。
    public var onRebuilt: (() -> Void)?

    /// 建窗 + 挂图层 + 提到最前。第一次调用才建，之后是幂等的。
    public func attach(player: AVQueuePlayer) {
        guard window == nil else { return }
        guard let screen = NSScreen.main else { return }
        let created = WallpaperWindow(screen: screen, player: player)
        window = created
        layer = created.videoLayer
        imageLayer = created.imageLayer
        created.orderFrontRegardless()
    }

    /// 切来源。**只翻可见性，不动播放器**：视频层保留着 player，切回视频时不用重新装载。
    public func setKind(_ kind: WallpaperKind) {
        window?.setKind(kind)
    }

    /// 显示一张图片。`image` 为 nil 时清屏（空态/解码失败）—— 传 nil 是合法调用，不是错误。
    public func showImage(_ image: CGImage?, fit: ImageFit) {
        imageLayer?.setImage(image, fit: fit)
    }

    /// UI 改完 `store.imageFit` 之后唯一的「当场生效」通道。走 `showImage(_:fit:)` 重设就得多解码
    /// 一次同一张图 —— 解码在主线程是一张卡的可见卡顿，而这里要变的只有落位几何。
    public func applyImageFit(_ fit: ImageFit) {
        imageLayer?.setFit(fit)
    }

    /// 重新断言系统默认的 Space 行为：重设集合行为后重新提到最前。
    ///
    /// **没有任何代码自动调用它** —— 没有 Space 变更订阅、没有定时器、没有 watcher。
    /// 要的正是这个形状：按系统默认行为表现，不做差异化处理。
    public func reassert() {
        guard let w = window else { return }
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        w.orderFrontRegardless()
    }

    /// 降级的**保留**语义：只 `orderOut(nil)` 把窗口从屏幕上撤下，`window` 与
    /// `layer` 原样保留 —— 与 `teardown()` 的**销毁**语义（`orderOut` + 置 nil）
    /// 并存且不冲突。恢复路径依赖这对 `hide()` / `show()`：文件夹恢复后 `show()`
    /// 能把同一个窗口原样叫回来，不需要重建。
    ///
    /// `window == nil`（还没 attach 过 / 已 teardown）时是安全空操作。
    /// 不碰 `collectionBehavior` 与 `level` —— 那两件事的唯一落点是 `reassert()`。
    public func hide() {
        window?.orderOut(nil)
    }

    /// `hide()` 的逆操作：把保留着的窗口重新提到最前。`window == nil` 时空操作，
    /// **不隐式 attach** —— 隐式 attach 会把「窗口建不出来」这个真实故障吞掉。
    public func show() {
        window?.orderFrontRegardless()
    }

    /// 屏幕参数变更（换主屏 / 改分辨率 / 合盖接显示器）→ 用新的 `NSScreen.main` 重建窗口。
    ///
    /// 窗口的 frame 在 `WallpaperWindow.init` 里就按当时的 `screen.frame` 固化了，不重建就一直是
    /// 旧屏的尺寸（表现是壁纸只铺满旧分辨率那块，或换外接屏后铺不满）。
    ///
    /// **`window == nil` 时什么都不做**：降级态（还没 attach 过 / 已 teardown）不该被一次换屏唤醒 ——
    /// 那会让「没有可播视频」的会话凭空冒出一扇黑窗。
    public func rebuildForCurrentScreen(player: AVQueuePlayer) {
        guard window != nil else { return }
        teardown()
        attach(player: player)
        // 只有真建出窗才通知：attach 失败（拿不到 NSScreen.main）时没有「重建完成」可言，
        // 旧 kind/旧图也没有新窗可贴。
        if window != nil { onRebuilt?() }
    }

    public func teardown() {
        window?.orderOut(nil)
        window = nil
        layer = nil
        imageLayer = nil
    }
}
