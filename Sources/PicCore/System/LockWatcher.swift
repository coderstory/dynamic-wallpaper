// LockWatcher.swift —— 锁屏信号的唯一来源（事件通知，不是轮询）。
//
// 分层红线：本文件**不引入播放框架**，不持有任何播放端引用。
// 单向流是 `LockWatcher → HoldArbiter.set(.screenLocked, active:) → PlaybackTarget.arbiterApply`，
// 方向不可逆。`test.sh` 的「System/ 四个 Watcher 零 AVFoundation」这条判据每次重验它。
//
// ⚠️ 分布式通知的投递方不可信。本类型把通知当**触发器**而不是状态本身：
// 收到信号后一律重新读 `CGSessionCopyCurrentDictionary()` 的公开只读键
// `CGSSessionScreenIsLocked`，只把这个键的值喂给 `HoldArbiter`。
// 伪造的「已解锁」通知因此最多触发一次重读，读到仍是锁着就不会误恢复播放。
//
// ⚠️ `start()` 在注册观察者之后**同步**回调一次当前值。这不是礼貌，是装配层正确性的前提：
// `com.apple.screenIsLocked` 是**跃迁通知**，只在锁↔解锁那一瞬间投递。本会话自
// `applicationDidFinishLaunching` 起屏幕一直锁着，没有任何跃迁可等 —— 少了那次同步回调，
// 装配层读到的 `holds` 是空集，锁屏会话下起播不会产生任何 hold。

import Foundation
import CoreGraphics

/// 锁屏信号的通知名。默认是系统那两个未文档化的名字；
/// 测试与探针一律注入自有前缀（见 `AppDelegate` 的 `PIC_LOCK_SIGNAL_PREFIX`），
/// 绝不往系统通知名投合成事件 —— 同机的其它壁纸 app 会一起被暂停。
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

/// 锁屏 → `Bool`（是否锁着）。
///
/// 本类型只回答「此刻锁着没有」，不决定播放。veto 集合语义由 `HoldArbiter` 独占。
@MainActor
public final class LockWatcher {
    public private(set) var isRunning = false

    private let center: DistributedNotificationCenter
    private let names: LockSignalNames
    /// 会话字典读取口，默认真读系统。测试注入 `[String: Any]` 夹具
    /// （缺键 / 0 / 1 三种输入的输出）。
    private let sessionReader: () -> [String: Any]?

    /// Pitfall 4：observer 注册与注销必须严格配对。token 存进数组，`stop()` 逐个摘。
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
    /// 顺序固定为「先注册后读值」：反过来会漏掉读值与注册之间发生的那次跃迁。
    /// 重复调用是幂等的。
    public func start(onChange: @escaping @Sendable (Bool) -> Void) {
        guard !isRunning else { return }

        let lockedToken = center.addObserver(
            forName: Notification.Name(names.locked), object: nil, queue: nil
        ) { _ in
            MainActor.assumeIsolated { onChange(self.currentLockState()) }
        }
        let unlockedToken = center.addObserver(
            forName: Notification.Name(names.unlocked), object: nil, queue: nil
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
    /// 读不到 / 键缺失一律返回 `false`（视作「没锁」），**什么都不打** ——
    /// 「读不到」与「没锁」是两件事，在观测输出里编一个数字会把两者的差别抹掉。
    public func currentLockState() -> Bool {
        Self.lockState(fromSession: sessionReader())
    }

    /// 对注入字典取值的**纯函数**。
    /// 抽出来是为了让「字典缺键 / 值为 0 / 值为 1」三种夹具能被单测直接断言，
    /// 而不必真的去锁一次屏幕。
    public static func lockState(fromSession session: [String: Any]?) -> Bool {
        guard let raw = session?["CGSSessionScreenIsLocked"] else { return false }
        if let n = raw as? NSNumber { return n.intValue != 0 }
        if let b = raw as? Bool { return b }
        return false
    }
}