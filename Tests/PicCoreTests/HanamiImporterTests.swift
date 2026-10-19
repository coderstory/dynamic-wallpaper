import CryptoKit
import XCTest
@testable import PicCore

final class HanamiImporterTests: XCTestCase {

    private var root: URL!
    private var source: URL!
    private var dest: URL!
    private var trash: URL!
    private var dbURL: URL!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pic-importer-\(UUID().uuidString)", isDirectory: true)
        source = root.appendingPathComponent("source", isDirectory: true)
        dest = root.appendingPathComponent("dest", isDirectory: true)
        trash = root.appendingPathComponent("trash", isDirectory: true)
        dbURL = root.appendingPathComponent("deleted-videos.sqlite")
        try? FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        root = nil
        source = nil
        dest = nil
        trash = nil
        dbURL = nil
        super.tearDown()
    }

    private struct FakeAssetProbe: VideoAssetProbe {
        var hasVideoTrack = true
        func metadata(_ url: URL) async -> VideoAssetMetadata {
            VideoAssetMetadata(hasVideoTrack: hasVideoTrack)
        }
    }

    @discardableResult
    private func makeFile(_ name: String, bytes: Data, in dir: URL) -> URL {
        let url = dir.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: bytes)
        return url
    }

    private func makeImporter(trash: URL?, probe: any VideoAssetProbe = FakeAssetProbe()) -> HanamiImporter {
        HanamiImporter(
            destinationDirectory: dest,
            sourceDirectory: source,
            trashDirectory: trash,
            probe: probe,
            ledger: HanamiVideoLedger(databaseURL: dbURL))
    }

    private func bytes(at url: URL) -> Data {
        (try? Data(contentsOf: url)) ?? Data()
    }

    private func entries(in dir: URL) -> Int {
        (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?.count ?? -1
    }

    private func hex(_ digest: Insecure.MD5.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    func testHappyPathImportsAndLeavesNoTmpResidue() async throws {
        let data = Data("video-bytes".utf8)
        makeFile("a.mp4", bytes: data, in: source)
        let report = await makeImporter(trash: trash).run()
        XCTAssertEqual(report.imported, 1)
        XCTAssertEqual(report.failedCopy, 0)
        XCTAssertEqual(bytes(at: dest.appendingPathComponent("a.mp4")), data)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.appendingPathComponent("a.mp4.tmp").path))
    }

    func testTombstonedSourceIsSkipped() async throws {
        let url = makeFile("gone.mp4", bytes: Data("deleted-video".utf8), in: source)
        let hash = try XCTUnwrap(HanamiImporter.md5(at: url))
        try HanamiVideoLedger(databaseURL: dbURL).insert(hash)
        let report = await makeImporter(trash: trash).run()
        XCTAssertEqual(report.skippedTombstone, 1)
        XCTAssertEqual(report.imported, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.appendingPathComponent("gone.mp4").path))
    }

    func testExistingSameNameIsSkipped() async throws {
        makeFile("a.mp4", bytes: Data("new-version".utf8), in: source)
        let userBytes = Data("user-file".utf8)
        makeFile("a.mp4", bytes: userBytes, in: dest)
        let report = await makeImporter(trash: trash).run()
        XCTAssertEqual(report.skippedExisting, 1)
        XCTAssertEqual(bytes(at: dest.appendingPathComponent("a.mp4")), userBytes, "同名用户文件不许被覆盖")
    }

    func testSameBytesInOneRoundAreImportedOnce() async throws {
        let data = Data("same-bytes".utf8)
        makeFile("one.mp4", bytes: data, in: source)
        makeFile("two.mp4", bytes: data, in: source)
        let report = await makeImporter(trash: trash).run()
        XCTAssertEqual(report.imported, 1)
        XCTAssertEqual(report.skippedDuplicate, 1)
    }

    func testProbeRejectionLeavesNoResidue() async throws {
        makeFile("broken.mp4", bytes: Data("junk".utf8), in: source)
        let report = await makeImporter(trash: trash, probe: FakeAssetProbe(hasVideoTrack: false)).run()
        XCTAssertEqual(report.rejectedByProbe, 1)
        XCTAssertEqual(report.imported, 0)
        XCTAssertEqual(entries(in: dest), 0, "dest 无成品也无 tmp 残留")
    }

    func testTrashSeedingFeedsTombstoneMatch() async throws {
        let data = Data("trashed-video".utf8)
        makeFile("t.mp4", bytes: data, in: trash)
        makeFile("t.mp4", bytes: data, in: source)
        let report = await makeImporter(trash: trash).run()
        XCTAssertEqual(report.tombstoneSeededFromTrash, 1)
        XCTAssertEqual(report.skippedTombstone, 1, "seed 先于 match：同字节候选被墓碑拦下")
        XCTAssertEqual(report.imported, 0)
    }

    func testTrashSeedingIsIdempotentAndNilOrMissingTrashIsTolerated() async throws {
        makeFile("s.mp4", bytes: Data("seed-me".utf8), in: trash)
        let first = await makeImporter(trash: trash).run()
        XCTAssertEqual(first.tombstoneSeededFromTrash, 1)
        let second = await makeImporter(trash: trash).run()
        XCTAssertEqual(second.tombstoneSeededFromTrash, 0, "回填幂等：第二轮零新增")

        makeFile("a.mp4", bytes: Data("one".utf8), in: source)
        let nilTrashRun = await makeImporter(trash: nil).run()
        XCTAssertEqual(nilTrashRun.imported, 1, "trashDirectory nil → 导入照常")

        makeFile("b.mp4", bytes: Data("two".utf8), in: source)
        let missingTrashRun = await makeImporter(trash: root.appendingPathComponent("no-such-trash")).run()
        XCTAssertEqual(missingTrashRun.imported, 1, "trash 目录不存在 → 导入照常")
    }

    func testMissingSourceDirectoryReportsSourceMissing() async throws {
        let importer = HanamiImporter(
            destinationDirectory: dest,
            sourceDirectory: source.appendingPathComponent("nope", isDirectory: true),
            trashDirectory: trash,
            probe: FakeAssetProbe(),
            ledger: HanamiVideoLedger(databaseURL: dbURL))
        let report = await importer.run()
        XCTAssertTrue(report.sourceMissing)
        XCTAssertEqual(report.tombstoneSeededFromTrash, 0)
        XCTAssertEqual(report.imported, 0)
        XCTAssertEqual(report.failedCopy, 0)
    }

    func testNonMp4AndNonRegularEntriesAreIgnored() async throws {
        makeFile("note.txt", bytes: Data("txt".utf8), in: source)
        makeFile("noext", bytes: Data("x".utf8), in: source)
        try FileManager.default.createDirectory(
            at: source.appendingPathComponent("dir.mp4"), withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(
            at: source.appendingPathComponent("link.mp4"),
            withDestinationURL: URL(fileURLWithPath: "/no-such-target"))
        makeFile("upper.MP4", bytes: Data("upper".utf8), in: source)  // 小写比较 → 命中
        let report = await makeImporter(trash: trash).run()
        XCTAssertEqual(report.imported, 1)
        XCTAssertEqual(bytes(at: dest.appendingPathComponent("upper.MP4")), Data("upper".utf8))
    }

    func testMD5StreamsAcrossChunksAndMatchesOneShot() throws {
        let small = Data("hello".utf8)
        let a = makeFile("a.bin", bytes: small, in: root)
        let b = makeFile("b.bin", bytes: small, in: root)
        XCTAssertEqual(HanamiImporter.md5(at: a), HanamiImporter.md5(at: b), "同内容同摘要")
        XCTAssertEqual(HanamiImporter.md5(at: a), hex(Insecure.MD5.hash(data: small)))

        let big = Data(repeating: 0xAB, count: 1_048_576 + 1234)  // 过 1MB 分块边界
        let bigURL = makeFile("big.bin", bytes: big, in: root)
        XCTAssertEqual(HanamiImporter.md5(at: bigURL), hex(Insecure.MD5.hash(data: big)))

        XCTAssertNil(HanamiImporter.md5(at: root.appendingPathComponent("gone.bin")), "缺文件 → nil")
    }

    func testStaleTmpFromCrashIsHealedAndCountedFailed() async throws {
        makeFile("a.mp4", bytes: Data("crash-recovery".utf8), in: source)
        makeFile("a.mp4.tmp", bytes: Data("stale".utf8), in: dest)
        let report = await makeImporter(trash: trash).run()
        XCTAssertEqual(report.failedCopy, 1)
        XCTAssertEqual(report.imported, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.appendingPathComponent("a.mp4.tmp").path),
                       "残留 tmp 被清")
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.appendingPathComponent("a.mp4").path),
                       "成品没落地 → 下轮可重导")
    }

    // 明示不单测：NSFileWriteFileExistsError 分支只在并发导入下可达（同名检查先跳过），不造并发注入。

    func testSourceURLForDerivativeAtMatchesStandardizedPaths() {
        let original = root.appendingPathComponent("orig.mp4")
        let derivative = root.appendingPathComponent("orig-30fps.mp4")
        // 路径必须真实存在：standardizedFileURL 只对存在的路径归并 /var ↔ /private/var
        // （同 FrameRateTableTests 的前缀容差测试先例）。
        FileManager.default.createFile(atPath: original.path, contents: Data("o".utf8))
        FileManager.default.createFile(atPath: derivative.path, contents: Data("d".utf8))
        let entry = FrameRateEntry(
            sourcePath: original.path, sourceSize: 1,
            sourceMtime: Date(timeIntervalSince1970: 1_700_000_000),
            fps: 60, durationSeconds: 1,
            derivativePath: derivative.path, derivativeMtime: nil,
            state: .done)
        let table = FrameRateTable(entries: [entry])  // 纯构造，不碰默认 JSON URL

        XCTAssertEqual(table.sourceURL(forDerivativeAt: derivative), original)
        // /var 与 /private/var 两形态互为同一物理文件（/var 是符号链接），standardizedFileURL
        // 只对真实存在的路径归并。以真实文件的归并形态为基准推另一形态，不对 TMPDIR 前缀做
        // /var 假设 —— 环境已是 /private/var 形态时盲替换会产出 /private/private。
        let merged = derivative.standardizedFileURL.path
        let alternate = URL(fileURLWithPath: merged.hasPrefix("/var/")
            ? "/private/var/" + merged.dropFirst("/var/".count)
            : merged)
        XCTAssertNotEqual(alternate.path, merged, "两个形态的字符串确实不同")
        XCTAssertEqual(table.sourceURL(forDerivativeAt: alternate), original, "/var 与 /private/var 两形态都必须命中")
        XCTAssertNil(table.sourceURL(forDerivativeAt: original), "非派生 → nil")
        XCTAssertNil(table.sourceURL(forDerivativeAt: root.appendingPathComponent("other.mp4")))
    }
}
