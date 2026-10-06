import Foundation

/// ffmpeg 可用性判定（状态卡消费面）—— 零执行，从不构造 ffmpeg 的 `Process`。
/// 判定只走 `ExternalToolLocator`：菜单栏 app 从 Finder/DMG 启动继承 launchd 最小 PATH
/// （无 `/opt/homebrew/bin`），自己扫 PATH 会让同一个 app 里两处结论打架。
public enum FFmpegAvailability {

    /// 判定投影：locator 的结论 → 状态卡的 `available` 参数。不判第二次。
    public static func available(_ status: FFmpegToolStatus) -> Bool {
        status.isAvailable
    }

    /// 生产件 —— 判定层唯一的生产构造点。测试传假件（`WhichProbing` / `ExecutableFileProbing`）。
    public static func productionLocator() -> ExternalToolLocator {
        ExternalToolLocator(which: ProcessWhichProbe(), fileSystem: FileManagerExecutableProbe())
    }

    /// 状态卡副标签。两个值穷举 —— 不掺版本串。
    public static func label(available: Bool) -> String {
        return available ? "可用" : "未安装"
    }
}