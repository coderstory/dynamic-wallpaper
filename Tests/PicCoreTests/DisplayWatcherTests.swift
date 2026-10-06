// 熄屏与睡眠是两条各自独立的 reason：叠加时先解除哪个都不恢复，都清空才 seek 且只 seek 一次。
// `start()` 不投递任何通知也必须当场把当前状态算一遍。`System/` 与 `State/` 零 AVFoundation。
// `FakeTarget` 是本文件本地的等价实现，不要改成引用 `HoldArbiterTests` 里那一个 ——
// 测试替身跨文件耦合后，失败时分不清是替身坏了还是被测代码坏了。

import XCTest
@testable import PicCore

@MainActor
final class DisplayWatcherTests: XCTestCase {

    private final class FakeTarget: PlaybackTarget {
        var position: TimeInterval = 0
        var seeks: [TimeInterval] = []
        var applies: [PlaybackDecision] = []

        func arbiterCurrentPosition() -> TimeInterval { position }
        func arbiterSeek(to seconds: TimeInterval) { seeks.append(seconds) }
        func arbiterApply(_ decision: PlaybackDecision) { applies.append(decision) }
    }

    /// 替身：接住重配置回调，测试不必真触发一次显示器重配置。
    private final class RecordingReconfigurationHook: DisplayReconfigurationHook {
        private(set) var registerCount = 0
        private(set) var unregisterCount = 0
        var registerResult = true
        private var handler: (() -> Void)?

        @discardableResult
        func register(_ onReconfigured: @escaping () -> Void) -> Bool {
            registerCount += 1
            handler = onReconfigured
            return registerResult
        }

        func unregister() {
            unregisterCount += 1
            handler = nil
        }

        /// 模拟一次显示器重配置 —— 熄屏、唤醒、热插拔都会走到这个回调。
        func fire() { handler?() }
    }

    @MainActor
    private final class ArbiterSpy {
        let arbiter: HoldArbiter
        private(set) var setCalls: [(reason: HoldReason, active: Bool)] = []

        init(target: PlaybackTarget) { arbiter = HoldArbiter(target: target) }

        /// 模拟装配层接线：一份 `DisplaySignals` 拆成两次 `set`。
        func apply(_ signals: DisplaySignals) {
            setCalls.append((.displayAsleep, signals.displayAsleep))
            arbiter.set(.displayAsleep, active: signals.displayAsleep)
            setCalls.append((.systemSleeping, signals.systemSleeping))
            arbiter.set(.systemSleeping, active: signals.systemSleeping)
        }

        func resetCalls() { setCalls.removeAll() }
    }

