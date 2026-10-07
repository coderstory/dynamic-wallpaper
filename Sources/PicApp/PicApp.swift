import SwiftUI
import AppKit
import PicCore

/// @main 入口。UI 全在 AppDelegate 的 AppKit 装配里：菜单栏面板是 NSStatusItem + NSPopover，
/// 设置窗是 NSWindow + NSHostingController —— SwiftUI Window 场景的 `openWindow` 在 popover
/// 里没有场景上下文叫不动，MenuBarExtra 的原生 .menu 又画不了设计稿的自绘面板（原型 D），
/// 两层就都迁到了 AppKit。
///
/// 本文件只留一个永不出现的 `Settings` 空场景满足 App 协议的 Scene 要求；
/// `.appSettings` 命令组被替换成空 —— 不替换的话 ⌘, 会叫出这个空窗。
@main
struct PicApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
            .commands { CommandGroup(replacing: .appSettings) { } }
    }
}
