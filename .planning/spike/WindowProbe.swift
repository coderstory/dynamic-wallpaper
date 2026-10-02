// WindowProbe.swift —— Phase 01 门禁 spike，一次性 throwaway 枚举器。
//
// 目的：把「我方窗口层级 < Finder 桌面图标层」从肉眼判断变成可 grep 的数字（D-02 强证据 ①②）。
// 关键约束：本机常驻另外 4 个同类动态壁纸 app，其中至少一个正停在同一个 -2147483623，
// 所以只能用 --pid（kCGWindowOwnerPID）认领自己的窗口，禁止用 layer 数值或 owner 名认。
// 隐私：只输出 layer / owner / pid / bounds，**不输出窗口标题**（可能含用户文件路径，T-01-03）。
// 编译：swiftc -parse-as-library -target arm64-apple-macosx15.0 -o out/windowprobe WindowProbe.swift

import AppKit
import CoreGraphics

struct WindowInfo {
    let layer: Int
    let owner: String
    let pid: Int
    let bounds: String
}

@main
struct ProbeMain {
    static func main() {
        var targetPid = Int(ProcessInfo.processInfo.processIdentifier)
        let args = CommandLine.arguments
        var i = 1
        while i < args.count {
            if args[i] == "--pid", i + 1 < args.count, let parsed = Int(args[i + 1]) {
                targetPid = parsed
                i += 2
            } else {
                i += 1
            }
        }

        let raw = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []

        var windows: [WindowInfo] = []
        for entry in raw {
            // CGWindowList 的数值字段是 NSNumber（layer/pid 在不同 SDK 上分别是
            // Int32/Int），统一走 NSNumber.intValue，避免类型窄化编译错误。
            guard let layerNum = entry[kCGWindowLayer as String] as? NSNumber,
                  let pidNum = entry[kCGWindowOwnerPID as String] as? NSNumber else { continue }
            let layer = layerNum.intValue
            let pid = pidNum.intValue
            let owner = entry[kCGWindowOwnerName as String] as? String ?? "?"
            var boundsText = "0,0,0,0"
            if let rect = entry[kCGWindowBounds as String] as? [String: Any],
               let x = rect["X"] as? Double, let y = rect["Y"] as? Double,
               let w = rect["Width"] as? Double, let h = rect["Height"] as? Double {
                boundsText = "\(Int(x)),\(Int(y)),\(Int(w)),\(Int(h))"
            }
            windows.append(WindowInfo(layer: layer, owner: owner, pid: pid, bounds: boundsText))
        }

        // Apple 未承诺返回顺序，必须自己排。layer 升序；同层按 pid 兜底保证可复现。
        windows.sort { a, b in
            if a.layer != b.layer { return a.layer < b.layer }
            if a.pid != b.pid { return a.pid < b.pid }
            return a.owner < b.owner
        }

        for w in windows {
            print("WIN layer=\(w.layer) owner=\(w.owner) pid=\(w.pid) bounds=\(w.bounds)")
        }

        // 取「非零层里的最小值」而不是最大值：spike 万一多出一扇 layer 0 的辅助窗，
        // 取最大值会挑中它得到 0，让 ORDER 恒定翻 fail。
        let selfLevels = windows.filter { $0.pid == targetPid && $0.layer != 0 }.map(\.layer)
        let selfLevel = selfLevels.min()

        // Finder 的桌面图标层窗口。owner 名中英文都认（本机中文系统报「访达」）。
        let iconLevelValue = Int(CGWindowLevelForKey(.desktopIconWindow))
        let iconOwners: Set<String> = ["访达", "Finder"]
        let iconLevels = windows.filter { $0.layer == iconLevelValue && iconOwners.contains($0.owner) }.map(\.layer)
        let iconLevel = iconLevels.min()

        let selfLevelText = selfLevel.map(String.init) ?? "none"
        let iconLevelText = iconLevel.map(String.init) ?? "none"
        print("SELF_PID=\(targetPid)")
        print("SELF_LEVEL=\(selfLevelText)")
        print("ICON_LEVEL=\(iconLevelText)")

        let desktopLevelValue = Int(CGWindowLevelForKey(.desktopWindow))

        // ORDER 四条同时成立才 ok；否则逐条报出第一个不满足的。
        var reason = ""
        if selfLevel == nil {
            reason = "self_level_missing"
        } else if iconLevel == nil {
            reason = "icon_level_missing"
        } else if selfLevel == iconLevel {
            reason = "self_level_not_below_icon_level"
        } else if selfLevel! >= iconLevel! {
            reason = "self_level_not_below_icon_level"
        } else if selfLevel != desktopLevelValue {
            reason = "self_level_not_desktop_level"
        }

        print("ORDER=\(reason.isEmpty ? "ok" : "fail")")
        print("REASON=\(reason)")
    }
}
