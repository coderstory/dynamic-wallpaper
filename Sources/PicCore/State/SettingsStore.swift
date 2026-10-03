import Foundation
import Observation

/// 播放模式。形状在此定死；Phase 4 只新增 case，不动 `SettingsStore` 的签名。
public enum PlayMode: String, CaseIterable, Sendable {
    case loopSingle
    // 列表循环：按顺序走完一圈再回到第一条（PLAY-04 / Plan 04-02）。
    case loopList
    // 列表随机：一轮内每条恰好一次（PLAY-05 / TEST-03）。
    case shuffle
}

/// 所有用户设置的单一真相源（★ 三个接口之一）。
///
/// 职责边界（ARCHITECTURE §5.2）：不含业务逻辑、不碰 AVFoundation、只做持久化与解析。
@MainActor
@Observable
public final class SettingsStore {
    /// 首次启动（尚无任何持久化值）时使用的种子。六个字段覆盖 store 的全部可设项。
    public struct Seed: Sendable {
        public var sourceFolder: String
        public var rate: Float
        public var volume: Float
        public var isMuted: Bool
        public var playMode: PlayMode
        public var rotationInterval: TimeInterval
        /// 「电池供电时暂停」开关（D-11 / PAUSE-05）。**默认 false** ——
        /// 默认开会让用户一拿电池本就无故失去壁纸，看起来像 app 坏了。
        /// Phase 3 纯追加（T-03-14）：前六个字段与它们的默认值一个字未改。
        public var pauseOnBattery: Bool
        /// 「开机自启」开关（SYS-01）。**默认 false** —— 自启是用户显式打开的东西，
        /// 默认开等于替用户往开机项里塞一个登录项。
        /// Phase 7 纯追加（T-07）：前七个字段与它们的默认值一个字未改。
        public var launchAtLogin: Bool

        public init(sourceFolder: String = "", rate: Float = 1.0, volume: Float = 1.0,
                    isMuted: Bool = false, playMode: PlayMode = .loopSingle,
                    rotationInterval: TimeInterval = 300, pauseOnBattery: Bool = false,
                    launchAtLogin: Bool = false) {
            self.sourceFolder = sourceFolder
            self.rate = rate
            self.volume = volume
            self.isMuted = isMuted
            self.playMode = playMode
            self.rotationInterval = rotationInterval
            self.pauseOnBattery = pauseOnBattery
            self.launchAtLogin = launchAtLogin
        }
    }

    /// UserDefaults 键名 —— `scripts/dev-seed.sh` 写的键必须与这里一致。
    public enum Key {
        public static let sourceFolderPath = "sourceFolderPath"
        public static let rate = "rate"
        public static let volume = "volume"
        public static let muted = "muted"
        public static let playMode = "playMode"
        public static let rotationInterval = "rotationInterval"
        /// Phase 3 追加的第七个键。前六个键名**一个字未改**（Phase 2 与
        /// `scripts/dev-seed.sh` 的契约）。
        public static let pauseOnBattery = "pauseOnBattery"
        /// Phase 7 追加的第八个键。前七个键名**一个字未改**（D-03）。
        public static let launchAtLogin = "launchAtLogin"
    }

    /// 开发期覆盖入口（D-03）：`swift run` 起的进程没有 bundle id，
    /// UserDefaults 域取不到 `com.local.pic`，故留一条环境变量路径。
    public static let envSourceFolderKey = "PIC_SOURCE_FOLDER"

    public var sourceFolder: String
    public var rate: Float
    public var volume: Float
    public var isMuted: Bool
    public var playMode: PlayMode
    public var rotationInterval: TimeInterval
    /// 「电池供电时暂停」。**没有环境变量这一级** —— 电源开关不是开发期覆盖项，
    /// 只走 `UserDefaults > seed` 两级（Phase 3 追加）。
    public var pauseOnBattery: Bool
    /// 「开机自启」。**没有环境变量这一级**（Phase 7 追加）——
    /// 开机自启是真持久化偏好，且系统侧状态由 `AutoStartManager` 对齐，不靠开发期覆盖。
    public var launchAtLogin: Bool

    private let defaults: UserDefaults

    public init(defaults: UserDefaults, seed: SettingsStore.Seed) {
        self.defaults = defaults

        // 三级优先：环境变量 > UserDefaults > 传入的 seed（D-03）。
        let envFolder = ProcessInfo.processInfo.environment[SettingsStore.envSourceFolderKey]
        if let envFolder, !envFolder.isEmpty {
            self.sourceFolder = envFolder
        } else {
            self.sourceFolder = defaults.string(forKey: Key.sourceFolderPath) ?? seed.sourceFolder
        }
        self.rate = defaults.object(forKey: Key.rate) as? Float ?? seed.rate
        self.volume = defaults.object(forKey: Key.volume) as? Float ?? seed.volume
        self.isMuted = defaults.object(forKey: Key.muted) as? Bool ?? seed.isMuted
        if let raw = defaults.string(forKey: Key.playMode), let m = PlayMode(rawValue: raw) {
            self.playMode = m
        } else {
            self.playMode = seed.playMode
        }
        self.rotationInterval = defaults.object(forKey: Key.rotationInterval) as? Double
            ?? seed.rotationInterval
        self.pauseOnBattery = defaults.object(forKey: Key.pauseOnBattery) as? Bool ?? seed.pauseOnBattery
        self.launchAtLogin = defaults.object(forKey: Key.launchAtLogin) as? Bool ?? seed.launchAtLogin
    }

    /// 解析后的壁纸目录 URL。
    ///
    /// 只走文件系统路径这一个形态 —— Pitfall 5：存在性检查必须喂 `url.path` 那种
    /// 裸路径，绝不能喂 URL 的字符串形式，否则检查恒为 false。
    public func resolvedFolderURL() -> URL? {
        guard !sourceFolder.isEmpty else { return nil }
        return URL(fileURLWithPath: sourceFolder)
    }

    public func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// 把内存值写回 UserDefaults（Phase 5 的设置窗改完当场调用）。
    public func persist() {
        defaults.set(sourceFolder, forKey: Key.sourceFolderPath)
        defaults.set(rate, forKey: Key.rate)
        defaults.set(volume, forKey: Key.volume)
        defaults.set(isMuted, forKey: Key.muted)
        defaults.set(playMode.rawValue, forKey: Key.playMode)
        defaults.set(rotationInterval, forKey: Key.rotationInterval)
        defaults.set(pauseOnBattery, forKey: Key.pauseOnBattery)
        defaults.set(launchAtLogin, forKey: Key.launchAtLogin)
    }
}
