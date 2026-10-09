import Foundation


/// 装载 seam。标 `@MainActor`：conformer 是 `@MainActor` 类型，不标会让 Swift 6 报
/// `#ConformanceIsolation`。方法名与产品侧刻意错开（那边「装载并遵守仲裁」）。
@MainActor
public protocol VideoLoading: AnyObject {
    func loadPlayback(url: URL)
}


/// 轮换 → 装载的路由器。只负责「下一条装载哪一条」；装载之后该不该播由产品侧的
/// 适配器走仲裁器的当前决策决定（单向流：Watcher → 仲裁器 → 播放内核，router 不在链上）。
/// **零播放框架、零 AppKit** —— 只对协议说话，因此「轮换驱动装载」在无屏幕环境可测。
@MainActor
public final class PlaybackRouter {

    public private(set) var loadCount: Int = 0

    private let rotation: RotationController
    private let loader: any VideoLoading
    /// `start()` 之后才为 true。判的是「有没有把 `onAdvance` 绑上」，与播放是否暂停无关 ——
    /// `stop()` 解绑了 `onAdvance`，所以它也跟着回落 false（否则 refresh 会走进一条没有订阅的路径）。
    private var isBound = false

    public init(rotation: RotationController, loader: any VideoLoading) {
        self.rotation = rotation
        self.loader = loader
    }

    /// 装载分派：换列表并起转。**顺序写死** —— 先绑 `onAdvance`、`setItems`、再 `start()`
    ///（这一步立刻回调一次首条）。绑在 `start()` 之前是硬要求：反序会漏掉首条。
    /// `resumingAt` 非空时走定点启动（单循环续播：从上次播放的文件接着来）。
    public func start(with items: [VideoItem], resumingAt url: URL? = nil) {
        bind()
        // 轮换内核只认 URL（图片来源复用同一个内核），`VideoItem` 这一层包装在进出时剥掉。
        rotation.setItems(items.map(\.url))
        if let url {
            rotation.start(resumingAt: url)
        } else {
            rotation.start()
        }
    }

    /// 重扫后的清单更新 —— **唯一的「不打断当前播放」入口**。
    /// 正在播的那条还在新清单里 → 一次装载都没有（播放原地继续）；
    /// 它已经不在了（被删 / 换目录 / 转码删了源）→ 才从头起一轮。
    /// 少了这条入口，任何一次重扫（换个设置、转完一个批次）都会把壁纸拽回列表第一条从头播。
    public func refresh(with items: [VideoItem]) {
        guard isBound else { start(with: items); return }
        if rotation.refreshItems(items.map(\.url)) { return }
        rotation.start()
    }

    private func bind() {
        // 记的是**真的交出去的装载次数，不是播放状态**。
        rotation.onAdvance = { [weak self] url in
            self?.loader.loadPlayback(url: url)
            self?.loadCount += 1
        }
        isBound = true
    }

    /// 是否已经起过一轮（`start()` 或 `refresh()` 的回退路径绑上过 `onAdvance`）。
    /// 启动路径上 `rescanAndApply()` 已经起过一轮，再 start 一次会把首条重新装载一遍
    /// （随机模式下还会重新抽签，观感是开场闪一下）。
    public var isStarted: Bool { isBound }

    /// 停转并解绑（`RotationController.stop()` 内部已清 `onAdvance`）。
    public func stop() {
        rotation.stop()
        isBound = false
    }

    public func advanceNow() {
        rotation.advanceNow()
    }

    /// 当前条目。轮换内核只存 URL，出口处包回 `VideoItem` ——
    /// 调用方（菜单 / 设置窗）拿到的仍是条目类型，不受内核换类型的影响。
    public var current: VideoItem? {
        rotation.current.map(VideoItem.init(url:))
    }
}
