import XCTest
@testable import PicCore

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

    /// 判据只吃属性字典，所以这两条用手工属性 + 注入值，不读真实文件系统（mtime 读数不稳定）。
    private func attributes(size: Int = 1, mtime: Date = Date(timeIntervalSince1970: 1_700_000_000))
        -> [FileAttributeKey: Any] {
        [.size: size, .modificationDate: mtime]
    }

    private func entryWith(size: Int, mtime: Date) -> FrameRateEntry {
        FrameRateEntry(
            sourcePath: source.path, sourceSize: size, sourceMtime: mtime,
            fps: 60, durationSeconds: 120, state: .needsConvert)
    }

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

    /// 读不到属性（文件被删）→ 判无效，调用方据此重新探测。
    func testUnreadableAttributesInvalidateEntry() {
        let entry = entryWith(size: 1, mtime: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertFalse(entry.isValid(against: [:]))
    }

    /// 复用是增量扫描的收益来源。
    func testSameFileReadTwiceIsStillReusable() {
        let table = FrameRateTable(entries: [makeEntry()])
        XCTAssertNotNil(table.reusableEntry(for: source),
                        "同一文件连续两次读必须复用，否则增量扫描退化成全量重探")
        XCTAssertEqual(table.reusableEntry(for: source)?.state, .needsConvert)
    }

    func testMissingFileInvalidatesEntry() {
        let table = FrameRateTable(entries: [makeEntry()])
        let gone = root.appendingPathComponent("gone.mp4")
        XCTAssertNil(table.reusableEntry(for: gone), "文件不在表里 → 需要探测")
    }

    /// `FileManager.enumerator` 返回 `/private/var/...`，而调用方给的 URL 可能是 `/var/...`。
    /// 直接 `==` 比 path 会永远命中不了 —— 症状是增量扫描静默退化成全量重探，没有任何报错。
    func testLookupTolerantToPathPrefixDifference() throws {
        let entry = makeEntry()
        let table = FrameRateTable(entries: [entry])
        // 临时目录在 /var/folders/... 下；换前缀即模拟 enumerator 的写法。
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

    /// 卸载重装 / 表丢过一次写入之后，产物还在磁盘上但表里仍是 `needsConvert` ——
    /// 不对账的话这些文件会被重新排一遍（已经降过帧还要再烤一次），播放池也不再替换它们。
    func testReconcileMarksEntryDoneWhenDerivativeIsOnDisk() throws {
        let derivative = root.appendingPathComponent("Converted/a-30fps.mp4")
        try FileManager.default.createDirectory(at: derivative.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data("d".utf8).write(to: derivative)

        var entry = makeEntry(state: .needsConvert)
        entry.derivativePath = derivative.path
        var table = FrameRateTable(entries: [entry])
        try table.save(to: tableURL)

        try table.reconcileWithDerivatives(to: tableURL)

        XCTAssertEqual(table.entries[0].state, .done, "产物在磁盘上 → 关系应当被认回来")
        XCTAssertNotNil(table.entries[0].derivativeMtime,
                        "`.done` 必须带上产物 mtime —— `hasLiveDerivative` 靠它判新鲜")
    }

    /// 反向：产物被手工删掉了，`.done` 必须退回可重试，否则这件事就被永久记成「已完成」。
    func testReconcileDemotesDoneWhenDerivativeVanished() throws {
        let missing = root.appendingPathComponent("Converted/gone-30fps.mp4")
        var entry = makeEntry(state: .done)
        entry.derivativePath = missing.path
        entry.derivativeMtime = Date()
        var table = FrameRateTable(entries: [entry])

        try table.reconcileWithDerivatives(to: tableURL)

        XCTAssertEqual(table.entries[0].state, .needsConvert, "产物没了 → 必须退回可重试")
        XCTAssertNil(table.entries[0].derivativeMtime)
    }

    /// 没变化的旁观者不动：`.okAt30` 的行不该被顺手抬成 `.done`。
    func testReconcileLeavesUnrelatedStatesAlone() throws {
        var entry = makeEntry(state: .okAt30)
        entry.derivativePath = root.appendingPathComponent("Converted/a-30fps.mp4").path
        var table = FrameRateTable(entries: [entry])

        try table.reconcileWithDerivatives(to: tableURL)

        XCTAssertEqual(table.entries[0].state, .okAt30)
    }

    /// 对账必须真的落盘 —— 只改内存的话，下一次 `load` 拿回的还是旧状态。
    func testReconcilePersistsToDisk() throws {
        let derivative = root.appendingPathComponent("Converted/a-30fps.mp4")
        try FileManager.default.createDirectory(at: derivative.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data("d".utf8).write(to: derivative)

        var entry = makeEntry(state: .needsConvert)
        entry.derivativePath = derivative.path
        var table = FrameRateTable(entries: [entry])
        try table.save(to: tableURL)
        try table.reconcileWithDerivatives(to: tableURL)

        XCTAssertEqual(FrameRateTable.load(from: tableURL).entries[0].state, .done)
    }

    /// 没有 derivativePath 的行必须原样跳过：既不能因为 nil 而崩，也不能被改状态。
    func testReconcileSkipsEntriesWithoutDerivativePath() throws {
        var table = FrameRateTable(entries: [makeEntry(state: .needsConvert)])
        XCTAssertNoThrow(try table.reconcileWithDerivatives(to: tableURL))
        XCTAssertEqual(table.entries[0].state, .needsConvert)
    }
}