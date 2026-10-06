import XCTest
@testable import PicCore

/// 系统事件 → 仲裁 → 播放端的**纵向集成**用例。`System/` 与 `State/` 零 AVFoundation。
@MainActor
final class SystemEventPipelineTests: XCTestCase {

    /// 记录式播放端。不复用 `HoldArbiterTests` 里那一个（那份测纯仲裁语义，本份测纵线）——
    /// 测试替身跨文件耦合后，失败时分不清是替身坏了还是被测代码坏了。
    private final class RecordingTarget: PlaybackTarget {
        var position: TimeInterval = 0
        var seeks: [TimeInterval] = []
        var applies: [PlaybackDecision] = []

        func arbiterCurrentPosition() -> TimeInterval { position }
        func arbiterSeek(to seconds: TimeInterval) { seeks.append(seconds) }
        func arbiterApply(_ decision: PlaybackDecision) { applies.append(decision) }
    }

    /// 合成通知一律用这个前缀，**绝不投系统通知名** —— `com.apple.screenIsLocked` 由别的进程投递，
    /// 往它投会污染同机其它壁纸 app。
    private static let prefix = "com.local.pic.tests.lock."

    private func makeNames() -> LockSignalNames {
        LockSignalNames(locked: "\(Self.prefix)locked", unlocked: "\(Self.prefix)unlocked")
    }

