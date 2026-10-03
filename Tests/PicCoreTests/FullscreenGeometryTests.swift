// FullscreenGeometryTests.swift —— 几何层对齐 `--selftest` 的四条基准。
//
// ⚠️ 本文件的每一个夹具数字都来自实测日志，**没有一个是编的**：
//   `.planning/spike/out/fullscreen-scenarios.log` 的 `SELFTEST_BLOCK` / `S0` 段，
//   `.planning/phases/02-playback-core/evidence/inset.log`。
// 写测试时改了夹具里的任何数字 = 判据作废。
//
// 本文件**只锁几何数字**。「那扇窗不该被判成全屏」是 `FullscreenVerdict` 的事 ——
// 两个文件各判一次会让判定逻辑出现两个落点。

import XCTest
@testable import PicCore

final class FullscreenGeometryTests: XCTestCase {

    // ── 基准常量（全部抄自 evidence，不是新算的）─────────────────────────

    /// `fullscreen-scenarios.log:SELFTEST` 段的 SCREEN frame / visible 两行。
    private let screenHeight: Double = 956
    private let visible = ScreenRect(x: 0, y: 90, w: 1470, h: 833)

    /// 三条基准都用同一个 pid 与 inset=.zero —— `--selftest` 量的是屏幕层窗口，
    /// 没有桌面层内缩。带内缩的那条路径由 `testInsetCompensationWidensTheRectByFourteenNine` 单独锁。
    private func aggregate(_ rects: [(Int, ScreenRect)]) -> CoverageResult {
        FullscreenGeometry.aggregate(
            samples: rects.map { WindowRectSample(pid: $0.0, raw: $0.1) },
            visible: visible,
            screenFrameHeight: screenHeight,
            inset: .zero)
    }

    // ── 1. 坐标系翻转 ──────────────────────────────────────────────

    /// `S0` 段 `WIN pid=1227 ... bounds=0.0,33.0,1470.0,833.0 flipped_y=90.000` 的逐字重放。
    func testFlipMatchesPhaseOneBaseline() {
        let flipped = FullscreenGeometry.flipTopLeftToBottomLeft(
            ScreenRect(x: 0, y: 33, w: 1470, h: 833), screenH: screenHeight)
        XCTAssertEqual(flipped.y, 90.0, accuracy: 0.001,
                       "D-04：screenH 956 下 (0,33,1470,833) 翻转后 y 必须是 90.000")
        // 翻转只动 y 轴，x/w/h 一字不改
        XCTAssertEqual(flipped.x, 0, accuracy: 0.001)
        XCTAssertEqual(flipped.w, 1470, accuracy: 0.001)
        XCTAssertEqual(flipped.h, 833, accuracy: 0.001)
    }

    // ── 2. 三条 coverage 基准 ───────────────────────────────────────────

    /// `SELFTEST_VERDICT=pass whole=1.000 chrome=1.000 split=1.000` 的逐字重放。
    func testSelftestBaselinesWholeChromeSplit() {
        let whole = aggregate([(1000, ScreenRect(x: 0, y: 33, w: 1470, h: 833))])
        XCTAssertEqual(whole.global, 1.000, accuracy: 0.005)
        XCTAssertEqual(whole.globalPid, 1000)

        let chrome = aggregate([(1000, ScreenRect(x: 0, y: 33, w: 1470, h: 124)),
                                (1000, ScreenRect(x: 0, y: 121, w: 1470, h: 835))])
        XCTAssertEqual(chrome.global, 1.000, accuracy: 0.005)
        XCTAssertEqual(chrome.globalPid, 1000)
        XCTAssertEqual(chrome.rectCount, 2)

        let split = aggregate([(1000, ScreenRect(x: 0, y: 33, w: 1470, h: 500)),
                               (1000, ScreenRect(x: 0, y: 533, w: 1470, h: 400))])
        XCTAssertEqual(split.global, 1.000, accuracy: 0.005)
        XCTAssertEqual(split.globalPid, 1000)
        XCTAssertEqual(split.rectCount, 2)
    }

    // ── 3. per_window_best 对照值（按 pid 聚合是承重设计的证明）───────────

