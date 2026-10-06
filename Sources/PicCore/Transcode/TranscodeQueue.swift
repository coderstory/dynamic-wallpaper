import AVFoundation
import Foundation

/// 转码执行队列（TRANS-03/04/06 执行侧）—— 串行 drain、预检、tmp→rename、进度。
public protocol TranscodeRunning: AnyObject, Sendable {
    /// 进程退出后返回 `terminationStatus` 语义的退出码（spawn 失败返回 -1）
    /// （串行队列的正交写法：run 不返回，下一个 job 不开始）。
    ///
    /// 反直觉陷阱：必须是 async。持有者 `TranscodeQueue` 是 `@MainActor`，
    /// 实现里同步 `waitUntilExit()` 会把整个 app 冻住，且 `onProgressLine` 的
    /// `Task { @MainActor }` 跳转在阻塞期间一条都送不出去（进度条卡 0% 后跳终值）。
    func run(ffmpegPath: String, arguments: [String], outputTemporaryPath: String,
             onProgressLine: @escaping @Sendable (String) -> Void) async -> Int32
}

/// job 状态机。`failed` 的 reason 是受控 token，不是自由文本（不给日志注入面）：
/// `disk_space` / `ffmpeg_unavailable` / `exit_nonzero` / `output_conflict`。
public enum TranscodeJobState: Equatable, Sendable {
    case pending, running, succeeded, skipped
    case failed(reason: String)
}

/// 一个转码任务。`commandDisplay` 入队时就算好 —— 审计串从入队那一刻就存在（TRANS-06）。
/// `deletesSource`：转码成功后是否删除源文件 —— 自动扫描（壁纸目录）的源为 true（目录保持整洁），用户手动选择的源一律 false（外部素材不碰，删除策略按来源不按路径）。
public struct TranscodeJob: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let sourceURL: URL
    public internal(set) var state: TranscodeJobState
    public internal(set) var percent: Double?
    public let commandDisplay: String
    /// 「转码成功后删源」。**入队时不标** —— 打开转码页只是看一眼，不该提前把素材押上
    /// 删除；由 `armSourceDeletion(for:)` 在点「开始转码」的那一刻才落位。
    /// 注意：删源的实际时机是「转码成功 **且** 产物校验可用后」（runJob 里的 looksLikeUsableOutput 闸），
    /// 产物不可用标 output_unverified 并保留源 —— 不是「退出码 0 就删」。
    public internal(set) var deletesSource: Bool

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

/// 串行转码队列 —— `@MainActor`（它最终被 AppDelegate 在主线程驱动，且 `onBatchFinished` 会触碰扫描器）。
/// UI 观察走回调，不 import 任何 UI 框架（view model 自己做 ObservableObject）。
@MainActor
public final class TranscodeQueue {

    private let runner: any TranscodeRunning
    private let naming: TranscodeOutputNaming
    private let availability: () -> FFmpegToolStatus
    private let freeSpaceProvider: (URL) -> Int64?
    private let durationProvider: (URL) async -> Double?
    /// 源文件的删除通道。**默认走废纸篓**：转码产物与源同名不同后缀，一次误判就是
    /// 不可恢复的素材丢失，删除必须可从访达找回。
    private let trashProvider: (URL) throws -> Void

    /// 全部依赖注入 —— 测试用 FakeRunner + 假闭包跑，零真实进程。
    public init(runner: any TranscodeRunning, naming: TranscodeOutputNaming,
                availability: @escaping () -> FFmpegToolStatus,
                freeSpaceProvider: @escaping (URL) -> Int64?,
                durationProvider: @escaping (URL) async -> Double? = AVAssetDurationProvider().duration(of:),
                trashProvider: @escaping (URL) throws -> Void = { url in
                    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                }) {
        self.runner = runner
        self.naming = naming
        self.availability = availability
        self.freeSpaceProvider = freeSpaceProvider
        self.durationProvider = durationProvider
        self.trashProvider = trashProvider
    }

    public private(set) var jobs: [TranscodeJob] = []

    /// UI 钩子。
    public var onJobsChanged: (() -> Void)?

    /// app 钩子（接 rescanAndApply —— SC#5 转完立即可播）。
    public var onBatchFinished: (() -> Void)?

