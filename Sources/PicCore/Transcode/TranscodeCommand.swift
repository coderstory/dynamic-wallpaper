import Foundation

/// 转码命令构造（TEST-06 / TRANS-03 参数侧）—— 纯参数逻辑，零进程执行。
///
/// 命令与执行分离正是 C6 的落点：本文件只产出 argv 数组与审计串；
/// `Process` / 管道是 06-03 `ProcessTranscodeRunner` 的事。
public enum TranscodeCommand {

    /// C7 的实测基线（06-05 手动 bench 若给出不同终值，改这两个常量 + 同 commit
    /// 更新 `TranscodeCommandTests` 对应断言）。不做配置化 —— 用户不调这个。
    public static let baselineCRF = 18
    public static let baselinePreset = "medium"

    /// 逐 token 返回 ffmpeg argv —— 每个 flag 与它的值是独立元素，绝不拼成一个
    /// 字符串（T-06-01：`Process.arguments` 数组形态从源头锁死，含空格中文的
    /// 路径必须是单个元素）。
    public static func arguments(input: URL, output: URL) -> [String] {
        [
            "-nostdin",                             // 防 ffmpeg 吃掉父进程 stdin
            "-y",
            "-i", input.path,                       // 绝对路径，防「文件名像选项」
            "-map", "0:v:0",
            "-map", "0:a:0?",                       // 可选音轨：无音轨源不报错（Q3）
            "-c:v", "libx264",
            "-preset", baselinePreset,
            "-crf", String(baselineCRF),
            "-pix_fmt", "yuv420p",                  // P2：防 Hi10P 产出 10bit 掉硬解
            "-c:a", "aac",
            "-b:a", "192k",
            "-sn", "-dn",                           // P3：丢字幕与数据附件
            "-movflags", "+faststart",
            "-progress", "pipe:1",                  // 机器可读进度（成败仍只认 terminationStatus）
            "-nostats",
            // ⚠️ 必须显式给 muxer：产物先写 `.tmp` 再 rename，而 ffmpeg 按**最后一个**
            // 扩展名判格式 —— `x.mp4.tmp` 会判成未知格式，muxer 初始化直接失败、进程秒退。
            // 与 FpsDownscaleCommand 同一条理由。
            "-f", "mp4",
            output.path,
        ]
    }

    /// 给人看的审计串（TRANS-06）—— `nice -n 10` 前缀 + argv 空格拼接。
    ///
    /// ⚠️ 这是审计展示，不是可执行物：路径含空格时它不保证能复制执行，
    /// 严禁把它交给解释器跑。真正的执行永远走 `arguments` 的数组形态。
    public static func displayString(ffmpegPath: String, input: URL, output: URL) -> String {
        "nice -n 10 " + ffmpegPath + " " + arguments(input: input, output: output).joined(separator: " ")
    }
}
