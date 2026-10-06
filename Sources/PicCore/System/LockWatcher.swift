// 锁屏信号的唯一来源（事件通知，不是轮询）。通知只当触发器，收到后一律重读会话字典的
// CGSSessionScreenIsLocked —— 投递方不可信。start() 注册之后同步回调一次：跃迁通知，锁屏会话下等不到。

import Foundation
import CoreGraphics

/// 锁屏信号的通知名。产品默认用系统那两个未文档化的名字；绝不往系统通知名投合成事件，
/// 同机的其它壁纸 app 会一起被暂停。
public struct LockSignalNames: Sendable, Equatable {
    public var locked: String
    public var unlocked: String

    public init(locked: String, unlocked: String) {
        self.locked = locked
        self.unlocked = unlocked
    }

    /// 产品默认值。
    public static let system = LockSignalNames(
        locked: "com.apple.screenIsLocked",
        unlocked: "com.apple.screenIsUnlocked")
}

/// 锁屏 → `Bool`（是否锁着）。不决定播放，veto 集合语义由 `HoldArbiter` 独占。
@MainActor
public final class LockWatcher {
    public private(set) var isRunning = false

    private let center: DistributedNotificationCenter
    private let names: LockSignalNames
    /// 会话字典读取口，默认真读系统，测试注入夹具。
    private let sessionReader: () -> [String: Any]?

    /// observer 注册与注销必须严格配对，token 存数组由 `stop()` 逐个摘。
    private var tokens: [NSObjectProtocol] = []

    public init(center: DistributedNotificationCenter = .default(),
                names: LockSignalNames = .system,
                sessionReader: @escaping () -> [String: Any]? = { CGSessionCopyCurrentDictionary() as? [String: Any] }) {
        self.center = center
        self.names = names
        self.sessionReader = sessionReader
    }

    /// 注册两个观察者，然后**同步**回调一次 `onChange(currentLockState())`，再置 `isRunning`。
    ///
    /// 顺序固定为「先注册后读值」：反过来会漏掉这中间发生的那次跃迁。重复调用幂等。
    public func start(onChange: @escaping @Sendable (Bool) -> Void) {
        guard !isRunning else { return }

        let lockedToken = center.addObserver(
            forName: Notification.Name(names.locked), object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { onChange(self.currentLockState()) }
        }
        let unlockedToken = center.addObserver(
            forName: Notification.Name(names.unlocked), object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { onChange(self.currentLockState()) }
        }
        tokens = [lockedToken, unlockedToken]
        isRunning = true

        onChange(currentLockState())
    }

    /// 按 token 逐个注销后清空数组 —— 少这一步就是 observer 泄漏。
    public func stop() {
        for token in tokens {
            center.removeObserver(token)
        }
        tokens.removeAll()
        isRunning = false
    }

    /// 读会话字典的 `CGSSessionScreenIsLocked` 键。
    ///
    /// 读不到 / 键缺失返回 `false` 且什么都不打 —— 在观测输出里编一个数字会把
    /// 「读不到」与「没锁」抹成一件。
    public func currentLockState() -> Bool {
        Self.lockState(fromSession: sessionReader())
    }

    /// 对注入字典取值的**纯函数**，供单测喂夹具而不必真去锁一次屏幕。
    public static func lockState(fromSession session: [String: Any]?) -> Bool {
        guard let raw = session?["CGSSessionScreenIsLocked"] else { return false }
        if let n = raw as? NSNumber { return n.intValue != 0 }
        if let b = raw as? Bool { return b }
        return false
    }
}