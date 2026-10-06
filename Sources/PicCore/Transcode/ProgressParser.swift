import Foundation

/// ffmpeg `-progress pipe:1` 输出解析（TRANS-06 进度侧）。
/// 纯函数、零正则、零 Date 解析、零 UI —— stderr 的人话输出不要去啃（格式随版本漂），只认 `-progress` 的 key=value 机器可读输出。
public enum ProgressParser {

    /// 一段 stdout 读数解析出的进度快照。
    public struct Snapshot: Equatable, Sendable {
        /// 已解码帧数；nil = 尚未收到。
        public let frame: Int64?
        /// ffmpeg 的 `out_time_ms` 键，值是微秒（键名的 ms 是历史遗留 —— 字段名直接叫 Us 把语义钉在类型上）。
        public let outTimeUs: Int64?
        public let isEnd: Bool

        public init(frame: Int64?, outTimeUs: Int64?, isEnd: Bool) {
            self.frame = frame
            self.outTimeUs = outTimeUs
            self.isEnd = isEnd
        }
    }

    /// 与 ffmpeg 输出键逐字一致（注意：值是微秒，不是键名写的毫秒）。
    public static let progressKeyOutTime = "out_time_ms"

    /// 单行 key=value 解析：按第一个 `=` 切（值里可能还有 `=`），trim 空白；无 `=` 或空键 → nil。
    public static func parseLine(_ line: String) -> (key: String, value: String)? {
        guard let eq = line.firstIndex(of: "=") else { return nil }
        let key = line[..<eq].trimmingCharacters(in: .whitespaces)
        let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return nil }
        return (key, value)
    }

    /// 增量解析器 —— 只吃新到的那一段，状态留在自己身上。
    ///
    /// 不得改回全量重扫：转码 1 小时 = 数万行 `-progress` 输出，逐行全量重扫是 O(n²)。
    /// 累加器每段只 parse 一次，n 段总共 O(n)。
    ///
    /// 语义（`parseChunk` 转调本类型，两者必须逐字一致）：
    ///   · 后值覆盖前值；
    ///   · 未知键 / 无 `=` / 空键 → 静默忽略；
    ///   · `frame=` / `out_time_ms=` 的值解析失败 → 该键置 nil（不是保持旧值）：`Int64(value)` 对非法值给 nil 并覆盖；
    ///   · `progress=` 每次都重写 isEnd（`continue` 会把先前的 `end` 打回 false），不是「只在 end 时置位」。
    public struct Accumulator {
        private var frame: Int64?
        private var outTimeUs: Int64?
        private var isEnd = false

        public init() {}

        /// 吸收一段 ffmpeg 输出（可含多行，内部按 `\n` 切），返回当前快照。调用方直接把它喂给 `percent(...)`。
        public mutating func consume(_ text: String) -> Snapshot {
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let (key, value) = parseLine(String(line)) else { continue }
                switch key {
                case "frame":
                    frame = Int64(value)
                case progressKeyOutTime:
                    outTimeUs = Int64(value)
                case "progress":
                    isEnd = (value == "end")
                default:
                    break
                }
            }
            return Snapshot(frame: frame, outTimeUs: outTimeUs, isEnd: isEnd)
        }
    }

    /// 多行块解析：已知键（frame / out_time_ms / progress）后值覆盖前值；未知键与解析失败的行静默忽略（格式漂移不崩）。
    ///
    /// 这是 `Accumulator` 的批量入口，实现只有一份（转调 consume）——「批量 = 逐行折叠」必须由构造保证，不靠两份代码碰巧一致。
    public static func parseChunk(_ text: String) -> Snapshot {
        var accumulator = Accumulator()
        return accumulator.consume(text)
    }

    /// 百分比换算：微秒 → 秒 → 除以时长，clamp 到 0...1（ffmpeg 起步瞬间可能报负值或超尾部）。时长缺失/非正/尚无 outTimeUs → nil —— nil 是进度条隐藏路径，不是假 0%。
    public static func percent(snapshot: Snapshot, durationSeconds: Double?) -> Double? {
        guard let durationSeconds, durationSeconds > 0,
              let outTimeUs = snapshot.outTimeUs else { return nil }
        let seconds = Double(outTimeUs) / 1_000_000.0
        return min(max(seconds / durationSeconds, 0), 1)
    }
}

/// 进度累加器的 `@MainActor` 壳 —— `onProgressLine` 是 `@Sendable`，不能可变捕获 `Accumulator`；
/// 所有读写都在 `Task { @MainActor }` 里，圈进主 actor 即可。两个转码队列共用这一份。
@MainActor
public final class ProgressState {
    private var accumulator = ProgressParser.Accumulator()

    public init() {}

    public func consume(_ line: String, durationSeconds: Double?) -> Double? {
        ProgressParser.percent(
            snapshot: accumulator.consume(line), durationSeconds: durationSeconds)
    }
}
