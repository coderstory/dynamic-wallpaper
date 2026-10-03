import XCTest
@testable import PicCore

// 合规说明（红线）：本测试的桩二进制是 /bin/sh 跑 printf + echo —— 不是
// ffmpeg、不转码、毫秒级、零编码负载。它验证的是 Process / stdout 管道 /
// 退出码机制，不触「禁止真实转码调用」的禁令。任何情况下不得为了让测试
// 「更真实」而把桩换成真实转码器 —— 那是 779.9% CPU 事故的直接复发。
// 真转码只存在于手动 bench。
final class ProcessTranscodeRunnerTests: XCTestCase {

    /// 线程安全收集盒：onProgressLine 来自 readabilityHandler 的后台队列。
    private final class LineBox {
        private let lock = NSLock()
        private var lines: [String] = []

        func append(_ line: String) {
            lock.lock()
            lines.append(line)
            lock.unlock()
        }

        var snapshot: [String] {
            lock.lock()
            defer { lock.unlock() }
            return lines
        }
    }

    /// 桩链路全验证：spawn 真的发生（echo 产物落地）+ stdout 逐行喂到回调
    /// + 退出判定只认 terminationStatus。
    func testRunnerReportsProgressLinesAndExitStatusViaShellStub() {
        let tmpPath = NSTemporaryDirectory() + "p6-0603-stub-" + UUID().uuidString + ".out"
        defer { try? FileManager.default.removeItem(atPath: tmpPath) }

        let runner = ProcessTranscodeRunner()
        let box = LineBox()
        // printf 的换行传给 sh 时必须是字面 backslash-n（Swift 字符串里写 \\n），
        // 由 printf 自己解释成换行。
        let script = "printf 'frame=1\\nout_time_ms=500000\\nprogress=end\\n'; echo payload > '" + tmpPath + "'"

        let status = runner.run(
            ffmpegPath: "/bin/sh",
            arguments: ["-c", script],
            outputTemporaryPath: tmpPath
        ) { line in
            box.append(line)
        }

        XCTAssertEqual(status, 0, "sh 桩正常退出必须报 0（terminationStatus 是唯一成败判据）")
        XCTAssertTrue(box.snapshot.contains { $0.contains("out_time_ms=500000") },
                      "stdout 管道必须逐行喂到回调（不许丢半行）")
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmpPath),
                      "桩的 echo 产物必须落地 —— 证明 spawn 真的发生了")
    }
}
