import Foundation

/// 降帧 argv 构造 —— 纯参数逻辑，零进程执行（与 `TranscodeCommand` 同形，各管各的档）。
///
/// argv 一律逐 token 数组，绝不拼字符串：含空格中文的路径拼成串会被解释器切成两半。
public enum FpsDownscaleCommand {


    /// 帧率封顶：恰好等于它不降，高于才降。
    public static let maxFrameRate: Double = 30

    /// 是否需要降帧 —— 唯一的判定口。0.5 容差不是随手取的：`nominalFrameRate` 对 NTSC 源读出 30.04 / 30.05（实际 29.97 或 30），裸 `>` 会把它们判超标等于白转；真超标从 48 起跳，0.5 碰不到。
    public static func needsDownscale(_ fps: Double) -> Bool {
        fps > maxFrameRate + 0.5
    }

    /// 高度上限。**是上限不是目标高度** —— 低于它的源必须原样保留。
    public static let maxHeight = 1440

    /// 缩放滤镜。写成 `min(1440,ih)` 而不是裸 `1440`：后者是无条件拉伸，
    /// 1080p 的源会被放大成 1440p（实测 1920x1080 → 2560x1440），体积和功耗反而在涨。
    /// `-2` 保证宽度为偶数 —— yuv420p 要求偶数尺寸。
    public static var scaleFilter: String { "scale=-2:'min(\(maxHeight),ih)'" }

    /// 逐 token 返回 ffmpeg argv。编码器与质量档取自 `VideoEncoderProfile`，与转码共用同一份，不要就地复制。
    public static func arguments(input: URL, output: URL) -> [String] {
        [
            "-nostdin",                             // 防 ffmpeg 吃掉父进程 stdin
            "-y",
            "-i", input.path,                       // 绝对路径，防「文件名像选项」
            "-map", "0:v:0",
            "-map", "0:a:0?",                       // 可选音轨：无音轨源不报错
            "-c:v", VideoEncoderProfile.encoder.ffmpegName,
        ]
        + VideoEncoderProfile.qualityTokens()
        + [
            // 顺序要紧：`fps` 在 `scale` 之前 —— 先减帧再缩像素，省掉一半重采样。
            "-vf", "fps=\(Int(maxFrameRate)),\(scaleFilter)",
            // HEVC 硬解的唯一开关，漏了会静默落到软解（不报错，只是更慢更烫，肉眼看不出来）。
            "-tag:v", "hvc1",
            "-pix_fmt", "yuv420p",                  // 防 10bit 掉硬解
            "-c:a", "aac",
            "-b:a", "192k",
            "-sn", "-dn",
            "-movflags", "+faststart",
            "-progress", "pipe:1",                  // 机器可读进度（成败仍只认 terminationStatus）
            "-nostats",
            // 必须显式给 muxer：产物先写 `.tmp` 再 rename，而 ffmpeg 按最后一个扩展名判格式，`x-30fps.mp4.tmp` 会判成未知格式、muxer 初始化直接失败、进程秒退。给了 `-f` 就与文件名无关。
            "-f", "mp4",
            output.path,
        ]
    }

    /// 产物路径推导：`root/Converted/<stem>-30fps.mp4`。`-30fps` 后缀不能去掉 —— 转码产物同名且无后缀，两者会互相覆盖。
    public static func derivativeName(for source: URL) -> String {
        source.deletingPathExtension().lastPathComponent + "-30fps.mp4"
    }
}