import AppKit
import AVFoundation
import Foundation

/// 300 秒无缝循环观察 —— ROADMAP Phase 2 SC2「连续观察 5 分钟无缝循环」的取证体。
///
/// 三条判据（全部来自真实采样，不是推断）：
///   ① `AVPlayerItemFailedToPlayToEndTime` 计数为 0，**且**「播完一条」通知的次数
///      与观察到的循环圈数相等（`endedCount == cycles`）
///   ② 采样点 ≥ 140（300 秒 / 2 秒一次，留 10% 抖动余量）
///   ③ 每一次采样 `status == playing` 且 `items >= 1`
///
/// ⚠️ 判据①里「播完一条」那一半的写法是被实测纠正过的（详见 02-02-SUMMARY 的
/// `PLAN_DEVIATION`）：计划原写 `endedCount == 0`。但 `AVPlayerLooper` 正是靠这条
/// 通知驱动「换下一条」的 —— 一个循环正常的播放器**必然**每圈发一次。
/// 把它判成失败，等于让「在循环」与「不循环」不可区分。
///
/// ⚠️ **位置读数的单调性不在判据里**。`AVPlayerLooper` 的队列里放的是克隆 item，
/// 每过一个 loop 边界 `AVPlayer.currentTime()` 就会归零，所以「跨边界单调不减」
/// 这件事在原理上就测不出来。它单独记成 `LOOP_POS_MONOTONIC`，且无条件附一行
/// `LOOP_POS_NOTE` 说明它是探针构造的 artifact 还是播放缺陷 —— 不许混为一谈。
/// 不传 `-DPIC_NO_PROBE` 时（本文件的默认态）整个声明区都在；交付构建由
/// `build.sh` 的 `-Xswiftc -DPIC_NO_PROBE` 打开开关，把测量脚手架从交付二进制里剥掉。
#if !PIC_NO_PROBE
@MainActor
public final class LoopProbe {

    /// 环境变量名：`PIC_LOOP_SECONDS=300` 才启动观察。不设就完全不跑，零成本。
    public static let secondsEnvKey = "PIC_LOOP_SECONDS"
    public static let sampleInterval: TimeInterval = 2.0
    public static let minimumSamples = 140

    private struct Sample {
        let n: Int
        let wall: Double
        let pos: Double
        let status: String
        let items: Int
        let hasCurrentItem: Bool
    }

    private let player: AVQueuePlayer
    private let durationSeconds: Int
    /// 观察跑完后结束进程的回调。由 `AppDelegate` 注入它自己的 `terminateApp()` ——
    /// 结束进程的全局调用字面量全仓只在 AppDelegate 里一处，两条路径不会各自漂移。
    private let terminate: () -> Void
    /// 观察者令牌只由主线程增删；标 nonisolated(unsafe) 只是为了让 deinit 能摘干净 ——
    /// deinit 本身不是主线程隔离的，而观察者泄漏是 D-14 明令禁止的。
    nonisolated(unsafe) private var tokens: [NSObjectProtocol] = []
    private var sampler: Timer?
    private var samples: [Sample] = []
    private var endedCount = 0
    private var stalledCount = 0
    private var failedCount = 0
    private var cycles = 0
    private var monotonic = true
    private var startedAt = Date()
    private var finished = false

    public init(player: AVQueuePlayer, durationSeconds: Int, terminate: @escaping () -> Void) {
        self.player = player
        self.durationSeconds = durationSeconds
        self.terminate = terminate
    }

    deinit {
        // D-14 / Pitfall 4：注册与注销严格配对。removeObserver 本身线程安全，
        // 这里不绕道主线程隔离的辅助方法，因为 deinit 不保证在主线程跑。
        let center = NotificationCenter.default
        for t in tokens { center.removeObserver(t) }
    }

