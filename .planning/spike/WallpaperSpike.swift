// WallpaperSpike.swift —— Phase 01 门禁 spike，一次性 throwaway 验证件。
//
// 目的：证明「挂在桌面图标层之下的 NSWindow」在本机成立（D-06 帧号叠加），
//       并补齐 D-07 的四组播放配置（none / v1 / transparent / avplayerview）。
// 边界：只读窗口元数据 + 在自己的窗口里画东西，绝不改任何系统设置。
// 编译：swiftc -parse-as-library -target arm64-apple-macosx15.0 -o out/wallpaperspike WallpaperSpike.swift
//
// 增量纪律：Plan 01 已验证通过的窗口骨架（层级 / 层级调用 / 集合行为）原样保留，
// Plan 04 只往里填播放配置，不改写层级写法。

import AppKit
import AVFoundation
import AVKit
import QuartzCore

// 坐标系翻转容器：左上角即 (0,0)，方便把帧号贴在窗口左上角。
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// CADisplayLink 的 target 必须是 NSObject + @objc selector。
final class FrameTicker: NSObject {
    private let window: WallpaperWindow
    private var frame: Int = 0
    private var fallbackTimer: Timer?

    init(window: WallpaperWindow) {
        self.window = window
        super.init()
    }

    // 显示刷新回调 —— macOS 27 SDK 只有 NSScreen/NSView/NSWindow.displayLink(target:selector:)
    // 这一条路（CADisplayLink.init(target:selector:) 与 preferredFramesPerSecond 标了
    // API_UNAVAILABLE(macos)）。本 spike 保持它是首选驱动，和 Phase 2 同一写法。
    func attach(to screen: NSScreen) {
        let link = screen.displayLink(target: self, selector: #selector(FrameTicker.onDisplayLink(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 30, preferred: 30)
        link.add(to: .main, forMode: .common)
        startFallbackWatchdog()
    }

    // 实测（本机，2026-10-03）：本进程拿不到任何显示刷新回调 —— CADisplayLink 与
    // CVDisplayLink 的 timestamp 恒为 0，NSApp.isActive 恒为 false（即使调用过
    // activate(ignoringOtherApps:)）。故 1 秒内没收到 tick 就退到 30Hz Timer 兜底，
    // 帧号仍是每 tick 变化的客观证据。DRIVER= 字段会打进 stderr 供采集脚本记录。
    private func startFallbackWatchdog() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self, self.frame == 0, self.fallbackTimer == nil else { return }
            FileHandle.standardError.write("DRIVER=timer_fallback_hz30\n".data(using: .utf8)!)
            let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                self?.step()
            }
            self.fallbackTimer = t
            RunLoop.main.add(t, forMode: .common)
        }
    }

    @objc private func onDisplayLink(_ link: CADisplayLink) {
        step()
    }

    private func step() {
        frame += 1
        window.render(frameNumber: frame)
        // 帧号每 tick 写 stderr：stdout 只允许出现一次 PIC_GATE（见 <action>），
        // 但「画面在动」需要可 grep 的客观证据，所以走 stderr。
        FileHandle.standardError.write("TICK frame=\(frame)\n".data(using: .utf8)!)
    }
}

// 播放封装：AVQueuePlayer + AVPlayerLooper（与 Phase 2 生产写法一致）。
// looper 必须被强持有，否则模板 item 会被立刻踢出队列 —— 见 PITFALLS Pitfall 4。
// 换视频时的正确顺序是 disableLooping() -> removeAllItems() -> 入队新 item，
// 本 spike 只播一路，不需要切队列，故不实现切换路径。
final class Playback {
    let player: AVQueuePlayer
    private let looper: AVPlayerLooper

    init(url: URL) {
        let item = AVPlayerItem(url: url)
        // 保音高必须设在 item 上；默认的 .timeDomain 会变调。
        item.audioTimePitchAlgorithm = .spectral
        // ROADMAP Phase 2 Notes 的定值 3.0。计划把它写在 player 上，实测该属性
        // 属于 AVPlayerItem（AVQueuePlayer 上没有这个成员），写在 item 上才是对的。
        item.preferredForwardBufferDuration = 3.0
        self.player = AVQueuePlayer()
        // spike 不该发出声音；同时四组一致，功耗 delta 不受影响。
        self.player.isMuted = true
        self.looper = AVPlayerLooper(player: player, templateItem: item)
    }

    func start() {
        player.play()
    }
}

// 桌面层窗口：层级是本 spike 唯一被测量的属性。
final class WallpaperWindow: NSWindow {
    private let canvas: FlippedView
    private let hueLayer: CALayer
    private let frameLabel: CATextLayer

    // opaque=false 是 D-07 第三组：isOpaque 开关就是 A/B 的自变量。
    init(screen: NSScreen, opaque: Bool) {
        self.canvas = FlippedView(frame: screen.frame)
        self.hueLayer = CALayer()
        self.frameLabel = CATextLayer()

        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)

