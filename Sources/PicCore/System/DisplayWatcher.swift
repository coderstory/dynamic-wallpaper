// 显示器熄屏与系统睡眠的信号源（事件通知，不是轮询）。零 AVFoundation，只产出 `DisplaySignals`，
// 不碰仲裁器和播放器。
// 唯一的内部状态是那一个 `Bool`，只由 `willSleep` / `didWake` 切换，不来自任何采样（采样再与通知
// 混用就等于凭空多出一个真相源）；`start()` 注册完之后必须同步跑一次 `re-evaluate()`，这几个信号
// 都只在跃迁时投递，等不到。

import Foundation
import AppKit
import CoreGraphics


/// 熄屏与睡眠的当前值。接线方拆成两次 `set`。
public struct DisplaySignals: Equatable, Sendable {
    /// 当前主显示器是否熄屏。每次重算都**重读** `CGDisplayIsAsleep`，不靠「边沿」记忆。
    public var displayAsleep: Bool      // → HoldReason.displayAsleep
    /// 系统是否正在睡眠。只由 `willSleep` / `didWake` 这一对通知切换。
    public var systemSleeping: Bool     // → HoldReason.systemSleeping

    public init(displayAsleep: Bool, systemSleeping: Bool) {
        self.displayAsleep = displayAsleep
        self.systemSleeping = systemSleeping
    }
}


/// 重配置回调的注册 / 摘除口。抽成协议是为了让「重配置 → 重算」这条路径可被单测驱动：
/// 真机跑一次热插拔才能验，但单测必须能在**不拔线**的情况下打同一条路径。
public protocol DisplayReconfigurationHook: AnyObject {
    /// 注册；返回是否注册成功。
    @discardableResult
    func register(_ onReconfigured: @escaping () -> Void) -> Bool
    /// 摘除。必须与 `register` 严格配对 —— 注册是**进程级**的（签名里没有 display 参数），
    /// 漏掉配对就是进程内永久泄漏。
    func unregister()
}

/// C 函数指针带不了 Swift 上下文 → 一张全局表把 C 回调转回闭包。
private let reconfigTableLock = NSLock()
private nonisolated(unsafe) var reconfigHandlers: [() -> Void] = []

/// C ABI 的回调（`@convention(c)`，不能捕获上下文）。
private let reconfigTrampoline: CGDisplayReconfigurationCallBack = { _, _, _ in
    let handler = reconfigTableLock.withLock { reconfigHandlers.first }
    guard let handler else { return }
    // 文档没有承诺投递线程 —— 一律 hop 回主队列，不在这里做隔离假设。
    DispatchQueue.main.async {
        MainActor.assumeIsolated { handler() }
    }
}

/// 真机实现：直接调 CoreGraphics 的那两个公开函数。注册与摘除都是进程级的，
/// 所以下面那张全局单槽表正对真实语义。
public final class SystemDisplayReconfigurationHook: DisplayReconfigurationHook {
    public init() {}

    @discardableResult
    public func register(_ onReconfigured: @escaping () -> Void) -> Bool {
        reconfigTableLock.withLock { reconfigHandlers.append(onReconfigured) }
        return CGDisplayRegisterReconfigurationCallback(reconfigTrampoline, nil) == .success
    }

    public func unregister() {
        _ = CGDisplayRemoveReconfigurationCallback(reconfigTrampoline, nil)
        reconfigTableLock.withLock { reconfigHandlers.removeAll() }
    }
}


/// 熄屏 + 睡眠的唯一信号源（只产出信号，不碰仲裁器、不碰播放器）。
@MainActor
public final class DisplayWatcher {
    public private(set) var isRunning = false
    /// `CGDisplayRegisterReconfigurationCallback` 的返回值 —— 单测读它。
    public private(set) var isReconfigurationRegistered = false

    /// 睡眠通知名。公开成常量，供装配层接线与单测断言**确切**名字。
    public static let sleepNotificationName = NSWorkspace.willSleepNotification
    /// 唤醒通知名。
    public static let wakeNotificationName = NSWorkspace.didWakeNotification

    private let center: NotificationCenter
    private let displayAsleepReader: () -> Bool
    private let reconfigurationHook: any DisplayReconfigurationHook

    /// 唯一的内部状态字段 —— 由那对通知驱动，不来自任何采样。
    private var systemSleeping = false

    private var onChange: ((DisplaySignals) -> Void)?
    /// 注册与注销严格配对，token 存数组，`stop()` 逐个摘。
    private var tokens: [NSObjectProtocol] = []
    private var reconfigurationRegistered = false

    public init(notificationCenter: NotificationCenter = NotificationCenter.default,
                displayAsleepReader: @escaping () -> Bool = { CGDisplayIsAsleep(CGMainDisplayID()) != 0 },
                reconfigurationHook: any DisplayReconfigurationHook = SystemDisplayReconfigurationHook()) {
        self.center = notificationCenter
        self.displayAsleepReader = displayAsleepReader
        self.reconfigurationHook = reconfigurationHook
    }

    /// 注册两个 `NSWorkspace` 观察者 + 一个重配置回调，然后**同步**重算一次，再置 `isRunning`。
    ///
    /// 顺序固定为「先注册后重算」：反过来会漏掉注册与重算之间发生的那次跃迁。
    /// 三个入口（睡眠、唤醒、重配置）都汇入同一个 `re-evaluate()`，否则唤醒路径与暂停路径不对称。
    /// 重复调用是幂等的。
    public func start(onChange: @escaping (DisplaySignals) -> Void) {
        guard !isRunning else { return }
        self.onChange = onChange

        // 睡眠/唤醒两个观察者仅差 systemSleeping 置位，抽成一个注册函数。
        tokens = [(Self.sleepNotificationName, true), (Self.wakeNotificationName, false)].map { name, sleeping in
            center.addObserver(forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.systemSleeping = sleeping
                    self.`re-evaluate`()
                }
            }
        }

        reconfigurationRegistered = reconfigurationHook.register { [weak self] in
            MainActor.assumeIsolated { self?.`re-evaluate`() }
        }
        isReconfigurationRegistered = reconfigurationRegistered
        isRunning = true

        // 启动即重算：这几个信号都只在跃迁时投递。
        `re-evaluate`()
    }

    /// token 逐个注销 + 摘掉重配置回调 —— 少任何一步都是常驻泄漏。
    public func stop() {
        for token in tokens {
            center.removeObserver(token)
        }
        tokens.removeAll()
        if reconfigurationRegistered {
            reconfigurationHook.unregister()
            reconfigurationRegistered = false
            isReconfigurationRegistered = false
        }
        onChange = nil
        isRunning = false
    }

    /// 此刻的两个信号位。`displayAsleep` 每次**现读**，不缓存。
    public func currentSignals() -> DisplaySignals {
        DisplaySignals(displayAsleep: displayAsleepReader(), systemSleeping: systemSleeping)
    }

    /// **唯一**的重算与回调出口，暂停与恢复走同一条。
    /// 这里不做去重 —— 幂等是仲裁器那一层的职责，信号源只管如实重算。
    private func `re-evaluate`() {
        onChange?(currentSignals())
    }
}
