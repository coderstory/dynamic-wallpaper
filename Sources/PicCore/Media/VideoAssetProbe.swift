import AVFoundation
import Foundation

/// 视频轨探测入口。【可注入】—— 单测用 `FakeAssetProbe`（放 Tests/，不是产品代码）。
public protocol VideoAssetProbe: Sendable {
    /// 该 URL 能否解出至少一条视频轨。
    func hasVideoTrack(_ url: URL) async -> Bool
}

/// 默认实现：用异步 `loadTracks(withMediaType:)` 读视频轨。
///
/// ⚠️ 不要用同名的同步取值接口 —— macOS 13 起已弃用（本机 macOS 27 实测会打
/// 弃用警告），判据会变成噪声。
public struct AVFoundationAssetProbe: VideoAssetProbe {
    public init() {}

    public func hasVideoTrack(_ url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        do {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            return !tracks.isEmpty
        } catch {
            return false
        }
    }
}