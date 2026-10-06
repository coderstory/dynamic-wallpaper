import Foundation

/// 转码候选发现（TRANS-05 第一闸门）—— 只看扩展名与目录规则。
/// 零探针（扩展名对但内容坏的 mkv，转码时 ffmpeg 会报错、队列标 failed，那是失败路径）、零缓存（候选列表只在开窗/刷新时扫一次，量小）。
public enum TranscodeCandidateFilter {

    /// 非原生格式白名单（小写、无点、比较时大小写不敏感）。
    public static let candidateExtensions: Set<String> = ["mkv", "avi", "webm"]

    /// 递归收集 root 下的转码候选。root 不存在/不可读 → `[]` 不抛（候选发现是尽力而为；真正报错的是播放扫描器的职责）。
    public static func candidates(in root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var result: [URL] = []
        for case let entry as URL in enumerator {
            // 符号链接一律不收（与 `MediaLibrary` 扫描器同规则）。
            guard let values = try? entry.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  values.isRegularFile == true,
                  values.isSymbolicLink != true else { continue }
            guard candidateExtensions.contains(entry.pathExtension.lowercased()) else { continue }
            if MediaLibrary.isInsideConverted(entry) { continue }
            result.append(entry)
        }
        result.sort { $0.path < $1.path }
        return result
    }

    /// 从未进过队列的候选 ——「补新文件」语义。转码页每次 `onAppear` 都会扫一遍，
    /// 若不过滤，已终态（succeeded / skipped）的源会被重新入队并显示成失败行。
    /// 过滤按 source path，不碰产物路径（那是 `TranscodeQueue.enqueue` 的活）。
    /// 两边都走 standardized 路径：enumerator 可能给 /private/var/...，调用方给 /var/...。
    public static func unseenCandidates(in root: URL, excluding knownSources: Set<String>) -> [URL] {
        let known = Set(knownSources.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
        return candidates(in: root).filter { !known.contains($0.standardizedFileURL.path) }
    }
}
