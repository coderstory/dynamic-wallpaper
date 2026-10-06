import XCTest
@testable import PicCore

/// `PlaybackRouter` 只对协议说话，所以整条「轮换驱动装载」链在无屏幕环境可测 —— `advanceNow()` 就是全部驱动，没有 runloop、没有 AV 对象、不需要媒体语料（路径用临时目录拼接）。
@MainActor
final class PlaybackRouterTests: XCTestCase {

    // 文件内替身不跨测试文件复用 —— 跨文件耦合后失败时分不清是替身坏了还是被测代码坏了。

    /// 只记 URL 的个数与顺序。
    @MainActor
    final class RecordingLoader: VideoLoading {
        private(set) var loaded: [URL] = []

        func loadPlayback(url: URL) {
            loaded.append(url)
        }
    }

    /// 只存闭包不触发：本文件不需要到点回调驱动，`advanceNow()` 足够。
    final class NoopScheduler: RotationScheduling {
        private var body: (@MainActor () -> Void)?

        func schedule(after interval: TimeInterval, _ body: @escaping @MainActor () -> Void) {
            self.body = body
        }

        func cancel() {
            body = nil
        }
    }

    private func makeItems(_ count: Int) -> [VideoItem] {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        return (0..<count).map { VideoItem(url: dir.appendingPathComponent("p4-0405-item-\($0).bin")) }
    }

    private func makeRouter(mode: PlayMode)
        -> (rotate: RotationController, loader: RecordingLoader, router: PlaybackRouter) {
        let rotate = RotationController(scheduler: NoopScheduler(),
                                        random: SeededRandomSource(seed: 42))
        rotate.mode = mode
        let loader = RecordingLoader()
        let router = PlaybackRouter(rotation: rotate, loader: loader)
        return (rotate, loader, router)
    }

    /// `onAdvance` 必须绑在 `start()` 之前，反序会漏掉第一条。
    func testStartLoadsFirstItemForLoopSingle() {
        let items = makeItems(3)
        let (_, loader, router) = makeRouter(mode: .loopSingle)

        router.start(with: items)

        XCTAssertEqual(loader.loaded.count, 1)
        XCTAssertEqual(loader.loaded.first, items[0].url)
        XCTAssertEqual(router.loadCount, 1)
    }

    func testAdvanceNowLoadsNextInLoopList() {
        let items = makeItems(3)
        let (_, loader, router) = makeRouter(mode: .loopList)

        router.start(with: items)
        router.advanceNow()
        router.advanceNow()

        XCTAssertEqual(loader.loaded, [items[0].url, items[1].url, items[2].url])
    }

    /// 一轮从 `start()` 交出的首条起算，所以三条片子只要驱两次切换就走完一轮。
    func testShuffleRoundVisitsEveryItemExactlyOnce() {
        let items = makeItems(3)
        let (_, loader, router) = makeRouter(mode: .shuffle)

        router.start(with: items)
        router.advanceNow()
        router.advanceNow()

        XCTAssertEqual(loader.loaded.count, 3, "首条 + 两次切换 = 一轮三条")
        XCTAssertEqual(Set(loader.loaded), Set(items.map(\.url)), "一轮内三条各来一次")
        XCTAssertEqual(Set(loader.loaded).count, 3)
    }

    /// 重扫不得打断正在播的那条：清单一模一样地再来一次，一次装载都不该发生。
    func testRefreshKeepsPlaybackWhenItemSurvives() {
        let items = makeItems(3)
        let (_, loader, router) = makeRouter(mode: .loopList)

        router.start(with: items)
        router.advanceNow()
        let loadedBeforeRefresh = loader.loaded.count
        XCTAssertEqual(router.current?.url, items[1].url)

        router.refresh(with: items)

        XCTAssertEqual(loader.loaded.count, loadedBeforeRefresh,
                       "当前那条还在 → 重扫不该重新装载（重装载 = 播放从头开始）")
        XCTAssertEqual(router.current?.url, items[1].url)
    }

    /// 降帧产物顶替原片之后清单顺序会变 —— 当前那条还在就得续着播。
    func testRefreshFollowsCurrentItemToItsNewIndex() {
        let items = makeItems(3)
        let (_, loader, router) = makeRouter(mode: .loopList)

        router.start(with: items)
        router.advanceNow()
        let loadedBeforeRefresh = loader.loaded.count

        router.refresh(with: [items[1], items[2], items[0]])

        XCTAssertEqual(loader.loaded.count, loadedBeforeRefresh, "顺序变了但片子还在 → 不打断")
        XCTAssertEqual(router.current?.url, items[1].url, "currentIndex 必须跟着它挪到新下标")
    }

    /// 唯一的例外：正在播的那条没了（被删 / 换了目录），这时候才重开一轮。
    func testRefreshRestartsOnlyWhenCurrentItemDisappeared() {
        let items = makeItems(3)
        let (_, loader, router) = makeRouter(mode: .loopList)

        router.start(with: items)
        router.advanceNow()
        let loadedBeforeRefresh = loader.loaded.count

        router.refresh(with: [items[0], items[2]])

        XCTAssertEqual(loader.loaded.count, loadedBeforeRefresh + 1, "正在播的那条没了 → 才重开")
        XCTAssertEqual(router.current?.url, items[0].url)
    }

    /// 还没起播时的 refresh 就是 start —— 首次重扫不该走一条没有订阅的路径。
    func testRefreshBeforeStartBehavesLikeStart() {
        let items = makeItems(3)
        let (_, loader, router) = makeRouter(mode: .loopList)

        router.refresh(with: items)

        XCTAssertEqual(loader.loaded.count, 1)
        XCTAssertEqual(router.current?.url, items[0].url)
    }

    /// stop 之后再 refresh 必须重新挂上回调 —— `stop()` 解绑了 `onAdvance`，
    /// 少了这一步会让「隐藏后恢复」变成「清单有了但屏幕永远黑着」。
    func testRefreshAfterStopRebindsLoader() {
        let items = makeItems(3)
        let (_, loader, router) = makeRouter(mode: .loopList)

        router.start(with: items)
        router.stop()

        router.refresh(with: items)

        XCTAssertEqual(loader.loaded.count, 2, "stop 之后的 refresh 必须重新起一轮")
    }

    func testEmptyItemsLoadsNothing() {
        let (_, loader, router) = makeRouter(mode: .loopList)

        router.start(with: [])

        XCTAssertTrue(loader.loaded.isEmpty)
        XCTAssertEqual(router.loadCount, 0)
        XCTAssertNil(router.current)
    }

    /// 重绑不会让单次 advance 多装载 —— 装载次数不随轮换线性放大（重复 `start()` 不叠加订阅）。
    func testStartRebindingDoesNotDoubleLoadPerAdvance() {
        let items = makeItems(3)
        let (_, loader, router) = makeRouter(mode: .loopList)

        router.start(with: items)
        router.start(with: items)
        let afterTwoStarts = loader.loaded.count

        router.advanceNow()

        XCTAssertEqual(loader.loaded.count - afterTwoStarts, 1)
    }
}
