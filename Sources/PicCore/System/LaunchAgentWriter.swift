// LaunchAgentWriter.swift —— 路线 B 的 plist 生成与落盘（不 spawn 进程）。
//
// ⚠️ 键集是**代码常量**（T-07-03 缓解面）：Label 由 init 传入且默认固定，
// ProgramArguments 只有 app 自己的可执行路径，全文件零用户输入拼入。
// 登录项 plist 是持久执行面 —— 判据 `src_count 'KeepAlive' == 0` 锁死这个不变量：
// 壁纸 app 崩了不该被 launchd 无限拉起，且 KeepAlive 与「退出」菜单项直接冲突。
//
// ⚠️ 分层：本文件不 import AppKit / SwiftUI，也不 spawn 进程
// （bootstrap / bootout 是 AutoStartManager 的活）。test.sh 的 System/ 分层判据每次重验。

import Foundation

/// 生成与管理路线 B 的 `~/Library/LaunchAgents/<label>.plist`。
///
/// 目录可注入 —— 单测指临时目录，产品指用户真实目录，两条路径共用同一份实现。
public final class LaunchAgentWriter {
    /// 路线 B 独占的 launchd 命名空间（BTM 会把它收编进「登录项与扩展」）。
    public static let defaultLabel = "com.local.pic"

    private let label: String
    private let directory: URL

    /// - Parameters:
    ///   - label: launchd 作业标识。
    ///   - directory: plist 落盘目录，`nil` 时取 `~/Library/LaunchAgents`。
    public init(label: String = LaunchAgentWriter.defaultLabel, directory: URL? = nil) {
        self.label = label
        self.directory = directory ?? FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
    }

    /// plist 的绝对路径 —— 传 `bootstrap` / `bootout` 用的就是它。
    public func plistURL() -> URL {
        directory.appendingPathComponent("\(label).plist", isDirectory: false)
    }

    /// 落盘最小键集：`Label` / `ProgramArguments` / `RunAtLoad`。
    ///
    /// ⚠️ 顺序即契约：`launchd.plist` 只要求 Label 必填，但 RunAtLoad 缺省为 false ——
    /// 漏掉它就是「注册成功但永不自启」这种最隐蔽的失败。
    public func write(executablePath: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL(), options: .atomic)
    }

    /// 读回已落盘 plist 的 `ProgramArguments` 首元素。文件不存在或读不出返回 `nil`。
    ///
    /// app 被移动后这里的旧路径会让已加载的作业指向一个不存在的可执行文件；
    /// 漂移检测据此判定「要重写」。
    public func existingExecutablePath() -> String? {
        guard let data = try? Data(contentsOf: plistURL()),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let plist = plist as? [String: Any],
              let arguments = plist["ProgramArguments"] as? [String]
        else { return nil }
        return arguments.first
    }

    /// 删 plist；文件不存在时静默成功（禁用路径要能重复跑）。
    public func remove() {
        try? FileManager.default.removeItem(at: plistURL())
    }
}