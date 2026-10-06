import AVFoundation
import Foundation

/// 播放内核（★ 三个接口之一）。形状照抄已实跑过的 spike 形态，不重新推导。
///
/// 它**不判断「为什么」暂停** —— 只听 `HoldArbiter` 的 `PlaybackDecision` 行事。
/// 单向流：Watcher → HoldArbiter → PlayerController。`stop()` 是降级路径的播放器侧
/// 落点，与 `WallpaperWindowController.teardown()` 成对使用（停止 + 隐藏）。
@MainActor
public final class PlayerController: NSObject, PlaybackTarget {

    public let player = AVQueuePlayer()

    /// looper 必须强持有：一旦释放，模板 item 立刻被踢出队列。
    private var looper: AVPlayerLooper?

    /// 画面挂载点。由渲染层的窗口控制器建好后注进来。
    public private(set) var playerLayer: AVPlayerLayer?

    public override init() {
        super.init()
    }

    public func attach(to layer: AVPlayerLayer) {
        playerLayer = layer
        layer.player = player
    }

    /// **先插后扫**：新 item 先入队，再扫掉全部旧 item。队列全程非空 ——
    /// 清空后等 looper 异步补位的那一段里图层无 currentItem 可呈现，会闪屏。
    public func load(url: URL) {
        let item = AVPlayerItem(url: url)
        // 保音高必须显式设：macOS 12+ 默认 .timeDomain 会变调。
        item.audioTimePitchAlgorithm = .spectral
        // 定值 3.0。该属性属于 AVPlayerItem，AVQueuePlayer 上没有。
        // 与上面一条一样必须设在 looper 之前 —— 克隆体不带，晚设只作用这一次。
        item.preferredForwardBufferDuration = 3.0

        looper?.disableLooping()
        // `after: nil` 是追加到队尾，所以必须扫掉全部非新条目 —— 否则旧片继续播、
        // 每次 load 净增一批，队列无界增长。
        player.insert(item, after: nil)
        player.items().filter { $0 !== item }.forEach { player.remove($0) }
        looper = AVPlayerLooper(player: player, templateItem: item)
    }

    /// 用户设的速度。`AVPlayer.play()` 等价于把 rate 置 **1.0** 而不是置回这个值，
    /// 所以恢复播放必须回放 `desiredRate`，不能调 `play()` —— 否则锁屏一次速度就丢了。
    /// 与 `player.rate` 的区别：这个是「用户想要多少」，那个是「此刻实际多少」（hold 时为 0）。
    public private(set) var desiredRate: Float = 1.0

    /// 速度。**必须挂在 player 上** —— `AVPlayerLooper` 的模板 item 属性在 init 时就冻结，
    /// 挂 item 会让「改设置当场生效」变成假的。AVPlayerItem 上也没有 rate 成员。
    /// 记住 + 当场应用两个动作一起做：漏了记住，hold 解除时就没有可回放的值。
    public func setRate(_ r: Float) {
        desiredRate = r
        player.rate = r
    }

    /// 只更新「用户想要的速度」，**不碰播放器**。hold 期间改速度走这条：改 `player.rate`
    /// 会把已 hold 的播放器重新拉起，那是绕过仲裁器。
    public func setDesiredRate(_ r: Float) {
        desiredRate = r
    }

    public func setVolume(_ v: Float) {
        player.volume = v
    }

    public func setMuted(_ m: Bool) {
        player.isMuted = m
    }


    public func arbiterCurrentPosition() -> TimeInterval {
        let t = player.currentTime()
        // CMTime 是值类型：这里**只有一次** `currentTime()` 读取，没有 actor 跳转。
        let seconds = t.seconds
        return seconds.isFinite ? seconds : 0
    }

    public func arbiterSeek(to seconds: TimeInterval) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
    }

    /// 播放 / 暂停的唯一入口（暂停与恢复走同一个函数，否则唤醒路径与暂停路径会不对称）。
    ///
    /// 恢复分支用 `player.rate = desiredRate` 而不是 `play()`：后者把 rate 顶回 1.0，
    /// 用户设的 0.5 / 1.5 在一次锁屏之后就没了。
    public func arbiterApply(_ decision: PlaybackDecision) {
        if decision.shouldPlay {
            player.rate = desiredRate
        } else {
            player.pause()
        }
    }

    /// 「没有媒体可播」的落点 —— 不是「暂停」。语义上它与 `arbiterApply` 不同：混用会让
    /// `HoldArbiter` 的状态机看到一个它没下过的决策。
    ///
    /// 三步、顺序不可换：`disableLooping()` 先解绑（否则空队列上的 looper 立刻报错）
    /// → `looper = nil`（looper 是 `AVQueuePlayer` 的拷贝源，留着会让下一次 `load(url:)`
    /// 的 `disableLooping()` 作用在已拆掉的队列上）→ `removeAllItems()` 清空队列。
    ///
    /// 幂等：对已空的队列重复调用无副作用。**不调 `pause()`** —— 队列空了播放自然停；
    /// 播放控制是 `arbiterApply` 的唯一入口（单向流）。
    public func stop() {
        looper?.disableLooping()
        looper = nil
        player.removeAllItems()
    }
}
