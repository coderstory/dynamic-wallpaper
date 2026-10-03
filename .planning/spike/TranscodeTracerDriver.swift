// TranscodeTracerDriver.swift —— Plan 06-03 T2 的一次性 throwaway 执行 tracer 驱动。
//
// 目的：一条命令的活体证据，把 06-01/06-02/06-03 的全部纯件串成端到端数据路径：
//   mkv 候选被找出 → argv 28 token 构造 → 审计串带 nice 前缀 → 假 runner 队列
//   一次调用 → Converted/sample.mp4 存在且 .tmp/源原状 → job 终态 succeeded →
//   ConvertedLibrary 判可播并进合并清单 → 再过滤零待转（回流闭环）→
//   二次入队判 skipped 且零 spawn → 每轮排空触发 onBatchFinished。
//
// 纪律（照 .planning/spike/MediaLibraryDriver.swift）：
//   ① 每行 print 后立刻 fflush(stdout) —— 进程可能被 kill。
//   ② 人造临时根（temporaryDirectory + UUID），绝不碰真实媒体目录（D-22）。
//   ③ FakeRunner 是进程外零调用的内存替身 —— 本 driver 连真 Process 都不起（C6）；
//      availability 的返回值是传给 FakeRunner 的数据，不是任何被执行的命令。

import Foundation

/// 每行立刻 flush —— 进程可能被 kill，不能靠退出时统一 flush。
var tracerLineCount = 0

func emit(_ line: String) {
    print(line)
    fflush(stdout)
    tracerLineCount += 1
}

/// 假 runner：写几字节 .tmp、返回 0、发两行进度样本
/// （durationProvider 传 nil → percent 走 nil 路径，这也是 nil 安全的活体读数）。
final class TracerFakeRunner: TranscodeRunning {
    private(set) var calls: [String] = []

    func run(ffmpegPath: String, arguments: [String], outputTemporaryPath: String,
             onProgressLine: @escaping (String) -> Void) -> Int32 {
        calls.append(outputTemporaryPath)
        FileManager.default.createFile(
            atPath: outputTemporaryPath, contents: Data("fake-mp4-payload".utf8))
        onProgressLine("frame=1")
        onProgressLine("out_time_ms=500000")
        return 0
    }
}

/// 全收探针：证据只验证「第二入口看得见产物」，不验证解码真伪。
struct TracerProbe: VideoAssetProbe {
    func hasVideoTrack(_ url: URL) async -> Bool { true }
}

@main
struct TranscodeTracerDriver {
    @MainActor
    static func main() async {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("p6-0603-tracer-\(UUID().uuidString)", isDirectory: true)
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let source = root.appendingPathComponent("sample.mkv")
        fm.createFile(atPath: source.path, contents: Data("placeholder-mkv".utf8))

        emit("PIC_TRC_ROOT=\(root.path)")

        let naming = TranscodeOutputNaming(root: root)

        let candidates = TranscodeCandidateFilter.candidates(in: root)
        emit("PIC_TRC_CANDIDATES=\(candidates.count)")

        let first = candidates[0]
        let temporaryURL = naming.temporaryURL(for: first)
        let argv = TranscodeCommand.arguments(input: first, output: temporaryURL)
        emit("PIC_TRC_ARGV_TOKENS=\(argv.count)")

        let toolPath = "/opt/homebrew/bin/ffmpeg"
        let display = TranscodeCommand.displayString(
            ffmpegPath: toolPath, input: first, output: temporaryURL)
        let displayOK = display.hasPrefix("nice -n 10") && display.contains(temporaryURL.path)
        emit("PIC_TRC_CMD_DISPLAY=\(displayOK ? "ok" : "bad")")

        let runner = TracerFakeRunner()
        var batchFinishedCount = 0
        let queue = TranscodeQueue(
            runner: runner,
            naming: naming,
            availability: { .available(path: toolPath) },
            freeSpaceProvider: { _ in 1_000_000_000 },
            durationProvider: { _ in nil })
        queue.onBatchFinished = { batchFinishedCount += 1 }

        queue.enqueue(sources: [first])
        await queue.run()
        emit("PIC_TRC_RUNNER_CALLS=\(runner.calls.count)")

        let product = naming.outputURL(for: first)
        emit("PIC_TRC_PRODUCT_EXISTS=\(fm.fileExists(atPath: product.path) ? 1 : 0)")
        emit("PIC_TRC_TMP_GONE=\(fm.fileExists(atPath: temporaryURL.path) ? 0 : 1)")
        emit("PIC_TRC_SOURCE_INTACT=\(fm.fileExists(atPath: source.path) ? 1 : 0)")

        let stateToken: String
        switch queue.jobs[0].state {
        case .pending:
            stateToken = "pending"
        case .running:
            stateToken = "running"
        case .succeeded:
            stateToken = "succeeded"
        case .skipped:
            stateToken = "skipped"
        case .failed:
            stateToken = "failed"
        }
        emit("PIC_TRC_JOB_STATE=\(stateToken)")

        // D-23 第二入口活体证明：产物在 Converted/ 里被第二扫描器收进可播清单。
        let convertedLibrary = ConvertedLibrary(probe: TracerProbe())
        let converted = (try? await convertedLibrary.scan(folder: root)) ?? []
        emit("PIC_TRC_CONVERTED_PLAYABLE=\(converted.count)")

        let fakeRootItem = VideoItem(url: root.appendingPathComponent("fake-root-item.mp4"))
        let merged = ConvertedLibrary.playbackItems(root: [fakeRootItem], converted: converted)
        emit("PIC_TRC_MERGED=\(merged.count)")

        // 回流闭环读数：候选再过 skipDecision（产物新鲜 → 无待转码输入）。
        // 裸 candidates 对已转码源恒非空（TRANS-04 源保留不删）；「回流」的定义
        // 是「还会被再次转码」，由 filter + skip 两道闸门联合判定。
        let refilter = TranscodeCandidateFilter.candidates(in: root)
            .filter { !naming.skipDecision(source: $0) }
        emit("PIC_TRC_REFILTER_CANDIDATES=\(refilter.count)")

        // 幂等：同一源二次入队 → 新 job 走 skipDecision → skipped、零重复 spawn。
        queue.enqueue(sources: [first])
        await queue.run()
        let secondPassSkipped: Bool
        if let last = queue.jobs.last, case .skipped = last.state {
            secondPassSkipped = true
        } else {
            secondPassSkipped = false
        }
        emit("PIC_TRC_SECOND_PASS_SKIPPED=\(secondPassSkipped ? 1 : 0)")
        emit("PIC_TRC_RUNNER_CALLS_TOTAL=\(runner.calls.count)")
        emit("PIC_TRC_BATCH_FINISHED=\(batchFinishedCount)")
        emit("PIC_TRC_LINES=\(tracerLineCount)")
    }
}
