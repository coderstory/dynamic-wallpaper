import Foundation

/// 图片显示的 seam。**只收 URL**：解码在实现类内部（后台）完成，seam 上不传 `CGImage` ——
/// 传图等于要求调用方先解码，那一步就跑到主线程上去了。
@MainActor
public protocol ImageLoading: AnyObject {
    func showImage(url: URL)
}

/// 图片侧「轮换 → 显示」的路由器。
///
/// 与 `PlaybackRouter` 同构、共用**同一个** `RotationController` 实例 —— 间隔、播放模式、
/// 让路暂停、`advanceNow`、菜单倒计时环因此两边完全一致。**刻意不写第二套轮换内核**：
/// 两套定时逻辑意味着「轮换不准时」这类 bug 要修两遍，且修完一边很容易忘了另一边。
///
/// 差别只有装载端：`PlaybackRouter` 交给播放器，这里交给「解码并显示」。
@MainActor
public final class ImagePlaybackRouter {

    public private(set) var loadCount: Int = 0

    private let rotation: RotationController
    private let loader: any ImageLoading
    /// 与 `PlaybackRouter.isBound` 同义：`start()` 之后才为 true，`stop()` 解绑后回落。
    private var isBound = false

    public init(rotation: RotationController, loader: any ImageLoading) {
        self.rotation = rotation
        self.loader = loader
    }

    /// **顺序写死**：先绑 `onAdvance` → `setItems` → 再 `start()`（这一步立刻回调首张）。
    /// 绑在 `start()` 之前是硬要求，反序会漏掉首张。
    public func start(with urls: [URL], resumingAt url: URL? = nil) {
        bind()
        rotation.setItems(urls)
        if let url {
            rotation.start(resumingAt: url)
        } else {
            rotation.start()
        }
    }

    /// 重扫后的清单更新 —— 与视频侧同款「不打断当前显示」入口。
    public func refresh(with urls: [URL]) {
        guard isBound else { start(with: urls); return }
        if rotation.refreshItems(urls) { return }
        rotation.start()
    }

    private func bind() {
        rotation.onAdvance = { [weak self] url in
            self?.loader.showImage(url: url)
            self?.loadCount += 1
        }
        isBound = true
    }

    public var isStarted: Bool { isBound }

    /// 停转并解绑。**与 `PlaybackRouter.stop()` 成对使用**：切来源时先停掉旧的再起新的，
    /// 否则两个 router 会争抢同一个 `onAdvance`（后绑的赢，先绑的静默失效）。
    public func stop() {
        rotation.stop()
        isBound = false
    }

    public func advanceNow() {
        rotation.advanceNow()
    }

    public var current: URL? { rotation.current }
}
