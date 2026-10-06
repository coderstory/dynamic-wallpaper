import XCTest
@testable import PicCore

/// `FakeRunner` 是进程外零调用的替身：自己写 .tmp 文件、返回可控退出码 —— 全套测试零真实转码、零真实进程。
@MainActor
final class TranscodeQueueTests: XCTestCase {

    /// 文件内替身，不要与 `FpsTranscodeQueueTests.swift` 里那份合并 —— 跨文件耦合后失败时分不清是替身坏了还是被测代码坏了。
    final class FakeRunner: TranscodeRunning, @unchecked Sendable {
        struct Call {
            let tmpPath: String
            let arguments: [String]
        }

        private(set) var calls: [Call] = []
        var exitStatus: Int32 = 0

        func run(ffmpegPath: String, arguments: [String], outputTemporaryPath: String,
                 onProgressLine: @escaping @Sendable (String) -> Void) async -> Int32 {
            calls.append(Call(tmpPath: outputTemporaryPath, arguments: arguments))
            FileManager.default.createFile(
                atPath: outputTemporaryPath, contents: Data("fake-payload".utf8))
            onProgressLine("frame=1")
            onProgressLine("out_time_ms=500000")
            return exitStatus
        }
    }

    private var root: URL!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("p6-0603-q-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        root = nil
        super.tearDown()
    }

