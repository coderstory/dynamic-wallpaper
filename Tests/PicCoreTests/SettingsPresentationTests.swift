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

    // ---- Plan 05-02 T1：轮换值表 / 两条置灰联动 / 模式文案 ----
    //
    // ⚠️ 两条联动的用例是 UI-03 的牙齿：变异 MUT-P5-LINK-ROT / MUT-P5-LINK-VOL
    // 拿掉任一条判据，本组必须转红，且红光来自断言而非编译失败（D-16）。

    func testRotationLabelSwitchesToHoursAtSixty() {
        XCTAssertEqual(SettingsPresentation.rotationLabel(minutes: 5), "5 分钟")
        XCTAssertEqual(SettingsPresentation.rotationLabel(minutes: 15), "15 分钟")
        XCTAssertEqual(SettingsPresentation.rotationLabel(minutes: 60), "1 小时")
        XCTAssertEqual(SettingsPresentation.rotationLabel(minutes: 120), "2 小时")
    }

    func testRotationSecondsAndMinutesRoundTrip() {
        for minutes in SettingsPresentation.rotationChoicesMinutes {
            let seconds = SettingsPresentation.rotationSeconds(minutes: minutes)
            XCTAssertEqual(seconds, TimeInterval(minutes) * 60)
            XCTAssertEqual(SettingsPresentation.rotationMinutes(seconds: seconds), minutes)
        }
    }

    /// 旧持久值对不上值表时就近吸附，不给表外的数 —— 否则步进器会索引到越界项。
    func testRotationMinutesSnapsToNearestChoice() {
        // 299 秒 ≈ 4.98 分钟（早期写进 UserDefaults 的脏值）
        XCTAssertEqual(SettingsPresentation.rotationMinutes(seconds: 299), 5)
        XCTAssertEqual(SettingsPresentation.rotationMinutes(seconds: 302), 5)
        // 111 分钟远离表内任何一项，取最近的 120
        XCTAssertEqual(SettingsPresentation.rotationMinutes(seconds: 111 * 60), 120)
    }

    func testRotationControlsDisabledOnlyForLoopSingle() {
        XCTAssertFalse(SettingsPresentation.rotationControlsEnabled(playMode: .loopSingle))
        XCTAssertTrue(SettingsPresentation.rotationControlsEnabled(playMode: .loopList))
        XCTAssertTrue(SettingsPresentation.rotationControlsEnabled(playMode: .shuffle))
    }

    func testVolumeControlsDisabledOnlyWhenMuted() {
        XCTAssertTrue(SettingsPresentation.volumeControlsEnabled(isMuted: false))
        XCTAssertFalse(SettingsPresentation.volumeControlsEnabled(isMuted: true))
    }

    /// 分段控件按 `PlayMode.allCases` 渲染（04-02 T1 锁序），文案单一来源。
    func testPlayModeLabelCoversAllCasesInOrder() {
        XCTAssertEqual(PlayMode.allCases.map(SettingsPresentation.playModeLabel),
                       ["单循环", "列表循环", "随机"])
    }
}
