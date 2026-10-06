import AVFoundation
import XCTest
@testable import PicCore

/// 场景 C8/C9（恢复播放后速度回落 1.0）。
///
/// `AVPlayer.play()` 等价于把 rate 置 1.0，不是置回用户设的速度。所以任何一次 hold
/// 解除（锁屏→解锁 / 退出全屏 / 插电 / 手动继续）都会把用户设的速度抹掉。
/// 契约：恢复走的是**记住的速度**，不是 1.0。
@MainActor
final class PlayerControllerRateRestoreTests: XCTestCase {

    private func makeController() -> PlayerController { PlayerController() }

    func testSetRateRecordsDesiredRate() {
        let controller = makeController()
        XCTAssertEqual(controller.desiredRate, 1.0, "未设过速度时默认 1.0")
        controller.setRate(1.5)
        XCTAssertEqual(controller.desiredRate, 1.5, "setRate 必须记住速度，供恢复时回放")
    }

    func testHeldRateChangeIsRecordedWithoutStartingPlayback() {
        let controller = makeController()
        // hold 期间改速度：只记，不把播放器拉起。
        controller.setDesiredRate(1.75)
        XCTAssertEqual(controller.desiredRate, 1.75)
        XCTAssertEqual(controller.player.rate, 0, "只记不应用 —— 拉起播放器就是绕过仲裁器")
    }

    func testResumeRestoresDesiredRateInsteadOfOne() {
        let controller = makeController()
        controller.setRate(1.5)

        // 锁屏：停播。
        controller.arbiterApply(PlaybackDecision(holds: [.screenLocked]))
        XCTAssertEqual(controller.player.rate, 0, "前置：hold 必须在播")

        // 解锁：恢复。旧实现是 play() → rate 1.0，用户设的 1.5 丢了。
        controller.arbiterApply(PlaybackDecision())
        XCTAssertEqual(controller.player.rate, 1.5,
                       "恢复播放必须回到用户设的速度，不是 AVPlayer.play() 的 1.0")
    }

    func testManualPauseResumeKeepsRate() {
        let controller = makeController()
        controller.setRate(0.5)
        controller.arbiterApply(PlaybackDecision(holds: [.manualPause]))
        controller.arbiterApply(PlaybackDecision())
        XCTAssertEqual(controller.player.rate, 0.5, "手动暂停/继续同样不能丢速度")
    }

    func testStopDoesNotForgetDesiredRate() {
        let controller = makeController()
        controller.setRate(2.0)
        controller.stop()
        XCTAssertEqual(controller.desiredRate, 2.0, "stop() 清的是队列，不是用户设的速度")
    }
}
