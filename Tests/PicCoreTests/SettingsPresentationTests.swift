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

    // ---- 空态文案 / 三态一张皮 / 暂停原因 / 状态卡标题 ----

    /// UI-02 逐字硬需求。哨兵写在本测试里 —— 常量改一个字这里就红。
    func testEmptyStateBodyMatchesSpecVerbatim() {
        XCTAssertEqual(SettingsPresentation.emptyStateBody,
                       "没找到能播的文件。壁纸已隐藏，桌面显示的是系统原壁纸。")
    }

    /// 文案只能有一份拷贝（它在 Sources 全树恰好出现一次）。
    /// 第二份拷贝不会自己漂移提醒 —— 它会漂移成两个版本的承诺。
    func testEmptyStateBodyIsSingleSourced() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // PicCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // 包根
            .appendingPathComponent("Sources/PicCore/App/SettingsPresentation.swift")
        let raw = try String(contentsOf: file, encoding: .utf8)
        let code = raw.components(separatedBy: .newlines).filter { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            return !(t.hasPrefix("//") || t.hasPrefix("/*") || t.hasPrefix("*") || t.hasPrefix("*/"))
        }.joined(separator: "\n")
        XCTAssertEqual(code.components(separatedBy: SettingsPresentation.emptyStateBody).count - 1, 1)
    }

    /// 三态一张皮：UI 不区分「没配过 / 目录没了 / 扫到 0」，
    /// 判定就是「不该显示壁纸」的反面。用 `allCases` 穷举，不手抄清单。
    func testThreeHideStatesShareOneEmptySkin() {
        var hidden = 0
        for state in LibraryState.allCases {
            XCTAssertEqual(SettingsPresentation.isEmptyState(state),
                           !state.shouldShowWallpaper, state.reasonToken)
            if !state.shouldShowWallpaper { hidden += 1 }
        }
        XCTAssertEqual(hidden, 3)
    }

    func testHoldReasonLabelsCoverAllSixCasesVerbatim() {
        let expected: [HoldReason: String] = [
            .manualPause: "手动暂停",
            .fullscreen: "检测到全屏应用",
            .screenLocked: "屏幕已锁定",
            .displayAsleep: "显示器已熄屏",
            .systemSleeping: "系统正在睡眠",
            .battery: "电池供电中",
        ]
        XCTAssertEqual(HoldReason.allCases.count, 6)
        let labels = HoldReason.allCases.map(SettingsPresentation.holdReasonLabel)
        XCTAssertEqual(labels, HoldReason.allCases.map { expected[$0]! })
        XCTAssertEqual(Set(labels).count, 6, "六条文案两两不同，否则 UI 无法区分原因")
    }

    /// 变异 MUT-P5-REASON-ORDER 的牙齿：拿掉排序这一行，多原因用例转红。
    func testJoinedReasonsSortsByOrderBeforeJoining() {
        XCTAssertEqual(SettingsPresentation.joinedReasons([.screenLocked, .manualPause]),
                       "手动暂停、屏幕已锁定")
        XCTAssertEqual(SettingsPresentation.joinedReasons([.battery, .systemSleeping, .fullscreen]),
                       "检测到全屏应用、系统正在睡眠、电池供电中")
    }

    func testJoinedReasonsEmptyReturnsEmptyString() {
        XCTAssertEqual(SettingsPresentation.joinedReasons([]), "")
    }

    func testJoinedReasonsSingleReasonHasNoSeparator() {
        XCTAssertEqual(SettingsPresentation.joinedReasons([.manualPause]), "手动暂停")
    }

    func testPlaybackTitlesAreDistinctConstants() {
        XCTAssertFalse(SettingsPresentation.playbackPausedTitle.isEmpty)
        XCTAssertFalse(SettingsPresentation.playbackRunningTitle.isEmpty)
        XCTAssertNotEqual(SettingsPresentation.playbackPausedTitle,
                          SettingsPresentation.playbackRunningTitle)
    }
}
