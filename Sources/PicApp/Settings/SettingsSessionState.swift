import Foundation
import Observation
import PicCore

/// 设置窗读的**会话态**：媒体库最近一次扫描的读数。
/// 不进 `SettingsStore`（八键冻结）—— 都是本次运行的读数，不 persist、不跨启动保留。
@MainActor
@Observable
final class SettingsSessionState {
    /// 最近一次媒体库状态；还没扫过是 nil。
    var lastLibraryState: LibraryState?
    var playableCount = 0
    var lastScanDate: Date?
    /// 防重入：扫描期间三个入口一起置灰。
    var isScanning = false
    /// ffmpeg 可用性读数，`AppDelegate.refreshFFmpegAvailability` 的唯一回填点。
    /// 视图不能直读 AppDelegate：那个 Bool 不是可观察状态，刷新后卡片不重渲染。
    var ffmpegAvailable = false
    /// 菜单面板「打开设置 / 去片库转码」的落地页请求（0 播放 / 1 片库 / 2 通用）。
    /// 一次性：SettingsView 读后即清。窗未开时 onAppear 消费，窗已开时 onChange 消费。
    var requestedTab: Int?

    /// 协调器状态变更的**唯一**写入口（AppDelegate 的 onStateChange handler 调）。
    func update(state: LibraryState) {
        lastLibraryState = state
        lastScanDate = Date()
        // 隐藏态必须归零：留着旧数字会出现「有 N 个视频」却什么都没播。
        if !state.shouldShowWallpaper { playableCount = 0 }
    }
}
