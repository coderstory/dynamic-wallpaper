import XCTest
@testable import PicCore

/// TEST-06 / TRANS-03 参数侧 —— argv 逐 token 断言（C6：只断参数构造，绝不跑 ffmpeg）。
final class TranscodeCommandTests: XCTestCase {

    private let input = URL(fileURLWithPath: "/tmp/p6-root/样本 movie.mkv")
    private let output = URL(fileURLWithPath: "/tmp/p6-root/Converted/样本 movie.mp4.tmp")

    /// 期望 argv —— 逐 token 手写，绝不从产品代码生成（从产品代码生成期望值等于没测）。
    /// 含空格中文的路径必须是单个元素，顺带锁死「无字符串拼接」。
    private var expectedTokens: [String] {
        [
            "-nostdin", "-y",
            "-i", "/tmp/p6-root/样本 movie.mkv",
            "-map", "0:v:0",
            "-map", "0:a:0?",
            "-c:v", "libx264",
            "-preset", "medium",
            "-crf", "18",
            "-pix_fmt", "yuv420p",
            "-c:a", "aac",
            "-b:a", "192k",
            "-sn", "-dn",
            "-movflags", "+faststart",
            "-progress", "pipe:1",
            "-nostats",
            "/tmp/p6-root/Converted/样本 movie.mp4.tmp"
        ]
    }

    func testArgumentsMatchExpectedTokenSequenceExactly() {
        XCTAssertEqual(TranscodeCommand.arguments(input: input, output: output), expectedTokens,
                       "argv 必须与锁定基线逐 token 相等（TEST-06 本体，不是子串包含）")
        XCTAssertEqual(expectedTokens.count, 28, "基线 argv 恰好 28 个 token")
    }

    func testDisplayStringStartsWithNiceAndJoinsSameTokens() {
        let ffmpegPath = "/opt/homebrew/bin/ffmpeg"
        let display = TranscodeCommand.displayString(ffmpegPath: ffmpegPath, input: input, output: output)
        XCTAssertTrue(display.hasPrefix("nice -n 10 /opt/homebrew/bin/ffmpeg -nostdin -y -i "),
                      "审计串以 nice -n 10 + ffmpeg 路径 + 前三个 token 开头（C11 低优先级的纯函数侧）")
        XCTAssertEqual(display, "nice -n 10 " + ffmpegPath + " " + expectedTokens.joined(separator: " "),
                       "审计串必须与 argv 同 token、空格拼接")
    }

    func testBaselineConstantsAreCrfEighteenPresetMedium() {
        XCTAssertEqual(TranscodeCommand.baselineCRF, 18,
                       "C7 实测前的基线 CRF 是 18（bench 改终值时同 commit 更新本条，防意外漂移）")
        XCTAssertEqual(TranscodeCommand.baselinePreset, "medium",
                       "基线 preset 是 medium（同上）")
    }

    func testAudioMapIsOptionalAndSubtitleDataStreamsDropped() {
        let argv = TranscodeCommand.arguments(input: input, output: output)
        // 这三处丢了测试 1 也会红，但那条红看不出「为什么」；本条把原因钉进测试报告。
        XCTAssertTrue(argv.contains("0:a:0?"), "音轨 map 必须带 ?（无音轨源不报错，Q3）—— 问号是 token 的一部分")
        XCTAssertTrue(argv.contains("-sn"), "字幕流必须丢弃（P3：MKV 内嵌字幕进 MP4 muxer 会报错）")
        XCTAssertTrue(argv.contains("-dn"), "数据附件必须丢弃（P3：字体附件等）")
    }
}
