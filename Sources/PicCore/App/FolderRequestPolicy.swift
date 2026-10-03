import Foundation

/// 「该不该弹文件夹选择框」的决策层（Plan 04-04 T2 / SYS-03 / SOURCE-07）。
///
/// 与 04-03 的 `LibraryAvailability` 同形：**只吃标量**的纯函数 ——
/// `shouldRequestFolder` 不读 `ProcessInfo`、不读 `UserDefaults`，环境变量那一级
/// （`PIC_SOURCE_FOLDER`）由调用方（AppDelegate）取出来传进来。决策函数一旦
/// 自己去读全局状态，就再也不能被穷举测试。
public enum FolderRequestPolicy {

    /// 没配置过目录（空串或纯空白）且没有环境变量覆盖 → 该弹框（SYS-03）。
    /// RED 骨架：恒 false，真实判定在 GREEN 落地。
    public static func shouldRequestFolder(sourceFolder: String, envOverride: String?) -> Bool {
        false
    }

    /// 归一化路径。返回 `path`，绝不返回 URL 的字符串形式（D-09 / Pitfall 5）。
    public static func normalizedPath(_ url: URL) -> String {
        ""
    }

    /// 选择合法性：非 nil、存在、且是目录，三者都真才 true。
    /// RED 骨架：恒 true，真实判定在 GREEN 落地。
    public static func isAcceptableSelection(_ url: URL?) -> Bool {
        true
    }
}
