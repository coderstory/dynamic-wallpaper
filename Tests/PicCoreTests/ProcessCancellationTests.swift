import XCTest
@testable import PicCore

/// 取消/暂停的执行面 —— 真 spawn `/bin/sh` 慢桩，不用替身。
///
/// 为什么不用 FakeRunner：取消要打的是真实进程的 `terminate()`，替身打不到那条路。
@MainActor
final class ProcessCancellationTests: XCTestCase {

    private var root: URL!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("p6-cancel-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        root = nil
        super.tearDown()
    }

    /// 不取消：进程自己跑完，退出码 0。
    func testUncancelledRunReturnsZero() async {
        let runner = ProcessTranscodeRunner()
        let status = await runner.run(
            ffmpegPath: "/bin/sh",
            arguments: ["-c", "printf 'frame=1\\nprogress=end\\n'"],
            outputTemporaryPath: root.appendingPathComponent("a.tmp").path,
            onProgressLine: { _ in })
        XCTAssertEqual(status, 0)
    }

    /// 取消：跑到一半 terminate，**必须返回**而不是永久挂住。
    ///
    /// ⚠️ 这条是最要紧的：不取消的话队列的 await 永远不回来，整个 tab 卡死。
    func testCancelTerminatesRunningProcessAndReturns() async throws {
        let runner = ProcessTranscodeRunner()
        let task = Task { () -> Int32 in
            await runner.run(
                ffmpegPath: "/bin/sh",
                arguments: ["-c", "sleep 30"],
                outputTemporaryPath: root.appendingPathComponent("b.tmp").path,
                onProgressLine: { _ in })
        }
        // 让进程真的起来再取消 —— 否则可能打在 spawn 之前。
        try await Task.sleep(nanoseconds: 300_000_000)
        runner.cancel()

        let status = await task.value
        XCTAssertNotEqual(status, 0, "被取消的进程退出码必须非 0，队列据此判 failed 不落盘")
    }

    /// 取消后再 run 必须还能用 —— 句柄不能被上一次的进程占住。
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

    /// 没有进程在跑时 cancel 不能崩 —— 暂停/取消可能被连点。
    func testCancelWithNoRunningProcessIsSafe() {
        ProcessTranscodeRunner().cancel()
    }

    /// 暂停：本条只钉「跑完当前文件才停」的语义 —— 队列侧检查 pending 是否被拾取。
    /// 执行面本身无法表达暂停（那是队列的状态机），所以这里只确认 runner 不阻塞。
    func testIsRunningIsFalseAfterProcessExits() async {
        let runner = ProcessTranscodeRunner()
        _ = await runner.run(
            ffmpegPath: "/bin/sh", arguments: ["-c", "printf 'frame=1\\n'"],
            outputTemporaryPath: root.appendingPathComponent("e.tmp").path,
            onProgressLine: { _ in })
        XCTAssertFalse(runner.isRunning, "进程退出后 isRunning 必须为 false")
    }
}