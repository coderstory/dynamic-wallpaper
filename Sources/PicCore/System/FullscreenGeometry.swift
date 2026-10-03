// FullscreenGeometry.swift —— 全屏几何的**纯值**计算层。Plan 03-02 T1。
//
// 文件头必须说清的三件事（缺一件，下一个读者就会把判定搬回几何层）：
//
// ① 本文件**不含任何判定阈值**。
//    coverage 仍然算、仍然打出来，但「算出来是多少」到「判不判全屏」之间隔着
//    `FullscreenDetector`（T2）。D-02 的核心是几何不得单独生效，所以阈值不在这里 ——
//    一旦阈值落回这一层，"换个阈值"就会重新变成"能单独判全屏"的旋钮。
//
// ② 坐标系方向（D-04）：`CGWindowListCopyWindowInfo` 报的 bounds 是**左上角原点**，
//    `NSScreen.frame` / `visibleFrame` 是**左下角原点**。两者不可直接相减，
//    必须先 `flipTopLeftToBottomLeft` 翻到同一原点。写反会让 coverage 恒为 0。
//
// ③ 内缩常量 14pt / 9pt 的来源：`.planning/phases/02-playback-core/evidence/inset.log`
//    的 `INSET_LEFT/TOP/RIGHT/BOTTOM` 四行，实测自一扇 `-2147483623` 层 borderless
//    窗口被 `CGWindowList` 报成 `14,9,1442,938`、而 `NSScreen.frame` 是 `0,0,1470,956`。
//    叠加刘海 33pt 共 47pt。**D-08 在另一组会话里独立测到过同一组数字** ——
//    两组读数来源不同、结论相同，不等于只有一次测量。
//
// ⚠️ 处理顺序写死（D-03 + D-04）：**先内缩补偿，再翻转，最后与 visibleFrame 求交。**
//    反过来做结果不同：内缩是「桌面层窗口比屏幕框系统性小一圈」，要在原始矩形上
//    向外扩；翻转只换原点不换尺寸，两者不可交换。
//
// 分层红线（D-09）：本文件**零 AppKit、零 CoreGraphics、零 AVFoundation**。
// `NSScreen` / `CGWindowList` 的读取在 `FullscreenDetector` 里；这里只处理传进来的数。
// 这不是洁癖 —— 几何层不碰框架，才能在锁屏会话下被单测覆盖全部基准，
// 不需要任何窗口服务器配合。

import Foundation

// MARK: - 值类型

/// 一个矩形。坐标系的原点由调用方的字段名语义决定：
/// `raw`（`WindowRectSample` 里）是左上角，`visible`（`aggregate` 参数）是左下角。
public struct ScreenRect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double

    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }

    /// 面积。相交的宽高可以是负的（不相交），一律夹到 0 —— 负面积会让 coverage 反向漂移。
    public var area: Double { max(0, w) * max(0, h) }
}

/// D-03：桌面层 borderless 窗口在 `CGWindowList` 里的系统性内缩。
/// 来源 `.planning/phases/02-playback-core/evidence/inset.log`。
public struct DesktopWindowInset: Equatable, Sendable {
    public var left: Double
    public var top: Double
    public var right: Double
    public var bottom: Double

    public init(left: Double, top: Double, right: Double, bottom: Double) {
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
    }

    /// 本机实测值（1470×956 单屏）。**Phase 1 的 `--selftest` 用 `.zero`** ——
    /// 那三条基准量的是屏幕层窗口，没有桌面层内缩；带内缩的路径由单测第 4 条单独锁。
    public static let measured1470x956 = DesktopWindowInset(left: 14, top: 9, right: 14, bottom: 9)

    /// 不补偿。用途只有一个：与 Phase 1 `--selftest` 的数值逐条对齐。
    public static let zero = DesktopWindowInset(left: 0, top: 0, right: 0, bottom: 0)
}

/// 一扇窗口的几何样本。`raw` 是 `CGWindowList` **原样报的值**（左上角原点），
/// 不带任何内缩补偿 —— 补偿是 `aggregate` 的事。
public struct WindowRectSample: Equatable, Sendable {
    public var pid: Int
    public var raw: ScreenRect

    public init(pid: Int, raw: ScreenRect) {
        self.pid = pid
        self.raw = raw
    }
}

/// 聚合结果。
public struct CoverageResult: Equatable, Sendable {
    /// 按 pid 聚合后的全局覆盖率，封顶 1.0（D-10 之外的纯数值量）。
    public var global: Double
    /// 贡献了 `global` 的那个 pid。
    public var globalPid: Int
    /// 该 pid 名下的矩形数。
    public var rectCount: Int
    /// **被 Phase 1 明确否决的朴素口径**：同一 pid 下每个矩形单独算覆盖率的最大值。
    /// 它存在**只为让「按 pid 聚合」可被单测看见**，不是目标值。
    /// `split` 基准上 `global=1.000` 而 `perWindowBest=0.600`，两者相等即聚合退化。
    public var perWindowBest: Double

