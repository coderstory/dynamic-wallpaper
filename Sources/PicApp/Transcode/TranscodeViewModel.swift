import Combine
import Foundation
import PicCore

/// 转码窗口的队列观察者（TRANS-02 的呈现层）。
///
/// 队列数据**只**经 `TranscodeQueue.onJobsChanged` 回调进来 —— PicCore 保持零
/// UI 框架（06-03 的分层不破）。本类不做任何判定之外的 IO：ffmpeg 定位交给
/// 注入的 locator，文件大小读 `.size`（读不到就显示 `—`，不猜）。
@MainActor
final class TranscodeViewModel: ObservableObject {

    @Published private(set) var jobs: [TranscodeJob] = []
    @Published private(set) var availability: FFmpegToolStatus = .unavailable
    @Published private(set) var isRunning = false

    private let queue: TranscodeQueue
    private let locator: ExternalToolLocator
    private let wallpaperRootProvider: () -> URL?

    init(queue: TranscodeQueue, locator: ExternalToolLocator,
         wallpaperRootProvider: @escaping () -> URL?) {
        self.queue = queue
        self.locator = locator
        self.wallpaperRootProvider = wallpaperRootProvider
        queue.onJobsChanged = { [weak self] in self?.reload() }
        reload()
    }

    /// 每次开窗都重查（RESEARCH Q7）：用户中途装上 ffmpeg 不用重启 app。
    func refresh() {
        availability = locator.locate()
    }

    /// 壁纸目录里的转码候选 → 队列的 pending jobs。同路径去重在队列侧。
    func loadCandidates() {
        guard let root = wallpaperRootProvider() else { return }
        queue.enqueue(sources: TranscodeCandidateFilter.candidates(in: root))
        reload()
    }

    func startTranscoding() {
        guard !isRunning else { return }
        isRunning = true
        Task { await queue.run(); isRunning = false }
    }

    /// 人类可读的源文件大小。读不到不抛、不显示 0 —— 显示 `—`。
    func sizeText(of job: TranscodeJob) -> String {
        let path = job.sourceURL.path
        guard let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int64 else {
            return "—"
        }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    private func reload() {
        jobs = queue.jobs
    }
}