import Combine
import Foundation
import PicCore

/// 转码窗口的队列观察者（呈现层）。
///
/// 队列数据**只**经 `TranscodeQueue.onJobsChanged` 回调进来 —— PicCore 保持零 UI 框架
/// （分层不破）。本类不做任何判定之外的 IO：ffmpeg 定位交给注入的 locator，
/// 文件大小读 `.size`（读不到就显示 `—`，不猜）。
@MainActor
final class TranscodeViewModel: ObservableObject {

    @Published private(set) var jobs: [TranscodeJob] = []
    @Published private(set) var availability: FFmpegToolStatus = .unavailable
    @Published private(set) var isRunning = false

    private let queue: TranscodeQueue
    private let locator: ExternalToolLocator
    private let wallpaperRootProvider: () -> URL?
    /// 转码源选择面板（与壁纸目录选择同一个 seam 实例 —— 全仓唯一 NSOpenPanel 落点）。
    private let sourcePicker: any FolderPicker

    init(queue: TranscodeQueue, locator: ExternalToolLocator,
         wallpaperRootProvider: @escaping () -> URL?,
         sourcePicker: any FolderPicker) {
        self.queue = queue
        self.locator = locator
        self.wallpaperRootProvider = wallpaperRootProvider
        self.sourcePicker = sourcePicker
        queue.onJobsChanged = { [weak self] in self?.reload() }
        reload()
    }

    /// 每次开窗都重查：用户中途装上 ffmpeg 不用重启 app。
    func refresh() {
        availability = locator.locate()
    }

    /// 壁纸目录里的转码候选 → 队列的 pending jobs（**自动来源**：转码成功后自动删源）。
    /// 同路径去重在队列侧。
    func loadCandidates() {
        guard let root = wallpaperRootProvider() else { return }
        queue.enqueue(sources: TranscodeCandidateFilter.candidates(in: root), deletesSource: true)
        reload()
    }

    /// 用户手动选择目录/文件（**手动来源**：源文件永不删除）。
    /// 目录递归展开成 N 个候选（与自动扫描同一过滤器）；白名单外的散选文件静默过滤。
    func loadPickedSources() async {
        guard let picked = await sourcePicker.pickTranscodeSources(), !picked.isEmpty else { return }
        var sources: [URL] = []
        var isDir: ObjCBool = false
        for url in picked {
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            if isDir.boolValue {
                sources.append(contentsOf: TranscodeCandidateFilter.candidates(in: url))
            } else if TranscodeCandidateFilter.candidateExtensions.contains(url.pathExtension.lowercased()) {
                sources.append(url)
            }
        }
        queue.enqueue(sources: sources, deletesSource: false)
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