    public init(global: Double = 0, globalPid: Int = -1, rectCount: Int = 0, perWindowBest: Double = 0) {
        self.global = global
        self.globalPid = globalPid
        self.rectCount = rectCount
        self.perWindowBest = perWindowBest
    }
}

// MARK: - 几何

/// 全屏几何的纯函数集合。输入是调用方传进来的数，输出是数。
/// 没有读取、没有全局状态、没有副作用 —— 这正是它能被锁屏会话下的单测全覆盖的原因。
public enum FullscreenGeometry {

    // MARK: 原子操作

    /// D-04：左上角原点 → 左下角原点。方向固定 —— 写反会让 coverage 恒为 0。
    public static func flipTopLeftToBottomLeft(_ b: ScreenRect, screenH: Double) -> ScreenRect {
        ScreenRect(x: b.x, y: screenH - (b.y + b.h), w: b.w, h: b.h)
    }

    /// 两矩形求交。不相交时 `w` / `h` 为负，由 `ScreenRect.area` 夹到 0。
    public static func intersect(_ a: ScreenRect, _ b: ScreenRect) -> ScreenRect {
        let x1 = max(a.x, b.x)
        let y1 = max(a.y, b.y)
        let x2 = min(a.x + a.w, b.x + b.w)
        let y2 = min(a.y + a.h, b.y + b.h)
        return ScreenRect(x: x1, y: y1, w: x2 - x1, h: y2 - y1)
    }

    /// D-03 内缩补偿：把 `CGWindowList` 报的**桌面层**窗口矩形向四个方向各外扩对应的 inset。
    ///
    /// 语义写死 —— 先扩，再交给 `intersect` 与 `visibleFrame` 求交：
    ///   `x -= left`、`y -= top`、`w += left + right`、`h += top + bottom`
    /// D-03 要求「先处理内缩」；顺序反过来结果就不同。
    ///
    /// 14/9 是**四边对称**的，所以 `top` 与 `bottom` 相等、`left` 与 `right` 相等；
    /// 但四个字段仍然分开存 —— 一旦某台机器出现非对称内缩（例如只在一侧有 Dock），
    /// 这个函数不用改形状。
    public static func compensatingInset(_ raw: ScreenRect, by inset: DesktopWindowInset) -> ScreenRect {
        ScreenRect(x: raw.x - inset.left,
                   y: raw.y - inset.top,
                   w: raw.w + inset.left + inset.right,
                   h: raw.h + inset.top + inset.bottom)
    }

    // MARK: 聚合

    /// D-03 + D-04 + 按 pid 聚合，三件事在这里一次做完。**这里不判全屏。**
    ///
    /// 口径逐条照抄 Phase 1 的 `.planning/spike/FullscreenProbe.swift` 的 `aggregate`：
    ///   ① 按 `pid` 分组，组内矩形顺序不影响结果（求和）
    ///   ② 每个矩形**先内缩补偿 → 再翻转到左下角原点 → 再与 `visibleFrame` 求交**
    ///   ③ 组内求和 → 除以 `visibleFrame` 面积 → `min(1.0, …)` 封顶
    ///   ④ 不同 pid 之间取**最大值**当全局 coverage
    ///
    /// ②③ 一起是承重的：Chrome 同 pid 双窗口
    /// （`0,33,1470,124` + `0,121,1470,835`）逐窗口口径必漏判，
    /// Phase 1 的 `SELFTEST_PROOF` 行把这条写成了显式证据。
    ///
    /// - Parameters:
    ///   - samples: 窗口矩形样本，`raw` 为 `CGWindowList` 原样值（**调用方负责去重/过滤**）。
    ///   - visible: `NSScreen.visibleFrame`，左下角原点。分母用它不用 `frame`：
    ///     `frame` 当分母时真全屏会因刘海而永远差一点（PITFALLS Pitfall 2(a)）。
    ///   - screenFrameHeight: 翻转用的屏幕高（D-04）。
    ///   - inset: 桌面层内缩补偿。Phase 1 `--selftest` 传 `.zero`。
    public static func aggregate(samples: [WindowRectSample],
                                 visible: ScreenRect,
                                 screenFrameHeight: Double,
                                 inset: DesktopWindowInset) -> CoverageResult {
        var groups: [Int: [ScreenRect]] = [:]
        for s in samples {
            groups[s.pid, default: []].append(s.raw)
        }

        let vArea = visible.area
        var out = CoverageResult()

        // pid 排序遍历：coverage 相同时取 pid 小的那个，结果不随字典哈希顺序漂移。
        for pid in groups.keys.sorted() {
            let rects = groups[pid]!
            var sum = 0.0
            var best = 0.0
            for raw in rects {
                let compensated = compensatingInset(raw, by: inset)
                let flipped = flipTopLeftToBottomLeft(compensated, screenH: screenFrameHeight)
                let a = intersect(flipped, visible).area
                sum += a
                best = max(best, vArea > 0 ? a / vArea : 0)
            }
            let cov = vArea > 0 ? min(1.0, sum / vArea) : 0
            if cov > out.global {
                out.global = cov
                out.globalPid = pid
                out.rectCount = rects.count
                out.perWindowBest = best
            }
        }
        return out
    }
}