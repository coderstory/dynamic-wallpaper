import Foundation
import Observation

/// 播放端的唯一入口（ARCHITECTURE §6.4）。整个协议标 `@MainActor`：
/// 否则 Swift 6 下 conformance 报 `#ConformanceIsolation`，Phase 1 已实测。
@MainActor
public protocol PlaybackTarget: AnyObject {
    func arbiterCurrentPosition() -> TimeInterval
    func arbiterSeek(to seconds: TimeInterval)
    func arbiterApply(_ decision: PlaybackDecision)
}

/// 仲裁状态机（★ 三个接口之一）。
///
/// 单向流：Watcher 只产出 `HoldReason` → `HoldArbiter` 决定 `shouldPlay`
/// → `PlayerController` 执行。仲裁器**永不**直接碰播放器（D-10 / D-11）。
@MainActor
@Observable
public final class HoldArbiter {
    public private(set) var decision: PlaybackDecision

    /// 续播锚点：只在 `holds` 由 ∅ → 非∅ 的那一刻写入，消费后清空（D-15）。
    private var resumeAnchor: TimeInterval?

    private var target: PlaybackTarget?

    public init(target: PlaybackTarget? = nil) {
        self.target = target
        self.decision = PlaybackDecision()
    }

    public func attach(_ target: PlaybackTarget) {
        self.target = target
    }

    /// 「当前是否手动暂停」—— **只读派生量，不是独立真相源**（T-02-08）。
    ///
    /// UI 侧（菜单的「暂停 / 继续」文案）只读它。若 UI 另立一个可变的 `isPaused`，
    /// Phase 3 的 6 个 reason 叠加时就会出现「菜单说在播、仲裁说在停」的第二个真相源。
    public var isManuallyPaused: Bool { decision.holds.contains(.manualPause) }

    public func set(_ reason: HoldReason, active: Bool) {
        let before = decision.holds
        let after = active ? before.union([reason]) : before.subtracting([reason])

        // D-15：锚点只在 ∅ → 非∅ 的那一刻写入一次，此后不再更新 ——
        // 否则叠加暂停期间锚点会被二次覆盖，解除后从错误的位置续播。
        if before.isEmpty && !after.isEmpty {
            resumeAnchor = target?.arbiterCurrentPosition()
        }

        // 幂等：状态没变就不重复打扰播放端（ARCHITECTURE §6.4 不变式 4）。
        guard before != after else { return }

        decision = PlaybackDecision(holds: after)

        // 集合清空 = 解除暂停 → 回到最初锚定的位置续播，然后清空锚点（不变式 2）。
        if after.isEmpty, let anchor = resumeAnchor {
            target?.arbiterSeek(to: anchor)
            resumeAnchor = nil
        }

        target?.arbiterApply(decision)
    }

    /// 把**当前** decision 直接交给播放端，**不经过** `set` 的并/差与锚点逻辑。
    ///
    /// 起播路径用它，取代菜单边界外的直连播放（D-06 / `W-2026-10-03-10`）：
    /// 四个 Watcher 已在 `wiring()` 里先置位，所以「已 hold 却先播一下」不会发生。
    ///
    /// ⚠️ 它**不碰续播锚点、不触发 seek** —— 起播时若顺带 seek 到锚点，
    /// 锁屏会话下会把播放头拽回暂停前的位置。单测
    /// `testApplyCurrentDecisionForwardsCurrentDecisionWithoutTouchingAnchor` 锁住这一条。
    public func applyCurrentDecision() { target?.arbiterApply(decision) }

    /// 「当前为什么暂停」的对外读数（D-12 的数据落点）。
    ///
    /// **纯派生量**：`decision` 是唯一真相源，这里不缓存、不另存。
    /// Phase 5 的运行状态卡读它；Phase 3 只产数据，零渲染。
    public var holdStatus: HoldStatus {
        HoldStatus(shouldPlay: decision.shouldPlay, reasons: decision.activeReasons)
    }
}
