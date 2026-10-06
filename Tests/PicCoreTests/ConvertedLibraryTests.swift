import XCTest
@testable import PicCore

/// 播放第二入口 —— `Converted/` 子树可播清单 + 合并去重（数据侧）。
@MainActor
final class ConvertedLibraryTests: XCTestCase {

    /// 文件内自带替身，不跨文件引用 MediaLibraryTests 的 FakeAssetProbe（耦合后失败时分不清是替身坏了还是被测代码坏了）。
    private struct FakeProbe: VideoAssetProbe {
        func metadata(_ url: URL) async -> VideoAssetMetadata {
            VideoAssetMetadata(hasVideoTrack: url.lastPathComponent != "broken.mp4")
        }
    }

    private var root: URL!
    private var library: ConvertedLibrary!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("p6-conv-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        library = ConvertedLibrary(probe: FakeProbe())
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        root = nil
        library = nil
        super.tearDown()
    }

    @discardableResult
    private func makeConvertedFile(_ relativePath: String) -> URL {
        let parts = relativePath.split(separator: "/").map(String.init)
        var url = root.appendingPathComponent("Converted", isDirectory: true)
        for (index, part) in parts.enumerated() {
            url = url.appendingPathComponent(part, isDirectory: index < parts.count - 1)
        }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? "placeholder".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testScanFindsPlayableItemsInConvertedSubtree() async throws {
        makeConvertedFile("a.mp4")
        makeConvertedFile("sub/b.mp4")
        let items = try await library.scan(folder: root)
        XCTAssertEqual(items.map { $0.url.lastPathComponent }, ["a.mp4", "b.mp4"],
                       "Converted/ 子树（含嵌套）的可播文件按 path 排序产出")
    }

    func testScanReturnsEmptyWhenConvertedDirectoryMissing() async throws {
        let items = try await library.scan(folder: root)
        XCTAssertEqual(items, [],
                       "Converted/ 不存在 → 空数组不抛错（还没转过任何东西是常态，SC#5 前提）")
    }

    func testTmpIntermediatesAreNeverPlayable() async throws {
        makeConvertedFile("half.mp4.tmp")
        let items = try await library.scan(folder: root)
        XCTAssertEqual(items, [],
                       ".tmp 的扩展名是 tmp，天然进不了 allowedExtensions —— 半成品不进播放目录")
    }

    func testNonWhitelistedExtensionsExcluded() async throws {
        makeConvertedFile("x.mkv")
        makeConvertedFile("y.txt")
        let items = try await library.scan(folder: root)
        XCTAssertEqual(items, [], "Converted/ 里也只收 mp4/mov/m4v（复用 MediaLibrary.allowedExtensions）")
    }

    func testProbeRejectsBrokenFile() async throws {
        makeConvertedFile("broken.mp4")
        let items = try await library.scan(folder: root)
        XCTAssertEqual(items, [], "扩展名对但解不出视频轨的文件被探针拒绝（D-08 同规则）")
    }

    func testPlaybackItemsMergeRootsFirstConvertedAppendedDeduped() {
        let r1 = VideoItem(url: URL(fileURLWithPath: "/w/root-a.mp4"))
        let r2 = VideoItem(url: URL(fileURLWithPath: "/w/root-b.mp4"))
        let r3 = VideoItem(url: URL(fileURLWithPath: "/w/root-c.mp4"))
        let c1 = VideoItem(url: URL(fileURLWithPath: "/w/root-b.mp4"))   // 与 root 重复的路径
        let c2 = VideoItem(url: URL(fileURLWithPath: "/w/Converted/out.mp4"))
        let merged = ConvertedLibrary.playbackItems(root: [r1, r2, r3], converted: [c1, c2])
        XCTAssertEqual(merged, [r1, r2, r3, c2],
                       "root 顺序保留在前、converted 去重后追加在后（按 url.path 去重）")
    }
}
