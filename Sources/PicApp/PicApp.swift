import SwiftUI
import AppKit
import PicCore

/// @main 入口：常驻菜单栏 + 一个设置窗。
/// 激活策略是 AppDelegate 的唯一职责，本文件只调它给的两个方法。
@main
struct PicApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("动态壁纸", id: "settings") {
            SettingsView(requestFolder: { appDelegate.requestFolderNow() },
                         rescanLibrary: { appDelegate.rescanLibrary() },
                         reapplyBatteryHold: { appDelegate.reapplyBatteryHold() },
                         setLaunchAtLogin: { appDelegate.setLaunchAtLogin($0) },
                         transcodeViewModel: appDelegate.transcodeViewModel,
                         fpsViewModel: appDelegate.fpsTranscodeViewModel,
                         refreshFFmpeg: { appDelegate.refreshFFmpegAvailability() },
                         rotation: appDelegate.rotation)
                .environment(appDelegate.store)
                .environment(appDelegate.arbiter)
                .environment(appDelegate.settingsApplier)
                .environment(appDelegate.sessionState)
                // 关窗只隐藏，策略回 .accessory
                .onDisappear { appDelegate.hideSettingsAndRestorePolicy() }
        }
        // defaultSize 只是初始值，真实尺寸由 SettingsView 的 minWidth/idealWidth 撑
        .defaultSize(width: SettingsPresentation.windowWidth, height: 480)
        // 原生标题栏不吃 backgroundColor，标题行自绘；NSWindow.title 仍是「动态壁纸」，
        // `applyWindowChrome` 按它找窗，拖动靠 isMovableByWindowBackground。
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra {
            MenuContentView(
                rotation: appDelegate.rotation,
                terminate: { appDelegate.terminateApp() },
                presentSettings: { appDelegate.presentSettingsWindow() },
                nextVideo: { appDelegate.nextVideoNow() },
                rescanFolder: { appDelegate.rescanLibrary() },
                deleteCurrent: { appDelegate.deleteCurrentWallpaperNow() }
            )
            .environment(appDelegate.arbiter)
            .environment(appDelegate.store)
        } label: {
            MenuBarLabel()
        }
    }
}

/// 菜单栏图标的常驻壳。
private struct MenuBarLabel: View {
    /// 菜单栏图标。必须显式 NSImage 加载：字符串名 `Image("…")` 在 MenuBarExtra label 里
    /// 解析不到散装 PNG，渲染成全透明空槽。size 固定 22pt，isTemplate 显式置位。
    private var statusIcon: NSImage {
        let img = Bundle.main.image(forResource: "menubar-v1Template") ?? NSImage()
        img.isTemplate = true
        img.size = NSSize(width: 22, height: 22)
        return img
    }

    var body: some View {
        Image(nsImage: statusIcon)
    }
}

/// `MenuShortcut` 的应用入口（⌘,）。放在本文件，避免 MenuContentView 里出现第二个
/// `MenuShortcut` 字面量。
extension View {
    func settingsShortcut(for id: MenuItemID) -> some View {
        modifier(MenuShortcut(id: id))
    }
}