    @discardableResult
    private func makeSource(_ name: String = "sample.mkv") -> URL {
        let url = root.appendingPathComponent(name)
        try? "placeholder-mkv".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func makeQueue(
        runner: FakeRunner,
        availability: @escaping () -> FFmpegToolStatus = { .available(path: "/opt/homebrew/bin/tool") },
        freeSpace: @escaping (URL) -> Int64? = { _ in 1_000_000_000 }
    ) -> TranscodeQueue {
        TranscodeQueue(runner: runner,
                       naming: TranscodeOutputNaming(root: root),
                       availability: availability,
                       freeSpaceProvider: freeSpace,
                       durationProvider: { _ in nil })
    }

    func testSuccessfulJobRenamesTmpToMp4AndKeepsSource() async throws {
        let source = makeSource()
        let runner = FakeRunner()
        let queue = makeQueue(runner: runner)

        queue.enqueue(sources: [source])
        await queue.run()

        let naming = TranscodeOutputNaming(root: root)
        XCTAssertEqual(queue.jobs.first?.state, .succeeded)
        XCTAssertTrue(FileManager.default.fileExists(atPath: naming.outputURL(for: source).path),
                      "产物 .mp4 必须存在")
        XCTAssertFalse(FileManager.default.fileExists(atPath: naming.temporaryURL(for: source).path),
                       ".tmp 必须被 rename 走")
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path),
                      "源文件必须保留（TRANS-04）")
        let sourceText = try String(contentsOf: source, encoding: .utf8)
        XCTAssertEqual(sourceText, "placeholder-mkv", "源文件内容原封不动")
    }

    func testFailedJobCleansTmpAndMarksFailed() async {
        let source = makeSource()
        let runner = FakeRunner()
        runner.exitStatus = 1
        let queue = makeQueue(runner: runner)

        queue.enqueue(sources: [source])
        await queue.run()

        let naming = TranscodeOutputNaming(root: root)
        XCTAssertEqual(queue.jobs.first?.state, .failed(reason: "exit_nonzero"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: naming.temporaryURL(for: source).path),
                       ".tmp 必须被清理")
        XCTAssertFalse(FileManager.default.fileExists(atPath: naming.outputURL(for: source).path),
                       "失败不得留半成品 .mp4")
    }

    /// 来源化删除策略：自动来源（`deletesSource=true`）成功后删源、手动来源保留。
    func testAutoSourceDeletedAfterSuccessAndUserSourceKept() async {
        let autoSource = makeSource("auto.mkv")
        let userSource = makeSource("user-picked.mkv")
        let runner = FakeRunner()
        let queue = makeQueue(runner: runner)

        queue.enqueue(sources: [autoSource], deletesSource: true)
        queue.enqueue(sources: [userSource], deletesSource: false)
        await queue.run()

        XCTAssertEqual(queue.jobs.first { $0.sourceURL == autoSource }?.deletesSource, true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: autoSource.path),
                       "自动来源的源文件转码成功后必须被删除")
        XCTAssertTrue(FileManager.default.fileExists(atPath: userSource.path),
                      "手动来源的源文件必须保留")
        XCTAssertEqual(queue.jobs.first { $0.sourceURL == userSource }?.deletesSource, false)
    }

    /// 转码删源必须走废纸篓，不能 `removeItem` —— 转码产物与源同名不同后缀，
    /// 一次误判就是不可恢复的素材丢失。用注入通道判据：替身不真删，所以
    /// 「通道被调用」与「文件还在」同时成立才能证明走的是废纸篓那条路。
    func testAutoSourceGoesToTrashChannelNotRemoveItem() async {
        let source = makeSource("auto.mkv")
        let runner = FakeRunner()
        var trashed: [URL] = []
        let queue = makeQueue(runner: runner, trashProvider: { url in trashed.append(url) })

        queue.enqueue(sources: [source], deletesSource: true)
        await queue.run()

        XCTAssertEqual(queue.jobs.first?.state, .succeeded, "前置：必须真的转成功才谈删源")
        XCTAssertEqual(trashed.map(\.path), [source.path],
                       "删源必须走废纸篓通道 —— 直接 removeItem 时这里会是空")
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path),
                      "替身不真删；文件还在说明删除确实交给了注入的通道")
    }

    /// 废纸篓失败（只读卷 / 权限）不得把 job 打成失败 —— 产物已经落盘了。
    func testTrashFailureKeepsJobSucceeded() async {
        let source = makeSource("auto.mkv")
        let runner = FakeRunner()
        let queue = makeQueue(runner: runner, trashProvider: { _ in throw CocoaError(.fileWriteNoPermission) })

        queue.enqueue(sources: [source], deletesSource: true)
        await queue.run()

        XCTAssertEqual(queue.jobs.first?.state, .succeeded,
                       "删源失败不影响转码结果：产物在，源也还在，下轮被幂等跳过")
    }

    /// 换目录（不重启 app）：产物必须落进新目录。
    func testRootProviderFollowsFolderChange() async {
        let secondRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("p6-trq-2-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: secondRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: secondRoot) }

        let source = secondRoot.appendingPathComponent("moved.mkv")
        try? "placeholder".write(to: source, atomically: true, encoding: .utf8)

        var current = root!
        let queue = TranscodeQueue(
            runner: FakeRunner(),
            naming: TranscodeOutputNaming(rootProvider: { current }),
            availability: { .available(path: "/opt/homebrew/bin/tool") },
            freeSpaceProvider: { _ in 1_000_000_000 },
            durationProvider: { _ in nil },
            trashProvider: { _ in })
        current = secondRoot

        queue.enqueue(sources: [source])
        await queue.run()

        let product = secondRoot
            .appendingPathComponent(MediaLibrary.excludedDirectoryName)
            .appendingPathComponent("moved.mp4")
        XCTAssertTrue(FileManager.default.fileExists(atPath: product.path),
                      "换目录后产物必须落在新目录的 Converted/ 下")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.appendingPathComponent(MediaLibrary.excludedDirectoryName)
                .appendingPathComponent("moved.mp4").path),
            "旧目录不该出现这个产物")
    }

    // MARK: - 同名冲突（场景 F9）

    /// 产物名是扁平的 `<stem>.mp4`，递归扫描下不同子目录的同名源文件算出同一个产物路径。
    /// 不拦住的话后跑的那个静默覆盖前一个的产物 —— 一份素材无声消失。
    func testSameStemInDifferentSubdirectoriesIsRefused() async {
        let dirA = root.appendingPathComponent("a", isDirectory: true)
        let dirB = root.appendingPathComponent("b", isDirectory: true)
        try? FileManager.default.createDirectory(at: dirA, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: dirB, withIntermediateDirectories: true)
        let first = dirA.appendingPathComponent("clip.mkv")
        let second = dirB.appendingPathComponent("clip.mkv")
        try? "one".write(to: first, atomically: true, encoding: .utf8)
        try? "two".write(to: second, atomically: true, encoding: .utf8)

        let runner = FakeRunner()
        let queue = makeQueue(runner: runner)
        queue.enqueue(sources: [first, second])
        await queue.run()

        XCTAssertEqual(queue.jobs.first { $0.sourceURL == first }?.state, .succeeded)
        XCTAssertEqual(queue.jobs.first { $0.sourceURL == second }?.state,
                       .failed(reason: "name_collision"),
                       "同名产物必须拒绝，不能静默覆盖")
        XCTAssertEqual(runner.calls.count, 1, "冲突的那个根本不该开跑")
    }

    // MARK: - 删源标记（场景 N6）

    /// 打开转码页只是看一眼 —— 入队时不该把素材标记成「成功即永久删除」。
    /// 标记只在用户真的点「开始转码」那一刻才落位。
    func testSourceDeletionIsArmedOnlyWhenStartIsPressed() async {
        let source = makeSource("auto.mkv")
        var trashed: [URL] = []
        let queue = makeQueue(runner: FakeRunner(), trashProvider: { url in trashed.append(url) })

        queue.enqueue(sources: [source], deletesSource: false)
        XCTAssertFalse(queue.jobs.first?.deletesSource ?? true,
                       "扫一遍就标删源 = 用户只是切过来看一眼就丢了素材")

        queue.armSourceDeletion(for: [source])
        XCTAssertTrue(queue.jobs.first?.deletesSource ?? false, "点了开始才押上")

        await queue.run()
        XCTAssertEqual(trashed.map(\.path), [source.path], "押上之后确实走删源通道")
    }

    func testFailedJobKeepsAutoSource() async {
        let source = makeSource()
        let runner = FakeRunner()
        runner.exitStatus = 1
        let queue = makeQueue(runner: runner)

        queue.enqueue(sources: [source], deletesSource: true)
        await queue.run()

        XCTAssertEqual(queue.jobs.first?.state, .failed(reason: "exit_nonzero"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path),
                      "失败不得删源（删除只挂在成功落盘上）")
    }

    func testUpToDateProductIsSkippedWithoutRunner() async throws {
        let source = makeSource()
        let naming = TranscodeOutputNaming(root: root)
        // 源 mtime 拨回 60 秒前，产物「现在」创建 → 产物必然更新，skipDecision 为真。
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -60)], ofItemAtPath: source.path)
        try FileManager.default.createDirectory(
            at: naming.convertedDirectoryURL(), withIntermediateDirectories: true)
        try "existing-product".write(
            to: naming.outputURL(for: source), atomically: true, encoding: .utf8)

        let runner = FakeRunner()
        let queue = makeQueue(runner: runner)
        queue.enqueue(sources: [source])
        await queue.run()

        XCTAssertEqual(queue.jobs.first?.state, .skipped)
        XCTAssertEqual(runner.calls.count, 0, "skipDecision 为真时 runner 必须零调用")
    }

    /// 串行是结构性的 —— for 循环里逐个 await，不建 Task 组；tmpPath 顺序必须等于入队顺序。
    /// 全部 job 都命中幂等跳过时一个 runner 都没调用 —— 这时候不该通知装配层去重扫：
    /// `onBatchFinished` 接的是全库重扫，没有新产物落地却扫一次是没有来由的开销。
    func testSkippedBatchDoesNotAnnounceBatchFinished() async {
        let source = makeSource()
        let runner = FakeRunner()
        let queue = makeQueue(runner: runner)
        var batchFinishes = 0
        queue.onBatchFinished = { batchFinishes += 1 }

        queue.enqueue(sources: [source])
        await queue.run()
        XCTAssertEqual(batchFinishes, 1, "第一次真的转了一个 job")

        let runnerCallsAfterFirstRun = runner.calls.count
        await queue.run()   // 第二次走幂等跳过（产物已经比源新）
        XCTAssertEqual(runner.calls.count, runnerCallsAfterFirstRun, "第二次不该再进 runner")
        XCTAssertEqual(batchFinishes, 1, "一个 job 都没真跑 → 不许再触发重扫")
    }

    func testJobsRunSeriallyInEnqueueOrder() async {
        let first = makeSource("a.mkv")
        let second = makeSource("b.mkv")
        let third = makeSource("c.mkv")
        let naming = TranscodeOutputNaming(root: root)
        let runner = FakeRunner()
        let queue = makeQueue(runner: runner)

        queue.enqueue(sources: [first, second, third])
        await queue.run()

        XCTAssertEqual(runner.calls.count, 3)
        XCTAssertEqual(runner.calls.map { $0.tmpPath },
                       [first, second, third].map { naming.temporaryURL(for: $0).path },
                       "runner 调用顺序必须等于入队顺序")
    }

    func testInsufficientDiskSpaceFailsBeforeRunner() async {
        let source = makeSource()
        let runner = FakeRunner()
        // 1 字节 < 源文件（14 字节）→ 拦截。
        let queue = makeQueue(runner: runner, freeSpace: { _ in 1 })

        queue.enqueue(sources: [source])
        await queue.run()

        XCTAssertEqual(queue.jobs.first?.state, .failed(reason: "disk_space"))
        XCTAssertEqual(runner.calls.count, 0, "磁盘预检不过绝不 spawn")
    }

    func testUnavailableFFmpegFailsWithoutSpawn() async {
        let source = makeSource()
        let runner = FakeRunner()
        let queue = makeQueue(runner: runner, availability: { .unavailable })

        queue.enqueue(sources: [source])
        await queue.run()

        XCTAssertEqual(queue.jobs.first?.state, .failed(reason: "ffmpeg_unavailable"))
        XCTAssertEqual(runner.calls.count, 0, "不可用绝不 spawn")
    }
}
