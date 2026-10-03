import AVFoundation
import Foundation

/// 转码执行队列（TRANS-03/04/06 执行侧）—— 串行 drain、预检、tmp→rename、进度。
/// 本文件是 Transcode/ 里唯一 `import AVFoundation` 的（duration 探测）。
public protocol TranscodeRunning: AnyObject {
    /// 同步阻塞至进程退出，返回 `terminationStatus` 语义的退出码
    /// （串行队列的正交写法：run 不返回，下一个 job 不开始）。
    func run(ffmpegPath: String, arguments: [String], outputTemporaryPath: String,
             onProgressLine: @escaping (String) -> Void) -> Int32
}

/// job 状态机。`failed` 的 reason 是受控 token，不是自由文本（不给日志注入面）：
/// `disk_space` / `ffmpeg_unavailable` / `exit_nonzero` / `output_conflict`。
public enum TranscodeJobState: Equatable, Sendable {
    case pending, running, succeeded, skipped
    case failed(reason: String)
}

/// 一个转码任务。`commandDisplay` 入队时就算好 —— 审计串从入队那一刻就存在（TRANS-06）。
public struct TranscodeJob: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let sourceURL: URL
    public internal(set) var state: TranscodeJobState
    public internal(set) var percent: Double?
    public let commandDisplay: String

    init(id: UUID = UUID(), sourceURL: URL, state: TranscodeJobState = .pending,
         percent: Double? = nil, commandDisplay: String) {
        self.id = id
        self.sourceURL = sourceURL
        self.state = state
        self.percent = percent
        self.commandDisplay = commandDisplay
    }
}

/// duration 探测（TRANS-06 进度链的时长来源）。拿不到 → nil，不阻塞转码。
public struct AVAssetDurationProvider {
    public init() {}

    public func duration(of url: URL) async -> Double? {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return nil }
        return duration.seconds
    }
}

/// 串行转码队列 —— `@MainActor`（持有者隔离，照 `MediaLibrary` 写法；它最终被
/// AppDelegate 驱动，且 `onBatchFinished` 会触碰扫描器）。UI 观察走回调，
/// 不 import 任何 UI 框架（06-04 的 view model 自己做 ObservableObject）。
@MainActor
public final class TranscodeQueue {

    private let runner: any TranscodeRunning
    private let naming: TranscodeOutputNaming
    private let availability: () -> FFmpegToolStatus
    private let freeSpaceProvider: (URL) -> Int64?
    private let durationProvider: (URL) async -> Double?

    /// 全部依赖注入 —— 测试用 FakeRunner + 假闭包，零真实进程。
    public init(runner: any TranscodeRunning, naming: TranscodeOutputNaming,
                availability: @escaping () -> FFmpegToolStatus,
                freeSpaceProvider: @escaping (URL) -> Int64?,
                durationProvider: @escaping (URL) async -> Double? = AVAssetDurationProvider().duration(of:)) {
        self.runner = runner
        self.naming = naming
        self.availability = availability
        self.freeSpaceProvider = freeSpaceProvider
        self.durationProvider = durationProvider
    }

    public private(set) var jobs: [TranscodeJob] = []

    /// UI 钩子（06-04 接）。
    public var onJobsChanged: (() -> Void)?

    /// app 钩子（06-05 接 rescanAndApply —— SC#5 转完立即可播）。
    public var onBatchFinished: (() -> Void)?

    /// 逐个建 Job（state pending、commandDisplay 先算）。仍在排队（pending/running）
    /// 的同路径不重复入队；已终态的同路径允许再入队（会走 skipDecision 的幂等路径）。
    public func enqueue(sources: [URL]) {
        var activePaths = Set(jobs.filter { Self.isActive($0.state) }.map { $0.sourceURL.path })
        let toolPath = currentToolPath()
        for source in sources where !activePaths.contains(source.path) {
            activePaths.insert(source.path)
            let temporaryURL = naming.temporaryURL(for: source)
            jobs.append(TranscodeJob(
                sourceURL: source,
                commandDisplay: TranscodeCommand.displayString(
                    ffmpegPath: toolPath, input: source, output: temporaryURL)))
        }
        onJobsChanged?()
    }

    /// RED 骨架：类型面齐全、行为空 —— 断言红在行为上，不在编译上。
    public func run() async {}

    private static func isActive(_ state: TranscodeJobState) -> Bool {
        switch state {
        case .pending, .running:
            return true
        case .succeeded, .skipped, .failed:
            return false
        }
    }

    /// 入队时的审计串路径：可用用真路径，不可用用裸名占位（串只是展示，不是执行物）。
    private func currentToolPath() -> String {
        if case .available(let path) = availability() { return path }
        return "ffmpeg"
    }
}
