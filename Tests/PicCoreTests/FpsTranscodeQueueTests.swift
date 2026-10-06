import XCTest
@testable import PicCore

/// 降帧队列 —— 扫描、串行 drain、暂停/继续、取消、失败继续。
@MainActor
final class FpsTranscodeQueueTests: XCTestCase {

    /// 文件内自带替身，不要与 `TranscodeQueueTests.swift` 里那份合并。进程外零调用：真写 .tmp、返回可控退出码。
    final class FakeRunner: TranscodeRunning, @unchecked Sendable {
        private(set) var calls: [String] = []
        var exitStatus: Int32 = 0
        var isCancelled = false

        func run(ffmpegPath: String, arguments: [String], outputTemporaryPath: String,
                 onProgressLine: @escaping @Sendable (String) -> Void) async -> Int32 {
            calls.append(arguments.joined(separator: " "))
            if isCancelled { return -1 }
            FileManager.default.createFile(
                atPath: outputTemporaryPath, contents: Data("fake".utf8))
            onProgressLine("frame=1")
            onProgressLine("out_time_ms=500000")
            onProgressLine("progress=end")
            return exitStatus
        }
    }

    private var root: URL!
    private var runner: FakeRunner!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("p6-fpsq-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        runner = FakeRunner()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        root = nil
        runner = nil
        super.tearDown()
    }

