import AppKit
import QuartzCore

/// 显示刷新驱动的**测量器**。
///
/// ## 它不参与渲染
///
/// 壁纸播放完全不依赖显示刷新 —— `AVPlayer` 按视频自己的时间戳出帧，窗口由
/// WindowServer 合成。本类**不碰任何渲染路径**：没有 layer、没有 frame counter
/// 画到屏幕上、没有 `player` 引用。启动它只为回答一个问题：打包成 `.app` 之后，
/// 本进程能不能拿到显示刷新回调？Phase 1 在 spike 里测到的是降级路径
/// （`FRAME_DRIVER=timer_fallback_hz30`），本类就是那次复测的取证体。
///
/// 降级兜底是 30Hz `Timer`，长期跑在产品里没有收益、只有成本，所以测满
/// `windowSeconds` 就自己 `invalidate()`：测量一次性完成，不留常驻定时器。
///
/// ## 写法照抄，逻辑不改进
///
/// macOS 27 SDK 上，CADisplayLink 的 target/selector 初始化器与它的
/// preferredFrames…PerSecond 属性标了 `API_UNAVAILABLE(macos)`（D-07），只有
/// `NSScreen.displayLink` + `CAFrameRateRange` 这一条路能编过。**不要**"顺手"改回旧写法。
///
/// ⚠️ 上面那两个被禁 API 的**名字在本文件里刻意不写成字面量**：T2 的验收判据是
/// 「grep 本文件里这两个被禁 API 的名字，计数必须为 0」，而判据数的是**全文**
/// （不剥注释）。把「被禁用的写法」抄进注释会让那条门禁恒红，也会让后人
/// 分不清它禁的是调用还是文档。这里用文字说明即可，别"修复"回字面量。
///
/// ## observer 配对
///
/// displayLink 与 Timer 在**同一处** `invalidate()`（D-14 / Pitfall 4）。刻意不引入
/// Phase 1 Pitfall 16 提到的 15 秒 teardown 宽限期 —— 那条是为切换视频时让旧
/// renderer 自然退场设计的。不传 `-DPIC_NO_PROBE` 时整个声明区都在；交付构建由
/// `build.sh` 的 `-Xswiftc -DPIC_NO_PROBE` 打开开关，把测量脚手架剥出交付二进制。
#if !PIC_NO_PROBE
@MainActor
public final class FrameDriver: NSObject {

    /// 测量窗口秒数。窗口内累计 tick 数，窗口结束打一行 `REFRESH_TICK_RATE`。
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

    /// 首选驱动：显示刷新回调。
    public func attach(to screen: NSScreen) {
        let link = screen.displayLink(target: self, selector: #selector(FrameDriver.onDisplayLink(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 30, preferred: 30)
        link.add(to: .main, forMode: .common)
        self.link = link
        startFallbackWatchdog()
        scheduleWindowEnd()
    }

    /// 1 秒内一个 tick 都没收到 → 拿不到显示刷新回调，退到 30Hz Timer 并如实打一行。
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

    /// tick 率窗口结束 → 打一行实测速率并收掉驱动。
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

    /// displayLink 与 Timer 在这里一起收（D-14 / Pitfall 4 的配对纪律）。
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
        // display_link 这条结论只打一次 —— 每 tick 刷屏会把日志淹掉。
        if reportedDriver == nil {
            WallpaperWindowController.emit("REFRESH_DRIVER=display_link")
            reportedDriver = "display_link"
        }
    }
}
#endif
