import Foundation

/// 播放池构建 —— 根目录清单与 `Converted/` 产物的合并规则。转码产物追加在后；
/// 降帧产物一对一顶替原片 —— `clip.mp4` 与 `Converted/clip-30fps.mp4` 路径不同，
/// 按 `url.path` 去重不生效，追加就是同一段素材播两遍。
public enum PlaybackPool {

    public static func build(root: [VideoItem], converted: [VideoItem],
                             table: FrameRateTable) -> [VideoItem] {
        let replacements = Dictionary(uniqueKeysWithValues: root.compactMap { item in
            liveDerivative(for: item.url, in: converted, table: table)
                .map { (item.url.path, $0) }
        })

        // 替换发生在原位 —— 追加会让壁纸轮换顺序整体错乱。
        var pool = root.map { replacements[$0.url.path] ?? $0 }
        var seen = Set(pool.map(\.url.path))

        for item in converted where !seen.contains(item.url.path) {
            if isOrphanDerivative(item, root: root, table: table) { continue }
            seen.insert(item.url.path)
            pool.append(item)
        }
        return pool
    }

    /// 该源此刻该换成哪个派生片。三个条件缺一不可：表说完成了、产物还在磁盘上、且产物真的在这次扫描结果里（表说有但扫不到 = 已被删，必须回落原片）。
    private static func liveDerivative(for source: URL, in converted: [VideoItem],
                                       table: FrameRateTable) -> VideoItem? {
        guard let entry = table.entry(for: source),
              entry.state.recovered == .done,
              entry.hasLiveDerivative(),
              let path = entry.derivativePath
        else { return nil }
        return converted.first { $0.url.path == path }
    }

    /// 降帧产物的源已被删 → 它是孤儿，留在池里等于凭空多一段素材。
/// 判据走表（唯一真相），不从文件名反推 —— 反推要拼字符串，且认不出「源没了但产物还在」和「这本来就是转码产物」的区别。
    private static func isOrphanDerivative(_ item: VideoItem, root: [VideoItem],
                                           table: FrameRateTable) -> Bool {
        let liveRootPaths = Set(root.map(\.url.path))
        return table.entries.contains { entry in
            entry.derivativePath == item.url.path && !liveRootPaths.contains(entry.sourcePath)
        }
    }
}