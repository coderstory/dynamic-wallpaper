// PowerWatcherTests.swift —— PAUSE-05「电池供电时暂停（开关，默认关闭）」。
//
// 拔电源是**硬件动作**，本会话做不到。本组用例守住的是三件不依赖那次动作的事：
//
//   ① 判定是**纯函数**：`isOnBattery && pauseOnBatteryEnabled`，四种组合各一行。
//      拔电源做不到，但这两个 `Bool` 谁都能注入 —— 判定逻辑因此 100% 可测。
//   ② PAUSE-05 的两半**连起来**成立：默认关（设置层）⇒ 即使在电池上也不暂停（判定层）。
//      缺任何一半，这条需求都不成立。
//   ③ `.battery` 与其它 reason 在**真实 HoldArbiter** 上独立共存 —— 解除它不影响别的 hold。
//
// ①② 是本次注入式反向验证的目标：把 `shouldHold` 改成忽略开关之后，
// `testPolicyHoldsOnlyWhenEnabledAndOnBattery` 与 `testDefaultSettingMeansBatteryNeverHolds`
// 必须转红 ——「一条从没红过的判据不证明它会红」。
//
// ⚠️ 本文件**不引入播放框架**（`System/` 与 `State/` 零 AVFoundation）。
//    `FakeTarget` 是本文件**本地**的等价实现，不跨文件引用别处那一个。

import XCTest
@testable import PicCore

@MainActor
final class PowerWatcherTests: XCTestCase {

    /// 本地记录式播放端。
    private final class FakeTarget: PlaybackTarget {
        var position: TimeInterval = 0
        var seeks: [TimeInterval] = []
        var applies: [PlaybackDecision] = []

        func arbiterCurrentPosition() -> TimeInterval { position }
        func arbiterSeek(to seconds: TimeInterval) { seeks.append(seconds) }
        func arbiterApply(_ decision: PlaybackDecision) { applies.append(decision) }
    }

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "pic.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    // ── 1. 判定是纯函数：四种组合各一行 ─────────────────────────────────

    /// **第二行是核心**：`true, false → false` —— 在电池上、开关关，一律不暂停。
    ///
    /// 这条如果反了（写成 `isOnBattery || ...` 或直接返回 `isOnBattery`），
    /// 用户拿电池本时壁纸就会无故停住，看起来像 app 坏了。
    func testPolicyHoldsOnlyWhenEnabledAndOnBattery() {
        XCTAssertFalse(BatteryHoldPolicy.shouldHold(isOnBattery: false, pauseOnBatteryEnabled: false),
                       "不在电池 + 开关关 → 不 hold")
        XCTAssertFalse(BatteryHoldPolicy.shouldHold(isOnBattery: true, pauseOnBatteryEnabled: false),
                       "在电池上但开关关 → 不 hold（D-11：默认关闭）")
        XCTAssertFalse(BatteryHoldPolicy.shouldHold(isOnBattery: false, pauseOnBatteryEnabled: true),
                       "不在电池但开关开 → 没有理由 hold")
        XCTAssertTrue(BatteryHoldPolicy.shouldHold(isOnBattery: true, pauseOnBatteryEnabled: true),
                      "在电池上 + 开关开 → 这才 hold")
    }

    /// **PAUSE-05 两半的联合判据**：默认关（设置层）⇒ 在电池上也不暂停（判定层）。
    ///
    /// 上面那条测的是「判定函数本身」，这条测的是「判定函数的输入**真的**是那个开关」。
    /// 少了它，一个把 `pauseOnBatteryEnabled: false` 硬写死的实现也能让上面那条全绿，
    /// 而真机上开关根本不起作用 —— 这是「两半需求」里最容易只交付一半的地方。
    func testDefaultSettingMeansBatteryNeverHolds() {
        let store = SettingsStore(defaults: defaults, seed: SettingsStore.Seed())
        XCTAssertFalse(store.pauseOnBattery, "前提：默认解析出来就是关的")

        XCTAssertFalse(
            BatteryHoldPolicy.shouldHold(isOnBattery: true,
                                         pauseOnBatteryEnabled: store.pauseOnBattery),
            "默认设置下即便真在电池上也不得 hold"
        )

        // 反向：开关一旦打开，同一个判定就必须 hold —— 说明上面那条不是恒假。
        XCTAssertTrue(
            BatteryHoldPolicy.shouldHold(isOnBattery: true, pauseOnBatteryEnabled: true),
            "夹具前提：开关打开时判定必须为真，否则上一条是空判"
        )
    }

    // ── 2. `.battery` 与其它 reason 独立共存 ─────────────────────────────

