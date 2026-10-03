import XCTest
@testable import PicCore

/// 轮换内核的行为判据 —— 三种模式 + 一轮无重复 + 到点就切 +
/// 播种可复现 + 空列表静默 + 模式/间隔当场生效。
///
/// **不引入任何播放框架**：轮换逻辑的测试必须能在没有任何 AV 对象的条件下成立，
/// 那正是「轮换器与播放器解耦」的可测代理 —— `ManualScheduler.fire()`
/// 就能推进到下一条，全程不存在「片长」这个概念。
@MainActor
final class RotationControllerTests: XCTestCase {

    // MARK: - 文件内 helper（不跨文件引用别的测试类）

    /// 手动调度器：`fire()` 模拟「到点」，不依赖任何 runloop。
    final class ManualScheduler: RotationScheduling {
        private(set) var pending: (() -> Void)?
        private(set) var scheduleCount = 0
        private(set) var cancelCount = 0

        func schedule(after interval: TimeInterval, _ body: @escaping () -> Void) {
            pending = body
            scheduleCount += 1
        }

        func cancel() {
            pending = nil
            cancelCount += 1
        }

        /// 测试专用：手动触发当前闭包（触发后清空，与一次性定时器同语义）。
        func fire() {
            let body = pending
            pending = nil
            body?()
        }
    }

    /// 写死序列的随机源：用途是判据「洗袋真的调了注入源」—— 若实现压根不调
    /// `random`，`calls` 恒为 0，判据立刻红。
    final class CountingRandomSource: RandomSource {
        private(set) var calls = 0
        private let sequence: [Int]
        private var position = 0

        init(sequence: [Int] = [0, 1, 2, 0, 1, 2]) {
            self.sequence = sequence
        }

        func nextInt(upperBound: Int) -> Int {
            calls += 1
            let value = sequence[position % sequence.count]
            position += 1
            return upperBound > 0 ? value % upperBound : 0
        }
    }

    // MARK: - 夹具

    /// 三条视频。文件名随便造 —— `VideoItem` 只吃 `URL`，不碰磁盘。
    private static let threeItems: [VideoItem] = [
        VideoItem(url: URL(fileURLWithPath: "/tmp/pic-0402-fixture/v0.mp4")),
        VideoItem(url: URL(fileURLWithPath: "/tmp/pic-0402-fixture/v1.mp4")),
        VideoItem(url: URL(fileURLWithPath: "/tmp/pic-0402-fixture/v2.mp4")),
    ]

    private func makeController(random: any RandomSource) -> (RotationController, ManualScheduler) {
        let scheduler = ManualScheduler()
        let controller = RotationController(scheduler: scheduler, random: random)
        return (controller, scheduler)
    }

    // MARK: - 用例 1：轮换到点在单循环下永远停在同一条

    func testLoopSingleAlwaysReturnsTheSameItem() {
        let (controller, scheduler) = makeController(random: SeededRandomSource(seed: 42))
        controller.setItems(Self.threeItems)
        controller.setMode(.loopSingle)
        controller.start()

        // 轮换路径驱动：锁定的语义只约束「到点」。用户手动「立即下一个」按 reason
        // 分流到用例 8。
        for _ in 0..<5 { scheduler.fire() }

        XCTAssertEqual(controller.currentIndex, 0,
                       "单循环下 currentIndex 必须恒为 0 —— 不前进")
        XCTAssertEqual(controller.advances.map(\.index), [0, 0, 0, 0, 0],
                       "5 次切换全部落在同一条上")
        XCTAssertEqual(controller.current, Self.threeItems[0])
    }

    // MARK: - 用例 2：列表循环按顺序走完一圈再回第一条

    func testLoopListWalksEveryItemThenWrapsToFirst() {
        let (controller, _) = makeController(random: SeededRandomSource(seed: 42))
        controller.setItems(Self.threeItems)
        controller.setMode(.loopList)
        controller.start()

        for _ in 0..<6 { controller.advanceNow() }

        XCTAssertEqual(controller.advances.map(\.index), [1, 2, 0, 1, 2, 0],
                       "三条列表：顺序前进、取模回卷")
        XCTAssertEqual(controller.currentIndex, 0)
    }

    // MARK: - 用例 3：列表随机一轮内每条恰好一次

