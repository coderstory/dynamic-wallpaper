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
            "-c:v", VideoEncoderProfile.encoder.ffmpegName,
            "-q:v", "65",
            "-vf", "fps=30,scale=-2:1440",
            "-tag:v", "hvc1",
            "-pix_fmt", "yuv420p",
            "-c:a", "aac",
            "-b:a", "192k",
            "-sn", "-dn",
            "-movflags", "+faststart",
            "-progress", "pipe:1",
            "-nostats",
            "-f", "mp4",
            "/tmp/p6-fps/Converted/样本 movie-30fps.mp4",
        ]
    }

    /// ⚠️ 这条钉的是实测 bug：产物先写 `.tmp` 再 rename，而 ffmpeg 按**最后一个**
    /// 扩展名判格式 —— `x-30fps.mp4.tmp` 被判成未知格式，muxer 初始化失败，
    /// 进程秒退（报 "Unable to choose an output format"）。必须显式 `-f mp4`。
    func testExplicitMuxerSoTmpExtensionDoesNotBreakFormatDetection() {
        let argv = FpsDownscaleCommand.arguments(input: input, output: output)
        guard let index = argv.firstIndex(of: "-f") else {
            return XCTFail("argv 必须带 -f mp4 —— .tmp 后缀会让 ffmpeg 判不出格式")
        }
        XCTAssertEqual(argv[index + 1], "mp4")
    }

    /// `-f` 必须紧邻输出路径（ffmpeg 把它当作用于其后的输出）。
    func testFormatFlagPrecedesOutputPath() {
        let argv = FpsDownscaleCommand.arguments(input: input, output: output)
        let formatIndex = argv.firstIndex(of: "-f")!
        XCTAssertEqual(argv[formatIndex + 2], output.path, "输出路径必须是 -f mp4 后的下一个 token")
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
        XCTAssertFalse(FpsDownscaleCommand.needsDownscale(30))
        XCTAssertFalse(FpsDownscaleCommand.needsDownscale(29.97))
    }

    /// ⚠️ 这条钉的是真实数据里的 bug：`nominalFrameRate` 对 NTSC 源会读出
    /// 30.04 / 30.05 这类值（理论 29.97 或 30）。裸 `> 30` 会把它们全判成需降帧 ——
    /// 实测 491 个文件里有 3 个是这种情况，于是转码了根本不该转的片。
    func testFrameRateJustAboveThirtyIsNotDownscaled() {
        for fps in [30.04, 30.05, 30.001] {
            XCTAssertFalse(FpsDownscaleCommand.needsDownscale(fps),
                           "\(fps)fps 是 30 的浮点噪声，不该被判定为超标")
        }
    }

    /// 容差不能大到放过真的超标 —— 48/50fps 仍必须降。
    func testGenuinelyAboveThirtyStillDownscaled() {
        for fps in [48.0, 50.03, 59.92, 60.0, 120.0] {
            XCTAssertTrue(FpsDownscaleCommand.needsDownscale(fps), "\(fps)fps 确实超标，必须降")
        }
    }

    /// 容差的上界：35fps 必须仍判超标。容差放大到 5 时 48fps 照样会被降 ——
    /// 这条钉住「容差不能变成 5」而不是笼统地测「48 要降」。
    func testToleranceStaysTightAtThirtyFiveFps() {
        XCTAssertTrue(FpsDownscaleCommand.needsDownscale(35),
                      "35fps 明显超标 —— 容差若被放大到 5 这条会红")
        XCTAssertTrue(FpsDownscaleCommand.needsDownscale(40))
    }

    func testAboveThirtyIsDownscaled() {
        XCTAssertTrue(FpsDownscaleCommand.needsDownscale(60))
        XCTAssertTrue(FpsDownscaleCommand.needsDownscale(120))
    }

    /// 读不到帧率时按「不降」——宁可文件大一点，不在元数据缺失时猜错画质。
    /// 判据吃非可选 Double，nil 由队列侧提前挡掉。
    func testFrameRateNilIsDecidedByCallerNotPredicate() {
        XCTAssertNil(VideoAssetMetadata(hasVideoTrack: true, frameRate: nil).frameRate)
    }

    func testDerivativeNameGetsDistinctSuffix() {
        XCTAssertEqual(
            FpsDownscaleCommand.derivativeName(for: URL(fileURLWithPath: "/a/b/clip.mkv")),
            "clip-30fps.mp4", "后缀用来和转码产物（同 stem 无后缀）区分")
    }
}