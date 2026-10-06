import XCTest
@testable import PicCore

/// argv 逐 token 断言，只断参数构造，绝不跑 ffmpeg（换台机器也必须照样过）。
final class TranscodeCommandTests: XCTestCase {

    private let input = URL(fileURLWithPath: "/tmp/p6-root/样本 movie.mkv")
    private let output = URL(fileURLWithPath: "/tmp/p6-root/Converted/样本 movie.mp4.tmp")

    /// 期望 argv 逐 token 手写，绝不从产品代码生成（那样等于没测）。含空格中文的路径必须是单个元素，顺带锁死「无字符串拼接」。
    private var expectedTokens: [String] {
        [
            "-nostdin", "-y",
            "-i", "/tmp/p6-root/样本 movie.mkv",
            "-map", "0:v:0",
            "-map", "0:a:0?",
            "-c:v", VideoEncoderProfile.encoder.ffmpegName,
            "-q:v", "65",
            "-pix_fmt", "yuv420p",
            "-tag:v", "hvc1",
            "-c:a", "aac",
            "-b:a", "192k",
            "-sn", "-dn",
            "-movflags", "+faststart",
            "-progress", "pipe:1",
            "-nostats",
            "-f", "mp4",
            "/tmp/p6-root/Converted/样本 movie.mp4.tmp"
        ]
    }

    func testArgumentsMatchExpectedTokenSequenceExactly() {
        XCTAssertEqual(TranscodeCommand.arguments(input: input, output: output), expectedTokens,
                       "argv 必须与锁定基线逐 token 相等（TEST-06 本体，不是子串包含）")
        XCTAssertEqual(expectedTokens.count, 30, "基线 argv 恰好 30 个 token")
    }

    /// ffmpeg 按最后一个扩展名判输出格式，`.tmp` 后缀会判成未知格式、muxer 初始化失败进程秒退，必须显式 `-f mp4`。
    func testExplicitMuxerSoTmpExtensionDoesNotBreakFormatDetection() {
        let argv = TranscodeCommand.arguments(input: input, output: output)
        guard let index = argv.firstIndex(of: "-f") else {
            return XCTFail("argv 必须带 -f mp4 —— .tmp 后缀会让 ffmpeg 判不出格式")
        }
        XCTAssertEqual(argv[index + 1], "mp4")
        XCTAssertEqual(argv[index + 2], output.path, "输出路径必须是 -f mp4 后的下一个 token")
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
