import Foundation

/// 菜单栏固定菜单项。**case 顺序 = 面板行序**（原型 D 的分组：无副作用操作 → 维护 → 不可逆 → 系统），
/// 新增项一律追加到 `openSettings` 之前、`quit` 保持最后 —— 行序与分隔线位置都依赖这个声明顺序。
public enum MenuItemID: String, CaseIterable {
    case pauseResume
    case nextVideo
    case rescanFolder
    /// 切壁纸来源（视频 ⇄ 图片）。文案随当前来源变，所以**只有一项**而不是两项常驻。
    case switchSource
    // 删除当前正在播放的壁纸文件（移到废纸篓）。
    case deleteCurrent
    case openSettings
    case quit
}

/// 菜单文案的唯一来源。
public struct MenuBarModel {
    public static func label(for id: MenuItemID, isPaused: Bool, kind: WallpaperKind) -> String {
        switch id {
        case .pauseResume: return isPaused ? "继续" : "暂停"
        case .nextVideo: return "立即下一个"
        // 菜单里不出现当前播放的文件名：文件名多为无语义的 0B0E397E-… 这类串，
        // 删的是「当前正在播的那个」，语义由动作本身说清。
        case .deleteCurrent: return "把当前壁纸移到废纸篓…"
        case .rescanFolder: return "重新扫描文件夹"
        // 说「改成什么」而不是「切换来源」：菜单里看不出当前是哪一个，
        // 写「切换壁纸来源」等于让用户先去设置窗确认现状再回来点。
        case .switchSource: return kind == .image ? "改用视频壁纸" : "改用图片壁纸"
        case .openSettings: return "打开设置"
        case .quit: return "退出"
        }
    }

    @MainActor
    public static func perform(_ id: MenuItemID, isPaused: Bool,
                               arbiter: HoldArbiter,
                               quit: () -> Void,
                               nextVideo: () -> Void = {},
                               rescanFolder: () -> Void = {},
                               switchSource: () -> Void = {},
                               deleteCurrent: () -> Void = {}) {
        switch id {
        case .pauseResume:
            arbiter.set(.manualPause, active: !isPaused)
        case .nextVideo:
            // 行为体由调用方注入（AppDelegate → RotationController.advanceNow）。
            // 菜单动作不得绕过仲裁器直连播放端。
            nextVideo()
        case .deleteCurrent:
            //  切下一个 + 移入废纸篓 + 失效扫描缓存三步全在 AppDelegate， 顺序由行为体保证（先切后删）。
            deleteCurrent()
        case .rescanFolder:
            rescanFolder()
        case .switchSource:
            // 整条切换链（停旧的 → 翻层 → 失效缓存 → 重扫）在 AppDelegate 里，
            // 菜单只转交意图 —— 与 deleteCurrent 同一分工。
            switchSource()
        case .openSettings:
            break
        case .quit:
            quit()
        }
    }
}