    /// 逐个建 Job（state pending、commandDisplay 先算）。仍在排队（pending/running）的同路径不重复入队；已终态的同路径允许再入队（会走 skipDecision 的幂等路径）。
    ///
    /// 产物名是**扁平**的（`<stem>.mp4`），递归扫描下不同子目录的同名源文件会算出同一个
    /// 产物路径 —— 后跑的那个会静默覆盖前一个的产物。这里按产物路径查重，撞上的直接标
    /// `name_collision` 且不入队：宁可让用户改个文件名，不可悄悄吃掉一份素材。
    public func enqueue(sources: [URL], deletesSource: Bool = false) {
        var activePaths = Set(jobs.filter { Self.isActive($0.state) }.map { $0.sourceURL.path })
        // 产物占位只算**活跃** job：已终态 job 的产物路径不该参与碰撞判定，
        // 否则「失败后修好文件再转一次」这条重试路径会被历史记录堵死。
        var claimedOutputs = Set(jobs.filter { Self.isActive($0.state) }
            .map { naming.outputURL(for: $0.sourceURL).path })
        let toolPath = currentToolPath()
        for source in sources where !activePaths.contains(source.path) {
            activePaths.insert(source.path)
            let outputPath = naming.outputURL(for: source).path
            if claimedOutputs.contains(outputPath) {
                jobs.append(TranscodeJob(
                    sourceURL: source,
                    state: .failed(reason: "name_collision"),
                    commandDisplay: TranscodeCommand.displayString(
                        ffmpegPath: toolPath, input: source,
                        output: URL(fileURLWithPath: outputPath)),
                    deletesSource: deletesSource))
                continue
            }
            claimedOutputs.insert(outputPath)
            let temporaryURL = naming.temporaryURL(for: source)
            jobs.append(TranscodeJob(
                sourceURL: source,
                commandDisplay: TranscodeCommand.displayString(
                    ffmpegPath: toolPath, input: source, output: temporaryURL),
                deletesSource: deletesSource))
        }
        onJobsChanged?()
    }

    /// 「开始转码」的落点：此刻才把**自动来源**（壁纸目录里扫出来的）押上删源标记。
    /// 入队时不标 —— 打开转码页扫一遍就把素材标记成「成功即永久删除」太危险，
    /// 用户可能只是切过去看一眼。
    public func armSourceDeletion(for sources: [URL]) {
        let paths = Set(sources.map { $0.path })
        var changed = false
        for index in jobs.indices where paths.contains(jobs[index].sourceURL.path) {
            guard case .pending = jobs[index].state else { continue }
            jobs[index].deletesSource = true
            changed = true
        }
        if changed { onJobsChanged?() }
    }

    /// 串行 drain：逐 job 预检 → 执行 → 终态。for 循环天然串行，不建 Task 组；
    /// 队列从非空排空（至少处理过一个 job）→ `onBatchFinished` 恰一次。
    ///
    /// 全部 job 都走幂等跳过（产物比源新）或预检失败时**不发** `onBatchFinished`：
    /// 它接的是装配层的全库重扫，没转出任何新东西却通知一次，用户看到的就是一场没有来由的重扫。
    public func run() async {
        var didWork = false
        for index in jobs.indices {
            guard case .pending = jobs[index].state else { continue }
            await runJob(at: index)
            didWork = true
        }
        if didWork { onBatchFinished?() }
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

        // 预检 3：建 Converted 目录。已存在或建不出来都不拦（`try?`）—— ffmpeg 写不进去时按 exit_nonzero 失败。
        let convertedDirectory = naming.convertedDirectoryURL()
        try? FileManager.default.createDirectory(
            at: convertedDirectory, withIntermediateDirectories: true)

        // 预检 4：磁盘余量 < 源大小 → 不 spawn（源大小读不到按「不拦截」）。
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
        let progress = ProgressState()
        let status = await runner.run(
            ffmpegPath: toolPath,
            arguments: arguments,
            outputTemporaryPath: temporaryURL.path
        ) { line in
            Task { @MainActor in
                // 增量解析：只吃新到的这一行，状态留在累加器里。不得改成把整段历史 `+=` 进来再全量重解析 —— 1 小时转码 = 数万行 → O(n²)。
                self.jobs[index].percent = progress.consume(line, durationSeconds: durationSeconds)
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
        // 来源化删除策略：仅在成功落盘后删源（失败/跳过一律保留）。
        // 走废纸篓而不是 removeItem —— 删错了能从访达找回来。删除失败静默：
        // 源还在只会让它下轮被 skipDecision 幂等跳过，且产物已经落盘，不算失败。
        if jobs[index].state == .succeeded, jobs[index].deletesSource {
            // 退出码 0 不是「产物可用」的充分条件：磁盘写满、map 落空都会退出 0 但产出空文件。
            // 删源不可逆（即便走废纸篓也是素材丢失），必须先确认产物真的可用再动源。
            let outputURL = naming.outputURL(for: source)
            if Self.looksLikeUsableOutput(outputURL) {
                try? trashProvider(source)
            } else {
                jobs[index].state = .failed(reason: "output_unverified")
            }
        }
        onJobsChanged?()
    }

    /// 产物可用性的同步闸：体积 > 0。不做 AVAsset 探测（那是 async，会把状态机拖长，
    /// 且失败路径下一轮 skipDecision 会幂等跳过这个源，不会反复重转）。
    private static func looksLikeUsableOutput(_ url: URL) -> Bool {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64 else {
            return false
        }
        return size > 0
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

/// 进度累加器的 `@MainActor` 壳 —— `onProgressLine` 是 `@Sendable`，不能可变捕获 `Accumulator`；所有读写都在 `Task { @MainActor }` 里，圈进主 actor 即可。
@MainActor
private final class ProgressState {
    private var accumulator = ProgressParser.Accumulator()

    func consume(_ line: String, durationSeconds: Double?) -> Double? {
        ProgressParser.percent(
            snapshot: accumulator.consume(line), durationSeconds: durationSeconds)
    }
}
