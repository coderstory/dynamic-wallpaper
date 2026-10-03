import Foundation
import ServiceManagement
import XCTest
@testable import PicCore

/// 开机自启双路线决策内核的 7 条行为用例。
///
/// ⚠️ 本文件**不碰**真实系统状态：不调 `SMAppService.register()`、不 spawn `launchctl`、
/// 不写 `~/Library/LaunchAgents`。路线 B 落在每个用例各自的临时目录里。
///
/// ⚠️ 路线 B 没有 mock writer —— `LaunchAgentWriter` 是 `final class`，故用**真 writer
/// 指向临时目录**，断言读回落盘的 plist 而不是「mock 记下了一次调用」：
/// 文件在不在、内容对不对，比调用记录更难自欺。
@MainActor
final class AutoStartTests: XCTestCase {

    // MARK: - Fake 三件套

    /// 路线 A 的可编程替身。
    private final class FakeRegistration: LoginItemRegistration, @unchecked Sendable {
        var registerError: Error?
        var unregisterError: Error?
        var stubbedStatus: SMAppService.Status = .enabled

        private(set) var registerCount = 0
        private(set) var unregisterCount = 0
        private(set) var openSettingsCount = 0

        func register() throws {
            registerCount += 1
            if let registerError { throw registerError }
        }

        func unregister() throws {
            unregisterCount += 1
            if let unregisterError { throw unregisterError }
        }

        var status: SMAppService.Status { stubbedStatus }

        func openSettings() { openSettingsCount += 1 }
    }

    /// 一条被测过的失败形态：`register()` 抛出来的错误带着 domain 与 code，
    /// `SYS01_ROUTE_A_FAILED error=…` 那行要能逐字把它带出去。
    private struct FakeRegisterError: LocalizedError, CustomStringConvertible {
        let description = "fake registration failure"
    }

    /// 路线 B 的命令记录器。
    private final class FakeRunner: ShellRunner {
        private(set) var calls: [(path: String, arguments: [String])] = []

        func run(_ path: String, _ arguments: [String]) -> Int32 {
            calls.append((path, arguments))
            return 0
        }

        var subcommands: [String] { calls.map { $0.arguments.first ?? "" } }
    }

    // MARK: - 夹具

    private var root: URL!
    private var writer: LaunchAgentWriter!

    override func setUp() async throws {
        try await super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pic-autostart-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        writer = LaunchAgentWriter(directory: root)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
        root = nil
        writer = nil
        try await super.tearDown()
    }

    private func makeManager(registration: LoginItemRegistration,
                             runner: ShellRunner,
                             emits: @escaping (String) -> Void = { _ in },
                             executablePath: String = "/Applications/Pic.app/Contents/MacOS/Pic")
        -> AutoStartManager {
        AutoStartManager(registration: registration, writer: writer, runner: runner,
                         executablePath: executablePath, emit: emits)
    }

    /// 剥 plist 里的键集 —— 判据只认「键在不在」，不认值的呈现形式。
    private func plistKeys() throws -> [String: Any] {
        let data = try Data(contentsOf: writer.plistURL())
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return try XCTUnwrap(plist as? [String: Any])
    }

    // MARK: - 7 条行为用例

    /// 落盘键集 = Label / ProgramArguments / RunAtLoad，**且没有 KeepAlive**。
    ///
    /// KeepAlive 会让 launchd 在 app 崩溃后无限拉起它，与「退出」菜单项直接冲突；
    /// 壁纸 app 不该被系统当守护进程。
    func testPlistHasLabelRunAtLoadAndNoKeepAlive() throws {
        try writer.write(executablePath: "/tmp/Pic")
        let plist = try plistKeys()

        XCTAssertEqual(plist["Label"] as? String, LaunchAgentWriter.defaultLabel)
        XCTAssertEqual(plist["RunAtLoad"] as? Bool, true,
                       "RunAtLoad 缺省是 false —— 漏掉它就是「注册成功但永不自启」")
        XCTAssertEqual(plist["ProgramArguments"] as? [String], ["/tmp/Pic"])
        XCTAssertNil(plist["KeepAlive"],
                     "登录项 plist 绝不能带 KeepAlive（崩了会被无限拉起，且与「退出」冲突）")
    }

    /// 删完再删不抛 —— 禁用路径要能重复跑。
    func testWriterRemoveDeletesPlist() throws {
        try writer.write(executablePath: "/tmp/Pic")
        XCTAssertTrue(FileManager.default.fileExists(atPath: writer.plistURL().path))

        writer.remove()
        XCTAssertFalse(FileManager.default.fileExists(atPath: writer.plistURL().path))

        writer.remove()
        XCTAssertNil(writer.existingExecutablePath())
    }

