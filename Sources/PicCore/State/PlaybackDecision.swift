/// 播放决策：`holds` 是唯一的播放判据（ARCHITECTURE §6.2）。
public struct PlaybackDecision: Equatable, Sendable {
    /// 当前所有生效的否决原因。空集合 = 应当播放。
    public let holds: Set<HoldReason>

    public init(holds: Set<HoldReason> = []) {
        self.holds = holds
    }

    public var shouldPlay: Bool { holds.isEmpty }

    /// 按 `order` 排好的原因列表 —— **仅供 UI 文案**，不参与决策（D-11）。
    public var activeReasons: [HoldReason] { holds.sorted() }
}
