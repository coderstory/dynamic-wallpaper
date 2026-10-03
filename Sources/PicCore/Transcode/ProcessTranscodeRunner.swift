import Foundation

/// RED 骨架：不 spawn 任何进程、恒返回 0 —— 测试红在「行没收到 / 产物没落地」。
public final class ProcessTranscodeRunner: TranscodeRunning {

    public init() {}

    public func run(ffmpegPath: String, arguments: [String], outputTemporaryPath: String,
                    onProgressLine: @escaping (String) -> Void) -> Int32 {
        0
    }
}
