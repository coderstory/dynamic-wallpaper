import SwiftUI
import AppKit
import PicCore

/// @main 入口 —— D-01 SwiftPM 包的可执行 target。
///
/// 菜单栏图标是本 Phase 的可感知价值之一。本 plan 的竖切只证明「图标这一路通了」，
/// 因此菜单里只放一个退出项；暂停/继续与打开设置是 Plan 02-03 的范围。
@main
struct PicApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            Button("退出") {
                appDelegate.terminateApp()
            }
        } label: {
            Image(systemName: "photo.on.rectangle")
        }
    }
}