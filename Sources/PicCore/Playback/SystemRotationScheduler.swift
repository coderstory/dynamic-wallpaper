import Foundation

/// 轮换定时器 —— `RotationScheduling` 的生产实现。
///
/// 用 `Task` 而不是 `Timer`：`Timer` 的回调块是 `@Sendable`、不带 MainActor 隔离，
/// 捕获主线程上的 body 会被判「跨隔离域发送」；`Task.sleep` 也**不受 runloop 模式影响**
///（`Timer` 得专门加 `.common` 才不被菜单拖动卡住）。
///
/// **不标 `@MainActor`**：协议没标，标了会报 `#ConformanceIsolation`。主线程由 `Task { @MainActor }` 保证。
public final class SystemRotationScheduler: RotationScheduling {

    private var task: Task<Void, Never>?

    public init() {}

    public func schedule(after interval: TimeInterval, _ body: @escaping @MainActor () -> Void) {
        // 摘干净旧的再排新的 —— 每换一片都会重排一次，摘不净会随轮换次数线性累积。
        cancel()
        task = Task { @MainActor in
            try? await Task.sleep(for: .seconds(interval))
            if Task.isCancelled { return }
            body()
        }
    }

    public func cancel() {
        task?.cancel()
        task = nil
    }

    /// 兜底清理。本类由 AppDelegate 强持有、生命周期与进程一致，正常路径轮不到这里。
    deinit {
        task?.cancel()
    }
}
