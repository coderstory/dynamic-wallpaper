import Foundation

/// ffmpeg 判定层的**生产构造点** —— 零执行，从不构造 ffmpeg 的 `Process`。
/// 判定只走 `ExternalToolLocator`：菜单栏 app 从 Finder/DMG 启动继承 launchd 最小 PATH
/// （无 `/opt/homebrew/bin`），自己扫 PATH 会让同一个 app 里两处结论打架。
public enum FFmpegAvailability {

    /// 生产件 —— 判定层唯一的生产构造点。测试传假件（`WhichProbing` / `ExecutableFileProbing`）。
    public static func productionLocator() -> ExternalToolLocator {
        ExternalToolLocator(which: ProcessWhichProbe(), fileSystem: FileManagerExecutableProbe())
    }
}