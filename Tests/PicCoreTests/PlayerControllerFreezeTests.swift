import AVFoundation
import XCTest
@testable import PicCore

/// `stop()` 的运行时判据：降级后队列必须清空，且重复 stop 不得有副作用。
///
/// 这里原本还有一份「八签名编译期签名锁」。按设计纪律已删 —— 它锁着的 `attach(to:)`
/// 生产侧零调用、`playerLayer` 零读取，等于用测试替两个死成员续命；真正的接缝是
/// `WallpaperWindow.init(player:)` 自己建 AVPlayerLayer。签名演进靠行为断言守护。
@MainActor
final class PlayerControllerFreezeTests: XCTestCase {

    func testStopEmptiesQueueAndIsIdempotent() async throws {
        let fixture = URL(fileURLWithPath: "fixtures/clip-a.mp4")
        let controller = PlayerController()
        controller.load(url: fixture)

        // 等 looper 把模板 item 真正入队。必须 await Task.sleep（400ms 实测值）：
        // Thread.sleep 堵死主 run loop，looper 的入队派发永远跑不到。
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertGreaterThanOrEqual(
            controller.player.items().count, 1,
            "装载后 looper 应已把模板 item 入队 —— 这条红说明前置没成立，不是 stop() 的问题"
        )

        controller.stop()
        XCTAssertTrue(
            controller.player.items().isEmpty,
            "stop() 之后队列必须为空 —— 否则降级后播放器还持着上一个 item"
        )

        controller.stop()
        XCTAssertTrue(
            controller.player.items().isEmpty,
            "stop() 必须幂等 —— 降级可能被反复触发，重复 stop 不得出副作用"
        )
    }
}
