// PowerWatcher.swift —— 电池供电信号的来源。
//
// ── 分层红线 ────────────────────────────────────────────────────────────
// 本文件**零 AVFoundation**、不持有播放端引用、也**不出现**仲裁器的类型名。
// 它只回答「此刻在电池上吗」；「要不要暂停」是装配层的事。
// 纯函数才是可单测的部分，判定不该埋在 IOKit 的调用栈里。
//
// 事件驱动、零轮询：信号源是 `IOPSNotificationCreateRunLoopSource` 挂主 run loop，
// 电源来源变化时回调触发，回调里**重读**当前状态 —— 信号只当触发器，状态一律现读。
//
// ⚠️ `IOPSPowerSourceStateKey` 的真实键名是 `"Power Source State"`，值是 **CFString**
//    （`kIOPSACPowerValue` / `kIOPSBatteryPowerValue` / `kIOPSOffLineValue`）不是 CFBoolean；
//    `"AC Power"` 是**值**不是键。判据改的是「核对哪个字面量」，**不是放宽判据**。
//
// ⚠️ 读失败绝不静默折值：`IOPSCopyPowerSourcesInfo` → `IOPSCopyPowerSourcesList` →
//    `IOPSGetPowerSourceDescription` 这条链上任一步返回空、或状态键缺失、或值是已知三种
//    之外的第四种，一律归一为 `PowerReadState.failed`，并由 `currentIsOnBattery()` 立刻往
//    stderr 打一行 `POWER_READ_FAILED=1`。**为什么必须在读取的这一层上报**：返回值只有
//    一个 `Bool`，折成 `false` 之后「读不到」与「在 AC 上」已无法分辨 —— 误折成「在电池上」
//    会无故暂停，误折成「在 AC 上」会漏暂停，两者都只靠这行显式上报区分。折哪个方向都不许
//    静默。上报与取布尔值**共用同一次**读取，不存在「打点时的状态」与「返回给调用方的状态」
//    分属两次读取的缝。
//
// 启动即读一次：电源状态**当下就可读**（不像锁屏 / 熄屏要等跃迁）。`start()` 在注册事件源
// 之后、调 `onChange` 之前必须同步求一次交出去。少了这一次，装配层读到的电源位是默认的
// `false`，而那与「在 AC 上」不可区分 —— 在电池上启动的机器会一直不产生 hold。

import Foundation
import IOKit.ps

/// 显式 release 的一次 CF 对象。
///
/// ⚠️ Swift 已把 CF 对象交给 ARC，`CFRelease` 因此被标成 unavailable。本文件刻意要
///    **显式**的那一次 release（`Unmanaged.release()` 会与 ARC 的那次释放重复 ——
///    会多还一次），所以用 `@_silgen_name` 直接引 CF 的 `CFRelease`，**恰好一次**。
@_silgen_name("CFRelease")
private func _CFRelease(_ cf: CFTypeRef!)

// MARK: - 判定纯函数

/// 「要不要因为电池而暂停」的**唯一**判定处。
///
/// 抽成纯函数是因为它是唯一可以在**不拔电源**的情况下 100% 测到的部分：
/// 拔电源是硬件动作，本会话做不到；这两个 `Bool` 的四种组合谁都能测。
public enum BatteryHoldPolicy {
    /// 开关关时电源信号**一律**不产生 hold。
    ///
    /// 不变量：实现体必须是两个输入的**合取**，且开关是**第二项** ——
    /// 「默认关闭」这条硬约束就落在第二个合取项上。
    ///
    /// ⚠️ 这里刻意**不写**出那个合取式的字面量形式：反向验证用一句 `perl -0pi` 的
    ///    整文件首次替换来改坏这个函数，注释里若抄了同一句字面量，替换就会落在注释上，
    ///    判据转绿却什么代码都没改坏 —— Phase 1 / Phase 2 各出现过 5 次与 3 次
    ///    「自己的判据被自己违反」。
    public static func shouldHold(isOnBattery: Bool, pauseOnBatteryEnabled: Bool) -> Bool {
        return isOnBattery && pauseOnBatteryEnabled
    }
}

// MARK: - 电源读数（三态）

/// 当前电源读数的三态。
///
/// 为什么不是 `Bool`：「读不到」与「在 AC 上」折成同一个 `false` 会抹掉一次
/// 真实的读数失败。三态让「读不到」有它自己的名字。
public enum PowerReadState: Equatable, Sendable {
    /// 内置电池供电。
    case onBattery
    /// 外接电源供电（`kIOPSACPowerValue`）。
    case onAC
    /// 读失败：链上任一步为空 / 键缺失 / 值是已知三种之外的状态。
    case failed
}

// MARK: - Watcher

/// 电池供电信号的唯一来源（只产出 `Bool`，不碰仲裁器、不碰播放器）。
@MainActor
public final class PowerWatcher {
    public private(set) var isRunning = false
    /// `IOPSNotificationCreateRunLoopSource` 是否拿到非空 source 并挂上主 run loop。
    /// 探针与单测都读它 —— 事件源没挂上就等于拔电源不会有任何反应。
    public private(set) var isSourceRegistered = false

    /// 挂在主 run loop 上的那个 source。
    ///
    /// ⚠️ 这里刻意**不**用 `takeRetainedValue()`：那个写法把 +1 的所有权交给 ARC，
    ///    释放就变成隐式的、看不见也点不掉。`IOPowerSources.h:341` 明写
    ///    "Caller must release the CFRunLoopSource"，所以这里持有 `Unmanaged` 原件，
    ///    由 `stop()` 显式还那一次 release —— 注册与释放严格配对，两个字面量都能被读到。
    private var source: Unmanaged<CFRunLoopSource>?

