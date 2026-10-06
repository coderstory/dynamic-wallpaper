import Foundation

/// 播放第二入口：扫 `<壁纸目录>/Converted/` 子树，产出与根扫描 items 合并的清单。
/// 与 `MediaLibrary` 同隔离域。不做缓存 —— 转码完成会触发全量重扫，加缓存反而要管失效。
@MainActor
public final class ConvertedLibrary {

    private let probe: any VideoAssetProbe
    private let entryCap: Int

    public init(probe: any VideoAssetProbe = AVFoundationAssetProbe(), entryCap: Int = 5000) {
        self.probe = probe
        self.entryCap = entryCap
    }

    /// 扫 `folder/Converted/` 子树。目录不存在 → `[]` 不抛错（还没转过任何东西是常态）。
    public func scan(folder: URL) async throws -> [VideoItem] {
        let fm = FileManager.default
        let converted = folder.appendingPathComponent(
            MediaLibrary.excludedDirectoryName, isDirectory: true)
        guard fm.fileExists(atPath: converted.path) else { return [] }
        guard let enumerator = fm.enumerator(
            at: converted,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var items: [VideoItem] = []
        var scanned = 0
        while let entry = enumerator.nextObject() as? URL {
            scanned += 1
            if scanned > entryCap { break }
            // 符号链接一律不收（与 `MediaLibrary` 扫描器同规则）。
            guard let values = try? entry.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  values.isRegularFile == true,
                  values.isSymbolicLink != true else { continue }
            guard MediaLibrary.allowedExtensions.contains(entry.pathExtension.lowercased()) else { continue }
            if await probe.metadata(entry).hasVideoTrack {
                items.append(VideoItem(url: entry))
            }
        }
        items.sort { $0.url.path < $1.url.path }
        return items
    }

    /// 合并纯函数：`router.start(with:)` 的入参由它产出。root 顺序保留在前，converted 按序追加在后，按 `url.path` 去重。
    public static func playbackItems(root: [VideoItem], converted: [VideoItem]) -> [VideoItem] {
        var seen = Set(root.map { $0.url.path })
        var merged = root
        for item in converted where !seen.contains(item.url.path) {
            seen.insert(item.url.path)
            merged.append(item)
        }
        return merged
    }
}
