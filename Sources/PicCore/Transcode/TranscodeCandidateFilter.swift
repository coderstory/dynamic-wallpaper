import Foundation

/// 转码候选发现（TRANS-05 第一闸门）—— RED 编译骨架。
public enum TranscodeCandidateFilter {

    public static let candidateExtensions: Set<String> = []

    public static func candidates(in root: URL) -> [URL] {
        []
    }

    public static func isCandidate(_ url: URL) -> Bool {
        false
    }
}
