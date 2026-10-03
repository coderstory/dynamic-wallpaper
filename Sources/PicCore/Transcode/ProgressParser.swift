import Foundation

/// ffmpeg `-progress pipe:1` 输出解析（TRANS-06 进度侧）。
///
/// 纯函数、零正则、零 Date 解析、零 UI —— stderr 的人话输出**不要**去啃
/// （格式随版本漂），只认 `-progress` 的 key=value 机器可读输出。
public enum ProgressParser {

    /// 一段 stdout 读数解析出的进度快照。
    public struct Snapshot: Equatable, Sendable {
        /// 已解码帧数；nil = 尚未收到。
        public let frame: Int64?
        /// ffmpeg 的 `out_time_ms` 键，**值是微秒**（ffmpeg 历史命名陷阱 ——
        /// 字段名直接叫 Us 把语义钉在类型上）。
        public let outTimeUs: Int64?
        /// `progress=end` 标志。
        public let isEnd: Bool

        public init(frame: Int64?, outTimeUs: Int64?, isEnd: Bool) {
            self.frame = frame
            self.outTimeUs = outTimeUs
            self.isEnd = isEnd
        }
    }

    /// 与 ffmpeg 输出键逐字一致（注意：值是微秒，不是键名写的毫秒）。
    public static let progressKeyOutTime = "out_time_ms"

    /// 单行 key=value 解析：按**第一个** `=` 切（值里可能还有 `=`），
    /// trim 空白；无 `=` 或空键 → nil。
    public static func parseLine(_ line: String) -> (key: String, value: String)? {
        // RED stub：待 GREEN 实现。
        return nil
    }

    /// 多行块解析：逐行 parseLine，已知键（frame / out_time_ms / progress）
    /// 后值覆盖前值；未知键与解析失败的行**静默忽略**（格式漂移不崩）。
    public static func parseChunk(_ text: String) -> Snapshot {
        // RED stub：待 GREEN 实现。
        return Snapshot(frame: nil, outTimeUs: nil, isEnd: false)
    }

    /// 百分比换算：微秒 → 秒 → 除以时长，clamp 到 0...1（ffmpeg 起步瞬间
    /// 可能报负值或超尾部）。时长缺失/非正/尚无 outTimeUs → nil
    /// （进度条隐藏路径，不是假 0%）。
    public static func percent(snapshot: Snapshot, durationSeconds: Double?) -> Double? {
        // RED stub：待 GREEN 实现。
        return nil
    }
}
