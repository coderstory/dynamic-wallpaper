import Foundation

/// 「该不该弹文件夹选择框」的决策层。只吃标量的纯函数 —— 环境变量（`PIC_SOURCE_FOLDER`）
/// 由调用方取出来传进来；决策函数一旦自己读全局状态，就再也不能被穷举测试。
public enum FolderRequestPolicy {

    /// - Parameters:
    ///   - sourceFolder: 已配置的目录路径，空串或纯空白都算未配置。
    ///   - envOverride: `PIC_SOURCE_FOLDER` 的值，非空非空白即视为已配置。
    /// - Returns: 该弹框时返回 true。空白视同未配置 —— 一个纯空格的偏好值会让产品永远
    ///   不再弹框，用户被永久卡死，且不会报错。
    public static func shouldRequestFolder(sourceFolder: String, envOverride: String?) -> Bool {
        if let envOverride, !envOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        return sourceFolder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 归一化路径：解析符号链接 + 标准化后取 `path`。绝不返回 URL 的字符串形式 ——
    /// 那会把中文与空格百分号编码，存在性检查拿到它恒为 false。
    public static func normalizedPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// 选择合法性：非 nil、存在、且是目录。存在性检查走 `url.path`，同上。
    public static func isAcceptableSelection(_ url: URL?) -> Bool {
        guard let url else { return false }
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }
}
