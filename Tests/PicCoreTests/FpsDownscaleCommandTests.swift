import XCTest
@testable import PicCore

/// 降帧 argv —— 逐 token 断言，零 ffmpeg 调用。
final class FpsDownscaleCommandTests: XCTestCase {

    private let input = URL(fileURLWithPath: "/tmp/p6-fps/样本 movie.mkv")
    private let output = URL(fileURLWithPath: "/tmp/p6-fps/Converted/样本 movie-30fps.mp4")

    /// 期望 argv 手写，**绝不从产品代码生成**（那样等于没测）。
    private var expectedTokens: [String] {
        [
            "-nostdin", "-y",
            "-i", "/tmp/p6-fps/样本 movie.mkv",
            "-map", "0:v:0",
            "-map", "0:a:0?",
            "-c:v", "libx265",
            "-preset", "fast",
            "-crf", "20",
            "-vf", "fps=30,scale=-2:1440",
            "-tag:v", "hvc1",
            "-pix_fmt", "yuv420p",
            "-c:a", "aac",
            "-b:a", "192k",
            "-sn", "-dn",
            "-movflags", "+faststart",
            "-progress", "pipe:1",
            "-nostats",
            "/tmp/p6-fps/Converted/样本 movie-30fps.mp4",
        ]
    }

    func testArgumentsMatchExpectedTokenSequenceExactly() {
        XCTAssertEqual(FpsDownscaleCommand.arguments(input: input, output: output),
                       expectedTokens, "argv 必须逐 token 相等")
    }

    /// 含空格中文的路径必须是单个元素 —— 拼字符串会被解释器切成两半。
    func testPathWithSpacesAndChineseStaysOneToken() {
        let argv = FpsDownscaleCommand.arguments(input: input, output: output)
        XCTAssertTrue(argv.contains("/tmp/p6-fps/样本 movie.mkv"))
        XCTAssertFalse(argv.contains { $0.contains("样本 movie.mkv ") },
                       "路径不能被拆成两半")
    }

    /// ⚠️ 漏掉 tag 会**静默**落到软解 —— 更慢更烫且不报错，肉眼看不出来。
    /// 这是本文件最要紧的一条断言。
    func testHvc1TagIsPresentForHardwareDecode() {
        let argv = FpsDownscaleCommand.arguments(input: input, output: output)
        guard let index = argv.firstIndex(of: "-tag:v") else {
            return XCTFail("argv 必须带 -tag:v，否则 Apple Silicon 上静默软解")
        }
        XCTAssertEqual(argv[index + 1], "hvc1")
    }

    /// 滤镜链顺序：先减帧再缩像素，省掉一半重采样。反了会先缩 60 帧再丢 30 帧。
    func testFilterChainCapsFramerateBeforeScaling() {
        let argv = FpsDownscaleCommand.arguments(input: input, output: output)
        guard let vf = argv.firstIndex(of: "-vf") else { return XCTFail("argv 必须带 -vf") }
        let graph = argv[vf + 1]
        let fps = graph.range(of: "fps=")
        let scale = graph.range(of: "scale=")
        XCTAssertNotNil(fps)
        XCTAssertNotNil(scale)
        XCTAssertLessThan(fps!.lowerBound, scale!.lowerBound, "fps 必须在 scale 之前")
    }

    func testCapsAreThirtyFpsAnd1440Height() {
        XCTAssertEqual(FpsDownscaleCommand.maxFrameRate, 30)
        XCTAssertEqual(FpsDownscaleCommand.maxHeight, 1440)
    }

    /// 恰好 30 不算超 —— NTSC 的 29.97 也走这条路。
    func testExactlyThirtyIsNotDownscaled() {
        XCTAssertFalse(VideoAssetMetadata(hasVideoTrack: true, frameRate: 30).needsDownscale())
        XCTAssertFalse(VideoAssetMetadata(hasVideoTrack: true, frameRate: 29.97).needsDownscale())
    }

    func testAboveThirtyIsDownscaled() {
        XCTAssertTrue(VideoAssetMetadata(hasVideoTrack: true, frameRate: 60).needsDownscale())
        XCTAssertTrue(VideoAssetMetadata(hasVideoTrack: true, frameRate: 120).needsDownscale())
    }

    /// 读不到帧率时按「不降」——宁可文件大一点，不在元数据缺失时猜错画质。
    func testUnknownFrameRateIsNotDownscaled() {
        XCTAssertFalse(VideoAssetMetadata(hasVideoTrack: true, frameRate: nil).needsDownscale())
    }

    func testDerivativeNameGetsDistinctSuffix() {
        XCTAssertEqual(
            FpsDownscaleCommand.derivativeName(for: URL(fileURLWithPath: "/a/b/clip.mkv")),
            "clip-30fps.mp4", "后缀用来和转码产物（同 stem 无后缀）区分")
    }
}