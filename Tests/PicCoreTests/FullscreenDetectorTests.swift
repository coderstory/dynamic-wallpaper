// 几何足以铺满 visibleFrame（coverage 顶到 1.000 上限）时，只要没有几何外信号
// （空间切换 / 前台应用激活），必须判 false：那类窗口 bounds 高小于屏幕高，结构上够不到刘海，
// 可证不是全屏，而 coverage 已顶在上限，没有任何阈值能把「几何为真」和「判定为真」分开。
// 所以本组测的是「几何单独为真必须判 false」，不是「阈值是多少」。
// 判定只在本文件判一次，几何数字由 FullscreenGeometryTests 锁；两处都判会让判定逻辑有两个落点。

import XCTest
@testable import PicCore

final class FullscreenDetectorTests: XCTestCase {

    // 假阳性夹具取自真实窗口：visibleFrame 1470×833，屏幕高 956。
    private let falsePositiveSamples = [WindowRectSample(pid: 1227, raw: ScreenRect(x: 0, y: 33, w: 1470, h: 833))]
    private let visible = ScreenRect(x: 0, y: 90, w: 1470, h: 833)
    private let screenHeight: Double = 956

    /// 「把阈值调高一点」防不住这件事 —— **必须靠合取**。
    func testGeometryAloneNeverTriggersFullscreen() {
        let s = FullscreenSignals(spaceChangedWhileFullyCovering: false,
                                  frontmostAppChangedWhileFullyCovering: false,
                                  covering: true)
        XCTAssertFalse(s.nonGeometricActive, "夹具前提：三个信号位全 false 时 nonGeometricActive 必须为 false")
        XCTAssertFalse(FullscreenVerdict.verdict(s),
                       "D-02：几何足够时没有几何外信号，一律不得判成全屏")
    }

    /// 一个断言同时锁住「几何算得对」与「判定用得对」；与几何侧那条不重叠：
    /// 那条只说 coverage=1.000，这条说 coverage=1.000 **不判全屏**。
    func testFalsePositiveWindowGeometryOnePointZeroStaysFalse() {
        let coverage = FullscreenGeometry.aggregate(samples: falsePositiveSamples,
                                                    visible: visible,
                                                    screenFrameHeight: screenHeight,
                                                    inset: .measured1470x956)
        XCTAssertEqual(coverage.global, 1.000, accuracy: 0.005,
                       "Phase 1 S0：Ghostty pid=1227 铺满 visibleFrame → coverage=1.000")
        XCTAssertEqual(coverage.globalPid, 1227)
        XCTAssertEqual(coverage.rectCount, 1)

        let s = FullscreenSignals(spaceChangedWhileFullyCovering: false,
                                  frontmostAppChangedWhileFullyCovering: false,
                                  covering: true)
        XCTAssertFalse(FullscreenVerdict.verdict(s),
                       "D-02 的核心反例：coverage=1.000 但没有几何外信号 → 判定必须是 false")
    }

    /// 两个合取项各自的四种组合一次走完。任一项被改成单侧，这四行里必有一行红。
    func testNonGeometricSignalTriggersFullscreenOnlyWhenCovering() {
        let noSignal = FullscreenSignals(spaceChangedWhileFullyCovering: false,
                                         frontmostAppChangedWhileFullyCovering: false,
                                         covering: false)
        XCTAssertFalse(FullscreenVerdict.verdict(noSignal), "两项皆假 → false")

        let signalOnly = FullscreenSignals(spaceChangedWhileFullyCovering: true,
                                           frontmostAppChangedWhileFullyCovering: false,
                                           covering: false)
        XCTAssertFalse(FullscreenVerdict.verdict(signalOnly), "信号成立但几何不足 → false")

        let both = FullscreenSignals(spaceChangedWhileFullyCovering: true,
                                     frontmostAppChangedWhileFullyCovering: false,
                                     covering: true)
        XCTAssertTrue(FullscreenVerdict.verdict(both), "两项皆真 → true")

        let geometryOnly = FullscreenSignals(spaceChangedWhileFullyCovering: false,
                                             frontmostAppChangedWhileFullyCovering: false,
                                             covering: true)
        XCTAssertFalse(FullscreenVerdict.verdict(geometryOnly), "几何充足但无信号 → false")
    }

    func testFrontmostSignalAloneAlsoCounts() {
        let spaceOnly = FullscreenSignals(spaceChangedWhileFullyCovering: true,
                                          frontmostAppChangedWhileFullyCovering: false,
                                          covering: true)
        let frontmostOnly = FullscreenSignals(spaceChangedWhileFullyCovering: false,
                                              frontmostAppChangedWhileFullyCovering: true,
                                              covering: true)
        XCTAssertTrue(FullscreenVerdict.verdict(spaceOnly))
        XCTAssertTrue(FullscreenVerdict.verdict(frontmostOnly),
                      "前台应用激活是第二条独立的几何外信号，不因只走它而失效")
    }
}