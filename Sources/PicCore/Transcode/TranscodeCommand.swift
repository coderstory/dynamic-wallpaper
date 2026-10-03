import Foundation

/// 转码命令构造（TEST-06 / TRANS-03 参数侧）—— RED 编译骨架。
public enum TranscodeCommand {

    public static let baselineCRF = 0
    public static let baselinePreset = ""

    public static func arguments(input: URL, output: URL) -> [String] {
        []
    }

    public static func displayString(ffmpegPath: String, input: URL, output: URL) -> String {
        ""
    }
}
