import XCTest
@testable import PicCore

/// 轮换 → 装载装配链的行为判据。
///
/// **不引入任何播放框架**：`PlaybackRouter` 只对协议说话，「轮换驱动装载」
/// 因此在无屏幕环境可测 —— `advanceNow()` 就是全部驱动，没有 runloop、
/// 没有任何 AV 对象、不需要媒体语料（路径用临时目录拼接）。
@MainActor
final class PlaybackRouterTests: XCTestCase {

    // MARK: - 文件内替身（不跨文件引用别的测试类的 helper）

    /// 记录式装载端：只记 URL 的个数与顺序。
    final class RecordingLoader: VideoLoading {
        private(set) var loaded: [URL] = []

        func loadPlayback(url: URL) {
            loaded.append(url)
        }
    }

    /// 只存闭包不触发：本文件不需要到点回调驱动，`advanceNow()` 足够。
    final class NoopScheduler: RotationScheduling {
        private var body: (() -> Void)?

        func schedule(after interval: TimeInterval, _ body: @escaping () -> Void) {
            self.body = body
        }

        func cancel() {
            body = nil
        }
    }

    // MARK: - 工具

    /// 三条人造条目：临时目录拼接，不碰媒体语料。
    private func makeItems(_ count: Int) -> [VideoItem] {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        return (0..<count).map { VideoItem(url: dir.appendingPathComponent("p4-0405-item-\($0).bin")) }
    }

    private func makeRouter(mode: PlayMode)
        -> (rotate: RotationController, loader: RecordingLoader, router: PlaybackRouter) {
        let rotate = RotationController(scheduler: NoopScheduler(),
                                        random: SeededRandomSource(seed: 42))
        rotate.setMode(mode)
        let loader = RecordingLoader()
        let router = PlaybackRouter(rotation: rotate, loader: loader)
        return (rotate, loader, router)
    }

    // MARK: - 用例

    /// start() 当场装载首条：`onAdvance` 必须绑在 `start()` 之前，反序会漏掉第一条。
    func testStartLoadsFirstItemForLoopSingle() {
        let items = makeItems(3)
        let (_, loader, router) = makeRouter(mode: .loopSingle)

        router.start(with: items)

        XCTAssertEqual(loader.loaded.count, 1)
        XCTAssertEqual(loader.loaded.first, items[0].url)
        XCTAssertEqual(router.loadCount, 1)
    }

    /// 「立即下一个」按列表顺序前进。
    func testAdvanceNowLoadsNextInLoopList() {
        let items = makeItems(3)
        let (_, loader, router) = makeRouter(mode: .loopList)

        router.start(with: items)
        router.advanceNow()
        router.advanceNow()

        XCTAssertEqual(loader.loaded, [items[0].url, items[1].url, items[2].url])
    }

    /// 随机模式一轮内每条恰好一次（内核那条在装配链上的延续）。
    func testShuffleRoundVisitsEveryItemExactlyOnce() {
        let items = makeItems(3)
        let (_, loader, router) = makeRouter(mode: .shuffle)

        router.start(with: items)
        router.advanceNow()
        router.advanceNow()
        router.advanceNow()

        XCTAssertEqual(loader.loaded.count, 4)
        XCTAssertEqual(Set(loader.loaded.dropFirst()), Set(items.map(\.url)))
        XCTAssertEqual(Set(loader.loaded.dropFirst()).count, 3)
    }

    /// 空列表零装载（降级路径在装配链上的前置）。
    func testEmptyItemsLoadsNothing() {
        let (_, loader, router) = makeRouter(mode: .loopList)

        router.start(with: [])

        XCTAssertTrue(loader.loaded.isEmpty)
        XCTAssertEqual(router.loadCount, 0)
        XCTAssertNil(router.current)
    }

    /// 重绑不会让单次 advance 多装载 —— 装载次数不随轮换线性放大。
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
