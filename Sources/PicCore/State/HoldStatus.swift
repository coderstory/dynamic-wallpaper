import Foundation

/// 「当前为什么暂停」的**数据**落点。全部是 `decision` 的纯派生量 —— UI 侧**没有第二个
/// 真相源**。若 UI 另存一份可变的 `reasons`，6 个 reason 叠加时就会与仲裁器不一致。
///
/// ⚠️ **本文件不做渲染。** 零 UI；运行状态卡才渲染它，届时只读本文件。因此这里**不允许**
/// `import SwiftUI` / `import AppKit` —— 那会让「只产数据」这条分层判据被自己的 import 作废。
///
/// ⚠️ `HoldReason.order` 的唯一用途就是让 `labels` / `summary` 顺序确定（优先级只允许用于
/// 文案排序，不参与播放决策）。
public struct HoldStatus: Equatable, Sendable {
    /// 与 `PlaybackDecision.shouldPlay` 同源，不另算。
    public let shouldPlay: Bool

    /// 已按 `order` 升序排好的原因，复用 `PlaybackDecision.activeReasons` 不重排（重排会让两个真相源漂移）。
    public let reasons: [HoldReason]

    public init(shouldPlay: Bool, reasons: [HoldReason]) {
        self.shouldPlay = shouldPlay
        self.reasons = reasons
    }

    /// 每条原因的中文文案，顺序同 `reasons`。
    public var labels: [String] { reasons.map(\.uiLabel) }

    /// 播放中返回 `nil`；暂停时返回按 `order` 排好序、逗号分隔的中文原因串。用 `nil` 而非空串
    /// 表示「在播」：空串会让下游 `grep summary=` 同时匹配到「在播」与「有原因但文案为空」。
    public var summary: String? {
        reasons.isEmpty ? nil : labels.joined(separator: ",")
    }
}

extension HoldReason {
    /// UI 文案（优先级只允许用于文案排序，不参与播放决策）。六个 case 各有一条互不相同且
    /// 非占位的中文（`HoldStatusTests` 断言两两不等）；刻意不写 `default:`，加 case 忘了写
    /// 文案会在编译期暴露，而不是显示成空。
    public var uiLabel: String {
        switch self {
        case .manualPause: return "手动暂停"
        case .fullscreen: return "全屏"
        case .screenLocked: return "锁屏"
        case .displayAsleep: return "显示器熄屏"
        case .systemSleeping: return "系统睡眠"
        case .battery: return "电池供电"
        }
    }
}