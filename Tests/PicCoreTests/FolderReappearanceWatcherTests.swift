import XCTest
@testable import PicCore

/// `FolderReappearanceWatcher` 是「拔盘后再插回能不能自愈」的唯一机制，所以每条语义都要单独锁：
/// 没回来不许回调、回来了必须回调**恰一次**并自动停、重臂必须先停旧的、停止后不许再回调。
@MainActor
final class FolderReappearanceWatcherTests: XCTestCase {

    /// 手动推进的时钟：把 body 记下来，由测试决定「什么时候过了一个间隔」。
    @MainActor
    private final class ManualClock {
        private(set) var body: (@MainActor () -> Void)?
        private(set) var intervals: [TimeInterval] = []
        private(set) var stopCount = 0

        var scheduler: FolderReappearanceWatcher.Scheduler {
            { [self] interval, body in
                intervals.append(interval)
                self.body = body
                return { [self] in
                    stopCount += 1
                    self.body = nil
                }
            }
        }

        /// 让时间走一格。
        func tick() { body?() }
    }

    func testIntervalIsHandedToTheSchedulerVerbatim() {
        let clock = ManualClock()
        let watcher = FolderReappearanceWatcher(scheduler: clock.scheduler)
        watcher.awaitReturn(interval: 7, isBack: { false }, onReturned: {})
        XCTAssertEqual(clock.intervals, [7], "间隔必须原样交给调度器，不能在中途另定一个")
    }

    func testStaysWaitingWhileFolderIsStillMissing() {
        let clock = ManualClock()
        let watcher = FolderReappearanceWatcher(scheduler: clock.scheduler)
        var returned = 0

        watcher.awaitReturn(isBack: { false }, onReturned: { returned += 1 })
        XCTAssertTrue(watcher.isWaiting)

        clock.tick()
        clock.tick()
        XCTAssertEqual(returned, 0, "目录还没回来就回调 = 拿一个还是缺失态的目录去重扫")
        XCTAssertTrue(watcher.isWaiting, "没回来必须继续等")
    }

    func testFiresExactlyOnceThenStopsItself() {
        let clock = ManualClock()
        let watcher = FolderReappearanceWatcher(scheduler: clock.scheduler)
        var returned = 0
        var isBack = false

        watcher.awaitReturn(isBack: { isBack }, onReturned: { returned += 1 })
        clock.tick()
        XCTAssertEqual(returned, 0)

        isBack = true
        clock.tick()
        XCTAssertEqual(returned, 1)
        XCTAssertFalse(watcher.isWaiting, "回调后必须自动停 —— 留着它会让定时器永久空转")

        clock.tick()
        XCTAssertEqual(returned, 1, "停掉之后不得再回调")
    }

    func testStopPreventsAnyCallback() {
        let clock = ManualClock()
        let watcher = FolderReappearanceWatcher(scheduler: clock.scheduler)
        var returned = 0
        var isBack = false

        watcher.awaitReturn(isBack: { isBack }, onReturned: { returned += 1 })
        watcher.stop()
        XCTAssertFalse(watcher.isWaiting)
        XCTAssertEqual(clock.stopCount, 1, "stop 必须把停止闭包调下去，否则定时器还在跑")

        // 目录后来又回来了，但已经没人等 —— 必须一声不响。
        isBack = true
        clock.tick()
        XCTAssertEqual(returned, 0)
    }

    func testRearmingStopsThePreviousSchedule() {
        let clock = ManualClock()
        let watcher = FolderReappearanceWatcher(scheduler: clock.scheduler)

        watcher.awaitReturn(isBack: { false }, onReturned: {})
        watcher.awaitReturn(isBack: { true }, onReturned: {})
        XCTAssertEqual(clock.intervals.count, 2, "重臂必须真的再排一次")
        XCTAssertEqual(clock.stopCount, 1, "重臂前必须先停掉旧的 —— 换目录后旧定时器会用旧路径判存在性")
    }

    /// 生产调度器（真 `Task.sleep` 循环）必须真的会跑 —— 上面几条都注入替身，唯独这条验真货。
    func testProductionSchedulerTicksAndStops() async {
        let watcher = FolderReappearanceWatcher()
        var returned = 0
        var isBack = false
        let fired = expectation(description: "目录回来后必须回调")

        watcher.awaitReturn(interval: 0.02,
                            isBack: { isBack },
                            onReturned: { returned += 1; fired.fulfill() })

        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(returned, 0, "目录还没回来就回调了")
        XCTAssertTrue(watcher.isWaiting)

        isBack = true
        await fulfillment(of: [fired], timeout: 2)
        XCTAssertEqual(returned, 1)
        XCTAssertFalse(watcher.isWaiting, "回调后必须自动停")
    }
}
