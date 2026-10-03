import Foundation

// MARK: - 注入 seam

/// 装载 seam（Plan 04-05 T1）。
///
/// **不标 `@MainActor`**：协议整体标 `@MainActor` 会让 Swift 6 下的
/// conformance 报 `#ConformanceIsolation`（Phase 1 已实测）；由持有它的
/// `@MainActor` `PlaybackRouter` 负责隔离 —— 与 `RotationScheduling`
/// 同款处理。
///
/// 方法名刻意与产品侧的装载方法错开：一侧是「装载并遵守仲裁」，另一侧
/// 只是「装载」—— 两侧语义不同，同名会让人以为可以直接对上。
public protocol VideoLoading: AnyObject {
    func loadPlayback(url: URL)
}

// MARK: - 路由器

/// 轮换 → 装载的路由器（Plan 04-05 T1）。
///
/// 只负责「下一条装载哪一条」；装载之后该不该播，由产品侧的适配器走
/// 仲裁器的当前决策决定（D-06 单向流：Watcher → 仲裁器 → 播放内核，
/// router 不在那条链上）。**零播放框架、零 AppKit** —— 它只对协议说话，
/// 因此「轮换驱动装载」在无屏幕环境可测。
@MainActor
public final class PlaybackRouter {

    public private(set) var loadCount: Int = 0

    private let rotation: RotationController
    private let loader: any VideoLoading

    public init(rotation: RotationController, loader: any VideoLoading) {
        self.rotation = rotation
        self.loader = loader
    }

    /// 装载分派：换列表并起转。**顺序写死**：
    /// 1. 先绑 `onAdvance`（每次 start 只绑一次，重绑覆盖旧闭包）；
    /// 2. `setItems`（索引归 0、清洗牌袋）；
    /// 3. `start()` —— 这一步立刻用 `items[0]` 回调一次。
    /// 绑在 `start()` 之前是硬要求：反序会漏掉首条。
    public func start(with items: [VideoItem]) {
        // `loadCount` 记的是**真的交出去的装载次数，不是播放状态** —— 拿它当
        // 播放状态读会把「装载过」误读成「在播」。
        rotation.onAdvance = { [weak self] item in
            self?.loader.loadPlayback(url: item.url)
            self?.loadCount += 1
        }
        rotation.setItems(items)
        rotation.start()
    }

    /// 停转并解绑（`RotationController.stop()` 内部已清 `onAdvance`）。
    public func stop() {
        rotation.stop()
    }

    /// 「立即下一个」的行为侧入口（SC3）。
    public func advanceNow() {
        rotation.advanceNow()
    }

    public var current: VideoItem? {
        rotation.current
    }
}
