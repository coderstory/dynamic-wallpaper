import XCTest
@testable import PicCore

/// 样本串全部硬编码（`-progress pipe:1` 的机器可读输出），零 ffmpeg 调用、不依赖 `fixtures/`，干净 clone 上 `swift test` 也必须绿。
final class ProgressParserTests: XCTestCase {

    /// 多行块按 `\n` 逐行喂给累加器 —— 与产品侧 `ProgressState.consume` 同一条路径。
    private func parse(_ chunk: String) -> ProgressParser.Snapshot {
        var accumulator = ProgressParser.Accumulator()
        return accumulator.consume(chunk)
    }

    func testParsesSampleChunkIntoSnapshot() {
        let chunk = """
        frame=120
        fps=61.5
        out_time_ms=2500000
        total_size=4096
        progress=continue
        """
        let snapshot = parse(chunk)
        XCTAssertEqual(snapshot, ProgressParser.Snapshot(
            frame: 120,
            outTimeUs: 2_500_000,
            isEnd: false
        ))
    }

    func testProgressEndFlagDetected() {
        let snapshot = parse("progress=end")
        XCTAssertTrue(snapshot.isEnd)
    }

    func testUnknownKeysAndGarbageLinesTolerated() {
        let chunk = """
        bitrate= 999.9kbits/s

        =novalue
        total garbage line
        frame=88
        """
        let snapshot = parse(chunk)
        XCTAssertEqual(snapshot.frame, 88)
    }

    func testPercentComputesRatioWithMicrosecondSemantics() {
        let snapshot = ProgressParser.Snapshot(
            frame: 120,
            outTimeUs: 2_500_000,
            isEnd: false
        )
        // out_time 是微秒：2_500_000 µs = 2.5 s，除以 10 s 时长 = 0.25。
        // 分母若错写成 1_000.0，这里得 250.0 转红。
        let result = ProgressParser.percent(snapshot: snapshot, durationSeconds: 10.0)
        guard let result else {
            XCTFail("expected non-nil percent for valid snapshot + duration")
            return
        }
        XCTAssertEqual(result, 0.25, accuracy: 0.0001)
    }

    func testPercentNilWhenDurationMissingOrZeroOrNoTimeYet() {
        let withTime = ProgressParser.Snapshot(
            frame: 1,
            outTimeUs: 2_500_000,
            isEnd: false
        )
        XCTAssertNil(ProgressParser.percent(snapshot: withTime, durationSeconds: nil))
        XCTAssertNil(ProgressParser.percent(snapshot: withTime, durationSeconds: 0))
        let noTime = ProgressParser.Snapshot(frame: nil, outTimeUs: nil, isEnd: false)
        XCTAssertNil(ProgressParser.percent(snapshot: noTime, durationSeconds: 10.0))
    }
}
