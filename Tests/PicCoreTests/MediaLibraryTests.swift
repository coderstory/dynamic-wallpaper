import Foundation
import XCTest
@testable import PicCore

/// `MediaFixtureTree` 之上的 9 条行为用例。
///
/// 两条纪律：本测试类**自带** `FakeAssetProbe`（不跨文件引用别的测试类）；
/// 测试不依赖 `fixtures/` 已生成 —— 自己造树，干净 clone 也绿。
@MainActor
final class MediaLibraryTests: XCTestCase {

    /// 假探针：按文件名决定接受与否。让单测完全不碰 AVFoundation 与真实素材。
    private struct FakeAssetProbe: VideoAssetProbe {
        func metadata(_ url: URL) async -> VideoAssetMetadata {
            VideoAssetMetadata(hasVideoTrack: url.lastPathComponent != "broken.mp4")
        }
    }

    private var tree: MediaFixtureTree.Tree!

    override func setUp() async throws {
        try await super.setUp()
        tree = try MediaFixtureTree.makeTree()
    }

    override func tearDown() async throws {
        MediaFixtureTree.remove(tree)
        tree = nil
        try await super.tearDown()
    }

    private func scanTree(entryCap: Int = 5000) async throws -> MediaLibraryReport {
        let library = MediaLibrary(probe: FakeAssetProbe(), entryCap: entryCap)
        return try await library.scan(folder: tree.rootURL)
    }

    private func lastPathNames(_ report: MediaLibraryReport) -> Set<String> {
        Set(report.items.map { $0.url.lastPathComponent })
    }

    // MARK: - 9 条行为用例

    func testRecursionFindsClipThreeDirectoriesDeep() async throws {
        let report = try await scanTree()
        // 专门用例：三层嵌套必须被发现，不是靠顶层用例顺带覆盖。
        XCTAssertTrue(report.items.contains { $0.url.path.hasSuffix("sub/deep/deeper/d.MP4") },
                      "三次目录深度下的 d.MP4 必须在 items 里")
        XCTAssertEqual(report.items.count, 6,
                       "fixture 树可收条目：a.mp4 / B.MOV / c.m4v / d.MP4 / keep.mp4 / 视频壁纸-e.mp4")
        XCTAssertGreaterThanOrEqual(report.scannedEntryCount, 12,
                                    "递归遍历应扫到全部条目，而不是只扫顶层")
    }

    func testRecursionAlsoFindsClipUnderDirectoryWithCjkAndSpaceName() async throws {
        let report = try await scanTree()
        XCTAssertTrue(report.items.contains { $0.url.path.contains("视频壁纸") },
                      "中文+空格目录名下的 e.mp4 必须被收")
        // 把理由钉死：URL 的字符串形态确实会被百分号编码，
        // 所以存在性检查只能用 path。
        let cjkPathURL = URL(fileURLWithPath: tree.cjkDirectoryURL.path)
        XCTAssertTrue(VideoItem(url: cjkPathURL).url.absoluteString.contains("%"),
                      "absoluteString 形态含中文时应含百分号编码")
    }

    func testWhitelistAcceptsOnlyMp4MovM4vCaseInsensitively() async throws {
        let report = try await scanTree()
        let names = lastPathNames(report)
        XCTAssertEqual(names, Set(["a.mp4", "B.MOV", "c.m4v", "d.MP4", "keep.mp4", "e.mp4"]),
                       "四个大小写变体全部应被收")
        for banned in ["notes.txt", "skip.mkv", "y.avi", "z.webm"] {
            XCTAssertFalse(names.contains(banned), "\(banned) 应被扩展名过滤掉（SOURCE-03）")
        }
    }

    func testFileWithAllowedExtensionButNoVideoTrackIsRejected() async throws {
        let report = try await scanTree()
        XCTAssertFalse(lastPathNames(report).contains("broken.mp4"),
                       "扩展名对但解不出视频轨的文件应被排除（D-08）")
        XCTAssertEqual(report.rejectedByProbe, 1)
    }

    func testConvertedDirectorySubtreeIsExcludedByExactDirectoryName() async throws {
        let report = try await scanTree()
        let names = lastPathNames(report)
        XCTAssertFalse(names.contains("out.mp4"), "Converted/ 下的 out.mp4 应被整棵排除")
        // 后半句是这条判据有牙齿的原因：只判前半句的话，一个「路径里出现 converted
        // 就排除」的错误实现照样绿。
        XCTAssertTrue(names.contains("keep.mp4"),
                      "converted-lower/ 只是子串相似，keep.mp4 必须仍被收")
    }

    func testSymlinkPointingOutsideRootIsExcluded() async throws {
        let report = try await scanTree()
        XCTAssertFalse(lastPathNames(report).contains("link-out.mp4"),
                       "指向根外的符号链接不应进入 items（T-04-01）")
        XCTAssertFalse(report.items.contains { $0.url.path.contains("pic-outside") },
                       "任何条目都不应解析到根外目录")
    }

    func testSecondScanUsesCacheAndInvalidateForcesRescan() async throws {
        let library = MediaLibrary(probe: FakeAssetProbe())
        let first = try await library.scan(folder: tree.rootURL)
        let second = try await library.scan(folder: tree.rootURL, useCache: true)
        XCTAssertEqual(library.scanCount, 1, "缓存命中不应触发第二次遍历")
        library.invalidateCache()
        let third = try await library.scan(folder: tree.rootURL, useCache: true)
        XCTAssertEqual(library.scanCount, 2, "invalidateCache() 后才应触发第二次遍历")
        XCTAssertEqual(first.playableCount, second.playableCount)
        XCTAssertEqual(second.playableCount, third.playableCount)
    }

    func testMissingFolderAndNonDirectoryRootThrowDistinctErrors() async throws {
        let library = MediaLibrary(probe: FakeAssetProbe())

        let missing = tree.rootURL.appendingPathComponent("does-not-exist-\(UUID().uuidString)")
        do {
            _ = try await library.scan(folder: missing)
            XCTFail("不存在的路径应抛 .folderMissing")
        } catch let err as MediaLibrary.MediaLibraryError {
            XCTAssertEqual(err, .folderMissing)
        } catch {
            XCTFail("预期 .folderMissing，实际 \(error)")
        }

        let fileURL = tree.rootURL.appendingPathComponent("a.mp4")
        do {
            _ = try await library.scan(folder: fileURL)
            XCTFail("确实是文件而不是目录的路径应抛 .folderUnreadable")
        } catch let err as MediaLibrary.MediaLibraryError {
            XCTAssertEqual(err, .folderUnreadable)
        } catch {
            XCTFail("预期 .folderUnreadable，实际 \(error)")
        }
    }

    func testEntryCapTruncatesAndReportsSkippedByEntryCap() async throws {
        let report = try await scanTree(entryCap: 3)
        XCTAssertTrue(report.skippedByEntryCap, "超过上限必须如实上报，不静默少给")
        XCTAssertLessThanOrEqual(report.items.count, 3, "超出上限后应被截断")
    }
}