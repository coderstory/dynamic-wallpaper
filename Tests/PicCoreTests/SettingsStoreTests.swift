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
        defaults.removePersistentDomain(forName: suiteName)
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
}
