import Foundation

/// 「扫描结果 → 窗口/播放器动作」的唯一落点。架构职责表只定义了「谁负责什么」，
/// 把「谁调用谁」留空了；装配点是无屏环境跑不起来的 AppDelegate，所以串接落在这里 ——
/// 一个只对着**协议**说话的薄壳，无屏幕环境也能用记录式替身驱动。
///
/// ⚠️ 本文件不 import AppKit / AVFoundation —— 一旦直接持有
/// `WallpaperWindowController` / `PlayerController`，降级路径就退化成「只能靠肉眼验」。
/// 也**不做播放决策**：不碰仲裁器、不 `load()`、不动 rate / volume / muted。
@MainActor
public protocol WallpaperPresenting: AnyObject {
    func show()
    func hide()
}

/// 播放停止的 seam。刻意不叫 `stop()`：名字会与 `PlayerController.stop()`
/// 混淆，且 seam 的语义（「没有媒体了」）比它更宽。
@MainActor
public protocol PlaybackStopping: AnyObject {
    func stopPlayback()
}

@MainActor
public final class MediaCoordinator {

    public private(set) var lastState: LibraryState

    /// 供装配层打 `PIC_LIBRARY_STATE=` 行（只打 token，不带路径）。
    public var onStateChange: ((LibraryState) -> Void)?

    private let presenting: any WallpaperPresenting
    private let stopping: any PlaybackStopping

    /// `lastState` 的默认值承担不了「还没调用过」与「调用过且状态相同」的区分。
    private var hasAppliedOnce = false

    public init(presenting: any WallpaperPresenting, stopping: any PlaybackStopping) {
        self.presenting = presenting
        self.stopping = stopping
        self.lastState = .folderUnconfigured
    }

    /// 决策交给纯函数 `LibraryAvailability.evaluate`，本方法只做执行：
    /// `.playing` → 只 `show()`；三个隐藏态 → `stopPlayback()` + `hide()`。
    /// 重复输入幂等：探针会反复投同一状态，重复执行会让窗口可见性读数不确定、
    /// 让 evidence 出现重复行。
    @discardableResult
    public func apply(scanOutcome: Result<Int, MediaLibrary.MediaLibraryError>,
                      folderConfigured: Bool) -> LibraryState {
        let next = LibraryAvailability.evaluate(folderConfigured: folderConfigured, scanOutcome: scanOutcome)

        // 幂等门：连续同样的输入不重复执行。
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
