// PowerWatcher.swift —— 电池供电信号的来源（PAUSE-05）。
//
// ── D-09 分层红线 ──────────────────────────────────────────────────────
//
// 本文件**零 AVFoundation**、不持有播放端引用、也**不出现** `SettingsStore` 与
// 仲裁器的类型名。它只回答一个事实问题：「此刻在电池上吗」。
// 「要不要暂停」是 `BatteryHoldPolicy` 的事，「把结果喂给谁」是装配层（Plan 03-05）的事。
// 纯函数才是可单测的部分，判定不该埋在 IOKit 的调用栈里。
//
// ── D-01：事件驱动，零轮询 ──────────────────────────────────────────────
//
// 本文件里没有任何定时器。信号源是 `IOPSNotificationCreateRunLoopSource`
// （`IOPowerSources.h:342`）挂到主 run loop 上；电源来源变化时回调触发，
// 回调里**重读**当前状态。单测与探针每次都跑真实的 `swift test` / 真编译，
// 不需要为了观察电源状态起一个轮询循环。
//
// ── ⚠️ 计划 AC 的两处 API 字面值在本机 SDK 上不成立（PLAN_DEVIATION，见 03-04-SUMMARY）──
//
// `03-04-PLAN.md` 写「字典键 `"AC Power"`（`kIOPSPowerSourceStateKey`）取 `CFBoolean` 值」。
// `IOPSKeys.h:311` 的真实定义是 `#define kIOPSPowerSourceStateKey "Power Source State"`，
// 且 `IOPSKeys.h:303` 写明「Type **CFString**, value is `kIOPSACPowerValue` /
// `kIOPSBatteryPowerValue` / `kIOPSOffLineValue`」。
// → **键名是 `"Power Source State"`，值是 CFString 不是 CFBoolean**，而 `"AC Power"`
//   是**值**（`kIOPSACPowerValue`，`IOPSKeys.h:760`）不是键。
// 判据改的是「核对哪个字面量」，**不是放宽判据**：真实键名与真实值都逐字打印进 evidence。
//
// ── ⚠️ T-03-16：读失败绝不静默折值 ──────────────────────────────────────
//
// `IOPSCopyPowerSourcesInfo` → `IOPSCopyPowerSourcesList` → `IOPSGetPowerSourceDescription`
// 这一条链上任一步返回空、或状态键缺失、或值是上面三种之外的第四种（比如 `Off Line`），
// 都归一为 `PowerReadState.failed`，并由 `currentIsOnBattery()` 立刻往 stderr 打一行
// `POWER_READ_FAILED=1`。
// 为什么必须在**读取的这一层**上报，而不放给调用方：返回值只有一个 `Bool`，
// 折成 `false` 之后「读不到」与「在 AC 上」已经无法分辨 ——
// 误折成「在电池上」会无故暂停（用户看得见的坏事），误折成「在 AC 上」会漏暂停。
// 两者都只靠这行显式上报区分。折哪个方向都不许静默。
//
// 上报与取布尔值共用**同一次**读取的结果（见 `currentIsOnBattery()` 的实现）——
// 不存在「打点时的状态」与「返回给调用方的状态」分属两次读取的缝。
//
// ── 启动即读一次（装配层的启动契约）──────────────────────────────────────
//
// 电源状态**当下就可读**（不像锁屏 / 熄屏要等跃迁）。所以 `start()` 在注册事件源之后、
// 调 `onChange` 之前，必须同步求一次 `currentIsOnBattery()` 交出去。
// 少了这一次，装配层读到的电源位是默认的 `false`，而那与「在 AC 上」不可区分 ——
// 在电池上启动的机器会一直不产生 hold，直到下一次拔/插电源。
// 同形契约见 03-01 的 `LockWatcher.start()` 与 03-03 的 `DisplayWatcher.start()`。

import Foundation
import IOKit.ps

/// 显式 release 的一次 CF 对象。
///
/// Swift 已把 CF 对象交给 ARC，`CFRelease` 因此被标成 unavailable。本文件刻意要
/// **显式**的那一次 release（`IOPSNotificationCreateRunLoopSource` 返回的是 +1 的
/// `Unmanaged`，所有权归本类型，由 `stop()` 还回去，T-03-15），
/// 而 `Unmanaged.release()` 在 ARC 已托管 CF 的前提下会与 ARC 的那次释放重复 ——
// 于是这里用 `@_silgen_name` 直接引 CF 的 `CFRelease`，**恰好一次**，
/// 既拿到显式的那一次，又不多还一次。
@_silgen_name("CFRelease")
private func _CFRelease(_ cf: CFTypeRef!)

// MARK: - 判定纯函数

