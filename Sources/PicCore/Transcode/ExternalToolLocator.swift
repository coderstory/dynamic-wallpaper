import Foundation

/// ffmpeg 检测结论（TRANS-01）。
///
/// 命名是 `FFmpegToolStatus` 而非 `FFmpegAvailability`：Phase 5（05-03）已在同
/// target 的 `Sources/PicCore/App/FFmpegAvailability.swift` 声明同名类型，再用
/// `FFmpegAvailability` 即撞型编译错（checker B1）。Phase 5 的 PATH-only 判定由
/// 06-04 T2 收编为本 locator 的薄委托（D-17）。
public enum FFmpegToolStatus: Equatable {
    case available(path: String)
    case unavailable
}

/// which 探测 seam：status 是 `Process.terminationStatus` 语义，path 是 stdout
/// 去空白（空串按 nil）。逻辑层全部注入假件，生产实现只有 `ProcessWhichProbe`。
public protocol WhichProbing: Sendable {
    func whichFFmpeg() -> (status: Int32, path: String?)
}

/// 文件系统可执行性 seam：存在 + 执行位一次到位。检测层零 `FileManager`
/// 直接调用 —— 否则决策表没法注入。
public protocol ExecutableFileProbing: Sendable {
    func isExecutableFile(atPath path: String) -> Bool
}

/// 外部工具定位器：显式路径探测在前、`which` 兜底（RESEARCH Q7 / P1 ——
/// GUI app 拿到的是 launchd 最小 PATH，不含 `/opt/homebrew/bin`，纯 which
/// 检测在本机必误报「未安装」）。
public struct ExternalToolLocator {

    /// 显式探测路径表：**逐字**，顺序即探测顺序（显式在前）。
    public static let probePaths: [String] = [
        "/opt/homebrew/bin/ffmpeg",
        "/usr/local/bin/ffmpeg",
    ]

    private let which: any WhichProbing
    private let fileSystem: any ExecutableFileProbing

    public init(which: any WhichProbing, fileSystem: any ExecutableFileProbing) {
        self.which = which
        self.fileSystem = fileSystem
    }

    /// 三态决策表（TEST-05）：显式路径存在且可执行 → available(该路径)；
    /// 「存在但不可执行」被**跳过而不是判死**（继续查其余途径）；
    /// `which` 退出码 0 → available(which 给的路径)；两者皆无 → unavailable。
    public func locate() -> FFmpegToolStatus {
        for path in Self.probePaths {
            if fileSystem.isExecutableFile(atPath: path) { return .available(path: path) }
        }
        let whichResult = which.whichFFmpeg()
        if whichResult.status == 0, let path = whichResult.path {
            return .available(path: path)
        }
        return .unavailable
    }
}

/// 生产 which 探测件：检测层唯一允许碰 `Process` 的地方。
/// 退出判定只看 `terminationStatus`（C10：绝不用管道拿退出码；读 stdout
/// 管道拿路径不违规 —— C10 禁的是「用管道的退出码」）。
public struct ProcessWhichProbe: WhichProbing {

    public init() {}

    public func whichFFmpeg() -> (status: Int32, path: String?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["ffmpeg"]
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
        } catch {
            return (1, nil)
        }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (process.terminationStatus, output.isEmpty ? nil : output)
    }
}

/// 生产文件系统探测件：`FileManager` 的存在 + 执行位检查。
public struct FileManagerExecutableProbe: ExecutableFileProbing {

    public init() {}

    public func isExecutableFile(atPath path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }
}
