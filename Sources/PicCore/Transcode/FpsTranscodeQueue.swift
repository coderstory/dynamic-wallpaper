import AVFoundation
import Foundation

/// 降帧队列。与 `TranscodeQueue` 同形（依赖注入、四道预检、tmp→rename），三处不同：
/// 候选来自帧率表而非扩展名白名单、派生产物顶替原片而非追加、带暂停/取消两个控制通道。
@MainActor
public final class FpsTranscodeQueue {

    // MARK: - 状态

    public enum JobState: Equatable, Sendable {
        case pending, running, done
        case failed(reason: String)
    }

    public struct Job: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let sourceURL: URL
        public internal(set) var state: JobState
        public internal(set) var percent: Double?
        public let fps: Double

        init(id: UUID = UUID(), sourceURL: URL, fps: Double,
             state: JobState = .pending, percent: Double? = nil) {
            self.id = id
            self.sourceURL = sourceURL
            self.fps = fps
            self.state = state
            self.percent = percent
        }
    }

    public private(set) var jobs: [Job] = []
    public private(set) var scannedCount = 0
    public private(set) var reusedCount = 0
    /// 帧率表卡的读数：总行数 / 无需处理数。探测失败的文件也算一行 —— 它被看过了，只是判不出帧率，不算进 `okAt30Count`。
    public private(set) var tableTotal = 0
    public private(set) var okAt30Count = 0

    public var onJobsChanged: (() -> Void)?
    public var onBatchFinished: (() -> Void)?

    // MARK: - 依赖

    private let runner: any TranscodeRunning
    private let root: URL
    private let availability: () -> FFmpegToolStatus
    private let freeSpaceProvider: (URL) -> Int64?
    private let specProvider: (URL) async -> VideoAssetMetadata
    private let tableURL: URL

    /// 暂停/取消标志。与 UI 的 await 不同线程，用锁保护。
    private let controlLock = NSLock()
    private var _pauseRequested = false
    private var _cancelRequested = false

    public init(runner: any TranscodeRunning, root: URL,
                availability: @escaping () -> FFmpegToolStatus,
                freeSpaceProvider: @escaping (URL) -> Int64?,
                specProvider: @escaping (URL) async -> VideoAssetMetadata,
                tableURL: URL = FrameRateTable.defaultURL()) {
        self.runner = runner
        self.root = root
        self.availability = availability
        self.freeSpaceProvider = freeSpaceProvider
        self.specProvider = specProvider
        self.tableURL = tableURL
    }

    public var isPaused: Bool { controlLock.withLock { _pauseRequested } }
    public var isRunning = false

    // MARK: - 控制

    public func pause() {
        controlLock.withLock { _pauseRequested = true }
    }

    public func resume() {
        controlLock.withLock { _pauseRequested = false }
    }

    /// 取消：置标志并终止当前进程。没有进程在跑时它只是个标志 —— `run()` 会立刻返回，且把当前 job 退回 pending。
    public func cancel() {
        controlLock.withLock { _cancelRequested = true }
        (runner as? ProcessTranscodeRunner)?.cancel()
    }

    private func shouldStop() -> Bool {
        controlLock.withLock { _pauseRequested || _cancelRequested }
    }

            _pauseRequested = false
    private func consumeCancel() -> Bool {
        controlLock.withLock { () -> Bool in
            let was = _cancelRequested
            _cancelRequested = false
            return was
        }
    }

    // MARK: - 扫描

    /// 遍历壁纸目录，把超过 30fps 的文件排进队列。走帧率表做增量：表里有效的行不重开 `AVURLAsset`。
    public func scan() async {
        var table = FrameRateTable.load(from: tableURL)
        // 先在内存里把「源 ↔ 产物」对齐一次，再决定谁要进队列。
        // 卸载重装（表被重置）、表丢过一次写入、`Converted/` 被手工删过 —— 这三种情况下
        // 表里坐着 `.needsConvert`，磁盘上的产物却好好地在那儿。不先对齐的话，
        // 已经降过帧的文件会被重新烤一遍，而且 UI 会把它们重新报成「待降帧」。
        try? table.reconcileWithDerivatives(to: tableURL)
        var candidates: [Job] = []
        var scanned = 0
        var reused = 0

        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        // 不能写 `for ... in enumerator` —— async 上下文里 makeIterator 不可用。先 nextObject() 取类型，再循环。
        var cursor: URL? = enumerator.nextObject() as? URL
        while let entry = cursor {
            cursor = enumerator.nextObject() as? URL
            // 产物目录整棵排除 —— 产物自己不能再进队列。
            if entry.pathComponents.contains(MediaLibrary.excludedDirectoryName) { continue }
            guard MediaLibrary.allowedExtensions.contains(entry.pathExtension.lowercased()) else { continue }
            guard let values = try? entry.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true else { continue }

            scanned += 1
            if let fps = await resolveFrameRate(for: entry, table: &table, reused: &reused) {
                candidates.append(Job(sourceURL: entry, fps: fps))
            }
        }

        jobs = candidates
        scannedCount = scanned
        reusedCount = reused
        tableTotal = table.entries.count
        okAt30Count = table.entries.filter { $0.state == .okAt30 }.count
        try? table.save(to: tableURL)
        onJobsChanged?()
    }

    /// 增量读表：命中就用表里的，否则探测一次并写回。返回 nil = 不需要降。
    private func resolveFrameRate(for source: URL, table: inout FrameRateTable,
                                  reused: inout Int) async -> Double? {
        if let cached = table.reusableEntry(for: source) {
            reused += 1
            // `.done` 不等于「不用降」—— `recovered` 只把 converting/failed 退回可重试，已完成的必须跳过，否则每次扫描都把已转文件重排一遍。
            guard cached.state.recovered == .needsConvert else { return nil }
            let cachedFPS = cached.fps
            return FpsDownscaleCommand.needsDownscale(cachedFPS) ? cachedFPS : nil
        }
        let meta = await specProvider(source)
        guard meta.hasVideoTrack, let fps = meta.frameRate else { return nil }

        let attributes = try? FileManager.default.attributesOfItem(atPath: source.path)
        let derivative = derivativeURL(for: source)
        // 产物已经在磁盘上 → 这一次不排队。表可能会丢，但产物名是确定的
        // `<stem>-30fps.mp4`：少了这一句，重装之后扫出来的全是「待降帧」，而它们其实早就降过。
        let derivativeAttributes = try? FileManager.default.attributesOfItem(atPath: derivative.path)
        let alreadyConverted = derivativeAttributes != nil
        let entry = FrameRateEntry(
            sourcePath: source.path,
            sourceSize: attributes?[.size] as? Int ?? 0,
            sourceMtime: attributes?[.modificationDate] as? Date ?? Date(timeIntervalSince1970: 0),
            fps: fps, durationSeconds: meta.durationSeconds ?? 0,
            derivativePath: derivative.path,
            derivativeMtime: derivativeAttributes?[.modificationDate] as? Date,
            state: alreadyConverted
                ? .done
                : (FpsDownscaleCommand.needsDownscale(fps) ? .needsConvert : .okAt30))
        try? table.upsert(entry, to: tableURL)
        return entry.state == .needsConvert ? fps : nil
    }

    // MARK: - 路径

    private var convertedDirectory: URL {
        root.appendingPathComponent(MediaLibrary.excludedDirectoryName, isDirectory: true)
    }

    private func derivativeURL(for source: URL) -> URL {
        convertedDirectory.appendingPathComponent(FpsDownscaleCommand.derivativeName(for: source))
    }

    private func temporaryURL(for source: URL) -> URL {
        derivativeURL(for: source).appendingPathExtension("tmp")
    }

    // MARK: - drain

    /// 串行 drain。用 `while` 重取下标而不是 `for in jobs.indices` —— 索引范围在循环开始时求值一次，运行中追加的 job 本轮看不到。
    public func run() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false; onBatchFinished?() }

        var didWork = false
        while true {
            guard let index = jobs.firstIndex(where: { $0.state == .pending }) else { break }
            // 暂停/取消在每个 job 之前判定 —— 暂停语义是「当前文件跑完再停」。
            if shouldStop() {
                if consumeCancel() { jobs[index].state = .pending; onJobsChanged?() }
                break
            }
            await runJob(at: index)
            didWork = true
        }
        _ = didWork
    }

    private func runJob(at index: Int) async {
        let source = jobs[index].sourceURL

        guard case .available(let toolPath) = availability() else {
            jobs[index].state = .failed(reason: "ffmpeg_unavailable")
            onJobsChanged?()
            return
        }
        try? FileManager.default.createDirectory(
            at: convertedDirectory, withIntermediateDirectories: true)
        if let free = freeSpaceProvider(convertedDirectory),
           let size = (try? FileManager.default.attributesOfItem(atPath: source.path))?[.size] as? Int64,
           free < size {
            jobs[index].state = .failed(reason: "disk_space")
            onJobsChanged?()
            return
        }

        jobs[index].state = .running
        onJobsChanged?()

        let temporary = temporaryURL(for: source)
        let progress = ProgressState()
        let meta = await specProvider(source)
        let status = await runner.run(
            ffmpegPath: toolPath,
            arguments: FpsDownscaleCommand.arguments(input: source, output: temporary),
            outputTemporaryPath: temporary.path
        ) { [weak self] line in
            Task { @MainActor in
                guard let self else { return }
                self.jobs[index].percent = progress.consume(line, durationSeconds: meta.durationSeconds)
                self.onJobsChanged?()
            }
        }

        let final = convertedDirectory
            .appendingPathComponent(FpsDownscaleCommand.derivativeName(for: source))
        if status == 0 {
            do {
                if FileManager.default.fileExists(atPath: final.path) {
                    try FileManager.default.removeItem(at: final)
                }
                try FileManager.default.moveItem(at: temporary, to: final)
                jobs[index].state = .done
                // 必须写回表：不写的话下次扫描这些行仍是 needsConvert，已转文件会被重新排队。
                writeTableState(.done, for: source)
            } catch {
                try? FileManager.default.removeItem(at: temporary)
                jobs[index].state = .failed(reason: "output_conflict")
                writeTableState(.failed, for: source)
            }
        } else {
            // 半成品绝不能留在 Converted/ —— 它扩展名合法，会被扫进播放池。
            try? FileManager.default.removeItem(at: temporary)
            jobs[index].state = .failed(reason: "exit_nonzero")
            writeTableState(.failed, for: source)
        }
        onJobsChanged?()
    }

    /// 状态跃迁时回写帧率表。写失败不阻塞 —— 表只是加速手段，丢了就退化成全量重探。
    private func writeTableState(_ state: ProbeState, for source: URL) {
        var table = FrameRateTable.load(from: tableURL)
        try? table.updateState(state, for: source, to: tableURL)
    }
}

/// 进度累加器的 `@MainActor` 壳 —— `onProgressLine` 是 `@Sendable`，不能可变捕获 `Accumulator`；所有读写都在 `Task { @MainActor }` 里。
@MainActor
private final class ProgressState {
    private var accumulator = ProgressParser.Accumulator()

    func consume(_ line: String, durationSeconds: Double?) -> Double? {
        ProgressParser.percent(snapshot: accumulator.consume(line), durationSeconds: durationSeconds)
    }
}