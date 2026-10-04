import XCTest
@testable import PicCore

/// 帧率表 —— 增量扫描的地基：判据错了整张表失效，491 个文件每次全量重探。
final class FrameRateTableTests: XCTestCase {

    private var root: URL!
    private var source: URL!
    private var tableURL: URL!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("p6-fps-\(UUID().uuidString)", isDirectory: true)
        source = root.appendingPathComponent("a.mp4")
        tableURL = root.appendingPathComponent("table.json")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: source.path, contents: Data("x".utf8))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        root = nil
        source = nil
        tableURL = nil
        super.tearDown()
    }

    /// 从真实文件建一行 —— `reusableEntry` 要读真实属性，判据必须对得上。
    private func makeEntry(state: ProbeState = .needsConvert) -> FrameRateEntry {
        let attributes = try! FileManager.default.attributesOfItem(atPath: source.path)
        return FrameRateEntry(
            sourcePath: source.path,
            sourceSize: attributes[.size] as! Int,
            sourceMtime: attributes[.modificationDate] as! Date,
            fps: 60, durationSeconds: 120,
            derivativePath: nil, derivativeMtime: nil,
            state: state)
    }

    /// 判据的直接对手：手工属性字典，不依赖文件系统读出的 mtime 是否稳定。
    private func attributes(size: Int = 1, mtime: Date = Date(timeIntervalSince1970: 1_700_000_000))
        -> [FileAttributeKey: Any] {
        [.size: size, .modificationDate: mtime]
    }

    /// 判据本身只吃属性字典，所以这四条用注入值，不受真实文件系统影响。
    private func entryWith(size: Int, mtime: Date) -> FrameRateEntry {
        FrameRateEntry(
            sourcePath: source.path, sourceSize: size, sourceMtime: mtime,
            fps: 60, durationSeconds: 120, state: .needsConvert)
    }

    // MARK: - 有效性

    func testIdenticalAttributesAreValid() {
        let entry = entryWith(size: 1, mtime: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertTrue(entry.isValid(against: attributes()),
                      "size 与 mtime 都没变 → 这一行还能信")
    }

    /// size 也要参与判据：换成同时间戳的另一个视频时 mtime 看不出来。
    func testChangedSizeInvalidatesEntry() {
        let entry = entryWith(size: 1, mtime: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertFalse(entry.isValid(against: attributes(size: 2)),
                       "size 变了说明文件被换过")
    }

    func testChangedMtimeInvalidatesEntry() {
        let entry = entryWith(size: 1, mtime: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertFalse(entry.isValid(against: attributes(mtime: Date(timeIntervalSince1970: 1))),
                       "mtime 变了说明文件动过")
    }

    /// 读不到属性（文件被删）→ 判无效，由调用方重新探测。
    func testUnreadableAttributesInvalidateEntry() {
        let entry = entryWith(size: 1, mtime: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertFalse(entry.isValid(against: [:]))
    }

    /// 同一文件连续两次读必须复用 —— 这是增量扫描的收益来源。
    func testSameFileReadTwiceIsStillReusable() {
        let table = FrameRateTable(entries: [makeEntry()])
        XCTAssertNotNil(table.reusableEntry(for: source),
                        "同一文件连续两次读必须复用，否则增量扫描退化成全量重探")
        XCTAssertEqual(table.reusableEntry(for: source)?.state, .needsConvert)
    }

    /// 表里没有的文件 → 需要探测。
    func testMissingFileInvalidatesEntry() {
        let table = FrameRateTable(entries: [makeEntry()])
        let gone = root.appendingPathComponent("gone.mp4")
        XCTAssertNil(table.reusableEntry(for: gone), "文件不在表里 → 需要探测")
    }

    /// ⚠️ 这条钉的是真实 bug：`FileManager.enumerator` 返回 `/private/var/...`，
    /// 而调用方给的 URL 可能是 `/var/...`。直接 `==` 比 path 会永远命中不了 ——
    /// 症状是增量扫描静默退化成全量重探，没有任何报错。
    func testLookupTolerantToPathPrefixDifference() throws {
        let entry = makeEntry()
        var table = FrameRateTable(entries: [entry])
        // macOS 临时目录在 /var/folders/... 下；enumerator 会给 /private/var/...
        let mangled = URL(fileURLWithPath: entry.sourcePath
            .replacingOccurrences(of: "/var/", with: "/private/var/"))
        XCTAssertNotEqual(mangled.path, entry.sourcePath, "两个 URL 的字符串确实不同")
        XCTAssertNotNil(table.entry(for: mangled), "规范化后必须命中同一条")
    }

    func testUpsertReplacesRowReachedByDifferentlyWrittenPath() throws {
        var table = FrameRateTable()
        try table.upsert(makeEntry(), to: tableURL)
        var second = makeEntry()
        second.sourcePath = second.sourcePath.replacingOccurrences(of: "/var/", with: "/private/var/")
        try table.upsert(second, to: tableURL)
        XCTAssertEqual(table.entries.count, 1, "同文件的不同路径写法必须覆盖而不是新增一行")
    }

    // MARK: - 跨重启恢复

    /// `converting` 是活状态：app 退出时表里会留下它，读回时没有半个进程在跑，
    /// 必须退回可重试，否则这个文件会被永久跳过。
    func testConvertingRecoversToRetryable() {
        let table = FrameRateTable(entries: [makeEntry(state: .converting)])
        XCTAssertEqual(table.reusableEntry(for: source)?.state, .needsConvert,
                       "converting 从磁盘读回要退回 needsConvert")
    }

    func testFailedRecoversToRetryable() {
        let table = FrameRateTable(entries: [makeEntry(state: .failed)])
        XCTAssertEqual(table.reusableEntry(for: source)?.state, .needsConvert)
    }

    func testDoneStaysDone() {
        let table = FrameRateTable(entries: [makeEntry(state: .done)])
        XCTAssertEqual(table.reusableEntry(for: source)?.state, .done,
                       "已完成的不能退回 —— 否则每次开 tab 都重转一遍")
    }

    // MARK: - 派生文件

    /// 派生文件被删 → 回落到原片，不能拿一条失效路径去装载。
    func testMissingDerivativeIsNotLive() {
        var entry = makeEntry(state: .done)
        entry.derivativePath = root.appendingPathComponent("gone-30fps.mp4").path
        entry.derivativeMtime = Date()
        XCTAssertFalse(entry.hasLiveDerivative(), "派生文件不存在 → 回落原片")
    }

    func testLiveDerivativeIsLive() throws {
        let derivative = root.appendingPathComponent("a-30fps.mp4")
        FileManager.default.createFile(atPath: derivative.path, contents: Data("y".utf8))
        var entry = makeEntry(state: .done)
        entry.derivativePath = derivative.path
        entry.derivativeMtime = try FileManager.default
            .attributesOfItem(atPath: derivative.path)[.modificationDate] as? Date
        XCTAssertTrue(entry.hasLiveDerivative())
    }

    // MARK: - 落盘

    func testSaveThenLoadRoundTrips() throws {
        var table = FrameRateTable()
        try table.upsert(makeEntry(), to: tableURL)
        let loaded = FrameRateTable.load(from: tableURL)
        XCTAssertEqual(loaded.entries.count, 1)
        XCTAssertEqual(loaded.entry(for: source)?.fps, 60)
    }

    /// 读不到 / 解不开一律当空表 —— 一张坏表不该卡死整个 tab。
    func testLoadGarbageYieldsEmptyTable() throws {
        try Data("not json".utf8).write(to: tableURL)
        XCTAssertEqual(FrameRateTable.load(from: tableURL).entries.count, 0)
    }

    func testLoadMissingFileYieldsEmptyTable() {
        XCTAssertEqual(FrameRateTable.load(from: root.appendingPathComponent("none.json")).entries.count, 0)
    }

    func testUpsertReplacesRatherThanDuplicates() throws {
        var table = FrameRateTable()
        try table.upsert(makeEntry(), to: tableURL)
        try table.upsert(makeEntry(), to: tableURL)
        XCTAssertEqual(table.entries.count, 1, "同路径两次 upsert 只留一行")
    }

    func testPruneDropsOrphanRows() throws {
        var table = FrameRateTable()
        try table.upsert(makeEntry(), to: tableURL)
        try table.prune(keepingLiveSources: [], to: tableURL)
        XCTAssertEqual(table.entries.count, 0, "片库删了文件，表里不能留孤儿行")
    }

    // MARK: - 计数（UI 的帧率表卡读它）

    func testCountsSplitNeedsConvertFromOkAt30() {
        let table = FrameRateTable(entries: [makeEntry(state: .needsConvert)])
        XCTAssertEqual(table.needsConvertCount, 1)
        XCTAssertEqual(table.okAt30Count, 0)

        let ok = FrameRateTable(entries: [makeEntry(state: .okAt30)])
        XCTAssertEqual(ok.needsConvertCount, 0)
        XCTAssertEqual(ok.okAt30Count, 1)
    }
}