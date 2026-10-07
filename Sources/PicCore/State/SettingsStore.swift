import Foundation
import Observation

public enum PlayMode: String, CaseIterable, Sendable {
    case loopSingle
    /// 按顺序走完一圈再回到第一条。
    case loopList
    /// 一轮内每条恰好一次。
    case shuffle
}

/// 用户设置的单一真相源 —— 别处不得再存第二份。不含业务逻辑、不碰 AVFoundation，只做持久化与解析。
@MainActor
@Observable
public final class SettingsStore {
    /// 首次启动（尚无任何持久化值）时使用的种子。
    public struct Seed: Sendable {
        public var sourceFolder: String
        public var rate: Float
        public var volume: Float
        public var isMuted: Bool
        public var playMode: PlayMode
        public var rotationInterval: TimeInterval
        /// 默认 false：默认开会让用户一拿电池本就无故失去壁纸，看起来像 app 坏了。
        public var pauseOnBattery: Bool
        /// 默认 false：自启是用户显式打开的东西，默认开等于替用户往开机项里塞一个登录项。
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

    /// UserDefaults 键名。
    public enum Key {
        public static let sourceFolderPath = "sourceFolderPath"
        public static let rate = "rate"
        public static let volume = "volume"
        public static let muted = "muted"
        public static let playMode = "playMode"
        public static let rotationInterval = "rotationInterval"
        public static let pauseOnBattery = "pauseOnBattery"
        public static let launchAtLogin = "launchAtLogin"
        public static let lastPlayedPath = "lastPlayedPath"
        public static let lastPlayedPosition = "lastPlayedPosition"
    }

    /// 开发期覆盖入口：`swift run` 起的进程没有 bundle id，UserDefaults 域取不到 `com.local.pic`，故留一条环境变量路径。
    public static let envSourceFolderKey = "PIC_SOURCE_FOLDER"

    public var sourceFolder: String
    public var rate: Float
    public var volume: Float
    public var isMuted: Bool
    public var playMode: PlayMode
    public var rotationInterval: TimeInterval
    /// 「电池供电时暂停」。**没有环境变量这一级** —— 电源开关不是开发期覆盖项。
    public var pauseOnBattery: Bool
    /// 「开机自启」。**没有环境变量这一级** —— 它是真持久化偏好，系统侧状态由 `AutoStartManager` 对齐。
    public var launchAtLogin: Bool
    /// 上次播放的文件路径 —— 单循环续播的读点。**运行时状态不是用户偏好**，但持久化
    /// 机制共用 UserDefaults 这一个落点，不另起第二个存储。
    public var lastPlayedPath: String
    /// 上次播放的视频内进度（秒）。每次装载归零，让路 / 退出时写真值。
    public var lastPlayedPosition: TimeInterval

    private let defaults: UserDefaults

    public init(defaults: UserDefaults, seed: SettingsStore.Seed) {
        self.defaults = defaults

        // 三级优先：环境变量 > UserDefaults > 传入的 seed。
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
        self.lastPlayedPath = defaults.string(forKey: Key.lastPlayedPath) ?? ""
        self.lastPlayedPosition = defaults.object(forKey: Key.lastPlayedPosition) as? Double ?? 0
    }

    /// 解析后的壁纸目录 URL。只走文件系统路径这一个形态：存在性检查必须喂 `url.path` 那种裸路径，喂 URL 的字符串形式会让含中文/空格的路径恒为假。
    public func resolvedFolderURL() -> URL? {
        guard !sourceFolder.isEmpty else { return nil }
        return URL(fileURLWithPath: sourceFolder)
    }

    public func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// 把内存值写回 UserDefaults（设置窗改完当场调用）。
    public func persist() {
        defaults.set(sourceFolder, forKey: Key.sourceFolderPath)
        defaults.set(rate, forKey: Key.rate)
        defaults.set(volume, forKey: Key.volume)
        defaults.set(isMuted, forKey: Key.muted)
        defaults.set(playMode.rawValue, forKey: Key.playMode)
        defaults.set(rotationInterval, forKey: Key.rotationInterval)
        defaults.set(pauseOnBattery, forKey: Key.pauseOnBattery)
        defaults.set(launchAtLogin, forKey: Key.launchAtLogin)
        defaults.set(lastPlayedPath, forKey: Key.lastPlayedPath)
        defaults.set(lastPlayedPosition, forKey: Key.lastPlayedPosition)
    }
}
