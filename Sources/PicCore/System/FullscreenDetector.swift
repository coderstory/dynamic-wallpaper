// 全屏 / 满覆盖检测（事件 + 轮询双驱动）。
// 语义（用户拍板）：**屏幕被应用窗口铺满就该让路** —— 原生全屏和「最大化」 alike。
// 因此判定 = 覆盖率 ≥ 1.0，不再要求几何之外的事件信号：最大化 / 还原这个动作本身
// 不产生 Space 或前台切换事件，合取式设计会让「盖住了却还在播」的状态悬到下一次
// 事件才纠正。覆盖变化的捕捉靠三件事：Space 变更、前台应用变更、2 秒轮询。
//
// 坐标系注意：coverage 以 `visibleFrame` 为参照（分母不含菜单栏 / Dock），最大化窗口
// 内缩补偿后恰好 1.000 —— 这正是想要的：最大化 = 让路。
// 本进程自己的窗口（壁纸层 / 设置窗 / 弹层）按 pid 排除，不会自己挡自己。

import Foundation
import AppKit
import CoreGraphics


public enum FullscreenVerdict {
    /// 判定就是几何本身：满覆盖即让路。**没有阈值旋钮** —— 唯一的常量在
    /// `FullscreenGeometryReference.covering`（1.0，封顶后的满分）。
    public static func verdict(covering: Bool) -> Bool { covering }
}


/// 一次几何采样。屏幕与可见框由调用方注入，单测因此不必依赖窗口服务器。
public struct ScreenGeometry: Equatable, Sendable {
    public var frame: ScreenRect
    public var visible: ScreenRect

    public init(frame: ScreenRect, visible: ScreenRect) {
        self.frame = frame
        self.visible = visible
    }

    /// 默认读 `NSScreen.main`。本机单屏；多屏留给以后 —— 那时选哪块屏本身就是一个待定决策。
    public static func current() -> ScreenGeometry? {
        guard let s = NSScreen.main else { return nil }
        let f = s.frame
        let v = s.visibleFrame
        return ScreenGeometry(
            frame: ScreenRect(x: Double(f.origin.x), y: Double(f.origin.y),
                              w: Double(f.width), h: Double(f.height)),
            visible: ScreenRect(x: Double(v.origin.x), y: Double(v.origin.y),
                                w: Double(v.width), h: Double(v.height)))
    }
}

/// 几何参考值：覆盖率到这个数才算「几何足够」。
///
/// 它**不是判定阈值**：调到 0 也不会让几何单独判全屏，调到 1 也一样不会。
/// 它唯一的作用是定义「covering」这个布尔量在什么时刻为真。
public enum FullscreenGeometryReference {
    public static let covering = 1.0
}

/// 全屏 / 满覆盖检测。只回答「此刻屏幕是否被铺满」，不决定播放（veto 集合由 `HoldArbiter` 独占）。
@MainActor
public final class FullscreenDetector {
    public private(set) var isRunning = false

    /// 轮询周期。最大化 / 还原不产生 Space 或前台事件，靠它捕捉覆盖变化。
    private static let pollInterval: Duration = .seconds(2)

    private let center: NSWorkspace
    private let geometryReader: () -> ScreenGeometry?
    private let sampleReader: () -> [WindowRectSample]
    private let inset: DesktopWindowInset

    /// `start()` 注册 3 个观察者 + 1 个轮询 Task，token 存数组；重算只读值不注册新观察者。
    private var tokens: [NSObjectProtocol] = []
    private var pollTask: Task<Void, Never>?

    public init(workspace: NSWorkspace = .shared,
                geometryReader: @escaping () -> ScreenGeometry? = { ScreenGeometry.current() },
                sampleReader: @escaping () -> [WindowRectSample] = { FullscreenDetector.currentWindowSamples() },
                inset: DesktopWindowInset = .measured1470x956) {
        self.center = workspace
        self.geometryReader = geometryReader
        self.sampleReader = sampleReader
        self.inset = inset
    }

