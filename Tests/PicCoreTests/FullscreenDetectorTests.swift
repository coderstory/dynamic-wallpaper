// FullscreenDetectorTests.swift —— Plan 03-02 T2：D-02 合取判定的四条用例。
//
// 这一组用例守护的是 Phase 1 用实测证伪掉的那件事：
//
//   `FALSE_POSITIVE_OBSERVED=1 direction=safe_area_filled_but_not_fullscreen_scored_fullscreen`
//   —— Ghostty(pid 1227) 与 CC Switch(pid 1228) 各把 visibleFrame(1470×833) 铺满，
//      coverage=1.000 被旧阈值判成全屏，但两者 bounds 高 833 < 屏幕 frame 高 956，
//      **结构上够不到刘海，可证不是全屏**。
//
// coverage 顶在 1.000 上限，任何阈值调整都改不了这件事（D-02）。
// 所以本组用例测的不是「阈值是多少」，而是「**几何单独为真时必须判 false**」。
//
// ⚠️ 判据只在这里判一次。`FullscreenGeometryTests` 只锁几何数字，
//    本文件只锁判定 —— 两个文件各判一次会让判定逻辑出现两个落点。

import XCTest
@testable import PicCore

final class FullscreenDetectorTests: XCTestCase {

    // Phase 1 S0 段的逐字重放：Ghostty 铺满 visibleFrame。
    private let falsePositiveSamples = [WindowRectSample(pid: 1227, raw: ScreenRect(x: 0, y: 33, w: 1470, h: 833))]
    private let visible = ScreenRect(x: 0, y: 90, w: 1470, h: 833)
    private let screenHeight: Double = 956

    // ── 1. 几何单独为真 → false ─────────────────────────────────────────

    /// 名字里带 `GeometryAlone` 是刻意的：将来有人改动判定时，从测试名就该看出意图。
    ///
    /// 这不是「阈值调高一点」能防住的事 —— `coverage` 已经是 1.000，
    /// 没有任何阈值能把「几何为真」和「判定为真」分开。**必须靠合取。**
    func testGeometryAloneNeverTriggersFullscreen() {
        let s = FullscreenSignals(spaceChangedWhileFullyCovering: false,
                                  frontmostAppChangedWhileFullyCovering: false,
                                  covering: true)
        XCTAssertFalse(s.nonGeometricActive, "夹具前提：三个信号位全 false 时 nonGeometricActive 必须为 false")
        XCTAssertFalse(FullscreenVerdict.verdict(s),
                       "D-02：几何足够时没有几何外信号，一律不得判成全屏")
    }

    // ── 2. Phase 1 假阳性夹具端到端 ─────────────────────────────────────

    /// 一个断言同时锁住「几何算得对」与「判定用得对」，两个数字都能指回 Phase 1 的日志行。
    ///
    /// 这是 T1 的第 5 条（`testFalsePositiveWindowStaysAtFullCoverageButIsNotTheDecision`）
    /// 在判定侧的对应物。两条不重叠：那条只说 coverage=1.000，这条说 coverage=1.000 **不判全屏**。
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

    // ── 3. 合取的四行穷举 ───────────────────────────────────────────────

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

    // ── 4. 两个信号源是等价的两条路，不是二选一 ─────────────────────────

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