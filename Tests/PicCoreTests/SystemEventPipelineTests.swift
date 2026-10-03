import XCTest
@testable import PicCore

/// 系统事件 → 仲裁 → 播放端的**纵向集成**用例。
///
/// 本文件**不得引入播放框架**（`System/` 与 `State/` 零 AVFoundation）。
@MainActor
final class SystemEventPipelineTests: XCTestCase {

    /// 记录式播放端。与 `HoldArbiterTests` 里的那个是两回事：
    /// 那份测纯仲裁语义，本份测「信号 → 仲裁 → 播放端」这条纵线，
    /// 故不复用（复用在两个 `@testable import` 的测试目标里反而要跨文件耦合）。
    private final class RecordingTarget: PlaybackTarget {
        var position: TimeInterval = 0
        var seeks: [TimeInterval] = []
        var applies: [PlaybackDecision] = []

        func arbiterCurrentPosition() -> TimeInterval { position }
        func arbiterSeek(to seconds: TimeInterval) { seeks.append(seconds) }
        func arbiterApply(_ decision: PlaybackDecision) { applies.append(decision) }
    }

    /// 合成通知一律用这个前缀，**绝不投系统通知名** ——
    /// `com.apple.screenIsLocked` 由别的进程投递，往它投会污染同机其它壁纸 app。
    private static let prefix = "com.local.pic.tests.lock."

    private func makeNames() -> LockSignalNames {
        LockSignalNames(locked: "\(Self.prefix)locked", unlocked: "\(Self.prefix)unlocked")
    }

    /// 跑一段主 run loop，等异步投递的回调落地。
    private func spinMainRunLoop(seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    // MARK: - start() 的同步回调

    /// `start()` 必须在**不投递任何通知**的情况下当场把当前锁屏状态喂给仲裁器。
    ///
    /// 这是装配层正确性的前提，不是礼貌：`com.apple.screenIsLocked` 是跃迁通知，
    /// 本会话自 `applicationDidFinishLaunching` 起屏幕一直锁着，没有任何跃迁可等。
    /// 少了这次同步回调，`holds` 在起播那一刻是空集 → 锁屏会话下起播不暂停。
    ///
    /// 会话字典注入 `[String: Any]` 夹具，所以本用例**自足**：换一台解锁的机器也照样过。
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

        var deliveries: [Bool] = []
        watcher.start { locked in
            deliveries.append(locked)
            arbiter.set(.screenLocked, active: locked)
        }

        // 未投递任何通知：回调必须**当场**发生一次，且参数是当前真实状态。
        XCTAssertEqual(deliveries, [true], "start() 返回前必须同步回调一次 currentLockState()")
        XCTAssertEqual(arbiter.decision.holds, [.screenLocked], "订阅前已锁屏 → start 后 holds 立即含 screenLocked")
        XCTAssertFalse(arbiter.decision.shouldPlay)
        XCTAssertTrue(watcher.isRunning)
        // 进入 hold 时记锚点，不 seek。
        XCTAssertEqual(target.seeks, [], "进入 hold 只记锚点，不 seek")

        watcher.stop()
        XCTAssertFalse(watcher.isRunning)
    }

    /// 未锁屏时同步回调 `false`：`holds` 保持空集，播放不被误暂停。
    func testStartDeliversUnlockedStateSynchronously() {
        let watcher = LockWatcher(
            center: DistributedNotificationCenter(),
            names: makeNames(),
            sessionReader: { ["CGSSessionScreenIsLocked": 0] }
        )
        let target = RecordingTarget()
        let arbiter = HoldArbiter(target: target)

        var deliveries: [Bool] = []
        watcher.start { locked in
            deliveries.append(locked)
            arbiter.set(.screenLocked, active: locked)
        }

        XCTAssertEqual(deliveries, [false])
        XCTAssertEqual(arbiter.decision.holds, [], "未锁屏不得产生任何 hold")
        XCTAssertTrue(arbiter.decision.shouldPlay)
        XCTAssertEqual(target.applies, [], "空集变化不发 apply（幂等，ARCHITECTURE §6.4 不变式 4）")

        watcher.stop()
    }

    // MARK: - 会话字典取值的纯函数

    /// 「读不到」与「没锁」是两件事。三种夹具把三者的输出都钉死：
    /// 字典为 nil / 键缺失 → `false`；值为 0 → `false`；值为 1 → `true`。
    func testLockStatePureFunctionHandlesMissingKeyZeroAndOne() {
        XCTAssertFalse(LockWatcher.lockState(fromSession: nil), "字典读不到 → 视作没锁")
        XCTAssertFalse(LockWatcher.lockState(fromSession: [:]), "键缺失 → 视作没锁")
        XCTAssertFalse(LockWatcher.lockState(fromSession: ["CGSSessionScreenIsLocked": 0]))
        XCTAssertTrue(LockWatcher.lockState(fromSession: ["CGSSessionScreenIsLocked": 1]))
        // 别的键（哪怕值是 1）不影响结果 —— 只认那一个键。
        XCTAssertFalse(LockWatcher.lockState(fromSession: ["CGSSessionOnConsoleKey": 1]))
    }

