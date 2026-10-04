import SwiftUI
import AppKit
import PicCore

// 菜单栏菜单体。
//
// 三条纪律，写在这里免得后面被「顺手改」掉：
//   ① 菜单项**只**由 `MenuItemID.allCases` 遍历产出。哨兵单测（菜单标签里不出现文件名）
//      能成立，全靠这一条 —— 手写 Button 就会绕过它。
//   ② 菜单**不直连 AVPlayer**。暂停/继续走仲裁器的 `set(.manualPause, active:)`，
//      由仲裁器决定 seek 锚点后再让 `PlayerController.arbiterApply` 执行。
//      接入锁屏/全屏等 reason 之后，手动暂停与系统 hold 才能叠加而不互相顶掉。
//   ③ 菜单是全局常驻、路过的人一眼能扫到的界面 —— 这里永不出现文件名或路径。
//
// 菜单定义一律单行，注释一律行首 —— 行尾注释会绕过 test.sh 的剥注释过滤器。
struct MenuContentView: View {
    @Environment(SettingsStore.self) private var store
    @Environment(HoldArbiter.self) private var arbiter
    @Environment(\.openWindow) private var openWindow

    /// 「退出」的真实动作。由 `PicApp` 注入 `AppDelegate.terminateApp`，
    /// 本文件**不出现**结束进程的全局调用字面量（它全仓只在 AppDelegate 里一处）。
    private let terminate: () -> Void

    /// 「打开设置窗口」的前置动作（把激活策略临时提到 .regular）。AppKit 那一半在 AppDelegate。
    private let presentSettings: () -> Void

    /// 「立即下一个」的动作。闭包体是 AppDelegate 的活，本文件只调模型 ——
    /// 菜单侧不碰播放器、不碰轮换器。
    private let nextVideo: () -> Void

    /// 「重新扫描文件夹」的动作。同上，只调模型。
    private let rescanFolder: () -> Void

    /// 「删除当前壁纸」的动作（AppDelegate 的 `deleteCurrentWallpaperNow`：
    /// 先切下一个，再把刚才在播的移进废纸篓）。顺序在那一侧保证。
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
            // 唯一入口是仲裁器，菜单自己不碰播放器、也不自己 seek。
            arbiter.set(.manualPause, active: !isPaused)
        case .nextVideo:
            // 只调模型；行为体（轮换器）由 AppDelegate 的闭包注入。
            MenuBarModel.perform(id, isPaused: isPaused, store: store, arbiter: arbiter,
                                 quit: terminate, nextVideo: nextVideo)
        case .rescanFolder:
            // 同上：失效缓存与重扫是 AppDelegate 的活，菜单只转交意图。
            MenuBarModel.perform(id, isPaused: isPaused, store: store, arbiter: arbiter,
                                 quit: terminate, rescanFolder: rescanFolder)
        case .deleteCurrent:
            // 「先切下一个再删旧的」整个语义在 AppDelegate 那一侧，菜单只转交意图。
            MenuBarModel.perform(id, isPaused: isPaused, store: store, arbiter: arbiter,
                                 quit: terminate, deleteCurrent: deleteCurrent)
        case .openSettings:
            // PicCore 不依赖 AppKit 的全局应用对象，所以窗口这一侧由调用方处理。
            MenuBarModel.perform(id, isPaused: isPaused, store: store, arbiter: arbiter, quit: terminate)
            presentSettings()
            openWindow(id: "settings")
        case .quit:
            MenuBarModel.perform(id, isPaused: isPaused, store: store, arbiter: arbiter, quit: terminate)
        }
    }
}

/// ⌘, 的渲染载体：只有 `openSettings` 挂快捷键，其余项原样通过。
/// 独立 ViewModifier 而不是行内条件分支 —— 菜单的 Button 字面量必须保持单一个
/// （菜单门语义），if/else 分支会逼出第二个 Button 字面量。
/// 应用入口在 PicApp.swift 的 `settingsShortcut(for:)`：计数门锁本文件内
/// `MenuShortcut` 字面量恰好 1 次（结构体声明已占用），在这里再写一次应用会是 2。
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
