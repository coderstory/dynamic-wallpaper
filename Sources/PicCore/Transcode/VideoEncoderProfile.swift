import Foundation

/// 视频编码档 —— 降帧与转码共用同一份。
/// 两者要的东西不同（转码只换容器不改画质，降帧同时动编码器/帧率/分辨率），
/// 但「用哪个编码器、什么质量档」是同一个决定 —— 只留这一处，改降帧时转码自动同步。
public enum VideoEncoderProfile {

    // MARK: - 硬件编码器

    public enum Encoder: Equatable, Sendable {
        /// CPU 软编。质量最好（能做完整 RDO + 4×4 块划分），慢。
        case libx264, libx265
        /// Apple Silicon 硬件编码。快得多，代价是不做 RDO、最小块 16×16，
        /// 同体积下画质略逊 —— 但把质量档调上去可以追平（见 hardwareQuality）。
        case videotoolboxHEVC

        var ffmpegName: String {
            switch self {
            case .libx264: return "libx264"
            case .libx265: return "libx265"
            case .videotoolboxHEVC: return "hevc_videotoolbox"
            }
        }

        /// videotoolbox 用 `-q:v`（质量越高值越大），x264/x265 用 `-crf`（质量越高值越小）。
        var qualityFlag: String { self == .videotoolboxHEVC ? "-q:v" : "-crf" }

        var isHardwareAccelerated: Bool { self == .videotoolboxHEVC }
    }

    // MARK: - 档位

    /// 改这里会同时影响降帧与转码。
    public static let encoder = Encoder.videotoolboxHEVC

    /// videotoolbox 的质量档（越大越好）。65 时与 libx265 crf 20 体积画质相当，速度快 3 倍。
    public static let hardwareQuality = 65

    /// 软件编码的质量档。仅在 `encoder` 切到 libx* 时使用。
    public static let softwareCRF = 20

    /// 软件编码的速度档。videotoolbox 忽略它。
    public static let preset = "fast"

    /// 把质量参数展开成 argv token 对。
    public static func qualityTokens() -> [String] {
        encoder == .videotoolboxHEVC
            ? [encoder.qualityFlag, String(hardwareQuality)]
            : [encoder.qualityFlag, String(softwareCRF), "-preset", preset]
    }
}