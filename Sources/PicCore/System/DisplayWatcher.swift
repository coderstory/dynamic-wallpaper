// DisplayWatcher.swift —— 显示器熄屏（PAUSE-03）与系统睡眠（PAUSE-04）的信号源（D-01：事件通知，不是轮询）。
//
// ── 为什么两个 reason 住在一个类型里 ────────────────────────────────────
//
// `CGDisplayIsAsleep` / `CGDisplayRegisterReconfigurationCallback` 与
// `NSWorkspace.willSleepNotification` / `didWakeNotification` 都属显示/电源域，
// 且共享同一条「重算」路径。拆成两个类型会让 PITFALLS Pitfall 7 的
// 「暂停与恢复走同一个 `re-evaluate()`」这条规则写两遍，两遍迟早漂移。
//
// ── 分层红线（D-09）────────────────────────────────────────────────────
//
// 本文件**零 AVFoundation**、不持有播放端引用、也不出现仲裁器的类型名 ——
// 它只产出 `DisplaySignals`，「拆成两次 `set`」的接线由装配层做（Plan 03-05）。
// `test.sh` 的「System/ 四个 Watcher 零 AVFoundation」每次重验这条。
//
// ── D-01：事件驱动，零轮询 ──────────────────────────────────────────────
//
// 本文件里没有任何定时器。两个信号位的来源：
//   displayAsleep   ← 重配置回调 / 睡眠回调触发时**重读** `CGDisplayIsAsleep(CGMainDisplayID())`
//   systemSleeping  ← `willSleep` / `didWake` 这一对通知（内存里的一个布尔量）
// Phase 2 实测 `.app` 下显示刷新回调仍是降级路径（`DRIVER=timer_fallback_hz30`，27 Hz，
// W-2026-10-03-11），逐帧轮询这条路在原理上就已排除。
//
// ⚠️ 唯一的内部状态是下面那一个 `Bool`。它**只**由上面那对通知切换，不来自任何采样 ——
//    采样一个布尔量再与通知混用，就等于凭空多出一个真相源。
//
// ── ⚠️ 与计划威胁模型的口径更正（PLAN_DEVIATION，见 03-03-SUMMARY）──────
//
// `03-03-PLAN.md` 的 T-03-10 写「该回调一旦注册就绑定在 `CGMainDisplayID()` 上」。
// 本机 SDK 实测**不成立**：`CGDisplayConfiguration.h:235` 的真实声明是
//
//     CGError CGDisplayRegisterReconfigurationCallback(
//         CGDisplayReconfigurationCallBack __nullable callback,
//         void * __nullable userInfo)
//
// —— **没有 display 参数**，注册与摘除都是**进程级**的。本实现按真实签名走：
//   后果的方向不变（摘不掉 = 进程内永久泄漏，必须配对），但「按 display 摘」那种写法根本编译不过。
//
// ── C 回调 → 闭包的桥 ───────────────────────────────────────────────────
//
// C 函数指针带不了 Swift 上下文，所以用一张全局表把 C 回调转回闭包 ——
// 既然注册本来就是进程级的，一张全局表正好对上真实语义。
// 投递线程文档没有承诺，一律 hop 回主队列，不做隔离假设。
//
// ⚠️ 两个 `NSWorkspace` 观察者用 `queue: .main`（与 `FullscreenDetector` 同形）。
//    代价：`willSleep` 投递与进程真正进入睡眠之间的间隔未在本会话实测
//    （屏幕锁着，且不允许无人值守地让机器睡）。该条已登记进 `.planning/WINDOWS.md`，
//    交给 Phase 7 的 20 轮休眠/唤醒去量。本文件不假装测过它。
//
// ── 启动即重算（装配层的启动契约）────────────────────────────────────────
//
// `willSleep` / `didWake` / 重配置回调**都只在跃迁时投递**。本会话既不熄屏也不睡眠，
// 等不到跃迁；`start()` 若只注册观察者，装配层读到的 `DisplaySignals` 会是默认的
// `(false, false)`，而 `evidence/display-sleep-signals.log` 的 `CGDisplay_IS_ASLEEP` 行
// 记着本机启动那一刻熄屏位**本来就是 true** —— 那条契约在本机不是形式主义。
// 所以 `start()` 在注册完之后**必须**跑一次 `re-evaluate()`，
// 让 `onChange` 在 `start()` 返回前就被调用过一次。
// 同形契约见 03-01 的 `LockWatcher.start()` 与 03-04 的 `PowerWatcher.start()`。

