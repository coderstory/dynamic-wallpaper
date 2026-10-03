import Foundation

/// 一个被扫描器接受的视频条目。
///
/// 只有 `url` 一个字段。加 duration / resolution / displayName 等于给
/// `Equatable` 造一个没人验证的维度。
public struct VideoItem: Equatable, Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }
}