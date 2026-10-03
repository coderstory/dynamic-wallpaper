// DisplayWatcherDriver.swift —— Plan 03-03 T2 的一次性 throwaway 驱动。
//
// 目的：证明「熄屏位与睡眠位各自**当前**读得到什么」「三个入口注册成功」
// 以及「`start()` 同步重算真的发生了」这几件事，并把**测不到**的部分如实记下来。
//
// ⚠️ 四条纪律（照 LockWatcherDriver 的三条 + 本 plan 新增的一条）：
//   ① **绝不往系统通知名投合成事件**。本驱动一次合成通知都不投 —— 熄屏与睡眠的跃迁
//      本会话**观测不到**，就记 `unobservable`，不拿合成事件冒充（LockWatcherDriver 的 ①③）。
//   ② `DISPLAY_START_SYNC_DELIVERED` 必须在**任何时间流逝之前**打。它的取证价值全在于
//      「没有等任何跃迁、也没有等任何通知」（LockWatcherDriver 的 ②）。
//   ③ 电源 / 会话读数**全部现读现打**，不写任何形容词、不写「应该能行」。
//   ④ **不打印媒体路径或文件名**（T-03-13）：只打通知名、显示 ID、布尔量、计数与电源键值。
//
// 编译（scripts/probe-display.sh 做这件事）：把**产品源码**与本驱动一起编进来，
// 证据跑的是产品代码，不是探针里重写一遍的逻辑：
//   swiftc -parse-as-library -o displaywatcher-driver \
//     Sources/PicCore/System/DisplayWatcher.swift .planning/spike/DisplayWatcherDriver.swift
//
// 本文件不引入播放框架（D-09），也不引用仲裁器 —— 它只看信号源本身。

import Foundation
import AppKit
import CoreGraphics

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

/// 重配置回调计数。C 回调的投递线程文档没有承诺 —— 上锁，别赌。
final class ReconfigCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func bump() { lock.withLock { value += 1 } }
    var count: Int { lock.withLock { value } }
}

/// 包一层计数：注册走的**仍是产品的真机实现**（真的调 CoreGraphics 那两个函数），
/// 只是在回调外套了个计数器 —— 这样 `DISPLAY_RECONFIG_CALLBACKS_FIRED` 才是实测数，
/// 而不是「re-evaluate 被调了几次」那种会混淆两个入口的间接量。
final class CountingReconfigurationHook: DisplayReconfigurationHook {
    private let system = SystemDisplayReconfigurationHook()
    private let counter: ReconfigCounter

    init(counter: ReconfigCounter) { self.counter = counter }

    @discardableResult
    func register(_ onReconfigured: @escaping () -> Void) -> Bool {
        system.register {
            MainActor.assumeIsolated {
                self.counter.bump()
                onReconfigured()
            }
        }
    }

    func unregister() { system.unregister() }
}

@main
struct DisplayWatcherDriver {
    static let windowSeconds = 4.0

