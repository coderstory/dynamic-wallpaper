import Combine
import Foundation
import PicCore

/// 降帧队列的观察者（呈现层）。数据只经 `onJobsChanged` 回调进来，PicCore 保持零 UI 框架。
@MainActor
final class FpsTranscodeViewModel: ObservableObject {

    @Published private(set) var jobs: [FpsTranscodeQueue.Job] = []
    @Published private(set) var availability: FFmpegToolStatus = .unavailable
    @Published private(set) var isRunning = false
    @Published private(set) var isScanning = false
    /// 帧率表卡的三行读数。
    @Published private(set) var scannedCount = 0
    @Published private(set) var reusedCount = 0
    @Published private(set) var tableTotal = 0
    @Published private(set) var okAt30Count = 0

    private let queue: FpsTranscodeQueue
    private let locator: ExternalToolLocator

    init(queue: FpsTranscodeQueue, locator: ExternalToolLocator) {
        self.queue = queue
        self.locator = locator
        queue.onJobsChanged = { [weak self] in self?.reload() }
        reload()
    }

    func refresh() {
        availability = locator.locate()
    }

    func scan() {
        guard !isScanning, !isRunning else { return }
        isScanning = true
        Task {
            await queue.scan()
            isScanning = false
            reload()
        }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        Task {
            await queue.run()
            isRunning = false
            reload()
        }
    }

    func pause() { queue.pause() }
    func cancel() { queue.cancel() }

    /// 继续。除了清暂停标志，还**必须重新起一轮 drain** —— 暂停的语义是
    /// 「当前文件跑完就停」，`run()` 因此是**退出**而不是挂起。只清标志的话
    /// 「继续」点了没反应，队列从此不动。
    func resume() {
        queue.resume()
        start()
    }

    var isPaused: Bool { queue.isPaused }

    /// UI 的启用判定：可转 = 有 pending 且工具就绪且没在跑。
    var canStart: Bool {
        !isRunning && !isScanning &&
        availabilityIsAvailable && jobs.contains { $0.state == .pending }
    }

    var canPause: Bool { isRunning && !isPaused }
    var canCancel: Bool { isRunning }

    var isEmpty: Bool { jobs.isEmpty && !isScanning }

    private var availabilityIsAvailable: Bool {
        availability.isAvailable
    }

    /// 人类可读的源文件大小。读不到显示 `—`，不猜。
    func sizeText(of job: FpsTranscodeQueue.Job) -> String {
        job.sourceURL.fileSizeText
    }

    private func reload() {
        jobs = queue.jobs
        scannedCount = queue.scannedCount
        reusedCount = queue.reusedCount
        tableTotal = queue.tableTotal
        okAt30Count = queue.okAt30Count
    }
}