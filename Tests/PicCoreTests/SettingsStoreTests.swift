import XCTest
@testable import PicCore

/// 设置解析单测。
///
/// 每个用例用独立的 `UserDefaults(suiteName:)`，绝不碰真实域。
/// 且**不依赖 `fixtures/` 已生成** —— 干净 clone 上 `swift test` 也必须绿。
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
        // 用 URL(fileURLWithPath:isDirectory:) 显式构造，避免 temporaryDirectory 自带尾斜杠
        // 导致 resolvedFolderURL().path 与 tmp.path 比不相等（那是测试夹具的坑，不是产品行为）。
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
        XCTAssertEqual(PlayMode.allCases, [.loopSingle],
                       "Phase 2 只枚举单循环；随机/顺序/播完停止属 Phase 4")
    }
}
