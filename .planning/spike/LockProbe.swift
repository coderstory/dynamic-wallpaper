// LockProbe.swift —— Phase 01 门禁 spike，一次性 throwaway 探针。
//
// 目的：回答「com.apple.screenIsLocked 在本机 macOS 27 上是否触发」——
//   ARCHITECTURE §4 / §12.1：未文档化通知，真失效时降级方案未找到公开资料。
// 纪律：本文件只如实记录「通知来没来」，不写任何「一定触发」的断言。
// 不需要 AppKit、不需要 run loop 权限、不调用任何锁屏 API（只监听）。
// 编译：swiftc -parse-as-library -target arm64-apple-macosx15.0 -o out/lockprobe LockProbe.swift

import Foundation
import CoreFoundation
import CoreGraphics

// 两个未文档化的分布式通知名。
let lockedNotification = "com.apple.screenIsLocked"
let unlockedNotification = "com.apple.screenIsUnlocked"

let isoFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    f.timeZone = TimeZone(secondsFromGMT: 0)
    return f
}()

func isoNow() -> String {
    isoFormatter.string(from: Date())
}

// 日志落盘：每行立刻 flush（进程可能被 kill，不能靠退出时统一 flush）。
// 每次运行 truncate 目标文件，不追加 —— 否则「恰好 N 行」这类判据会随重跑失效。
final class Sink {
    private let path: String

    init(path: String) {
        self.path = path
        FileManager.default.createFile(atPath: path, contents: Data())
    }

    func append(_ line: String) {
        guard let handle = FileHandle(forWritingAtPath: path) else {
            FileHandle.standardError.write("LOCKPROBE_LOGFAIL=\(path)\n".data(using: .utf8)!)
            return
        }
        defer { try? handle.close() }
        handle.seekToEndOfFile()
        handle.write(Data((line + "\n").utf8))
        try? handle.synchronize()
        print(line)
        fflush(stdout)
    }
}

final class ProbeState {
    static let shared = ProbeState()
    var sink: Sink?
    var events = 0
    var lockedSeen = false
    var seconds = 120
    var heartbeats = 0
}

// C 回调无法捕获上下文，故用全局单例做出口。
// 两个通知各挂一个专属 trampoline：CFNotificationName 在 macOS 27 SDK 上是与 CFString
// 不同的类型，不做桥接就没法在回调里比名字，分开挂最省事也最不会认错。
func darwinLockedCallback(
    center: CFNotificationCenter?,
    observer: UnsafeMutableRawPointer?,
    name: CFNotificationName?,
    object: UnsafeRawPointer?,
    userInfo: CFDictionary?
) {
    let state = ProbeState.shared
    state.events += 1
    state.lockedSeen = true
    state.sink?.append("lock|locked|\(isoNow())")
}

func darwinUnlockedCallback(
    center: CFNotificationCenter?,
    observer: UnsafeMutableRawPointer?,
    name: CFNotificationName?,
    object: UnsafeRawPointer?,
    userInfo: CFDictionary?
) {
    let state = ProbeState.shared
    state.events += 1
    state.sink?.append("lock|unlocked|\(isoNow())")
}

func registerDarwinNotifications() {
    let center = CFNotificationCenterGetDarwinNotifyCenter()
    let observer = Unmanaged.passUnretained(ProbeState.shared).toOpaque()
    CFNotificationCenterAddObserver(
        center, observer, darwinLockedCallback,
        lockedNotification as CFString, nil, .deliverImmediately
    )
    CFNotificationCenterAddObserver(
        center, observer, darwinUnlockedCallback,
        unlockedNotification as CFString, nil, .deliverImmediately
    )
}

// session 心跳：公开 API（CGSessionCopyCurrentDictionary，macOS 10.3+）。
// ARCHITECTURE 实测它只有 5 个键、没有锁屏键 —— 心跳的价值在于：通知若始终不来，
// 仍能证明「探针确实在跑，且 session 字典在这段时间里没有变化」，
// 从而把「通知失效」与「探针根本没跑」区分开。
func sessionLine() -> String {
    guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else {
        return "session|\(isoNow())|keys="
    }
    return "session|\(isoNow())|keys=\(dict.keys.sorted().joined(separator: ","))"
}

func finish() -> Never {
    let state = ProbeState.shared
    state.sink?.append(
        "LOCKPROBE_DONE events=\(state.events) locked=\(state.lockedSeen ? 1 : 0) seconds=\(state.seconds)"
    )
    exit(0)
}

@main
struct LockProbeMain {
    static func main() {
        var seconds = 120
        var logPath = ".planning/spike/out/lock.log"
        let args = CommandLine.arguments
        var i = 1
        while i < args.count {
            if args[i] == "--seconds", i + 1 < args.count, let parsed = Int(args[i + 1]) {
                seconds = parsed
                i += 2
            } else if args[i] == "--log", i + 1 < args.count {
                logPath = args[i + 1]
                i += 2
            } else {
                i += 1
            }
        }

        let sink = Sink(path: logPath)
        ProbeState.shared.sink = sink
        ProbeState.shared.seconds = seconds

        // 存在性证明：探针确实跑起来了。与「有没有收到通知」严格区分。
        sink.append("probe|start|\(isoNow())|pid=\(ProcessInfo.processInfo.processIdentifier)")
        registerDarwinNotifications()

        // 时序：首次 deadline 设成 .now() → t=0 就写第一条心跳，之后每满 1 秒一条，
        // 到 t = seconds 时不再写并退出。于是 --seconds N 的行数恒为
        // probe|start 1 + session N + LOCKPROBE_DONE 1。
        let startUptime = DispatchTime.now().uptimeNanoseconds
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .seconds(1), leeway: .milliseconds(1))
        timer.setEventHandler {
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startUptime) / 1_000_000_000.0
            let state = ProbeState.shared
            // 墙钟退出是主判据；心跳计数只是抖动兜底，保证恰好 N 条而不是 N±1 条。
            if elapsed >= Double(state.seconds) || state.heartbeats >= state.seconds {
                timer.cancel()
                finish()
            }
            state.heartbeats += 1
            state.sink?.append(sessionLine())
        }
        timer.resume()

        dispatchMain()
    }
}
