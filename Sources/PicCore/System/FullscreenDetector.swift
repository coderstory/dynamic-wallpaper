// FullscreenDetector.swift —— 全屏检测（D-01：事件通知驱动，不是逐帧轮询）。
//
// 分层红线（D-09）：本文件**零 AVFoundation**，不出现 player。
// 单向流是 `FullscreenDetector → HoldArbiter.set(.fullscreen, active:) → PlaybackTarget.arbiterApply`。
//
// ── D-02 的落点（本文件存在的全部理由）────────────────────────────────────
//
// Phase 1 用实测证伪了纯几何阈值：
//   `FALSE_POSITIVE_OBSERVED=1 direction=safe_area_filled_but_not_fullscreen_scored_fullscreen`
// Ghostty(pid 1227) 与 CC Switch(pid 1228) 各把 visibleFrame(1470×833) 铺满 →
// coverage=1.000 被判成全屏，但两者 bounds 高 833 < 屏幕 frame 高 956，
// 结构上够不到刘海，**可证不是全屏**。coverage 已顶在 1.000 上限，调阈值改不了。
//
// 用户 2026-10-03 拍板走「几何之外加判别信号」，与几何取**合取**：
//     verdict = nonGeometricActive && covering
//
// ⚠️ **`FullscreenVerdict.verdict` 的函数体必须保持这个合取形状。**
//    把它改成几何单侧，Phase 1 那条假阳性立刻复活（用户在没全屏时壁纸永久暂停），
//    而纯几何层测不出来 —— 唯一能抓住它的就是注入式反向验证。
//
// ── `styleMask` 为什么不能当几何外信号（结构事实，不是推断）────────────────
//
// 编排器 2026-10-03 一手实测：`CGWindowListCopyWindowInfo` 返回的字典共 11 个 key
// （kCGWindowAlpha / Bounds / IsOnscreen / Layer / MemoryUsage / Name / Number /
// OwnerName / OwnerPID / SharingState / StoreType），**无任何 key 含 `tyle` 或 `ullScreen`**。
// → 公开 API 读不到**别的进程**窗口的 styleMask，D-02 的候选 ① 结构上不适用。
// Phase 1 探针读到过 styleMask，是因为它读的是**自己创建的那扇 NSWindow**。
// 本 plan 的字典键普查（`probe-fullscreen.sh` 落 evidence）把这条从推断变成实测。
//
// ⚠️ 因此本文件**绝不读窗口标题键**（T-03-02）：枚举输出的字段白名单固定为
//    pid / owner / layer / alpha / bounds / coverage —— 标题字段可能含用户文件名。
//
// ── 事件驱动（D-01）─────────────────────────────────────────────────────
//
// 订阅三个 `NSWorkspace` 公开通知：Space 变更 / 应用激活 / 应用失活。
// **每个通知都只当触发器**：收到后一律 `re-evaluate`() 重读当前几何，
// 不靠「边沿」记忆 —— 这条与 `LockWatcher` 的 T-03-01 处置同形。
// 每个信号位的语义是「**本次重算是被谁触发的 + 此刻几何如何**」，不是「某个跃迁发生过」。

import Foundation
import AppKit
import CoreGraphics

// MARK: - 判定（D-02）

/// 全屏判定的四个输入。全部由外部注入 —— 锁屏会话下四种组合都能单测覆盖，
/// 不需要真的切一次 Space 或激活一次应用。
public struct FullscreenSignals: Equatable, Sendable {
    /// 本次重算由 Space 变更通知触发，且此刻几何满覆盖。
    public var spaceChangedWhileFullyCovering: Bool
    /// 本次重算由前台应用激活/失活通知触发，且此刻几何满覆盖。
    public var frontmostAppChangedWhileFullyCovering: Bool
    /// 几何足够（coverage 达到几何参考值）。
    ///
    /// ⚠️ 这个值**单独成立时不构成判定**。它只是合取的第二项。
    public var covering: Bool

    public init(spaceChangedWhileFullyCovering: Bool,
                frontmostAppChangedWhileFullyCovering: Bool,
                covering: Bool) {
        self.spaceChangedWhileFullyCovering = spaceChangedWhileFullyCovering
        self.frontmostAppChangedWhileFullyCovering = frontmostAppChangedWhileFullyCovering
        self.covering = covering
    }

