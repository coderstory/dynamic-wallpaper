import Foundation

/// 媒体库可用性的**决策层**：把「扫描结果」翻译成「壁纸窗口该不该在」的纯函数。
///
/// ⚠️ **本文件不做执行。** 它不碰 `SettingsStore`、不碰扫描、不碰任何窗口 ——
/// `evaluate` 只吃标量、吐一个枚举；执行是 `MediaCoordinator` 与装配层的活。
/// 把 `resolvedFolderURL()` / `scan()` / `FileManager` 塞进来会让它再也无法被单测穷举。
///
/// 分层纪律（同 `State/` 的 HoldStatus）：决策层**不允许** `import AppKit` /
/// `import SwiftUI` / `import AVFoundation` —— 那会让「决策是纯函数」被自己的 import 作废。
public enum LibraryState: String, Equatable, Sendable, CaseIterable {
    /// 从未选定过壁纸目录 —— 唯一「用户还没选」的状态，与「选了一个但没了」不同。
    case folderUnconfigured
    /// 选过，但根目录现在不存在 / 不可读。
    case folderMissing
    /// 根目录在，扫描成功，但可用条数为 0
    /// （全非白名单格式 / 全解不出视频轨 / entryCap 截断后一条没收）。
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

    /// 机器可 grep 的小写 token。**结构性不可能夹带路径或文件名**：
    /// 四个值都是固定单词，供装配层打 `PIC_LIBRARY_STATE=` 行、做判据。
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

    /// 三输入 → 一枚举。`folderConfigured == false` 压过一切（没选目录时不该问扫描结果）；
    /// 两个「目录本身出问题」的错误归 `.folderMissing`，**其他** failure 兜底 `.noPlayableVideos`。
    /// 兜底分支看着多余但不是死代码：将来 `MediaLibraryError` 加 case 时这里 exhaustively
    /// switch，编译器会提醒补分支。`success(负数)` 结构上不可能，不加分支。
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

    /// 供打点用。只回 `reasonToken`，不带任何路径或文件名（隐私纪律）。
    public static func token(_ state: LibraryState) -> String {
        state.reasonToken
    }
}
