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

    /// 该源此刻该换成哪个派生片。两个来源，任一命中即可替换：
    ///
    /// ① **表说 vs 磁盘**：表里必须是 `.done`、且产物还在磁盘上。
    /// ② **按名兜底**：`-30fps` 后缀的产物名是确定的（见 `FpsDownscaleCommand.derivativeName`），
    ///    所以即使表丢了、被重置、或状态落后于磁盘（本机实测过一次：199 个产物全部停在
    ///    `needsConvert`），关系照样能认回来。缺了 ② 的表现是：降帧产物被当成新素材追加一遍，
    ///    同一段素材播两次，壁纸播出去的还是未降帧的原片，降帧白做。
    ///
    /// 两条路都要求产物**真的读得到** —— 只出现在清单里但文件没了 = 已被删，必须回落原片。
    private static func liveDerivative(for source: URL, in converted: [VideoItem],
                                       table: FrameRateTable) -> VideoItem? {
        if let entry = table.entry(for: source),
           entry.state.recovered == .done,
           entry.hasLiveDerivative(),
           let path = entry.derivativePath,
           let listed = converted.first(where: { $0.url.path == path }),
           fileExists(listed.url) {
            return listed
        }
        return derivativeByName(for: source, in: converted)
    }

    /// 按命名认回关系：`<Converted>/<stem>-30fps.mp4`。名字从 `FpsDownscaleCommand` 取，
    /// 不在这里拼 —— 拼一份就会和真正写盘的那一份漂移。
    private static func derivativeByName(for source: URL, in converted: [VideoItem]) -> VideoItem? {
        let expected = FpsDownscaleCommand.derivativeName(for: source)
        return converted.first {
            $0.url.lastPathComponent == expected && fileExists($0.url)
        }
    }

    private static func fileExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
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