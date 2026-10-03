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

// MARK: - 路由器（RED 骨架：只保证可编译，行为留空）

@MainActor
public final class PlaybackRouter {

    public private(set) var loadCount: Int = 0

    private let rotation: RotationController
    private let loader: any VideoLoading

    public init(rotation: RotationController, loader: any VideoLoading) {
        self.rotation = rotation
        self.loader = loader
    }

    public func start(with items: [VideoItem]) {
        rotation.setItems(items)
    }

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
