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
