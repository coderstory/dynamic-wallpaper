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
}
