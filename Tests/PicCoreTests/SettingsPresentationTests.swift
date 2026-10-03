import XCTest
@testable import PicCore

/// `SettingsPresentation` 纯显示映射单测（Plan 05-01 T1）。
///
/// 窗口常量（780/680）在这里锁死 —— SC-1 的两个数的唯一来源是
/// `SettingsPresentation`，视图与探针都读它，不许散落字面量。
final class SettingsPresentationTests: XCTestCase {

    func testRateLabelFormatsBounds() {
        XCTAssertEqual(SettingsPresentation.rateLabel(0.5), "0.50×")
        XCTAssertEqual(SettingsPresentation.rateLabel(1.0), "1.00×")
        XCTAssertEqual(SettingsPresentation.rateLabel(2.0), "2.00×")
    }

    func testRateLabelClampsOutOfRangeValues() {
        XCTAssertEqual(SettingsPresentation.rateLabel(0.3), "0.50×")
        XCTAssertEqual(SettingsPresentation.rateLabel(2.5), "2.00×")
    }

    func testVolumePercentMapsAndClamps() {
        XCTAssertEqual(SettingsPresentation.volumePercent(0), 0)
        XCTAssertEqual(SettingsPresentation.volumePercent(0.6), 60)
        XCTAssertEqual(SettingsPresentation.volumePercent(1.0), 100)
        XCTAssertEqual(SettingsPresentation.volumePercent(-0.2), 0)
        XCTAssertEqual(SettingsPresentation.volumePercent(1.7), 100)
    }

    func testVolumeFromPercentRoundTrips() {
        // UI 是 0–100 整数、store 是 Float 0–1，往返误差必须远小于
        // 一个人能感知的音量步长（1% = 0.01，容差放宽到 0.011）。
        var v = Float(0.0)
        while v <= 1.0 {
            let back = SettingsPresentation.volumeFromPercent(
                SettingsPresentation.volumePercent(v))
            XCTAssertEqual(back, v, accuracy: 0.011)
            v += 0.05
        }
    }

    func testWindowConstantsMatchContract() {
        XCTAssertEqual(SettingsPresentation.windowWidth, 780)
        XCTAssertEqual(SettingsPresentation.windowMinWidth, 680)
    }

    func testRateBoundsAreHalfToDouble() {
        XCTAssertEqual(SettingsPresentation.rateBounds.lowerBound, 0.5)
        XCTAssertEqual(SettingsPresentation.rateBounds.upperBound, 2.0)
    }
}
