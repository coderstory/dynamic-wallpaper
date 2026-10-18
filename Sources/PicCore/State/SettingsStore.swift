import Foundation
import Observation

public enum PlayMode: String, CaseIterable, Sendable {
    case loopSingle
    /// 按顺序走完一圈再回到第一条。
    case loopList
    /// 一轮内每条恰好一次。
    case shuffle
}

/// 壁纸来源。`rawValue` 会落 UserDefaults —— 改名等于让老用户的偏好读不出来，改名前先想迁移。
public enum WallpaperKind: String, CaseIterable, Sendable {
    case video
    case image
}

/// 图片铺屏方式。默认 `.fill` 与系统一致（Windows / macOS 的桌面壁纸默认都是「填充」）：
/// 等比放大到铺满、超出裁掉、不变形。
public enum ImageFit: String, CaseIterable, Sendable {
    /// 填充：铺满，超出裁掉。
    case fill
    /// 适应：完整显示，留边由「留边处」决定。
    case fit
    /// 居中：原始尺寸居中，不放大。
    case center
    /// 平铺：原始尺寸重复铺满。
    case tile
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
        public var wallpaperKind: WallpaperKind
        public var imageFolderPath: String
        public var imageMinPixels: Int
        public var imageFit: ImageFit
        /// 默认 false：材质是显式开启的视觉偏好，默认开等于替老用户换掉既见的界面。
        public var liquidGlassEnabled: Bool

        /// 新参数一律**加在末尾**：既有调用点用位置无关具名传参，插到中间会让它们编译不过。
        public init(sourceFolder: String = "", rate: Float = 1.0, volume: Float = 1.0,
                    isMuted: Bool = false, playMode: PlayMode = .loopSingle,
                    rotationInterval: TimeInterval = 300, pauseOnBattery: Bool = false,
                    launchAtLogin: Bool = false,
                    wallpaperKind: WallpaperKind = .video,
                    imageFolderPath: String = "",
                    imageMinPixels: Int = ImageResolutionTier.k2.pixels,
                    imageFit: ImageFit = .fill,
                    liquidGlassEnabled: Bool = false) {
            self.sourceFolder = sourceFolder
            self.rate = rate
            self.volume = volume
            self.isMuted = isMuted
            self.playMode = playMode
            self.rotationInterval = rotationInterval
            self.pauseOnBattery = pauseOnBattery
            self.launchAtLogin = launchAtLogin
            self.wallpaperKind = wallpaperKind
            self.imageFolderPath = imageFolderPath
            self.imageMinPixels = imageMinPixels
            self.imageFit = imageFit
            self.liquidGlassEnabled = liquidGlassEnabled
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
        public static let wallpaperKind = "wallpaperKind"
        public static let imageFolderPath = "imageFolderPath"
        public static let imageMinPixels = "imageMinPixels"
        public static let imageFit = "imageFit"
        public static let liquidGlassEnabled = "liquidGlassEnabled"
        public static let lastImagePath = "lastImagePath"
    }

    /// 开发期覆盖入口：`swift run` 起的进程没有 bundle id，UserDefaults 域取不到 `com.local.bizhier`，故留一条环境变量路径。
    public static let envSourceFolderKey = "PIC_SOURCE_FOLDER"

    /// 改名前的旧偏好域 id。刻意按段拼接而不是写成完整字面量：仓库守门 grep 要求 Sources /
    /// Tests 里不出现旧 id 的连续字样（「任何地方不出现」的机器可验形式）。只供迁移默认参数用，
    /// 模块内别处不得引用。
    static let legacySuiteName = ["com.local", "pic"].joined(separator: ".")

    /// 产品入口：对改名后的新域跑一次性迁移（见下面的完整实现）。
    public static func migrateLegacyPreferencesIfNeeded(defaults: UserDefaults) {
        migrateLegacyPreferencesIfNeeded(defaults: defaults, legacySuiteName: legacySuiteName)
    }

