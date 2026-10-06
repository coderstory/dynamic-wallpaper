import Foundation
import XCTest
@testable import PicCore

/// 本测试类自带 `FakeAssetProbe`，不跨文件引用别的测试类的替身（耦合后失败时分不清是替身坏了还是被测代码坏了）；树也是自己造的，不依赖 `fixtures/` 已生成，干净 clone 上照样绿。
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

    func testRecursionFindsClipThreeDirectoriesDeep() async throws {
        let report = try await scanTree()
        // 三层嵌套必须被发现，不是靠顶层用例顺带覆盖。
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
        // URL 的字符串形态确实会被百分号编码，所以存在性检查只能用 path。
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
        // 后半句才有牙齿：只判前半句的话，「路径里出现 converted 就排除」的错误实现照样绿。
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

    func testSwitchingFolderBypassesCacheByRootKey() async throws {
        // 换目录必须重扫，不能拿旧目录的缓存顶数 —— 设置窗「选择…」走的就是这条路径。
        let library = MediaLibrary(probe: FakeAssetProbe())
        let first = try await library.scan(folder: tree.rootURL)
        XCTAssertEqual(library.scanCount, 1)
        let other = tree.cjkDirectoryURL
        let second = try await library.scan(folder: other)
        XCTAssertEqual(library.scanCount, 2, "换目录必须重新遍历，而不是命中旧缓存")
        XCTAssertEqual(second.rootPath, other.standardizedFileURL.path,
                       "report 必须来自新目录")
        XCTAssertEqual(second.playableCount, 1, "新目录的清单应与旧目录不同")
        _ = first
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

    // MARK: - 探测并发度

    /// 记录同时「在飞」探测数的假探针。`@unchecked Sendable`：真并发下被多个任务同时调用，计数用锁护住。
    private final class ConcurrencyProbe: @unchecked Sendable, VideoAssetProbe {
        private let lock = NSLock()
        private var inFlight = 0
        private var peakInFlight = 0
        private var callCount = 0

        var peak: Int { lock.withLock { peakInFlight } }
        var calls: Int { lock.withLock { callCount } }

        func metadata(_ url: URL) async -> VideoAssetMetadata {
            lock.withLock {
                inFlight += 1
                callCount += 1
                peakInFlight = max(peakInFlight, inFlight)
            }
            // 必须真的挂起：不挂起的话每个任务瞬间跑完，并发度永远是 1，这条判据就成了空断言。
            try? await Task.sleep(for: .milliseconds(20))
            lock.withLock { inFlight -= 1 }
            return VideoAssetMetadata(hasVideoTrack: true)
        }
    }

    /// 探测是**有界并发**。上限刻意是常数而不是「有多少发多少」：探测受磁盘 IO 限制、本机只有一块盘，
    /// 放开并发只会把 IO/CPU 打满而不更快。这条同时锁住「并发没把结果算错」。
    func testProbeRunsConcurrentlyButBounded() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pic-probe-bound-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for index in 0..<16 {
            FileManager.default.createFile(
                atPath: dir.appendingPathComponent("clip-\(index).mp4").path,
                contents: Data("x".utf8))
        }

        let probe = ConcurrencyProbe()
        let report = try await MediaLibrary(probe: probe).scan(folder: dir)

        XCTAssertEqual(report.playableCount, 16, "并发只该改变耗时，不该改变结果")
        XCTAssertEqual(probe.calls, 16, "每个候选恰好探测一次")
        XCTAssertGreaterThan(probe.peak, 1, "串行的话首屏延迟对视频数是线性的，这条就是那个回归锁")
        XCTAssertLessThanOrEqual(probe.peak, 4, "并发度超过上限 = 把 IO/CPU 打满（与 probeConcurrency 一致）")
    }
}