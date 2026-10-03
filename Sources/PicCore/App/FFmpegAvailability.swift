import Foundation

/// ffmpeg 可用性判定（Phase 5 的状态卡消费面）—— **零执行**，从不构造 ffmpeg 的 `Process`。
///
/// 🔴 D-17 收编（06-04 T2）：原先这里是**一套自己的 PATH 目录扫描**，与 06-02 的
/// `ExternalToolLocator` 并存。菜单栏 app 从 Finder/DMG 启动时继承的是 launchd 的
/// 最小 PATH（不含 `/opt/homebrew/bin`），于是同一个 app 里「明明装了 ffmpeg」
/// 在设置窗报「未安装」、转码窗报「已就绪」—— 两套真相。判定现已全部在 locator，
/// 本类型只剩**状态卡的消费面**：判定投影 + 文案。
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

    /// 状态卡副标签。两个值穷举 —— 不掺版本串。
    /// 文案是 Phase 5 的承诺，改它要同步改 `PIC_FFMPEG available=<0|1> label=…`
    /// 证据行的口径。
    public static func label(available: Bool) -> String {
        return available ? "可用" : "未安装"
    }
}