    /// 是否出现「几何之外」的可判别信号。
    ///
    /// ⚠️ W-2026-10-03-18（已登记的语义降级）：两个字段名里都编进了
    ///    `WhileFullyCovering`，所以本值恒蕴含「此刻几何满覆盖」。
    ///    D-02 字面要求的「几何外信号可独立触发暂停」在当前形状下**不可达**；
    ///    交付的是合取判定，不是独立触发。详见 `.planning/WINDOWS.md`。
    public var nonGeometricActive: Bool {
        spaceChangedWhileFullyCovering || frontmostAppChangedWhileFullyCovering
    }
}

public enum FullscreenVerdict {
    /// D-02 的落点：几何**不得单独**作为判定依据。
    ///
    /// 形状写死：`nonGeometricActive && covering`。
    /// 把函数体改成 `s.covering` 会让 T2 的注入式反向验证立刻转红 —— 那是
    /// 「合取没有被悄悄退回纯几何」的唯一机器证据。
    public static func verdict(_ s: FullscreenSignals) -> Bool {
        s.nonGeometricActive && s.covering
    }
}

// MARK: - 采集

/// 一次几何采样。屏幕与可见框由调用方注入，单测因此不必依赖窗口服务器。
public struct ScreenGeometry: Equatable, Sendable {
    public var frame: ScreenRect
    public var visible: ScreenRect

    public init(frame: ScreenRect, visible: ScreenRect) {
        self.frame = frame
        self.visible = visible
    }

    /// 默认读 `NSScreen.main`。本机单屏（`inset.log:SCREENS_COUNT=1`），
    /// 多屏留给 Phase 4/5 —— 那时 `NSScreen.main` 的选择本身就是一个待定决策。
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
/// ⚠️ 它**不是判定阈值**。判定是 `nonGeometricActive && covering` 的合取；
/// 把这个数调到 0 也不会让几何单独判全屏，把它调到 1 也一样不会。
/// 它唯一的作用是定义「covering」这个布尔量在什么时刻为真。
/// Phase 1 之所以栽在这里，正是因为几何量本身被直接当成了结论。
public enum FullscreenGeometryReference {
    public static let covering = 1.0
}

/// 全屏 → `Bool`。只回答「此刻是否全屏」，不决定播放（veto 集合由 `HoldArbiter` 独占）。
@MainActor
public final class FullscreenDetector {
    public private(set) var isRunning = false

    /// 本次重算由哪个信号触发。信号位由它派生 —— 不另存一份「边沿」。
    private enum Trigger: String {
        case start
        case space
        case frontmost
    }

    private let center: NSWorkspace
    private let geometryReader: () -> ScreenGeometry?
    private let sampleReader: () -> [WindowRectSample]
    private let inset: DesktopWindowInset
    /// 诊断输出（条件行 `FULLSCREEN_SIGNAL_ONLY`）。默认不输出，探针注入。
    private let emit: (String) -> Void

    private var lastTrigger: Trigger = .start
    private var lastCoverage: CoverageResult?

    /// T-03-08：`start()` 只注册 3 个观察者，token 存数组；`re-evaluate`() 只读值不注册新观察者。
    private var tokens: [NSObjectProtocol] = []

    public init(workspace: NSWorkspace = .shared,
                geometryReader: @escaping () -> ScreenGeometry? = { ScreenGeometry.current() },
                sampleReader: @escaping () -> [WindowRectSample] = { FullscreenDetector.currentWindowSamples() },
                inset: DesktopWindowInset = .measured1470x956,
                emit: @escaping (String) -> Void = { _ in }) {
        self.center = workspace
        self.geometryReader = geometryReader
        self.sampleReader = sampleReader
        self.inset = inset
        self.emit = emit
    }

