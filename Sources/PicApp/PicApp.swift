import SwiftUI
import AppKit
import PicCore

/// @main 入口 —— D-01 SwiftPM 包的可执行 target。
///
/// 两个场景，职责不重叠：
///   - `MenuBarExtra` 是常驻入口，内容交给 `MenuContentView` 遍历 `MenuItemID.allCases` 渲染。
///   - `Window(id: "settings")` 只放**最小骨架**，不自动弹出（`.accessory` 下默认不打开）；
///     完整设置窗是 MENUBAR-02，属 Phase 5。
///
/// 激活策略是 AppDelegate 的唯一职责，视图这一侧只调它提供的两个方法 ——
/// 策略切换散落在多处是 T-02-09 点名的 DoS 面（漏恢复就会永久留下 Dock 图标）。
@main
struct PicApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Pic 设置", id: "settings") {
            SettingsSkeletonView()
                .environment(appDelegate.store)
                .environment(appDelegate.arbiter)
                .onDisappear { appDelegate.hideSettingsAndRestorePolicy() }
        }
        .defaultSize(width: 452, height: 150)

        MenuBarExtra("Pic", systemImage: "photo.on.rectangle") {
            MenuContentView(
                terminate: { appDelegate.terminateApp() },
                presentSettings: { appDelegate.presentSettingsWindow() }
            )
            .environment(appDelegate.store)
            .environment(appDelegate.arbiter)
        }
    }
}
