import Foundation
import Observation
import PicCore

/// 设置窗读的**会话态**：媒体库最近一次扫描的读数。
///
/// ⚠️ 不进 `SettingsStore` —— 七键冻结（04-02 D-03）。这里每个字段都是本次
/// 运行的读数，不该被 persist，也不该跨启动保留。
@MainActor
@Observable
final class SettingsSessionState {
    /// 最近一次媒体库状态；还没扫过是 nil（设置窗在扫描前打开的那一瞬）。
    var lastLibraryState: LibraryState?
    var playableCount = 0
    var lastScanDate: Date?
    /// 防重入：扫描期间三个入口一起置灰。
    var isScanning = false

    /// 协调器状态变更的**唯一**写入口（AppDelegate 的 onStateChange handler 调）。
    func update(state: LibraryState) {
        lastLibraryState = state
        lastScanDate = Date()
        // 隐藏态的计数归零：目录没了或被换掉后还留着旧数字，用户会看到
        // 「有 N 个视频」却什么都没播 —— 空态皮因此是假的。
        if !state.shouldShowWallpaper { playableCount = 0 }
    }
}
