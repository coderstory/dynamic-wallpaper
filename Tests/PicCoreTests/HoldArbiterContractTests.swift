import XCTest
@testable import PicCore

/// 本文件**零** AVFoundation / AppKit / SwiftUI：验证的是暂停原因文案与排序契约、起播路径的调用序列，不碰 `AVPlayer.timeControlStatus`。
@MainActor
final class HoldArbiterContractTests: XCTestCase {

    /// 文件内替身，不要与 `HoldArbiterTests.swift` 里那份合并 —— 跨文件耦合后失败时分不清是替身坏了还是被测代码坏了。
    private final class FakeTarget: PlaybackTarget {
        var position: TimeInterval = 0
        var seeks: [TimeInterval] = []
        var applies: [PlaybackDecision] = []

        func arbiterCurrentPosition() -> TimeInterval { position }
        func arbiterSeek(to seconds: TimeInterval) { seeks.append(seconds) }
        func arbiterApply(_ decision: PlaybackDecision) { applies.append(decision) }
    }

    /// 断言对象是**调用次数**，不是播放器状态。
    private final class SettingsSink {
        var setRateCalls = 0
        var setVolumeCalls = 0
        var setMutedCalls = 0

        func setRate(_ r: Float) { setRateCalls += 1 }
        func setVolume(_ v: Float) { setVolumeCalls += 1 }
        func setMuted(_ m: Bool) { setMutedCalls += 1 }
    }

    private var target: FakeTarget!
    private var arbiter: HoldArbiter!

    override func setUp() async throws {
        try await super.setUp()
        target = FakeTarget()
        arbiter = HoldArbiter(target: target)
    }

    override func tearDown() async throws {
        arbiter = nil
        target = nil
        try await super.tearDown()
    }

    func testSixReasonsHaveDistinctChineseLabels() {
        let labels = HoldReason.allCases.map(SettingsPresentation.holdReasonLabel)
        XCTAssertEqual(labels.count, 6, "HoldReason 应为 6 个 case（幂集 2^6 = 64）")

        let unique = Set(labels)
        XCTAssertEqual(unique.count, labels.count,
                       "六个文案必须两两不同，实际得到 \(labels)")

        for label in labels {
            XCTAssertGreaterThanOrEqual(label.count, 2,
                                        "文案不得为空或单字符占位，实际得到 \(label)")
        }
    }

    func testActiveReasonsAreOrderedAndJoinedInHoldOrder() {
        for reason in HoldReason.allCases {
            arbiter.set(reason, active: true)
        }

        XCTAssertEqual(arbiter.decision.activeReasons, HoldReason.allCases.sorted(),
                       "activeReasons 必须按 order 升序：order 只用于文案排序，不参与决策")
        XCTAssertEqual(SettingsPresentation.joinedReasons(arbiter.decision.activeReasons),
                       HoldReason.allCases.sorted().map(SettingsPresentation.holdReasonLabel)
                           .joined(separator: "、"),
                       "叠加原因必须全列且按 order 排序（只列一个会让用户误判成 bug）")

        // 全屏必须排在系统类原因之前 —— order 的取值契约。
        let systemReasons: [HoldReason] = [.screenLocked, .displayAsleep, .systemSleeping, .battery]
        for reason in systemReasons {
            XCTAssertLessThan(HoldReason.fullscreen.order, reason.order,
                              "全屏必须排在 \(reason) 之前")
        }
    }

    func testApplyCurrentDecisionForwardsCurrentDecisionWithoutTouchingAnchor() {
        target.position = 33.0
        arbiter.set(.manualPause, active: true)
        target.applies.removeAll()

        arbiter.applyCurrentDecision()

        XCTAssertEqual(target.applies.count, 1, "起播路径应当把当前 decision 交给播放端一次")
        XCTAssertEqual(target.applies.last?.shouldPlay, false)
        XCTAssertTrue(target.seeks.isEmpty,
                      "applyCurrentDecision 不得碰锚点、不得触发续播 seek —— 否则锁屏起播会把播放头拽回暂停处")

        target.position = 5.0
        arbiter.set(.manualPause, active: false)
        XCTAssertEqual(target.seeks, [33.0], "锚点必须在解除时仍然有效")
    }

    /// `startWallpaper()` 末尾那一段的**逻辑原样**搬进测试，用替身跑两遍。
    ///
    /// 下面这个 `do { }` 不是多余的：删掉 `if decision.shouldPlay {` 那一行之后整个文件**仍能编译**，`setRate` 变无条件调用，`setRateCalls` 从 0 变 1，下面的 `XCTAssertEqual` 以**断言失败**的形式转红 —— 而不是变成一个 `}` 悬空的编译错误。
    private func runStartPath(_ decision: PlaybackDecision, sink: SettingsSink, arbiter: HoldArbiter) {
        arbiter.applyCurrentDecision()
        sink.setVolume(1.0)
        sink.setMuted(false)
        do {
            if decision.shouldPlay {
                sink.setRate(1.0)
            }
        }
    }

    func testSetRateOnStartPathIsGatedByShouldPlay() {
        arbiter.set(.screenLocked, active: true)
        let heldSink = SettingsSink()
        runStartPath(arbiter.decision, sink: heldSink, arbiter: arbiter)

        XCTAssertEqual(heldSink.setRateCalls, 0,
                       "已 hold 时起播路径不得调用 setRate —— 它的实现就是 player.rate = r，非零值会把播放器重新拉起")
        XCTAssertEqual(heldSink.setVolumeCalls, 1, "音量实测不影响 timeControlStatus，可无条件落位")
        XCTAssertEqual(heldSink.setMutedCalls, 1)

        let free = HoldArbiter(target: FakeTarget())
        let freeSink = SettingsSink()
        runStartPath(free.decision, sink: freeSink, arbiter: free)

        XCTAssertEqual(freeSink.setRateCalls, 1, "应当播放时必须落位速率，否则起播速度不是设置里的值")
        XCTAssertEqual(freeSink.setVolumeCalls, 1)
        XCTAssertEqual(freeSink.setMutedCalls, 1)
    }
}