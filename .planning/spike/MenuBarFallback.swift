// MenuBarFallback.swift —— Phase 01 plan 01-02 退路 spike，一次性 throwaway。
//
// 目的：ROADMAP Success Criteria 第 3 条的兜底分支 —— MenuBarExtra 若不可用，
//      NSStatusItem 这条路必须「已验证可编译可运行」。本文件与主路线不能编到同一产物
//      （一个产物只能有一个 @main）。
// 形态：单文件 AppKit 二进制，不依赖 SwiftUI。swiftc -parse-as-library 一条命令编译。
// 不组装 .app bundle、不写 Info.plist、不建 Xcode 工程。
// 不调 NSApplication.shared.activate —— 会抢焦点，违背 .accessory 语义（T-01-05）。
// 菜单体与 MenuBarSpike.swift 完全同形：固定 5 条、无子层级，退出含在这 5 条之内。
// Divider 不是菜单项。菜单里不出现文件名。本 spike 只验证能否挂上并弹出，行为是空实现。
// menubarExtra=fallback 是 menubar-check.sh 区分两条路径的唯一标记，不要写成 ok。
//
// 激活策略 rawValue 本机实测（2026-10-03）：regular=0 / accessory=1 / prohibited=2，
// 所以打印的是 setActivationPolicy 之后的生效策略，accessory 期望值是 1 而不是 0。

import AppKit

@main
final class StatusMain: NSObject {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let ok = app.setActivationPolicy(.accessory)
        let policy = app.activationPolicy().rawValue

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "play.rectangle", accessibilityDescription: nil)

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "暂停", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "立即下一个", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "重新扫描文件夹", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "打开设置窗口", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "退出", action: #selector(terminateApp), keyEquivalent: "q"))
        item.menu = menu

        print("PIC_MENU policy=\(policy) ok=\(ok) menubarExtra=fallback dock=hidden_by_policy")
        fflush(stdout)

        app.run()
    }

    @objc func terminateApp() {
        NSApp.terminate(nil)
    }
}
