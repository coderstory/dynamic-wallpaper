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

    // MARK: - Plan 05-02 T1：轮换值表与两条置灰联动

    /// 轮换间隔的封闭值表（UI-SPEC §7，分钟）。UI 只在表内选，
    /// 换算的**唯一**落点在下面两个函数（视图里不出现第二份 ×60）。
    public static let rotationChoicesMinutes: [Int] = [5, 10, 15, 30, 60, 120]

    /// 步进器读数：`>= 60` 显示「N 小时」，否则「N 分钟」。
    public static func rotationLabel(minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60) 小时" : "\(minutes) 分钟"
    }

    /// UI 分钟 → store 秒（`rotationInterval` 的量纲是秒）。
    public static func rotationSeconds(minutes: Int) -> TimeInterval {
        TimeInterval(minutes) * 60
    }

    /// store 秒 → 表内分钟。**就近吸附**：持久化旧值（例如 299×60）对不上值表时
    /// 回落到最近的表项，否则步进器会索引到越界位置（UI-SPEC §7 的量纲红线）。
    public static func rotationMinutes(seconds: TimeInterval) -> Int {
        let target = seconds / 60
        return rotationChoicesMinutes.min {
            abs(Double($0) - target) < abs(Double($1) - target)
        } ?? rotationChoicesMinutes[0]
    }

    /// 置灰联动①（UI-03 / SC-3）。判据字面量只允许出现在下面这一行 return 上 ——
    /// 写进注释会让变异的替换打在注释上、代码没坏（03-04 踩过，D-15）。
    public static func rotationControlsEnabled(playMode: PlayMode) -> Bool {
        return playMode != .loopSingle
    }

    /// 置灰联动②（UI-03 / SC-3）。同 D-15：判据只出现在 return 行。
    public static func volumeControlsEnabled(isMuted: Bool) -> Bool {
        return !isMuted
    }

    /// 分段控件文案（按 `PlayMode.allCases` 顺序渲染，04-02 T1 锁序）。
    public static func playModeLabel(_ mode: PlayMode) -> String {
        switch mode {
        case .loopSingle: return "单循环"
        case .loopList: return "列表循环"
        case .shuffle: return "随机"
        }
    }

    // MARK: - 空态 / 运行状态卡的文案映射

    /// 空态副行（UI-02 逐字硬需求）。**全仓唯一一份**：视图与探针都引用它，
    /// 第二份拷贝不会自己漂移提醒，只会漂成两个版本的承诺。
    public static let emptyStateBody = "没找到能播的文件。壁纸已隐藏，桌面显示的是系统原壁纸。"

    /// 三态一张皮：没配过 / 目录没了 / 扫到 0 在 UI 上**不区分**，
    /// 判定就是「不该显示壁纸」的反面。
    public static func isEmptyState(_ state: LibraryState) -> Bool {
        return !state.shouldShowWallpaper
    }

    /// 暂停原因 → 副标签。刻意**不写 `default:`**（照 HoldStatus.swift）：
    /// `HoldReason` 加 case 时编译不过，比漏一分支静默显示错文案安全。
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

    /// 多原因按 `order` 排序后顿号连接（veto 集合下叠加原因必须全列 ——
    /// 只列一个会让用户误判成 bug）。空集合 → 空串，调用方据此走「播放中」分支。
    ///
    /// ⚠️ 排序调用**只允许出现在本函数**：这是 D-15 的变异靶点，
    /// 抄进注释会让「拿掉排序」那条变异打偏而不改代码。
    public static func joinedReasons(_ reasons: [HoldReason]) -> String {
        guard !reasons.isEmpty else { return "" }
        return reasons.sorted().map(holdReasonLabel).joined(separator: "、")
    }

    public static let playbackPausedTitle = "已暂停"
    public static let playbackRunningTitle = "播放中"
}
