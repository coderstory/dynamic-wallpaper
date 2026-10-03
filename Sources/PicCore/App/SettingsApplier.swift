import Foundation

/// 「当场生效」的唯一落点（Plan 05-01 T1）。TDD RED 桩 —— 实现在 GREEN 提交落位。
@MainActor
public final class SettingsApplier {
    private let store: SettingsStore
    private let player: PlayerController
    private let arbiter: HoldArbiter

    public init(store: SettingsStore, player: PlayerController, arbiter: HoldArbiter) {
        self.store = store
        self.player = player
        self.arbiter = arbiter
    }

    public func applyRate() {}

    public func applyVolume() {}

    public func applyMuted() {}

    public func applyAudioTrio() {}
}
