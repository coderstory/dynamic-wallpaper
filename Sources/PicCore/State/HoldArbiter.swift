import Foundation
import Observation

/// 播放端唯一入口。整个协议必须标 `@MainActor`：Swift 6 下非隔离类型的 conformance 报 `#ConformanceIsolation`。
@MainActor
public protocol PlaybackTarget: AnyObject {
    func arbiterCurrentPosition() -> TimeInterval
    func arbiterSeek(to seconds: TimeInterval)
    func arbiterApply(_ decision: PlaybackDecision)
}

/// 全仓唯一的播放决策点。单向流：Watcher 只产出 `HoldReason` → 仲裁器决定 `shouldPlay` → `PlayerController` 执行。
///
/// 菜单与设置窗**不得直连播放器**：那会产生第二个真相源，六个 reason 叠加时菜单与仲裁结论不一致。仲裁器自身也永不碰播放器。
@MainActor
@Observable
public final class HoldArbiter {
    public private(set) var decision: PlaybackDecision

    /// 续播锚点：只在 `holds` 由 ∅ → 非∅ 的那一刻写入，消费后清空。
    private var resumeAnchor: TimeInterval?

    private var target: PlaybackTarget?

    public init(target: PlaybackTarget? = nil) {
        self.target = target
        self.decision = PlaybackDecision()
    }

    public func attach(_ target: PlaybackTarget) {
        self.target = target
    }

    /// 「当前是否手动暂停」—— **只读派生量，不是独立真相源**。UI 侧若另立一个可变的 `isPaused`，就会出现「菜单说在播、仲裁说在停」的第二个真相源。
    public var isManuallyPaused: Bool { decision.holds.contains(.manualPause) }

    public func set(_ reason: HoldReason, active: Bool) {
        let before = decision.holds
        let after = active ? before.union([reason]) : before.subtracting([reason])

        // 锚点只在 ∅ → 非∅ 写入一次，此后不再更新：叠加暂停期间二次覆盖会让解除后从错误位置续播。
        if before.isEmpty && !after.isEmpty {
            resumeAnchor = target?.arbiterCurrentPosition()
        }

        // 幂等：状态没变就不打扰播放端 —— 否则同一次 hold 会重复 apply。
        guard before != after else { return }

        decision = PlaybackDecision(holds: after)

        // 集合清空 = 解除暂停 → 回锚定位置续播，然后清空锚点。
        if after.isEmpty, let anchor = resumeAnchor {
            target?.arbiterSeek(to: anchor)
            resumeAnchor = nil
        }

        target?.arbiterApply(decision)
    }

    /// 把**当前** decision 直接交给播放端，**绕过** `set` 的并/差与锚点逻辑。调用前置：四个 Watcher 已在 `wiring()` 里置位，否则处于 hold 的会话会「先播一下」。
    ///
    /// 它**不碰续播锚点、不触发 seek** —— 起播时顺带 seek 会把锁屏会话的播放头拽回暂停前的位置。
    public func applyCurrentDecision() { target?.arbiterApply(decision) }

    /// 「当前为什么暂停」的对外读数。**纯派生量**：`decision` 是唯一真相源，不缓存、不另存。
    public var holdStatus: HoldStatus {
        HoldStatus(shouldPlay: decision.shouldPlay, reasons: decision.activeReasons)
    }
}
