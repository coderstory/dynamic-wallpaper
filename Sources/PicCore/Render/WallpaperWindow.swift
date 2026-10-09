import AppKit
import AVFoundation
import QuartzCore

/// 桌面层壁纸窗口 —— 播放与渲染之间的接缝的最外层。
///
/// 窗口配置已实跑验证过（`ORDER=ok` / `FINDER_RESTART_ALIVE=1`），层级写法不重新推导。
public final class WallpaperWindow: NSWindow {

    /// 视频图层。本窗口是它唯一的持有者，控制器经 `videoLayer` 取用 —— 它也是
    /// `PlayerController.player`（AVQueuePlayer）与屏幕之间唯一的一条接缝。
    public let videoLayer: AVPlayerLayer

    /// 图片图层，与 `videoLayer` 并列常驻。默认隐藏（`setKind` 才点亮它）——
    /// 图片模式下视频层隐藏但仍持有 player，切回视频时不用重新装载。
    public let imageLayer: WallpaperImageLayer

    private let host: HostView

    public init(screen: NSScreen, player: AVQueuePlayer) {
        let host = HostView(frame: screen.frame)
        let video = AVPlayerLayer(player: player)
        let image = WallpaperImageLayer()
        self.host = host
        self.videoLayer = video
        self.imageLayer = image

        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)

        // 层级值取自 CoreGraphics 运行时符号 —— AppKit 没有对应的 NSWindow.Level 常量，
        // 写成数字字面量即被禁。与图标层那个被禁用的标识符只差二十几级，
        // 用了会盖住桌面图标。
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))

        // 走系统默认行为 —— 跨 Space 跟随、不参与 Space 切换循环、全屏时可作为
        // 辅助窗口。本项目不做任何 Space 级特殊处理，因此源码里没有任何 Space
        // 变更通知的订阅。
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        // isOpaque=true + 黑色底的功耗结论未跑过（powermetrics 需要 root），
        // 照写但不声称已验证。
        isOpaque = true
        hasShadow = false
        ignoresMouseEvents = true
        backgroundColor = .black

        // 这一组四条（不吃鼠标事件 / 不能当 key / 不能当 main / borderless）合起来
        // 保证这扇窗不可能截获桌面上其他 app 的输入，也不改变焦点。
        host.wantsLayer = true
        video.frame = host.bounds
        video.videoGravity = .resizeAspectFill
        host.videoLayer = video
        host.layer?.addSublayer(video)

        image.frame = host.bounds
        image.isHidden = true
        host.imageLayer = image
        host.layer?.addSublayer(image)
        // 手动 `addSublayer` 挂上来的子层**不继承宿主视图的 contentsScale**（layer-backed
        // 视图只有自己那一层会随窗口 scale 走），不设的话默认 1x 光栅化再被放大到屏，
        // Retina 上图片发虚。`attach` 与 `rebuildForCurrentScreen` 都经由本 init 建窗，
        // 在这里设一次即覆盖两条路径。AVPlayerLayer 自管 scale，不碰。
        image.contentsScale = screen.backingScaleFactor

        contentView = host
    }

    /// 切来源：两层都在树上，只翻 `isHidden`。**不做 `removeFromSuperlayer()`** ——
    /// 见 `WallpaperImageLayer` 的注释。
    public func setKind(_ kind: WallpaperKind) {
        videoLayer.isHidden = kind == .image
        imageLayer.isHidden = kind != .image
    }

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }
}

/// 视频宿主视图。翻转坐标系只为让布局计算与 NSView 惯例一致。
final class HostView: NSView {
    var videoLayer: AVPlayerLayer?
    var imageLayer: WallpaperImageLayer?

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        videoLayer?.frame = bounds
        imageLayer?.frame = bounds
        // 不经重建窗口的 scale 变化（同屏改分辨率/深浅色重排）也要跟屏：发现 scale 变了才
        // 重设并重画 —— contentsScale 决定光栅化分辨率，不改的话图片层会停在旧 scale 上继续发虚。
        if let scale = window?.backingScaleFactor, let imageLayer, imageLayer.contentsScale != scale {
            imageLayer.contentsScale = scale
            imageLayer.setNeedsDisplay()
        }
    }
}