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

    /// 超过这个时长的 `.tmp` 视为上次运行留下的半成品（app 在转码途中退出 / 崩了）。
    /// 必须是**陈旧**的才清：正在写的那个 mtime 一直在更新，清了会把进行中的转码打断。
    private static let staleTemporaryAge: TimeInterval = 3600

    /// 扫 `folder/Converted/` 子树。目录不存在 → `[]` 不抛错（还没转过任何东西是常态）。
    public func scan(folder: URL) async throws -> [VideoItem] {
        let fm = FileManager.default
        let converted = folder.appendingPathComponent(
            MediaLibrary.excludedDirectoryName, isDirectory: true)
        guard fm.fileExists(atPath: converted.path) else { return [] }
        // 清掉上次运行留下的半成品。`.tmp` 扩展名进不了任何白名单，不会污染播放池，
        // 但不清就一直躺在磁盘上（场景 F12）。
        Self.removeStaleTemporaryFiles(in: converted)
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

    /// 清掉陈旧的 `.tmp` 半成品。只碰顶层（两个队列的 tmp 都直接写在 `Converted/` 下），
    /// 不递归 —— 递归会碰上用户自己放的东西。删除失败一律忽略：清理是卫生措施，不是主流程。
    private static func removeStaleTemporaryFiles(in converted: URL) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: converted.path) else { return }
        let cutoff = Date().addingTimeInterval(-staleTemporaryAge)
        for name in names where (name as NSString).pathExtension == "tmp" {
            let path = converted.appendingPathComponent(name).path
            guard let mtime = (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date,
                  mtime < cutoff else { continue }
            try? fm.removeItem(atPath: path)
        }
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
