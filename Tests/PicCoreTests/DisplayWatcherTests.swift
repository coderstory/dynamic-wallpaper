// DisplayWatcherTests.swift —— 熄屏（PAUSE-03）与睡眠（PAUSE-04）的两条 reason。
//
// 这一组用例守护的不是「API 能不能调通」，而是三件**结构**事实：
//
//   ① 两个 reason **各自独立**置位与解除 —— 熄屏不影响睡眠位，反之亦然。
//   ② 叠加时**先解除哪一个都不恢复播放**；只有两个都清空才 seek，**且只 seek 一次**。
//   ③ `start()` **不投递任何通知**也必须当场把当前状态算一遍（装配层的启动契约）。
//
// ①② 是本次注入式反向验证的目标：把两个字段耦合（共用一个来源）之后，
// `testWakingWithDisplayStillAsleepDoesNotResume` 必须转红 ——
// 「一条从没红过的判据不证明它会红」。
//
// ⚠️ 本文件**不引入播放框架**（`System/` 与 `State/` 零 AVFoundation）。
//    `FakeTarget` 是本文件**本地**的等价实现，不跨文件引用 `HoldArbiterTests` 里那一个 ——
//    两个测试目标里跨文件耦合测试替身，比各写一份更难排查。

import XCTest
@testable import PicCore

@MainActor
final class DisplayWatcherTests: XCTestCase {

    /// 本地记录式播放端。
    private final class FakeTarget: PlaybackTarget {
        var position: TimeInterval = 0
        var seeks: [TimeInterval] = []
        var applies: [PlaybackDecision] = []

        func arbiterCurrentPosition() -> TimeInterval { position }
        func arbiterSeek(to seconds: TimeInterval) { seeks.append(seconds) }
        func arbiterApply(_ decision: PlaybackDecision) { applies.append(decision) }
    }

    /// 单测替身：接住 `DisplayWatcher` 注册的重配置回调，不必真拔一次线就能打同一条路径。
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

    /// 薄包装：持有**真实**的仲裁器并转发，同时记录 `set` 的调用序列。
    /// 不改 `HoldArbiter` 的签名（每个信号源独立可测）。
    @MainActor
    private final class ArbiterSpy {
        let arbiter: HoldArbiter
        private(set) var setCalls: [(reason: HoldReason, active: Bool)] = []

        init(target: PlaybackTarget) { arbiter = HoldArbiter(target: target) }

        /// 装配层的接线形状：一份 `DisplaySignals` 拆成**两次** `set`。
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

    // ── 1. 两个 reason 各自独立 ──────────────────────────────────────────

    /// 熄屏与睡眠是**两条** reason，不是同一条的两个名字。
    ///
    /// 只置熄屏时 `holds` 里**不许**出现 `systemSleeping`，反之亦然 —— 这条一旦不成立，
    /// 2/3 两条的叠加语义也就无从谈起。
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

    // ── 2. 唤醒但仍熄屏 → 不得恢复（本次反向验证的落点）─────────────────

    /// **唤醒不等于恢复**：睡眠结束而显示器仍熄着时，一个 hold 还在，就一律不播。
    ///
    /// 换到熄屏 / 睡眠这一对上的经典错误 —— 覆盖式实现会让「唤醒」顺手把 `holds`
    /// 清空，于是合上盖子又打开、屏幕还没亮的那一秒，壁纸开始播。
    ///
    /// 注入式反向验证：把 `DisplaySignals` 的两个字段耦合（共用一个来源）后，
    /// 下面这条 `holds` 断言必须转红。
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

    // ── 3. 两个都清空才 seek，且只 seek 一次 ────────────────────────────

