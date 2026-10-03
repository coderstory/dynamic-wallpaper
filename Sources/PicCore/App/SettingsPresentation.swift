import Foundation

/// 设置窗的纯显示映射（Plan 05-01 T1）。
///
/// 职责边界：只做「值 ↔ 显示形态」的换算，不碰 SwiftUI/AppKit/AVFoundation
/// （剥注释判据锁着），不做任何决策。窗口常量是 SC-1 两个数的唯一来源。
public enum SettingsPresentation {
    public static let windowWidth: CGFloat = 0
    public static let windowMinWidth: CGFloat = 0
    public static let rateBounds: ClosedRange<Float> = 0...0

    public static func rateLabel(_ rate: Float) -> String {
        ""
    }

    public static func volumePercent(_ volume: Float) -> Int {
        0
    }

    public static func volumeFromPercent(_ percent: Int) -> Float {
        0
    }
}
