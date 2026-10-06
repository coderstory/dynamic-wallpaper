import XCTest
@testable import PicCore

/// 取消打的是真实进程的 `terminate()`，替身打不到那条路，所以真 spawn `/bin/sh` 慢桩。
@MainActor
final class ProcessCancellationTests: XCTestCase {

    private var root: URL!

    override func setUp() async throws {
        try await super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("p6-cancel-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
        root = nil
        try await super.tearDown()
    }

    func testUncancelledRunReturnsZero() async {
        let runner = ProcessTranscodeRunner()
        let status = await runner.run(
            ffmpegPath: "/bin/sh",
            arguments: ["-c", "printf 'frame=1\\nprogress=end\\n'"],
            outputTemporaryPath: root.appendingPathComponent("a.tmp").path,
            onProgressLine: { _ in })
        XCTAssertEqual(status, 0)
    }

    /// 取消：跑到一半 terminate，必须返回而不是永久挂住 —— 不返回的话队列的 await 永远不回来，整个 tab 卡死。
    func testCancelTerminatesRunningProcessAndReturns() async throws {
        let runner = ProcessTranscodeRunner()
        let task = Task { () -> Int32 in
            await runner.run(
                ffmpegPath: "/bin/sh",
                arguments: ["-c", "sleep 30"],
                outputTemporaryPath: root.appendingPathComponent("b.tmp").path,
                onProgressLine: { _ in })
        }
        // 必须先等进程真起来再 cancel，否则可能打在 spawn 之前。
        try await Task.sleep(nanoseconds: 300_000_000)
        runner.cancel()

        let status = await task.value
        XCTAssertNotEqual(status, 0, "被取消的进程退出码必须非 0，队列据此判 failed 不落盘")
    }

    /// 取消后再 run 必须还能用 —— `Process` 实例不能被上一次的进程占住。
    func testRunnerIsReusableAfterCancel() async throws {
        let runner = ProcessTranscodeRunner()
        let first = Task { () -> Int32 in
            await runner.run(
                ffmpegPath: "/bin/sh", arguments: ["-c", "sleep 30"],
                outputTemporaryPath: root.appendingPathComponent("c.tmp").path,
                onProgressLine: { _ in })
        }
        try await Task.sleep(nanoseconds: 300_000_000)
        runner.cancel()
        _ = await first.value

        let status = await runner.run(
            ffmpegPath: "/bin/sh", arguments: ["-c", "printf 'x\\n'"],
            outputTemporaryPath: root.appendingPathComponent("d.tmp").path,
            onProgressLine: { _ in })
        XCTAssertEqual(status, 0, "取消过一次之后 runner 仍要能正常执行")
    }

    /// 暂停/取消会被连点，没有进程时 cancel 也不能崩。
    func testCancelWithNoRunningProcessIsSafe() {
        ProcessTranscodeRunner().cancel()
    }

    /// 本条只钉执行面：进程退出后 runner 不阻塞。暂停的「跑完当前文件才停」是队列侧状态机，不在这里。
    func testIsRunningIsFalseAfterProcessExits() async {
        let runner = ProcessTranscodeRunner()
        _ = await runner.run(
            ffmpegPath: "/bin/sh", arguments: ["-c", "printf 'frame=1\\n'"],
            outputTemporaryPath: root.appendingPathComponent("e.tmp").path,
            onProgressLine: { _ in })
        XCTAssertFalse(runner.isRunning, "进程退出后 isRunning 必须为 false")
    }

    /// stderr 挂了 Pipe 却不读时，缓冲区（~64KB）一满 ffmpeg 就阻塞在写 stderr 上永不退出 —— 表现是 waitUntilExit 挂住、队列卡死、CPU 归零。长视频必现（告警量足以填满管道）。
    func testLargeStderrOutputDoesNotHangTheProcess() async {
        let runner = ProcessTranscodeRunner()
        let status = await runner.run(
            ffmpegPath: "/bin/sh",
            // 输出量远超管道容量。
            arguments: ["-c", "i=0; while [ $i -lt 20000 ]; do echo \"stderr 填充行 $i\"; i=$((i+1)); done; printf 'frame=1\\n'"],
            outputTemporaryPath: root.appendingPathComponent("f.tmp").path,
            onProgressLine: { _ in })
        XCTAssertEqual(status, 0, "stderr 灌满管道时进程仍必须正常退出")
    }
}