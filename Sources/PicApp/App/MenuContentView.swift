import SwiftUI
import AppKit
import PicCore

// 菜单栏菜单体 —— MENUBAR-03 / MENUBAR-07 / MENUBAR-08 的落点。
//
// 三条纪律，写在这里免得后面被「顺手改」掉：
//   ① 菜单项**只**由 `MenuItemID.allCases` 遍历产出。T3 的哨兵单测
//      （菜单标签里不出现文件名）能成立，全靠这一条 —— 手写 Button 就会绕过它。
//   ② 菜单**不直连 AVPlayer**。暂停/继续走仲裁器的 `set(.manualPause, active:)`，
//      由仲裁器决定 seek 锚点后再让 `PlayerController.arbiterApply` 执行
//      （D-11 单向流，T-02-08）。Phase 3 接入锁屏/全屏等 reason 之后，
//      手动暂停与系统 hold 才能叠加而不互相顶掉。
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

    init(terminate: @escaping () -> Void, presentSettings: @escaping () -> Void) {
        self.terminate = terminate
        self.presentSettings = presentSettings
    }

    var body: some View {
        // 「当前是否暂停」直接读仲裁器的派生量；本文件不另立一个可变的暂停标志。
        let isPaused = arbiter.isManuallyPaused
        ForEach(MenuItemID.allCases, id: \.self) { id in
            if id == .quit { Divider() }
            Button(MenuBarModel.label(for: id, isPaused: isPaused)) { activate(id, isPaused: isPaused) }
        }
    }

    private func activate(_ id: MenuItemID, isPaused: Bool) {
        switch id {
        case .pauseResume:
            // 唯一入口是仲裁器，菜单自己不碰播放器、也不自己 seek（D-11 / D-15）。
            arbiter.set(.manualPause, active: !isPaused)
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

/// 设置窗口的**最小骨架**（MENUBAR-02 的完整形态属 Phase 5）。
///
/// 这里只有一行只读的源目录路径 —— 路径只出现在用户主动打开的设置窗里，
/// 菜单栏那一侧永远不出现文件名或路径（MENUBAR-08）。
struct SettingsSkeletonView: View {
    @Environment(SettingsStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("源目录")
                .font(.headline)
            Text(store.resolvedFolderURL()?.path ?? "未设置")
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
            Text("设置项在 Phase 5 交付")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 420, alignment: .leading)
    }
}
