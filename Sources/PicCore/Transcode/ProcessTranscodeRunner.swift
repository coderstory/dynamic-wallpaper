import Foundation

/// 生产执行件 —— 队列唯一的外部执行面。三条铁律的落点：
/// - `/usr/bin/nice -n 10` 前缀：argv 数组直接给 nice，不经 shell；
/// - 退出判定只认 `Process.terminationStatus`（stdout 管道只喂进度解析，绝不用管道技巧拿退出码）；
/// - 本文件不含任何转码知识 —— 收到什么 argv 就执行什么。
///
/// 协议不标 `@MainActor`，由持有者（`TranscodeQueue`）负责隔离。
public final class ProcessTranscodeRunner: TranscodeRunning, @unchecked Sendable {

    public init() {}

    /// 当前进程的句柄 —— 取消要靠它，所以不能是 `run` 的局部变量。必须加锁：`cancel()` 可能来自与 `run()` 不同的线程，而协议要求 `Sendable`。
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    public var isRunning: Bool {
        lock.withLock { process != nil }
    }

    /// 终止当前进程。没有进程在跑时空操作（取消可能被连点）。
    public func cancel() {
        let running = lock.withLock { () -> Process? in
            cancelled = true
            return process
        }
        running?.terminate()
    }

    /// 本次 run 是否已被取消 —— spawn 前查一次，避免取消后还把进程拉起来。
    private func consumeCancellation() -> Bool {
        lock.withLock { () -> Bool in
            let was = cancelled
            cancelled = false
            return was
        }
    }

    public func run(ffmpegPath: String, arguments: [String], outputTemporaryPath: String,
                    onProgressLine: @escaping @Sendable (String) -> Void) async -> Int32 {
        _ = consumeCancellation()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nice")
        process.arguments = ["-n", "10", ffmpegPath] + arguments
        process.standardInput = nil
        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        // stderr 必须丢给 /dev/null，不能挂一个不读的 Pipe：管道缓冲区（约 64KB）一满，ffmpeg 就阻塞在写 stderr 上，进程永不退出 —— 表现是 waitUntilExit 挂住、队列卡死、CPU 归零（转长视频必现）。人话输出格式随版本漂，本就不解析，所以直接丢弃。
        process.standardError = FileHandle.nullDevice

        lock.withLock { self.process = process }

        do {
            try process.run()
        } catch {
            clearProcess()
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
        clearProcess()
        return process.terminationStatus
    }

    private func clearProcess() {
        lock.withLock { process = nil }
    }
}

/// 行切分器：readabilityHandler（后台队列）与收尾 drain（调用线程）两个来源，NSLock 串行化；残行留在 buffer，不丢半行。`@unchecked Sendable`：要进 `@Sendable` 的 readabilityHandler，buffer 的写入全在 `feed()` 的锁内。
private final class LineSplitter: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private let emit: (String) -> Void

    init(emit: @escaping (String) -> Void) {
        self.emit = emit
    }

    func feed(_ chunk: Data) {
        var lines: [String] = []
        lock.lock()
        buffer.append(chunk)
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = buffer.subdata(in: buffer.startIndex..<newline)
            buffer.removeSubrange(buffer.startIndex...newline)
            if let line = String(data: lineData, encoding: .utf8) {
                lines.append(line)
            }
        }
        lock.unlock()
        // **emit 必须在锁外**：现在的实现是 `Task { @MainActor }` 异步派发、不会阻塞，但哪天有人把它
        // 换成同步实现，锁内调用就会把整条读取管道卡死（readabilityHandler 与收尾 drain 争同一把锁）。
        for line in lines { emit(line) }
    }
}
