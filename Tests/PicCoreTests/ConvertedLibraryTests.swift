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

    /// 场景 F12：app 在转码途中退出 / 崩了，`.tmp` 会一直躺在 `Converted/`。
    /// 它进不了播放池（扩展名不在白名单），但也不会自己消失 —— 扫描时顺手清掉。
    func testStaleTmpIsCleanedUpOnScan() async throws {
        let leftover = makeConvertedFile("half.mp4.tmp")
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-7200)], ofItemAtPath: leftover.path)

        _ = try await library.scan(folder: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: leftover.path),
                       "陈旧的 .tmp 必须清掉 —— 上次崩溃留下的半成品不会自己消失")
    }

    /// 反例：正在写的 .tmp **不能**被清。用户在转码途中点了「重新扫描」，
    /// 清掉它就是把进行中的转码打断。判据是 mtime 新鲜度。
    func testFreshTmpSurvivesScan() async throws {
        let inFlight = makeConvertedFile("inflight.mp4.tmp")
        _ = try await library.scan(folder: root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: inFlight.path),
                      "刚写的 .tmp = 有转码在跑，清了会打断它")
    }

    /// 只清顶层 —— 递归会碰上用户自己放在 Converted/ 子目录里的东西。
    func testNestedTmpIsLeftAlone() async throws {
        let nested = makeConvertedFile("sub/deep.mp4.tmp")
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-7200)], ofItemAtPath: nested.path)

        _ = try await library.scan(folder: root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: nested.path),
                      "只清顶层：两个队列的 tmp 都直接写在 Converted/ 下，子目录里的不碰")
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
