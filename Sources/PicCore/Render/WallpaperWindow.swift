import AppKit
import AVFoundation
import QuartzCore

/// 桌面层壁纸窗口 —— 播放与渲染之间的接缝的最外层。
///
/// 窗口配置**逐行照抄** Phase 1 的 spike（那份已实跑通过 `ORDER=ok` /
/// `FINDER_RESTART_ALIVE=1`），只把 spike 用来证明「画面在动」的帧号叠加层换成真正的
/// 视频图层。层级写法不重新推导。
public final class WallpaperWindow: NSWindow {

    /// 视频图层。本窗口是它唯一的持有者，控制器经 `videoLayer` 取用 —— 它也是
    /// `PlayerController.player`（AVQueuePlayer）与屏幕之间唯一的一条接缝。
    public let videoLayer: AVPlayerLayer

    private let host: HostView

    public init(screen: NSScreen, player: AVQueuePlayer) {
        let host = HostView(frame: screen.frame)
        let video = AVPlayerLayer(player: player)
        self.host = host
        self.videoLayer = video

        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)

        // 层级值取自 CoreGraphics 运行时符号 —— AppKit 没有对应的 NSWindow.Level 常量，
        // 写成数字字面量即被禁。与图标层那个被禁用的标识符只差二十几级，
        // 用了会盖住桌面图标。
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))

        // 走系统默认行为 —— 跨 Space 跟随、不参与 Space 切换循环、全屏时可作为
        // 辅助窗口。本项目不做任何 Space 级特殊处理，因此源码里没有任何 Space
        // 变更通知的订阅。
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        // 第二组配置。isOpaque=true + 黑色底的功耗结论仍停在「没跑过」栏
        // （powermetrics 需要 root，实测 AB_GROUPS_MEASURED=0），照写但不声称已验证。
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
        contentView = host
    }

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }
}

/// 视频宿主视图。翻转坐标系只为让布局计算与 NSView 惯例一致；
/// 视频图层自己会钉满整个 bounds，缩放时不留黑边。
final class HostView: NSView {
    var videoLayer: AVPlayerLayer?

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        videoLayer?.frame = bounds
    }
}