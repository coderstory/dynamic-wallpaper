import XCTest
@testable import PicCore

/// 仲裁器单测 —— 纯逻辑，**本文件不得引入播放框架**（ARCHITECTURE §9：State/ 零依赖）。
@MainActor
final class HoldArbiterTests: XCTestCase {

    /// 假播放端：记录仲裁器对它的每一次调用。
    private final class FakeTarget: PlaybackTarget {
        var position: TimeInterval = 0
        var seeks: [TimeInterval] = []
        var applies: [PlaybackDecision] = []

        func arbiterCurrentPosition() -> TimeInterval { position }
        func arbiterSeek(to seconds: TimeInterval) { seeks.append(seconds) }
        func arbiterApply(_ decision: PlaybackDecision) { applies.append(decision) }
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

    /// 幂集判据：子集在**运行时**从 `allCases` 生成，Phase 3 加 case 后自动从
    /// 2^n 扩到 2^(n+1)，测试代码一个字都不用改。
    func testShouldPlayMatchesEmptyHoldsForEverySubset() {
        let all = HoldReason.allCases
        XCTAssertFalse(all.isEmpty, "HoldReason 至少要有一个 case")

        for mask in 0..<(1 << all.count) {
            let subset = Set(all.enumerated()
                .filter { mask & (1 << $0.offset) != 0 }
                .map { $0.element })

            let fresh = HoldArbiter(target: target)
            for reason in all {
                fresh.set(reason, active: subset.contains(reason))
            }

            XCTAssertEqual(fresh.decision.holds, subset, "mask=\(mask)")
            XCTAssertEqual(fresh.decision.shouldPlay, subset.isEmpty, "mask=\(mask)")
        }
    }

    func testIdempotentSetAppliesOnce() {
        arbiter.set(.manualPause, active: true)
        arbiter.set(.manualPause, active: true)
        XCTAssertEqual(target.applies.count, 1, "同一 reason 重复置位只应生效一次")
        XCTAssertEqual(arbiter.decision.holds, [.manualPause])
    }

    func testAnchorWrittenOnlyOnEmptyToNonEmptyTransition() {
        target.position = 7
        arbiter.set(.manualPause, active: true)   // ∅ → 非∅：记锚点 7
        arbiter.set(.manualPause, active: false)  // 非∅ → ∅：消费锚点 7
        XCTAssertEqual(target.seeks, [7])

        target.position = 99
        arbiter.set(.manualPause, active: false)  // ∅ → ∅：不得再记锚点
        XCTAssertEqual(target.seeks, [7], "∅ → ∅ 不得记录新锚点，也不得触发续播")
    }

    func testResumeSeeksToAnchorThenClearsAnchor() {
        target.position = 12
        arbiter.set(.manualPause, active: true)
        XCTAssertEqual(target.seeks, [], "进入暂停时只记锚点，不 seek")

        arbiter.set(.manualPause, active: false)
        XCTAssertEqual(target.seeks, [12], "解除暂停必须从原处续播")

        target.position = 30
        arbiter.set(.manualPause, active: true)
        arbiter.set(.manualPause, active: false)
        XCTAssertEqual(target.seeks, [12, 30], "锚点消费后清空，第二次暂停记新锚点")
    }

    func testSetWithoutTargetDoesNotCrash() {
        let detached = HoldArbiter(target: nil)
        detached.set(.manualPause, active: true)
        XCTAssertFalse(detached.decision.shouldPlay)
        detached.set(.manualPause, active: false)
        XCTAssertTrue(detached.decision.shouldPlay)
    }

    func testActiveReasonsSorted() {
        XCTAssertEqual(PlaybackDecision().activeReasons, [])
        XCTAssertEqual(
            PlaybackDecision(holds: Set(HoldReason.allCases)).activeReasons,
            HoldReason.allCases.sorted(),
            "activeReasons 必须按 order 排好序"
        )
    }

    /// UI 侧读「是否手动暂停」的唯一入口 —— 它必须是 `decision.holds` 的派生量。
    /// 若 Phase 5 在 UI 侧另立一个可变的 `isPaused`，本用例不会红，但
    /// `test.sh` 的「UI 侧零可变真相源」源码判据会红；两条一起锁。
    func testIsManuallyPausedIsDerivedFromHolds() {
        XCTAssertFalse(arbiter.isManuallyPaused, "初始 holds 为空，不是手动暂停")
        arbiter.set(.manualPause, active: true)
        XCTAssertTrue(arbiter.isManuallyPaused, "holds 含 manualPause 即为手动暂停")
        arbiter.set(.manualPause, active: false)
        XCTAssertFalse(arbiter.isManuallyPaused, "hold 解除后派生量跟着回落")
    }

    /// D-15 的正面判据：手动暂停后解除，续播点是**暂停时**的那一秒，
    /// 不是片头。判据是 `FakeTarget.seeks` 里的具体秒数，不是「播起来了」。
    func testManualPauseResumesFromAnchorNotFromZero() {
        target.position = 42.0
        arbiter.set(.manualPause, active: true)
        arbiter.set(.manualPause, active: false)

        XCTAssertEqual(target.seeks, [42.0], "必须从暂停时的位置续播")
        XCTAssertNotEqual(target.seeks.first, 0.0, "从 0 续播就是从头播")
        XCTAssertTrue(arbiter.decision.shouldPlay, "hold 清空后应当恢复播放")
    }

    /// D-15 的第二半：锚点只在 ∅→非∅ 写入一次。暂停期间位置被别处改掉
    /// （Phase 3 的系统 hold、Phase 4 的换片都会这样），解除后仍从原锚点续播。
    func testAnchorNotOverwrittenBySecondHold() {
        target.position = 42.0
        arbiter.set(.manualPause, active: true)
        target.position = 55.0          // 模拟暂停期间另一路改了位置
        arbiter.set(.manualPause, active: false)

        XCTAssertEqual(target.seeks, [42.0], "锚点不得被暂停期间的位置变化覆盖")
    }
}
