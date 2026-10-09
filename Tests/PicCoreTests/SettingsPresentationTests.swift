import XCTest
@testable import PicCore

/// 窗口常量（1024/880）在这里锁死 —— 唯一来源是 `SettingsPresentation`，视图与探针都读它，不许散落字面量。
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
        // UI 是 0–100 整数、store 是 Float 0–1。1% = 0.01，容差只能放宽到 0.011，再大就掩盖了整整一档的偏差。
        var v = Float(0.0)
        while v <= 1.0 {
            let back = SettingsPresentation.volumeFromPercent(
                SettingsPresentation.volumePercent(v))
            XCTAssertEqual(back, v, accuracy: 0.011)
            v += 0.05
        }
    }

    func testWindowConstantsMatchContract() {
        XCTAssertEqual(SettingsPresentation.windowWidth, 1024)
        XCTAssertEqual(SettingsPresentation.windowMinWidth, 880)
    }

    func testRateBoundsAreHalfToDouble() {
        XCTAssertEqual(SettingsPresentation.rateBounds.lowerBound, 0.5)
        XCTAssertEqual(SettingsPresentation.rateBounds.upperBound, 2.0)
    }

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

    /// 对不上值表时就近吸附，不给表外的数 —— 否则步进器会索引到越界项。
    func testRotationMinutesSnapsToNearestChoice() {
        // 299 秒 ≈ 4.98 分钟，靠近表内的 5
        XCTAssertEqual(SettingsPresentation.rotationMinutes(seconds: 299), 5)
        XCTAssertEqual(SettingsPresentation.rotationMinutes(seconds: 302), 5)
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

    func testPlayModeLabelCoversAllCasesInOrder() {
        XCTAssertEqual(PlayMode.allCases.map(SettingsPresentation.playModeLabel),
                       ["单循环", "列表循环", "随机"])
    }

    /// 轮播方式的标签按来源分派。图片不谈「循环」—— 同一张图不会「循环播放」，它是「不变」；
    /// 写成「单图循环」会让用户以为图片自己在动。
    func testPlayModeLabelForImageUsesCarouselWording() {
        XCTAssertEqual(PlayMode.allCases.map { SettingsPresentation.playModeLabel($0, kind: .image) },
                       ["单张不变", "顺序轮播", "随机轮播"])
    }

    /// 派发函数最容易顺手把两版写成一样 —— 视频这三个字一个都不能动。
    func testPlayModeLabelForVideoIsUnchangedByDispatch() {
        XCTAssertEqual(PlayMode.allCases.map { SettingsPresentation.playModeLabel($0, kind: .video) },
                       ["单循环", "列表循环", "随机"])
    }

    func testResolutionTierLabelsFollowTierOrder() {
        XCTAssertEqual(SettingsPresentation.resolutionTierLabels(), ["1080P", "2K", "4K"])
        XCTAssertEqual(ImageResolutionTier.allCases.map(\.pixels),
                       [2_073_600, 3_686_400, 8_294_400])
    }

    func testResolutionTierIndexRoundTrips() {
        for (index, tier) in ImageResolutionTier.allCases.enumerated() {
            XCTAssertEqual(SettingsPresentation.resolutionTierIndex(pixels: tier.pixels), index)
            XCTAssertEqual(SettingsPresentation.resolutionTierPixels(index: index), tier.pixels)
        }
    }

    /// 对不上任何一档的像素值（手改过 / 旧版本）必须吸附，否则分段控件会索引越界。
    func testResolutionTierIndexSnapsToNearestTier() {
        XCTAssertEqual(SettingsPresentation.resolutionTierIndex(pixels: 1), 0)
        XCTAssertEqual(SettingsPresentation.resolutionTierIndex(pixels: 3_000_000), 1)
        XCTAssertEqual(SettingsPresentation.resolutionTierIndex(pixels: 99_000_000), 2)
    }

    func testResolutionTierPixelsClampsOutOfRangeIndex() {
        XCTAssertEqual(SettingsPresentation.resolutionTierPixels(index: -1),
                       ImageResolutionTier.p1080.pixels)
        XCTAssertEqual(SettingsPresentation.resolutionTierPixels(index: 99),
                       ImageResolutionTier.p1080.pixels)
    }

    /// 哨兵写在本测试里，不引用常量 —— 常量改一个字这里就红。
    func testEmptyStateBodyMatchesSpecVerbatim() {
        XCTAssertEqual(SettingsPresentation.emptyStateBody,
                       "没找到能播的文件。壁纸已隐藏，桌面显示的是系统原壁纸。")
    }

    /// 文案只能有一份拷贝 —— 第二份拷贝不会自己漂移提醒，它会漂移成两个版本的承诺。
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

    /// UI 不区分「没配过 / 目录没了 / 扫到 0」，判定就是「不该显示壁纸」的反面；用 `allCases` 穷举，不手抄清单。
    func testThreeHideStatesShareOneEmptySkin() {
        var hidden = 0
        for state in LibraryState.allCases {
            XCTAssertEqual(SettingsPresentation.isEmptyState(state),
                           !state.shouldShowWallpaper, String(describing: state))
            if !state.shouldShowWallpaper { hidden += 1 }
        }
        XCTAssertEqual(hidden, 3)
    }

    /// 三种空态必须给出两两不同的标题与主行动 —— 压成同一份就退回了「三态一张皮」，用户仍不知道下一步。
    func testEmptyStateCopyDistinguishesThreeVariants() {
        let variants: [LibraryState] = [.folderUnconfigured, .folderMissing, .noPlayableVideos]
        let copies = variants.compactMap { SettingsPresentation.emptyStateCopy($0) }
        XCTAssertEqual(copies.count, 3, "三种空态都必须给出文案")
        XCTAssertEqual(Set(copies.map(\.title)).count, 3, "三种空态标题两两不同")
        XCTAssertEqual(Set(copies.map(\.primaryAction)).count, 3, "三种空态主行动两两不同")
        XCTAssertNil(SettingsPresentation.emptyStateCopy(.playing), "播放中不该显示空态")
    }

    /// 同一个 `LibraryState` 在两种来源下是**两件事**：图片没有转码这条路，
    /// 沿用视频文案会把「不够档位」说成「不能播放」，主行动还会指向一个不存在的动作。
    func testEmptyStateCopyDiffersByWallpaperKind() {
        // 没配目录：两种来源的主行动都是「选文件夹」，只有标题与原因不同 ——
        // 断言主行动也必须不同是错的，那会逼着把一个正确的共享文案拆成两份。
        let unconfiguredVideo = SettingsPresentation.emptyStateCopy(.folderUnconfigured, kind: .video)
        let unconfiguredImage = SettingsPresentation.emptyStateCopy(.folderUnconfigured, kind: .image)
        XCTAssertNotNil(unconfiguredVideo)
        XCTAssertNotNil(unconfiguredImage)
        XCTAssertNotEqual(unconfiguredVideo?.title, unconfiguredImage?.title)
        XCTAssertEqual(unconfiguredVideo?.primaryAction, unconfiguredImage?.primaryAction,
                       "没配目录就是去选目录，与媒体类型无关")

        let video = SettingsPresentation.emptyStateCopy(.noPlayableVideos, kind: .video)
        let image = SettingsPresentation.emptyStateCopy(.noPlayableVideos, kind: .image)
        XCTAssertNotEqual(video?.title, image?.title)
        XCTAssertNotEqual(video?.primaryAction, image?.primaryAction, "图片没有转码这条路")
        XCTAssertFalse(image?.reason.contains("MP4") ?? true, "图片空态不该提 MP4 转码")
    }

    /// 目录不见那一条两种来源同文案 —— 它与媒体类型无关，分派只该发生在有差异的两条上。
    func testFolderMissingCopyIsSharedByBothKinds() {
        XCTAssertEqual(SettingsPresentation.emptyStateCopy(.folderMissing, kind: .video),
                       SettingsPresentation.emptyStateCopy(.folderMissing, kind: .image))
    }

    func testHoldReasonLabelsCoverAllSixCasesVerbatim() {
        let expected: [HoldReason: String] = [
            .manualPause: "手动暂停",
            .fullscreen: "检测到全屏/最大化窗口",
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

    /// 拿掉排序这一行，多原因用例转红。
    func testJoinedReasonsSortsByOrderBeforeJoining() {
        XCTAssertEqual(SettingsPresentation.joinedReasons([.screenLocked, .manualPause]),
                       "手动暂停、屏幕已锁定")
        XCTAssertEqual(SettingsPresentation.joinedReasons([.battery, .systemSleeping, .fullscreen]),
                       "检测到全屏/最大化窗口、系统正在睡眠、电池供电中")
    }

    func testJoinedReasonsEmptyReturnsEmptyString() {
        XCTAssertEqual(SettingsPresentation.joinedReasons([]), "")
    }

    func testJoinedReasonsSingleReasonHasNoSeparator() {
        XCTAssertEqual(SettingsPresentation.joinedReasons([.manualPause]), "手动暂停")
    }
}
