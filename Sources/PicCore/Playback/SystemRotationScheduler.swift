import Foundation

/// 主 runloop 的轮换定时器 —— `RotationScheduling` 的生产实现。
///
/// **不标 `@MainActor`**：协议 `RotationScheduling` 没标（协议整体标
/// `@MainActor` 会在 Swift 6 下报 `#ConformanceIsolation`），由持有它的
/// `@MainActor` `RotationController` 负责隔离。
///
/// `.common` 模式：菜单拖动期间定时器仍走。
///
/// 满足上面那条「body 必须回到主线程」的契约：`RunLoop.main.add` 保证回调在主线程上跑。
public final class SystemRotationScheduler: RotationScheduling {

    private var timer: Timer?

    public init() {}

    public func schedule(after interval: TimeInterval, _ body: @escaping () -> Void) {
        // 摘干净旧定时器再排新的 —— 每换一片都会重排一次，摘不净会随轮换次数线性累积。
        cancel()
        let t = Timer(timeInterval: interval, repeats: false) { _ in body() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    public func cancel() {
        timer?.invalidate()
        timer = nil
    }

    /// 兜底清理。本类由 AppDelegate 强持有、生命周期与进程一致，正常路径轮不到这里。
    deinit {
        timer?.invalidate()
    }
}