    /// `SELFTEST=chrome coverage=1.000 per_window_best=0.894`、
    /// `SELFTEST=split coverage=1.000 per_window_best=0.600`。
    ///
    /// **`split` 这条是几何侧的核心资产**：两块各 0.600 / 0.400 合起来才 1.000。
    /// 实现一旦退化成「逐窗口取最大」，`split` 会输出 0.600 而这条立刻红 ——
    /// 探针把它原样写在 `SELFTEST_PROOF` 行上作为承重证据。
    func testPerWindowBestMatchesPhaseOneBaselines() {
        let chrome = aggregate([(1000, ScreenRect(x: 0, y: 33, w: 1470, h: 124)),
                                (1000, ScreenRect(x: 0, y: 121, w: 1470, h: 835))])
        XCTAssertEqual(chrome.perWindowBest, 0.894, accuracy: 0.005)

        let split = aggregate([(1000, ScreenRect(x: 0, y: 33, w: 1470, h: 500)),
                               (1000, ScreenRect(x: 0, y: 533, w: 1470, h: 400))])
        XCTAssertEqual(split.perWindowBest, 0.600, accuracy: 0.005)

        // 逐窗口口径与按 pid 聚合口径在 split 上必须给出不同答案，否则这条断言是空判。
        XCTAssertNotEqual(split.global, split.perWindowBest, accuracy: 0.001,
                          "split 上两者相等说明聚合退化成了逐窗口取最大")
    }

    // ── 4. 桌面层内缩补偿 ─────────────────────────────────────────

    /// `inset.log` 三行的直接算术：`SCREEN_FRAME=0,0,1470,956` 减 `WINDOW_FRAME=14,9,1442,938`
    /// 得 `INSET_LEFT=14 / INSET_TOP=9 / INSET_RIGHT=14 / INSET_BOTTOM=9`；反向补偿回去
    /// 必须逐字节还原成屏幕框。纯加减，**不设容差** —— 容差只会掩盖写错。
    func testInsetCompensationWidensTheRectByFourteenNine() {
        let raw = ScreenRect(x: 14, y: 9, w: 1442, h: 938)
        let widened = FullscreenGeometry.compensatingInset(raw, by: .measured1470x956)
        XCTAssertEqual(widened, ScreenRect(x: 0, y: 0, w: 1470, h: 956))
    }

    // ── 5. 那条假阳性：几何照样算满，但几何不是判定 ──────────────

    /// `S0` 段 `TOP_PID=1227 coverage=1.000 rects=1`（Ghostty）与
    /// `FALSE_POSITIVE_NOTE`：该窗口 bounds 高 833 < 屏幕 frame 高 956，够不到刘海，
    /// 可证不是全屏，但 coverage 顶到 1.000。
    ///
    /// 本条**只锁几何数字**。「它不该被判成全屏」由 `FullscreenVerdict` 断言
    /// （`testFalsePositiveWindowGeometryOnePointZeroStaysFalse`）。两处各判一次、
    /// 断言不重叠，是刻意的。
    func testFalsePositiveWindowStaysAtFullCoverageButIsNotTheDecision() {
        // 逐字重放实测 S0（探针当时不补偿内缩）。
        let literalReplay = aggregate([(1227, ScreenRect(x: 0, y: 33, w: 1470, h: 833))])
        XCTAssertEqual(literalReplay.global, 1.000, accuracy: 0.005)
        XCTAssertEqual(literalReplay.globalPid, 1227)
        XCTAssertEqual(literalReplay.rectCount, 1)

        // 加上产品默认内缩后仍然顶满 —— 说明这条假阳性不是内缩补偿没做出来的，
        // 它在几何上无论怎么补偿都成立（bounds 根本够不到屏幕 frame 顶边）。
        let withInset = FullscreenGeometry.aggregate(
            samples: [WindowRectSample(pid: 1227, raw: ScreenRect(x: 0, y: 33, w: 1470, h: 833))],
            visible: visible,
            screenFrameHeight: screenHeight,
            inset: .measured1470x956)
        XCTAssertEqual(withInset.global, 1.000, accuracy: 0.005)
    }
}