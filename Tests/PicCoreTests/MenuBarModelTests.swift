import XCTest
@testable import PicCore

/// MENUBAR-08 的哨兵法 —— 菜单栏**不显示当前播放的文件名**。
///
/// 菜单栏是全局常驻、路过的人一眼能扫到的地方。文件名会泄露用户在看的片子
/// （「Work-Interview-Final-v3.mp4」这类），所以这条要求必须有牙齿，
/// 不能只是一句「我们不写文件名」的纪律。
///
/// 哨兵串 `clip-sentinel.mp4` 是 02-01 生成的合成视频的**文件名本身**，没有第二个别名。
/// ⚠️ 这里以字面量写死，**不去读 `fixtures/` 里的真实文件** —— 否则干净 clone 上
/// （fixtures 未生成）`swift test` 会红。
@MainActor
final class MenuBarModelTests: XCTestCase {

    /// 哨兵串。菜单标签里出现 0 次即通过。
    private static let sentinelFilename = "clip-sentinel.mp4"

    /// 一个不存在于磁盘、但绝不会出现在菜单里的目录名 —— 用来证明
    /// 「菜单不依赖 SettingsStore 的当前值」。不建这个目录，测试不依赖任何文件系统状态。
    private static let fakeFolder = "/tmp/pic-menu-sentinel-dir-4242"

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "pic.tests.menubar.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        if let suiteName {
            defaults?.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    private func makeStore() -> SettingsStore {
        var seed = SettingsStore.Seed()
        seed.sourceFolder = Self.fakeFolder
        return SettingsStore(defaults: defaults!, seed: seed)
    }

    /// 仲裁器的假播放端 —— 「spy」打在它记录到的 `applies` 上。
    /// `HoldArbiter` 是 final class，不能用子类替身；改用真仲裁器 + 假播放端，
    /// 断言的是**仲裁器真的被驱动了**，而不是某个 mock 的调用计数。
    private final class SpyTarget: PlaybackTarget {
        var position: TimeInterval = 0
        var seeks: [TimeInterval] = []
        var applies: [PlaybackDecision] = []

        func arbiterCurrentPosition() -> TimeInterval { position }
        func arbiterSeek(to seconds: TimeInterval) { seeks.append(seconds) }
        func arbiterApply(_ decision: PlaybackDecision) { applies.append(decision) }
    }

    // MARK: - 标签数量

    func testLabelsHaveExactlyFiveEntriesInEveryState() {
        for isPaused in [false, true] {
            let labels = MenuBarModel.labels(isPaused: isPaused)
            XCTAssertEqual(labels.count, MenuItemID.allCases.count,
                           "菜单项数量必须恒等于 MenuItemID.allCases")
            XCTAssertEqual(labels.count, 5, "本 Phase 起共五项菜单（Phase 2 三项 + Phase 4 新增两项）")
            XCTAssertEqual(Set(labels).count, labels.count, "五项文案不得重复")
        }
    }

    // MARK: - 隐私（哨兵法）

