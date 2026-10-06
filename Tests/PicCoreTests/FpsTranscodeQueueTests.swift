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

    /// 卸载重装的等价形态：磁盘上有产物，但表已经丢了 / 没写过。
    /// 这时候必须靠磁盘把关系认回来，而不是把 60fps 的源再排一次队。
    func testScanSkipsSourceWhoseDerivativeAlreadyExistsWithoutTable() async {
        _ = makeSource("fresh.mp4")
        _ = makeDerivative("fresh-30fps.mp4")
        let queue = makeQueue()

        await queue.scan()

        XCTAssertTrue(queue.jobs.isEmpty, "产物已在磁盘上 → 不该再排一次队")
        XCTAssertEqual(queue.okAt30Count, 0)
    }

    /// 表的状态落后于磁盘（一次性写入被覆盖）：行写着 `needsConvert`，产物却好好的。
    func testScanReconcilesStaleNeedsConvertRowToDone() async throws {
        let source = makeSource("stale.mp4")
        let derivative = makeDerivative("stale-30fps.mp4")
        let tableURL = root.appendingPathComponent("t.json")
        let canonical = source.resolvingSymlinksInPath().path
        let attributes = try FileManager.default.attributesOfItem(atPath: canonical)
        var table = FrameRateTable()
        try table.upsert(FrameRateEntry(
            sourcePath: canonical,
            sourceSize: attributes[.size] as? Int ?? 0,
            sourceMtime: attributes[.modificationDate] as? Date ?? Date(),
            fps: 60, durationSeconds: 10,
            derivativePath: derivative.path, derivativeMtime: nil,
            state: .needsConvert), to: tableURL)

        let queue = FpsTranscodeQueue(
            runner: runner, root: root,
            availability: { .available(path: "/opt/homebrew/bin/ffmpeg") },
            freeSpaceProvider: { _ in nil },
            specProvider: { _ in VideoAssetMetadata(hasVideoTrack: true, frameRate: 60, durationSeconds: 10) },
            tableURL: tableURL)

        await queue.scan()

        XCTAssertTrue(queue.jobs.isEmpty, "已经有产物的不该进队列")
        let after = FrameRateTable.load(from: tableURL)
        XCTAssertEqual(after.entries.first?.state, .done, "对账必须落盘，不然下次又从头来")
        XCTAssertNotNil(after.entries.first?.derivativeMtime)
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

    /// `onBatchFinished` 是一次全库重扫的扳机。一个 job 都没处理就通知装配层的话，
    /// 用户会看到没有任何来由的重扫。
    func testRunWithoutProcessingAnyJobDoesNotAnnounceBatch() async {
        let queue = makeQueue()
        await queue.scan()
        var batchFinishes = 0
        queue.onBatchFinished = { batchFinishes += 1 }

        await queue.run()

        XCTAssertEqual(batchFinishes, 0, "一个 job 都没跑 → 不许通知装配层去重扫")
    }

    /// 还没开工就暂停同理 —— 对应「点开始又马上暂停」的真实操作。
    func testPausedBeforeAnyJobDoesNotAnnounceBatch() async {
        makeSource("a.mp4")
        let queue = makeQueue()
        await queue.scan()
        queue.pause()
        var batchFinishes = 0
        queue.onBatchFinished = { batchFinishes += 1 }

        await queue.run()

        XCTAssertTrue(runner.calls.isEmpty)
        XCTAssertEqual(batchFinishes, 0, "没干活就通知 = 白扫一次库")
    }

    /// 反面：真的转了东西就必须通知一次，且只通知一次。
    func testRunAnnouncesBatchExactlyOnceAfterRealWork() async {
        makeSource("a.mp4")
        makeSource("b.mp4")
        let queue = makeQueue()
        await queue.scan()
        var batchFinishes = 0
        queue.onBatchFinished = { batchFinishes += 1 }

        await queue.run()

        XCTAssertEqual(batchFinishes, 1, "真的跑了 job 就得通知一次")
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

    // MARK: - 换目录后清表（场景 H2）

    /// 换过目录之后，旧目录的行会永远留在表里 —— `prune()` 从未被生产代码调用过，
    /// 于是「总行数」长期虚高，UI 报的片库规模比实际大。
    func testScanPrunesRowsWhoseSourceIsGone() async throws {
        let stale = root.appendingPathComponent("stale.mp4")
        let tableURL = root.appendingPathComponent("fps-table.json")
        var table = FrameRateTable()
        try table.upsert(FrameRateEntry(
            sourcePath: stale.path, sourceSize: 1,
            sourceMtime: Date(timeIntervalSince1970: 0), fps: 60, durationSeconds: 1,
            derivativePath: nil, state: .needsConvert), to: tableURL)
        makeSource("live.mp4")

        let queue = FpsTranscodeQueue(
            runner: runner, root: root,
            availability: { .available(path: "/opt/homebrew/bin/ffmpeg") },
            freeSpaceProvider: { _ in nil },
            specProvider: { _ in VideoAssetMetadata(hasVideoTrack: true, frameRate: 60, durationSeconds: 10) },
            tableURL: tableURL)
        await queue.scan()

        let remaining = FrameRateTable.load(from: tableURL).entries.map(\.sourcePath)
        XCTAssertFalse(remaining.contains(stale.path), "源已不在 → 行必须清掉")
        XCTAssertTrue(remaining.contains { $0.hasSuffix("live.mp4") }, "还在的行不能误删")
    }

    /// 反例：一个文件都没扫到（盘被拔了 / 目录暂时不可读）时**不许**清表 ——
    /// 那时候清等于把整个片库的历史一次抹掉。
    func testEmptyScanDoesNotPruneTable() async throws {
        let tableURL = root.appendingPathComponent("fps-table.json")
        var table = FrameRateTable()
        try table.upsert(FrameRateEntry(
            sourcePath: root.appendingPathComponent("gone.mp4").path, sourceSize: 1,
            sourceMtime: Date(timeIntervalSince1970: 0), fps: 60, durationSeconds: 1,
            derivativePath: nil, state: .needsConvert), to: tableURL)

        let emptyRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("p6-fpsq-empty-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: emptyRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: emptyRoot) }

        let queue = FpsTranscodeQueue(
            runner: runner, root: emptyRoot,
            availability: { .available(path: "/opt/homebrew/bin/ffmpeg") },
            freeSpaceProvider: { _ in nil },
            specProvider: { _ in VideoAssetMetadata(hasVideoTrack: true, frameRate: 60, durationSeconds: 10) },
            tableURL: tableURL)
        await queue.scan()

        XCTAssertEqual(FrameRateTable.load(from: tableURL).entries.count, 1,
                       "扫到 0 个文件时清表会把整个历史抹掉 —— 必须跳过")
    }

    // MARK: - 同名冲突（场景 F9）

    /// 降帧产物名同样是扁平的，不同子目录的同名源文件会撞车。
    func testSameStemInDifferentSubdirectoriesIsRefused() async {
        let dirA = root.appendingPathComponent("a", isDirectory: true)
        let dirB = root.appendingPathComponent("b", isDirectory: true)
        try? FileManager.default.createDirectory(at: dirA, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: dirB, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: dirA.appendingPathComponent("clip.mp4").path,
                                       contents: Data("1".utf8))
        FileManager.default.createFile(atPath: dirB.appendingPathComponent("clip.mp4").path,
                                       contents: Data("2".utf8))

        let queue = makeQueue()
        await queue.scan()

        let states = queue.jobs.map(\.state)
        XCTAssertEqual(states.filter { $0 == .pending }.count, 1, "只有一个能进队列")
        XCTAssertTrue(states.contains(.failed(reason: "name_collision")),
                      "撞车的那个必须报冲突，不能静默覆盖前一个的产物")
    }

    // MARK: - 暂停 / 取消（场景 G7 / G8）

    /// 暂停语义是「当前文件跑完再停」，drain 因此是**退出**而不是「挂起」。
    /// 退出时顺手把暂停标志清掉的话，UI 会从「已暂停」自己跳回 idle，
    /// 「继续」按钮随之置灰 —— 用户只能靠「开始转码」重来，且看不出刚才发生了什么。
    func testPauseSurvivesDrainExit() async {
        makeSource("a.mp4")
        let queue = makeQueue()
        await queue.scan()
        queue.pause()
        await queue.run()

        XCTAssertTrue(runner.calls.isEmpty, "暂停后不该开跑")
        XCTAssertTrue(queue.isPaused, "drain 退出不得顺手清掉暂停标志 —— UI 要凭它显示「已暂停」")

        queue.resume()
        XCTAssertFalse(queue.isPaused)
        await queue.run()
        XCTAssertEqual(runner.calls.count, 1, "继续之后必须真的接着跑")
    }

    /// 用户主动取消 ≠ 转码失败。旧实现把它记成 `.failed(exit_nonzero)`，
    /// UI 上写「失败 · exit_nonzero」，用户以为转码器坏了。
    func testCancelDuringJobMarksCancelledNotFailed() async {
        runner.isCancelled = true
        makeSource("a.mp4")
        makeSource("b.mp4")
        let queue = makeQueue()
        // 转码途中点取消：runner 已被终止（退出码非零），但原因是用户按的按钮。
        runner.onRun = { queue.cancel() }
        await queue.scan()
        await queue.run()

        XCTAssertEqual(queue.jobs.first?.state, .cancelled,
                       "用户主动取消不能显示成「失败 · exit_nonzero」")
    }

    /// 取消过的文件必须能重来 —— 表里要退回可重试态，否则它会被永久记成终态。
    func testCancelledJobReturnsToRetryableTableState() async throws {
        runner.isCancelled = true
        let source = makeSource("a.mp4")
        let tableURL = root.appendingPathComponent("fps-table.json")
        let queue = FpsTranscodeQueue(
            runner: runner, root: root,
            availability: { .available(path: "/opt/homebrew/bin/ffmpeg") },
            freeSpaceProvider: { _ in nil },
            specProvider: { _ in VideoAssetMetadata(hasVideoTrack: true, frameRate: 60, durationSeconds: 10) },
            tableURL: tableURL)
        runner.onRun = { queue.cancel() }
        await queue.scan()
        await queue.run()

        let state = FrameRateTable.load(from: tableURL)
            .entry(for: source.resolvingSymlinksInPath())?.state
        XCTAssertNotEqual(state, .failed, "取消不是失败，表里不该落 .failed")
        XCTAssertEqual(state?.recovered, .needsConvert, "取消过的文件必须能重新排队")
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

    // MARK: - 产物目录排除（场景 H6）

    /// 排除规则必须与 `MediaLibrary` 一致 —— 那里是大小写不敏感的。
    /// 用户在壁纸目录里放了个小写 `converted/`，降帧就会把产物自己再降一遍帧，
    /// 而根扫描根本不会把它算进播放清单（两边对同一件事看法不同）。
    func testScanSkipsLowercaseConvertedDirectory() async {
        let lower = root.appendingPathComponent("converted", isDirectory: true)
        try? FileManager.default.createDirectory(at: lower, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: lower.appendingPathComponent("prod-30fps.mp4").path,
                                       contents: Data("d".utf8))

        let queue = makeQueue()
        await queue.scan()
        XCTAssertTrue(queue.jobs.isEmpty,
                      "小写 converted/ 同样是产物目录，必须整棵排除（与 MediaLibrary 同一套规则）")
    }

    // MARK: - 换目录（场景 H4 / G9）

    /// 用户在设置里换了壁纸目录，**不重启 app**：降帧队列必须扫新目录、产物也落在新目录。
    /// `init(root:)` 在构造时固化目录 → 换完之后扫的还是旧目录，产物写进用户看不到的地方。
    func testRootProviderFollowsFolderChange() async {
        let secondRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("p6-fpsq-2-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: secondRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: secondRoot) }
        FileManager.default.createFile(
            atPath: secondRoot.appendingPathComponent("moved.mp4").path,
            contents: Data("s".utf8))

        var current = root!
        let queue = FpsTranscodeQueue(
            runner: runner,
            rootProvider: { current },
            availability: { .available(path: "/opt/homebrew/bin/ffmpeg") },
            freeSpaceProvider: { _ in nil },
            specProvider: { _ in VideoAssetMetadata(hasVideoTrack: true, frameRate: 60, durationSeconds: 10) },
            tableURL: root.appendingPathComponent("fps-table.json"))
        current = secondRoot

        await queue.scan()
        XCTAssertEqual(queue.jobs.count, 1, "换目录后必须扫新目录里的那个文件")
        XCTAssertTrue(queue.jobs.first?.sourceURL.lastPathComponent == "moved.mp4")

        await queue.run()
        let product = secondRoot
            .appendingPathComponent(MediaLibrary.excludedDirectoryName)
            .appendingPathComponent("moved-30fps.mp4")
        XCTAssertTrue(FileManager.default.fileExists(atPath: product.path),
                      "产物必须落在新目录的 Converted/ 下")
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(MediaLibrary.excludedDirectoryName)
                    .appendingPathComponent("moved-30fps.mp4").path),
            "旧目录不该出现这个产物")
    }
}