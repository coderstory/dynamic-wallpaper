import XCTest
@testable import PicCore

/// 降帧队列 —— 扫描、串行 drain、暂停/继续、取消、失败继续。
@MainActor
final class FpsTranscodeQueueTests: XCTestCase {

    /// 文件内自带替身（既有纪律：不跨文件引用别的测试类的 helper）。
    /// 进程外零调用 —— 自己写 .tmp、返回可控退出码。
    final class FakeRunner: TranscodeRunning, @unchecked Sendable {
        private(set) var calls: [String] = []
        var exitStatus: Int32 = 0
        /// 取消要观察的：`cancel()` 之后 run 返回非 0。
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

    // MARK: - 夹具

    @discardableResult
    private func makeSource(_ name: String) -> URL {
        let url = root.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: Data("s".utf8))
        return url
    }

    /// 真在磁盘上建一个产物（`hasLiveDerivative` 要读它）。
    @discardableResult
    private func makeDerivative(_ name: String) -> URL {
        let url = root.appendingPathComponent(
            MediaLibrary.excludedDirectoryName).appendingPathComponent(name)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: Data("d".utf8))
        return url
    }

    private func makeQueue(specProvider: @escaping (URL) async -> VideoAssetMetadata = { _ in
        VideoAssetMetadata(hasVideoTrack: true, frameRate: 60, durationSeconds: 10)
    }) -> FpsTranscodeQueue {
        FpsTranscodeQueue(
            runner: runner,
            root: root,
            availability: { .available(path: "/opt/homebrew/bin/ffmpeg") },
            freeSpaceProvider: { _ in nil },
            specProvider: specProvider)
    }

    // MARK: - 扫描

    /// fps ≤30 的不进队列 —— 287 个文件走这条路，一个都不转。
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
        // 比末段文件名 —— `enumerator` 返回 /private/var/...，raw 是 /var/...，
        // 两种规范化都给不出同一个串。
        XCTAssertEqual(queue.jobs.first?.sourceURL.lastPathComponent, "hi.mp4")
    }

    /// 读不到帧率 → 按「不降」处理，宁可文件大一点也不猜错画质。
    func testScanSkipsSourcesWithUnknownFrameRate() async {
        makeSource("unknown.mp4")
        let queue = makeQueue { _ in VideoAssetMetadata(hasVideoTrack: true, frameRate: nil) }
        await queue.scan()
        XCTAssertTrue(queue.jobs.isEmpty, "帧率读不到就不降")
    }

    /// 无视频轨的文件不进队列。
    func testScanSkipsSourcesWithoutVideoTrack() async {
        makeSource("broken.mp4")
        let queue = makeQueue { _ in VideoAssetMetadata(hasVideoTrack: false) }
        await queue.scan()
        XCTAssertTrue(queue.jobs.isEmpty)
    }

    /// `Converted/` 整棵排除 —— 产物自己不能再进队列。
    func testScanExcludesConvertedDirectory() async {
        makeDerivative("a-30fps.mp4")
        let queue = makeQueue()
        await queue.scan()
        XCTAssertTrue(queue.jobs.isEmpty, "Converted/ 里的产物不进队列")
    }

    /// 表里已完成的文件不再重复入队。
    func testScanSkipsEntriesAlreadyDoneInTable() async throws {
        let source = makeSource("done.mp4")
        let derivative = makeDerivative("done-30fps.mp4")
        let tableURL = root.appendingPathComponent("t.json")
        // ⚠️ 表项必须用**规范化路径 + 真实属性** —— `enumerator` 给的是
        // /private/var/...，属性也要真的对上，否则 reusableEntry 判无效。
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

    // MARK: - 执行

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

    /// argv 必须含 HEVC 硬解 tag —— 漏了会静默软解。
    func testRunUsesHevcArguments() async {
        makeSource("a.mp4")
        let queue = makeQueue()
        await queue.scan()
        await queue.run()
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertTrue(runner.calls[0].contains("libx265"), "用 libx265")
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

    /// ffmpeg 不可用 → 不 spawn。
    func testUnavailableToolFailsWithoutRunning() async {
        makeSource("a.mp4")
        let queue = FpsTranscodeQueue(
            runner: runner, root: root,
            availability: { .unavailable },
            freeSpaceProvider: { _ in nil },
            specProvider: { _ in VideoAssetMetadata(hasVideoTrack: true, frameRate: 60) })
        await queue.scan()
        await queue.run()
        XCTAssertTrue(runner.calls.isEmpty, "工具不可用不得进 runner")
        XCTAssertEqual(queue.jobs.first?.state, .failed(reason: "ffmpeg_unavailable"))
    }

    /// 没有 pending 就不该空转。
    func testRunWithNoPendingDoesNothing() async {
        let queue = makeQueue()
        await queue.scan()
        await queue.run()
        XCTAssertTrue(runner.calls.isEmpty)
    }

    // MARK: - 暂停 / 取消

    /// 暂停：当前文件跑完才停，已完成的保留。剩下的仍是 pending。
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

    /// 取消：终止当前进程，当前文件回到 pending（可重试），不留半成品。
    func testCancelTerminatesAndReturnsCurrentToPending() async {
        makeSource("a.mp4")
        let queue = makeQueue()
        await queue.scan()
        queue.cancel()
        await queue.run()
        XCTAssertEqual(queue.jobs.first?.state, .pending, "取消后回到 pending 可重试")
    }

    /// 取消后不留 .tmp。
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
}