import Foundation

/// 设置窗 ffmpeg 行的可用性判定（Phase 5 / TRANS-02 的前半边）。
///
/// ⚠️ **零执行**：只看 PATH 目录里有没有一个名为 ffmpeg 的**可执行文件**，
/// 从不构造 `Process`、从不跑它。本机没有 timeout 机制，ffmpeg 类调用绝不进
/// 自动路径（主会话硬约束）。
///
/// 版本串（`9.0.2 · 可用`）属 Phase 6 真正与 ffmpeg 交互时才拿得到，
/// 本 Phase 状态卡只报可用性（UI-SPEC §12）。
public enum FFmpegAvailability {

    /// PATH 目录列表 → 是否可用。目录逐个拼接判定，任一命中即 true。
    public static func resolve(searchPaths: [String],
                               fileManager: FileManager = .default) -> Bool {
        searchPaths.contains { dir in
            // 空目录项（PATH 里的 `::`、环境缺失）拼接出的路径会落到当前目录，
            // 那会让「没装」误报成「装了 ./ffmpeg」。
            !dir.isEmpty
                && fileManager.isExecutableFile(
                    atPath: URL(fileURLWithPath: dir).appendingPathComponent("ffmpeg").path)
        }
    }

    /// 生产入口：拆 `PATH` 再走 `resolve`。PATH 缺失/为空 → false。
    public static func resolveFromPATH(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        resolve(searchPaths: (environment["PATH"] ?? "").split(separator: ":").map(String.init))
    }

    /// 状态卡副标签。两个值穷举 —— 不掺版本串。
    public static func label(available: Bool) -> String {
        return available ? "可用" : "未安装"
    }
}
