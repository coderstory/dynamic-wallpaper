import AVFoundation
import XCTest
@testable import PicCore

/// D-01 冻结面的**编译期**判据 + `stop()` 的运行时幂等用例。
///
/// `PlayerController` 是 `final class`，子类替身不可用；而「八个签名没被改」
/// 用源码 grep 只能抓到已经发生的破坏。这里用协议 conformance 把它变成
/// **编译期**约束：测试侧逐字复刻八个签名，`extension PlayerController:
/// PlayerControllerSurface {}` 空 conformance 成立即签名逐字匹配 ——
/// 任何一处被改（参数标签、类型、名字、增删）都编译不过。
///
/// 空 conformance 不是 XCTest 用例，不计入 `Executed N tests`；
/// 运行时恰好 1 条：`testStopEmptiesQueueAndIsIdempotent`。
/// D-01 冻结面：八个签名逐字复刻。整体标 `@MainActor`（Swift 5 语言模式下
/// 不标会报隔离错误 —— Phase 1 在 `PlaybackTarget` 上实测过这一类）。
@MainActor
protocol PlayerControllerSurface: AnyObject {
    func attach(to layer: AVPlayerLayer)
    func load(url: URL)
    func setRate(_ r: Float)
    func setVolume(_ v: Float)
    func setMuted(_ m: Bool)
    func arbiterCurrentPosition() -> TimeInterval
    func arbiterSeek(to seconds: TimeInterval)
    func arbiterApply(_ decision: PlaybackDecision)
}

/// 空 conformance：成立即八个签名与 D-01 逐字一致（协议与 extension 都在
/// 文件作用域 —— 嵌在测试类里会互相不可见）。若这里编译失败，说明产品侧
/// 签名被改 —— 改产品代码去迁就协议，不要改协议。
extension PlayerController: PlayerControllerSurface {}

@MainActor
final class PlayerControllerFreezeTests: XCTestCase {

    // MARK: - stop()：清空队列且幂等

    func testStopEmptiesQueueAndIsIdempotent() async throws {
        // 干净 clone 上 fixtures/ 不存在（gitignored），本条跳过，不影响其余用例。
        // 纪律见 MenuBarModelTests：测试不依赖任何可能缺席的文件系统状态。
        let fixture = URL(fileURLWithPath: "fixtures/clip-a.mp4")
        guard FileManager.default.fileExists(atPath: fixture.path) else {
            throw XCTSkip("干净 clone 上 fixtures/ 不存在，本条跳过，不影响其余用例")
        }

        let controller = PlayerController()
        controller.load(url: fixture)

        // 等 looper 把模板 item 真正入队。必须 await Task.sleep（400ms，04-01 tracer
        // 的实测值）：Thread.sleep 堵死主 run loop，looper 的入队派发永远跑不到。
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

        // 幂等：二次调用不得抛错、队列仍为空。
        controller.stop()
        XCTAssertTrue(
            controller.player.items().isEmpty,
            "stop() 必须幂等 —— 探针会反复投降级状态，重复 stop 不得出副作用"
        )
    }
}
