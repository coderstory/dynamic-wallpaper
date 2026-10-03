import Foundation

/// 转码候选发现（TRANS-05 第一闸门）—— 只看扩展名与目录规则。
///
/// 零探针（扩展名对但内容坏的 mkv，转码时 ffmpeg 会报错、队列标 failed，
/// 那是 06-03 的失败路径）、零缓存（候选列表只在开窗/刷新时扫一次，量小）。
public enum TranscodeCandidateFilter {

    /// 非原生格式白名单（小写、无点、比较时大小写不敏感）。
    public static let candidateExtensions: Set<String> = ["mkv", "avi", "webm"]

    /// 递归收集 root 下的转码候选。root 不存在/不可读 → `[]` 不抛
    /// （候选发现是尽力而为；真正报错的是播放扫描器 04-01 的职责）。
    public static func candidates(in root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var result: [URL] = []
        for case let entry as URL in enumerator {
            // 符号链接一律不收（T-06-03，与 04-01 扫描器同规则）。
            guard let values = try? entry.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  values.isRegularFile == true,
                  values.isSymbolicLink != true else { continue }
            guard candidateExtensions.contains(entry.pathExtension.lowercased()) else { continue }
            if isInsideConverted(entry) { continue }
            result.append(entry)
        }
        result.sort { $0.path < $1.path }
        return result
    }

    /// 单文件判定（扩展名 + 不在 Converted 内），供队列防御性复核。
    /// `.tmp` 天然不中：扩展名 tmp 不在白名单。
    public static func isCandidate(_ url: URL) -> Bool {
        guard candidateExtensions.contains(url.pathExtension.lowercased()) else { return false }
        return !isInsideConverted(url)
    }

    /// 目录名**大小写不敏感精确匹配** Converted（与 04-01 `MediaLibrary` 同规则），
    /// 不是子串匹配 —— `converted-lower` 不命中。
    private static func isInsideConverted(_ url: URL) -> Bool {
        url.pathComponents.contains {
            $0.caseInsensitiveCompare(MediaLibrary.excludedDirectoryName) == .orderedSame
        }
    }
}