/// 「要不要因为电池而暂停」的**唯一**判定处。
///
/// 抽成纯函数是因为它是本 plan 唯一可以在**不拔电源**的情况下 100% 测到的部分：
/// 拔电源是硬件动作，本会话做不到；这两个 `Bool` 的四种组合谁都能测。
public enum BatteryHoldPolicy {
    /// 开关关时电源信号**一律**不产生 hold（D-11 / PAUSE-05）。
    ///
    /// 不变量：实现体必须是两个输入的**合取**，且开关是**第二项** ——
    /// 「默认关闭」这条硬约束就落在第二个合取项上。
    ///
    /// ⚠️ 这里刻意**不写**出那个合取式的字面量形式（D-07）：反向验证用一句
    /// `perl -0pi` 的整文件首次替换来改坏这个函数，注释里若抄了同一句字面量，
    /// 替换就会落在注释上，判据转绿却什么代码都没改坏 ——
    /// Phase 1 / Phase 2 各出现过 5 次与 3 次「自己的判据被自己违反」。
    public static func shouldHold(isOnBattery: Bool, pauseOnBatteryEnabled: Bool) -> Bool {
        return isOnBattery && pauseOnBatteryEnabled
    }
}

// MARK: - 电源读数（三态）

/// 当前电源读数的三态。
///
/// 为什么不是 `Bool`：「读不到」与「在 AC 上」折成同一个 `false` 会抹掉一次
/// 真实的读数失败（T-03-16）。三态让「读不到」有它自己的名字。
public enum PowerReadState: Equatable, Sendable {
    /// 内置电池供电。
    case onBattery
    /// 外接电源供电（`kIOPSACPowerValue`）。
    case onAC
    /// 读失败：链上任一步为空 / 键缺失 / 值是已知三种之外的状态。
    case failed
}

// MARK: - Watcher

/// 电池供电信号的唯一来源（D-09：只产出 `Bool`，不碰仲裁器、不碰播放器）。
@MainActor
public final class PowerWatcher {
    public private(set) var isRunning = false
    /// `IOPSNotificationCreateRunLoopSource` 是否拿到非空 source 并挂上主 run loop。
    /// 探针与单测都读它 —— 事件源没挂上就等于拔电源不会有任何反应（D-01 没兑现）。
    public private(set) var isSourceRegistered = false

    /// 挂在主 run loop 上的那个 source。
    ///
    /// ⚠️ 这里刻意**不**用 `takeRetainedValue()`：那个写法把 +1 的所有权交给 ARC，
    /// 释放就变成隐式的、看不见也点不掉。`IOPowerSources.h:341` 明写
    /// "Caller must release the CFRunLoopSource"，所以这里持有 `Unmanaged` 原件，
    /// 由 `stop()` 显式还那一次 release（T-03-15）—— 注册与释放严格配对，两个字面量都能被读到。
    private var source: Unmanaged<CFRunLoopSource>?

    public init() {}

    /// 注册事件源，然后**同步**回调一次 `currentIsOnBattery()`，再置 `isRunning`。
    ///
    /// 顺序固定为「先注册后读值」：反过来会漏掉读值与注册之间发生的那次跃迁。
    /// 重复调用是幂等的。
    public func start(onChange: @escaping (Bool) -> Void) {
        guard !isRunning else { return }
        isRunning = true

        registerRunLoopSource(onChange)

        // 同步投递当前值：不依赖任何跃迁（电源状态此刻就能读到）。
        onChange(Self.currentIsOnBattery())
    }

    /// 摘掉并释放 run loop source，再清回调表（T-03-15 / Pitfall 4：注册与释放严格配对）。
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
    ///
    /// 返回值与那行上报**共用同一次读取**（`readPowerState()` 调一次，两个出口用它的结果），
    /// 不存在「打点时的状态」与「返回给调用方的状态」分属两次读取的缝。
    public static func currentIsOnBattery() -> Bool {
        switch readPowerState() {
        case .onBattery:
            return true
        case .onAC:
            return false
        case .failed:
            // T-03-16：显式上报，不静默折值。折哪个方向都是用户可见的后果变化。
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
        // （IOPowerSources.h:303 明写 "Caller should NOT release the returned CFDictionary"），
        // 随 `IOPSCopyPowerSourcesInfo()` 那次 retain 一起释放。这里必须用
        // `takeUnretainedValue()` —— 用 `takeRetainedValue()` 会多 release 一次。
        guard let description = firstPowerSourceDescription() else { return nil }
        return description[powerSourceStateKey] as? String
    }

    /// 第一个电源源的描述字典。**unretained** —— 随上面那次 `takeRetainedValue` 一起释放。
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
/// 一张单槽表正好对上真实语义。与 03-03 的重配置表同形。
private let powerCallbackLock = NSLock()
private var powerHandlers: [(Bool) -> Void] = []

/// C ABI（`IOPowerSources.h:342` 的 `IOPowerSourceCallbackType`，形参是 `void *context`）。
///
/// 回调里**重读**当前状态再交给闭包，而不是缓存上次那个值 —— 与 `LockWatcher`
/// 对分布式通知、03-03 对重配置回调的处理同形：信号只当触发器，状态一律现读。
private let powerTrampoline: IOPowerSourceCallbackType = { _ in
    guard let handler = powerCallbackLock.withLock({ powerHandlers.first }) else { return }
    // 回调的投递线程文档没有承诺 —— 一律 hop 回主队列，不在 C 边界做隔离假设。
    DispatchQueue.main.async {
        MainActor.assumeIsolated { handler(PowerWatcher.currentIsOnBattery()) }
    }
}