    func testShuffleVisitsEveryItemExactlyOncePerRound() {
        let (controller, _) = makeController(random: SeededRandomSource(seed: 42))
        controller.setItems(Self.threeItems)
        controller.setMode(.shuffle)
        controller.start()

        // 两次完整轮次（一轮 = 3 条）。
        for _ in 0..<6 { controller.advanceNow() }

        let idx = controller.advances.map(\.index)
        XCTAssertEqual(idx.count, 6)
        let round1 = Array(idx[0..<3])
        let round2 = Array(idx[3..<6])
        XCTAssertEqual(Set(round1), [0, 1, 2], "第一轮内必须无重复、无遗漏（TEST-03）")
        XCTAssertEqual(round1.count, 3)
        XCTAssertEqual(Set(round2), [0, 1, 2], "第二轮同样每条恰好一次")
        XCTAssertEqual(round2.count, 3)
        // 判据加严：「顺序轮转」实现（nextIndex = (currentIndex + 1) % items.count）同样满足
        // 上面两个「每轮是排列」的断言 —— 必须用已冻结的 seed=42 真实顺序把它抓住。
        // 该顺序由 SeededRandomSource 的冻结算法（播种散列 + xorshift64 +
        // Fisher–Yates）唯一决定。
        XCTAssertEqual(idx, [1, 0, 2, 2, 1, 0],
                       "seed=42 的冻结顺序 —— 顺序轮转会给 [1,2,0,1,2,0]，被这条抓住")
    }

    // MARK: - 用例 4：同 seed 逐字相同、不同 seed 至少一个不同、注入源真的被调

    func testShuffleOrderIsIdenticalForSameSeedAndDiffersForAnotherSeed() {
        func order(seed: UInt64) -> [Int] {
            let (controller, _) = makeController(random: SeededRandomSource(seed: seed))
            controller.setItems(Self.threeItems)
            controller.setMode(.shuffle)
            controller.start()
            for _ in 0..<3 { controller.advanceNow() }
            return controller.advances.map(\.index)
        }

        // 上半句：同一个 seed 跑两次，顺序逐字相同。
        let first42 = order(seed: 42)
        let second42 = order(seed: 42)
        XCTAssertEqual(first42, second42, "同 seed 两次的顺序必须完全相同（判据可复现）")

        // 下半句：不同 seed 给出不同顺序 —— 这是这条用例有牙齿的原因：
        // 只判上半句的话，一个恒返回同一个 index 的实现照样绿。
        let order43 = order(seed: 43)
        XCTAssertNotEqual(first42, order43,
                          "seed 43 与 seed 42 必须给出不同顺序（本机实测 42→[1,0,2]、43→[0,1,2]）")

        // 另一侧确认：洗袋真的调了注入的随机源 —— 绕过 seam 直接用系统随机的实现会让同
        // seed 不可复现，上半句已经红；这里再证明注入源被调。
        let counting = CountingRandomSource()
        let (controller, _) = makeController(random: counting)
        controller.setItems(Self.threeItems)
        controller.setMode(.shuffle)
        controller.start()
        controller.advanceNow()
        XCTAssertGreaterThan(counting.calls, 0, "洗袋必须调用注入的随机源")
    }

    // MARK: - 用例 5：到点就切 —— 不等播完，不需要任何片长概念

    func testRotationElapsedAdvancesWithoutWaitingForPlayback() {
        let (controller, scheduler) = makeController(random: SeededRandomSource(seed: 42))
        controller.setItems(Self.threeItems)
        controller.setMode(.loopList)
        controller.setInterval(5)
        controller.start()

        XCTAssertEqual(scheduler.scheduleCount, 1, "start() 用 interval 排首程")

        let indexBeforeFire = controller.currentIndex
        scheduler.fire()

        XCTAssertNotEqual(controller.currentIndex, indexBeforeFire,
                          "到点回调必须推进 —— 全程没有构造任何播放器、没有设任何播放时长")
        XCTAssertEqual(controller.advances.last?.reason, .rotationElapsed,
                       "到点切换的 reason 必须是 .rotationElapsed")
        XCTAssertEqual(scheduler.scheduleCount, 2, "切完立刻重排下一程")
    }

