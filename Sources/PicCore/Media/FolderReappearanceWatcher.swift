import Foundation

/// 「壁纸目录消失后又回来」的看护：只在目录**已确认不存在**时启动，按固定间隔轮询它是否回来，
/// 回来就回调一次并自动停止。
///
/// 刻意不用 FSEvents / DispatchSource：那条路要盯着「不存在的路径」的父目录，还得在卷重挂后重臂 fd，
/// 复杂度远高于收益。本看护只在坏状态下活着 —— 目录正常时它一次都不跑。
///
/// 整条链都门在 MainActor 上：回调要碰 `MediaLibrary` 与窗口，跨出去再回来只会多一层竞态。
@MainActor
public final class FolderReappearanceWatcher {

    /// 注入的调度器：每 `interval` 秒跑一次 `body`，返回停止闭包。测试注入手动触发的替身。
    public typealias Scheduler = @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> @MainActor () -> Void

    /// 生产调度器：MainActor 隔离的 `Task` 循环。刻意**不用 `Timer`** ——
    /// `Timer` 的回调块是 `@Sendable`、不带 MainActor 隔离，捕获 MainActor 上的 body 会被判成跨域发送；
    /// 而 `Task.sleep` 本来就不受 runloop 模式影响（`Timer` 要专门加 `.common` 才不被菜单拖动卡住）。
    public static let taskScheduler: Scheduler = { interval, body in
        let task = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                if Task.isCancelled { return }
                body()
            }
        }
        return { task.cancel() }
    }

    private let scheduler: Scheduler
    private var cancel: (() -> Void)?

    public init(scheduler: @escaping Scheduler = FolderReappearanceWatcher.taskScheduler) {
        self.scheduler = scheduler
    }

    /// 是否正在等。
    public var isWaiting: Bool { cancel != nil }

    /// 开始等目录回来。**已在等则先停掉旧的** —— 换目录后必须盯新目录，留下旧定时器会让回调用旧路径判存在性。
    /// - Parameter isBack: 每次轮询调一次；返回 true 视作目录已回来。
    public func awaitReturn(interval: TimeInterval = 3,
                            isBack: @escaping @MainActor () -> Bool,
                            onReturned: @escaping @MainActor () -> Void) {
        stop()
        cancel = scheduler(interval) { [weak self] in
            guard let self, isBack() else { return }
            self.stop()
            onReturned()
        }
    }

    public func stop() {
        cancel?()
        cancel = nil
    }
}
