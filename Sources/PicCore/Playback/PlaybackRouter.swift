import Foundation

// MARK: - 注入 seam

/// 装载 seam。标 `@MainActor`：conformer 是 `@MainActor` 类型，不标会让 Swift 6 报
/// `#ConformanceIsolation`。方法名与产品侧刻意错开（那边「装载并遵守仲裁」）。
@MainActor
public protocol VideoLoading: AnyObject {
    func loadPlayback(url: URL)
}

// MARK: - 路由器

/// 轮换 → 装载的路由器。只负责「下一条装载哪一条」；装载之后该不该播由产品侧的
/// 适配器走仲裁器的当前决策决定（单向流：Watcher → 仲裁器 → 播放内核，router 不在链上）。
/// **零播放框架、零 AppKit** —— 只对协议说话，因此「轮换驱动装载」在无屏幕环境可测。
@MainActor
public final class PlaybackRouter {

    public private(set) var loadCount: Int = 0

    private let rotation: RotationController
    private let loader: any VideoLoading

    public init(rotation: RotationController, loader: any VideoLoading) {
        self.rotation = rotation
        self.loader = loader
    }

    /// 装载分派：换列表并起转。**顺序写死** —— 先绑 `onAdvance`、`setItems`、再 `start()`
    ///（这一步立刻用 `items[0]` 回调一次）。绑在 `start()` 之前是硬要求：反序会漏掉首条。
    public func start(with items: [VideoItem]) {
        // 记的是**真的交出去的装载次数，不是播放状态**。
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

    public func advanceNow() {
        rotation.advanceNow()
    }

    public var current: VideoItem? {
        rotation.current
    }
}
