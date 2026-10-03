import AppKit
import CoreGraphics

/// 产品侧的窗口探针 —— **按 PID 认领**。
///
/// 为什么必须按 PID：本机常驻若干个同类动态壁纸 app，只按层级认领会把别人的窗口
/// 当成自己的。本探针把这件事变成机器可读的数字：`FOREIGN_SAME_LEVEL=<n>` 数的是
/// 「层级与我方窗口完全相同、owner pid 却不是自己」的窗口数。
///
/// 隐私纪律：**只**读 `kCGWindowLayer` / `kCGWindowOwnerPID` / `kCGWindowOwnerName` /
/// `kCGWindowBounds` 四个键。窗口标题那个键一个字节都不碰 —— 它可能含用户文件名；
/// `test.sh` 每次自动重验「产品源码里那个标题键 0 次」。
///
/// 本文件**不需要**桌面图标层的值，因此不出现取层级值的那个 CoreGraphics 函数，
/// 也不出现任何层级数字字面量。「我方层 < 图标层」这一半由 throwaway 探针承担
/// （`run-probe.sh order` 现编译现跑），两边都不硬编码。
/// 不传 `-DPIC_NO_PROBE` 时整个声明区都在；交付构建由 `build.sh` 的
/// `-Xswiftc -DPIC_NO_PROBE` 打开开关，把测量脚手架从交付二进制里剥掉。
#if !PIC_NO_PROBE
public enum WindowProbe {

    /// 「桌面层家族」的带宽：以我方层级为中心上下各多少级算作同一族。
    /// 这是带宽，不是层级值 —— 换机器不会失效（层级之间的间距由系统定，不由本项目定）。
    static let familyBand = 64

    struct Entry {
        let layer: Int
        let pid: Int
        let owner: String
        let bounds: CGRect
    }

    // MARK: - 按 PID 认领

    public static func claimReport(targetPid: Int) -> [String] {
        let all = listWindows()
        // layer == 0 的辅助窗不参与最小值计算：取最大值会挑中它，让层级读数恒为 0。
        let mine = all.filter { $0.pid == targetPid && $0.layer != 0 }
        let selfLevel = mine.map(\.layer).min()

        var foreignSame = 0
        var foreignFamily = 0
        if let level = selfLevel {
            for w in all where w.pid != targetPid {
                if w.layer == level { foreignSame += 1 }
                if abs(w.layer - level) <= familyBand { foreignFamily += 1 }
            }
        }

        return [
            "SELF_PID=\(targetPid)",
            "SELF_LEVEL=\(selfLevel.map(String.init) ?? "none")",
            "FOREIGN_SAME_LEVEL=\(foreignSame)",
            "FOREIGN_DESKTOP_FAMILY=\(foreignFamily)",
            "PID_CLAIM_REQUIRED=\(foreignSame >= 1 ? 1 : 0)",
            // 同一族（层级在我方 \u00b1familyBand 内）里的外来窗口数 —— 严格同层可能为 0，
            // 但这一族里的窗口只按层级认领同样会认错。两个数都给，不合并成一个。
            "PID_CLAIM_REQUIRED_BAND=\(foreignFamily >= 1 ? 1 : 0)",
            "WINDOWS_TOTAL=\(all.count)",
            "OWNED_WINDOW_COUNT=\(mine.count)",
            "FOREIGN_OWNERS=\(foreignOwners(all: all, selfLevel: selfLevel, targetPid: targetPid))",
            "D09_NOTE=ORDER 判定（我方层是否严格低于图标层）由 .planning/spike/WindowProbe.swift 承担；产品侧只负责按 pid 认领；PID_CLAIM_REQUIRED 数的是层级完全相同者，PID_CLAIM_REQUIRED_BAND 数的是同族者",
        ]
    }

    // MARK: - 几何内缩（D-08）

