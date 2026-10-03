import Foundation

/// D-23 的播放第二入口 —— RED 编译骨架。
@MainActor
public final class ConvertedLibrary {

    private let probe: any VideoAssetProbe
    private let entryCap: Int

    public init(probe: any VideoAssetProbe = AVFoundationAssetProbe(), entryCap: Int = 5000) {
        self.probe = probe
        self.entryCap = entryCap
    }

    public func scan(folder: URL) async throws -> [VideoItem] {
        []
    }

    public static func playbackItems(root: [VideoItem], converted: [VideoItem]) -> [VideoItem] {
        []
    }
}
