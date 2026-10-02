/// 暂停否决原因（D-11：veto 集合，不是优先级链）。
///
/// 形状一次定死：Phase 3 只需新增 `case` 与对应的 `order` 分支，不改任何已有签名。
public enum HoldReason: Hashable, Comparable, CaseIterable, Sendable {
    /// 用户手动暂停。Phase 2 只有这一个 case。
    case manualPause

    /// UI 文案排序用；**不参与播放决策**（D-11）。
    /// Phase 3 在此新增：fullscreen(0) / screenLocked(1) / displayAsleep(2) /
    /// systemSleeping(3) / battery(4)。
    public var order: Int {
        switch self {
        case .manualPause: return 0
        }
    }

    public static func < (lhs: HoldReason, rhs: HoldReason) -> Bool {
        lhs.order < rhs.order
    }
}
