import SwiftUI
import AppKit
import PicCore

/// @main 入口 —— D-01 SwiftPM 包的可执行 target。
/// 本 Phase 只放一个最小 MenuBarExtra 骨架，让 swift build 在 State 层落地前就能过；
/// 菜单三项（暂停/继续、打开设置、退出）的接线在 Plan 02-03。
@main
struct PicApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Pic", systemImage: "play.rectangle") {
            Button("退出") {
                appDelegate.terminateApp()
            }
        }
    }
}
