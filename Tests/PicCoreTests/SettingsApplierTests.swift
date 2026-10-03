import XCTest
@testable import PicCore

/// `SettingsApplier`（「当场生效」唯一落点）单测（Plan 05-01 T1）。
///
/// `testHeldPlayerDoesNotGetRateApplied` 是 shouldPlay 门禁的牙齿 ——
/// 变异验证（MUT-P5-RATE-GATE）打在 `applyRate` 第一行，拿掉门后必须
/// 恰好这一条转红，且红光来自断言而非编译失败（D-16）。
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
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    /// 播放中（holds 空）改速度：`AVPlayer.rate` 当场变（PLAY-07 的机制证明）。
    func testPlayingRateAppliesImmediately() {
        let store = SettingsStore(defaults: defaults, seed: SettingsStore.Seed())
        store.rate = 1.5
        let player = PlayerController()
        let applier = SettingsApplier(store: store, player: player, arbiter: HoldArbiter())

        applier.applyRate()

        XCTAssertEqual(player.player.rate, store.rate)
    }

    /// held（暂停）状态下改速度不会把播放器拉起 —— shouldPlay 门的行为证明。
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

    /// 音量/静音不设门：held 下仍当场落位（PLAY-08/09 的机制前提 ——
    /// `setVolume`/`setMuted` 不会把播放器拉起）。
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

    /// 解除 hold 后再调 applyRate：速度能重新落位（门的另一半语义）。
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

    // MARK: - Plan 05-02 T1：模式 / 轮换 / 电池三条接线

    /// 手动调度器：与 RotationControllerTests 同型（不跨测试文件引用）。
    final class ManualScheduler: RotationScheduling {
        private(set) var pending: (() -> Void)?
        private(set) var scheduleCount = 0

        func schedule(after interval: TimeInterval, _ body: @escaping () -> Void) {
            pending = body
            scheduleCount += 1
        }

        func cancel() { pending = nil }
    }

    private static let items = [
        VideoItem(url: URL(fileURLWithPath: "/tmp/pic-0502-fixture/v0.mp4")),
        VideoItem(url: URL(fileURLWithPath: "/tmp/pic-0502-fixture/v1.mp4")),
    ]

    /// 已 start 的轮换器（`setInterval` 的重排程门要求 isRunning 且非空列表）。
    private func startedRotation() -> (RotationController, ManualScheduler) {
        let scheduler = ManualScheduler()
        let rotation = RotationController(scheduler: scheduler,
                                          random: SeededRandomSource(seed: 1))
        rotation.setItems(Self.items)
        rotation.start()
        return (rotation, scheduler)
    }

    /// 默认参数表达式在 nonisolated 上求值，`HoldArbiter()` 的 init 是 @MainActor —— 显式传。
    private func makeApplier(arbiter: HoldArbiter) -> (SettingsApplier, SettingsStore) {
        let store = SettingsStore(defaults: defaults, seed: SettingsStore.Seed())
        return (SettingsApplier(store: store, player: PlayerController(), arbiter: arbiter), store)
    }

    /// 模式切换当场生效：store → applier → `RotationController.mode`（不存第二份）。
    func testApplyModeTakesEffectImmediately() {
        let (rotation, _) = startedRotation()
        let (applier, store) = makeApplier(arbiter: HoldArbiter())
        applier.attach(rotation: rotation)
        store.playMode = .shuffle

        applier.applyMode()

        XCTAssertEqual(rotation.mode, .shuffle)
    }

    /// 轮换间隔当场重排程（04-02 为 Phase 5 预留的落点）。
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

    /// toggle 后用**同一份** `BatteryHoldPolicy` 映射当场重估，不需要下一次电源跃迁。
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

    /// 反方向（关掉开关）也要当场解除，且重复调幂等 —— 全仓 `.battery` 只有一个
    /// set 落点（AppDelegate 的闭包搬进了这里），漂移会在这一条上现形。
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
