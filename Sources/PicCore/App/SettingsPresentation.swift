import Foundation

/// 设置窗的纯显示映射：只做「值 ↔ 显示形态」的换算，不碰 SwiftUI/AppKit/AVFoundation，
/// 不做任何决策。窗口常量是唯一来源，视图与单测都读它，不许在别处散落字面量。
public enum SettingsPresentation {
    /// 设置窗打开时的宽度（`.defaultSize` / `idealWidth` 读这里）。
    public static let windowWidth: CGFloat = 780
    /// 设置窗的最小内容宽度（`contentMinSize` 的来源）。
    public static let windowMinWidth: CGFloat = 680
    /// 速度滑杆的合法区间。
    public static let rateBounds: ClosedRange<Float> = 0.5...2.0

    /// 速度读数（`1.00×`）。越界值先 clamp 进 `rateBounds` 再格式化。
    public static func rateLabel(_ rate: Float) -> String {
        let clamped = min(max(rate, rateBounds.lowerBound), rateBounds.upperBound)
        return String(format: "%.2f×", clamped)
    }

    /// store（Float 0–1）→ UI（0–100 整数）。映射红线。
    public static func volumePercent(_ volume: Float) -> Int {
        let clamped = min(max(volume, 0), 1)
        return Int((clamped * 100).rounded())
    }

    /// UI（0–100 整数）→ store（Float 0–1）。
    public static func volumeFromPercent(_ percent: Int) -> Float {
        min(max(Float(percent) / 100, 0), 1)
    }


    /// 轮换间隔的封闭值表（分钟）。换算只落在下面两个函数（视图里不出现第二份 ×60）。
    public static let rotationChoicesMinutes: [Int] = [5, 10, 15, 30, 60, 120]

    /// 步进器读数：`>= 60` 显示「N 小时」，否则「N 分钟」。
    public static func rotationLabel(minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60) 小时" : "\(minutes) 分钟"
    }

    /// UI 分钟 → store 秒（`rotationInterval` 的量纲是秒）。
    public static func rotationSeconds(minutes: Int) -> TimeInterval {
        TimeInterval(minutes) * 60
    }

    /// store 秒 → 表内分钟，就近吸附：对不上值表的旧值回落到最近的表项，否则步进器会索引越界。
    public static func rotationMinutes(seconds: TimeInterval) -> Int {
        let target = seconds / 60
        return rotationChoicesMinutes.min {
            abs(Double($0) - target) < abs(Double($1) - target)
        } ?? rotationChoicesMinutes[0]
    }

    /// 置灰联动①。判据只允许出现在下面这一行 return 上。
    public static func rotationControlsEnabled(playMode: PlayMode) -> Bool {
        return playMode != .loopSingle
    }

    /// 置灰联动②。同上。
    public static func volumeControlsEnabled(isMuted: Bool) -> Bool {
        return !isMuted
    }

    /// 分段控件文案（按 `PlayMode.allCases` 顺序渲染）。
    public static func playModeLabel(_ mode: PlayMode) -> String {
        switch mode {
        case .loopSingle: return "单循环"
        case .loopList: return "列表循环"
        case .shuffle: return "随机"
        }
    }


    /// 空态副行（逐字硬需求）。全仓唯一一份：视图与单测都引用它。
    public static let emptyStateBody = "没找到能播的文件。壁纸已隐藏，桌面显示的是系统原壁纸。"

    ///  三态一张皮：没配过 / 目录没了 / 扫到 0 在 UI 上**不区分**， 判定就是「不该显示壁纸」的反面。
    public static func isEmptyState(_ state: LibraryState) -> Bool {
        return !state.shouldShowWallpaper
    }

    /// 空态的标题 / 原因说明 / 主行动。
    public struct EmptyStateCopy: Equatable, Sendable {
        public let title: String
        public let reason: String
        public let primaryAction: String

        public init(title: String, reason: String, primaryAction: String) {
            self.title = title
            self.reason = reason
            self.primaryAction = primaryAction
        }
    }

    /// LibraryState → 空态文案。`.playing` 返回 nil（那时不该显示空态）。
    /// 与 isEmptyState(_:) 平行而非替代：那个回答「该不该显示壁纸」，这个回答「怎么告诉用户」。
    public static func emptyStateCopy(_ state: LibraryState) -> EmptyStateCopy? {
        switch state {
        case .folderUnconfigured:
            return EmptyStateCopy(
                title: "还没选壁纸文件夹",
                reason: "Pic 还不知道该去哪里找视频。选一个文件夹，里面所有能播的视频都会进轮换池。",
                primaryAction: "选择文件夹…")
        case .folderMissing:
            return EmptyStateCopy(
                title: "壁纸文件夹不见了",
                reason: "上次选的位置现在不存在或读不了。可能被改名、被移动，或在没挂载的磁盘上。",
                primaryAction: "重新选择文件夹…")
        case .noPlayableVideos:
            return EmptyStateCopy(
                title: "没有能直接播的文件",
                reason: "文件夹能正常读取，但里面 0 个能直接播的文件。MKV / AVI / WEBM 需要先转成 MP4 才能当壁纸。",
                primaryAction: "去片库转码")
        case .playing:
            return nil
        }
    }

    /// 暂停原因 → 副标签。刻意**不写 `default:`**：`HoldReason` 加 case 时编译不过，
    /// 比漏一分支静默显示错文案安全。
    public static func holdReasonLabel(_ reason: HoldReason) -> String {
        switch reason {
        case .manualPause: return "手动暂停"
        case .fullscreen: return "检测到全屏应用"
        case .screenLocked: return "屏幕已锁定"
        case .displayAsleep: return "显示器已熄屏"
        case .systemSleeping: return "系统正在睡眠"
        case .battery: return "电池供电中"
        }
    }

    /// 多原因按 `order` 排序后顿号连接（veto 集合下叠加原因必须全列 —— 只列一个会让用户
    /// 误判成 bug）。空集合 → 空串，调用方据此走「播放中」分支。排序只允许出现在本函数。
    public static func joinedReasons(_ reasons: [HoldReason]) -> String {
        guard !reasons.isEmpty else { return "" }
        return reasons.sorted().map(holdReasonLabel).joined(separator: "、")
    }
}
