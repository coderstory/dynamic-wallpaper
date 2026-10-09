import Foundation
import XCTest
@testable import PicCore

/// 图片侧的装载分派。与 `PlaybackRouterTests` 同款可注入替身，不碰真实图片、不碰 AppKit。
@MainActor
final class ImagePlaybackRouterTests: XCTestCase {

    /// 手动调度器：排程不真跑，由用例手动触发。
    private final class ManualScheduler: RotationScheduling {
        var pending: TimeInterval?
        var body: (@MainActor () -> Void)?
        var scheduleCount = 0

        func schedule(after interval: TimeInterval, _ body: @escaping @MainActor () -> Void) {
            pending = interval
            self.body = body
            scheduleCount += 1
        }

        func cancel() { pending = nil; body = nil }
    }

    private final class FakeLoader: ImageLoading {
        var shown: [URL] = []
        func showImage(url: URL) { shown.append(url) }
    }

    private func makeRotation() -> (RotationController, ManualScheduler) {
        let scheduler = ManualScheduler()
        let rotation = RotationController(scheduler: scheduler, random: SeededRandomSource(seed: 7))
        return (rotation, scheduler)
    }

    private func urls(_ count: Int) -> [URL] {
        (0..<count).map { URL(fileURLWithPath: "/tmp/pic-image-\($0).png") }
    }

    func testStartLoadsFirstImageImmediately() {
        let (rotation, scheduler) = makeRotation()
        let loader = FakeLoader()
        let router = ImagePlaybackRouter(rotation: rotation, loader: loader)

        router.start(with: urls(3))

        XCTAssertEqual(loader.shown.count, 1, "首张必须在 start() 里就装载")
        XCTAssertEqual(loader.shown.first, URL(fileURLWithPath: "/tmp/pic-image-0.png"))
        XCTAssertNotNil(scheduler.pending, "start 之后必须排下一程")
        XCTAssertTrue(router.isStarted)
    }

    /// 单张循环续播：从上次显示的那张接着来，而不是回到第一张。
    func testStartResumingAtLoadsThatImage() {
        let (rotation, _) = makeRotation()
        let loader = FakeLoader()
        let router = ImagePlaybackRouter(rotation: rotation, loader: loader)
        rotation.mode = .loopSingle

        router.start(with: urls(3), resumingAt: URL(fileURLWithPath: "/tmp/pic-image-2.png"))

        XCTAssertEqual(loader.shown, [URL(fileURLWithPath: "/tmp/pic-image-2.png")])
        XCTAssertEqual(router.current, URL(fileURLWithPath: "/tmp/pic-image-2.png"))
    }

    /// 重扫时正在显示的图还在 → 一次装载都没有（显示原地继续）。
    /// 少了这条，每次重扫都会把壁纸拽回第一张。
    func testRefreshKeepsCurrentImageWhenItIsStillInList() {
        let (rotation, _) = makeRotation()
        let loader = FakeLoader()
        let router = ImagePlaybackRouter(rotation: rotation, loader: loader)
        rotation.mode = .loopList

        router.start(with: urls(3))
        schedulerFire(rotation)
        XCTAssertEqual(loader.shown.count, 2)

        var list = urls(3)
        list.removeFirst()          // 第一张被删了，当前显示的第二张还在
        router.refresh(with: list)

        XCTAssertEqual(loader.shown.count, 2, "当前那张还在就不该重新装载")
        XCTAssertEqual(router.current, list.first)
    }

    /// 当前那张已经不在（被删）→ 从头起一轮。
    func testRefreshRestartsWhenCurrentImageIsGone() {
        let (rotation, _) = makeRotation()
        let loader = FakeLoader()
        let router = ImagePlaybackRouter(rotation: rotation, loader: loader)

        router.start(with: urls(3))
        router.refresh(with: [URL(fileURLWithPath: "/tmp/other.png")])

        XCTAssertEqual(loader.shown.last, URL(fileURLWithPath: "/tmp/other.png"))
        XCTAssertEqual(loader.shown.count, 2)
    }

    /// 空清单：不装载、不排程（与视频侧的降级路径一致）。
    func testEmptyListLoadsNothing() {
        let (rotation, scheduler) = makeRotation()
        let loader = FakeLoader()
        let router = ImagePlaybackRouter(rotation: rotation, loader: loader)

        router.start(with: [])

        XCTAssertTrue(loader.shown.isEmpty)
        XCTAssertNil(scheduler.pending)
    }

    /// 两个 router 共用一个轮换内核 —— 后 start 的接管 `onAdvance`。
    /// 切来源时必须先 `stop()` 旧的，否则两个装载端会同时收到回调。
    func testSecondRouterTakesOverTheSharedRotation() {
        let (rotation, _) = makeRotation()
        let imageLoader = FakeLoader()
        let secondLoader = FakeLoader()
        let first = ImagePlaybackRouter(rotation: rotation, loader: imageLoader)
        let second = ImagePlaybackRouter(rotation: rotation, loader: secondLoader)

        first.start(with: urls(2))
        first.stop()
        second.start(with: urls(2))

        XCTAssertEqual(imageLoader.shown.count, 1)
        XCTAssertEqual(secondLoader.shown.count, 1)
        XCTAssertFalse(first.isStarted)
        rotation.advanceNow()
        XCTAssertEqual(secondLoader.shown.count, 2, "接管后只有新的装载端在收回调")
        XCTAssertEqual(imageLoader.shown.count, 1, "已 stop 的那个不该再收到")
    }

    private func schedulerFire(_ rotation: RotationController) {
        rotation.advanceNow()
    }
}
