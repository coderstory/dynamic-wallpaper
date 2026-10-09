import XCTest
@testable import PicCore

/// 菜单栏**不显示当前播放的文件名**。哨兵串 `clip-sentinel.mp4` 以字面量写死，
/// 不读 `fixtures/` 里的真实文件 —— fixtures 未生成时干净 clone 上 `swift test` 会红。
@MainActor
final class MenuBarModelTests: XCTestCase {

    private static let sentinelFilename = "clip-sentinel.mp4"

    /// 一个不存在于磁盘的哨兵目录名 —— 用来证明菜单文案不泄露目录。
    /// 不建这个目录，测试不依赖任何文件系统状态，换台机器也照样过。
    private static let fakeFolder = "/tmp/pic-menu-sentinel-dir-4242"

    /// 假播放端只记录 `applies`。`HoldArbiter` 是 final class 不能用子类替身，所以改用真仲裁器 + 假播放端：
    /// 断言的是仲裁器真的被驱动了，不是某个 mock 的调用计数。
    private final class SpyTarget: PlaybackTarget {
        var position: TimeInterval = 0
        var seeks: [TimeInterval] = []
        var applies: [PlaybackDecision] = []

        func arbiterCurrentPosition() -> TimeInterval { position }
        func arbiterSeek(to seconds: TimeInterval) { seeks.append(seconds) }
        func arbiterApply(_ decision: PlaybackDecision) { applies.append(decision) }
    }

    func testLabelsHaveExactlySixEntriesInEveryState() {
        for isPaused in [false, true] {
            let labels = MenuItemID.allCases.map { MenuBarModel.label(for: $0, isPaused: isPaused, kind: .video) }
            XCTAssertEqual(labels.count, MenuItemID.allCases.count,
                           "菜单项数量必须恒等于 MenuItemID.allCases")
            XCTAssertEqual(labels.count, 7, "共七项菜单（六项 + 切换壁纸来源）")
            XCTAssertEqual(Set(labels).count, labels.count, "七项文案不得重复")
        }
    }

    func testDeleteCurrentLabelNeverNamesAFile() {
        for isPaused in [false, true] {
            let label = MenuBarModel.label(for: .deleteCurrent, isPaused: isPaused, kind: .video)
            XCTAssertFalse(label.contains(Self.sentinelFilename), "删除项文案泄露了文件名：\(label)")
            XCTAssertFalse(label.lowercased().contains(".mp4"), "删除项文案泄露了扩展名：\(label)")
            XCTAssertFalse(label.contains(Self.fakeFolder), "删除项文案泄露了目录：\(label)")
        }
    }

    func testLabelsNeverContainAnyMediaFileName() {
        for isPaused in [false, true] {
            let labels = MenuItemID.allCases.map { MenuBarModel.label(for: $0, isPaused: isPaused, kind: .video) }
            let blob = labels.joined(separator: "|")

            XCTAssertFalse(blob.contains(Self.sentinelFilename),
                           "菜单标签里出现了哨兵文件名：\(labels)")
            XCTAssertFalse(blob.contains(".mp4"),
                           "菜单标签里出现了媒体扩展名：\(labels)")
            XCTAssertFalse(blob.contains(Self.fakeFolder),
                           "菜单标签里出现了源目录全路径：\(labels)")
            XCTAssertFalse(blob.contains("sentinel-dir-4242"),
                           "菜单标签里出现了源目录名：\(labels)")
        }
    }

    func testPauseResumeLabelIsExactlyTwoStringsWithoutFileNameParts() {
        let playing = MenuBarModel.label(for: .pauseResume, isPaused: false, kind: .video)
        let paused = MenuBarModel.label(for: .pauseResume, isPaused: true, kind: .video)

        XCTAssertNotEqual(playing, paused, "暂停/继续必须是两个不同的文案")
        for label in [playing, paused] {
            XCTAssertFalse(label.contains(Self.sentinelFilename))
            XCTAssertFalse(label.contains(".mp4"))
            XCTAssertFalse(label.contains("sentinel"))
        }
    }

    func testPerformQuitCallsInjectedClosureOnlyOnce() {
        let target = SpyTarget()
        let arbiter = HoldArbiter(target: target)
        var quitCalls = 0

        MenuBarModel.perform(.quit, isPaused: false,
                             arbiter: arbiter, quit: { quitCalls += 1 })

        XCTAssertEqual(quitCalls, 1, "「退出」必须调注入的闭包，且只调一次")
        XCTAssertTrue(arbiter.decision.shouldPlay, "退出不应改动播放状态")
        XCTAssertEqual(target.applies.count, 0, "退出不应把决策推给播放端")
    }

    func testPerformPauseResumeGoesThroughArbiterNotDirectly() {
        let target = SpyTarget()
        let arbiter = HoldArbiter(target: target)

        MenuBarModel.perform(.pauseResume, isPaused: false,
                             arbiter: arbiter, quit: {})
        XCTAssertEqual(arbiter.decision.holds, [.manualPause],
                       "第一次点应进入手动暂停 —— 走的必须是仲裁器")
        XCTAssertFalse(arbiter.decision.shouldPlay)
        XCTAssertEqual(target.applies.count, 1, "仲裁器应把决策推给播放端一次")

        MenuBarModel.perform(.pauseResume, isPaused: true,
                             arbiter: arbiter, quit: {})
        XCTAssertEqual(arbiter.decision.holds, [], "第二次点应解除暂停")
        XCTAssertTrue(arbiter.decision.shouldPlay)
    }