    /// 注册观察者 + 启动轮询，然后**同步**跑一次重算 —— 与 `LockWatcher` 同一形状。
    /// 重复调用是幂等的。
    public func start(onChange: @escaping @Sendable (Bool) -> Void) {
        guard !isRunning else { return }

        // 事件负责「即时响应」；轮询负责「无事件的状态变化」（最大化 / 还原 / 拖动窗口）。
        let names = [
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didDeactivateApplicationNotification,
        ]
        tokens = names.map { name in
            center.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reevaluate(onChange: onChange) }
            }
        }
        isRunning = true

        reevaluate(onChange: onChange)
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                guard !Task.isCancelled else { return }
                self?.reevaluate(onChange: onChange)
            }
        }
    }

    /// 按 token 逐个注销、轮询取消后清空 —— 少任何一步都是泄漏或幽灵定时器。
    public func stop() {
        for token in tokens {
            center.notificationCenter.removeObserver(token)
        }
        tokens.removeAll()
        pollTask?.cancel()
        pollTask = nil
        isRunning = false
    }

    /// 唤醒路径与暂停路径走同一条：每次都重读当前值，不记边沿。
    private func reevaluate(onChange: (Bool) -> Void) {
        let covering: Bool
        if let g = geometryReader() {
            let coverage = FullscreenGeometry.aggregate(samples: sampleReader(),
                                                        visible: g.visible,
                                                        screenFrameHeight: g.frame.h,
                                                        inset: inset)
            covering = coverage.global >= FullscreenGeometryReference.covering
        } else {
            //  读不到屏幕就读不到几何。判「没满覆盖」而不是猜一个数 —— 编一个数会把「读不到」
            // 与「没满覆盖」抹成一件。
            covering = false
        }

        onChange(FullscreenVerdict.verdict(covering: covering))
    }
}


extension FullscreenDetector {
    /// 枚举 layer 0、alpha > 0、且**不属于本进程**的窗口矩形。
    ///
    ///  按 PID 认领，不按 owner 名：同机有别的 app 来自同一个可执行文件， 按名字排除会把它一起滤掉。
    /// 字段白名单：pid / layer / alpha / bounds —— **绝不读标题**，标题可能含用户文件名。
    nonisolated public static func currentWindowSamples() -> [WindowRectSample] {
        enumerateWindowEntries().map { WindowRectSample(pid: $0.pid, raw: $0.raw) }
    }

    /// 枚举用的内部记录。`owner` 只参与排序，不参与判定。
    struct WindowEntry {
        var pid: Int
        var owner: String
        var layer: Int
        var alpha: Double
        var raw: ScreenRect
    }

    nonisolated static func enumerateWindowEntries(excludingSelf: Bool = true) -> [WindowEntry] {
        let raw = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        let me = ProcessInfo.processInfo.processIdentifier
        var out: [WindowEntry] = []
        for e in raw {
            guard let layerNum = e[kCGWindowLayer as String] as? NSNumber,
                  let pidNum = e[kCGWindowOwnerPID as String] as? NSNumber else { continue }
            let layer = layerNum.intValue
            guard layer == 0 else { continue }
            let alpha = (e[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 0
            guard alpha > 0 else { continue }
            let pid = pidNum.intValue
            if excludingSelf, pid == me { continue }
            let owner = e[kCGWindowOwnerName as String] as? String ?? "?"
            var b = ScreenRect(x: 0, y: 0, w: 0, h: 0)
            if let r = e[kCGWindowBounds as String] as? [String: Any],
               let x = (r["X"] as? NSNumber)?.doubleValue, let y = (r["Y"] as? NSNumber)?.doubleValue,
               let w = (r["Width"] as? NSNumber)?.doubleValue, let h = (r["Height"] as? NSNumber)?.doubleValue {
                b = ScreenRect(x: x, y: y, w: w, h: h)
            }
            out.append(WindowEntry(pid: pid, owner: owner, layer: layer, alpha: alpha, raw: b))
        }
        out.sort { a, b2 in a.pid != b2.pid ? a.pid < b2.pid : a.owner < b2.owner }
        return out
    }
}