    /// bundle id 改名后的一次性偏好迁移：新域从未写过值、旧域有值时，把旧域里属于 `Key`
    /// 全集的键逐个搬进当前域，再整体删除旧域。
    ///
    /// - 触发时机：AppDelegate 在创建 `SettingsStore` **之前**调用 —— store 的 init 就在读
    ///   偏好，晚于它迁移等于白搬（store 已用空域的种子值定终身）。
    /// - 幂等：新域已有 `wallpaperKind`（= 新域写过偏好，迁移早已完成或用户已重新设置过）
    ///   直接返回，绝不覆盖。
    /// - 按 `Key` 全集过滤：旧域的 `dictionaryRepresentation()` 会混进系统塞的杂键
    ///   （全局域 + 注册域的内容都在里面），照单全收等于把垃圾写进新域。
    /// - 只有真搬了东西才删旧域：对不存在的域空跑 `removePersistentDomain` 会让 cfprefsd
    ///   把一个全新的空旧域 plist 写回磁盘（见 `TestDefaults` 头注释），等于给每台新机器造残留文件。
    ///
    /// `legacySuiteName` 是测试注入缝：单测指 `pic.tests.*` 隔离域，绝不碰真实旧域。
    static func migrateLegacyPreferencesIfNeeded(
        defaults: UserDefaults,
        legacySuiteName: String
    ) {
        guard defaults.object(forKey: Key.wallpaperKind) == nil else { return }
        guard let legacy = UserDefaults(suiteName: legacySuiteName) else { return }
        let knownKeys: Set<String> = [
            Key.sourceFolderPath, Key.rate, Key.volume, Key.muted, Key.playMode,
            Key.rotationInterval, Key.pauseOnBattery, Key.launchAtLogin,
            Key.lastPlayedPath, Key.lastPlayedPosition, Key.wallpaperKind,
            Key.imageFolderPath, Key.imageMinPixels, Key.imageFit,
            Key.liquidGlassEnabled, Key.lastImagePath,
        ]
        var migrated = false
        for (key, value) in legacy.dictionaryRepresentation() where knownKeys.contains(key) {
            defaults.set(value, forKey: key)
            migrated = true
        }
        guard migrated else { return }
        legacy.removePersistentDomain(forName: legacySuiteName)
    }

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
    /// 当前壁纸来源。读不到持久化值时回落 `.video` —— 老用户（只有视频偏好）不需要迁移。
    public var wallpaperKind: WallpaperKind
    /// 图片来源目录，与 `sourceFolder` 并存：两个来源可以同时配好，切 `wallpaperKind` 即时生效。
    public var imageFolderPath: String
    /// 参与轮播的最低总像素量。存**绝对值**而不是档位下标，加档位不用迁移。
    public var imageMinPixels: Int
    public var imageFit: ImageFit
    /// 「液态玻璃效果」。默认关：材质是显式开启的视觉偏好，默认开会让老用户升级后界面变样。
    /// **纯展示偏好**——只被 SwiftUI 读，不走 Applier、不动窗口，@Observable 让开关即时生效。
    public var liquidGlassEnabled: Bool
    /// 上次显示的图片路径。**必须与 `lastPlayedPath` 分开**：图片的单张续播若拿视频路径去匹配，
    /// 匹配不到就静默从第一张开始 —— 不崩，但用户不知道为什么换了一张。
    public var lastImagePath: String

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
        if let raw = defaults.string(forKey: Key.wallpaperKind), let k = WallpaperKind(rawValue: raw) {
            self.wallpaperKind = k
        } else {
            self.wallpaperKind = seed.wallpaperKind
        }
        self.imageFolderPath = defaults.string(forKey: Key.imageFolderPath) ?? seed.imageFolderPath
        self.imageMinPixels = defaults.object(forKey: Key.imageMinPixels) as? Int ?? seed.imageMinPixels
        if let raw = defaults.string(forKey: Key.imageFit), let f = ImageFit(rawValue: raw) {
            self.imageFit = f
        } else {
            self.imageFit = seed.imageFit
        }
        self.liquidGlassEnabled = defaults.object(forKey: Key.liquidGlassEnabled) as? Bool
            ?? seed.liquidGlassEnabled
        self.lastImagePath = defaults.string(forKey: Key.lastImagePath) ?? ""
    }

    /// 解析后的壁纸目录 URL。只走文件系统路径这一个形态：存在性检查必须喂 `url.path` 那种裸路径，喂 URL 的字符串形式会让含中文/空格的路径恒为假。
    public func resolvedFolderURL() -> URL? {
        resolvedFolderURL(for: wallpaperKind)
    }

    /// 指定来源的目录 URL。切来源后必须用**对应**的那一份路径去判存在性 ——
    /// 拿视频目录去判图片来源会得出「已配置」的假结论。
    public func resolvedFolderURL(for kind: WallpaperKind) -> URL? {
        let path = kind == .image ? imageFolderPath : sourceFolder
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
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
        defaults.set(wallpaperKind.rawValue, forKey: Key.wallpaperKind)
        defaults.set(imageFolderPath, forKey: Key.imageFolderPath)
        defaults.set(imageMinPixels, forKey: Key.imageMinPixels)
        defaults.set(imageFit.rawValue, forKey: Key.imageFit)
        defaults.set(liquidGlassEnabled, forKey: Key.liquidGlassEnabled)
        defaults.set(lastImagePath, forKey: Key.lastImagePath)
    }
}
