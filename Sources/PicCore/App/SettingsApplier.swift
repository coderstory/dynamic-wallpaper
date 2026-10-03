import Foundation
import Observation

/// 「当场生效」的唯一落点（Plan 05-01 T1）。
///
/// UI 只写 store 再调这里 —— 本类是 store 值与播放内核之间唯一的中转。
/// @Observable 是 SwiftUI `@Environment(SettingsApplier.self)` 注入的前提，
/// 无其它可变状态。
///
/// ⚠️ 不 import AVFoundation：它只调 `PlayerController` 公开面
/// （D-13：UI/applier 都不直接摸 `AVPlayer`）。
@MainActor
@Observable
public final class SettingsApplier {
    private let store: SettingsStore
    private let player: PlayerController
    private let arbiter: HoldArbiter

    /// 轮换。**可选持有**：装配点在 AppDelegate
    /// `wiring()` 里 attach，单测不必构造整个调度器栈就能测另外四个 apply。
    public private(set) var rotation: RotationController?

    public init(store: SettingsStore, player: PlayerController, arbiter: HoldArbiter) {
        self.store = store
        self.player = player
        self.arbiter = arbiter
    }

    public func attach(rotation: RotationController) {
        self.rotation = rotation
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

    // MARK: - Plan 05-02 T1：模式 / 轮换 / 电池三条接线

    /// 模式当场生效：`RotationController.mode` 可直写即生效（04-02 不存第二份）。
    public func applyMode() {
        rotation?.mode = store.playMode
        WallpaperWindowController.emit(
            "PIC_SETTINGS_APPLY key=playMode value=\(store.playMode.rawValue) applied=\(rotation == nil ? 0 : 1)")
    }

    /// 间隔当场重排程（04-02 的 `setInterval` 就是 Phase 5 预留的落点）。
    public func applyInterval() {
        rotation?.setInterval(store.rotationInterval)
        WallpaperWindowController.emit(
            "PIC_SETTINGS_APPLY key=rotationInterval value=\(Int(store.rotationInterval)) applied=\(rotation == nil ? 0 : 1)")
    }

    /// 「电池时播放」开关的当场重估入口。电源跃迁与设置窗 toggle **走同一个方法**，
    /// 因此这是全仓唯一一处 `.battery` 的 set 落点（从 AppDelegate 的闭包搬来）。
    /// 搬家不复制：两处 set 会在电源事件与用户 toggle 之间产生竞态双写（T-05-06）。
    public func applyBatteryPolicy(isOnBattery: Bool) {
        arbiter.set(.battery, active: BatteryHoldPolicy.shouldHold(
            isOnBattery: isOnBattery,
            pauseOnBatteryEnabled: store.pauseOnBattery))
        WallpaperWindowController.emit(
            "PIC_SETTINGS_APPLY key=pauseOnBattery value=\(store.pauseOnBattery ? 1 : 0) applied=1 onBattery=\(isOnBattery ? 1 : 0)")
    }
}