    public func start() {
        startedAt = Date()
        registerObservers()

        emit("LOOP_PROBE_START duration=\(durationSeconds) interval=\(String(format: "%.1f", Self.sampleInterval)) pid=\(ProcessInfo.processInfo.processIdentifier)")

        let t = Timer(timeInterval: Self.sampleInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        RunLoop.main.add(t, forMode: .common)
        sampler = t

        // 到点收尾。用 run loop 的一次性延后，不另开线程。
        let deadline = DispatchTime.now() + .seconds(durationSeconds)
        DispatchQueue.main.asyncAfter(deadline: deadline) { [weak self] in
            MainActor.assumeIsolated { self?.finish() }
        }
    }

    // MARK: - 采样

    private func sample() {
        let t = player.currentTime().seconds
        let pos = t.isFinite ? t : -1
        if let last = samples.last, pos + 0.001 < last.pos {
            cycles += 1
            monotonic = false
        }
        let s = Sample(
            n: samples.count + 1,
            wall: Date().timeIntervalSince(startedAt),
            pos: pos,
            status: LoopProbe.statusToken(player.timeControlStatus),
            items: player.items().count,
            hasCurrentItem: player.currentItem != nil
        )
        samples.append(s)
        emit("LOOP_SAMPLE n=\(s.n) t=\(String(format: "%.1f", s.wall)) pos=\(String(format: "%.3f", s.pos)) status=\(s.status) items=\(s.items) hasItem=\(s.hasCurrentItem ? 1 : 0)")
    }

    // MARK: - 收尾

    private func finish() {
        guard !finished else { return }
        finished = true
        sampler?.invalidate()
        sampler = nil
        removeObservers()

        let elapsed = Int(Date().timeIntervalSince(startedAt).rounded())
        let statusOk = samples.allSatisfy { $0.status == "playing" }
        let itemsOk = samples.allSatisfy { $0.items >= 1 }
        let countOk = samples.count >= Self.minimumSamples
        // 「播完一条」每圈一次是 looper 正常换片的证据，不是缺陷证据。
        let failedOk = failedCount == 0
        let cyclesOk = endedCount == cycles

        var reasons: [String] = []
        if !failedOk { reasons.append("failed=\(failedCount)") }
        if !cyclesOk { reasons.append("ended=\(endedCount)_cycles=\(cycles)_mismatch") }
        if !countOk { reasons.append("samples=\(samples.count)_below_\(Self.minimumSamples)") }
        if !statusOk {
            let bad = Set(samples.map(\.status)).sorted().joined(separator: "+")
            reasons.append("status_not_always_playing=\(bad)")
        }
        if !itemsOk {
            let lo = samples.map(\.items).min() ?? 0
            reasons.append("items_below_1_min=\(lo)")
        }

        emit("LOOP_SAMPLES=\(samples.count)")
        emit("LOOP_ENDED=\(endedCount)")
        emit("LOOP_ENDED_PER_CYCLE=\(cycles == 0 ? "n/a" : String(format: "%.3f", Double(endedCount) / Double(cycles)))")
        emit("LOOP_STALLED=\(stalledCount)")
        emit("LOOP_FAILED=\(failedCount)")
        emit("LOOP_VERDICT=\(reasons.isEmpty ? "pass" : "fail")")
        if !reasons.isEmpty {
            emit("LOOP_FAIL_REASON=\(reasons.joined(separator: ";"))")
        }
        emit("LOOP_CYCLES=\(cycles)")
        emit("LOOP_POS_MONOTONIC=\(monotonic ? 1 : 0)")
        emit("LOOP_POS_NOTE=AVPlayerLooper 在 loop 边界克隆 item 并把 currentTime 归零，故 pos 非单调是探针 artifact；播放是否正常由 endedCount/failedCount/status/items 四项判定")
        emit("LOOP_DURATION=\(elapsed)")

        // 让主线程喘一口气再退，跑完不留残窗。退的是进程，走的是注入进来的那条路。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.terminate()
        }
    }

    // MARK: - 通知

    private func registerObservers() {
        let center = NotificationCenter.default
        // looper 在每个 loop 边界换 item，所以 object 传 nil 才能覆盖全部克隆 item。
        let watched: [Notification.Name] = [
            .AVPlayerItemDidPlayToEndTime,
            .AVPlayerItemPlaybackStalled,
            .AVPlayerItemFailedToPlayToEndTime,
        ]
        for name in watched {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    switch note.name {
                    case .AVPlayerItemDidPlayToEndTime: self?.endedCount += 1
                    case .AVPlayerItemPlaybackStalled: self?.stalledCount += 1
                    default: self?.failedCount += 1
                    }
                }
            })
        }
    }

    private func removeObservers() {
        let center = NotificationCenter.default
        for t in tokens { center.removeObserver(t) }
        tokens.removeAll()
    }

    // MARK: - 公共

    /// `AVPlayer.TimeControlStatus` 在 Swift 里反射成 `AVPlayerTimeControlStatus(rawValue: N)`，
    /// 不可 grep。映射成固定词，判定与验收脚本都按这个词读。
    public static func statusToken(_ s: AVPlayer.TimeControlStatus) -> String {
        switch s {
        case .paused: return "paused"
        case .waitingToPlayAtSpecifiedRate: return "waiting"
        case .playing: return "playing"
        default: return "unknown(\(s.rawValue))"
        }
    }

    /// 全部观察读数走 stderr —— 与 `TICK` 行同一个流，探针脚本一次收齐。
    private func emit(_ line: String) {
        FileHandle.standardError.write((line + "\n").data(using: .utf8)!)
    }
}
#endif