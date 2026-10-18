// 拔电源是硬件动作，本组用例守的是不依赖那次动作的部分：判定是纯函数
// `isOnBattery && pauseOnBatteryEnabled`（两个 `Bool` 谁都能注入，判定逻辑因此全可测）；
// 判定函数的输入必须真的是 `SettingsStore.pauseOnBattery` —— 默认值关（设置层）与判定层
// 少任何一半，用户侧的开关就不起作用。`System/` 与 `State/` 零 AVFoundation。

import XCTest
@testable import PicCore

@MainActor
final class PowerWatcherTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "pic.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        TestDefaults.purge(suiteName)
        defaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    /// 第二行是核心：写成 `isOnBattery || ...` 或直接返回 `isOnBattery`，它会转红。
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

    /// 测的是判定函数的输入**真的是**那个开关：把 `pauseOnBatteryEnabled: false` 硬写死的实现
    /// 也能让上一条全绿，只有本条能抓住。
    func testDefaultSettingMeansBatteryNeverHolds() {
        let store = SettingsStore(defaults: defaults, seed: SettingsStore.Seed())
        XCTAssertFalse(store.pauseOnBattery, "前提：默认解析出来就是关的")

        XCTAssertFalse(
            BatteryHoldPolicy.shouldHold(isOnBattery: true,
                                         pauseOnBatteryEnabled: store.pauseOnBattery),
            "默认设置下即便真在电池上也不得 hold"
        )

        // 反向：开关打开时必须 hold，否则上面那条是空判
        XCTAssertTrue(
            BatteryHoldPolicy.shouldHold(isOnBattery: true, pauseOnBatteryEnabled: true),
            "夹具前提：开关打开时判定必须为真，否则上一条是空判"
        )
    }

    /// 覆盖式实现（进入 hold 时把集合覆盖成 `[.battery]`）会让叠加那条转红 ——
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

    /// 读电源状态是**三态**而不是 `Bool`：值是 String，键名固定，键名取错或值当 Bool 读都会静默退化成「永远在 AC 上」。
    func testPowerSourceStateKeyIsTheRealSDKKeyAndValuesAreStrings() {
        XCTAssertEqual(PowerWatcher.powerSourceStateKey, "Power Source State",
                       "kIOPSPowerSourceStateKey 的实测键名，不是 AC Power")

        // 断言三态映射本身，不硬编本机此刻是哪个态
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

    /// 与 `LockWatcher` / `DisplayWatcher` 同形的启动契约。电源状态**当下可读**（不像锁屏 / 熄屏要等跃迁），
    /// 缺了这次同步读，在电池上启动的机器会一直不产生 hold，直到下一次拔/插电源。
    /// 本用例跑**真实的** `PowerWatcher`（真调 IOKit、真挂 run loop source），不断言回调里那个 `Bool`
    /// 是 true 还是 false（取决于本机此刻插没插电源），只断言回调**发生了一次**。
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

        watcher.start { _ in XCTFail("重复 start() 不得接管回调") }
        XCTAssertEqual(deliveries.count, 1, "重复 start() 不再同步读")

        watcher.stop()
        XCTAssertFalse(watcher.isRunning)
        XCTAssertFalse(watcher.isSourceRegistered, "stop() 必须摘掉事件源（T-03-15）")
    }

    /// 不断言观察窗内回调次数是 0（本机接线一变就变），只断言：计数可读、`stop()` 之后不再增长。
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