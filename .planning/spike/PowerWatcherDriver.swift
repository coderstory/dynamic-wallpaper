// PowerWatcherDriver.swift —— Plan 03-04 T2 的一次性 throwaway 驱动。
//
// 目的：证明「电源来源的**当前**读数是什么」「run loop source 挂上了没有」
// 「`start()` 的同步读真的发生了」以及「默认关闭 ⇒ verdict=0」这几件事，
// 并把**测不到**的部分（拔电源跃迁）如实记下来。
//
// ⚠️ 五条纪律（照 DisplayWatcherDriver 的四条 + 本 plan 新增的一条）：
//   ① **一次合成事件都不制造**。电源跃迁需要**拔电源线**这个硬件动作 —— 本会话做不到，
//      就记 `unobservable` + 原因，不拿合成事件冒充。
//   ② `POWER_START_SYNC_DELIVERED` 必须在**任何时间流逝之前**打。它的取证价值全在于
//      「没有等任何跃迁、也没有等任何通知」。
//   ③ 电源读数**全部现读现打**，不写任何形容词、不写「应该能行」。
//   ④ **不打印媒体路径或文件名**（T-03-17）：只打键名、布尔量、计数与一行 `pmset` 交叉参考。
//   ⑤ **键名与取值都是从 SDK 常量读出来的**，不是手抄的字符串 —— 手抄的那份
//      正是本 plan 被纠正的东西（见下面的 PLAN_DEVIATION）。
//
// ⚠️ PLAN_DEVIATION（判据未放宽，事实已更正；详见 03-04-SUMMARY）：
//   计划把 `kIOPSPowerSourceStateKey` 写成键 `"AC Power"`、类型写成 `CFBoolean`。
//   本机 SDK 实测：`IOPSKeys.h:311` 是 `#define kIOPSPowerSourceStateKey "Power Source State"`，
//   `IOPSKeys.h:303` 写明 Type **CFString**。`"AC Power"` 是**取值**
//   （`kIOPSACPowerValue`，`IOPSKeys.h:760`）不是键。
//   → 计划 AC 的 `POWER_SOURCE_KEY=AC Power` 与 `POWER_SOURCE_VALUE=(true|false)`
//     改成核对**真实**的键名与真实的三态取值。**核对得更严了，不是更松。**
//
// 编译（scripts/probe-power.sh 做这件事）：把**产品源码**与本驱动一起编进来，
// 证据跑的是产品代码，不是探针里重写一遍的逻辑：
//   swiftc -parse-as-library -o powerwatcher-driver \
//     Sources/PicCore/System/PowerWatcher.swift .planning/spike/PowerWatcherDriver.swift
//
// 本文件不引入播放框架（D-09），也不引用仲裁器 —— 它只看信号源本身。

import Foundation
import CoreGraphics
import IOKit.ps

// MARK: - 小工具（throwaway，不值得为它建类型）

/// 每行立刻 flush —— 进程可能被 kill，不能靠退出时统一 flush。
func emit(_ line: String) {
    print(line)
    fflush(stdout)
}

/// 跑一个只读命令并取它的 stdout。失败返回空串（调用方自己决定怎么如实表达「读不到」）。
func capture(_ path: String, _ args: [String]) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = args
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    do {
        try process.run()
    } catch {
        return ""
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(decoding: data, as: UTF8.self)
}

/// ⚠️ 这个计数器**只数 start() 的那次同步投递**，不算电源事件回调 ——
///
/// 第一版把两者合在一起数，结果 `POWER_CALLBACKS_FIRED=1`，而同一份日志里
/// `POWER_DELIVERY_COUNT=1` 也是 1，读起来像「电源回调触发了 1 次」。
/// 实测是 **0 次**：在 AC 上不动电源，IOKit 不会投递任何回调。
/// 一个数有两种读法会让证据假（与 03-03 的 DISPLAY_RECONFIG_FIRED_COUNT 同一个坑），
/// 所以这里改成：回调次数 = 总投递次数 − start() 那次同步投递。
final class PowerDeliveryCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func bump() { lock.withLock { value += 1 } }
    var count: Int { lock.withLock { value } }
}

@main
struct PowerWatcherDriver {
    static let windowSeconds = 4.0

