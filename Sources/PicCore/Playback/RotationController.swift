import Foundation


/// 轮换的调度 seam。**协议本身不标 `@MainActor`**：整体标会让 Swift 6 的 conformance 报
/// `#ConformanceIsolation`，由持有它的 `@MainActor` 类负责隔离。
///
/// 主线程契约写进 `body` 的**类型**（`@MainActor () -> Void`）而不是注释：实现者交出一个
/// 在主线程上执行它的调度，调用方因此可以直呼。**别退回成裸 `() -> Void` + `assumeIsolated`** ——
/// 那是断言不是切换，换个在自建队列上跑的实现会当场崩，且崩在「我以为编译器已经保证了」上。
public protocol RotationScheduling: AnyObject {
    func schedule(after interval: TimeInterval, _ body: @escaping @MainActor () -> Void)
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

    /// 一次切换的记录。**只记 reason 与 index，不记文件名**（隐私纪律）。
    /// `reason` 只从这里出去：单测靠它区分「用户点的」与「轮换到点」，别删。
    public struct RotationAdvance: Equatable, Sendable {
        public let reason: AdvanceReason
        public let index: Int

        public init(reason: AdvanceReason, index: Int) {
            self.reason = reason
            self.index = index
        }
    }


    /// 轮换的条目。**只存 URL 而不是 `VideoItem`**：图片来源复用同一个内核，
    /// 把图片包成「视频条目」能编译但语义是错的。
    public private(set) var items: [URL] = []
    public private(set) var currentIndex: Int = 0
    public private(set) var advances: [RotationAdvance] = []
    public private(set) var interval: TimeInterval = 300

    /// 下一程的计划触发时刻。由 `reschedule()` 唯一写入 —— 别在别处赋值，否则读数与实际定时器会分叉。
    public private(set) var nextFireDate: Date?

    /// 播放模式。**可读写且直接生效**，不存第二份 —— 下一次 `advance` 就按新值走。
    public var mode: PlayMode

    /// 装配层用它把「下一条」转成播放端的装载。单向出参。
    public var onAdvance: ((URL) -> Void)?

    /// 洗牌袋：`setItems` 时清空，跨同一次列表内的 `advance` 保持 —— 这正是
    /// 「一轮内每条恰好一次」的实现载体。
    private var bag: [Int] = []

    private let scheduler: any RotationScheduling
    private let random: any RandomSource
    private var isRunning = false

    /// 手动暂停旗标。只由 `pauseRotation()` / `resumeRotation()` 写；**系统让路（锁屏 /
    /// 全屏 / 睡眠）不碰它** —— 那些场景轮换照走、解除后续播，只有用户亲手按的「暂停」
    /// 才连轮换定时器一起停。
    private var isPaused = false

    /// 暂停那一刻的剩余秒数。恢复时按它重排；暂停期间「立即下一个」切完会把剩余
    /// 重置为完整间隔（刚切过一片，从头数）。`secondsUntilNextRotation` 暂停期间返回
    /// 这个冻结值 —— 菜单环静止，不再走秒。
    public private(set) var remainingAtPause: TimeInterval?

    public var current: URL? { items.isEmpty ? nil : items[currentIndex] }


    /// **没有 player 参数，也没有 interval 参数** —— 这是让「到点就切 ≠ 播完才切」结构上不可绕过的关键。
    public init(scheduler: any RotationScheduling, random: any RandomSource,
                mode: PlayMode = .loopSingle) {
        self.scheduler = scheduler
        self.random = random
        self.mode = mode
    }

    /// 换列表：索引归 0、清空洗牌袋。`start()` 之前调。
    public func setItems(_ newItems: [URL]) {
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
    public func refreshItems(_ newItems: [URL]) -> Bool {
        bag = []
        guard let currentURL = current, let newIndex = newItems.firstIndex(of: currentURL) else {
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
    /// 首条装载**不记进 `advances`** —— 它不是一次切换。空列表时直接返回：不记录、
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

    /// 单循环的续播变体：从上次播放的文件接着来（`start()` 的定点版）。
    /// 文件已不在清单里（被删 / 换目录）时回退成普通 `start()`。随机模式不走这里
    /// （装配层只在 loopSingle 下调用；误用时等价于定点命中或回退，无副作用）。
    public func start(resumingAt url: URL) {
        guard !items.isEmpty else { return }
        guard let index = items.firstIndex(of: url) else {
            start()
            return
        }
        isRunning = true
        currentIndex = index
        onAdvance?(items[currentIndex])
        reschedule()
    }

    public func stop() {
        isRunning = false
        isPaused = false
        remainingAtPause = nil
        nextFireDate = nil
        scheduler.cancel()
        onAdvance = nil
    }

    /// 手动暂停轮换：取消定时器、冻结剩余秒数。倒计时读数静止，到点切换不再发生。
    /// 幂等：已暂停时再调是空操作。
    public func pauseRotation() {
        guard isRunning, !isPaused else { return }
        isPaused = true
        remainingAtPause = nextFireDate.map { max(0, $0.timeIntervalSinceNow) }
        scheduler.cancel()
        nextFireDate = nil
    }

    /// 恢复轮换：按冻结的剩余秒数重排（不是重置为完整间隔 —— 暂停了 8 分钟的 10 分钟
    /// 轮换，继续后 2 分钟就该换）。幂等：未暂停时再调是空操作。
    public func resumeRotation() {
        guard isPaused else { return }
        isPaused = false
        let remaining = remainingAtPause ?? interval
        remainingAtPause = nil
        nextFireDate = Date().addingTimeInterval(remaining)
        scheduler.schedule(after: remaining) { [weak self] in
            self?.rotationElapsed()
        }
    }

    /// 距下次轮换的剩余秒数。没有「下一个」时给 nil —— 单循环 / 只有一条时，
    /// 倒计时读出来的是个不会发生的切换，比不显示更坏。
    /// 暂停期间返回冻结的 `remainingAtPause`：读数静止，且与真实时钟无关。
    public func secondsUntilNextRotation(now: Date = Date()) -> TimeInterval? {
        guard isRunning, mode != .loopSingle, items.count > 1 else { return nil }
        if isPaused { return remainingAtPause }
        guard let nextFireDate else { return nil }
        return max(0, nextFireDate.timeIntervalSince(now))
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
                nextIndex = currentIndex
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
    /// **暂停期间不排程**：暂停中「立即下一个」切完不启动定时器，剩余按完整间隔重置
    /// —— 刚切过一片，恢复后从头数。
    private func reschedule() {
        guard !isPaused else {
            remainingAtPause = interval
            nextFireDate = nil
            return
        }
        nextFireDate = Date().addingTimeInterval(interval)
        scheduler.schedule(after: interval) { [weak self] in
            self?.rotationElapsed()
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
