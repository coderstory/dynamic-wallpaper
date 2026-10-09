import Foundation
import XCTest
@testable import PicCore

/// 自带 `FakeSizeProbe` 与自己造的临时目录树：不碰真实图片、不依赖 `fixtures/`，干净 clone 上 `swift test` 也绿。
@MainActor
final class ImageLibraryTests: XCTestCase {

    /// 假探针：尺寸编在文件名里（`2560x1440.jpg`）；名字含 `broken` 则返回 nil，模拟解码失败。
    private struct FakeSizeProbe: ImageSizeProbe {
        func pixelSize(_ url: URL) async -> (width: Int, height: Int)? {
            let name = url.deletingPathExtension().lastPathComponent
            guard !name.contains("broken") else { return nil }
            let parts = name.split(separator: "x").compactMap { Int($0) }
            guard parts.count == 2 else { return nil }
            return (parts[0], parts[1])
        }
    }

    private var root: URL!

    override func setUp() async throws {
        try await super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pic-images-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
        root = nil
        try await super.tearDown()
    }

    private func touch(_ relativePath: String) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data("placeholder".utf8).write(to: url)
    }

    private func scan(_ minPixels: Int, useCache: Bool = true) async throws -> ImageLibraryReport {
        try await ImageLibrary(probe: FakeSizeProbe()).scan(folder: root, minPixels: minPixels, useCache: useCache)
    }

    private func names(_ report: ImageLibraryReport) -> Set<String> {
        Set(report.items.map { $0.url.lastPathComponent })
    }

    func testExtensionWhitelistAcceptsFourFormatsAndRejectsGif() async throws {
        // 大写扩展名只放一个：macOS 默认卷大小写不敏感，同名不同大小写的两个文件会互相覆盖，
        // 夹具会静默少一个文件（不是产品行为）。
        try touch("4000x3000.jpg")
        try touch("4000x3001.JPEG")     // 扩展名匹配必须大小写不敏感
        try touch("4000x3000.png")
        try touch("4000x3000.heic")
        try touch("4000x3000.webp")
        try touch("4000x3000.gif")      // 动图不收：会把图片模式混回视频语义
        try touch("notes.txt")

        let report = try await scan(ImageResolutionTier.p1080.pixels)
        XCTAssertEqual(report.acceptedByExtension, 5)
        XCTAssertEqual(report.extensionRejected, 2)
        XCTAssertEqual(names(report).count, 5)
        XCTAssertFalse(names(report).contains("4000x3000.gif"))
    }

    /// 判定口径是总像素量：`2560×1440 == 2K` 恰好过线，`1920×1080` 差一档就不过。
    func testTotalPixelsIsTheThresholdNotEitherEdge() async throws {
        try touch("2560x1440.png")      // 3,686,400 —— 正好等于 2K
        try touch("1920x1080.png")      // 2,073,600 —— 1080P，2K 档下不过
        try touch("1000x1000.png")      // 1,000,000
        try touch("4000x1200.png")      // 4,800,000 —— 全景：过 2K 但只有 1200 高（口径的已知代价）

        let report = try await scan(ImageResolutionTier.k2.pixels)
        XCTAssertEqual(report.total, 4)
        XCTAssertEqual(report.passing, 2, "正好等于阈值的必须算过")
        XCTAssertEqual(report.filteredOut, 2)
        XCTAssertTrue(names(report).contains("2560x1440.png"))
        XCTAssertTrue(names(report).contains("4000x1200.png"))
    }

    /// 解码失败必须单独计数：混进「低于档位」会让用户以为自己的图太小，实际是文件打不开。
    func testUndecodableIsCountedApartFromFilteredOut() async throws {
        try touch("broken-a.png")
        try touch("1000x1000.png")      // 1,000,000 —— 4K 档下不过

        let report = try await scan(ImageResolutionTier.k4.pixels)
        XCTAssertEqual(report.undecodable, 1)
        XCTAssertEqual(report.total, 1, "打不开的文件不该计入总数")
        XCTAssertEqual(report.filteredOut, 1, "被忽略的那一张只可能是 1000×1000，不是损坏的那张")
    }

    /// 三格统计必须自洽：total = passing + filteredOut，且 passing 恒等于 items.count。
    func testThreeCountsAreSelfConsistent() async throws {
        try touch("3840x2160.png")
        try touch("1920x1080.png")
        try touch("broken.png")

        let report = try await scan(ImageResolutionTier.k4.pixels)
        XCTAssertEqual(report.total, report.passing + report.filteredOut)
        XCTAssertEqual(report.passing, report.items.count)
        XCTAssertEqual(report.total, 2)
        XCTAssertEqual(report.passing, 1)
    }

    /// **缓存必须把档位纳入判等**：只按目录缓存的话，用户把 4K 降到 1080P 会拿回上一轮的 report，
    /// 「将参与轮播」永远是 0 —— 看起来像降档位没生效。
    func testChangingTierRescansInsteadOfReturningStaleCache() async throws {
        try touch("1920x1080.png")

        let library = ImageLibrary(probe: FakeSizeProbe())
        let strict = try await library.scan(folder: root, minPixels: ImageResolutionTier.k4.pixels)
        XCTAssertEqual(strict.passing, 0)

        let loose = try await library.scan(folder: root, minPixels: ImageResolutionTier.p1080.pixels)
        XCTAssertEqual(loose.passing, 1, "同一个目录换档位必须重扫，不能吃旧缓存")
        XCTAssertEqual(library.scanCount, 2)
    }

    func testSameFolderAndTierUsesCache() async throws {
        try touch("1920x1080.png")

        let library = ImageLibrary(probe: FakeSizeProbe())
        _ = try await library.scan(folder: root, minPixels: ImageResolutionTier.p1080.pixels)
        _ = try await library.scan(folder: root, minPixels: ImageResolutionTier.p1080.pixels)
        XCTAssertEqual(library.scanCount, 1, "同目录同档位的第二次扫描必须命中缓存")

        library.invalidateCache()
        _ = try await library.scan(folder: root, minPixels: ImageResolutionTier.p1080.pixels)
        XCTAssertEqual(library.scanCount, 2, "失效缓存后必须真的重扫")
    }

    func testMissingFolderThrowsFolderMissing() async throws {
        let missing = root.appendingPathComponent("nope", isDirectory: true)
        do {
            _ = try await ImageLibrary(probe: FakeSizeProbe()).scan(folder: missing, minPixels: 0)
            XCTFail("目录不存在必须抛错")
        } catch let error as MediaLibrary.MediaLibraryError {
            XCTAssertEqual(error, .folderMissing)
        }
    }

    func testRootThatIsAFileThrowsFolderUnreadable() async throws {
        try touch("3840x2160.png")
        let file = root.appendingPathComponent("3840x2160.png")
        do {
            _ = try await ImageLibrary(probe: FakeSizeProbe()).scan(folder: file, minPixels: 0)
            XCTFail("传文件路径必须被挡住")
        } catch let error as MediaLibrary.MediaLibraryError {
            XCTAssertEqual(error, .folderUnreadable)
        }
    }

    func testRecursionFindsImagesInSubdirectories() async throws {
        try touch("sub/deep/3840x2160.png")
        let report = try await scan(ImageResolutionTier.k4.pixels)
        XCTAssertTrue(report.items.contains { $0.url.path.hasSuffix("sub/deep/3840x2160.png") })
    }
}