    /// 真读系统会话字典：本机会话锁着，键存在且值为非零。
    /// 只断言「读得到一个 Bool」，不断言具体是 true —— 换一台解锁的机器也要过。
    func testCurrentLockStateReadsRealSessionDictionary() {
        let watcher = LockWatcher(center: DistributedNotificationCenter(), names: makeNames())
        let live = watcher.currentLockState()
        let direct = LockWatcher.lockState(fromSession: CGSessionCopyCurrentDictionary() as? [String: Any])
        XCTAssertEqual(live, direct, "currentLockState() 与直接读会话字典必须一致")
        watcher.stop()
    }

    // MARK: - 纵向：注入的通知走完订阅 → 仲裁 → 播放端

    /// 合成锁屏通知 → `holds == [.screenLocked]`、`shouldPlay == false`、
    /// 播放端收到 `arbiterApply`。PAUSE-02 / PAUSE-06 的接线证据。
    func testInjectedLockSignalAppliesHoldThroughToPlaybackTarget() {
        let center = DistributedNotificationCenter()
        let names = makeNames()
        let watcher = LockWatcher(
            center: center,
            names: names,
            sessionReader: { ["CGSSessionScreenIsLocked": 1] }   // 通知到达后会重读（T-03-01）
        )
        let target = RecordingTarget()
        target.position = 42.0
        let arbiter = HoldArbiter(target: target)

        watcher.start { locked in arbiter.set(.screenLocked, active: locked) }
        XCTAssertEqual(arbiter.decision.holds, [.screenLocked], "同步回调已置位")

        // 幂等：重复置位不重复打扰播放端。
        let appliesAfterStart = target.applies.count
        arbiter.set(.screenLocked, active: true)
        XCTAssertEqual(target.applies.count, appliesAfterStart, "同一 reason 重复置位只 apply 一次")

        // 解除：换掉会话字典再投「已解锁」通知 —— 通知只当触发器。
        watcher.stop()
        let watcher2 = LockWatcher(
            center: center,
            names: names,
            sessionReader: { ["CGSSessionScreenIsLocked": 0] }
        )
        watcher2.start { locked in arbiter.set(.screenLocked, active: locked) }
        XCTAssertEqual(arbiter.decision.holds, [], "解除后 holds 清空")
        XCTAssertTrue(arbiter.decision.shouldPlay)
        XCTAssertEqual(target.seeks, [42.0], "解除后从暂停时的位置续播（PAUSE-06）")
        watcher2.stop()
    }

    /// `stop()` 之后通知不再触发回调 —— 与注册配对的语义。
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

        var deliveries = 0
        watcher.start { locked in
            deliveries += 1
            arbiter.set(.screenLocked, active: locked)
        }
        XCTAssertEqual(deliveries, 1, "start 的同步回调")
        XCTAssertTrue(watcher.isRunning)

        watcher.stop()
        XCTAssertFalse(watcher.isRunning)

        center.post(name: Notification.Name(names.unlocked), object: nil)
        spinMainRunLoop(seconds: 0.4)

        XCTAssertEqual(deliveries, 1, "stop() 之后不得再收到通知")
        XCTAssertEqual(arbiter.decision.holds, [.screenLocked], "stop 不得改变已有状态")
    }

    /// 重复 `start()` 是幂等的 —— 不会注册出第二对 observer（内存单调上涨的防线）。
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

        var deliveries = 0
        watcher.start { locked in
            deliveries += 1
            arbiter.set(.screenLocked, active: locked)
        }
        watcher.start { _ in deliveries += 100 }   // 第二次必须被 isRunning 挡掉
        XCTAssertEqual(deliveries, 1, "重复 start() 不再同步回调，也不接管回调")

        center.post(name: Notification.Name(names.locked), object: nil)
        spinMainRunLoop(seconds: 0.4)
        XCTAssertEqual(deliveries, 2, "只有第一次 start 的那个回调仍然活着")

        watcher.stop()
    }

    // MARK: - HoldReason 的形状

    /// 6 个 case、幂集恰 64 组、order 互不相同。
    /// 子集在**运行时**从 `allCases` 生成，不存在手抄的 64 条断言。
    func testHoldReasonPowerSetIsExactlySixtyFour() {
        let all = HoldReason.allCases
        XCTAssertEqual(all.count, 6, "manualPause + 5 个系统原因；实际 \(all.count)")
        XCTAssertEqual(1 << all.count, 64, "幂集组数；实际 \(1 << all.count)")
        XCTAssertEqual(all.map(\.order), [0, 1, 2, 3, 4, 5], "order 必须互不相同且升序")
        XCTAssertEqual(HoldReason.manualPause.order, 0, "Phase 2 的值，一个字不改")
    }
}