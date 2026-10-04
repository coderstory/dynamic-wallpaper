import Foundation

/// 降帧 argv 构造 —— 纯参数逻辑，零进程执行（与 `TranscodeCommand` 同形，各管各的档）。
///
/// 与转码是**同一个 ffmpeg，只是参数不同**：转码固定 H.264 换容器，降帧固定
/// HEVC 换规格。所以这里是独立类型而不是 `TranscodeCommand` 的一个分支 ——
/// 两者的 preset / crf / 编码器全不一样，混在一个函数里迟早互相拖累。
///
/// ⚠️ argv 一律逐 token 数组，绝不拼字符串：路径含空格中文时拼出来的串会被
/// 解释器切成两半（含空格中文的路径必须是单个元素，这是既有纪律）。
public enum FpsDownscaleCommand {

    // MARK: - 档位常量（不做配置化 —— 用户不调这个）

    /// 帧率封顶。**高于**它才需要降，恰好等于不动。
    public static let maxFrameRate: Double = 30

    /// 高度上限。`scale=-2:1440` 只给高、宽按比例跟随，`-2` 保证偶数
    /// （libx265 + yuv420p 要求偶数尺寸，写死 1440 可能得到奇数宽而报错）。
    public static let maxHeight = 1440

    /// x265 慢速档（默认 100）会让 198 个 4K 文件从几小时变一天多。
    /// `fast` 与 x264 medium 编码耗时同量级（实测 10s 的 4K60 素材约 10.6s）。
    public static let preset = "fast"

    /// x265 的 CRF 与 x264 不是同一质量档，不能按数字类比。
    public static let crf = 20

    /// 逐 token 返回 ffmpeg argv。
    public static func arguments(input: URL, output: URL) -> [String] {
        [
            "-nostdin",                             // 防 ffmpeg 吃掉父进程 stdin
            "-y",
            "-i", input.path,                       // 绝对路径，防「文件名像选项」
            "-map", "0:v:0",
            "-map", "0:a:0?",                       // 可选音轨：无音轨源不报错
            "-c:v", "libx265",
            "-preset", preset,
            "-crf", String(crf),
            // ⚠️ 顺序要紧：`fps` 在 `scale` 之前 —— 先减帧再缩像素，省掉一半重采样。
            "-vf", "fps=\(Int(maxFrameRate)),scale=-2:\(maxHeight)",
            // ⚠️ 这一行是 HEVC 硬解的唯一开关，**漏了会静默落到软解**（不报错，
            //    只是更慢更烫，肉眼看不出来）。本机实测产物 tag = hvc1。
            "-tag:v", "hvc1",
            "-pix_fmt", "yuv420p",                  // 防 10bit 掉硬解
            "-c:a", "aac",
            "-b:a", "192k",
            "-sn", "-dn",
            "-movflags", "+faststart",
            "-progress", "pipe:1",                  // 机器可读进度（成败仍只认 terminationStatus）
            "-nostats",
            output.path,
        ]
    }

    /// 产物路径推导：`root/Converted/<stem>-30fps.mp4`。
    ///
    /// ⚠️ 后缀是为了和转码产物（同名无后缀）区分，也是 `playbackItems` 一对一替换的
    /// 前提 —— 不带后缀的话两张产物会互相覆盖。
    public static func derivativeName(for source: URL) -> String {
        source.deletingPathExtension().lastPathComponent + "-30fps.mp4"
    }
}