    func testLabelsNeverContainAnyMediaFileName() {
        // 三种状态各来一遍：暂停 / 播放 / 已有设置路径。
        for isPaused in [false, true] {
            let labels = MenuBarModel.labels(isPaused: isPaused)
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
        let playing = MenuBarModel.label(for: .pauseResume, isPaused: false)
        let paused = MenuBarModel.label(for: .pauseResume, isPaused: true)

        XCTAssertNotEqual(playing, paused, "暂停/继续必须是两个不同的文案")
        for label in [playing, paused] {
            XCTAssertFalse(label.contains(Self.sentinelFilename))
            XCTAssertFalse(label.contains(".mp4"))
            XCTAssertFalse(label.contains("sentinel"))
        }
    }

    // MARK: - 动作接线

    func testPerformQuitCallsInjectedClosureOnlyOnce() {
        let target = SpyTarget()
        let arbiter = HoldArbiter(target: target)
        var quitCalls = 0

        MenuBarModel.perform(.quit, isPaused: false, store: makeStore(),
                             arbiter: arbiter, quit: { quitCalls += 1 })

        XCTAssertEqual(quitCalls, 1, "「退出」必须调注入的闭包，且只调一次")
        XCTAssertTrue(arbiter.decision.shouldPlay, "退出不应改动播放状态")
        XCTAssertEqual(target.applies.count, 0, "退出不应把决策推给播放端")
    }

    func testPerformPauseResumeGoesThroughArbiterNotDirectly() {
        let target = SpyTarget()
        let arbiter = HoldArbiter(target: target)

        MenuBarModel.perform(.pauseResume, isPaused: false, store: makeStore(),
                             arbiter: arbiter, quit: {})
        XCTAssertEqual(arbiter.decision.holds, [.manualPause],
                       "第一次点应进入手动暂停 —— 走的必须是仲裁器")
        XCTAssertFalse(arbiter.decision.shouldPlay)
        XCTAssertEqual(target.applies.count, 1, "仲裁器应把决策推给播放端一次")

        MenuBarModel.perform(.pauseResume, isPaused: true, store: makeStore(),
                             arbiter: arbiter, quit: {})
        XCTAssertEqual(arbiter.decision.holds, [], "第二次点应解除暂停")
        XCTAssertTrue(arbiter.decision.shouldPlay)
    }

    func testPerformOpenSettingsTouchesNeitherQuitNorPlayback() {
        let target = SpyTarget()
        let arbiter = HoldArbiter(target: target)
        var quitCalls = 0

        MenuBarModel.perform(.openSettings, isPaused: false, store: makeStore(),
                             arbiter: arbiter, quit: { quitCalls += 1 })

        XCTAssertEqual(quitCalls, 0, "打开设置不得触发退出")
        XCTAssertTrue(arbiter.decision.shouldPlay, "打开设置不得改动播放状态")
        XCTAssertEqual(target.applies.count, 0, "打开设置不得把决策推给播放端")
    }

    // MARK: - Phase 4 新增两项（Plan 04-04 T1）

    func testNextVideoAndRescanLabelsAreDistinctAndPathless() {
        for isPaused in [false, true] {
            XCTAssertEqual(MenuBarModel.label(for: .nextVideo, isPaused: isPaused),
                           "立即下一个", "「立即下一个」文案逐字冻结（Phase 5 的 UI-SPEC 引用它）")
            XCTAssertEqual(MenuBarModel.label(for: .rescanFolder, isPaused: isPaused),
                           "重新扫描文件夹", "「重新扫描文件夹」文案逐字冻结（Phase 5 的 UI-SPEC 引用它）")
        }
        let next = MenuBarModel.label(for: .nextVideo, isPaused: false)
        let rescan = MenuBarModel.label(for: .rescanFolder, isPaused: false)
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

        MenuBarModel.perform(.nextVideo, isPaused: false, store: makeStore(),
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

        MenuBarModel.perform(.rescanFolder, isPaused: false, store: makeStore(),
                             arbiter: arbiter, quit: { quitCalls += 1 },
                             rescanFolder: { rescanCalls += 1 })

        XCTAssertEqual(rescanCalls, 1, "「重新扫描文件夹」必须调注入的闭包，且只调一次")
        XCTAssertEqual(quitCalls, 0, "重新扫描文件夹不得触发退出")
        XCTAssertTrue(arbiter.decision.shouldPlay, "重新扫描文件夹不得改动播放状态")
        XCTAssertEqual(target.applies.count, 0, "重新扫描文件夹不得把决策推给播放端")
    }

    // MARK: - 枚举本身的形状

    func testMenuItemIDsAreExactlyTheFiveFixedItems() {
        XCTAssertEqual(MenuItemID.allCases,
                       [.pauseResume, .nextVideo, .rescanFolder, .openSettings, .quit],
                       "五项菜单，顺序冻结：新增项插在 openSettings 之前、quit 保持最后（分隔线规则依赖它）")
    }
}
