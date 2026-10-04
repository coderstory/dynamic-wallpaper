import AVFoundation
import Foundation

/// 视频轨元信息 —— 探测的唯一返回值。
///
/// ⚠️ 放宽成结构而非加第二个方法：`hasVideoTrack` 把 `AVAssetTrack` 当场丢掉，
/// 再探帧率要重开一次 `AVURLAsset`。三项都可为 nil，调用方按「不降」处理。
public struct VideoAssetMetadata: Equatable, Sendable {
    public let hasVideoTrack: Bool
    public let frameRate: Double?
    public let durationSeconds: Double?

    public init(hasVideoTrack: Bool, frameRate: Double? = nil, durationSeconds: Double? = nil) {
        self.hasVideoTrack = hasVideoTrack
        self.frameRate = frameRate
        self.durationSeconds = durationSeconds
    }

    /// 帧率是否高于给定的封顶线。**恰好等于不降** —— NTSC 的 29.97 也走这条路。
    ///
    /// ⚠️ 封顶线由调用方传，不在这里引用 `FpsDownscaleCommand` ——
    /// 那会让 Media/ 反向依赖 Transcode/，两个探针脚本的编译面会因此破。
    public func exceedsFrameRate(_ target: Double) -> Bool {
        guard let frameRate else { return false }
        return frameRate > target
    }
}

/// 视频轨探测入口。【可注入】—— 单测用 `FakeAssetProbe`（放 Tests/，不是产品代码）。
public protocol VideoAssetProbe: Sendable {
    /// 该 URL 的视频轨元信息。⚠️ 解不出视频轨（文件损坏、无视频流）时返回
    /// `hasVideoTrack = false`，**不是抛错也不是 nil** —— 扫描器要跳过它，
    /// 但不能因此中断整轮扫描。
    func metadata(_ url: URL) async -> VideoAssetMetadata
}

/// 默认实现：一次 `AVURLAsset` 打开同时取到视频轨、帧率、时长。
/// ⚠️ 不要用同名的同步取值接口 —— macOS 13 起已弃用（本机实测会打弃用警告），判据会变成噪声。
public struct AVFoundationAssetProbe: VideoAssetProbe {
    public init() {}

    public func metadata(_ url: URL) async -> VideoAssetMetadata {
        let asset = AVURLAsset(url: url)
        do {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else {
                return VideoAssetMetadata(hasVideoTrack: false)
            }
            // 帧率与时长分开 try：其中一个读不到不该把另一个作废。
            let frameRate = try? await track.load(.nominalFrameRate)
            let duration = try? await asset.load(.duration)
            return VideoAssetMetadata(
                hasVideoTrack: true,
                frameRate: frameRate.map(Double.init),
                durationSeconds: duration?.seconds)
        } catch {
            return VideoAssetMetadata(hasVideoTrack: false)
        }
    }
}