import AVFoundation
import Foundation

/// 转码执行队列（TRANS-03/04/06 执行侧）—— 串行 drain、预检、tmp→rename、进度。
/// 本文件是 Transcode/ 里唯一 `import AVFoundation` 的（duration 探测）。
public protocol TranscodeRunning: AnyObject {
    /// 进程退出后返回 `terminationStatus` 语义的退出码
    /// （串行队列的正交写法：run 不返回，下一个 job 不开始）。
    ///
    /// ⚠️ 反直觉陷阱：必须是 async。持有者 `TranscodeQueue` 是 `@MainActor`，
    /// 实现里同步 `waitUntilExit()` 会把整个 app 冻住，且 `onProgressLine` 的
    /// `Task { @MainActor }` 跳转在阻塞期间一条都送不出去（进度条卡 0% 后跳终值）。
    func run(ffmpegPath: String, arguments: [String], outputTemporaryPath: String,
             onProgressLine: @escaping (String) -> Void) async -> Int32
}

/// job 状态机。`failed` 的 reason 是受控 token，不是自由文本（不给日志注入面）：
/// `disk_space` / `ffmpeg_unavailable` / `exit_nonzero` / `output_conflict`。
public enum TranscodeJobState: Equatable, Sendable {
    case pending, running, succeeded, skipped
    case failed(reason: String)
}

/// 一个转码任务。`commandDisplay` 入队时就算好 —— 审计串从入队那一刻就存在（TRANS-06）。
/// `deletesSource`：转码**成功**后是否删除源文件 —— 自动扫描（壁纸目录）的源为 true
///（目录保持整洁），用户手动选择的源一律 false（外部素材不碰，删除策略按来源不按路径）。
public struct TranscodeJob: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let sourceURL: URL
    public internal(set) var state: TranscodeJobState
    public internal(set) var percent: Double?
    public let commandDisplay: String
    public let deletesSource: Bool

    init(id: UUID = UUID(), sourceURL: URL, state: TranscodeJobState = .pending,
         percent: Double? = nil, commandDisplay: String, deletesSource: Bool = false) {
        self.id = id
        self.sourceURL = sourceURL
        self.state = state
        self.percent = percent
        self.commandDisplay = commandDisplay
        self.deletesSource = deletesSource
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
    /// `deletesSource` 逐 job 记录（来源化删除策略：自动扫描 true / 用户选择 false）。
    public func enqueue(sources: [URL], deletesSource: Bool = false) {
        var activePaths = Set(jobs.filter { Self.isActive($0.state) }.map { $0.sourceURL.path })
        let toolPath = currentToolPath()
        for source in sources where !activePaths.contains(source.path) {
            activePaths.insert(source.path)
            let temporaryURL = naming.temporaryURL(for: source)
            jobs.append(TranscodeJob(
                sourceURL: source,
                commandDisplay: TranscodeCommand.displayString(
                    ffmpegPath: toolPath, input: source, output: temporaryURL),
                deletesSource: deletesSource))
        }
        onJobsChanged?()
    }

    /// 串行 drain：逐 job 预检 → 执行 → 终态。for 循环天然串行，不建 Task 组；
    /// 队列从非空排空（至少处理过一个 job）→ `onBatchFinished` 恰一次。
    public func run() async {
        guard jobs.contains(where: { Self.isActive($0.state) }) else { return }
        for index in jobs.indices {
            guard case .pending = jobs[index].state else { continue }
            await runJob(at: index)
        }
        onBatchFinished?()
    }

    /// 单个 job 的完整生命周期：预检（可用性 → 幂等 → 目录 → 磁盘）→ 执行 → 落盘。
    private func runJob(at index: Int) async {
        let source = jobs[index].sourceURL

        // 预检 1：工具不可用 → 不进 runner（入口置灰之外的第二道闸）。
        guard case .available(let toolPath) = availability() else {
            jobs[index].state = .failed(reason: "ffmpeg_unavailable")
            onJobsChanged?()
            return
        }

        // 预检 2：产物已新鲜 → 幂等跳过，零 runner 调用（防重复烤机）。
        if naming.skipDecision(source: source) {
            jobs[index].state = .skipped
            onJobsChanged?()
            return
        }

        // 预检 3：建 Converted 目录（已存在不报错）。
        let convertedDirectory = naming.convertedDirectoryURL()
        try? FileManager.default.createDirectory(
            at: convertedDirectory, withIntermediateDirectories: true)

        // 预检 4：磁盘余量 < 源大小 → 不 spawn（P6；源大小读不到按「不拦截」）。
        if let freeSpace = freeSpaceProvider(convertedDirectory),
           let sourceSize = (try? FileManager.default.attributesOfItem(atPath: source.path))?[.size] as? Int64,
           freeSpace < sourceSize {
            jobs[index].state = .failed(reason: "disk_space")
            onJobsChanged?()
            return
        }

        jobs[index].state = .running
        onJobsChanged?()

        let temporaryURL = naming.temporaryURL(for: source)
        let arguments = TranscodeCommand.arguments(input: source, output: temporaryURL)
        // duration 在 job 开始时取一次缓存，不逐行取（拿不到 → percent 走 nil 路径）。
        let durationSeconds = await durationProvider(source)
        var progress = ProgressParser.Accumulator()
        let status = await runner.run(
            ffmpegPath: toolPath,
            arguments: arguments,
            outputTemporaryPath: temporaryURL.path
        ) { line in
            Task { @MainActor in
                // 增量解析：只吃新到的这一行，状态留在累加器里 ——
                // 旧写法把整段历史 `+=` 进来再全量重解析，1 小时转码 = 数万行 → O(n²)。
                let snapshot = progress.consume(line)
                self.jobs[index].percent = ProgressParser.percent(
                    snapshot: snapshot, durationSeconds: durationSeconds)
                self.onJobsChanged?()
            }
        }

        if status == 0 {
            let outputURL = naming.outputURL(for: source)
            do {
                if FileManager.default.fileExists(atPath: outputURL.path) {
                    try FileManager.default.removeItem(at: outputURL)
                }
                try FileManager.default.moveItem(at: temporaryURL, to: outputURL)
                jobs[index].state = .succeeded
            } catch {
                try? FileManager.default.removeItem(at: temporaryURL)
                jobs[index].state = .failed(reason: "output_conflict")
            }
        } else {
            try? FileManager.default.removeItem(at: temporaryURL)
            jobs[index].state = .failed(reason: "exit_nonzero")
        }
        // 来源化删除策略：仅在**成功落盘后**删源（失败/跳过一律保留）。
        // 删除失败静默 —— 源还在只会让它下轮被 skipDecision 幂等跳过，不出错。
        if jobs[index].state == .succeeded, jobs[index].deletesSource {
            try? FileManager.default.removeItem(at: source)
        }
        onJobsChanged?()
    }

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
