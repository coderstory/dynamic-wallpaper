import Foundation

/// ffmpeg 可用性判定（状态卡消费面）—— **零执行**，从不构造 ffmpeg 的 `Process`。
///
/// 🔴 原先是**一套自己的 PATH 目录扫描**，与 `ExternalToolLocator` 并存：菜单栏 app 从
/// Finder/DMG 启动继承 launchd 最小 PATH（无 `/opt/homebrew/bin`），于是同一个 app 里
/// 「明明装了 ffmpeg」设置窗报「未安装」、转码窗报「已就绪」。判定现已全部在 locator。
public enum FFmpegAvailability {

    /// 判定投影：locator 的结论 → 状态卡的 `available` 参数。一行映射，不判第二次。
    public static func available(_ status: FFmpegToolStatus) -> Bool {
        if case .available = status { return true }
        return false
    }

    /// 生产件 —— 判定层唯一的生产构造点。测试传假件（`WhichProbing` / `ExecutableFileProbing`）。
    public static func productionLocator() -> ExternalToolLocator {
        ExternalToolLocator(which: ProcessWhichProbe(), fileSystem: FileManagerExecutableProbe())
    }

    /// 状态卡副标签。两个值穷举 —— 不掺版本串。改文案要同步改
    /// `PIC_FFMPEG available=<0|1> label=…` 证据行的口径。
    public static func label(available: Bool) -> String {
        return available ? "可用" : "未安装"
    }
}