import Foundation

/// 产物路径推导与幂等跳过（TRANS-04）—— 纯推导，本类型不写盘（`Converted/` 目录的创建是队列的预检）。
public struct TranscodeOutputNaming {

    /// 壁纸目录。**取成闭包而不是值**：用户可以在不重启 app 的情况下换目录，
    /// 构造时固化会让产物继续写进已经不再使用的旧目录（场景 H4 / F10）。
    private let rootProvider: () -> URL

    public init(rootProvider: @escaping () -> URL) {
        self.rootProvider = rootProvider
    }

    /// 固定目录的便捷构造（目录在整个生命周期内不变的调用方）。
    public init(root: URL) {
        self.rootProvider = { root }
    }

    /// 当前壁纸目录。
    public var root: URL { rootProvider() }

    /// 产物目录名 —— 必须引用 `MediaLibrary` 的同一常量（同模块无循环）：两个名字漂移的那天就是回流闸门失效的那天。
    public static let convertedDirectoryName = MediaLibrary.excludedDirectoryName

    /// `root/Converted`。创建目录的动作留给队列。
    public func convertedDirectoryURL() -> URL {
        rootProvider().appendingPathComponent(Self.convertedDirectoryName, isDirectory: true)
    }

    /// `root/Converted/<源文件去扩展名>.mp4` —— 不加任何后缀：目录隔离 + MP4 原生双闸门已够，后缀只换来难看的文件名。
    /// 源文件保留不删（是否删源由 `TranscodeJob.deletesSource` 决定）。
    public func outputURL(for source: URL) -> URL {
        let stem = source.deletingPathExtension().lastPathComponent
        return convertedDirectoryURL().appendingPathComponent(stem + ".mp4")
    }

    /// 中间态：`outputURL` 加 `.tmp` 后缀（先写 tmp 再 rename；`.tmp` 扩展名天然进不了任何白名单）。
    public func temporaryURL(for source: URL) -> URL {
        outputURL(for: source).appendingPathExtension("tmp")
    }

    /// 幂等跳过：产物已存在且产物 mtime ≥ 源 mtime → true（已转过且源没变，跳过防重复烤机）。产物不存在或更旧 → false。
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
