import Foundation

/// 产物路径推导与幂等跳过（TRANS-04）—— 纯推导，本类型不写盘
/// （`Converted/` 目录的创建是 06-03 队列的预检）。
public struct TranscodeOutputNaming {

    /// root = 壁纸目录（`SettingsStore.resolvedFolderURL()` 的产物）。
    /// 不校验它存在 —— 转码时目录必然存在，校验是队列的预检。
    private let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// 产物目录名 —— 引用 `MediaLibrary` 的同一常量（同模块无循环）：
    /// 两个名字漂移的那天就是回流闸门失效的那天（D-21）。
    public static let convertedDirectoryName = MediaLibrary.excludedDirectoryName

    /// `root/Converted`。创建目录的动作留给队列（06-03）。
    public func convertedDirectoryURL() -> URL {
        root.appendingPathComponent(Self.convertedDirectoryName, isDirectory: true)
    }

    /// `root/Converted/<源文件去扩展名>.mp4`（RESEARCH Q4：不加任何后缀 ——
    /// 目录隔离 + MP4 原生双闸门已够，后缀只换来难看的文件名）。
    /// 源文件保留不删（TRANS-04）。
    public func outputURL(for source: URL) -> URL {
        let stem = source.deletingPathExtension().lastPathComponent
        return convertedDirectoryURL().appendingPathComponent(stem + ".mp4")
    }

    /// 中间态：`outputURL` 加 `.tmp` 后缀（C11：先写 tmp 再 rename；
    /// `.tmp` 扩展名天然进不了任何白名单）。
    public func temporaryURL(for source: URL) -> URL {
        outputURL(for: source).appendingPathExtension("tmp")
    }

    /// 幂等跳过：产物已存在且产物 mtime ≥ 源 mtime → true（已转过且源没变，
    /// 跳过防重复烤机）。产物不存在或更旧 → false。
    /// 任何读取失败按 false 处理 —— 宁可重转，不可误跳。
    public func skipDecision(source: URL) -> Bool {
        let fm = FileManager.default
        let productPath = outputURL(for: source).path
        guard fm.fileExists(atPath: productPath) else { return false }
        guard let productDate = (try? fm.attributesOfItem(atPath: productPath))?[.modificationDate] as? Date,
              let sourceDate = (try? fm.attributesOfItem(atPath: source.path))?[.modificationDate] as? Date else {
            return false
        }
        return productDate >= sourceDate
    }
}
