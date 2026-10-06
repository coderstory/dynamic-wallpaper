import Foundation


/// 轮换的调度 seam。**不标 `@MainActor`**：协议整体标会让 Swift 6 的 conformance 报
/// `#ConformanceIsolation`，由持有它的 `@MainActor` 类负责隔离。
public protocol RotationScheduling: AnyObject {
    func schedule(after interval: TimeInterval, _ body: @escaping () -> Void)
    func cancel()
}

/// 随机源 seam（可复现判据靠它）。**不标 `@MainActor`**，理由同上。**只有
/// `nextInt(upperBound:)` 一个方法** —— 多一个就多一处可以藏「恒定实现」的地方。
public protocol RandomSource: AnyObject {
    func nextInt(upperBound: Int) -> Int
}

/// 可播种的随机源（xorshift64）。同 seed 两次给出完全相同的序列 —— 可复现判据靠它。
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


/// 轮换内核 ——「下一条播哪条、多久换一条」的唯一真相源。**与播放端彻底解耦**：
/// `init` 里没有 player、文件里零播放进度读取，「到点就切」在结构上不可被绕过成
/// 「等播完再切」。只要轮换器能读到播放位置，一个「等播完」的实现就能悄悄混进来。
@MainActor
public final class RotationController {

    /// 为什么切换。
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

    /// 重扫换列表 —— 与 `setItems` 的差别是：**正在播的那条还在就不打断它**。
    ///
    /// 返回 true = 那条片子还在（已挪到新下标），调用方什么都不用做，播放继续；
    /// 返回 false = 它已经不在了（被删 / 换目录 / 转码删了源），该由调用方重开一轮。
    ///
    /// 洗牌袋里存的是**旧列表的下标**，列表一换就全部失效 —— 必须作废，留着会按旧下标
    /// 挑出已经不在列表里的条目（越界或播到错片）。
    @discardableResult
    public func refreshItems(_ newItems: [VideoItem]) -> Bool {
        bag = []
        guard let currentURL = current?.url,
              let newIndex = newItems.firstIndex(where: { $0.url == currentURL }) else {
            items = newItems
            currentIndex = 0
            return false
        }
        items = newItems
        currentIndex = newIndex
        return true
    }

    /// **当场重排程**：取消旧定时器、用新间隔重新排，让设置改动立即生效。尚未
    /// `start()` 时不排（排了会把首程提前到 `start()` 之前）。
    public func setInterval(_ seconds: TimeInterval) {
        interval = seconds
        guard isRunning, !items.isEmpty else { return }
        reschedule()
    }

    /// `setItems` 之后调一次：把首条交给 `onAdvance`，并用 `interval` 排下一程。
    /// 首条装载**不记进 `advances`** —— 它不是一次切换。空列表时直接返回：不打点、
    /// 不回调、不排程（降级路径的共同前置）。
    ///
    /// **shuffle 下首条必须从洗牌袋取**，不能写死 `items[0]`：写死就是「每次开 app
    /// 第一个壁纸都一样」。取走的那一条**不回袋** —— 一轮内每条恰好一次的语义才会成立
    ///（固定 items[0] 的话，它在第一轮里会被播两次）。
    public func start() {
        guard !items.isEmpty else { return }
        isRunning = true
        if mode == .shuffle {
            if bag.isEmpty { refillBag() }
            currentIndex = bag.removeFirst()
        } else {
            currentIndex = 0
        }
        onAdvance?(items[currentIndex])
        reschedule()
    }

    public func stop() {
        isRunning = false
        scheduler.cancel()
        onAdvance = nil
    }


    /// 立即下一个（行为侧）。
    public func advanceNow() {
        advance(reason: .userRequested)
    }

    /// 由调度器到点回调进来。**这里不读任何播放进度** —— 结构上也读不到。
    public func rotationElapsed() {
        advance(reason: .rotationElapsed)
    }

    private func advance(reason: AdvanceReason) {
        // 空列表：不回调、不崩，也**不重排程**（定时器自然熄火）。
        guard !items.isEmpty else { return }
        let previousIndex = currentIndex
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

        // 到点解析出的下标与切换前相同 → 只记一次切换、重排下一程，**不重新装载**。
        // onAdvance 的下游是 player.load(url:)，它会重建 AVPlayerItem 与 looper、把播放头归零；
        // 单循环下这就等于「每到一个间隔从头重播一次」。循环本身由 AVPlayerLooper 维持，
        // 不需要靠重新装载续命。list 只有一条 / shuffle 洗牌袋边界撞回同下标时同理。
        guard !(nextIndex == previousIndex && reason == .rotationElapsed) else {
            reschedule()
            return
        }
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
