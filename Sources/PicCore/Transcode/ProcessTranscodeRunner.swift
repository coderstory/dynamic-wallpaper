import Foundation

/// 生产执行件（06-03 T1）—— 队列唯一的外部执行面（threat T-06-10 的边界）。
///
/// 三条铁律的落点：
/// - C11：`/usr/bin/nice -n 10` 前缀 —— argv 数组直接给 nice，不经 shell；
/// - C10：退出判定只认 `Process.terminationStatus`（stdout 管道只喂进度解析，
///   绝不用管道技巧拿退出码 —— PITFALLS #9(d)）；
/// - 本文件不含任何转码知识 —— 收到什么 argv 就执行什么。
/// 协议不标 `@MainActor`，由持有者（`TranscodeQueue`）负责隔离。
public final class ProcessTranscodeRunner: TranscodeRunning {

    public init() {}

    public func run(ffmpegPath: String, arguments: [String], outputTemporaryPath: String,
                    onProgressLine: @escaping @Sendable (String) -> Void) async -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nice")
        process.arguments = ["-n", "10", ffmpegPath] + arguments
        process.standardInput = nil
        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        // stderr 整根吞掉不读：人话输出格式随版本漂，不解析（RESEARCH Don't-Hand-Roll）。
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return -1
        }
        let splitter = LineSplitter(emit: onProgressLine)
        let handle = stdoutPipe.fileHandleForReading
        handle.readabilityHandler = { reading in
            let chunk = reading.availableData
            if chunk.isEmpty {
                reading.readabilityHandler = nil
                return
            }
            splitter.feed(chunk)
        }
        // 只有这一次等待需要跳离主 actor —— readabilityHandler 本就在私有队列，
        // 同步 waitUntilExit 会冻住 @MainActor 的调用方（TranscodeQueue），
        // 进度回调在阻塞期间一条也送不出去。
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .utility).async {
                process.waitUntilExit()
                c.resume()
            }
        }
        handle.readabilityHandler = nil
        // 收尾 drain：handler 置 nil 后管道里可能还有未投递的字节，不读会丢尾行。
        splitter.feed(handle.readDataToEndOfFile())
        return process.terminationStatus
    }
}

/// 行切分器：readabilityHandler（后台队列）与收尾 drain（调用线程）两个来源，
/// NSLock 串行化；残行留在 buffer，不丢半行。`@unchecked Sendable`：要进
/// `@Sendable` 的 readabilityHandler，buffer 的写入全在 `feed()` 的锁内。
private final class LineSplitter: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private let emit: (String) -> Void

    init(emit: @escaping (String) -> Void) {
        self.emit = emit
    }

    func feed(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(chunk)
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = buffer.subdata(in: buffer.startIndex..<newline)
            buffer.removeSubrange(buffer.startIndex...newline)
            if let line = String(data: lineData, encoding: .utf8) {
                emit(line)
            }
        }
    }
}
