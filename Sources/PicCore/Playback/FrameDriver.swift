import AppKit
import QuartzCore

/// 显示刷新驱动的**测量器**：不参与渲染路径（`AVPlayer` 按视频时间戳出帧，窗口由
/// WindowServer 合成），本类没有 layer、没有 `player` 引用，只回答「打包成 `.app`
/// 之后本进程能否拿到显示刷新回调」。兜底是 30Hz `Timer`，测满 `windowSeconds`
/// 就自己 `invalidate()`，不留常驻定时器。
///
/// CADisplayLink 的 target/selector 初始化器与它的 preferredFrames…PerSecond 属性标了
/// `API_UNAVAILABLE(macos)`，只有 `NSScreen.displayLink` + `CAFrameRateRange` 能编过。
/// 不要"顺手"改回旧写法 —— 被禁的两个 API 名字在本文件里刻意不写全，别"修复"回字面量。
///
/// displayLink 与 fallback Timer 在同一处 `invalidate()`。
///
/// `build.sh` 传 `-Xswiftc -DPIC_NO_PROBE` 把整个声明区剥出交付二进制。
#if !PIC_NO_PROBE
@MainActor
public final class FrameDriver: NSObject {

    /// `nonisolated`：默认值出现在 init 的默认参数位，那里是 nonisolated 上下文。
    public nonisolated static let defaultWindowSeconds: TimeInterval = 10.0

    private let windowSeconds: TimeInterval
    private var link: CADisplayLink?
    private var fallbackTimer: Timer?
    private var tickCount = 0
    private var reportedDriver: String?
    private var finished = false

    public init(windowSeconds: TimeInterval = FrameDriver.defaultWindowSeconds) {
        self.windowSeconds = windowSeconds
        super.init()
    }

    public func attach(to screen: NSScreen) {
        let link = screen.displayLink(target: self, selector: #selector(FrameDriver.onDisplayLink(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 30, preferred: 30)
        link.add(to: .main, forMode: .common)
        self.link = link
        startFallbackWatchdog()
        scheduleWindowEnd()
    }

    /// 1 秒内零 tick 即判定拿不到显示刷新回调。
    private func startFallbackWatchdog() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self, self.tickCount == 0, self.fallbackTimer == nil else { return }
            WallpaperWindowController.emit("REFRESH_DRIVER=timer_fallback_hz30")
            self.reportedDriver = "timer_fallback_hz30"
            let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.step() }
            }
            self.fallbackTimer = t
            RunLoop.main.add(t, forMode: .common)
        }
    }

    private func scheduleWindowEnd() {
        DispatchQueue.main.asyncAfter(deadline: .now() + self.windowSeconds) { [weak self] in
            MainActor.assumeIsolated { self?.finish() }
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        let rate = Double(tickCount) / windowSeconds
        WallpaperWindowController.emit(String(format: "REFRESH_TICK_COUNT=%d", tickCount))
        WallpaperWindowController.emit(String(format: "REFRESH_WINDOW_SECONDS=%.1f", windowSeconds))
        WallpaperWindowController.emit(String(format: "REFRESH_TICK_RATE=%.1f", rate))
        WallpaperWindowController.emit("REFRESH_DRIVER_FINAL=\(reportedDriver ?? "none")")
        invalidate()
    }

    public func invalidate() {
        link?.invalidate()
        link = nil
        fallbackTimer?.invalidate()
        fallbackTimer = nil
    }

    @objc private func onDisplayLink(_ link: CADisplayLink) {
        step()
    }

    private func step() {
        tickCount += 1
        // 每 tick 都打会把日志淹掉。
        if reportedDriver == nil {
            WallpaperWindowController.emit("REFRESH_DRIVER=display_link")
            reportedDriver = "display_link"
        }
    }
}
#endif
