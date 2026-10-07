import XCTest
@testable import PicCore

/// 轮换器与播放器解耦：全程不存在任何 AV 对象，也没有「片长」这个概念 ——
/// `ManualScheduler.fire()` 直接把时间推进到下一程。
/// `ManualScheduler` 是本文件本地替身，不要跨文件引用别的测试类里的调度器。
@MainActor
final class RotationControllerTests: XCTestCase {

    /// 不挂 runloop、不读片长，时长完全由测试掌控。
    final class ManualScheduler: RotationScheduling {
        private(set) var pending: (@MainActor () -> Void)?
        private(set) var scheduleCount = 0
        private(set) var cancelCount = 0

        func schedule(after interval: TimeInterval, _ body: @escaping @MainActor () -> Void) {
            pending = body
            scheduleCount += 1
        }

        func cancel() {
            pending = nil
            cancelCount += 1
        }

        /// 触发后清空 `pending`，与一次性定时器同语义。
        /// 标 `@MainActor`：本类不能整体标（协议 `RotationScheduling` 是非隔离的，标了会报
        /// `#ConformanceIsolation`），但调 `pending` 必须回到主线程 —— 那正是它被注入的契约。
        @MainActor
        func fire() {
            let body = pending
            pending = nil
            body?()
        }
    }

    /// 判据是「洗袋真的调了注入源」：实现压根不调 `random` 时 `calls` 恒为 0。
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

    /// 三条视频。文件名随便造：`VideoItem` 只吃 `URL`，不碰磁盘。
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

    func testLoopSingleAlwaysReturnsTheSameItem() {
        let (controller, scheduler) = makeController(random: SeededRandomSource(seed: 42))
        controller.setItems(Self.threeItems)
        controller.mode = .loopSingle
        controller.start()

        // 只驱动「到点」这一路：用户显式「立即下一个」是另一条路径，按 reason 分流到用例 8
        for _ in 0..<5 { scheduler.fire() }

        XCTAssertEqual(controller.currentIndex, 0,
                       "单循环下 currentIndex 必须恒为 0 —— 不前进")
        XCTAssertEqual(controller.advances.map(\.index), [0, 0, 0, 0, 0],
                       "5 次切换全部落在同一条上")
        XCTAssertEqual(controller.current, Self.threeItems[0])
    }

    func testLoopSingleRotationElapsedDoesNotReloadSameItem() {
        let (controller, scheduler) = makeController(random: SeededRandomSource(seed: 42))
        controller.setItems(Self.threeItems)
        controller.mode = .loopSingle
        var loaded: [String] = []
        controller.onAdvance = { loaded.append($0.url.path) }
        controller.start()

        // start 装载首条一次；之后到点解析出的下标恒等于当前下标（=0），
        // 绝不能再走 onAdvance —— 每一次 onAdvance 下游都是 player.load(url:)，
        // 重建 item + looper、播放头归零，等于「每到一个间隔从头重播一次」。
        for _ in 0..<3 { scheduler.fire() }

        XCTAssertEqual(loaded, [Self.threeItems[0].url.path],
                       "单循环到点只应装载一次（start 那次）；重载即播放头归零")
        XCTAssertEqual(controller.advances.map(\.index), [0, 0, 0],
                       "切换打点照旧落在同一条 —— 只砍装载，不动索引语义")
    }

    func testLoopListWalksEveryItemThenWrapsToFirst() {
        let (controller, _) = makeController(random: SeededRandomSource(seed: 42))
        controller.setItems(Self.threeItems)
        controller.mode = .loopList
        controller.start()

        for _ in 0..<6 { controller.advanceNow() }

        XCTAssertEqual(controller.advances.map(\.index), [1, 2, 0, 1, 2, 0],
                       "三条列表：顺序前进、取模回卷")
        XCTAssertEqual(controller.currentIndex, 0)
    }

