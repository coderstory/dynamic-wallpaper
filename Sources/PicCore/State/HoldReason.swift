/// 暂停否决原因（veto 集合，不是优先级链）。文案映射在 `SettingsPresentation.holdReasonLabel`。
public enum HoldReason: Hashable, Comparable, CaseIterable, Sendable {
    case manualPause

    /// 别的应用 / 界面进入全屏（本 app 自己的窗口不算）。
    case fullscreen

    case screenLocked

    case displayAsleep

    case systemSleeping

    /// 仅在「电池供电时暂停」开关打开时置位，唯一判定处是 `BatteryHoldPolicy.shouldHold`。
    case battery

    /// UI 文案排序用；**不参与播放决策**。取值必须两两不同且 `manualPause=0`：两个 case 共用一个 `order` 会让 `holds.sorted()` 在两者之间顺序不确定。
    public var order: Int {
        switch self {
        case .manualPause: return 0
        case .fullscreen: return 1
        case .screenLocked: return 2
        case .displayAsleep: return 3
        case .systemSleeping: return 4
        case .battery: return 5
        }
    }

    public static func < (lhs: HoldReason, rhs: HoldReason) -> Bool {
        lhs.order < rhs.order
    }
}