    func testPerformOpenSettingsTouchesNeitherQuitNorPlayback() {
        let target = SpyTarget()
        let arbiter = HoldArbiter(target: target)
        var quitCalls = 0

        MenuBarModel.perform(.openSettings, isPaused: false,
                             arbiter: arbiter, quit: { quitCalls += 1 })

        XCTAssertEqual(quitCalls, 0, "打开设置不得触发退出")
        XCTAssertTrue(arbiter.decision.shouldPlay, "打开设置不得改动播放状态")
        XCTAssertEqual(target.applies.count, 0, "打开设置不得把决策推给播放端")
    }

    func testNextVideoAndRescanLabelsAreDistinctAndPathless() {
        for isPaused in [false, true] {
            XCTAssertEqual(MenuBarModel.label(for: .nextVideo, isPaused: isPaused, kind: .video),
                           "立即下一个", "「立即下一个」文案逐字冻结（Phase 5 的 UI-SPEC 引用它）")
            XCTAssertEqual(MenuBarModel.label(for: .rescanFolder, isPaused: isPaused, kind: .video),
                           "重新扫描文件夹", "「重新扫描文件夹」文案逐字冻结（Phase 5 的 UI-SPEC 引用它）")
        }
        let next = MenuBarModel.label(for: .nextVideo, isPaused: false, kind: .video)
        let rescan = MenuBarModel.label(for: .rescanFolder, isPaused: false, kind: .video)
        XCTAssertNotEqual(next, rescan, "两条新文案必须不同")
        for label in [next, rescan] {
            XCTAssertFalse(label.contains(".mp4"), "菜单文案里出现了媒体扩展名：\(label)")
            XCTAssertFalse(label.contains("/"), "菜单文案里出现了路径分隔符：\(label)")
            XCTAssertFalse(label.contains(Self.sentinelFilename), "菜单文案里出现了哨兵文件名：\(label)")
        }
    }

    func testPerformNextVideoCallsOnlyItsInjectedClosure() {
        let target = SpyTarget()
        let arbiter = HoldArbiter(target: target)
        var quitCalls = 0
        var nextCalls = 0

        MenuBarModel.perform(.nextVideo, isPaused: false,
                             arbiter: arbiter, quit: { quitCalls += 1 },
                             nextVideo: { nextCalls += 1 })

        XCTAssertEqual(nextCalls, 1, "「立即下一个」必须调注入的闭包，且只调一次")
        XCTAssertEqual(quitCalls, 0, "立即下一个不得触发退出")
        XCTAssertTrue(arbiter.decision.shouldPlay, "立即下一个不得改动播放状态")
        XCTAssertEqual(target.applies.count, 0, "立即下一个不得把决策推给播放端")
    }

    func testPerformRescanFolderCallsOnlyItsInjectedClosure() {
        let target = SpyTarget()
        let arbiter = HoldArbiter(target: target)
        var quitCalls = 0
        var rescanCalls = 0

        MenuBarModel.perform(.rescanFolder, isPaused: false,
                             arbiter: arbiter, quit: { quitCalls += 1 },
                             rescanFolder: { rescanCalls += 1 })

        XCTAssertEqual(rescanCalls, 1, "「重新扫描文件夹」必须调注入的闭包，且只调一次")
        XCTAssertEqual(quitCalls, 0, "重新扫描文件夹不得触发退出")
        XCTAssertTrue(arbiter.decision.shouldPlay, "重新扫描文件夹不得改动播放状态")
        XCTAssertEqual(target.applies.count, 0, "重新扫描文件夹不得把决策推给播放端")
    }

    func testMenuItemIDsAreExactlyTheSevenFixedItems() {
        XCTAssertEqual(MenuItemID.allCases,
                       [.pauseResume, .nextVideo, .rescanFolder, .switchSource,
                        .deleteCurrent, .openSettings, .quit],
                       "七项菜单，顺序冻结 = 原型 D 面板行序：无副作用操作 → 维护 → 不可逆 → 系统；"
                       + "新增项插在 openSettings 之前、quit 保持最后（面板分隔线位置依赖它）")
    }

    /// 来源项的文案必须随当前来源变：写死成「切换壁纸来源」等于让用户先去设置窗确认现状。
    func testSwitchSourceLabelNamesTheOtherSide() {
        XCTAssertEqual(MenuBarModel.label(for: .switchSource, isPaused: false, kind: .video),
                       "改用图片壁纸")
        XCTAssertEqual(MenuBarModel.label(for: .switchSource, isPaused: false, kind: .image),
                       "改用视频壁纸")
    }

    /// 切换只走注入的闭包 —— 与 deleteCurrent 同款分工：菜单不得自己实现切换链。
    func testPerformSwitchSourceGoesOnlyThroughInjectedClosure() {
        let target = SpyTarget()
        let arbiter = HoldArbiter(target: target)
        var calls = 0
        MenuBarModel.perform(.switchSource, isPaused: false, arbiter: arbiter,
                             quit: {}, switchSource: { calls += 1 })
        XCTAssertEqual(calls, 1, "切换来源必须调注入的闭包，且只调一次")
        XCTAssertEqual(target.applies.count, 0, "菜单不得直接把决策推给播放端")
    }

    func testDeleteCurrentGoesOnlyThroughInjectedClosure() {
        for isPaused in [false, true] {
            let target = SpyTarget()
            let arbiter = HoldArbiter(target: target)
            var deletes = 0
            MenuBarModel.perform(.deleteCurrent, isPaused: isPaused,
                                 arbiter: arbiter,
                                 quit: {},
                                 deleteCurrent: { deletes += 1 })
            XCTAssertEqual(deletes, 1, "删除当前壁纸必须走注入的闭包")
            XCTAssertEqual(target.applies.count, 0, "删除当前壁纸不得把决策推给播放端")
            XCTAssertEqual(arbiter.decision.shouldPlay, true,
                           "删除当前壁纸不得改动播放状态")
        }
    }
}