    /// A 抛错 → 自动落 B：plist 真被写出来，且 A 的失败形态进了 emit 序列。
    func testRouteAFailureFallsBackToLaunchAgentWriter() {
        let registration = FakeRegistration()
        registration.registerError = FakeRegisterError()
        let runner = FakeRunner()
        var emitted: [String] = []
        let manager = makeManager(registration: registration, runner: runner) { emitted.append($0) }

        manager.setEnabled(true)

        XCTAssertEqual(writer.existingExecutablePath(), "/Applications/Pic.app/Contents/MacOS/Pic",
                       "A 失败必须自动落 B：plist 里的可执行路径就是 manager 持有的那个")
        XCTAssertEqual(runner.subcommands, ["bootout", "bootstrap"],
                       "routeB 固定是 bootout → 写盘 → bootstrap 的顺序")
        XCTAssertTrue(emitted.contains { $0.hasPrefix("SYS01_ROUTE_A_FAILED error=") },
                      "A 的失败形态必须逐字可 grep：\(emitted)")
        XCTAssertTrue(emitted.contains("SYS01_ROUTE=launchagent"))
    }

    /// `.requiresApproval` 留在路线 A 并引导用户 —— **不落 B**。
    ///
    /// 注册已经成功，缺的只是用户点一次批准；此时再落 B 会变成两套登录项并存。
    func testRouteARequiresApprovalStaysOnRouteAAndOpensSettings() {
        let registration = FakeRegistration()
        registration.stubbedStatus = .requiresApproval
        let runner = FakeRunner()
        var emitted: [String] = []
        let manager = makeManager(registration: registration, runner: runner) { emitted.append($0) }

        manager.setEnabled(true)

        XCTAssertEqual(registration.openSettingsCount, 1,
                       "requiresApproval 必须引导用户在「登录项与扩展」里手动批准")
        XCTAssertNil(writer.existingExecutablePath(),
                     "requiresApproval 不落路线 B —— 一次开启只对应一套登录项")
        XCTAssertTrue(runner.calls.isEmpty, "留在 A 就不该有任何 launchctl 调用")
        XCTAssertTrue(emitted.contains("SYS01_REQUIRES_APPROVAL=1"))
        XCTAssertTrue(emitted.contains("SMAPP_STATUS=requiresApproval"))
        XCTAssertTrue(emitted.contains("SYS01_ROUTE=smappservice"))
    }

    /// A 成功（`.enabled`）→ 不碰路线 B。
    func testRouteASuccessSkipsLaunchAgentWriter() {
        let registration = FakeRegistration()
        registration.stubbedStatus = .enabled
        let runner = FakeRunner()
        var emitted: [String] = []
        let manager = makeManager(registration: registration, runner: runner) { emitted.append($0) }

        manager.setEnabled(true)

        XCTAssertNil(writer.existingExecutablePath(), "A 成功时不许留下任何路线 B 产物")
        XCTAssertTrue(runner.calls.isEmpty)
        XCTAssertTrue(emitted.contains("SMAPP_STATUS=enabled"))
        XCTAssertTrue(emitted.contains("SYS01_ROUTE=smappservice"))
    }

    /// 关：两条路线都清（注销 + bootout + 删 plist）。
    func testDisableCleansBothRoutes() {
        let registration = FakeRegistration()
        let runner = FakeRunner()
        var emitted: [String] = []
        let manager = makeManager(registration: registration, runner: runner) { emitted.append($0) }
        try? writer.write(executablePath: "/Applications/Pic.app/Contents/MacOS/Pic")

        manager.setEnabled(false)

        XCTAssertEqual(registration.unregisterCount, 1, "关掉必须注销路线 A")
        XCTAssertTrue(runner.subcommands.contains("bootout"), "关掉必须 bootout 掉路线 B")
        XCTAssertFalse(FileManager.default.fileExists(atPath: writer.plistURL().path),
                       "关掉必须删掉 plist —— 留着就是下一次登录时的一个幽灵登录项")
        XCTAssertTrue(emitted.contains("SYS01_DISABLED=1"))
    }

    /// app 被移动 → plist 里的旧路径必须被重写，且 bootout 发生在 bootstrap 之前。
    ///
    /// plist 存的是绝对路径：app 挪位置后 launchd 会照着旧路径拉一个不存在的可执行文件。
    /// 「bootout → 写盘 → bootstrap」的顺序天然覆盖这种情况，不需要额外分支。
    func testStalePlistPathIsRewrittenOnEnable() {
        try? writer.write(executablePath: "/old/location/Pic")
        XCTAssertEqual(writer.existingExecutablePath(), "/old/location/Pic")

        let registration = FakeRegistration()
        registration.registerError = FakeRegisterError()
        let runner = FakeRunner()
        let manager = makeManager(registration: registration, runner: runner,
                                  executablePath: "/new/location/Pic")

        manager.setEnabled(true)

        XCTAssertEqual(writer.existingExecutablePath(), "/new/location/Pic",
                       "plist 里的旧路径必须被当前可执行路径覆盖")
        XCTAssertEqual(runner.subcommands, ["bootout", "bootstrap"],
                       "必须先 bootout 掉旧作业再 bootstrap 新 plist")
        XCTAssertEqual(runner.calls.map { $0.arguments.last }, [writer.plistURL().path, writer.plistURL().path],
                       "bootout 与 bootstrap 必须指向同一个 plist 路径，否则旧作业留在 launchd 里")
    }
}