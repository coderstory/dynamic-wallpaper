import Foundation

/// 媒体库可用性的**决策层**：把「扫描结果」翻译成「壁纸窗口该不该在」的纯函数。
///
/// `evaluate` 只吃标量、吐一个枚举；执行是 `MediaCoordinator` 与装配层的活。把 `SettingsStore` / `scan()` / `FileManager` 塞进来会让它再也无法被单测穷举，因此本文件**不 import AppKit / SwiftUI / AVFoundation**。
public enum LibraryState: String, Equatable, Sendable, CaseIterable {
    /// 从未选定过壁纸目录 —— 与「选了一个但没了」是不同的状态。
    case folderUnconfigured
    /// 根目录现在不存在或不可读。
    case folderMissing
    /// 根目录在、扫描成功，但可用条数为 0（全非白名单格式 / 全解不出视频轨 / entryCap 截断后一条没收）。
    case noPlayableVideos
    /// 有可用视频。
    case playing

    /// 恰好三个 false、一个 true。
    public var shouldShowWallpaper: Bool {
        switch self {
        case .folderUnconfigured, .folderMissing, .noPlayableVideos:
            return false
        case .playing:
            return true
        }
    }

    /// 机器可读的小写 token。固定单词，**不得夹带路径或文件名**。
    public var reasonToken: String {
        switch self {
        case .folderUnconfigured: return "folder_unconfigured"
        case .folderMissing: return "folder_missing"
        case .noPlayableVideos: return "no_playable_videos"
        case .playing: return "playing"
        }
    }
}

/// 唯一的决策函数（静态命名空间，不持任何状态）。
public enum LibraryAvailability {

    /// 三输入 → 一枚举。`folderConfigured == false` 压过一切（没选目录时不该问扫描结果）；两个「目录本身出问题」的错误归 `.folderMissing`，**其他** failure 兜底 `.noPlayableVideos`。
    ///
    /// 兜底分支看着多余但不是死代码：将来 `MediaLibraryError` 加 case 时这里的 exhaustive switch 会要求补分支。`success(负数)` 结构上不可能，不加分支。
    public static func evaluate(folderConfigured: Bool,
                                scanOutcome: Result<Int, MediaLibrary.MediaLibraryError>) -> LibraryState {
        guard folderConfigured else { return .folderUnconfigured }
        switch scanOutcome {
        case .failure(.folderMissing), .failure(.folderUnreadable):
            return .folderMissing
        case .failure:
            return .noPlayableVideos
        case .success(let playableCount):
            return playableCount >= 1 ? .playing : .noPlayableVideos
        }
    }

    /// 供打点用，只回 `reasonToken`，不带任何路径或文件名。
    public static func token(_ state: LibraryState) -> String {
        state.reasonToken
    }
}
