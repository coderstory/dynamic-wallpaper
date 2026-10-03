/// 暂停否决原因（veto 集合，不是优先级链）。
public enum HoldReason: Hashable, Comparable, CaseIterable, Sendable {
    /// 用户手动暂停。
    case manualPause

    /// 有别的应用 / 界面进入了全屏。
    case fullscreen

    /// 本机会话锁着。信号来自 `LockWatcher`（`Sources/PicCore/System/`）。
    case screenLocked

    /// 显示器熄屏。
    case displayAsleep

    case systemSleeping

    /// 电池供电且开关打开（默认关闭）。
    case battery

    /// UI 文案排序用；**不参与播放决策**。
    ///
    /// ⚠️ 取值固定为 `manualPause=0`、其余依次 1…5 —— 曾预告过新 case 从 `fullscreen(0)`
    /// 起排，但 0 已被 `manualPause` 占用；两个 case 共用一个 `order` 会让 `holds.sorted()`
    /// 在这两者之间顺序不确定，「优先级只用于 UI 文案排序」就失效了。
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