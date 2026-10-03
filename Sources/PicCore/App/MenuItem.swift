import Foundation

/// 菜单栏固定菜单项。本 Phase 起共 5 项：暂停/继续（Phase 2）、立即下一个与
/// 重新扫描文件夹（Phase 4 / MENUBAR-04/05）、打开设置窗口与退出（Phase 2）。
/// **新增项一律追加到 `openSettings` 之前、`quit` 保持最后** —— `quit` 排在最后
/// 是「退出项之前插分隔线」这条渲染规则的依赖，重排会挪动分隔线的位置。
///
/// 「菜单里不出现当前播放的文件名」之所以能被 `swift test` 判定而不只是一句承诺：
/// `MenuContentView` 必须遍历 `MenuItemID.allCases` 渲染，文案来源单一到 `MenuBarModel`。
public enum MenuItemID: String, CaseIterable {
    case pauseResume
    // 立即下一个（Phase 4 / MENUBAR-04）。
    case nextVideo
    // 重新扫描文件夹（Phase 4 / MENUBAR-05）。
    case rescanFolder
    case openSettings
    case quit
}

/// 菜单文案的唯一来源。
public struct MenuBarModel {
    public static func label(for id: MenuItemID, isPaused: Bool) -> String {
        switch id {
        case .pauseResume: return isPaused ? "继续" : "暂停"
        case .nextVideo: return "立即下一个"
        case .rescanFolder: return "重新扫描文件夹"
        case .openSettings: return "打开设置"
        case .quit: return "退出"
        }
    }

    /// 恰好五项，顺序即 `MenuItemID.allCases` 的声明序。
    public static func labels(isPaused: Bool) -> [String] {
        MenuItemID.allCases.map { label(for: $0, isPaused: isPaused) }
    }

    @MainActor
    public static func perform(_ id: MenuItemID, isPaused: Bool,
                               store: SettingsStore, arbiter: HoldArbiter,
                               quit: () -> Void,
                               nextVideo: () -> Void = {},
                               rescanFolder: () -> Void = {}) {
        switch id {
        case .pauseResume:
            arbiter.set(.manualPause, active: !isPaused)
        case .nextVideo:
            // 行为体由调用方注入（AppDelegate → RotationController.advanceNow）。
            // 本层不碰 arbiter、不碰 store、不碰 quit（T-04-22：菜单动作不得
            // 绕过仲裁器直连播放端）。
            nextVideo()
        case .rescanFolder:
            // 同上：失效缓存与重扫是 AppDelegate 的活，模型只转交意图。
            rescanFolder()
        case .openSettings:
            // 设置窗口由调用方处理；Phase 2 只需骨架，Phase 5 填内容。
            break
        case .quit:
            quit()
        }
    }
}
