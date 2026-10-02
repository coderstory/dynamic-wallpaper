import Foundation

/// 菜单栏固定菜单项。**只有这三条，永不追加**（MENUBAR-03~08）。
///
/// 「菜单里不出现当前播放的文件名」之所以能被 `swift test` 判定而不只是一句承诺：
/// `MenuContentView` 必须遍历 `MenuItemID.allCases` 渲染，文案来源单一到 `MenuBarModel`。
public enum MenuItemID: String, CaseIterable {
    case pauseResume
    case openSettings
    case quit
}

/// 菜单文案的唯一来源。
public struct MenuBarModel {
    public static func label(for id: MenuItemID, isPaused: Bool) -> String {
        switch id {
        case .pauseResume: return isPaused ? "继续" : "暂停"
        case .openSettings: return "打开设置窗口"
        case .quit: return "退出"
        }
    }

    /// 恰好三项，顺序即 `MenuItemID.allCases` 的声明序。
    public static func labels(isPaused: Bool) -> [String] {
        MenuItemID.allCases.map { label(for: $0, isPaused: isPaused) }
    }

    @MainActor
    public static func perform(_ id: MenuItemID, isPaused: Bool,
                               store: SettingsStore, arbiter: HoldArbiter,
                               quit: () -> Void) {
        switch id {
        case .pauseResume:
            arbiter.set(.manualPause, active: !isPaused)
        case .openSettings:
            // 设置窗口由调用方处理；Phase 2 只需骨架，Phase 5 填内容。
            break
        case .quit:
            quit()
        }
    }
}