    public init() {}

    /// 注册事件源后**同步**回调一次当前读数，再置 `isRunning`。
    ///
    /// 顺序固定为「先注册后读值」：反过来会漏掉读值与注册之间发生的那次跃迁。
    /// 重复调用是幂等的。
    public func start(onChange: @escaping (Bool) -> Void) {
        guard !isRunning else { return }
        isRunning = true

        registerRunLoopSource(onChange)

        onChange(Self.currentIsOnBattery())
    }

    /// 摘掉并释放 run loop source，再清回调表（注册与释放严格配对，Pitfall 4）。
    public func stop() {
        if let held = source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), held.takeUnretainedValue(), .defaultMode)
            _CFRelease(held.takeUnretainedValue())
            source = nil
        }
        powerCallbackLock.withLock { powerHandlers.removeAll() }
        isSourceRegistered = false
        isRunning = false
    }

    // MARK: 读数

    /// 此刻是否在电池上。**读失败时返回 `false` 并打一行 `POWER_READ_FAILED=1`**。
    public static func currentIsOnBattery() -> Bool {
        switch readPowerState() {
        case .onBattery:
            return true
        case .onAC:
            return false
        case .failed:
            // 显式上报，不静默折值。折哪个方向都是用户可见的后果变化。
            FileHandle.standardError.write(Data("POWER_READ_FAILED=1\n".utf8))
            return false
        }
    }

    /// 三态读数。**纯读取**，不打印任何东西 —— 上报那一层在 `currentIsOnBattery()`，
    /// 这样探针与单测可以只取三态而拿到干净的 stdout。
    public static func readPowerState() -> PowerReadState {
        guard let rawState = currentPowerSourceStateValue() else { return .failed }
        // `kIOPSBatteryPowerValue` / `kIOPSACPowerValue` 是 `#define` 的字符串字面量，
        // Swift 直接把它们 import 成 `String` —— 判据比对的是 SDK 常量本身，
        // 不是手抄的 `"Battery Power"`。
        switch rawState {
        case kIOPSBatteryPowerValue: return .onBattery
        case kIOPSACPowerValue: return .onAC
        default: return .failed
        }
    }

    /// `kIOPSPowerSourceStateKey` 的**实测**键名（本机 SDK：`"Power Source State"`）。
    /// 公开成常量，探针打的是从 SDK 读出来的字面量，不是手抄的字符串。
    public static let powerSourceStateKey: String = kIOPSPowerSourceStateKey

    /// 第一个电源源的 `kIOPSPowerSourceStateKey` 的**实测取值**（CFString），
    /// 读不到返回 nil（由调用方如实表达成 `unknown`，不折成 `AC Power`）。
    public static func currentPowerSourceStateValue() -> String? {
        // `IOPSGetPowerSourceDescription` 返回的是 **unretained** 指针
        // （"Caller should NOT release the returned CFDictionary"），
        // 随 `IOPSCopyPowerSourcesInfo()` 那次 retain 一起释放。这里必须用
        // `takeUnretainedValue()` —— 用 `takeRetainedValue()` 会多 release 一次。
        guard let description = firstPowerSourceDescription() else { return nil }
        return description[powerSourceStateKey] as? String
    }

    /// 第一个电源源的描述字典。**unretained** —— 随上面那次 retain 一起释放。
    private static func firstPowerSourceDescription() -> NSDictionary? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let rawList = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue()
        else { return nil }
        let list = rawList as NSArray
        guard let source = list.firstObject else { return nil }
        guard let described = IOPSGetPowerSourceDescription(blob, source as CFTypeRef)?
            .takeUnretainedValue() else { return nil }
        return described as NSDictionary
    }

    /// 电源源列表的**实测**键名集合（供探针逐字打印）。
    public static func currentPowerSourceKeys() -> [String] {
        guard let description = firstPowerSourceDescription() else { return [] }
        return description.allKeys.compactMap { $0 as? String }.sorted()
    }

    // MARK: 事件源

    private func registerRunLoopSource(_ onChange: @escaping (Bool) -> Void) {
        powerCallbackLock.withLock {
            powerHandlers.removeAll()
            powerHandlers.append(onChange)
        }

        // 不 takeRetainedValue —— 所有权留在 `source` 里，由 `stop()` 显式归还一次。
        guard let created = IOPSNotificationCreateRunLoopSource(powerTrampoline, nil) else {
            isSourceRegistered = false
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), created.takeUnretainedValue(), .defaultMode)
        source = created
        isSourceRegistered = true
    }
}

// MARK: - C 回调 → Swift 闭包的桥

/// C 函数指针带不了 Swift 上下文，所以用一张进程级表把回调转回来 ——
/// `IOPSNotificationCreateRunLoopSource` 的注册本来就是进程级的（同一个 run loop source），
/// 一张单槽表正好对上真实语义。与重配置表同形。
private let powerCallbackLock = NSLock()
private var powerHandlers: [(Bool) -> Void] = []

/// C ABI 的回调（形参是 `void *context`）。
///
/// 回调里**重读**当前状态再交给闭包，而不是缓存上次那个值：信号只当触发器，状态一律现读。
private let powerTrampoline: IOPowerSourceCallbackType = { _ in
    guard let handler = powerCallbackLock.withLock({ powerHandlers.first }) else { return }
    // 回调的投递线程文档没有承诺 —— 一律 hop 回主队列，不在 C 边界做隔离假设。
    DispatchQueue.main.async {
        MainActor.assumeIsolated { handler(PowerWatcher.currentIsOnBattery()) }
    }
}