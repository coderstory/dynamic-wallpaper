import XCTest
@testable import PicCore

/// 转码执行期间主 actor 必须保持可服务。判据是「run 尚未返回时 percent 已被观察到非 nil」—— 同步 `waitUntilExit` 冻住 `@MainActor` 时观察窗一次都进不去（实测 0，修好后 130~170）。瞬时替身挡不住这类 BLOCKER，必须用真进程慢桩。
///
/// 桩是 `/bin/sh` + `sleep`，零编码负载。不要为了「更真实」把它换成真转码器。
@MainActor
final class TranscodeMainActorFreezeTests: XCTestCase {

    /// 真 `ProcessTranscodeRunner` + `/bin/sh -c 'printf…; sleep…'`，把真实长时进程接进真实队列。
    private final class SlowShellRunner: TranscodeRunning {
        private let script: String
        init(script: String) { self.script = script }

        func run(ffmpegPath: String, arguments: [String], outputTemporaryPath: String,
                 onProgressLine: @escaping @Sendable (String) -> Void) async -> Int32 {
            await ProcessTranscodeRunner().run(
                ffmpegPath: "/bin/sh", arguments: ["-c", script, outputTemporaryPath],
                outputTemporaryPath: outputTemporaryPath, onProgressLine: onProgressLine)
        }
    }

    private var root: URL!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("p6-freeze-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        root = nil
        super.tearDown()
    }

    func testProgressReachesMainActorWhileRunIsStillInFlight() async throws {
        let source = root.appendingPathComponent("sample.mkv")
        try "placeholder-mkv".write(to: source, atomically: true, encoding: .utf8)

        // 9 行进度、约 0.9s 进程存活；末尾把占位 payload 写进 tmp（走成功路径）。
        // tmp 路径以 `$0` 传进桩（`-c script <path>`）—— 桩 argv 不吃队列那套 ffmpeg 参数。
        let script = """
        printf 'frame=1\\nout_time_ms=100000000\\n'; sleep 0.3
        printf 'frame=2\\nout_time_ms=400000000\\n'; sleep 0.3
        printf 'frame=3\\nout_time_ms=700000000\\n'; sleep 0.3
        printf payload > "$0"
        """
        let queue = TranscodeQueue(
            runner: SlowShellRunner(script: script),
            naming: TranscodeOutputNaming(root: root),
            availability: { .available(path: "/bin/sh") },
            freeSpaceProvider: { _ in 1_000_000_000 },
            durationProvider: { _ in 10 })

        queue.enqueue(sources: [source])
        let runTask = Task { @MainActor in await queue.run() }

        // 起步窗：等 job 进 .running。超时即判「run 没跑起来」。
        let deadline = Date().addingTimeInterval(10)
        while queue.jobs.first?.state != .running && Date() < deadline {
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTAssertEqual(queue.jobs.first?.state, .running, "job 必须在 10s 内进 running")

        // 观察窗：state 仍是 .running（即 run 未返回）期间读到 percent 非 nil 的次数。
        // 主 actor 被同步 waitUntilExit 冻住时，这个循环一次都跑不起来。
        var progressDuringRun = 0
        while queue.jobs.first?.state == .running {
            if queue.jobs.first?.percent != nil { progressDuringRun += 1 }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        await runTask.value

        print("PIC_TRC_PROGRESS_DURING_RUN=\(progressDuringRun)")
        XCTAssertGreaterThan(progressDuringRun, 0,
                             "run 期间必须已收到进度回调（同步 waitUntilExit 会让它恒为 0）")
        XCTAssertEqual(queue.jobs.first?.state, .succeeded)
        XCTAssertNotNil(queue.jobs.first?.percent, "收尾 percent 必须存在")
    }
}