    /// 随机模式的首条必须是抽出来的。`start()` 写死 `items[0]` 的症状是：
    /// 每次启动 app 看到的第一个壁纸都一样，且它在第一轮里会再出现一次。
    func testShuffleFirstItemVariesAcrossSeeds() {
        var firstItems: Set<String> = []
        for seed in 1...12 {
            let (controller, _) = makeController(random: SeededRandomSource(seed: UInt64(seed)))
            controller.setItems(Self.threeItems)
            controller.mode = .shuffle
            var played: [VideoItem] = []
            controller.onAdvance = { played.append($0) }
            controller.start()
            XCTAssertEqual(played.count, 1, "start() 必须交出首条")
            firstItems.insert(played[0].url.path)
        }
        XCTAssertGreaterThan(firstItems.count, 1,
                             "随机模式的首条不得恒定 —— 恒为 items[0] 就是「每次开 app 第一张壁纸都一样」")
    }

    /// 首条必须取自洗牌袋，且取走后不回袋 —— 否则第一轮里它会播两次。
    /// 判据用注入序列（`CountingRandomSource` 给 [0,1,2]）：洗完袋顺序为 [2,1,0]，
    /// 于是首条是索引 2，紧接着的两次切换必须正好是剩下的 1 和 0。
    func testShuffleFirstItemIsDrawnFromTheBagAndNotRepeated() {
        let (controller, _) = makeController(random: CountingRandomSource())
        controller.setItems(Self.threeItems)
        controller.mode = .shuffle
        var played: [VideoItem] = []
        controller.onAdvance = { played.append($0) }
        controller.start()
        controller.advanceNow()
        controller.advanceNow()

        let indices = played.map { item in Self.threeItems.firstIndex(of: item)! }
        XCTAssertEqual(indices[0], 2, "首条按注入的洗牌结果取 items[2]，不是写死的 items[0]")
        XCTAssertEqual(indices, [2, 1, 0], "第一轮三条互不重复 —— 首条已从袋里取走")
    }

    func testShuffleVisitsEveryItemExactlyOncePerRound() {
        let (controller, _) = makeController(random: SeededRandomSource(seed: 42))
        controller.setItems(Self.threeItems)
        controller.mode = .shuffle
        // 一轮的边界从**首条**起算：`start()` 交出的那一条是这一轮的第一条，
        // 只是不计进 `advances`。只统计 advances 会把首条漏在读数的外面。
        var played: [VideoItem] = []
        controller.onAdvance = { played.append($0) }
        controller.start()

        for _ in 0..<5 { controller.advanceNow() }

        let idx = played.map { item in Self.threeItems.firstIndex(of: item)! }
        XCTAssertEqual(idx.count, 6)
        let round1 = Array(idx[0..<3])
        let round2 = Array(idx[3..<6])
        XCTAssertEqual(Set(round1), [0, 1, 2], "第一轮内必须无重复、无遗漏（TEST-03）")
        XCTAssertEqual(round1.count, 3)
        XCTAssertEqual(Set(round2), [0, 1, 2], "第二轮同样每条恰好一次")
        XCTAssertEqual(round2.count, 3)
        // 上面两条「每轮是排列」顺序轮转也满足，只有 seed=42 的精确顺序能抓住它。
        // 该顺序由 SeededRandomSource 的冻结算法（播种散列 + xorshift64 + Fisher–Yates）唯一决定 ——
        // 别动这个 seed，也别改期望值。
        XCTAssertEqual(idx, [1, 0, 2, 2, 1, 0],
                       "seed=42 的冻结顺序 —— 顺序轮转会给 [1,2,0,1,2,0]，被这条抓住")
    }

    func testShuffleOrderIsIdenticalForSameSeedAndDiffersForAnotherSeed() {
        func order(seed: UInt64) -> [Int] {
            let (controller, _) = makeController(random: SeededRandomSource(seed: seed))
            controller.setItems(Self.threeItems)
            controller.mode = .shuffle
            controller.start()
            for _ in 0..<3 { controller.advanceNow() }
            return controller.advances.map(\.index)
        }

        let first42 = order(seed: 42)
        let second42 = order(seed: 42)
        XCTAssertEqual(first42, second42, "同 seed 两次的顺序必须完全相同（判据可复现）")

        // 下半句才有牙齿：只判上半句的话，一个恒返回同一个 index 的实现照样绿
        let order43 = order(seed: 43)
        XCTAssertNotEqual(first42, order43,
                          "seed 43 与 seed 42 必须给出不同顺序（本机实测 42→[1,0,2]、43→[0,1,2]）")

        let counting = CountingRandomSource()
        let (controller, _) = makeController(random: counting)
        controller.setItems(Self.threeItems)
        controller.mode = .shuffle
        controller.start()
        controller.advanceNow()
        XCTAssertGreaterThan(counting.calls, 0, "洗袋必须调用注入的随机源")
    }