        // D-03 定案：层级只有这一种写法，禁止把数字写成字面量。
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))

        // D-04 禁用项：换成图标层会盖住桌面图标（两值只差 20）。本文件不得出现该标识符。
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        isOpaque = opaque
        hasShadow = false
        ignoresMouseEvents = true
        backgroundColor = opaque ? .black : .clear

        canvas.wantsLayer = true
        if let root = canvas.layer {
            hueLayer.frame = root.bounds
            hueLayer.backgroundColor = NSColor.black.cgColor
            root.addSublayer(hueLayer)

            frameLabel.contentsScale = 2.0
            frameLabel.alignmentMode = .left
            frameLabel.fontSize = 24
            frameLabel.foregroundColor = NSColor.white.cgColor
            frameLabel.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
            frameLabel.string = "frame 0"
            frameLabel.frame = CGRect(x: 24, y: 24, width: 480, height: 44)
            root.addSublayer(frameLabel)
        }
        contentView = canvas
    }

    // 视频组：AVPlayerLayer 叠在 canvas 根 layer 之上（后加的 sublayer 在上层）。
    func attachVideoLayer(player: AVQueuePlayer, gravity: AVLayerVideoGravity) {
        guard let root = canvas.layer else { return }
        let videoLayer = AVPlayerLayer(player: player)
        videoLayer.frame = root.bounds
        videoLayer.videoGravity = gravity
        root.addSublayer(videoLayer)
    }

    // D-07 第四组：AVKit 的播放器视图，作为 contentView 的子视图。
    // ARCHITECTURE 反模式 7 判定产品不该用它（带 UI chrome），这里只作对照组量一次。
    func attachPlayerView(player: AVQueuePlayer, gravity: AVLayerVideoGravity) {
        let playerView = AVPlayerView(frame: canvas.bounds)
        playerView.autoresizingMask = [.width, .height]
        playerView.videoGravity = gravity
        playerView.controlsStyle = .none
        playerView.player = player
        canvas.addSubview(playerView)
    }

    func render(frameNumber: Int) {
        hueLayer.backgroundColor = NSColor(
            hue: CGFloat(frameNumber % 360) / 360.0,
            saturation: 0.85,
            brightness: 1.0,
            alpha: 1.0
        ).cgColor
        frameLabel.string = "frame \(frameNumber)"
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@main
struct WallpaperSpikeMain {
    private static var retainedTicker: FrameTicker?
    private static var retainedPlayback: Playback?

    // 默认视频目录：~/Movies/视频壁纸/。
    private static var videoDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Movies/视频壁纸", isDirectory: true)
    }

    // 默认视频：该目录下按文件名排序的第一个 .mp4。
    private static func defaultVideoURL() -> URL? {
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(at: videoDirectory, includingPropertiesForKeys: nil)) ?? []
        return items
            .filter { $0.pathExtension.lowercased() == "mp4" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .first
    }

    private static func abort(_ reason: String, code: Int32) -> Never {
        FileHandle.standardError.write("PIC_ABORT=\(reason)\n".data(using: .utf8)!)
        exit(code)
    }

    static func main() {
        var mode = "color"
        var videoArg: String?
        let args = CommandLine.arguments
        var i = 1
        while i < args.count {
            if args[i] == "--mode", i + 1 < args.count {
                mode = args[i + 1]
                i += 2
            } else if args[i] == "--video", i + 1 < args.count {
                videoArg = args[i + 1]
                i += 2
            } else {
                i += 1
            }
        }

        // D-07 的四组 + Plan 01 遗留的 color 动画基线。未知 mode 显式失败，不静默降级。
        let videoModes = ["none", "v1", "transparent", "avplayerview"]
        if mode != "color" && !videoModes.contains(mode) {
            abort("mode_not_implemented:\(mode)", code: 3)
        }

        // 只有 A/B 组需要视频资产；color 是 Plan 01 的纯动画基线，保持零外部依赖。
        var videoURL = URL(fileURLWithPath: "")
        if videoModes.contains(mode) {
            if let arg = videoArg {
                videoURL = URL(fileURLWithPath: (arg as NSString).expandingTildeInPath)
            } else if let fallback = defaultVideoURL() {
                videoURL = fallback
            } else {
                abort("video_missing:\(videoDirectory.path)", code: 2)
            }
            // Pitfall 5：存在性一律查 url.path，喂 absoluteString 会让含 %20 的路径查不到文件。
            guard FileManager.default.fileExists(atPath: videoURL.path) else {
                abort("video_missing:\(videoURL.path)", code: 2)
            }
            guard !AVURLAsset(url: videoURL).tracks(withMediaType: .video).isEmpty else {
                abort("no_video_track:\(videoURL.lastPathComponent)", code: 2)
            }
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        guard let screen = NSScreen.main else {
            abort("no_screen", code: 4)
        }

        // 第一组 isOpaque=true，第二、三组 isOpaque=false，第四组沿用对照组默认值。
        let windowOpaque = (mode == "none" || mode == "v1" || mode == "avplayerview")
        let window = WallpaperWindow(screen: screen, opaque: windowOpaque)
        window.orderFrontRegardless()

        var playback: Playback?
        if mode != "none" && mode != "color" {
            let pb = Playback(url: videoURL)
            pb.start()
            playback = pb
            if mode == "avplayerview" {
                window.attachPlayerView(player: pb.player, gravity: .resizeAspectFill)
            } else {
                window.attachVideoLayer(player: pb.player, gravity: .resizeAspectFill)
            }
        }
        retainedPlayback = playback

        // 恰好一次，且在播放器建好之后打印 —— hasVideoTrack 必须是已校验的事实。
        // color 组不碰视频资产，故如实写 none/0，不谎称校验过视频轨。
        let videoName = videoModes.contains(mode) ? videoURL.lastPathComponent : "none"
        let hasVideoTrack = videoModes.contains(mode) ? 1 : 0
        print("PIC_GATE level=\(window.level.rawValue) pid=\(ProcessInfo.processInfo.processIdentifier) mode=\(mode) video=\(videoName) hasVideoTrack=\(hasVideoTrack)\n", terminator: "")
        fflush(stdout)

        // none 组不跑动画：它的用途是把「解码耗电」与「动画耗电」隔离开。
        if mode != "none" {
            let ticker = FrameTicker(window: window)
            retainedTicker = ticker
            ticker.attach(to: screen)
        }

        app.run()
    }
}
