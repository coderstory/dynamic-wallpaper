// 夹具里的每个数字都是锁定的基准常量（`--selftest` 实测值），不是现场算的 —— 重算或替换即判据作废。
// 本文件**只锁几何数字**；「那扇窗该不该被判成全屏」由 `FullscreenVerdict` 那侧断言，
// 两个文件各判一次会让判定逻辑出现两个落点。

import XCTest
@testable import PicCore

final class FullscreenGeometryTests: XCTestCase {

    private let screenHeight: Double = 956
    private let visible = ScreenRect(x: 0, y: 90, w: 1470, h: 833)

    /// `inset` 固定 `.zero`：`--selftest` 量的是屏幕层窗口，没有桌面层内缩。带内缩的路径由用例 4 单独锁。
    private func aggregate(_ rects: [(Int, ScreenRect)]) -> CoverageResult {
        FullscreenGeometry.aggregate(
            samples: rects.map { WindowRectSample(pid: $0.0, raw: $0.1) },
            visible: visible,
            screenFrameHeight: screenHeight,
            inset: .zero)
    }

    /// screenH=956 下 (0,33,1470,833) 翻转后 y 必须是 90.000 —— 逐字重放实测基准。
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

    /// whole / chrome / split 三条都是 1.000 —— 逐字重放实测基准。
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

    /// 按 pid 聚合是承重设计：`split` 两块各 0.600 / 0.400 合起来才 1.000。
    /// 实现一旦退化成「逐窗口取最大」，`split.perWindowBest` 就会输出 0.600 而这两条立刻红。
    func testPerWindowBestMatchesPhaseOneBaselines() {
        let chrome = aggregate([(1000, ScreenRect(x: 0, y: 33, w: 1470, h: 124)),
                                (1000, ScreenRect(x: 0, y: 121, w: 1470, h: 835))])
        XCTAssertEqual(chrome.perWindowBest, 0.894, accuracy: 0.005)

        let split = aggregate([(1000, ScreenRect(x: 0, y: 33, w: 1470, h: 500)),
                               (1000, ScreenRect(x: 0, y: 533, w: 1470, h: 400))])
        XCTAssertEqual(split.perWindowBest, 0.600, accuracy: 0.005)

        // 两者相等说明聚合已退化成逐窗口取最大，本用例就变成空判
        XCTAssertNotEqual(split.global, split.perWindowBest, accuracy: 0.001,
                          "split 上两者相等说明聚合退化成了逐窗口取最大")
    }

    /// 屏幕 frame (0,0,1470,956) 减窗口 frame (14,9,1442,938) 得 14 / 9 / 14 / 9，反向补偿必须逐字节还原。
    /// 纯加减，**刻意不设容差** —— 加了容差只会掩盖写错。
    func testInsetCompensationWidensTheRectByFourteenNine() {
        let raw = ScreenRect(x: 14, y: 9, w: 1442, h: 938)
        let widened = FullscreenGeometry.compensatingInset(raw, by: .measured1470x956)
        XCTAssertEqual(widened, ScreenRect(x: 0, y: 0, w: 1470, h: 956))
    }

    /// 那条假阳性：窗口高 833 < 屏幕 frame 高 956，够不到刘海所以可证不是全屏，coverage 却顶到 1.000 ——
    /// 几何满覆盖不等于全屏。「不该判成全屏」由 `FullscreenVerdict` 那侧断言，两处不重叠是刻意的。
    func testFalsePositiveWindowStaysAtFullCoverageButIsNotTheDecision() {
        let literalReplay = aggregate([(1227, ScreenRect(x: 0, y: 33, w: 1470, h: 833))])
        XCTAssertEqual(literalReplay.global, 1.000, accuracy: 0.005)
        XCTAssertEqual(literalReplay.globalPid, 1227)
        XCTAssertEqual(literalReplay.rectCount, 1)

        // 加上内缩补偿后仍顶满：这条假阳性与补偿无关，几何上怎么补偿都成立（bounds 够不到屏幕 frame 顶边）
        let withInset = FullscreenGeometry.aggregate(
            samples: [WindowRectSample(pid: 1227, raw: ScreenRect(x: 0, y: 33, w: 1470, h: 833))],
            visible: visible,
            screenFrameHeight: screenHeight,
            inset: .measured1470x956)
        XCTAssertEqual(withInset.global, 1.000, accuracy: 0.005)
    }
}