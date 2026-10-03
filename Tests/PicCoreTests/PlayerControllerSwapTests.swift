import AVFoundation
import XCTest
@testable import PicCore

/// 不变量：`load` 返回时队列已经非空。
///
/// 旧的清空形态在「清空后」到「looper 异步补位前」有一段空队列，图层无
/// currentItem 可呈现。判据在第二次装载上取：装载一返回就同步读队列，
/// 不给 runloop 补位的机会。
@MainActor
final class PlayerControllerSwapTests: XCTestCase {

    func testLoadLeavesQueueNonEmptyImmediately() async throws {
        // 干净 clone 上 fixtures/ 不存在（gitignored），本条跳过，不影响其余用例。
        let clipA = URL(fileURLWithPath: "fixtures/clip-a.mp4")
        let clipB = URL(fileURLWithPath: "fixtures/clip-b.mp4")
        guard FileManager.default.fileExists(atPath: clipA.path),
              FileManager.default.fileExists(atPath: clipB.path) else {
            throw XCTSkip("干净 clone 上 fixtures/ 不存在，本条跳过，不影响其余用例")
        }

        let controller = PlayerController()
        controller.load(url: clipA)

        // 等 looper 首次入队。必须 await Task.sleep：Thread.sleep 堵死主 run loop。
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertGreaterThanOrEqual(
            controller.player.items().count, 1,
            "前置：首次装载后队列应非空，否则后续判据无意义"
        )

        let previousItem = controller.player.currentItem

        controller.load(url: clipB)

        XCTAssertGreaterThanOrEqual(
            controller.player.items().count, 1,
            "load 返回时队列必须已非空 —— 旧实现的空队列帧就在这一刻"
        )
        let current = controller.player.currentItem
        XCTAssertNotNil(current, "交接完成后必须有 currentItem 可呈现")
        XCTAssertTrue(current !== previousItem,
                      "currentItem 必须是新条目，留旧的就是旧片继续播")
        XCTAssertTrue(controller.player.items().allSatisfy { $0 !== previousItem },
                      "items() 不得残留旧条目 —— 只 insert 不扫会让队列无界增长")
    }
}
