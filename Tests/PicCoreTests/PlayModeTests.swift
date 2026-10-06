import XCTest
@testable import PicCore

/// 每个用例用独立的 `UserDefaults(suiteName:)`，绝不碰真实域；`setUp` 里 `unsetenv`
/// 开发期覆盖入口，否则宿主环境变量会盖过注入的 suite。
@MainActor
final class PlayModeTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "pic.tests.playmode.\(UUID().uuidString)"
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

    /// rawValue 逐字未改，**且**新 case 是追加而不是插在前面 —— 设置窗分段控件按 `allCases`
    /// 顺序渲染，插到前面会改变 UI。
    func testLoopSingleRawValueIsUnchangedAndStaysFirstCase() {
        XCTAssertEqual(PlayMode.loopSingle.rawValue, "loopSingle",
                       "loopSingle 的 rawValue 已持久化进老用户偏好，改名等于让他们的设置失效（D-04）")
        XCTAssertEqual(PlayMode.allCases.first, .loopSingle,
                       "新 case 必须追加在 loopSingle 之后，不许插到前面")
    }

    func testAllCasesAreExactlyThreeInDeclarationOrder() {
        XCTAssertEqual(PlayMode.allCases, [.loopSingle, .loopList, .shuffle],
                       "三种播放模式，声明顺序即渲染顺序（PLAY-03/04/05）")
    }

    /// 端到端：用户偏好里存的就是字符串 "loopSingle"，新增 case 不得让老配置回落。
    func testPersistedLoopSingleStringStillResolvesFromUserDefaults() {
        defaults.set("loopSingle", forKey: SettingsStore.Key.playMode)
        let store = makeStore(seed: SettingsStore.Seed(playMode: .shuffle))
        XCTAssertEqual(store.playMode, .loopSingle,
                       "老配置里的 \"loopSingle\" 必须仍解析回 .loopSingle，不能回落到 seed")
    }

    /// 未知 rawValue 回落到 seed 的既有兜底行为不被新增 case 改变。
    func testUnknownPersistedRawValueFallsBackToSeed() {
        defaults.set("legacyModeThatNeverExisted", forKey: SettingsStore.Key.playMode)
        let store = makeStore(seed: SettingsStore.Seed(playMode: .shuffle))
        XCTAssertEqual(store.playMode, .shuffle,
                       "未知 rawValue 必须回落到 seed.playMode —— 兜底行为与 Phase 2 一致")
    }

    /// `persist()` 写出的键集合**恰好**是那 8 个。过滤用「排除系统注入键」而不是「包含某前缀」：
    /// `dictionaryRepresentation()` 对 suite 域返回**不带 suite 前缀的裸键名**，且混有系统键
    /// （`AppleLanguages` / `com.apple.*` / `NS*` 一类）。系统键集合从一个**全新的空 suite**
    /// 实测取得，不写死清单 —— 谁往 `persist()` 里多加一个键，差集里立刻多出一项，这条当场红。
    func testPersistWritesExactlyTheEightKnownKeys() {
        let baselineName = "pic.tests.playmode.baseline.\(UUID().uuidString)"
        guard let baseline = UserDefaults(suiteName: baselineName) else {
            return XCTFail("baseline suite 创建失败")
        }
        defer { baseline.removePersistentDomain(forName: baselineName) }
        let systemKeys = Set(baseline.dictionaryRepresentation().keys)

        let store = makeStore()
        store.persist()

        let written = Set(defaults.dictionaryRepresentation().keys).subtracting(systemKeys)
        let expected: Set<String> = [
            SettingsStore.Key.sourceFolderPath,
            SettingsStore.Key.rate,
            SettingsStore.Key.volume,
            SettingsStore.Key.muted,
            SettingsStore.Key.playMode,
            SettingsStore.Key.rotationInterval,
            SettingsStore.Key.pauseOnBattery,
            SettingsStore.Key.launchAtLogin,
        ]
        XCTAssertEqual(written, expected,
                       "persist() 写出的键必须恰好是已知的 8 个（D-03）—— 多一个少一个都算破契约")
    }
}
