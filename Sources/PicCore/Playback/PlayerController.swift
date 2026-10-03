import AVFoundation
import Foundation

/// 播放内核（★ 三个接口之一）。
///
/// 形状照抄 Phase 1 `.planning/spike/WallpaperSpike.swift` 的 `Playback`
/// （AVQueuePlayer + AVPlayerLooper，已实跑过），不重新推导。
///
/// 它**不判断「为什么」暂停**（ARCHITECTURE §5.2）—— 只听 `HoldArbiter` 的
/// `PlaybackDecision` 行事。单向流：Watcher → HoldArbiter → PlayerController。
/// `stop()` 是 D-11 降级路径的播放器侧落点，与 `WallpaperWindowController.teardown()`
/// 成对使用（停止 + 隐藏）。
@MainActor
public final class PlayerController: NSObject, PlaybackTarget {

    public let player = AVQueuePlayer()

    /// looper 必须强持有：一旦释放，模板 item 立刻被踢出队列（Pitfall 4）。
    private var looper: AVPlayerLooper?

    /// 画面挂载点。由渲染层（Plan 02-02 的窗口控制器）建好后注进来。
    public private(set) var playerLayer: AVPlayerLayer?

    public override init() {
        super.init()
    }

    public func attach(to layer: AVPlayerLayer) {
        playerLayer = layer
        layer.player = player
    }

    /// 装载一路视频并交给 looper 无限循环。
    ///
    /// 切队列顺序是 D-14 的硬约束：先停 looper，再清队列，最后入队新 item，
    /// 否则 looper 与手动清队列打架。首次装载时还没有 looper，跳过第一步。
    public func load(url: URL) {
        let item = AVPlayerItem(url: url)
        // 保音高必须显式设：macOS 12+ 默认 .timeDomain 会变调（D-12）。
        item.audioTimePitchAlgorithm = .spectral
        // ROADMAP Phase 2 Notes 的定值 3.0。该属性属于 AVPlayerItem，AVQueuePlayer 上没有。
        item.preferredForwardBufferDuration = 3.0

        looper?.disableLooping()
        player.removeAllItems()
        looper = AVPlayerLooper(player: player, templateItem: item)
    }

    /// 速度。**必须挂在 player 上**（D-13）——
    /// `AVPlayerLooper` 的模板 item 属性在 init 时就冻结，挂 item 会让
    /// Phase 5 的「改设置当场生效」变成假的。AVPlayerItem 上也没有 rate 成员。
    public func setRate(_ r: Float) {
        player.rate = r
    }

    public func setVolume(_ v: Float) {
        player.volume = v
    }

    public func setMuted(_ m: Bool) {
        player.isMuted = m
    }

    // MARK: - PlaybackTarget

    public func arbiterCurrentPosition() -> TimeInterval {
        let t = player.currentTime()
        return t.seconds.isFinite ? t.seconds : 0
    }

    public func arbiterSeek(to seconds: TimeInterval) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
    }

    /// 播放 / 暂停的唯一入口（D-14 的 Pitfall 7：暂停与恢复走同一个函数，
    /// 否则唤醒路径与暂停路径会不对称）。
    public func arbiterApply(_ decision: PlaybackDecision) {
        if decision.shouldPlay {
            player.play()
        } else {
            player.pause()
        }
    }

    /// 「没有媒体可播」的落点 —— 不是「暂停」。语义上它与 `arbiterApply` 不同：
    /// 混用会让 `HoldArbiter` 的状态机看到一个它没下过的决策。
    ///
    /// 三步、顺序不可换（Pitfall 4 的注册/注销配对纪律）：
    /// 1. `disableLooping()` —— 先解绑，否则空队列上的 looper 会立刻报错；
    /// 2. `looper = nil` —— 必须置 nil。looper 是 `AVQueuePlayer` 的拷贝源，
    ///    留着它会让下一次 `load(url:)` 里 `looper?.disableLooping()` 作用在
    ///    一个已经被拆掉的队列上；
    /// 3. `removeAllItems()` —— 清空队列。
    ///
    /// 幂等：对已空的队列重复调用无副作用。**不调 `pause()`** —— 队列空了播放
    /// 自然停；播放控制是 `arbiterApply` 的唯一入口（D-06 / D-11 的单向流）。
    public func stop() {
        looper?.disableLooping()
        looper = nil
        player.removeAllItems()
    }
}
