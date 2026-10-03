import XCTest
@testable import PicCore

/// 仲裁器单测 —— 纯逻辑，**本文件不得引入播放框架**（State/ 零依赖）。
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

    /// 幂集判据：子集在**运行时**从 `allCases` 生成，加 case 后自动从
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
    /// 若 UI 侧另立一个可变的 `isPaused`，本用例不会红，但
    /// `test.sh` 的「UI 侧零可变真相源」源码判据会红；两条一起锁。
    func testIsManuallyPausedIsDerivedFromHolds() {
        XCTAssertFalse(arbiter.isManuallyPaused, "初始 holds 为空，不是手动暂停")
        arbiter.set(.manualPause, active: true)
        XCTAssertTrue(arbiter.isManuallyPaused, "holds 含 manualPause 即为手动暂停")
        arbiter.set(.manualPause, active: false)
        XCTAssertFalse(arbiter.isManuallyPaused, "hold 解除后派生量跟着回落")
    }

    /// 正面判据：手动暂停后解除，续播点是**暂停时**的那一秒，
    /// 不是片头。判据是 `FakeTarget.seeks` 里的具体秒数，不是「播起来了」。
    func testManualPauseResumesFromAnchorNotFromZero() {
        target.position = 42.0
        arbiter.set(.manualPause, active: true)
        arbiter.set(.manualPause, active: false)

        XCTAssertEqual(target.seeks, [42.0], "必须从暂停时的位置续播")
        XCTAssertNotEqual(target.seeks.first, 0.0, "从 0 续播就是从头播")
        XCTAssertTrue(arbiter.decision.shouldPlay, "hold 清空后应当恢复播放")
    }

    /// 第二半：锚点只在 ∅→非∅ 写入一次。暂停期间位置被别处改掉
    /// （系统 hold、换片都会这样），解除后仍从原锚点续播。
    func testAnchorNotOverwrittenBySecondHold() {
        target.position = 42.0
        arbiter.set(.manualPause, active: true)
        target.position = 55.0          // 模拟暂停期间另一路改了位置
        arbiter.set(.manualPause, active: false)

        XCTAssertEqual(target.seeks, [42.0], "锚点不得被暂停期间的位置变化覆盖")
    }

    // MARK: - 幂集与 order 的核心资产

    /// **存在性**判据：6 个输入 × 开闭 = 64 种组合。
    ///
    /// 幂集是**运行时**从 `allCases` 生成的（见 `testShouldPlayMatchesEmptyHoldsForEverySubset`），
    /// 这里只钉住组合数本身。将来有人加/减 case，数字立刻对不上。
    func testAllCasesCountIsSixAndPowersetIsSixtyFour() {
        let count = HoldReason.allCases.count
        XCTAssertEqual(count, 6, "HoldReason 必须是 manualPause + 5 个系统原因；实际 \(count) 个")

        let powerset = 1 << count
        XCTAssertEqual(powerset, 64, "TEST-01 要求 64 种组合；2^\(count) = \(powerset)")
    }

    /// `order` 两两不同 —— 否则 `PlaybackDecision.activeReasons`（即 `holds.sorted()`）
    /// 在撞号的那两个 case 之间顺序不确定，「优先级只用于 UI 文案排序」就失效。
    /// `manualPause` 的 0 是早期定的值，不许被改。
    func testOrderValuesAreDistinctAndManualPauseStaysZero() {
        let orders = HoldReason.allCases.map(\.order)
        XCTAssertEqual(orders, [0, 1, 2, 3, 4, 5], "order 必须互不相同且升序；实际 \(orders)")
        XCTAssertEqual(HoldReason.manualPause.order, 0, "Phase 2 的值，一个字不改")

        let sorted = HoldReason.allCases.sorted().map(\.order)
        XCTAssertEqual(sorted, orders, "Comparable 必须与 order 升序一致")
    }

    /// **最核心的反例**：锁屏中退出全屏**不恢复播放**。
    ///
    /// 覆盖式实现（点名的反模式：优先级链 / 覆盖）在这一步会把
    /// `holds` 直接写成「剩下的那一个」，于是用户从全屏退出来的瞬间壁纸就播了起来。
    /// veto 集合语义要求 `holds` 非空就一律不播。
    /// 这条用例被注入式反向验证过 —— 把移除语义换成覆盖语义后必须转红。
    func testLockedThenFullscreenExitDoesNotResume() {
        target.position = 42.0

        arbiter.set(.screenLocked, active: true)    // ∅ → {screenLocked}：记锚点 42.0
        arbiter.set(.fullscreen, active: true)      // → {screenLocked, fullscreen}
        arbiter.set(.fullscreen, active: false)     // → {screenLocked}

        XCTAssertEqual(arbiter.decision.holds, [.screenLocked], "退出全屏后仍锁着，holds 不得被覆盖成空集")
        XCTAssertFalse(arbiter.decision.shouldPlay, "锁屏仍在 → 一律不播")
        XCTAssertTrue(target.seeks.isEmpty, "退出全屏那一刻不得有任何 seek —— 有 seek 就说明续播被提前触发了")

        arbiter.set(.screenLocked, active: false)   // 锁屏解除才续播

        XCTAssertTrue(arbiter.decision.shouldPlay)
        XCTAssertEqual(target.seeks, [42.0], "解除锁屏才 seek，且 seek 到第一次进 hold 时的位置")
    }

    /// 在 6 个 reason 下不漂移：锚点只在 ∅ → 非∅ 写一次，
    /// 其余 5 个 reason 依次置位再**逆序**解除，锚点必须一直是 42.0。
    func testAnchorNotOverwrittenAcrossAllSixReasons() {
        target.position = 42.0
        arbiter.set(.manualPause, active: true)     // 写锚点 42.0
        target.position = 55.0                       // 模拟暂停期间另一路改了位置

        let overlay: [HoldReason] = [.fullscreen, .screenLocked, .displayAsleep, .systemSleeping, .battery]

        for reason in overlay {
            arbiter.set(reason, active: true)
        }
        XCTAssertEqual(arbiter.decision.holds.count, 6, "6 个 reason 全部生效")
        XCTAssertFalse(arbiter.decision.shouldPlay)

        for reason in overlay.reversed() {
            arbiter.set(reason, active: false)
            XCTAssertTrue(target.seeks.isEmpty, "\(reason) 解除时手动暂停仍在，不得触发续播")
        }

        XCTAssertEqual(arbiter.decision.holds, [.manualPause], "只剩手动暂停")
        XCTAssertFalse(arbiter.decision.shouldPlay)

        arbiter.set(.manualPause, active: false)

        XCTAssertEqual(target.seeks, [42.0], "锚点从头到尾没被二次覆盖")
    }
}
