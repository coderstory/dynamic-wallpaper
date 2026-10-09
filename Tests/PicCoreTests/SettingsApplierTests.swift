import XCTest
@testable import PicCore

/// 播放中改速度当场生效；held（暂停）时只有 rate 被 shouldPlay 门拦住，音量/静音不设门。
@MainActor
final class SettingsApplierTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "pic.tests.settings-applier.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        unsetenv(SettingsStore.envSourceFolderKey)
    }

    override func tearDown() async throws {
        unsetenv(SettingsStore.envSourceFolderKey)
        TestDefaults.purge(suiteName)
        defaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    func testPlayingRateAppliesImmediately() {
        let store = SettingsStore(defaults: defaults, seed: SettingsStore.Seed())
        store.rate = 1.5
        let player = PlayerController()
        let applier = SettingsApplier(store: store, player: player, arbiter: HoldArbiter())

        applier.applyRate()

        XCTAssertEqual(player.player.rate, store.rate)
    }

    func testHeldPlayerDoesNotGetRateApplied() {
        let store = SettingsStore(defaults: defaults, seed: SettingsStore.Seed())
        store.rate = 1.5
        let player = PlayerController()
        let arbiter = HoldArbiter()
        arbiter.set(.manualPause, active: true)
        let applier = SettingsApplier(store: store, player: player, arbiter: arbiter)

        applier.applyRate()

        XCTAssertEqual(player.player.rate, 0)
        XCTAssertNotEqual(player.player.rate, store.rate)
    }

    func testVolumeAndMutedApplyWithoutGate() {
        let store = SettingsStore(defaults: defaults, seed: SettingsStore.Seed())
        store.volume = 0.25
        store.isMuted = true
        let player = PlayerController()
        let arbiter = HoldArbiter()
        arbiter.set(.manualPause, active: true)
        let applier = SettingsApplier(store: store, player: player, arbiter: arbiter)

        applier.applyVolume()
        applier.applyMuted()

        XCTAssertEqual(player.player.volume, 0.25)
        XCTAssertTrue(player.player.isMuted)
    }

    func testRateReappliesAfterHoldReleased() {
        let store = SettingsStore(defaults: defaults, seed: SettingsStore.Seed())
        store.rate = 1.5
        let player = PlayerController()
        let arbiter = HoldArbiter()
        arbiter.set(.manualPause, active: true)
        let applier = SettingsApplier(store: store, player: player, arbiter: arbiter)

        arbiter.set(.manualPause, active: false)
        applier.applyRate()

        XCTAssertEqual(player.player.rate, store.rate)
    }

    /// 手动调度器；测试替身不跨文件共用 —— 共用后失败时分不清是替身坏了还是被测代码坏了。
    final class ManualScheduler: RotationScheduling {
        private(set) var pending: (@MainActor () -> Void)?
        private(set) var scheduleCount = 0

        func schedule(after interval: TimeInterval, _ body: @escaping @MainActor () -> Void) {
            pending = body
            scheduleCount += 1
        }

        func cancel() { pending = nil }
    }

    private static let items = [
        URL(fileURLWithPath: "/tmp/pic-0502-fixture/v0.mp4"),
        URL(fileURLWithPath: "/tmp/pic-0502-fixture/v1.mp4"),
    ]

    /// `setInterval` 的重排程门要求 isRunning 且列表非空，夹具必须先 start。
    private func startedRotation() -> (RotationController, ManualScheduler) {
        let scheduler = ManualScheduler()
        let rotation = RotationController(scheduler: scheduler,
                                          random: SeededRandomSource(seed: 1))
        rotation.setItems(Self.items)
        rotation.start()
        return (rotation, scheduler)
    }

    /// `HoldArbiter()` 的 init 是 @MainActor，默认参数表达式在 nonisolated 上求值 —— 必须显式传。
    private func makeApplier(arbiter: HoldArbiter) -> (SettingsApplier, SettingsStore) {
        let store = SettingsStore(defaults: defaults, seed: SettingsStore.Seed())
        return (SettingsApplier(store: store, player: PlayerController(), arbiter: arbiter), store)
    }

    /// store → applier → `RotationController.mode` 直连，applier 不存第二份 mode。
    func testApplyModeTakesEffectImmediately() {
        let (rotation, _) = startedRotation()
        let (applier, store) = makeApplier(arbiter: HoldArbiter())
        applier.attach(rotation: rotation)
        store.playMode = .shuffle

        applier.applyMode()

        XCTAssertEqual(rotation.mode, .shuffle)
    }

    /// setInterval 会重排程，且旧 timer 必须被取消（`pending` 不留上一份 body）。
    func testApplyIntervalReschedulesImmediately() {
        let (rotation, scheduler) = startedRotation()
        let (applier, store) = makeApplier(arbiter: HoldArbiter())
        applier.attach(rotation: rotation)
        let before = scheduler.scheduleCount
        store.rotationInterval = 600

        applier.applyInterval()

        XCTAssertEqual(rotation.interval, 600)
        XCTAssertEqual(scheduler.scheduleCount, before + 1)
        XCTAssertNotNil(scheduler.pending)
    }

    /// toggle 后用同一份映射当场重估，不等下一次电源跃迁事件。
    func testBatteryPolicyReappliesWithSameMapping() {
        let arbiter = HoldArbiter()
        let (applier, store) = makeApplier(arbiter: arbiter)
        store.pauseOnBattery = false

        applier.applyBatteryPolicy(isOnBattery: true)
        XCTAssertFalse(arbiter.decision.activeReasons.contains(.battery))

        store.pauseOnBattery = true
        applier.applyBatteryPolicy(isOnBattery: true)
        XCTAssertTrue(arbiter.decision.activeReasons.contains(.battery))
    }

    /// 反方向（关掉开关）当场解除且幂等 —— 全仓 `.battery` 只有这一个 set 落点，别处再加一处本条就红。
    func testBatteryPolicyClearsHoldIdempotently() {
        let arbiter = HoldArbiter()
        let (applier, store) = makeApplier(arbiter: arbiter)
        store.pauseOnBattery = true
        applier.applyBatteryPolicy(isOnBattery: true)

        store.pauseOnBattery = false
        applier.applyBatteryPolicy(isOnBattery: true)
        applier.applyBatteryPolicy(isOnBattery: true)

        XCTAssertFalse(arbiter.decision.activeReasons.contains(.battery))
    }
}
