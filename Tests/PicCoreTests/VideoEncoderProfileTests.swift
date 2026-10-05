import XCTest
@testable import PicCore

/// 编码档 —— 降帧与转码共用同一份。
///
/// ⚠️ 这组测试的核心是「两边都引用同一个 profile」：两份独立 argv 会导致
/// 改了降帧忘了转码（这正是本文件存在的原因）。
final class VideoEncoderProfileTests: XCTestCase {

    private let input = URL(fileURLWithPath: "/tmp/p6-enc/源 movie.mkv")

    // MARK: - 降帧侧

    func testDownscaleUsesSharedProfile() {
        let argv = FpsDownscaleCommand.arguments(input: input, output: input)
        XCTAssertTrue(argv.contains(VideoEncoderProfile.encoder.ffmpegName),
                      "降帧必须用 profile 里的编码器")
        for token in VideoEncoderProfile.qualityTokens() {
            XCTAssertTrue(argv.contains(token), "降帧必须带 profile 的质量 token \(token)")
        }
    }

    func testDownscaleStillCarriesFpsAndScale() {
        let argv = FpsDownscaleCommand.arguments(input: input, output: input)
        XCTAssertTrue(argv.contains("fps=30,scale=-2:1440"), "降帧的滤镜链不能因为换编码器丢掉")
        XCTAssertTrue(argv.contains("hvc1"), "hvc1 tag 是硬解开关，任何编码器下都不能丢")
    }

    // MARK: - 转码侧

    func testTranscodeUsesSameSharedProfile() {
        let argv = TranscodeCommand.arguments(input: input, output: input)
        XCTAssertTrue(argv.contains(VideoEncoderProfile.encoder.ffmpegName),
                      "转码必须与降帧用同一个编码器")
        for token in VideoEncoderProfile.qualityTokens() {
            XCTAssertTrue(argv.contains(token), "转码必须带同一份质量 token \(token)")
        }
    }

    /// ⚠️ 这条钉的是本次要防的事故：两个 argv 各写各的编码器，
    /// 改了一边另一边没跟上，用户拿到的是两种画质。
    func testBothSidesShareExactlyOneEncoder() {
        XCTAssertTrue(TranscodeCommand.arguments(input: input, output: input)
            .contains(VideoEncoderProfile.encoder.ffmpegName))
        XCTAssertFalse(TranscodeCommand.arguments(input: input, output: input)
            .contains { $0 == "libx264" || $0 == "libx265" },
            "转码侧不得再硬编码别的编码器 —— profile 是唯一真相")
        XCTAssertFalse(FpsDownscaleCommand.arguments(input: input, output: input)
            .contains { $0 == "libx264" || $0 == "libx265" },
            "降帧侧同样")
    }

    // MARK: - profile 自身

    func testHardwareEncoderUsesQualityFlagNotCrf() {
        XCTAssertEqual(VideoEncoderProfile.Encoder.videotoolboxHEVC.qualityFlag, "-q:v")
        XCTAssertEqual(VideoEncoderProfile.Encoder.libx265.qualityFlag, "-crf")
    }

    /// videotoolbox 没有 preset 概念，传了会被忽略甚至报错 —— 不该带上。
    func testHardwareProfileOmitsPreset() {
        XCTAssertTrue(VideoEncoderProfile.encoder.isHardwareAccelerated)
        XCTAssertFalse(VideoEncoderProfile.qualityTokens().contains("-preset"),
                       "videotoolbox 不认 preset")
        XCTAssertFalse(VideoEncoderProfile.qualityTokens().contains("-crf"),
                       "videotoolbox 用 -q:v 不是 -crf")
    }
}