    @MainActor
    static func main() {
        // ── 现读的会话与电源状态（全部真读，不假设）─────────────────────────
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        let locked = ((session?["CGSSessionScreenIsLocked"] as? NSNumber)?.intValue ?? 0) != 0
        let loginwindowPid = Int(capture("/usr/bin/pgrep", ["-x", "loginwindow"])
            .split(separator: "\n")
            .first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? "") ?? 0

        // ── 显示器当前读数 ─────────────────────────────────────────────────
        let mainDisplay = CGMainDisplayID()
        // 主显示器 ID 为 0 时这个读数没有意义，如实打 unknown 而不是编一个数。
        let asleepToken: String
        if mainDisplay == 0 {
            asleepToken = "unknown"
        } else {
            asleepToken = CGDisplayIsAsleep(mainDisplay) != 0 ? "1" : "0"
        }

        // ── 起产品 watcher ─────────────────────────────────────────────────
        let counter = ReconfigCounter()
        let watcher = DisplayWatcher(reconfigurationHook: CountingReconfigurationHook(counter: counter))

        var deliveryCount = 0
        watcher.start { signals in
            deliveryCount += 1
            // start() 的那次同步重算：必须在任何时间流逝、任何通知之前打。
            if deliveryCount == 1 {
                emit("DISPLAY_START_SYNC_DELIVERED=1 displayAsleep=\(signals.displayAsleep ? 1 : 0) systemSleeping=\(signals.systemSleeping ? 1 : 0)")
            } else {
                emit("DISPLAY_RECONFIG_DELIVERED=1 displayAsleep=\(signals.displayAsleep ? 1 : 0) systemSleeping=\(signals.systemSleeping ? 1 : 0)")
            }
        }

        emit("DISPLAY_SIGNALS_REGISTERED=1 sleep=\(DisplayWatcher.sleepNotificationName.rawValue) wake=\(DisplayWatcher.wakeNotificationName.rawValue) reconfig=\(watcher.isReconfigurationRegistered ? 1 : 0)")
        emit("MAIN_DISPLAY_ID=\(mainDisplay)")
        emit("CGDisplay_IS_ASLEEP=\(asleepToken)")

        let current = watcher.currentSignals()
        emit("DISPLAY_SIGNALS displayAsleep=\(current.displayAsleep ? 1 : 0) systemSleeping=\(current.systemSleeping ? 1 : 0)")

        emit("SESSION_LOCKED=\(locked ? 1 : 0) loginwindow_pid=\(loginwindowPid) session_keys=\(session?.count ?? 0)")

        // ── 电源状态：真读 pmset，不复述任何推测 ───────────────────────────
        let batt = capture("/usr/bin/pmset", ["-g", "batt"])
        let source = batt
            .split(separator: "\n")
            .first(where: { $0.contains("drawing from") })?
            .split(separator: "'").dropFirst().first.map(String.init) ?? "unknown"
        let settings = capture("/usr/bin/pmset", ["-g"])
        let assertions = capture("/usr/bin/pmset", ["-g", "assertions"])

        emit("POWER_SOURCE=\(source)")
        emit("POWER_SLEEP_DISABLED=\(pmsetFlag(settings, "SleepDisabled") ?? "unknown")")
        emit("POWER_DISPLAYSLEEP_MINUTES=\(pmsetSetting(settings, "displaysleep") ?? "unknown")")
        emit("POWER_PREVENT_SYSTEM_SLEEP=\(pmsetFlag(assertions, "PreventUserIdleSystemSleep") ?? "unknown")")
        emit("POWER_PREVENT_DISPLAY_SLEEP=\(pmsetFlag(assertions, "PreventUserIdleDisplaySleep") ?? "unknown")")

        // ── 观察窗：只等、不制造任何事件 ───────────────────────────────────
        emit("DISPLAY_RECONFIG_WINDOW_SECONDS=\(Int(windowSeconds))")
        RunLoop.main.run(until: Date().addingTimeInterval(windowSeconds))
        emit("DISPLAY_RECONFIG_CALLBACKS_FIRED=\(counter.count)")

        watcher.stop()

        // ── 跃迁：本会话观测不到，如实记 unobservable + 原因 ───────────────
        // 会话锁着；且系统睡眠被外部的 caffeinate 断言挡住（见上面的 POWER_PREVENT_SYSTEM_SLEEP），
        // 无人值守地让机器睡会打断用户的工作 —— 两个原因都不允许在本会话制造跃迁。
        let reason = locked ? "session_locked" : "session_unlocked"
        emit("DISPLAY_SLEEP_TRANSITION=unobservable reason=\(reason) CGSSessionScreenIsLocked=\(locked ? 1 : 0) loginwindow_pid=\(loginwindowPid)")
        emit("SYSTEM_SLEEP_TRANSITION=unobservable reason=\(reason) CGSSessionScreenIsLocked=\(locked ? 1 : 0) loginwindow_pid=\(loginwindowPid)")
        emit("DISPLAY_DELIVERY_COUNT=\(deliveryCount)")
        emit("DISPLAY_STOP_UNREGISTERED=\(watcher.isReconfigurationRegistered ? 0 : 1)")
    }

    /// `pmset -g assertions` 的「Assertion status system-wide:」块里取某个键的 0/1。
    private static func pmsetFlag(_ text: String, _ key: String) -> String? {
        for line in text.split(separator: "\n") {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            if parts.count == 2, parts[0] == key, parts[1] == "0" || parts[1] == "1" {
                return parts[1]
            }
        }
        return nil
    }

    /// `pmset -g` 的「Currently in use:」块里取 `key<空白>value`。
    private static func pmsetSetting(_ text: String, _ key: String) -> String? {
        var inBlock = false
        for line in text.split(separator: "\n") {
            if line.contains("Currently in use") { inBlock = true; continue }
            guard inBlock else { continue }
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            if parts.count >= 2, parts[0] == key { return parts[1] }
        }
        return nil
    }
}
