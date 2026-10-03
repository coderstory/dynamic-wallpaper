import Foundation
import Observation

/// 「当场生效」的唯一落点（Plan 05-01 T1）。
///
/// UI 只写 store 再调这里 —— 本类是 store 值与播放内核之间唯一的中转
/// （05-02 起换片等场合复用 `applyAudioTrio()`）。@Observable 是 SwiftUI
/// `@Environment(SettingsApplier.self)` 注入的前提，无其它可变状态。
///
/// ⚠️ 不 import AVFoundation：它只调 `PlayerController` 公开面
/// （D-13：UI/applier 都不直接摸 `AVPlayer`）。
@MainActor
@Observable
public final class SettingsApplier {
    private let store: SettingsStore
    private let player: PlayerController
    private let arbiter: HoldArbiter

    public init(store: SettingsStore, player: PlayerController, arbiter: HoldArbiter) {
        self.store = store
        self.player = player
        self.arbiter = arbiter
    }

    /// 速度。第一行的门是变异验证的靶点（`MUT-P5-RATE-GATE`）：
    /// `PlayerController.setRate(r)` 的实现就是 `player.rate = r`，无条件调用
    /// 会把已 hold 的播放器重新拉起（`W-2026-10-03-21` 起播门禁的设置路径延伸，
    /// B1 同型风险）。门内当场生效并打证据行；门外只记不拉起。
    public func applyRate() {
        let gated = arbiter.decision.shouldPlay
        if gated {
            player.setRate(store.rate)
            WallpaperWindowController.emit("PIC_SETTINGS_APPLY key=rate value=\(store.rate) applied=1")
        } else {
            let reasons = arbiter.decision.activeReasons
                .map { String(describing: $0) }
                .joined(separator: ",")
            // 空集写 (none) 与 PIC_HOLD 的既有形状一致（空串会让 grep 误伤别的行）。
            WallpaperWindowController.emit("PIC_SETTINGS_APPLY key=rate value=\(store.rate) applied=0 hold=(\(reasons.isEmpty ? "none" : reasons))")
        }
    }

    /// 音量/静音无门直发：`setVolume`/`setMuted` 不会把播放器拉起
    /// （PLAY-08/09 的机制前提，单测 `testVolumeAndMutedApplyWithoutGate`）。
    public func applyVolume() {
        player.setVolume(store.volume)
        WallpaperWindowController.emit("PIC_SETTINGS_APPLY key=volume value=\(store.volume) applied=1")
    }

    public func applyMuted() {
        player.setMuted(store.isMuted)
        WallpaperWindowController.emit("PIC_SETTINGS_APPLY key=muted value=\(store.isMuted ? 1 : 0) applied=1")
    }

    /// 按序调齐三件（05-02 起在换片等场合复用；顺序与起播尾段一致）。
    public func applyAudioTrio() {
        applyRate()
        applyVolume()
        applyMuted()
    }
}