    // MARK: - 用例 6：空列表不打点、不回调、不崩（装配的前置）

    func testEmptyListAdvancesNothingAndCallsOnAdvanceZeroTimes() {
        let (controller, scheduler) = makeController(random: SeededRandomSource(seed: 42))
        var onAdvanceCalls = 0
        controller.onAdvance = { _ in onAdvanceCalls += 1 }

        controller.setItems([])
        controller.start()
        for _ in 0..<3 { controller.advanceNow() }

        XCTAssertEqual(onAdvanceCalls, 0, "空列表时 onAdvance 必须被调 0 次")
        XCTAssertEqual(controller.advances.isEmpty, true, "空列表不打点")
        XCTAssertNil(controller.current, "空列表时 current 为 nil")
        XCTAssertEqual(scheduler.scheduleCount, 0, "空列表不排程 —— 定时器自然熄火")
    }

    // MARK: - 用例 7：模式与间隔变更当场生效，不需要重建控制器

    func testModeAndIntervalChangesTakeEffectOnNextAdvance() {
        let (controller, scheduler) = makeController(random: SeededRandomSource(seed: 42))
        controller.setItems(Self.threeItems)
        controller.setMode(.loopList)
        controller.start()

        // 走一步：0 → 1（停在 1，从 1 出发时列表循环与单循环给不同结果，
        // 这是「切换生效」的判别点）。
        controller.advanceNow()
        XCTAssertEqual(controller.currentIndex, 1)

        // 切到单循环：下一次 advance 就按新模式走（当场生效）。轮换路径驱动 ——
        // 锁定的语义只约束到点那一路。
        controller.setMode(.loopSingle)
        scheduler.fire()
        XCTAssertEqual(controller.currentIndex, 0,
                       "从 1 出发，单循环必须回到 0 —— 列表循环会给 2，被这条区分")

        // 切回列表循环走两步：按序前进 0 → 1 → 2。
        controller.setMode(.loopList)
        controller.advanceNow()
        controller.advanceNow()
        XCTAssertEqual(controller.currentIndex, 2)
        XCTAssertEqual(controller.advances.map(\.index), [1, 0, 1, 2])

        // 间隔变更当场重排程。
        let scheduleCountBeforeIntervalChange = scheduler.scheduleCount
        controller.setInterval(30)
        XCTAssertGreaterThan(scheduler.scheduleCount, scheduleCountBeforeIntervalChange,
                             "setInterval 必须当场重排程")
        XCTAssertNotNil(scheduler.pending, "重排程后必须有 pending 的下一程")
    }

    // MARK: - 用例 8：单循环下用户显式「立即下一个」照样换片

    func testUserRequestedAdvancesInLoopSingle() {
        let (controller, _) = makeController(random: SeededRandomSource(seed: 42))
        controller.setItems(Self.threeItems)
        controller.setMode(.loopSingle)
        controller.start()

        for _ in 0..<3 { controller.advanceNow() }

        XCTAssertEqual(controller.advances.map(\.index), [1, 2, 0],
                       "单循环下用户要求下一个必须按列表前进 —— 恒返 [0,0,0] 是 G-04-3")
        XCTAssertTrue(controller.advances.allSatisfy { $0.reason == .userRequested },
                      "这条路径全程是用户意图")
        XCTAssertEqual(controller.currentIndex, 0, "三条一轮，走完三条回到 0")
    }

    // MARK: - 用例 9：轮换到点在单循环下仍锁定同一条

    func testRotationElapsedHoldsLoopSingleLocked() {
        let (controller, scheduler) = makeController(random: SeededRandomSource(seed: 42))
        controller.setItems(Self.threeItems)
        controller.setMode(.loopSingle)
        controller.setInterval(5)
        controller.start()

        for _ in 0..<3 { scheduler.fire() }

        XCTAssertEqual(controller.advances.map(\.index), [0, 0, 0],
                       "轮换到点在单循环下必须锁死在同一条")
        XCTAssertTrue(controller.advances.allSatisfy { $0.reason == .rotationElapsed },
                      "这条路径全程是轮换，不是用户意图")
        XCTAssertEqual(scheduler.scheduleCount, 4,
                       "start 排 1 次 + 每次切完重排 3 次")
    }
}