    /// 跑一段主 run loop，等异步投递的回调落地。
    private func spinMainRunLoop(seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// 锁屏通知是跃迁通知，无跃迁时永远等不到 —— 少了这次同步回调，锁屏会话下起播那一刻 `holds` 是空集。
    /// 会话字典注入 `[String: Any]` 夹具，换一台解锁的机器也照样过。
    func testStartDeliversCurrentStateSynchronouslyEvenWithoutAnyTransition() {
        let center = DistributedNotificationCenter()
        let watcher = LockWatcher(
            center: center,
            names: makeNames(),
            sessionReader: { ["CGSSessionScreenIsLocked": 1] }   // 订阅前已锁屏
        )
        let target = RecordingTarget()
        target.position = 42.0
        let arbiter = HoldArbiter(target: target)

        let deliveries = DeliveryLog()
        watcher.start { locked in
            MainActor.assumeIsolated {
                deliveries.append(locked)
                arbiter.set(.screenLocked, active: locked)
            }
        }

        XCTAssertEqual(deliveries.flags, [true], "start() 返回前必须同步回调一次 currentLockState()")
        XCTAssertEqual(arbiter.decision.holds, [.screenLocked], "订阅前已锁屏 → start 后 holds 立即含 screenLocked")
        XCTAssertFalse(arbiter.decision.shouldPlay)
        XCTAssertTrue(watcher.isRunning)
        XCTAssertEqual(target.seeks, [], "进入 hold 只记锚点，不 seek")

        watcher.stop()
        XCTAssertFalse(watcher.isRunning)
    }

    func testStartDeliversUnlockedStateSynchronously() {
        let watcher = LockWatcher(
            center: DistributedNotificationCenter(),
            names: makeNames(),
            sessionReader: { ["CGSSessionScreenIsLocked": 0] }
        )
        let target = RecordingTarget()
        let arbiter = HoldArbiter(target: target)

        let deliveries = DeliveryLog()
        watcher.start { locked in
            MainActor.assumeIsolated {
                deliveries.append(locked)
                arbiter.set(.screenLocked, active: locked)
            }
        }

        XCTAssertEqual(deliveries.flags, [false])
        XCTAssertEqual(arbiter.decision.holds, [], "未锁屏不得产生任何 hold")
        XCTAssertTrue(arbiter.decision.shouldPlay)
        XCTAssertEqual(target.applies, [], "空集变化不发 apply（幂等，ARCHITECTURE §6.4 不变式 4）")

        watcher.stop()
    }

    /// 「读不到」与「没锁」是两件事，都按没锁处理。
    func testLockStatePureFunctionHandlesMissingKeyZeroAndOne() {
        XCTAssertFalse(LockWatcher.lockState(fromSession: nil), "字典读不到 → 视作没锁")
        XCTAssertFalse(LockWatcher.lockState(fromSession: [:]), "键缺失 → 视作没锁")
        XCTAssertFalse(LockWatcher.lockState(fromSession: ["CGSSessionScreenIsLocked": 0]))
        XCTAssertTrue(LockWatcher.lockState(fromSession: ["CGSSessionScreenIsLocked": 1]))
        // 别的键（哪怕值是 1）不影响结果 —— 只认那一个键。
        XCTAssertFalse(LockWatcher.lockState(fromSession: ["CGSSessionOnConsoleKey": 1]))
    }

    /// 真读系统会话字典：不断言具体是 true —— 换一台解锁的机器也要过。
    func testCurrentLockStateReadsRealSessionDictionary() {
        let watcher = LockWatcher(center: DistributedNotificationCenter(), names: makeNames())
        let live = watcher.currentLockState()
        let direct = LockWatcher.lockState(fromSession: CGSessionCopyCurrentDictionary() as? [String: Any])
        XCTAssertEqual(live, direct, "currentLockState() 与直接读会话字典必须一致")
        watcher.stop()
    }

    func testInjectedLockSignalAppliesHoldThroughToPlaybackTarget() {
        let center = DistributedNotificationCenter()
        let names = makeNames()
        let watcher = LockWatcher(
            center: center,
            names: names,
            sessionReader: { ["CGSSessionScreenIsLocked": 1] }   // 通知到达后会重读
        )
        let target = RecordingTarget()
        target.position = 42.0
        let arbiter = HoldArbiter(target: target)

        watcher.start { locked in MainActor.assumeIsolated { arbiter.set(.screenLocked, active: locked) } }
        XCTAssertEqual(arbiter.decision.holds, [.screenLocked], "同步回调已置位")

        // 幂等：重复置位不重复打扰播放端
        let appliesAfterStart = target.applies.count
        arbiter.set(.screenLocked, active: true)
        XCTAssertEqual(target.applies.count, appliesAfterStart, "同一 reason 重复置位只 apply 一次")

        // 解除：sessionReader 注入后不可换，所以另起一个带「已解锁」字典的 watcher —— 通知只当触发器
        watcher.stop()
        let watcher2 = LockWatcher(
            center: center,
            names: names,
            sessionReader: { ["CGSSessionScreenIsLocked": 0] }
        )
        watcher2.start { locked in MainActor.assumeIsolated { arbiter.set(.screenLocked, active: locked) } }
        XCTAssertEqual(arbiter.decision.holds, [], "解除后 holds 清空")
        XCTAssertTrue(arbiter.decision.shouldPlay)
        XCTAssertEqual(target.seeks, [42.0], "解除后从暂停时的位置续播（PAUSE-06）")
        watcher2.stop()
    }

    func testStopRemovesObserversSoLaterSignalsAreIgnored() {
        let center = DistributedNotificationCenter()
        let names = makeNames()
        let watcher = LockWatcher(
            center: center,
            names: names,
            sessionReader: { ["CGSSessionScreenIsLocked": 1] }
        )
        let target = RecordingTarget()
        let arbiter = HoldArbiter(target: target)

        let deliveries = DeliveryLog()
        watcher.start { locked in
            MainActor.assumeIsolated {
                deliveries.append(locked)
                arbiter.set(.screenLocked, active: locked)
            }
        }
        XCTAssertEqual(deliveries.count, 1, "start 的同步回调")
        XCTAssertTrue(watcher.isRunning)

        watcher.stop()
        XCTAssertFalse(watcher.isRunning)

        center.post(name: Notification.Name(names.unlocked), object: nil)
        spinMainRunLoop(seconds: 0.4)

        XCTAssertEqual(deliveries.count, 1, "stop() 之后不得再收到通知")
        XCTAssertEqual(arbiter.decision.holds, [.screenLocked], "stop 不得改变已有状态")
    }

    /// 重复 `start()` 不会注册出第二对 observer（内存单调上涨的防线）。
    func testRepeatedStartDoesNotRegisterDuplicateObservers() {
        let center = DistributedNotificationCenter()
        let names = makeNames()
        let watcher = LockWatcher(
            center: center,
            names: names,
            sessionReader: { ["CGSSessionScreenIsLocked": 1] }
        )
        let target = RecordingTarget()
        let arbiter = HoldArbiter(target: target)

        let deliveries = DeliveryLog()
        watcher.start { locked in
            MainActor.assumeIsolated {
                deliveries.append(locked)
                arbiter.set(.screenLocked, active: locked)
            }
        }
        // 重复 start 若真接管了回调，计数 +100 让断言炸得一眼可见，别降成 1
        watcher.start { _ in MainActor.assumeIsolated { deliveries.bump(by: 100) } }
        XCTAssertEqual(deliveries.count, 1, "重复 start() 不再同步回调，也不接管回调")

        center.post(name: Notification.Name(names.locked), object: nil)
        spinMainRunLoop(seconds: 0.4)
        XCTAssertEqual(deliveries.count, 2, "只有第一次 start 的那个回调仍然活着")

        watcher.stop()
    }

    /// 幂集组数在运行时由 `allCases` 算出，不存在手抄的 64 条断言。
    func testHoldReasonPowerSetIsExactlySixtyFour() {
        let all = HoldReason.allCases
        XCTAssertEqual(all.count, 6, "manualPause + 5 个系统原因；实际 \(all.count)")
        XCTAssertEqual(1 << all.count, 64, "幂集组数；实际 \(1 << all.count)")
        XCTAssertEqual(all.map(\.order), [0, 1, 2, 3, 4, 5], "order 必须互不相同且升序")
        XCTAssertEqual(HoldReason.manualPause.order, 0, "Phase 2 的值，一个字不改")
    }
}

/// `@Sendable` 回调不能可变捕获局部 var —— 收尾计数走这个主 actor 盒。
@MainActor
private final class DeliveryLog {
    private(set) var flags: [Bool] = []
    private(set) var count = 0

    func append(_ value: Bool) {
        flags.append(value)
        count += 1
    }

    func bump(by delta: Int) {
        count += delta
    }
}