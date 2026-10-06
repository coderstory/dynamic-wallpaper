import XCTest
@testable import PicCore

/// 端到端验收：真实片库 + 真实帧率表 → 播放池必须选派生片而非原片。产物做对了但池仍选原片，降帧等于白跑。
@MainActor
final class RealLibraryPlaybackPoolTests: XCTestCase {

    private var root: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Documents/Videos", isDirectory: true)
    }
    private var tableURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/Pic/frame-rate-table.json")
    }

    func testRealLibraryPlaybackPoolPrefersDerivatives() async throws {
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: tableURL.path),
            "真实帧率表不存在（还没跑过降帧）")

        let table = FrameRateTable.load(from: tableURL)
        let done = table.entries.filter { $0.state == .done && $0.hasLiveDerivative() }
        try XCTSkipIf(done.isEmpty, "表里没有已完成的条目")

        // 真实扫描 Converted/；探测恒真 —— 这里只验路径选择，不验解码。
        struct AcceptAll: VideoAssetProbe {
            func metadata(_ url: URL) async -> VideoAssetMetadata {
                VideoAssetMetadata(hasVideoTrack: true)
            }
        }
        let scan = ConvertedLibrary(probe: AcceptAll())
        let convertedItems = try await scan.scan(folder: root)

        // 只取有派生片的源，真实扫描 491 个太慢。
        let sources = done.prefix(20).map { VideoItem(url: URL(fileURLWithPath: $0.sourcePath)) }
        let pool = PlaybackPool.build(root: sources, converted: convertedItems, table: table)

        XCTAssertEqual(pool.count, sources.count, "池大小必须等于根目录条目数")

        let derivativeSet = Set(done.compactMap { $0.derivativePath })
        let usingDerivative = pool.filter { derivativeSet.contains($0.url.path) }
        XCTAssertEqual(usingDerivative.count, pool.count,
                       "池里每一条都必须是派生片而非原片 —— 否则降帧白做了")

        // 池里每条要么是派生片，要么其源没有活的派生片
        for item in pool {
            let source = done.first { $0.sourcePath == item.url.path }
            if source?.derivativePath == item.url.path { continue }
            let isDerivativeOfSomething = done.contains { $0.derivativePath == item.url.path }
            XCTAssertTrue(isDerivativeOfSomething,
                          "池里出现了既非原片也非其派生片的路径：\(item.url.lastPathComponent)")
        }
    }

    /// 派生片被删 → 必须回落原片，不能拿失效路径去装载。
    /// 这条会把用户的真实文件移走再移回，那个 `defer` 是唯一的还原路径，不要删。
    func testDeletingDerivativeFallsBackToSource() async throws {
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: tableURL.path),
            "真实帧率表不存在")

        let table = FrameRateTable.load(from: tableURL)
        let done = table.entries.filter { $0.state == .done }
        guard let victim = done.first(where: { $0.hasLiveDerivative() }) else {
            throw XCTSkip("没有活的派生片可测")
        }
        let derivativeURL = URL(fileURLWithPath: victim.derivativePath!)
        try FileManager.default.moveItem(at: derivativeURL,
                                        to: derivativeURL.appendingPathExtension("bak"))

        defer {
            try? FileManager.default.moveItem(
                at: derivativeURL.appendingPathExtension("bak"), to: derivativeURL)
        }

        let source = VideoItem(url: URL(fileURLWithPath: victim.sourcePath))
        struct AcceptAll: VideoAssetProbe {
            func metadata(_ url: URL) async -> VideoAssetMetadata {
                VideoAssetMetadata(hasVideoTrack: true)
            }
        }
        let convertedItems = try await ConvertedLibrary(probe: AcceptAll()).scan(folder: root)
        let pool = PlaybackPool.build(root: [source], converted: convertedItems, table: table)
        XCTAssertEqual(pool.first?.url.path, victim.sourcePath,
                       "派生片被删 → 回落原片")
    }
}