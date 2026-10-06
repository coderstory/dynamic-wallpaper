import Foundation
import Observation

/// 「当场生效」的唯一落点。UI 只写 store 再调这里 —— store 值与播放内核之间的唯一中转。
/// 不 import AVFoundation：只调 `PlayerController` 公开面。
@MainActor
@Observable
public final class SettingsApplier {
    private let store: SettingsStore
    private let player: PlayerController
    private let arbiter: HoldArbiter

    /// 轮换。可选持有：装配点在 AppDelegate `wiring()` 里 attach，单测不必构造整个调度器栈。
    public private(set) var rotation: RotationController?

    public init(store: SettingsStore, player: PlayerController, arbiter: HoldArbiter) {
        self.store = store
        self.player = player
        self.arbiter = arbiter
    }

    public func attach(rotation: RotationController) {
        self.rotation = rotation
    }

    /// 速度。门控必须存在：`setRate(r)` 的实现就是 `player.rate = r`，
    /// 无条件调用会把已 hold 的播放器重新拉起。门内当场生效并打证据行；门外只记不拉起。
    ///
    /// **两个分支都必须记住速度** —— 门外只记不应用的话，hold 解除时 `arbiterApply`
    /// 回放的 `desiredRate` 才是这一次的设置值，而不是上一次的或默认的 1.0。
    public func applyRate() {
        let gated = arbiter.decision.shouldPlay
        if gated {
            player.setRate(store.rate)
            WallpaperWindowController.emit("PIC_SETTINGS_APPLY key=rate value=\(store.rate) applied=1")
        } else {
            player.setDesiredRate(store.rate)
            let reasons = arbiter.decision.activeReasons
                .map { String(describing: $0) }
                .joined(separator: ",")
            // 空集写 (none) 与 PIC_HOLD 同形状：空串会让 grep 误伤别的行
            WallpaperWindowController.emit("PIC_SETTINGS_APPLY key=rate value=\(store.rate) applied=0 hold=(\(reasons.isEmpty ? "none" : reasons))")
        }
    }

    /// 音量/静音无门直发：`setVolume`/`setMuted` 不会把播放器拉起。
    public func applyVolume() {
        player.setVolume(store.volume)
        WallpaperWindowController.emit("PIC_SETTINGS_APPLY key=volume value=\(store.volume) applied=1")
    }

    public func applyMuted() {
        player.setMuted(store.isMuted)
        WallpaperWindowController.emit("PIC_SETTINGS_APPLY key=muted value=\(store.isMuted ? 1 : 0) applied=1")
    }

    // MARK: - 模式 / 轮换 / 电池三条接线

    /// 模式当场生效：`RotationController.mode` 可直写即生效（不存第二份）。
    public func applyMode() {
        rotation?.mode = store.playMode
        WallpaperWindowController.emit(
            "PIC_SETTINGS_APPLY key=playMode value=\(store.playMode.rawValue) applied=\(rotation == nil ? 0 : 1)")
    }

    /// 间隔当场重排程（`setInterval` 就是这条预留落点）。
    public func applyInterval() {
        rotation?.setInterval(store.rotationInterval)
        WallpaperWindowController.emit(
            "PIC_SETTINGS_APPLY key=rotationInterval value=\(Int(store.rotationInterval)) applied=\(rotation == nil ? 0 : 1)")
    }

    /// 「电池时播放」开关的当场重估入口。电源跃迁与设置窗 toggle 走同一个方法，
    /// 所以这是全仓唯一一处 `.battery` 的 set 落点 —— 两处 set 会产生竞态双写。
    public func applyBatteryPolicy(isOnBattery: Bool) {
        arbiter.set(.battery, active: BatteryHoldPolicy.shouldHold(
            isOnBattery: isOnBattery,
            pauseOnBatteryEnabled: store.pauseOnBattery))
        WallpaperWindowController.emit(
            "PIC_SETTINGS_APPLY key=pauseOnBattery value=\(store.pauseOnBattery ? 1 : 0) applied=1 onBattery=\(isOnBattery ? 1 : 0)")
    }
}
