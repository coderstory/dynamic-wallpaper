// 全屏几何的纯值计算层，零 AppKit/CoreGraphics/AVFoundation。不含任何判定阈值 —— 阈值归
// `FullscreenDetector`，否则「换个阈值」又变成能单独判全屏的旋钮。
// 坐标系：`CGWindowList` 的 bounds 左上角原点、`NSScreen` 左下角，不翻到同一原点 coverage 恒为 0。
// 顺序：先内缩补偿 → 再翻转 → 最后与 visibleFrame 求交。内缩要在原始矩形上向外扩、翻转只换原点
// 不换尺寸，两者不可交换。内缩 14/9 是实测值。

import Foundation


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

/// 桌面层 borderless 窗口在 `CGWindowList` 里的系统性内缩。
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

    /// 桌面层窗口相对屏幕框的内缩（1470×956 单屏实测）。`--selftest` 用 `.zero` ——
    /// 那三条基准量的是屏幕层窗口，没有桌面层内缩；带内缩的路径由单测第 4 条单独锁。
    public static let measured1470x956 = DesktopWindowInset(left: 14, top: 9, right: 14, bottom: 9)

    /// 不补偿。用途只有一个：与 `--selftest` 的数值逐条对齐。
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
    /// 按 pid 聚合后的全局覆盖率，封顶 1.0。
    public var global: Double
    /// 贡献了 `global` 的那个 pid。
    public var globalPid: Int
    /// 该 pid 名下的矩形数。
    public var rectCount: Int
    /// 同一 pid 下逐矩形算覆盖率的最大值。**不是**目标值，只为让「按 pid 聚合」可被单测看见。
    /// `split` 基准上 `global=1.000` 而 `perWindowBest=0.600`，两者相等即聚合退化。
    public var perWindowBest: Double

    public init(global: Double = 0, globalPid: Int = -1, rectCount: Int = 0, perWindowBest: Double = 0) {
        self.global = global
        self.globalPid = globalPid
        self.rectCount = rectCount
        self.perWindowBest = perWindowBest
    }
}


/// 全屏几何的纯函数集合：输入是调用方传进来的数，输出是数。无读取、无全局状态、无副作用。
public enum FullscreenGeometry {


    /// 左上角原点 → 左下角原点。方向固定，写反会让 coverage 恒为 0。
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

    /// 内缩补偿：把 `CGWindowList` 报的**桌面层**窗口矩形向四个方向各外扩对应的 inset，
    /// 先扩再交给 `intersect` 与 `visibleFrame` 求交。四个字段分开存是为了容纳非对称内缩
    /// （例如只在一侧有 Dock），函数形状不用改。
    public static func compensatingInset(_ raw: ScreenRect, by inset: DesktopWindowInset) -> ScreenRect {
        ScreenRect(x: raw.x - inset.left,
                   y: raw.y - inset.top,
                   w: raw.w + inset.left + inset.right,
                   h: raw.h + inset.top + inset.bottom)
    }


    /// 内缩补偿 + 翻转 + 按 pid 聚合，三件事在这里一次做完。**这里不判全屏。**
    ///
    /// 口径：按 `pid` 分组求和，除以 `visibleFrame` 面积后封顶 1.0，不同 pid 之间取最大值。
    /// 分组与求和一起是承重的：Chrome 同 pid 双窗口
    /// （`0,33,1470,124` + `0,121,1470,835`）逐窗口口径必漏判。
    ///
    /// - Parameters:
    ///   - samples: 窗口矩形样本，`raw` 为 `CGWindowList` 原样值（**调用方负责去重/过滤**）。
    ///   - visible: `NSScreen.visibleFrame`，左下角原点。分母用它不用 `frame`：真全屏会因刘海而永远差一点。
    ///   - screenFrameHeight: 翻转用的屏幕高。
    ///   - inset: 桌面层内缩补偿。`--selftest` 传 `.zero`。
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