import Foundation
import AppKit
import CoreGraphics

// MARK: - 信号（纯值，零依赖）

/// 熄屏与睡眠的当前值。接线方（Plan 03-05）拆成两次 `set`。
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

// MARK: - 重配置回调的注入缝

/// 重配置回调的注册 / 摘除口。抽成协议是为了让「重配置 → 重算」这条路径可被单测驱动：
/// 真机跑一次热插拔才能验，但单测必须能在**不拔线**的情况下打同一条路径。
public protocol DisplayReconfigurationHook: AnyObject {
    /// 注册；返回是否注册成功。
    @discardableResult
    func register(_ onReconfigured: @escaping () -> Void) -> Bool
    /// 摘除。必须与 `register` 严格配对（Pitfall 4）。
    func unregister()
}

/// C 函数指针带不了 Swift 上下文 → 一张全局表把 C 回调转回闭包。
private let reconfigTableLock = NSLock()
private var reconfigHandlers: [() -> Void] = []

/// C ABI 的回调（`@convention(c)`，不能捕获上下文）。
private let reconfigTrampoline: CGDisplayReconfigurationCallBack = { _, _, _ in
    let handler = reconfigTableLock.withLock { reconfigHandlers.first }
    guard let handler else { return }
    // 文档没有承诺投递线程 —— 一律 hop 回主队列，不在这里做隔离假设。
    DispatchQueue.main.async {
        MainActor.assumeIsolated { handler() }
    }
}

/// 真机实现：直接调 CoreGraphics 的那两个公开函数（`CGDisplayConfiguration.h:235`）。
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

// MARK: - Watcher

/// 熄屏 + 睡眠的唯一信号源（D-09：只产出信号，不碰仲裁器、不碰播放器）。
@MainActor
public final class DisplayWatcher {
    public private(set) var isRunning = false
    /// `CGDisplayRegisterReconfigurationCallback` 的返回值 —— 探针与单测都读它。
    public private(set) var isReconfigurationRegistered = false

    /// 睡眠通知名。公开成常量，供装配层接线与探针打印**确切**名字
    /// （本机实测 rawValue = `NSWorkspaceWillSleepNotification`）。
    public static let sleepNotificationName = NSWorkspace.willSleepNotification
    /// 唤醒通知名（本机实测 rawValue = `NSWorkspaceDidWakeNotification`）。
    public static let wakeNotificationName = NSWorkspace.didWakeNotification

    private let center: NotificationCenter
    private let displayAsleepReader: () -> Bool
    private let reconfigurationHook: any DisplayReconfigurationHook

    /// 唯一的内部状态字段 —— 它由上面那对通知驱动，不来自任何采样（见文件头）。
    private var systemSleeping = false

    private var onChange: ((DisplaySignals) -> Void)?
    /// Pitfall 4：注册与注销严格配对，token 存数组，`stop()` 逐个摘。
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
    /// 三个入口（睡眠、唤醒、重配置）都汇入同一个 `re-evaluate()`，不各写各的
    /// —— 否则唤醒路径与暂停路径会不对称（Pitfall 7）。
    /// 重复调用是幂等的。
    public func start(onChange: @escaping (DisplaySignals) -> Void) {
        guard !isRunning else { return }
        self.onChange = onChange

        let sleepToken = center.addObserver(
            forName: Self.sleepNotificationName, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.systemSleeping = true
                self.`re-evaluate`()
            }
        }
        let wakeToken = center.addObserver(
            forName: Self.wakeNotificationName, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.systemSleeping = false
                self.`re-evaluate`()
            }
        }
        tokens = [sleepToken, wakeToken]

        reconfigurationRegistered = reconfigurationHook.register { [weak self] in
            MainActor.assumeIsolated { self?.`re-evaluate`() }
        }
        isReconfigurationRegistered = reconfigurationRegistered
        isRunning = true

        // 启动即重算：不依赖任何跃迁（本会话既不熄屏也不睡眠，等不到跃迁）。
        `re-evaluate`()
    }

    /// token 逐个注销 + 摘掉重配置回调 —— 少任何一步都是常驻泄漏（T-03-10）。
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

    /// **唯一**的重算与回调出口。暂停与恢复走的是同一条路径（Pitfall 7）。
    /// 这里不做去重 —— 幂等是仲裁器那一层的职责，信号源只管如实重算。
    private func `re-evaluate`() {
        onChange?(currentSignals())
    }
}
