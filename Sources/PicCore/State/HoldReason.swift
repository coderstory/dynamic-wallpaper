/// 暂停否决原因（D-11：veto 集合，不是优先级链）。
///
/// 形状一次定死：Phase 3 只需新增 `case` 与对应的 `order` 分支，不改任何已有签名。
public enum HoldReason: Hashable, Comparable, CaseIterable, Sendable {
    /// 用户手动暂停。Phase 2 只有这一个 case。
    case manualPause

    /// 有别的应用 / 界面进入了全屏（D-02 的判定逻辑在 03-02，本 plan 只留 case）。
    case fullscreen

    /// 本机会话锁着。信号来自 `LockWatcher`（`Sources/PicCore/System/`）。
    case screenLocked

    /// 显示器熄屏（03-03 交付检测，本 plan 只留 case）。
    case displayAsleep

    /// 系统进入睡眠（03-03 交付检测，本 plan 只留 case）。
    case systemSleeping

    /// 电池供电且开关打开（D-11：默认关闭）。
    case battery

    /// UI 文案排序用；**不参与播放决策**（D-11）。
    ///
    /// ⚠️ 取值更正（W-2026-10-03-14）：Phase 2 的文件头注释预告新 case 取
    /// `fullscreen(0) / screenLocked(1) / displayAsleep(2) / systemSleeping(3) / battery(4)`，
    /// 但 `manualPause` **已经占着 0**。两个 case 共用同一个 `order` 会让
    /// `PlaybackDecision.activeReasons`（即 `holds.sorted()`）在这两者之间顺序不确定，
    /// 「优先级只用于 UI 文案排序」（D-10）就失效了。
    /// → 取值固定为 `manualPause=0`（Phase 2 的值，一个字不改）、其余依次 1…5。
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