    func testRotationElapsedAdvancesWithoutWaitingForPlayback() {
        let (controller, scheduler) = makeController(random: SeededRandomSource(seed: 42))
        controller.setItems(Self.threeItems)
        controller.mode = .loopList
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

    func testModeAndIntervalChangesTakeEffectOnNextAdvance() {
        let (controller, scheduler) = makeController(random: SeededRandomSource(seed: 42))
        controller.setItems(Self.threeItems)
        controller.mode = .loopList
        controller.start()

        // 停在 1：从 1 出发时列表循环给 2、单循环给 0，这是「切换生效」的判别点
        controller.advanceNow()
        XCTAssertEqual(controller.currentIndex, 1)

        // 用 fire() 而非 advanceNow()：advanceNow 是用户路径，锁定的语义只约束到点那一路
        controller.mode = .loopSingle
        scheduler.fire()
        XCTAssertEqual(controller.currentIndex, 0,
                       "从 1 出发，单循环必须回到 0 —— 列表循环会给 2，被这条区分")

        controller.mode = .loopList
        controller.advanceNow()
        controller.advanceNow()
        XCTAssertEqual(controller.currentIndex, 2)
        XCTAssertEqual(controller.advances.map(\.index), [1, 0, 1, 2])

        let scheduleCountBeforeIntervalChange = scheduler.scheduleCount
        controller.setInterval(30)
        XCTAssertGreaterThan(scheduler.scheduleCount, scheduleCountBeforeIntervalChange,
                             "setInterval 必须当场重排程")
        XCTAssertNotNil(scheduler.pending, "重排程后必须有 pending 的下一程")
    }

    func testUserRequestedAdvancesInLoopSingle() {
        let (controller, _) = makeController(random: SeededRandomSource(seed: 42))
        controller.setItems(Self.threeItems)
        controller.mode = .loopSingle
        controller.start()

        for _ in 0..<3 { controller.advanceNow() }

        XCTAssertEqual(controller.advances.map(\.index), [1, 2, 0],
                       "单循环下用户要求下一个必须按列表前进 —— 恒返 [0,0,0] 是 G-04-3")
        XCTAssertTrue(controller.advances.allSatisfy { $0.reason == .userRequested },
                      "这条路径全程是用户意图")
        XCTAssertEqual(controller.currentIndex, 0, "三条一轮，走完三条回到 0")
    }

    func testRotationElapsedHoldsLoopSingleLocked() {
        let (controller, scheduler) = makeController(random: SeededRandomSource(seed: 42))
        controller.setItems(Self.threeItems)
        controller.mode = .loopSingle
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

    func testSecondsUntilNextRotationGatedByRunningModeAndItemCount() {
        let (controller, _) = makeController(random: SeededRandomSource(seed: 42))
        controller.setItems(Self.threeItems)
        controller.mode = .loopList
        controller.setInterval(300)

        XCTAssertNil(controller.secondsUntilNextRotation(), "未 start 时没有下一程")

        controller.start()
        let running = controller.secondsUntilNextRotation()
        XCTAssertNotNil(running, "跑起来后必须读得到倒计时")
        XCTAssertGreaterThan(running ?? 0, 0)
        XCTAssertLessThanOrEqual(running ?? .infinity, 300, "读数不得超过 interval")

        controller.mode = .loopSingle
        XCTAssertNil(controller.secondsUntilNextRotation(), "单循环下到点不换片，倒计时指向一个不会发生的切换")

        controller.mode = .loopList
        controller.stop()
        XCTAssertNil(controller.secondsUntilNextRotation(), "stop 后必须清成 nil")

        let (single, _) = makeController(random: SeededRandomSource(seed: 42))
        single.setItems([Self.threeItems[0]])
        single.mode = .loopList
        single.start()
        XCTAssertNil(single.secondsUntilNextRotation(), "只有一条时切换不会发生")
    }
}