    @MainActor
    static func main() {
        // ── 会话现状：只用来解释「为什么跃迁观测不到」───────────────────────
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        let locked = ((session?["CGSSessionScreenIsLocked"] as? NSNumber)?.intValue ?? 0) != 0
        let loginwindowPid = Int(capture("/usr/bin/pgrep", ["-x", "loginwindow"])
            .split(separator: "\n")
            .first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? "") ?? 0

        // ── 事件源注册：先挂上，才能观察「4 秒内有没有回调」──────────────
        // 计数包在产品回调**外面** —— 注册走的仍是产品的真机实现（真的调
        // `IOPSNotificationCreateRunLoopSource`），只是在闭包外套了个计数器，
        // 这样 `POWER_CALLBACKS_FIRED` 才是实测的回调次数，而不是「判定被调了几次」。
        let deliveries = PowerDeliveryCounter()
        let watcher = PowerWatcher()
        var deliveryCount = 0
        watcher.start { _ in
            deliveryCount += 1
            deliveries.bump()
            // start() 的那次同步读：必须在任何时间流逝、任何通知之前打。
            if deliveryCount == 1 {
                emit("POWER_START_SYNC_DELIVERED=1")
            } else {
                emit("POWER_CALLBACK_DELIVERED=\(deliveryCount)")
            }
        }

        // ① run loop source 挂上了没有 —— 挂不上等于拔电源不会有任何反应。
        emit("POWER_SOURCE_REGISTERED=1 runloop_source=\(watcher.isSourceRegistered ? 1 : 0)")

        // ② 键名：从 SDK 常量读出来逐字打（不是手抄）。
        emit("POWER_SOURCE_KEY=\(PowerWatcher.powerSourceStateKey)")
        emit("POWER_SOURCE_KEY_COUNT=\(PowerWatcher.currentPowerSourceKeys().count)")

        // ③ 取值 + 结论。**读不到就 unknown，不折成 false**（T-03-16）。
        let stateValue = PowerWatcher.currentPowerSourceStateValue()
        let readState = PowerWatcher.readPowerState()
        if let value = stateValue {
            emit("POWER_SOURCE_VALUE=\(value)")
        } else {
            emit("POWER_SOURCE_VALUE=unknown")
            emit("POWER_READ_FAILED=1")
        }
        switch readState {
        case .onBattery:
            emit("IS_ON_BATTERY=1")
        case .onAC:
            emit("IS_ON_BATTERY=0")
        case .failed:
            emit("IS_ON_BATTERY=unknown")
        }

        // ④ 默认关闭 ⇒ verdict=0（PAUSE-05 两半的联合判据，在真机上再跑一次）。
        // enabled 取产品 `SettingsStore.Seed()` 的默认值 —— 即「一个键都没设过」的形状。
        let enabled = SettingsStore.Seed().pauseOnBattery
        let isOnBattery = (readState == .onBattery)
        let verdict = BatteryHoldPolicy.shouldHold(isOnBattery: isOnBattery,
                                                  pauseOnBatteryEnabled: enabled)
        emit("BATTERY_HOLD enabled=\(enabled ? 1 : 0) verdict=\(verdict ? 1 : 0)")

        // ⑤ 硬件事实：这台机器到底有没有内置电池。没有的话 PAUSE-05 的活体路径本机不可达。
        let batt = capture("/usr/bin/pmset", ["-g", "batt"])
        let hasInternalBattery = batt.contains("InternalBattery")
        emit("INTERNAL_BATTERY_PRESENT=\(hasInternalBattery ? 1 : 0)")

        // ── 观察窗：只等、不制造任何事件 ───────────────────────────────────
        emit("POWER_OBSERVE_WINDOW_SECONDS=\(Int(windowSeconds))")
        let deliveriesAtStart = deliveries.count
        RunLoop.main.run(until: Date().addingTimeInterval(windowSeconds))
        // 只数**事件**投递：减去 start() 那次同步投递（观察窗开始前就发生，不是一次回调）。
        let callbackCount = deliveries.count - deliveriesAtStart
        emit("POWER_CALLBACKS_FIRED=\(callbackCount)")
        emit("POWER_DELIVERY_COUNT=\(deliveries.count)")
        emit("POWER_START_SYNC_DELIVERIES=\(deliveriesAtStart)")

        watcher.stop()
        emit("POWER_STOP_UNREGISTERED=\(watcher.isSourceRegistered ? 0 : 1)")

        // ── 跃迁：本会话观测不到，如实记 unobservable + 写明解开需要什么动作 ──
        // 关键点：**不是**因为屏幕锁着才观测不到拔电源 —— 拔电源是物理动作，
        // 屏幕锁不锁都不影响它能不能拔。所以原因字段如实写硬件动作本身。
        let reason = hasInternalBattery ? "requires_physical_unplug" : "no_internal_battery"
        emit("POWER_TRANSITION=unobservable reason=\(reason) CGSSessionScreenIsLocked=\(locked ? 1 : 0) loginwindow_pid=\(loginwindowPid) action=unplug_power_cord_required")

        // ⑦ pmset 交叉参考：首行原样贴进来，作为 IOKit 读数的独立对照。
        let pmsetFirstLine = batt.split(separator: "\n").first.map(String.init) ?? "unavailable"
        emit("PMSET_CROSSCHECK=\(pmsetFirstLine)")
    }
}