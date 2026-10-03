import Foundation

/// 「扫描结果 → 窗口/播放器动作」的唯一落点（Plan 04-03 T3）。
///
/// ARCHITECTURE 的组件职责表里没有这一环 —— 表只定义了「谁负责什么」
/// （`MediaLibrary` 递归扫描、`PlayerController` 持有播放器、
/// `WallpaperWindowController` 建/销毁窗口），把「谁调用谁」留空了。
/// 04-05 的 `AppDelegate` 是唯一装配点（D-10），但把这段串接写进
/// `AppDelegate` 就无法单测（它需要真实屏幕与 run loop）。所以它落在这里：
/// 一个只对着**协议**说话的薄壳，无屏幕环境也能用记录式替身驱动。
///
/// ⚠️ 本文件不 import AppKit / AVFoundation —— 一旦直接持有
/// `WallpaperWindowController` / `PlayerController`，降级路径就退化成
/// 「只能靠肉眼验」。也**不做播放决策**：不碰仲裁器、不 `load()`、
/// 不动 rate / volume / muted —— 那些是 04-05 `wiring()` 的活
/// （D-06 的单向流里没有「协调器」这一环）。
@MainActor
public protocol WallpaperPresenting: AnyObject {
    func show()
    func hide()
}

/// 播放停止的 seam。刻意不叫 `stop()`：名字会与 `PlayerController.stop()`
/// 混淆，且 seam 的语义（「没有媒体了」）比它更宽 —— 将来可能要顺带
/// `setVolume(0)` 之类。产品实现由 04-05 包住 `PlayerController.stop()`。
@MainActor
public protocol PlaybackStopping: AnyObject {
    func stopPlayback()
}

@MainActor
public final class MediaCoordinator {

    public private(set) var lastState: LibraryState

    /// 04-05 用它打 `PIC_LIBRARY_STATE=` 行（只打 token，不带路径）。
    public var onStateChange: ((LibraryState) -> Void)?

    private let presenting: any WallpaperPresenting
    private let stopping: any PlaybackStopping

    /// 区分「还没调用过」与「调用过且状态相同」：`lastState` 的默认值
    /// 承担不了这个区分，第一次 `apply` 必须真执行。
    private var hasAppliedOnce = false

    public init(presenting: any WallpaperPresenting, stopping: any PlaybackStopping) {
        self.presenting = presenting
        self.stopping = stopping
        self.lastState = .folderUnconfigured
    }

    /// 决策交给纯函数 `LibraryAvailability.evaluate`，本方法只做执行：
    /// `.playing` → 只 `show()`；三个隐藏态 → `stopPlayback()` + `hide()`。
    /// 重复输入幂等：探针会反复投同一状态，重复调用会让窗口可见性读数
    /// 变得不确定、让 04-05 的 evidence 出现重复行。
    @discardableResult
    public func apply(scanOutcome: Result<Int, MediaLibrary.MediaLibraryError>,
                      folderConfigured: Bool) -> LibraryState {
        let next = LibraryAvailability.evaluate(folderConfigured: folderConfigured, scanOutcome: scanOutcome)

        // 幂等门：连续同样的输入不重复执行（第一次由 hasAppliedOnce 放行 ——
        // `lastState` 的默认值区分不了「未调用过」与「调用过且状态相同」）。
        if hasAppliedOnce {
            guard next != lastState else { return lastState }
        }
        hasAppliedOnce = true

        switch next {
        case .playing:
            presenting.show()
        case .folderUnconfigured, .folderMissing, .noPlayableVideos:
            stopping.stopPlayback()
            presenting.hide()
        }

        lastState = next
        onStateChange?(next)
        return next
    }
}
