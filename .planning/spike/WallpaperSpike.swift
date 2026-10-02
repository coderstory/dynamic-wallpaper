// WallpaperSpike.swift —— Phase 01 门禁 spike，一次性 throwaway 验证件。
//
// 目的：证明「挂在桌面图标层之下的 NSWindow」在本机成立（D-06 帧号叠加）。
// 边界：只读窗口元数据 + 在自己的窗口里画东西，绝不改任何系统设置。
// 编译：swiftc -parse-as-library -target arm64-apple-macosx15.0 -o out/wallpaperspike WallpaperSpike.swift

import AppKit
import QuartzCore

// 坐标系翻转容器：左上角即 (0,0)，方便把帧号贴在窗口左上角。
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// CADisplayLink 的 target 必须是 NSObject + @objc selector。
final class FrameTicker: NSObject {
    private let window: WallpaperWindow
    private let mode: String
    private var frame: Int = 0
    private var gatePrinted = false
    private var fallbackTimer: Timer?

    init(window: WallpaperWindow, mode: String) {
        self.window = window
        self.mode = mode
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
    // 帧号仍是每 tick 变化的客观证据。DRIVER= 字段会打进 stderr 供 run-gate.sh 记录。
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
        if !gatePrinted {
            gatePrinted = true
            let line = "PIC_GATE level=\(window.level.rawValue) pid=\(ProcessInfo.processInfo.processIdentifier) mode=\(mode) frame=\(frame)\n"
            print(line, terminator: "")
            fflush(stdout)
        }
    }
}

// 桌面层窗口：层级是本 spike 唯一被测量的属性。
final class WallpaperWindow: NSWindow {
    private let canvas: FlippedView
    private let hueLayer: CALayer
    private let frameLabel: CATextLayer

    init(screen: NSScreen) {
        self.canvas = FlippedView(frame: screen.frame)
        self.hueLayer = CALayer()
        self.frameLabel = CATextLayer()

        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)

        // D-03 定案：层级只有这一种写法，禁止把数字写成字面量。
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))

        // D-04 禁用项：换成图标层会盖住桌面图标（两值只差 20）。本文件不得出现该标识符。
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        isOpaque = true
        hasShadow = false
        ignoresMouseEvents = true
        backgroundColor = .black

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

    static func main() {
        var mode = "color"
        let args = CommandLine.arguments
        var i = 1
        while i < args.count {
            if args[i] == "--mode", i + 1 < args.count {
                mode = args[i + 1]
                i += 2
            } else {
                i += 1
            }
        }

        // 其余 mode 由 Phase 04 填充。显式失败，不静默降级成 color。
        if mode != "color" {
            FileHandle.standardError.write("PIC_ABORT=mode_not_implemented:\(mode)\n".data(using: .utf8)!)
            exit(3)
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        guard let screen = NSScreen.main else {
            FileHandle.standardError.write("PIC_ABORT=no_screen\n".data(using: .utf8)!)
            exit(4)
        }

        let window = WallpaperWindow(screen: screen)
        window.orderFrontRegardless()

        let ticker = FrameTicker(window: window, mode: mode)
        retainedTicker = ticker
        ticker.attach(to: screen)

        app.run()
    }
}
