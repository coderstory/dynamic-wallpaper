import XCTest
@testable import PicCore

/// `clip.mp4` 与 `Converted/clip-30fps.mp4` 路径不同，按 `url.path` 去重不生效，两条都会进池，同一段素材播两遍 —— 本组钉的是一对一替换且池大小不变。
@MainActor
final class PlaybackPoolReplacementTests: XCTestCase {

    private var root: URL!

    override func setUp() async throws {
        try await super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("p6-pool-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
        root = nil
        try await super.tearDown()
    }

    private func item(_ relativePath: String) -> VideoItem {
        VideoItem(url: root.appendingPathComponent(relativePath))
    }

    /// 派生文件必须在磁盘上真实存在 —— `hasLiveDerivative()` 读的是它的属性。
    @discardableResult
    private func makeFile(_ relativePath: String) -> VideoItem {
        let url = root.appendingPathComponent(relativePath)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: Data("d".utf8))
        return VideoItem(url: url)
    }

    /// 表项。`derivativeMtime` 留 nil —— 这组用例只关心路径替换，不关心产物新旧。
    private func entry(source: VideoItem, derivative: VideoItem) -> FrameRateEntry {
        FrameRateEntry(
            sourcePath: source.url.path, sourceSize: 0, sourceMtime: Date(timeIntervalSince1970: 0),
            fps: 60, durationSeconds: 60,
            derivativePath: derivative.url.path, derivativeMtime: nil,
            state: .done)
    }

    func testDerivativeReplacesSourceOneToOne() {
        let source = item("clip.mp4")
        let derivative = makeFile("Converted/clip-30fps.mp4")
        let table = FrameRateTable(entries: [entry(source: source, derivative: derivative)])

        let pool = PlaybackPool.build(root: [source], converted: [derivative], table: table)
        XCTAssertEqual(pool.count, 1, "池大小必须恒等于根目录条目数")
        XCTAssertEqual(pool.first?.url.path, derivative.url.path)
    }

    /// 卸载重装后表是空的（或被重置），但产物还在磁盘上 —— 这时候「没有表」不等于「没有关系」：
    /// 产物命名是确定的 `<stem>-30fps.mp4`，按名字就能认回来。认不回来的代价是同一段素材播两遍。
    func testWithoutTableStillReplacesByDerivativeName() {
        let source = item("clip.mp4")
        let derivative = makeFile("Converted/clip-30fps.mp4")
        let pool = PlaybackPool.build(root: [source], converted: [derivative], table: FrameRateTable())
        XCTAssertEqual(pool.count, 1, "表丢了也得认回来 —— 关系可由命名推导，不该依赖表记住")
        XCTAssertEqual(pool.first?.url.path, derivative.url.path)
    }

    /// 状态落后于磁盘的场景（本机实测过：199 个产物全部停在 `needsConvert`）——
    /// 表说了不算，磁盘上的产物说了算。
    func testStaleTableRowStillReplacesByDerivativeName() {
        let source = item("clip.mp4")
        let derivative = makeFile("Converted/clip-30fps.mp4")
        let stale = FrameRateEntry(
            sourcePath: source.url.path, sourceSize: 0, sourceMtime: Date(timeIntervalSince1970: 0),
            fps: 60, durationSeconds: 60,
            derivativePath: derivative.url.path, derivativeMtime: nil,
            state: .needsConvert)
        let pool = PlaybackPool.build(root: [source], converted: [derivative],
                                      table: FrameRateTable(entries: [stale]))
        XCTAssertEqual(pool.count, 1, "表状态落后时也必须替换，不能把产物追加成第二条")
        XCTAssertEqual(pool.first?.url.path, derivative.url.path)
    }

    /// 表说有派生片但文件已被删 → 回落原片，不能拿失效路径去装载。
    func testDeadDerivativeFallsBackToSource() {
        let source = item("clip.mp4")
        let vanished = item("Converted/clip-30fps.mp4")   // item 而非 makeFile：从未落盘
        let table = FrameRateTable(entries: [entry(source: source, derivative: vanished)])

        let pool = PlaybackPool.build(root: [source], converted: [vanished], table: table)
        XCTAssertEqual(pool.first?.url.path, source.url.path, "派生文件不在磁盘上 → 回落原片")
    }

    /// 源已被删时派生片是孤儿，不进池。
    func testOrphanDerivativeIsDropped() {
        let derivative = makeFile("Converted/ghost-30fps.mp4")
        let table = FrameRateTable(entries: [entry(source: item("ghost.mp4"), derivative: derivative)])

        let pool = PlaybackPool.build(root: [], converted: [derivative], table: table)
        XCTAssertEqual(pool.count, 0, "源已不存在的派生片不进池")
    }

    /// 替换发生在原位，不追加到末尾 —— 追加会让壁纸轮换顺序整体错乱。
    func testReplacementKeepsSourcePosition() {
        let a = item("a.mp4"), b = item("b.mp4"), c = item("c.mp4")
        let derivativeB = makeFile("Converted/b-30fps.mp4")
        let table = FrameRateTable(entries: [entry(source: b, derivative: derivativeB)])

        let pool = PlaybackPool.build(root: [a, b, c], converted: [derivativeB], table: table)
        XCTAssertEqual(pool.map(\.url.path), [a.url.path, derivativeB.url.path, c.url.path],
                       "替换发生在原位，不改变轮换顺序")
    }

    /// 转码产物（同名无后缀）不参与替换 —— 降帧与转码是两条产品线，按原规则追加。
    func testPlainTranscodeProductStillAppends() {
        let source = item("clip.mkv")
        let transcodeProduct = makeFile("Converted/clip.mp4")
        let pool = PlaybackPool.build(root: [source], converted: [transcodeProduct], table: FrameRateTable())
        XCTAssertEqual(pool.count, 2)
    }

    func testEmptyInputsYieldEmptyPool() {
        XCTAssertTrue(PlaybackPool.build(root: [], converted: [], table: FrameRateTable()).isEmpty)
    }
}