    /// 桌面层窗口相对 `NSScreen.main.frame` 的四个内缩整数（允许为负）。
    ///
    /// ⚠️ 坐标系陷阱：`CGWindowList` 的 bounds 原点在**主屏左上角**，
    /// `NSScreen.frame` 原点在**全局左下角**。不翻转直接相减得到的数是错的 ——
    /// 全屏场景复现过一次这个坑。
    public static func insetReport(targetPid: Int) -> [String] {
        let all = listWindows()
        guard let screen = NSScreen.main else {
            return ["INSET_RECORDED=0", "INSET_FAIL_REASON=no_main_screen"]
        }
        guard let w = all.filter({ $0.pid == targetPid && $0.layer != 0 }).first else {
            return ["INSET_RECORDED=0", "INSET_FAIL_REASON=no_owned_window"]
        }
        // screens[0] 是带菜单栏的那块屏，也就是全局原点所在的那块。
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let flippedY = primaryHeight - w.bounds.origin.y - w.bounds.height
        let win = CGRect(x: w.bounds.origin.x, y: flippedY, width: w.bounds.width, height: w.bounds.height)
        let s = screen.frame

        return [
            "INSET_LEFT=\(Int((win.minX - s.minX).rounded()))",
            "INSET_TOP=\(Int((s.maxY - win.maxY).rounded()))",
            "INSET_RIGHT=\(Int((s.maxX - win.maxX).rounded()))",
            "INSET_BOTTOM=\(Int((win.minY - s.minY).rounded()))",
            "INSET_RECORDED=1",
            "SCREEN_FRAME=\(fmt(s))",
            "WINDOW_FRAME=\(fmt(win))",
            "WINDOW_FRAME_RAW_CG=\(fmt(w.bounds))",
            "COORD_FLIP_TOP_LEFT_TO_BOTTOM_LEFT=\(fmt(height: primaryHeight))",
            "SELF_LEVEL=\(w.layer)",
            "SCREENS_COUNT=\(NSScreen.screens.count)",
            "INSET_NOTE=本会话实测值；D-08 记的 14/9 是 Phase 1 另一组会话的读数，本 Phase 只记录不据此断言",
        ]
    }

    // MARK: - 私有

    static func listWindows() -> [Entry] {
        let raw = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        var out: [Entry] = []
        for e in raw {
            // 数值字段在不同 SDK 上分别是 Int32 / Int，统一走 NSNumber.intValue。
            guard let l = e[kCGWindowLayer as String] as? NSNumber,
                  let p = e[kCGWindowOwnerPID as String] as? NSNumber else { continue }
            var rect = CGRect.zero
            if let r = e[kCGWindowBounds as String] as? [String: Any],
               let x = r["X"] as? Double, let y = r["Y"] as? Double,
               let w = r["Width"] as? Double, let h = r["Height"] as? Double {
                rect = CGRect(x: x, y: y, width: w, height: h)
            }
            out.append(Entry(layer: l.intValue, pid: p.intValue,
                             owner: e[kCGWindowOwnerName as String] as? String ?? "?",
                             bounds: rect))
        }
        // Apple 不承诺返回顺序，自己排才能复现。
        out.sort { $0.layer == $1.layer ? $0.pid < $1.pid : $0.layer < $1.layer }
        return out
    }

    static func foreignOwners(all: [Entry], selfLevel: Int?, targetPid: Int) -> String {
        guard let level = selfLevel else { return "none" }
        let names = Set(all.filter { $0.pid != targetPid && $0.layer == level }.map(\.owner))
        return names.isEmpty ? "none" : names.sorted().joined(separator: ",")
    }

    static func fmt(_ r: CGRect) -> String {
        "\(Int(r.minX.rounded())),\(Int(r.minY.rounded())),\(Int(r.width.rounded())),\(Int(r.height.rounded()))"
    }

    static func fmt(height: CGFloat) -> String {
        String(Int(height.rounded()))
    }
}

// MARK: - 独立可执行体
//
// 同一个文件在两处以不同方式编译：进产品库时下面这段被条件编译剥掉；
// `scripts/run-probe.sh` 加 -DPIC_WINDOW_PROBE_MAIN 现编译成一次性可执行文件，
// 拿到产品进程的 pid 后对它取证。产品代码一行也不进 spike 目录，反向也不破。
#if PIC_WINDOW_PROBE_MAIN
@main
struct PicWindowProbeMain {
    static func main() {
        var targetPid = Int(ProcessInfo.processInfo.processIdentifier)
        var mode = "claim"
        let args = CommandLine.arguments
        var i = 1
        while i < args.count {
            if args[i] == "--pid", i + 1 < args.count, let v = Int(args[i + 1]) {
                targetPid = v; i += 2
            } else if args[i] == "--inset" {
                mode = "inset"; i += 1
            } else {
                i += 1
            }
        }
        for l in (mode == "inset"
                  ? WindowProbe.insetReport(targetPid: targetPid)
                  : WindowProbe.claimReport(targetPid: targetPid)) {
            print(l)
        }
    }
}
#endif
#endif