    /// 承 2 的一条，但这次**走真实的 `DisplayWatcher`**：睡眠 / 唤醒两个通知与重配置回调
    /// 都汇入同一条重算路径（Pitfall 7：唤醒后立刻重算，而不是等下一个信号）。
    ///
    /// 三个入口依次驱动：`start` → `willSleep` → `didWake` → 重配置回调。
    func testOnlyAfterBothClearDoesItSeekToAnchor() {
        let target = FakeTarget()
        target.position = 42.0
        let spy = ArbiterSpy(target: target)

        let center = NotificationCenter()
        let hook = RecordingReconfigurationHook()
        var displayAsleep = true                       // 合成夹具，不依赖本机显示器状态
        let watcher = DisplayWatcher(
            notificationCenter: center,
            displayAsleepReader: { displayAsleep },
            reconfigurationHook: hook
        )

        // ① 启动即重算：不投递任何通知就应当看到「熄屏中」
        watcher.start { spy.apply($0) }
        XCTAssertEqual(spy.arbiter.decision.holds, [.displayAsleep], "start() 必须同步算一次当前状态")
        XCTAssertTrue(target.seeks.isEmpty, "启动时就在 hold 中，只记锚点不 seek")

        // ② willSleep：置位系统睡眠
        center.post(name: DisplayWatcher.sleepNotificationName, object: nil)
        spin(seconds: 0.3)
        XCTAssertEqual(spy.arbiter.decision.holds, [.displayAsleep, .systemSleeping])

        // ③ didWake：只解除睡眠 —— 与用例 2 同一断言，区别是这次由真实通知驱动
        center.post(name: DisplayWatcher.wakeNotificationName, object: nil)
        spin(seconds: 0.3)
        XCTAssertEqual(spy.arbiter.decision.holds, [.displayAsleep], "唤醒后仍熄屏 → 只解 systemSleeping")
        XCTAssertTrue(target.seeks.isEmpty, "熄屏仍在 → 一个 seek 都不许有")

        // ④ 屏幕点亮：重配置回调触发**同一条**重算路径
        displayAsleep = false
        hook.fire()
        XCTAssertEqual(spy.arbiter.decision.holds, [], "两个都清空才恢复")
        XCTAssertTrue(spy.arbiter.decision.shouldPlay)
        XCTAssertEqual(target.seeks, [42.0], "两个都清空才 seek，且 seek 到进 hold 时的位置")
        XCTAssertEqual(target.seeks.count, 1, "只 seek 一次 —— 重复 seek 会把续播点推走")

        watcher.stop()
    }

    // ── 4. 清空时是两次 `set`，不是一次批量清空 ─────────────────────────

    /// 两个 reason 的**解除路径各自可测**（每个信号源独立可测：任一源坏掉不污染其他）。
    ///
    /// 若装配层改成「一次性清空两个 reason」，本条转红 —— 那样两个 reason 的解除
    /// 就绑成了一根绳，其中一个信号源坏掉时另一个也查不出来。
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

    // ── 5. `start()` 的同步重算（装配层的启动契约）──────────────────────

    /// `start()` 必须在**不投递任何通知**的情况下当场把当前信号喂给回调。
    ///
    /// 这不是礼貌，是装配层正确性的前提：`willSleep` / `didWake` 与重配置回调**都只在跃迁时**
    /// 投递，本会话既不熄屏也不睡眠，等不到跃迁。少了那次同步重算，装配层读到的
    /// `DisplaySignals` 是默认的 `(false, false)`。
    ///
    /// 夹具把 `displayAsleepReader` 注入成恒 `true`，所以本用例**自足**：
    /// 换一台屏幕亮着的机器也照样过（`evidence/display-sleep-signals.log` 记本机真实读数）。
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

        // 未投递任何通知：回调必须**当场**发生一次。
        XCTAssertEqual(deliveries.count, 1, "start() 返回前必须同步重算一次")
        XCTAssertEqual(deliveries.first, watcher.currentSignals(), "同步投递的必须是此刻的真实状态")
        XCTAssertEqual(deliveries.first?.displayAsleep, true, "夹具前提：注入的读数恒为熄屏")
        XCTAssertEqual(deliveries.first?.systemSleeping, false, "启动时没有睡眠通知 → 睡眠位为 false")
        XCTAssertTrue(watcher.isRunning)
        XCTAssertTrue(watcher.isReconfigurationRegistered, "重配置回调注册失败就没有唤醒后的重算入口")
        XCTAssertEqual(hook.registerCount, 1)

        // 通知名就是系统那两个 —— 单测锁住「用的是真名」，合成事件才不会误投系统名。
        XCTAssertEqual(DisplayWatcher.sleepNotificationName.rawValue, "NSWorkspaceWillSleepNotification")
        XCTAssertEqual(DisplayWatcher.wakeNotificationName.rawValue, "NSWorkspaceDidWakeNotification")

        // 重复 `start()` 幂等：不会注册出第二对观察者（内存单调上涨的防线）。
        watcher.start { _ in XCTFail("重复 start() 不得接管回调") }
        XCTAssertEqual(deliveries.count, 1, "重复 start() 不再同步重算")
        XCTAssertEqual(hook.registerCount, 1, "重复 start() 不得重复注册重配置回调")

        // `stop()` 必须把重配置回调摘掉 —— 摘不掉就是进程内永久泄漏。
        watcher.stop()
        XCTAssertFalse(watcher.isRunning)
        XCTAssertEqual(hook.unregisterCount, 1, "stop() 必须摘掉重配置回调")
        XCTAssertFalse(watcher.isReconfigurationRegistered)

        // stop 之后通知不再触发回调（Pitfall 4 的配对语义）。
        center.post(name: DisplayWatcher.sleepNotificationName, object: nil)
        spin(seconds: 0.3)
        XCTAssertEqual(deliveries.count, 1, "stop() 之后不得再收到通知")
    }
}