    /// 与锁屏 / 熄屏同构：换一条 reason 再锁一次，veto 集合语义不变。
    ///
    /// 覆盖式实现（进入 hold 时顺手把集合覆盖成 `[.battery]`）会让这里转红 ——
    /// 那样「锁屏中拔电源」就会把锁屏那条抹掉，壁纸在锁屏状态下开始播。
    func testBatteryReasonEntersAndLeavesVetoSetIndependently() {
        let target = FakeTarget()
        target.position = 42.0
        let arbiter = HoldArbiter(target: target)

        arbiter.set(.battery, active: true)
        XCTAssertEqual(arbiter.decision.holds, [.battery])
        XCTAssertFalse(arbiter.decision.shouldPlay)
        XCTAssertTrue(target.seeks.isEmpty, "进入 hold 只记锚点，不 seek")

        arbiter.set(.screenLocked, active: true)
        XCTAssertEqual(arbiter.decision.holds, [.battery, .screenLocked],
                       "叠加后两条都必须在集合里 —— 覆盖式实现会让这条转红")

        arbiter.set(.battery, active: false)
        XCTAssertEqual(arbiter.decision.holds, [.screenLocked],
                       "只解除 battery，锁屏那条不许跟着消失")
        XCTAssertFalse(arbiter.decision.shouldPlay, "还剩一条 hold → 一律不播")
        XCTAssertTrue(target.seeks.isEmpty, "holds 未清空不得 seek —— 否则续播被提前触发")

        arbiter.set(.screenLocked, active: false)
        XCTAssertEqual(arbiter.decision.holds, [])
        XCTAssertTrue(arbiter.decision.shouldPlay)
        XCTAssertEqual(target.seeks, [42.0], "两条都清空才从原处续播（D-15）")
    }

    // ── 3. 读数链与启动即读（可测的部分） ───────────────────────────────

    /// 读电源状态走的是**三态**而不是 `Bool`：读不到有它自己的名字。
    ///
    /// 这条断言的是**键名**与**值的形状** —— 计划原本写「键 `"AC Power"` 取 `CFBoolean`」，
    /// 本机 SDK 实测不成立（`IOPSKeys.h:311` 键名是 `"Power Source State"`，
    /// `:303` 类型是 CFString）。本用例锁的是**真实**的键名与三态映射，不锁错的那个字面量。
    func testPowerSourceStateKeyIsTheRealSDKKeyAndValuesAreStrings() {
        XCTAssertEqual(PowerWatcher.powerSourceStateKey, "Power Source State",
                       "kIOPSPowerSourceStateKey 的实测键名，不是 AC Power")

        // 本机此刻在 AC 上（有内置电池但接着电源），
        // 所以这里断言的是**三态映射**，不硬编「当前一定是哪个态」。
        switch PowerWatcher.readPowerState() {
        case .onAC:
            let value = PowerWatcher.currentPowerSourceStateValue()
            XCTAssertEqual(value, "AC Power", "onAC 对应的取值必须是 kIOPSACPowerValue")
        case .onBattery:
            let value = PowerWatcher.currentPowerSourceStateValue()
            XCTAssertEqual(value, "Battery Power", "onBattery 对应的取值必须是 kIOPSBatteryPowerValue")
        case .failed:
            XCTFail("读电源状态失败 —— 真值必须如实上报（T-03-16），不许折成在 AC 上或电池上")
        }
    }

    /// `start()` 在**不投递任何事件**的情况下就必须把当前状态交出去。
    ///
    /// 与 `LockWatcher` / `DisplayWatcher` 同形的启动契约。电源状态**当下可读**
    /// （不像锁屏 / 熄屏要等跃迁），所以缺了这一次同步读，在电池上启动的机器
    /// 会一直不产生 hold，直到下一次拔/插电源。
    ///
    /// 本用例跑**真实的** `PowerWatcher`（真调 IOKit、真挂 run loop source），
    /// 不断言回调里那个 `Bool` 是 true 还是 false —— 那取决于本机此刻插没插电源。
    /// 断言的是「回调**发生了一次**」这件事本身。
    func testStartDeliversCurrentPowerStateSynchronously() {
        let watcher = PowerWatcher()
        var deliveries: [Bool] = []

        watcher.start { deliveries.append($0) }
        XCTAssertEqual(deliveries.count, 1, "start() 返回前必须同步读一次当前电源状态")
        XCTAssertTrue(watcher.isRunning)
        XCTAssertTrue(watcher.isSourceRegistered,
                      "事件源没挂上就等于拔电源不会有任何反应（D-01 没兑现）")
        XCTAssertEqual(PowerWatcher.currentIsOnBattery(), deliveries[0],
                       "同步投递的值必须与此刻真读出来的一致（同一时刻不该是两种答案）")

        // 幂等：重复 start() 不接管回调。
        watcher.start { _ in XCTFail("重复 start() 不得接管回调") }
        XCTAssertEqual(deliveries.count, 1, "重复 start() 不再同步读")

        watcher.stop()
        XCTAssertFalse(watcher.isRunning)
        XCTAssertFalse(watcher.isSourceRegistered, "stop() 必须摘掉事件源（T-03-15）")
    }

    /// 4 秒观察窗内电源回调触发次数 —— 本会话在 AC 上不动电源，这个数必然是 0。
    ///
    /// 这条用例不断言它是 0（本机接线若有变动就会变），只断言：
    /// 跑满观察窗、回调计数可读、`stop()` 之后计数不再增长。
    /// 「拔电源跃迁不可观测」这件事在 evidence 里如实记 `unobservable`，不在这儿假装测过。
    func testPowerCallbackCountIsObservableAndStopsAfterStop() {
        let watcher = PowerWatcher()
        var deliveries: [Bool] = []
        watcher.start { deliveries.append($0) }
        XCTAssertEqual(deliveries.count, 1)

        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        let beforeStop = deliveries.count
        watcher.stop()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        XCTAssertEqual(deliveries.count, beforeStop,
                       "stop() 之后不得再收到电源回调（注册与释放严格配对）")
    }
}