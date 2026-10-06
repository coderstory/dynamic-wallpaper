import XCTest
@testable import PicCore

/// 产物路径推导、`.tmp` 中间态、mtime 幂等跳过。临时目录 + UUID 自造，干净 clone 上 `swift test` 也必须绿。
final class TranscodeOutputNamingTests: XCTestCase {

    private var root: URL!
    private var naming: TranscodeOutputNaming!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("p6-naming-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        naming = TranscodeOutputNaming(root: root)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        root = nil
        naming = nil
        super.tearDown()
    }

    /// 在 root 下放一个几字节的占位源文件。
    private func makeSource(_ name: String) -> URL {
        let url = root.appendingPathComponent(name)
        try? "placeholder".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func makeProduct(for source: URL, mtimeOffset: TimeInterval) throws {
        let product = naming.outputURL(for: source)
        try FileManager.default.createDirectory(
            at: product.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "product".write(to: product, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(mtimeOffset)],
            ofItemAtPath: product.path)
    }

    func testOutputURLIsConvertedDirWithMp4Extension() {
        let source = makeSource("电影.a.mkv")
        XCTAssertEqual(naming.outputURL(for: source).path,
                       root.appendingPathComponent("Converted/电影.a.mp4").path,
                       "电影.a.mkv → <root>/Converted/电影.a.mp4（去扩展名只去最后一段，不加任何后缀）")
    }

    func testTemporaryURLAppendsTmpSuffix() {
        let source = makeSource("电影.a.mkv")
        XCTAssertEqual(naming.temporaryURL(for: source).path,
                       root.appendingPathComponent("Converted/电影.a.mp4.tmp").path,
                       "中间态 = 产物路径 + .tmp 后缀（C11：先写 tmp 再 rename）")
    }

    func testWeirdNamesSurvive() {
        let source = makeSource("视频 壁纸.sample (1).webm")
        XCTAssertEqual(naming.outputURL(for: source).lastPathComponent,
                       "视频 壁纸.sample (1).mp4",
                       "空格 + 点 + 括号 + 中文逐字保留")
    }

    func testSkipWhenProductNewerThanOrEqualToSource() throws {
        let source = makeSource("s.mkv")
        try makeProduct(for: source, mtimeOffset: 60)
        XCTAssertTrue(naming.skipDecision(source: source),
                      "产物比源新 60 秒 → 跳过（已转过且源没变，防重复烤机）")
    }

    func testNoSkipWhenSourceNewer() throws {
        let source = makeSource("s.mkv")
        try makeProduct(for: source, mtimeOffset: -60)
        XCTAssertFalse(naming.skipDecision(source: source),
                       "产物比源旧 → 源变过，必须重转")
    }

    func testNoSkipWhenProductMissing() {
        let source = makeSource("s.mkv")
        XCTAssertFalse(naming.skipDecision(source: source),
                       "产物不存在 → 不跳过")
    }
}
