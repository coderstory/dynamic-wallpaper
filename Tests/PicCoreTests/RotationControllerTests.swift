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
    private static let threeItems: [URL] = [
        URL(fileURLWithPath: "/tmp/pic-0402-fixture/v0.mp4"),
        URL(fileURLWithPath: "/tmp/pic-0402-fixture/v1.mp4"),
        URL(fileURLWithPath: "/tmp/pic-0402-fixture/v2.mp4"),
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
        controller.onAdvance = { loaded.append($0.path) }
        controller.start()

        // start 装载首条一次；之后到点解析出的下标恒等于当前下标（=0），
        // 绝不能再走 onAdvance —— 每一次 onAdvance 下游都是 player.load(url:)，
        // 重建 item + looper、播放头归零，等于「每到一个间隔从头重播一次」。
        for _ in 0..<3 { scheduler.fire() }

        XCTAssertEqual(loaded, [Self.threeItems[0].path],
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
            var played: [URL] = []
            controller.onAdvance = { played.append($0) }
            controller.start()
            XCTAssertEqual(played.count, 1, "start() 必须交出首条")
            firstItems.insert(played[0].path)
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
        var played: [URL] = []
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
        var played: [URL] = []
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

        // 停在 1：从 1 出发时列表循环给 2、单循环原地不动，这是「切换生效」的判别点
        controller.advanceNow()
        XCTAssertEqual(controller.currentIndex, 1)

        // 用 fire() 而非 advanceNow()：advanceNow 是用户路径，锁定的语义只约束到点那一路。
        // 到点锁定 = 原地续播（下标不变、不重新装载），不是「跳回第 0 条」。
        controller.mode = .loopSingle
        scheduler.fire()
        XCTAssertEqual(controller.currentIndex, 1,
                       "从 1 出发，单循环到点必须原地不动 —— 列表循环会给 2，被这条区分")

        controller.mode = .loopList
        controller.advanceNow()
        controller.advanceNow()
        XCTAssertEqual(controller.currentIndex, 0)
        XCTAssertEqual(controller.advances.map(\.index), [1, 1, 2, 0])

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

    // ── 手动暂停轮换（菜单「暂停」= 连定时器一起停）──

    /// 暂停后：定时器取消、倒计时冻结（读数与真实时钟无关）。
    func testPauseCancelsTimerAndFreezesCountdown() {
        let (controller, scheduler) = makeController(random: SeededRandomSource(seed: 42))
        controller.setItems(Self.threeItems)
        controller.mode = .loopList
        controller.start()

        controller.pauseRotation()

        XCTAssertNil(scheduler.pending, "暂停后不得有挂在 runloop 上的定时器")
        let frozen = controller.secondsUntilNextRotation()
        XCTAssertNotNil(frozen, "暂停期间倒计时应冻结而不是消失")
        // 冻结读数与真实时钟无关：把 now 推到一分钟后，读数不变。
        XCTAssertEqual(controller.secondsUntilNextRotation(now: Date().addingTimeInterval(60)),
                       frozen)
        XCTAssertEqual(frozen ?? 0, controller.interval, accuracy: 5,
                       "刚 start 就暂停，剩余应接近完整间隔")
    }

    /// 暂停幂等：重复 pause 只 cancel 一次，冻结读数不被覆盖。
    func testPauseIsIdempotent() {
        let (controller, scheduler) = makeController(random: SeededRandomSource(seed: 42))
        controller.setItems(Self.threeItems)
        controller.mode = .loopList
        controller.start()

        controller.pauseRotation()
        let frozen = controller.secondsUntilNextRotation()
        controller.pauseRotation()

        XCTAssertEqual(scheduler.cancelCount, 1)
        XCTAssertEqual(controller.secondsUntilNextRotation(), frozen)
    }

    /// 恢复按冻结的剩余时间重排，而不是重置为完整间隔。
    func testResumeReschedulesWithFrozenRemaining() {
        let (controller, scheduler) = makeController(random: SeededRandomSource(seed: 42))
        controller.setItems(Self.threeItems)
        controller.mode = .loopList
        controller.start()

        controller.pauseRotation()
        let frozen = controller.secondsUntilNextRotation()!
        controller.resumeRotation()

        XCTAssertEqual(scheduler.scheduleCount, 2, "start 一次 + 恢复一次")
        // 恢复后的读数从冻结值继续走真实时钟：此刻应仍接近冻结值（测试瞬时执行）。
        let after = controller.secondsUntilNextRotation()!
        XCTAssertLessThanOrEqual(after, frozen + 1)
        XCTAssertGreaterThan(after, frozen - 5)
    }

    /// 暂停期间「立即下一个」：切换照常发生（用户意图优先），但**不**启动定时器，
    /// 剩余重置为完整间隔 —— 刚切过一片，恢复后从头数。
    func testAdvanceNowWhilePausedSwitchesWithoutArmingTimer() {
        let (controller, scheduler) = makeController(random: SeededRandomSource(seed: 42))
        controller.setItems(Self.threeItems)
        controller.mode = .loopList
        controller.start()
        let startedIndex = controller.currentIndex

        controller.pauseRotation()
        controller.advanceNow()

        XCTAssertEqual(controller.currentIndex, (startedIndex + 1) % Self.threeItems.count,
                       "暂停期间用户要下一条，切换照常")
        XCTAssertNil(scheduler.pending)
        XCTAssertEqual(controller.remainingAtPause, controller.interval)
        XCTAssertEqual(controller.secondsUntilNextRotation(), controller.interval)
    }

    /// 未 start / 已 stop 时暂停是空操作；恢复在未暂停时也是空操作。
    func testPauseResumeGuards() {
        let (controller, scheduler) = makeController(random: SeededRandomSource(seed: 42))
        controller.setItems(Self.threeItems)
        controller.mode = .loopList

        controller.pauseRotation()
        XCTAssertEqual(scheduler.cancelCount, 0, "未运行时暂停不碰调度器")

        controller.start()
        controller.resumeRotation()
        XCTAssertEqual(scheduler.scheduleCount, 1, "未暂停时恢复是空操作")

        controller.pauseRotation()
        controller.stop()
        controller.resumeRotation()
        XCTAssertNil(controller.secondsUntilNextRotation(), "stop 之后恢复不得复活定时器")
    }

    // ── 单循环续播：start(resumingAt:) ──

    /// 定点启动：从上次播放的文件接着来，而不是清单第一条。
    func testStartResumingAtLoadsThatItem() {
        let (controller, scheduler) = makeController(random: SeededRandomSource(seed: 42))
        controller.setItems(Self.threeItems)
        controller.mode = .loopSingle

        var loaded: [URL] = []
        controller.onAdvance = { loaded.append($0) }
        controller.start(resumingAt: Self.threeItems[2])

        XCTAssertEqual(controller.currentIndex, 2)
        XCTAssertEqual(loaded, [Self.threeItems[2]], "首条装载必须是定点的那条")
        XCTAssertNotNil(scheduler.pending, "定点启动同样要排下一程")
    }

    /// 定点文件已不在清单里（被删 / 换目录）→ 回退成普通 start（第一条）。
    func testStartResumingAtMissingFileFallsBackToFirst() {
        let (controller, scheduler) = makeController(random: SeededRandomSource(seed: 42))
        controller.setItems(Self.threeItems)
        controller.mode = .loopSingle

        var loaded: [URL] = []
        controller.onAdvance = { loaded.append($0) }
        controller.start(resumingAt: URL(fileURLWithPath: "/tmp/pic-0402-fixture/gone.mp4"))

        XCTAssertEqual(controller.currentIndex, 0)
        XCTAssertEqual(loaded, [Self.threeItems[0]], "回退 = 普通 start 的首条")
        XCTAssertNotNil(scheduler.pending)
    }

    /// 空清单：定点启动是空操作（与 start() 的降级路径一致）。
    func testStartResumingAtWithEmptyItemsDoesNothing() {
        let (controller, scheduler) = makeController(random: SeededRandomSource(seed: 42))
        controller.mode = .loopSingle

        var fired = false
        controller.onAdvance = { _ in fired = true }
        controller.start(resumingAt: Self.threeItems[0])

        XCTAssertFalse(fired)
        XCTAssertNil(scheduler.pending)
    }

    /// 这条在防：loopSingle + 续播（下标 ≠ 0）后，到点被写死成 items[0]，
    /// 播一个间隔就跳回清单第一条并从此钉死。锁定 = 原地续播，下标不变、不重新装载。
    func testLoopSingleRotationElapsedHoldsResumedIndex() {
        let (controller, scheduler) = makeController(random: SeededRandomSource(seed: 42))
        controller.setItems(Self.threeItems)
        controller.mode = .loopSingle

        var loaded: [URL] = []
        controller.onAdvance = { loaded.append($0) }
        controller.start(resumingAt: Self.threeItems[2])

        scheduler.fire()

        XCTAssertEqual(controller.current, Self.threeItems[2],
                       "从第 3 条续播，到点必须仍是同一条 —— 写死 items[0] 的实现被这条抓住")
        XCTAssertEqual(loaded, [Self.threeItems[2]],
                       "start 已装载过，到点不重新装载（重载即播放头归零）")
        XCTAssertEqual(controller.advances.last?.index, 2,
                       "打点落在续播那条上，而不是第 0 条")
    }

    /// 这条在防：锁定语义被矫枉过正成「loopSingle 下到点、用户点都不换」——
    /// 「立即下一个」必须照旧按列表前进并重新装载，锁定只约束轮换到点那一路。
    func testLoopSingleUserRequestedStillAdvancesAndReloads() {
        let (controller, _) = makeController(random: SeededRandomSource(seed: 42))
        controller.setItems(Self.threeItems)
        controller.mode = .loopSingle
        controller.start(resumingAt: Self.threeItems[2])

        var loaded: [URL] = []
        controller.onAdvance = { loaded.append($0) }
        controller.advanceNow()

        XCTAssertEqual(controller.current, Self.threeItems[0],
                       "用户要下一条：从 2 前进取模回卷到 0，不得被锁定卡住")
        XCTAssertEqual(loaded, [Self.threeItems[0]],
                       "用户路径必须重新装载 —— 恒不装载 = 锁定泄漏到了用户意图上")
        XCTAssertEqual(controller.advances.last?.reason, .userRequested)
    }
}
