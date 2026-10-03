import Foundation

/// 「该不该弹文件夹选择框」的决策层。与 `LibraryAvailability` 同形：**只吃标量**的纯函数
/// —— 不读 `ProcessInfo`、不读 `UserDefaults`，环境变量那一级（`PIC_SOURCE_FOLDER`）由调用方
/// （AppDelegate）取出来传进来。决策函数一旦自己去读全局状态，就再也不能被穷举测试。
public enum FolderRequestPolicy {

    /// 没配置过目录（空串或纯空白）且没有环境变量覆盖 → 该弹框。
    /// - 环境变量覆盖非空非空白，或 `sourceFolder` 去除首尾空白后非空 → false。
    /// - 空白视同未配置 —— 否则一个纯空格的偏好值会让产品永远不再弹框，用户被永久卡死
    ///   （这条不会报错，只会静默失效）。
    public static func shouldRequestFolder(sourceFolder: String, envOverride: String?) -> Bool {
        if let envOverride, !envOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        return sourceFolder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 归一化路径：解析符号链接 + 标准化后取 `path`。
    /// 绝不返回 URL 的字符串形式（D-09 / Pitfall 5）—— 那会把中文与空格
    /// 百分号编码，存在性检查拿到它恒为 false。
    public static func normalizedPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// 选择合法性：非 nil、存在、且是目录，三者都真才 true。
    /// 存在性检查走 `url.path`（D-09 / Pitfall 5）。挡的是「面板被绕过」或「用户选了个文件」。
    public static func isAcceptableSelection(_ url: URL?) -> Bool {
        guard let url else { return false }
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }
}