    @discardableResult
    private func makeSource(_ name: String) -> URL {
        let url = root.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: Data("s".utf8))
        return url
    }

    /// 真在磁盘上建一个产物 —— `hasLiveDerivative` 要去读它。
    @discardableResult
    private func makeDerivative(_ name: String) -> URL {
        let url = root.appendingPathComponent(
            MediaLibrary.excludedDirectoryName).appendingPathComponent(name)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: Data("d".utf8))
        return url
    }

    /// 必须显式给 tableURL，默认路径会读写真实用户数据（~/Library/Application Support/Pic/frame-rate-table.json）。
    private func makeQueue(specProvider: @escaping (URL) async -> VideoAssetMetadata = { _ in
        VideoAssetMetadata(hasVideoTrack: true, frameRate: 60, durationSeconds: 10)
    }) -> FpsTranscodeQueue {
        FpsTranscodeQueue(
            runner: runner,
            root: root,
            availability: { .available(path: "/opt/homebrew/bin/ffmpeg") },
            freeSpaceProvider: { _ in nil },
            specProvider: specProvider,
            tableURL: root.appendingPathComponent("fps-table.json"))
    }

    func testScanSkipsSourcesAtOrBelowThirtyFps() async {
        let source = makeSource("ok.mp4")
        let queue = makeQueue { _ in
            VideoAssetMetadata(hasVideoTrack: true, frameRate: 30, durationSeconds: 10)
        }
        await queue.scan()
        XCTAssertTrue(queue.jobs.isEmpty, "恰好 30fps 不需要降")
    }

    func testScanEnqueuesSourcesAboveThirtyFps() async {
        let source = makeSource("hi.mp4")
        let queue = makeQueue()
        await queue.scan()
        XCTAssertEqual(queue.jobs.count, 1)
        // 只比末段文件名：`enumerator` 返回 /private/var/...，raw 是 /var/...，两种规范化都给不出同一个串。
        XCTAssertEqual(queue.jobs.first?.sourceURL.lastPathComponent, "hi.mp4")
    }

    func testScanSkipsSourcesWithUnknownFrameRate() async {
        makeSource("unknown.mp4")
        let queue = makeQueue { _ in VideoAssetMetadata(hasVideoTrack: true, frameRate: nil) }
        await queue.scan()
        XCTAssertTrue(queue.jobs.isEmpty, "帧率读不到就不降")
    }

    func testScanSkipsSourcesWithoutVideoTrack() async {
        makeSource("broken.mp4")
        let queue = makeQueue { _ in VideoAssetMetadata(hasVideoTrack: false) }
        await queue.scan()
        XCTAssertTrue(queue.jobs.isEmpty)
    }

    func testScanExcludesConvertedDirectory() async {
        makeDerivative("a-30fps.mp4")
        let queue = makeQueue()
        await queue.scan()
        XCTAssertTrue(queue.jobs.isEmpty, "Converted/ 里的产物不进队列")
    }

    func testScanExposesTableCardCounts() async {
        makeSource("hi1.mp4")
        makeSource("hi2.mp4")
        makeSource("lo1.mp4")
        let queue = makeQueue { url in
            url.lastPathComponent.hasPrefix("hi")
                ? VideoAssetMetadata(hasVideoTrack: true, frameRate: 60, durationSeconds: 10)
                : VideoAssetMetadata(hasVideoTrack: true, frameRate: 30, durationSeconds: 10)
        }
        await queue.scan()

        XCTAssertEqual(queue.scannedCount, 3, "扫到 3 个源文件")
        XCTAssertEqual(queue.jobs.count, 2, "两个高于 30fps 进队列")
        XCTAssertEqual(queue.okAt30Count, 1, "「已是 30fps」必须显示 1，不能是 0")
        XCTAssertEqual(queue.tableTotal, 3, "帧率表行数 = 扫到的源文件数")
    }

    /// 探测失败的文件**不进表** —— 表存的是实测结果，`fps` 是非可选 Double，存失败只能写 0。所以 tableTotal 会小于 scannedCount。
    func testUnknownFrameRateCountsInScanButNotTable() async {
        makeSource("a.mp4")
        makeSource("b.mp4")
        let queue = makeQueue { url in
            url.lastPathComponent == "a.mp4"
                ? VideoAssetMetadata(hasVideoTrack: true, frameRate: nil)
                : VideoAssetMetadata(hasVideoTrack: true, frameRate: 30, durationSeconds: 10)
        }
        await queue.scan()
        XCTAssertEqual(queue.scannedCount, 2, "两个都被扫过")
        XCTAssertEqual(queue.tableTotal, 1, "只有真正测到帧率的才占一行")
        XCTAssertEqual(queue.okAt30Count, 1, "30fps 那个算达标")
    }

    func testScanSkipsEntriesAlreadyDoneInTable() async throws {
        let source = makeSource("done.mp4")
        let derivative = makeDerivative("done-30fps.mp4")
        let tableURL = root.appendingPathComponent("t.json")
        // 表项必须用**规范化路径 + 真实属性** —— `enumerator` 给的是 /private/var/...，属性也要真的对上，否则 reusableEntry 判无效。
        let canonical = source.resolvingSymlinksInPath().path
        let attributes = try FileManager.default.attributesOfItem(atPath: canonical)
        var table = FrameRateTable()
        try table.upsert(FrameRateEntry(
            sourcePath: canonical,
            sourceSize: attributes[.size] as? Int ?? 0,
            sourceMtime: attributes[.modificationDate] as? Date ?? Date(),
            fps: 60, durationSeconds: 10,
            derivativePath: derivative.path, derivativeMtime: nil,
            state: .done), to: tableURL)

        let queue = FpsTranscodeQueue(
            runner: runner, root: root,
            availability: { .available(path: "/opt/homebrew/bin/ffmpeg") },
            freeSpaceProvider: { _ in nil },
            specProvider: { _ in VideoAssetMetadata(hasVideoTrack: true, frameRate: 60, durationSeconds: 10) },
            tableURL: tableURL)
        await queue.scan()
        XCTAssertTrue(queue.jobs.isEmpty, "已在表里完成的文件不重复入队")
    }

    func testRunProducesDerivativeAndMarksDone() async throws {
        let source = makeSource("a.mp4")
        let queue = makeQueue()
        await queue.scan()
        await queue.run()

        XCTAssertEqual(queue.jobs.first?.state, .done)
        let derivative = root.appendingPathComponent(
            MediaLibrary.excludedDirectoryName).appendingPathComponent("a-30fps.mp4")
        XCTAssertTrue(FileManager.default.fileExists(atPath: derivative.path), "产物落盘")
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "原片保留不动")
    }

    /// 编码器名必须引用 profile 而非硬编码 —— profile 是唯一真相。
    func testRunUsesProfileEncoderWithHevcTag() async {
        makeSource("a.mp4")
        let queue = makeQueue()
        await queue.scan()
        await queue.run()
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertTrue(runner.calls[0].contains(VideoEncoderProfile.encoder.ffmpegName),
                      "用 profile 指定的编码器")
        XCTAssertTrue(runner.calls[0].contains("-tag:v hvc1"), "必须带 hvc1 tag 才走硬解")
    }

    func testFailureMarksFailedAndContinues() async {
        runner.exitStatus = 1
        makeSource("bad.mp4")
        let queue = makeQueue()
        await queue.scan()
        await queue.run()
        XCTAssertEqual(queue.jobs.first?.state, .failed(reason: "exit_nonzero"),
                       "失败用受控 token，不放 ffmpeg 原始日志")
    }

    func testUnavailableToolFailsWithoutRunning() async {
        makeSource("a.mp4")
        let queue = FpsTranscodeQueue(
            runner: runner, root: root,
            availability: { .unavailable },
            freeSpaceProvider: { _ in nil },
            specProvider: { _ in VideoAssetMetadata(hasVideoTrack: true, frameRate: 60) },
            tableURL: root.appendingPathComponent("fps-table.json"))
        await queue.scan()
        await queue.run()
        XCTAssertTrue(runner.calls.isEmpty, "工具不可用不得进 runner")
        XCTAssertEqual(queue.jobs.first?.state, .failed(reason: "ffmpeg_unavailable"))
    }

    func testRunWithNoPendingDoesNothing() async {
        let queue = makeQueue()
        await queue.scan()
        await queue.run()
        XCTAssertTrue(runner.calls.isEmpty)
    }

    func testPauseStopsAfterCurrentJob() async {
        makeSource("a.mp4")
        makeSource("b.mp4")
        let queue = makeQueue()
        await queue.scan()
        queue.pause()
        await queue.run()

        XCTAssertTrue(runner.calls.isEmpty, "暂停后不该开跑")
        XCTAssertEqual(queue.jobs.count, 2)
        XCTAssertTrue(queue.jobs.allSatisfy { $0.state == .pending })
    }

    /// 取消：当前文件回到 pending（可重试），不留半成品。
    func testCancelTerminatesAndReturnsCurrentToPending() async {
        makeSource("a.mp4")
        let queue = makeQueue()
        await queue.scan()
        queue.cancel()
        await queue.run()
        XCTAssertEqual(queue.jobs.first?.state, .pending, "取消后回到 pending 可重试")
    }

    func testCancelLeavesNoTemporaryArtifacts() async {
        runner.isCancelled = true
        makeSource("a.mp4")
        let queue = makeQueue()
        await queue.scan()
        queue.cancel()
        await queue.run()

        let converted = root.appendingPathComponent(MediaLibrary.excludedDirectoryName)
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: converted.path)) ?? []
        XCTAssertFalse(leftovers.contains { $0.hasSuffix(".tmp") }, "取消后不得残留 .tmp")
    }

    func testCancelWithEmptyQueueIsSafe() async {
    makeQueue().cancel()
    }

    /// 产物落盘后必须把 `.done` 写回表 —— 否则下次扫描还是 `needsConvert`，同一批文件会被重新排队。
    func testSuccessWritesDoneBackToTable() async throws {
        makeSource("a.mp4")
        let tableURL = root.appendingPathComponent("fps-table.json")
        let queue = FpsTranscodeQueue(
            runner: runner, root: root,
            availability: { .available(path: "/opt/homebrew/bin/ffmpeg") },
            freeSpaceProvider: { _ in nil },
            specProvider: { _ in VideoAssetMetadata(hasVideoTrack: true, frameRate: 60, durationSeconds: 10) },
            tableURL: tableURL)
        await queue.scan()
        await queue.run()

        let entry = FrameRateTable.load(from: tableURL)
            .entry(for: root.appendingPathComponent("a.mp4").resolvingSymlinksInPath())
        XCTAssertEqual(entry?.state, .done, "成功后必须写回 done")
        XCTAssertNotNil(entry?.derivativeMtime, "done 时要记下产物时间戳供后续失效判定")
    }

    /// 失败也要写回 —— 否则每次扫描都重排同一个失败文件。
    func testFailureWritesFailedBackToTable() async {
        runner.exitStatus = 1
        makeSource("bad.mp4")
        let tableURL = root.appendingPathComponent("fps-table.json")
        let queue = FpsTranscodeQueue(
            runner: runner, root: root,
            availability: { .available(path: "/opt/homebrew/bin/ffmpeg") },
            freeSpaceProvider: { _ in nil },
            specProvider: { _ in VideoAssetMetadata(hasVideoTrack: true, frameRate: 60, durationSeconds: 10) },
            tableURL: tableURL)
        await queue.scan()
        await queue.run()

        let entry = FrameRateTable.load(from: tableURL)
            .entry(for: root.appendingPathComponent("bad.mp4").resolvingSymlinksInPath())
        XCTAssertEqual(entry?.state, .failed, "失败要写回，避免下次重复排队")
    }

    func testCancelKeepsCompletedEntriesInTable() async throws {
        makeSource("a.mp4")
        makeSource("b.mp4")
        let tableURL = root.appendingPathComponent("fps-table.json")
        let queue = FpsTranscodeQueue(
            runner: runner, root: root,
            availability: { .available(path: "/opt/homebrew/bin/ffmpeg") },
            freeSpaceProvider: { _ in nil },
            specProvider: { _ in VideoAssetMetadata(hasVideoTrack: true, frameRate: 60, durationSeconds: 10) },
            tableURL: tableURL)
        await queue.scan()
        queue.cancel()
        await queue.run()

        let table = FrameRateTable.load(from: tableURL)
        let states = table.entries.map(\.state)
        XCTAssertFalse(states.contains(.done), "取消时不该有已完成")
        XCTAssertEqual(states.count, 2, "两个文件都已在表里")
    }
}