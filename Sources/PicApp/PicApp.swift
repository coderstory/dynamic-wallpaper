import SwiftUI
import AppKit
import PicCore

/// @main 入口 —— D-01 SwiftPM 包的可执行 target。
///
/// 两个场景，职责不重叠：
///   - `MenuBarExtra` 是常驻入口，内容交给 `MenuContentView` 遍历 `MenuItemID.allCases` 渲染。
///   - `Window(id: "settings")` 放 Phase 5 的完整设置窗（`SettingsView`）。
///     沿用 `Window` 场景而非 SwiftUI `Settings` 场景：标题栏文字「Pic 设置」是
///     UI-SPEC §7 的硬要求，且 T-02-09 的策略接线已按 `Window + openWindow` 建好；
///     `Settings` 场景的 ⌘, 语义由 MenuContentView 的 keyboardShortcut 补齐。
///
/// 激活策略是 AppDelegate 的唯一职责，视图这一侧只调它提供的两个方法 ——
/// 策略切换散落在多处是 T-02-09 点名的 DoS 面（漏恢复就会永久留下 Dock 图标）。
@main
struct PicApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Pic 设置", id: "settings") {
            SettingsView(reapplyBatteryHold: { appDelegate.reapplyBatteryHold() })
                .environment(appDelegate.store)
                .environment(appDelegate.arbiter)
                .environment(appDelegate.settingsApplier)
                // MENUBAR-02 的关窗路径（T-02-09 既有）：关窗只隐藏 + 策略回 .accessory。
                .onDisappear { appDelegate.hideSettingsAndRestorePolicy() }
        }
        // 宽 780 只是初始值（真实宽度由 minWidth/idealWidth 撑），高由内容撑。
        .defaultSize(width: SettingsPresentation.windowWidth, height: 420)

        MenuBarExtra {
            MenuContentView(
                terminate: { appDelegate.terminateApp() },
                presentSettings: { appDelegate.presentSettingsWindow() },
                nextVideo: { appDelegate.nextVideoNow() },
                rescanFolder: { appDelegate.rescanFolderNow() }
            )
            .environment(appDelegate.store)
            .environment(appDelegate.arbiter)
        } label: {
            // 菜单栏图标视图常驻（菜单内容是打开菜单时才构建的，订阅放那里
            // 在启动期收不到通知）。`PicOpenSettings` 通知桥挂在这里 —— 调的还是
            // 用户路径的两个函数（presentSettingsWindow + openWindow）。
            MenuBarLabel(presentSettings: { appDelegate.presentSettingsWindow() })
        }
    }
}

/// 菜单栏图标的常驻壳（仅承载 `--open-settings` 脚手架的通知订阅）。
private struct MenuBarLabel: View {
    let presentSettings: () -> Void
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // 菜单栏图标 = 设计定稿的 menubar-v1（ASSET-02）。bundle 里存的是
        // menubar-v1Template{,@2x,@3x}.png —— 名字带 Template 后缀时 AppKit 自动
        // 置 isTemplate，深浅色由系统适配。@2x/@3x 变体由具名查找自动带上。
        Image("menubar-v1Template")
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("PicOpenSettings"))) { _ in
                presentSettings()
                openWindow(id: "settings")
            }
    }
}

/// `MenuShortcut` 的应用入口（MENUBAR-06 的 ⌘,）。
/// 放在本文件而不是 MenuContentView：计数门锁 MenuContentView 内
/// `MenuShortcut` 字面量恰好 1 次（结构体声明已占用），在那里再写一次
/// 应用会把计数顶到 2。语义不变：仍只有一个 ViewModifier、一个 Button 字面量。
extension View {
    func settingsShortcut(for id: MenuItemID) -> some View {
        modifier(MenuShortcut(id: id))
    }
}
