// 开机自启的「先 A 后 B」决策内核。
// A（SMAppService）在未签名 app 上真实行为无可靠公开资料，故 A 抛错或未注册即自动落 B，
// 并把 A 的失败形态逐字打出来可 grep。绝不出现已废弃的 launchd load/unload 子命令。

import Foundation
import ServiceManagement

/// 路线 A 的注入面。包一层是为了让单测在不碰真实登录项的前提下驱动全部四个分支。
public protocol LoginItemRegistration: Sendable {
    /// 注册为登录项。失败形态由调用方逐字记录。
    func register() throws
    /// 注销登录项。best-effort：失败也要继续清路线 B。
    func unregister() throws
    /// 注册后的实际状态（判据，不看 `register()` 是否抛错）。
    var status: SMAppService.Status { get }
    /// 引导用户在「登录项与扩展」里手动批准。
    func openSettings()
}

/// 路线 A 的产品实现。不持有 `SMAppService`，每次现读静态单例 ——
/// 免得把一个非 Sendable 的系统类型拖进 `Sendable` 协议的实现里。
public struct SMAppServiceAdapter: LoginItemRegistration {
    public init() {}

    public func register() throws {
        try SMAppService.mainApp.register()
    }

    public func unregister() throws {
        try SMAppService.mainApp.unregister()
    }

    public var status: SMAppService.Status { SMAppService.mainApp.status }

    public func openSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

/// 路线 B 的进程执行面。抽出来是为了单测能断言命令与顺序，而不是真去动用户会话的 launchd 域。
public protocol ShellRunner {
    /// 返回终止状态（调用方按需忽略，见 `routeB()`）。
    func run(_ path: String, _ arguments: [String]) -> Int32
}

/// `ShellRunner` 的产品实现：起进程、等退出、返回退出码。
public struct ProcessShellRunner: ShellRunner {
    public init() {}

    public func run(_ path: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        do {
            try process.run()
        } catch {
            return -1
        }
        process.waitUntilExit()
        return process.terminationStatus
    }
}

/// 开机自启的唯一写入口：`setEnabled(true)` 先试路线 A，注册成功但待批准就留在 A 并弹
/// 系统设置，其余情况自动落路线 B；`setEnabled(false)` 两条路线都清。
@MainActor
public final class AutoStartManager {
    private let registration: LoginItemRegistration
    private let writer: LaunchAgentWriter
    private let runner: ShellRunner
    /// 路线 B 写进 plist 的可执行路径。app 移动后由 `routeB()` 的
    /// 「bootout → 重写 → bootstrap」顺序天然修正，无需单独分支。
    private let executablePath: String
    private let emit: (String) -> Void

    public init(registration: LoginItemRegistration = SMAppServiceAdapter(),
                writer: LaunchAgentWriter = LaunchAgentWriter(),
                runner: ShellRunner = ProcessShellRunner(),
                executablePath: String = Bundle.main.executablePath ?? "",
                emit: @escaping (String) -> Void = { _ in }) {
        self.registration = registration
        self.writer = writer
        self.runner = runner
        self.executablePath = executablePath
        self.emit = emit
    }

    /// 用户拨动开关。启动时也直接调它：偏好为 false 时清两路是幂等的。
    public func setEnabled(_ enabled: Bool) {
        if enabled {
            ensureRegistered()
        } else {
            disableBoth()
        }
    }

    private func ensureRegistered() {
        do {
            try registration.register()
        } catch {
            emit("SYS01_ROUTE_A_FAILED error=\(error)")
            routeB()
            return
        }
        switch registration.status {
        case .enabled:
            emit("SMAPP_STATUS=\(Self.statusToken(registration.status))")
            emit("SYS01_ROUTE=smappservice")
        case .requiresApproval:
            // 注册已成功，缺的只是用户点一次批准 —— 落 B 会变成两套注册并存。
            emit("SMAPP_STATUS=\(Self.statusToken(registration.status))")
            emit("SYS01_REQUIRES_APPROVAL=1")
            registration.openSettings()
            emit("SYS01_ROUTE=smappservice")
        default:
            emit("SMAPP_STATUS=\(Self.statusToken(registration.status))")
            routeB()
        }
    }

    /// 路线 B：bootout → 写盘 → bootstrap。
    /// 不 throwing：两个调用点都在 catch 块 / 兜底分支里，让它 throwing 会把整条
    /// `ensureRegistered()` 拖成 throwing，写盘因而走 `try?`。
    ///
    /// bootout 的 rc 一律忽略 —— plist 可能压根不存在（首次开启），
    /// 也可能指向已被移动的旧路径（两种都要能被 bootstrap 覆盖掉）。
    private func routeB() {
        let domain = "gui/\(getuid())"
        let path = writer.plistURL().path
        runner.run("/bin/launchctl", ["bootout", domain, path])
        try? writer.write(executablePath: executablePath)
        runner.run("/bin/launchctl", ["bootstrap", domain, path])
        emit("SYS01_ROUTE=launchagent")
    }

    ///  关：两条路线都清。路线 A 的注销失败也必须继续清 B， 否则系统里会留下一条用户已经关掉的登录项。
    private func disableBoth() {
        do {
            try registration.unregister()
        } catch {
            emit("SYS01_UNREGISTER_FAILED error=\(error)")
        }
        runner.run("/bin/launchctl", ["bootout", "gui/\(getuid())", writer.plistURL().path])
        writer.remove()
        emit("SYS01_DISABLED=1")
    }

    /// 状态行只打状态 token，不打路径、不打文件名（状态一行、路由另一行）。
    ///
    ///  必须显式映射：`String(describing:)` 给的是 `SMAppServiceStatus(rawValue: 1)` 而不是 case 名。
    private static func statusToken(_ status: SMAppService.Status) -> String {
        switch status {
        case .notRegistered: return "notRegistered"
        case .enabled: return "enabled"
        case .requiresApproval: return "requiresApproval"
        case .notFound: return "notFound"
        @unknown default: return "unknown"
        }
    }
}