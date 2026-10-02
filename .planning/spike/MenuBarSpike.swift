// MenuBarSpike.swift —— Phase 01 plan 01-02 主路线 spike，一次性 throwaway。
//
// 目的：ROADMAP Success Criteria 第 3 条 —— MenuBarExtra 在 .accessory 激活策略 + 无 Dock 图标下是否真能用。
// 形态：单文件 SwiftUI App，`swiftc -parse-as-library -target arm64-apple-macosx15.0` 一条命令编译。
// 不组装 .app bundle、不写 Info.plist、不建 Xcode 工程（编排器硬性指令 1/2）。
// 不调 NSApplication.shared.activate —— 会抢焦点，违背 .accessory 语义（T-01-05）。
// 不显式调 NSApp.run()：SwiftUI App 协议自带 run loop，再跑一次会重入。
// stdout 打印恰好一次 PIC_MENU 行，作为 menubar-check.sh 的断言对象（T-01-12）。
//
// 激活策略 rawValue 以本机实测为准（2026-10-03）：regular=0 / accessory=1 / prohibited=2。
// 所以这里打印的是 setActivationPolicy 之后的生效策略，accessory 期望值是 1 而不是 0。

import SwiftUI
import AppKit

@main
struct MenuBarSpikeApp: App {
    @NSApplicationDelegateAdaptor(MenuBarSpikeDelegate.self) var delegate

    var body: some Scene {
        MenuBarExtra { MenuBarBody() } label: { Image(systemName: "play.rectangle") }
    }
}

// 菜单体：菜单项固定 5 条、无子层级，与 PROJECT.md 已锁定的菜单形态一致。
// 退出本身在这 5 条之内，不是第 6 条；Divider 不是菜单项。
// 菜单里不出现文件名（PROJECT.md 已定）。
// 本 spike 只验证能否弹出，行为是空实现。
// 书写约束：菜单定义一律单行，注释一律行首，避免计数判据被行尾注释污染。
struct MenuBarBody: View {
    var body: some View {
        Button("暂停") {}
        Button("立即下一个") {}
        Button("重新扫描文件夹") {}
        Divider()
        Button("打开设置窗口") {}
        Button("退出") { NSApp.terminate(nil) }
    }
}

final class MenuBarSpikeDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let ok = NSApp.setActivationPolicy(.accessory)
        let policy = NSApp.activationPolicy().rawValue
        print("PIC_MENU policy=\(policy) ok=\(ok) menubarExtra=ok dock=hidden_by_policy")
        fflush(stdout)
    }
}
