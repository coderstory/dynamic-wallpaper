import Foundation

/// 产物路径与幂等跳过（TRANS-04）—— RED 编译骨架。
public struct TranscodeOutputNaming {

    private let root: URL

    public init(root: URL) {
        self.root = root
    }

    public static let convertedDirectoryName = MediaLibrary.excludedDirectoryName

    public func convertedDirectoryURL() -> URL {
        root
    }

    public func outputURL(for source: URL) -> URL {
        source
    }

    public func temporaryURL(for source: URL) -> URL {
        source
    }

    public func skipDecision(source: URL) -> Bool {
        false
    }
}