    /// 跑一段主 run loop，等 `queue: .main` 异步投递的通知落地。
    private func spin(seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// 熄屏与睡眠是**两条** reason。只置熄屏时 `holds` 里**不许**出现 `systemSleeping`，反之亦然 ——
    /// 这条一旦不成立，叠加语义与清空语义也就无从谈起。
    func testDisplayAsleepAndSystemSleepingAreIndependentReasons() {
        let target = FakeTarget()
        target.position = 42.0
        let spy = ArbiterSpy(target: target)

        spy.apply(DisplaySignals(displayAsleep: true, systemSleeping: false))
        XCTAssertEqual(spy.arbiter.decision.holds, [.displayAsleep],
                       "只置熄屏时 holds 里不得出现 systemSleeping")
        XCTAssertFalse(spy.arbiter.decision.shouldPlay)
        XCTAssertTrue(target.seeks.isEmpty, "进入 hold 只记锚点，不 seek")

        spy.apply(DisplaySignals(displayAsleep: false, systemSleeping: false))
        XCTAssertTrue(spy.arbiter.decision.shouldPlay, "熄屏解除后应当恢复播放")
        XCTAssertEqual(target.seeks, [42.0], "从进 hold 时的位置续播（D-15）")

        spy.apply(DisplaySignals(displayAsleep: false, systemSleeping: true))
        XCTAssertEqual(spy.arbiter.decision.holds, [.systemSleeping],
                       "只置睡眠时 holds 里不得出现 displayAsleep")
        XCTAssertFalse(spy.arbiter.decision.shouldPlay)

        spy.apply(DisplaySignals(displayAsleep: false, systemSleeping: false))
        XCTAssertTrue(spy.arbiter.decision.shouldPlay, "睡眠解除后应当恢复播放")
        XCTAssertEqual(target.seeks, [42.0, 42.0], "第二次进 hold 记了新锚点")
    }

    /// 唤醒不等于恢复：睡眠结束而显示器仍熄着时还有一个 hold，就一律不播。
    /// 覆盖式实现（唤醒时顺手把 `holds` 清空）会让下面两条转红：合上盖子再打开、屏幕还没亮的那一秒壁纸就播了。
    /// 把两个字段耦合到同一来源后，`holds` 断言也转红。
    func testWakingWithDisplayStillAsleepDoesNotResume() {
        let target = FakeTarget()
        target.position = 42.0
        let spy = ArbiterSpy(target: target)

        // 熄屏 + 睡眠同时置位（合上盖子：屏灭 + 机器睡）
        spy.apply(DisplaySignals(displayAsleep: true, systemSleeping: true))
        XCTAssertEqual(spy.arbiter.decision.holds, [.displayAsleep, .systemSleeping])
        XCTAssertFalse(spy.arbiter.decision.shouldPlay)
        XCTAssertTrue(target.seeks.isEmpty, "进入 hold 不 seek")

        // 唤醒：只解除睡眠，熄屏仍在（打开盖子，屏幕还没亮的那一瞬）
        spy.apply(DisplaySignals(displayAsleep: true, systemSleeping: false))
        XCTAssertEqual(spy.arbiter.decision.holds, [.displayAsleep],
                       "唤醒只解除 systemSleeping —— 熄屏仍在，holds 不得被覆盖成空集")
        XCTAssertFalse(spy.arbiter.decision.shouldPlay, "熄屏仍在 → 一律不播")
        XCTAssertTrue(target.seeks.isEmpty, "唤醒那一瞬不得有任何 seek —— 有 seek 就是续播被提前触发了")
    }

    /// 睡眠通知、唤醒通知与重配置回调**三个入口**必须汇入同一条重算路径。
    func testOnlyAfterBothClearDoesItSeekToAnchor() {
        let target = FakeTarget()
        target.position = 42.0
        let spy = ArbiterSpy(target: target)

        let center = NotificationCenter()
        let hook = RecordingReconfigurationHook()
        var displayAsleep = true                       // 注入值，不依赖本机显示器状态
        let watcher = DisplayWatcher(
            notificationCenter: center,
            displayAsleepReader: { displayAsleep },
            reconfigurationHook: hook
        )

        watcher.start { spy.apply($0) }
        XCTAssertEqual(spy.arbiter.decision.holds, [.displayAsleep], "start() 必须同步算一次当前状态")
        XCTAssertTrue(target.seeks.isEmpty, "启动时就在 hold 中，只记锚点不 seek")

        center.post(name: DisplayWatcher.sleepNotificationName, object: nil)
        spin(seconds: 0.3)
        XCTAssertEqual(spy.arbiter.decision.holds, [.displayAsleep, .systemSleeping])

        center.post(name: DisplayWatcher.wakeNotificationName, object: nil)
        spin(seconds: 0.3)
        XCTAssertEqual(spy.arbiter.decision.holds, [.displayAsleep], "唤醒后仍熄屏 → 只解 systemSleeping")
        XCTAssertTrue(target.seeks.isEmpty, "熄屏仍在 → 一个 seek 都不许有")

        // 屏幕点亮：重配置回调也汇入同一条重算路径
        displayAsleep = false
        hook.fire()
        XCTAssertEqual(spy.arbiter.decision.holds, [], "两个都清空才恢复")
        XCTAssertTrue(spy.arbiter.decision.shouldPlay)
        XCTAssertEqual(target.seeks, [42.0], "两个都清空才 seek，且 seek 到进 hold 时的位置")
        XCTAssertEqual(target.seeks.count, 1, "只 seek 一次 —— 重复 seek 会把续播点推走")

        watcher.stop()
    }

    /// 装配层改成「一次性清空两个 reason」会让本条转红 —— 两个 reason 的解除路径必须各自可测，
    /// 绑成一根绳后，其中一个信号源坏掉时另一个也查不出来。
    func testSignalsAllFalseProducesTwoSetCallsOnClear() {
        let target = FakeTarget()
        target.position = 42.0
        let spy = ArbiterSpy(target: target)

        spy.apply(DisplaySignals(displayAsleep: true, systemSleeping: true))
        XCTAssertEqual(spy.setCalls.count, 2, "置位时也是两次 set —— 一个 reason 一次")

        spy.resetCalls()
        spy.apply(DisplaySignals(displayAsleep: false, systemSleeping: false))

        XCTAssertEqual(spy.setCalls.count, 2, "全部清空时必须是两次 set，不是一次批量清空")
        XCTAssertEqual(spy.setCalls.map(\.reason), [.displayAsleep, .systemSleeping],
                       "两个 reason 各清一次，顺序固定")
        XCTAssertEqual(spy.setCalls.map(\.active), [false, false])
        XCTAssertEqual(target.seeks, [42.0], "两次 set 走完仲裁器，只产生一次续播 seek")
    }

    /// 跃迁通知只在状态变化时投递，不熄屏也不睡眠的机器永远等不到 —— 少了那次同步重算，
    /// 装配层读到的是默认的 `DisplaySignals(false, false)`。
    /// 夹具把 `displayAsleepReader` 注入成恒 `true`，换一台屏幕亮着的机器也照样过。
    func testStartRecomputesOnceSynchronously() {
        let center = NotificationCenter()
        let hook = RecordingReconfigurationHook()
        let watcher = DisplayWatcher(
            notificationCenter: center,
            displayAsleepReader: { true },
            reconfigurationHook: hook
        )

        var deliveries: [DisplaySignals] = []
        watcher.start { deliveries.append($0) }

        XCTAssertEqual(deliveries.count, 1, "start() 返回前必须同步重算一次")
        XCTAssertEqual(deliveries.first, watcher.currentSignals(), "同步投递的必须是此刻的真实状态")
        XCTAssertEqual(deliveries.first?.displayAsleep, true, "夹具前提：注入的读数恒为熄屏")
        XCTAssertEqual(deliveries.first?.systemSleeping, false, "启动时没有睡眠通知 → 睡眠位为 false")
        XCTAssertTrue(watcher.isRunning)
        XCTAssertTrue(watcher.isReconfigurationRegistered, "重配置回调注册失败就没有唤醒后的重算入口")
        XCTAssertEqual(hook.registerCount, 1)

        // 锁系统真名：合成事件靠它精确定位，投成别的名字会静默失效
        XCTAssertEqual(DisplayWatcher.sleepNotificationName.rawValue, "NSWorkspaceWillSleepNotification")
        XCTAssertEqual(DisplayWatcher.wakeNotificationName.rawValue, "NSWorkspaceDidWakeNotification")

        watcher.start { _ in XCTFail("重复 start() 不得接管回调") }
        XCTAssertEqual(deliveries.count, 1, "重复 start() 不再同步重算")
        XCTAssertEqual(hook.registerCount, 1, "重复 start() 不得重复注册重配置回调")

        watcher.stop()
        XCTAssertFalse(watcher.isRunning)
        XCTAssertEqual(hook.unregisterCount, 1, "stop() 必须摘掉重配置回调")
        XCTAssertFalse(watcher.isReconfigurationRegistered)

        center.post(name: DisplayWatcher.sleepNotificationName, object: nil)
        spin(seconds: 0.3)
        XCTAssertEqual(deliveries.count, 1, "stop() 之后不得再收到通知")
    }
}