    /// 注册三个观察者，然后**同步**跑一次重算 —— 与 `LockWatcher` 同一形状：
    /// 本会话屏幕一直锁着，没有任何 Space / 应用跃迁可等。
    public func start(onChange: @escaping (Bool) -> Void) {
        guard !isRunning else { return }

        let space = Notification.Name(NSWorkspace.activeSpaceDidChangeNotification.rawValue)
        let activate = Notification.Name(NSWorkspace.didActivateApplicationNotification.rawValue)
        let deactivate = Notification.Name(NSWorkspace.didDeactivateApplicationNotification.rawValue)

        let spaceToken = center.notificationCenter.addObserver(forName: space, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.`re-evaluate`(trigger: .space, onChange: onChange) }
        }
        let activateToken = center.notificationCenter.addObserver(forName: activate, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.`re-evaluate`(trigger: .frontmost, onChange: onChange) }
        }
        let deactivateToken = center.notificationCenter.addObserver(forName: deactivate, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.`re-evaluate`(trigger: .frontmost, onChange: onChange) }
        }
        tokens = [spaceToken, activateToken, deactivateToken]
        isRunning = true

        `re-evaluate`(trigger: .start, onChange: onChange)
    }

    /// 按 token 逐个注销后清空数组 —— 少这一步就是 observer 泄漏（T-03-08）。
    public func stop() {
        for token in tokens {
            center.notificationCenter.removeObserver(token)
        }
        tokens.removeAll()
        isRunning = false
    }

    /// 唤醒路径与暂停路径走同一条（Pitfall 7）：每次都重读当前值，不记边沿。
    private func `re-evaluate`(trigger: Trigger, onChange: (Bool) -> Void) {
        lastTrigger = trigger

        let samples = sampleReader()
        let coverage: CoverageResult
        let covering: Bool
        if let g = geometryReader() {
            coverage = FullscreenGeometry.aggregate(samples: samples,
                                                    visible: g.visible,
                                                    screenFrameHeight: g.frame.h,
                                                    inset: inset)
            covering = coverage.global >= FullscreenGeometryReference.covering
        } else {
            // 读不到屏幕就读不到几何。记 0 而不是猜 —— 编一个数会把「读不到」与「没满覆盖」
            // 两件事抹成一件（Pitfall 1 同形的观测纪律）。
            coverage = CoverageResult()
            covering = false
        }
        lastCoverage = coverage

        let signals = FullscreenSignals(
            spaceChangedWhileFullyCovering: trigger == .space && covering,
            frontmostAppChangedWhileFullyCovering: trigger == .frontmost && covering,
            covering: covering)

        // ⚠️ 条件行：本会话屏幕锁着且无 Space / 应用切换，`non_geometric` 恒为 0，
        // 跑不出这一行。**逻辑必须实现**（信号成立但几何不足是需要人看一眼的情形，
        // 不能静默吞掉），但它不得进 AC 的必达行清单 —— 否则会有人为了让判据变绿去制造事件。
        if signals.nonGeometricActive && !signals.covering {
            emit(String(format: "FULLSCREEN_SIGNAL_ONLY covering=%.3f non_geometric=1", coverage.global))
        }

        onChange(FullscreenVerdict.verdict(signals))
    }

    /// 最近一次重算的覆盖率。供装配层打日志用。
    public func currentCoverage() -> CoverageResult? { lastCoverage }

    /// 最近一次重算的信号位。供装配层打日志用。
    public func currentSignals() -> FullscreenSignals {
        let covering = lastCoverage.map { $0.global >= FullscreenGeometryReference.covering } ?? false
        return FullscreenSignals(
            spaceChangedWhileFullyCovering: lastTrigger == .space && covering,
            frontmostAppChangedWhileFullyCovering: lastTrigger == .frontmost && covering,
            covering: covering)
    }
}

// MARK: - 窗口枚举

extension FullscreenDetector {
    /// 枚举 layer 0、alpha > 0、且**不属于本进程**的窗口矩形。
    ///
    /// 按 PID 认领（D-08），不按 owner 名：同机有别的 app 来自同一个可执行文件，
    /// 按名字排除会把它一起滤掉。
    /// 字段白名单：pid / layer / alpha / bounds —— **不含标题**（T-03-02）。
    nonisolated public static func currentWindowSamples() -> [WindowRectSample] {
        enumerateWindowEntries().map { WindowRectSample(pid: $0.pid, raw: $0.raw) }
    }

    /// 枚举用的内部记录。`owner` 只用于给证据行标注进程名，不参与判定。
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

    /// 第一扇 layer 0 且 alpha > 0 的窗口的全部字典键名 —— D-02 候选 ① 的**实测**。
    ///
    /// 键名里含 `tyle`（忽略大小写）或 `ullScreen` 的行数为 0 ⇒ 公开 API 读不到别的进程的
    /// `styleMask`。`nil` 表示一扇候选窗口都没有（会话异常），返回空数组而不是编一个结论。
    nonisolated public static func firstOnscreenWindowDictionaryKeys() -> [String] {
        let raw = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        for e in raw {
            let layer = (e[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -1
            let alpha = (e[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? -1
            if layer == 0 && alpha > 0 {
                return e.keys.sorted()
            }
        }
        return []
    }

    /// 从键名表判定「styleMask 可得」的**纯函数**（单测直接喂夹具，不碰窗口服务器）。
    nonisolated public static func styleMaskKeyPresent(in keys: [String]) -> Bool {
        keys.contains { k in
            let l = k.lowercased()
            return l.contains("tyle") || l.contains("ullscreen")
        }
    }
}