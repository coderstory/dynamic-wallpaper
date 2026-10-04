import SwiftUI
import AppKit
import PicCore

/// @main 入口 —— SwiftPM 包的可执行 target。
///
/// 两个场景，职责不重叠：
///   - `MenuBarExtra` 是常驻入口，内容交给 `MenuContentView` 遍历 `MenuItemID.allCases` 渲染。
///   - `Window(id: "settings")` 放完整设置窗（`SettingsView`）。沿用 `Window` 场景而非 SwiftUI
///     `Settings` 场景：标题栏文字「Pic 设置」是 UI-SPEC §7 的硬要求，且策略接线已按
///     `Window + openWindow` 建好；`Settings` 场景的 ⌘, 语义由 MenuContentView 的
///     keyboardShortcut 补齐。
///
/// ⚠️ 激活策略是 AppDelegate 的唯一职责，视图这一侧只调它提供的两个方法 ——
/// 策略切换散落在多处是点名的 DoS 面（漏恢复就会永久留下 Dock 图标）。
@main
struct PicApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Pic 设置", id: "settings") {
            SettingsView(requestFolder: { appDelegate.requestFolderNow() },
                         rescanLibrary: { appDelegate.rescanLibrary() },
                         reapplyBatteryHold: { appDelegate.reapplyBatteryHold() },
                         setLaunchAtLogin: { appDelegate.setLaunchAtLogin($0) },
                         openTranscode: { appDelegate.openTranscodeWindow($0) },
                         refreshFFmpeg: {
                             appDelegate.refreshFFmpegAvailability()
                             return appDelegate.ffmpegIsAvailable
                         })
                .environment(appDelegate.store)
                .environment(appDelegate.arbiter)
                .environment(appDelegate.settingsApplier)
                .environment(appDelegate.sessionState)
                // 关窗路径：关窗只隐藏 + 策略回 .accessory。
                .onDisappear { appDelegate.hideSettingsAndRestorePolicy() }
        }
        // 宽 780 只是初始值（真实宽度由 minWidth/idealWidth 撑），高由内容撑。
        .defaultSize(width: SettingsPresentation.windowWidth, height: 420)
        // 原生标题栏在 macOS 27 上不吃 backgroundColor/透明化（实测被 SwiftUI 改回灰）。
        // 「蓝色标题栏」用 hiddenTitleBar + 内容自绘标题行实现；NSWindow.title 仍是
        // 「Pic 设置」（Mission Control / 几何探针按它找窗），拖动走
        // isMovableByWindowBackground（SettingsView.applyWindowChrome 里开）。
        .windowStyle(.hiddenTitleBar)

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
            // 菜单栏图标视图常驻（菜单内容是打开菜单时才构建的，订阅放那里在启动期收不到通知）。
        // `PicOpenSettings` 通知桥挂在这里 —— 调的还是用户路径的两个函数
        //（presentSettingsWindow + openWindow）。
            MenuBarLabel(presentSettings: { appDelegate.presentSettingsWindow() })
        }

        // 转码窗。全 app 唯一出现列表的地方；开窗动作由设置窗「维护」行的
        // `openWindow(id:)` 触发 —— 与设置窗同一套开窗机制。
        TranscodeScene(queue: appDelegate.transcodeQueue,
                       locator: appDelegate.transcodeLocator,
                       wallpaperRootProvider: { appDelegate.store.resolvedFolderURL() })
    }
}

/// 菜单栏图标的常驻壳（仅承载 `--open-settings` 脚手架的通知订阅）。
private struct MenuBarLabel: View {
    let presentSettings: () -> Void
    @Environment(\.openWindow) private var openWindow

    /// 菜单栏图标 = 设计定稿的 menubar-v1（bundle 里是 menubar-v1Template{,@2x,@3x}.png，
    /// @2x/@3x 变体由 NSImage 加载自动带上）。
    /// ⚠️ 必须**显式 NSImage 加载**，不许「简化」回字符串名 `Image("menubar-v1Template")`：
    /// macOS 27 实测该具名路径在 MenuBarExtra label 里解析不到散装 PNG，状态项渲染成
    /// 18pt 全透明空槽——而 Bundle.image 层加载是好的（07-01 的加载验证因此漏过）。
    /// 实测判据：裸 Image / Text / nsImage±onReceive = 34pt 有内容；字符串名 = 18pt 空。
    /// isTemplate 显式置位，不押注文件名后缀自动判定。
    /// ⚠️ size 固定 22pt：素材（2026-10-04 重制）画布 20pt、glyph 满幅约 17.6×15.4pt、
    /// 线条约 3.3pt —— 用户两轮实测反馈「太小 / 线条太细」。@3x 源 60px 下采样，无画质损失。
    private var statusIcon: NSImage {
        let img = Bundle.main.image(forResource: "menubar-v1Template") ?? NSImage()
        img.isTemplate = true
        img.size = NSSize(width: 22, height: 22)
        return img
    }

    var body: some View {
        Image(nsImage: statusIcon)
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("PicOpenSettings"))) { _ in
                presentSettings()
                openWindow(id: "settings")
            }
    }
}

/// `MenuShortcut` 的应用入口（⌘,）。
/// 放在本文件而不是 MenuContentView：计数门锁 MenuContentView 内
/// `MenuShortcut` 字面量恰好 1 次（结构体声明已占用），在那里再写一次应用会把计数顶到 2。
/// 语义不变：仍只有一个 ViewModifier、一个 Button 字面量。
extension View {
    func settingsShortcut(for id: MenuItemID) -> some View {
        modifier(MenuShortcut(id: id))
    }
}
