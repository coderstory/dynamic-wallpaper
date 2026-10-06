import SwiftUI
import AppKit
import PicCore

// 菜单栏菜单体。菜单项只由 `MenuItemID.allCases` 遍历产出（手写 Button 会绕过哨兵单测），
// 暂停/继续一律走仲裁器 `set(.manualPause, active:)` —— 本文件不直连播放器、不出现文件名。
struct MenuContentView: View {
    @Environment(HoldArbiter.self) private var arbiter
    @Environment(\.openWindow) private var openWindow

    /// 「退出」的动作，由 `PicApp` 注入 `AppDelegate.terminateApp`。
    /// 本文件不出现结束进程的全局调用字面量（全仓只在 AppDelegate 一处）。
    private let terminate: () -> Void

    /// 「打开设置窗口」的前置动作（把激活策略临时提到 .regular）。AppKit 那一半在 AppDelegate。
    private let presentSettings: () -> Void

    /// 「立即下一个」的动作。闭包体在 AppDelegate，本文件只调模型，不碰播放器和轮换器。
    private let nextVideo: () -> Void

    /// 「重新扫描文件夹」的动作。同上，只调模型。
    private let rescanFolder: () -> Void

    /// 「删除当前壁纸」的动作。先切下一个再把刚才在播的移进废纸篓，顺序由 AppDelegate 保证。
    private let deleteCurrent: () -> Void

    init(terminate: @escaping () -> Void, presentSettings: @escaping () -> Void,
         nextVideo: @escaping () -> Void = {},
         rescanFolder: @escaping () -> Void = {},
         deleteCurrent: @escaping () -> Void = {}) {
        self.terminate = terminate
        self.presentSettings = presentSettings
        self.nextVideo = nextVideo
        self.rescanFolder = rescanFolder
        self.deleteCurrent = deleteCurrent
    }

    var body: some View {
        // 「当前是否暂停」直接读仲裁器的派生量；本文件不另立一个可变的暂停标志。
        let isPaused = arbiter.isManuallyPaused
        ForEach(MenuItemID.allCases, id: \.self) { id in
            if id == .quit { Divider() }
            Button(MenuBarModel.label(for: id, isPaused: isPaused)) { activate(id, isPaused: isPaused) }
                .settingsShortcut(for: id)
        }
    }

    private func activate(_ id: MenuItemID, isPaused: Bool) {
        switch id {
        case .pauseResume:
            // 唯一入口是模型层 perform：消掉这里与 MenuItem.perform 重复的 arbiter.set(.manualPause)，
            // 否则「暂停/继续」语义有两份实现，测试测 perform、UI 走这里，改一处漏一处。
            MenuBarModel.perform(id, isPaused: isPaused, arbiter: arbiter, quit: terminate)
        case .nextVideo:
            // 只调模型；行为体（轮换器）由 AppDelegate 的闭包注入。
            MenuBarModel.perform(id, isPaused: isPaused, arbiter: arbiter,
                                 quit: terminate, nextVideo: nextVideo)
        case .rescanFolder:
            // 同上：失效缓存与重扫是 AppDelegate 的活，菜单只转交意图。
            MenuBarModel.perform(id, isPaused: isPaused, arbiter: arbiter,
                                 quit: terminate, rescanFolder: rescanFolder)
        case .deleteCurrent:
            // 「先切下一个再删旧的」整个语义在 AppDelegate 那一侧，菜单只转交意图。
            MenuBarModel.perform(id, isPaused: isPaused, arbiter: arbiter,
                                 quit: terminate, deleteCurrent: deleteCurrent)
        case .openSettings:
            // PicCore 不依赖 AppKit 的全局应用对象，所以窗口这一侧由调用方处理。
            MenuBarModel.perform(id, isPaused: isPaused, arbiter: arbiter, quit: terminate)
            presentSettings()
            openWindow(id: "settings")
        case .quit:
            MenuBarModel.perform(id, isPaused: isPaused, arbiter: arbiter, quit: terminate)
        }
    }
}

/// 只有 `openSettings` 挂 ⌘,，其余项原样通过。
/// 必须是独立 ViewModifier：菜单的 Button 字面量要保持单一个，if/else 分支会逼出第二个。
struct MenuShortcut: ViewModifier {
    let id: MenuItemID
    func body(content: Content) -> some View {
        if id == .openSettings {
            content.keyboardShortcut(",", modifiers: .command)
        } else {
            content
        }
    }
}
