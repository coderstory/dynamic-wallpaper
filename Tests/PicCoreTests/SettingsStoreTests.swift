import XCTest
@testable import PicCore

/// 每个用例用独立的 `UserDefaults(suiteName:)`，绝不碰真实域；也不依赖 `fixtures/` 已生成 —— 干净 clone 上 `swift test` 也必须绿。
@MainActor
final class SettingsStoreTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "pic.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        unsetenv(SettingsStore.envSourceFolderKey)
    }

    override func tearDown() async throws {
        unsetenv(SettingsStore.envSourceFolderKey)
        TestDefaults.purge(suiteName)
        defaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    private func makeStore(seed: SettingsStore.Seed = SettingsStore.Seed()) -> SettingsStore {
        SettingsStore(defaults: defaults, seed: seed)
    }

    func testEnvVarWinsOverUserDefaults() {
        defaults.set("/from/defaults", forKey: SettingsStore.Key.sourceFolderPath)
        setenv(SettingsStore.envSourceFolderKey, "/from/env", 1)

        let store = makeStore(seed: SettingsStore.Seed(sourceFolder: "/from/seed"))
        XCTAssertEqual(store.sourceFolder, "/from/env")
    }

    func testUserDefaultsWinsOverSeed() {
        defaults.set("/from/defaults", forKey: SettingsStore.Key.sourceFolderPath)

        let store = makeStore(seed: SettingsStore.Seed(sourceFolder: "/from/seed"))
        XCTAssertEqual(store.sourceFolder, "/from/defaults")
    }

    func testSeedUsedWhenNothingElseSet() {
        let store = makeStore(seed: SettingsStore.Seed(
            sourceFolder: "/from/seed", rate: 1.5, volume: 0.25,
            isMuted: true, playMode: .loopSingle, rotationInterval: 42
        ))
        XCTAssertEqual(store.sourceFolder, "/from/seed")
        XCTAssertEqual(store.rate, 1.5)
        XCTAssertEqual(store.volume, 0.25)
        XCTAssertTrue(store.isMuted)
        XCTAssertEqual(store.rotationInterval, 42)
    }

    func testResolvedFolderURLHasNoSchemeSeparator() {
        let store = makeStore(seed: SettingsStore.Seed(sourceFolder: "/tmp/pic-fixtures"))
        let url = store.resolvedFolderURL()
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.path, "/tmp/pic-fixtures")
        XCTAssertFalse(url?.path.contains("://") ?? true,
                      "文件存在性检查只认裸路径，不认 URL 字符串")
    }

    func testFileExistsUsesPathAndSeesTempFile() throws {
        // 用 URL(fileURLWithPath:isDirectory:) 显式构造，避免 temporaryDirectory 自带尾斜杠导致 resolvedFolderURL().path 与 tmp.path 比不相等（那是测试夹具的坑，不是产品行为）。
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("pic-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let file = tmp.appendingPathComponent("sample.mp4")
        XCTAssertTrue(FileManager.default.createFile(atPath: file.path, contents: Data([0x00])))

        let store = makeStore(seed: SettingsStore.Seed(sourceFolder: tmp.path))
        XCTAssertEqual(store.resolvedFolderURL()?.path, tmp.path)
        XCTAssertTrue(store.fileExists(at: file))
    }

    func testFileExistsFalseForMissingPath() {
        let store = makeStore(seed: SettingsStore.Seed(sourceFolder: "/tmp"))
        let missing = URL(fileURLWithPath: "/tmp/pic-definitely-missing-\(UUID().uuidString)")
        XCTAssertFalse(store.fileExists(at: missing))
    }

    func testPersistWritesBackToDefaults() {
        let store = makeStore(seed: SettingsStore.Seed(sourceFolder: "/from/seed"))
        store.rate = 1.5
        store.volume = 0.25
        store.isMuted = true
        store.sourceFolder = "/persisted"
        store.persist()

        XCTAssertEqual(defaults.double(forKey: SettingsStore.Key.rate), 1.5)
        XCTAssertEqual(defaults.double(forKey: SettingsStore.Key.volume), 0.25)
        XCTAssertEqual(defaults.bool(forKey: SettingsStore.Key.muted), true)
        XCTAssertEqual(defaults.string(forKey: SettingsStore.Key.sourceFolderPath), "/persisted")
    }

    func testPlayModeDefaultIsLoopSingle() {
        XCTAssertEqual(SettingsStore.Seed().playMode, .loopSingle)
        XCTAssertEqual(makeStore().playMode, .loopSingle)
        XCTAssertEqual(PlayMode.allCases, [.loopSingle, .loopList, .shuffle],
                       "Phase 2 只枚举单循环；列表循环/列表随机是 Phase 4（Plan 04-02）纯追加的 case")
    }

    /// seed 层与解析层**两道**默认都要断言：`Seed` 的参数默认值管「没给种子」，
    /// `init` 的 `?? seed.pauseOnBattery` 兜底管「给了种子但键不存在」。只断一道，另一道仍可能默认开。
    func testPauseOnBatteryDefaultsToFalseWithEmptyDefaults() {
        XCTAssertFalse(SettingsStore.Seed().pauseOnBattery,
                       "种子层的默认值必须是 false（D-11）")
        XCTAssertFalse(makeStore().pauseOnBattery,
                       "空 UserDefaults 下解析出的值必须是 false（D-11）")
    }

    func testSeedCanTurnPauseOnBatteryOn() {
        let store = makeStore(seed: SettingsStore.Seed(pauseOnBattery: true))
        XCTAssertTrue(store.pauseOnBattery)
    }

    func testUserDefaultsWinsOverSeedForPauseOnBattery() {
        defaults.set(true, forKey: SettingsStore.Key.pauseOnBattery)
        let store = makeStore(seed: SettingsStore.Seed(pauseOnBattery: false))
        XCTAssertTrue(store.pauseOnBattery, "UserDefaults 必须压过 seed")
    }

    /// **真值和假值都得能持久化**：只断言存 true 会漏掉「只写 true、false 写不回去」这种实现 ——
    /// 那正是「用户在设置窗里把开关关掉，改完重启又自己开回来」的故障形状。
    func testPersistWritesPauseOnBattery() {
        let store = makeStore()

        store.pauseOnBattery = true
        store.persist()
        XCTAssertTrue(defaults.bool(forKey: SettingsStore.Key.pauseOnBattery))

        store.pauseOnBattery = false
        store.persist()
        XCTAssertFalse(defaults.bool(forKey: SettingsStore.Key.pauseOnBattery),
                       "关掉也必须能持久化 —— 否则设置窗里关掉的开关会自己开回来")
    }

    /// 默认 false 是**产品决策**不是实现细节：自启是用户显式打开的东西，默认开等于替用户往开机项里塞一个登录项。
    /// round-trip 是自启的前提：开关不持久化，用户拨开的设置重启即丢。
    func testLaunchAtLoginDefaultsFalseAndRoundTrips() {
        XCTAssertFalse(SettingsStore.Seed().launchAtLogin, "种子层的默认值必须是 false")
        XCTAssertFalse(makeStore().launchAtLogin, "空 UserDefaults 下解析出的值必须是 false")

        let store = makeStore()
        store.launchAtLogin = true
        store.persist()
        XCTAssertTrue(defaults.bool(forKey: SettingsStore.Key.launchAtLogin))

        XCTAssertTrue(makeStore().launchAtLogin, "重建的 store 必须读回 true")
    }

    /// 液态玻璃是**显式开启**的视觉偏好：默认关保证老用户升级后界面逐像素不变。
    /// 纯展示偏好不走 Applier，持久化只为「拨过一次就记住」。
    func testLiquidGlassDefaultsFalseAndRoundTrips() {
        XCTAssertFalse(SettingsStore.Seed().liquidGlassEnabled, "种子层的默认值必须是 false")
        XCTAssertFalse(makeStore().liquidGlassEnabled, "空 UserDefaults 下解析出的值必须是 false")

        let store = makeStore()
        store.liquidGlassEnabled = true
        store.persist()
        XCTAssertTrue(defaults.object(forKey: SettingsStore.Key.liquidGlassEnabled) != nil,
                      "persist 后 defaults 里必须存在这个键")
        XCTAssertTrue(defaults.bool(forKey: SettingsStore.Key.liquidGlassEnabled))
        XCTAssertTrue(makeStore().liquidGlassEnabled, "重建的 store 必须读回 true")

        store.liquidGlassEnabled = false
        store.persist()
        XCTAssertFalse(defaults.bool(forKey: SettingsStore.Key.liquidGlassEnabled),
                       "关掉也必须能持久化 —— 否则设置窗里关掉的开关会自己开回来")
    }

    /// 纯追加的回归防线：既有六字段一个都没改名、没改顺序，所以**位置无关的具名传参**必须照旧编译。
    /// 谁把 `pauseOnBattery` 插进既有参数的中间（而不是末尾），或改了某个既有参数的类型，这里立刻编译不过。
    func testExistingSeedCallSitesStillCompile() {
        XCTAssertNotNil(SettingsStore.Seed())

        let store = makeStore(seed: SettingsStore.Seed(
            sourceFolder: "/from/seed", rate: 1.5, volume: 0.25,
            isMuted: true, playMode: .loopSingle, rotationInterval: 42
        ))
        XCTAssertEqual(store.sourceFolder, "/from/seed")
        XCTAssertEqual(store.rate, 1.5)
        XCTAssertEqual(store.volume, 0.25)
        XCTAssertTrue(store.isMuted)
        XCTAssertEqual(store.playMode, .loopSingle)
        XCTAssertEqual(store.rotationInterval, 42)
    }

    /// 上次播放的路径与进度：写盘 → 新实例读回（单循环续播的持久化契约）。
    func testLastPlayedRoundTripsAcrossInstances() {
        let store = makeStore()
        store.lastPlayedPath = "/tmp/pic-0402-fixture/v1.mp4"
        store.lastPlayedPosition = 37.5
        store.persist()

        let reopened = makeStore()
        XCTAssertEqual(reopened.lastPlayedPath, "/tmp/pic-0402-fixture/v1.mp4")
        XCTAssertEqual(reopened.lastPlayedPosition, 37.5, accuracy: 0.001)
    }

    /// 首次启动（无持久化值）：路径为空串、进度为 0 —— 续播逻辑据此判定「没有上次」。
    func testLastPlayedDefaultsToEmptyOnFreshInstall() {
        let store = makeStore()
        XCTAssertEqual(store.lastPlayedPath, "")
        XCTAssertEqual(store.lastPlayedPosition, 0)
    }

    // MARK: - 壁纸来源（视频 / 图片）

    /// 老用户的 UserDefaults 里**没有** `wallpaperKind`。读不到必须静默回落 `.video`，
    /// 而不是要求一次迁移 —— 迁移脚本是纯负担，且失败形状是「老用户升级后壁纸没了」。
    func testWallpaperKindDefaultsToVideoForExistingUsers() {
        XCTAssertEqual(SettingsStore.Seed().wallpaperKind, .video, "种子层的默认值必须是 .video")
        XCTAssertEqual(makeStore().wallpaperKind, .video, "空 UserDefaults 下必须解析出 .video")
    }

    /// 切换是**真持久化偏好**：不落盘的话用户切到图片、重启又变回视频。
    func testWallpaperKindRoundTrips() {
        let store = makeStore()
        store.wallpaperKind = .image
        store.persist()

        XCTAssertEqual(makeStore().wallpaperKind, .image)
    }

    /// 存进去的 rawValue 不在枚举里（手改 plist / 未来删了某个 case）时回落种子值，不能崩。
    func testUnknownWallpaperKindRawValueFallsBackToSeed() {
        defaults.set("wallpaper", forKey: SettingsStore.Key.wallpaperKind)
        XCTAssertEqual(makeStore().wallpaperKind, .video)
    }

    func testImagePreferencesRoundTrip() {
        let store = makeStore()
        store.imageFolderPath = "/Users/me/Pictures"
        store.imageMinPixels = ImageResolutionTier.k4.pixels
        store.imageFit = .fit
        store.lastImagePath = "/Users/me/Pictures/a.png"
        store.persist()

        let reopened = makeStore()
        XCTAssertEqual(reopened.imageFolderPath, "/Users/me/Pictures")
        XCTAssertEqual(reopened.imageMinPixels, ImageResolutionTier.k4.pixels)
        XCTAssertEqual(reopened.imageFit, .fit)
        XCTAssertEqual(reopened.lastImagePath, "/Users/me/Pictures/a.png")
    }

    func testImagePreferencesDefaults() {
        let store = makeStore()
        XCTAssertEqual(store.imageFolderPath, "")
        XCTAssertEqual(store.imageMinPixels, ImageResolutionTier.k2.pixels, "默认档位是 2K")
        XCTAssertEqual(store.imageFit, .fill, "默认填充，与系统壁纸一致")
        XCTAssertEqual(store.lastImagePath, "")
    }

    /// 两个来源的目录**并存**：配了图片目录不代表视频目录失效，切换改的是「用哪个」而不是「哪个存在」。
    func testResolvedFolderURLIsPerKind() {
        let store = makeStore(seed: SettingsStore.Seed(
            sourceFolder: "/tmp/videos", imageFolderPath: "/tmp/pics"))
        XCTAssertEqual(store.resolvedFolderURL(for: .video)?.path, "/tmp/videos")
        XCTAssertEqual(store.resolvedFolderURL(for: .image)?.path, "/tmp/pics")

        store.wallpaperKind = .image
        XCTAssertEqual(store.resolvedFolderURL()?.path, "/tmp/pics", "无参版本必须跟当前 kind 走")
    }

    /// 图片目录没配就是 nil，**不回落到视频目录**：回落会让「图片未配置」的空态永远不出现，
    /// 用户切过去看到的是视频的片库，以为切换没生效。
    func testResolvedFolderURLForImageIsNilWhenUnconfigured() {
        let store = makeStore(seed: SettingsStore.Seed(sourceFolder: "/tmp/videos"))
        XCTAssertNil(store.resolvedFolderURL(for: .image))
        XCTAssertEqual(store.resolvedFolderURL(for: .video)?.path, "/tmp/videos")
    }
}
