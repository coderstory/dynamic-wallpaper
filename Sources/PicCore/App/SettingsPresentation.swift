import Foundation

/// 设置窗的纯显示映射（Plan 05-01 T1）。
///
/// 职责边界：只做「值 ↔ 显示形态」的换算，不碰 SwiftUI/AppKit/AVFoundation
/// （剥注释判据锁着），不做任何决策。窗口常量是 SC-1 两个数的唯一来源，
/// 视图与探针都读它，不许在别处散落字面量。
public enum SettingsPresentation {
    /// SC-1：设置窗打开时的宽度（`.defaultSize` / `idealWidth` 读这里）。
    public static let windowWidth: CGFloat = 780
    /// SC-1：设置窗的最小内容宽度（`contentMinSize` 的来源）。
    public static let windowMinWidth: CGFloat = 680
    /// PLAY-07：速度滑杆的合法区间。
    public static let rateBounds: ClosedRange<Float> = 0.5...2.0

    /// 速度读数（`1.00×`）。越界值先 clamp 进 `rateBounds` 再格式化 ——
    /// 持久化值被外部改坏时 UI 也不显示离谱数字。
    public static func rateLabel(_ rate: Float) -> String {
        let clamped = min(max(rate, rateBounds.lowerBound), rateBounds.upperBound)
        return String(format: "%.2f×", clamped)
    }

    /// store（Float 0–1）→ UI（0–100 整数）。UI-SPEC §11 的映射红线。
    public static func volumePercent(_ volume: Float) -> Int {
        let clamped = min(max(volume, 0), 1)
        return Int((clamped * 100).rounded())
    }

    /// UI（0–100 整数）→ store（Float 0–1）。
    public static func volumeFromPercent(_ percent: Int) -> Float {
        min(max(Float(percent) / 100, 0), 1)
    }
}
