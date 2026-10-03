import Foundation

// MARK: - 注入 seam

/// 轮换的调度 seam。**不标 `@MainActor`**：协议整体标会让 Swift 6 的 conformance 报
/// `#ConformanceIsolation`，由持有它的 `@MainActor` 类负责隔离。单测注入 `ManualScheduler`，生产注入系统调度器。
public protocol RotationScheduling: AnyObject {
    func schedule(after interval: TimeInterval, _ body: @escaping () -> Void)
    func cancel()
}

/// 随机源 seam（可复现判据靠它）。**不标 `@MainActor`**，理由同上。**只有
/// `nextInt(upperBound:)` 一个方法** —— 多一个就多一处可以藏「恒定实现」的地方。
public protocol RandomSource: AnyObject {
    func nextInt(upperBound: Int) -> Int
}

/// 可播种的随机源（xorshift64）。同 seed 两次给出完全相同的序列；两个不同 seed
/// 至少有一个顺序不同 —— 证明随机源真接上了，不是恒等实现。
public final class SeededRandomSource: RandomSource {

    private var state: UInt64

    public init(seed: UInt64) {
        // 播种散列（golden ratio 常数）+ 置奇数位：保证 seed == 0 时不退化成恒零序列。
        state = seed &* 0x9E3779B97F4A7C15 | 1
    }

    public func nextInt(upperBound: Int) -> Int {
        var x = state
        x ^= x >> 12
        x ^= x << 25
        x ^= x >> 27
        state = x
        return Int(x % UInt64(upperBound))
    }
}

// MARK: - 轮换内核

/// 轮换内核 ——「下一条播哪条、多久换一条」的唯一真相源。**与播放端彻底解耦**：
/// `init` 里没有 player、文件里零播放进度读取，「到点就切」在结构上不可被绕过成
/// 「等播完再切」。这不是洁癖：只要轮换器能读到播放位置，一个「等播完」的实现就能悄悄混进来。
@MainActor
public final class RotationController {

    /// 为什么切换。轮换到点 / 用户手动「立即下一个」。
    public enum AdvanceReason: String, Equatable, Sendable {
        case rotationElapsed
        case userRequested
    }

    /// 一次切换的打点。**只记 reason 与 index，不记文件名**（隐私纪律）。
    public struct RotationAdvance: Equatable, Sendable {
        public let reason: AdvanceReason
        public let index: Int

        public init(reason: AdvanceReason, index: Int) {
            self.reason = reason
            self.index = index
        }
    }

    // MARK: 状态

    public private(set) var items: [VideoItem] = []
    public private(set) var currentIndex: Int = 0
    public private(set) var advances: [RotationAdvance] = []
    public private(set) var interval: TimeInterval = 300

    /// 播放模式。**可读写且直接生效**，不存第二份 —— 下一次 `advance` 就按新值走。
    public var mode: PlayMode

    /// 装配层用它把「下一条」转成播放端的装载。单向出参。
    public var onAdvance: ((VideoItem) -> Void)?

    /// 洗牌袋：`setItems` 时清空，跨同一次列表内的 `advance` 保持 —— 这正是
    /// 「一轮内每条恰好一次」的实现载体。
    private var bag: [Int] = []

    private let scheduler: any RotationScheduling
    private let random: any RandomSource
    private var isRunning = false

    public var current: VideoItem? { items.isEmpty ? nil : items[currentIndex] }

    // MARK: 生命周期

    /// **没有 player 参数，也没有 interval 参数** —— 这是让「到点就切 ≠ 播完才切」结构上不可绕过的关键。
    public init(scheduler: any RotationScheduling, random: any RandomSource,
                mode: PlayMode = .loopSingle) {
        self.scheduler = scheduler
        self.random = random
        self.mode = mode
    }

    /// 换列表：索引归 0、清空洗牌袋。`start()` 之前调。
    public func setItems(_ newItems: [VideoItem]) {
        items = newItems
        currentIndex = 0
        bag = []
    }

    /// 与 `mode` 属性共用同一个真相源（`mode = newMode`），不另存副本。
    /// 保留方法入口是因为计划冻结的公开面两者都在。
    public func setMode(_ newMode: PlayMode) {
        mode = newMode
    }

    /// **当场重排程**：取消旧定时器、用新间隔重新排，让设置改动立即生效。尚未
    /// `start()` 时不排（排了会把首程提前到 `start()` 之前，`scheduleCount` 的读数就漂了）。
    public func setInterval(_ seconds: TimeInterval) {
        interval = seconds
        guard isRunning, !items.isEmpty else { return }
        reschedule()
    }

    /// `setItems` 之后调一次：把首条交给 `onAdvance`，并用 `interval` 排下一程。
    /// 首条装载**不记进 `advances`** —— 它不是一次切换。空列表时直接返回：不打点、
    /// 不回调、不排程（降级路径的共同前置）。
    public func start() {
        guard !items.isEmpty else { return }
        isRunning = true
        onAdvance?(items[0])
        reschedule()
    }

    public func stop() {
        isRunning = false
        scheduler.cancel()
        onAdvance = nil
    }

    // MARK: 切换

    /// 立即下一个（菜单「立即下一个」的行为侧）。
    public func advanceNow() {
        advance(reason: .userRequested)
    }

    /// 由调度器到点回调进来。**这里不读任何播放进度** —— 结构上也读不到。
    public func rotationElapsed() {
        advance(reason: .rotationElapsed)
    }

    /// 三种模式的选取逻辑。名字（`nextIndex` / `bag` / `refillBag()`）是判据依赖的
    /// 名字，逐字照写 —— 变异插桩的 perl 正则正按它们匹配。
    private func advance(reason: AdvanceReason) {
        // 空列表：不打点、不回调、不崩，也**不重排程**（定时器自然熄火）。
        guard !items.isEmpty else { return }
        let nextIndex: Int
        switch mode {
        case .loopSingle:
            // reason 是「轮换」与「用户要下一条」的唯一区分量：单循环的锁定只约束轮换到点，
            // 菜单「立即下一个」按列表前进（用户意图优先）。
            if reason == .userRequested {
                nextIndex = (currentIndex + 1) % items.count
            } else {
                nextIndex = 0
            }
        case .loopList:
            nextIndex = (currentIndex + 1) % items.count
        case .shuffle:
            if bag.isEmpty { refillBag() }
            nextIndex = bag.removeFirst()
        }
        currentIndex = nextIndex
        advances.append(RotationAdvance(reason: reason, index: nextIndex))
        onAdvance?(items[nextIndex])
        reschedule()
    }

    /// 重排下一程 —— `setInterval` / `start` / `advance` 三处共用的唯一排程点。切完立刻
    /// 重排（到点就切，不等播完；`schedule` 内部先 `cancel()` 旧定时器，不累积）。
    private func reschedule() {
        scheduler.schedule(after: interval) { [weak self] in
            MainActor.assumeIsolated { self?.rotationElapsed() }
        }
    }

    /// 用注入的 `random` 做一次 Fisher–Yates，把 `0..<items.count` 洗满 `bag`。
    private func refillBag() {
        var deck = Array(0..<items.count)
        for i in stride(from: deck.count - 1, to: 0, by: -1) {
            let j = random.nextInt(upperBound: i + 1)
            deck.swapAt(i, j)
        }
        bag = deck
    }
}
