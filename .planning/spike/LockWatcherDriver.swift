// LockWatcherDriver.swift —— Plan 03-01 T1 的一次性 throwaway 驱动。
//
// 目的：证明「`LockWatcher.start()` 同步投递当前值」与「合成通知走完
// `LockWatcher → HoldArbiter.set → PlaybackTarget.arbiterApply`」这两件事真的发生。
//
// ⚠️ 三条纪律（照 Phase 1 LockProbe 的写法）：
//   ① **绝不往系统通知名投合成事件**。本驱动一律用 `com.local.pic.tests.lock.` 前缀 ——
//      `com.apple.screenIsLocked` 由别的进程投递，投它会让同机的其它壁纸 app 一起暂停。
//   ② `LOCK_START_SYNC_DELIVERED` 必须在**投递任何合成通知之前**打。它的取证价值全在于
//      「没有等任何跃迁」；顺序反了它就退化成「收到通知后打的」。
//   ③ 屏幕锁着，真实跃迁观测不到 —— 如实记 `LOCK_TRANSITION=unobservable`，不冒充已验证。
//
// 编译（scripts/probe-lock.sh 做这件事）：把**产品源码**与本驱动一起编进来，
// 证据跑的是产品代码，不是探针里重写一遍的逻辑：
//   swiftc -parse-as-library -o lockwatcher-driver \
//     Sources/PicCore/State/HoldReason.swift Sources/PicCore/State/PlaybackDecision.swift \
//     Sources/PicCore/State/HoldArbiter.swift Sources/PicCore/System/LockWatcher.swift \
//     .planning/spike/LockWatcherDriver.swift
//
// 本文件不引入播放框架（D-09），自带一个记录式的 PlaybackTarget 实现。

import Foundation
import CoreGraphics

/// 合成通知前缀 —— 绝不投系统通知名。
let signalPrefix = "com.local.pic.tests.lock."

let names = LockSignalNames(locked: "\(signalPrefix)locked", unlocked: "\(signalPrefix)unlocked")

/// 会话字典夹具。通知**只当触发器**（T-03-01）：收到后 `LockWatcher` 重读这里，
/// 所以投「已解锁」通知时必须先把夹具翻成未锁，否则读到仍是锁着就不会恢复播放。
final class SessionFixture: @unchecked Sendable {
    var locked = true
    var dict: [String: Any] { ["CGSSessionScreenIsLocked": locked ? 1 : 0] }
}

/// 记录式播放端：只记 apply / seek，不碰任何播放框架。
final class RecordingTarget: PlaybackTarget {
    var position: TimeInterval = 0
    var seeks: [TimeInterval] = []
    var applies: [PlaybackDecision] = []

    func arbiterCurrentPosition() -> TimeInterval { position }
    func arbiterSeek(to seconds: TimeInterval) { seeks.append(seconds) }
    func arbiterApply(_ decision: PlaybackDecision) { applies.append(decision) }
}

/// 每行立刻 flush —— 进程可能被 kill，不能靠退出时统一 flush。
func emit(_ line: String) {
    print(line)
    fflush(stdout)
}

func holdList(_ decision: PlaybackDecision) -> String {
    let list = decision.activeReasons.map { String(describing: $0) }.joined(separator: ",")
    return list.isEmpty ? "(none)" : "(\(list))"
}

@main
struct LockWatcherDriver {
    @MainActor
    static func main() {
        // 真实会话状态：本机锁着。合成通知**不**改变它，只是证据行如实记一次读数。
        let realSession = CGSessionCopyCurrentDictionary() as? [String: Any]
        let realLocked = LockWatcher.lockState(fromSession: realSession)

        let fixture = SessionFixture()
        fixture.locked = realLocked

        let target = RecordingTarget()
        target.position = 42.0
        let arbiter = HoldArbiter(target: target)

        // 注入的分布式通知中心 —— 与系统中心隔离，投它不影响整机。
        let center = DistributedNotificationCenter()
        let watcher = LockWatcher(center: center, names: names, sessionReader: { fixture.dict })

        var notificationsSeen = 0
        var syncDelivered = false

        // start() 会**同步**回调一次。这第一次回调只打 LOCK_START_SYNC_DELIVERED ——
        // 它的取证价值全在于「没有等任何跃迁」，所以它必须与后续「收到通知」的行分开，
        // 计数也分开（`LOCK_SIGNAL_COUNT` 只数通知投递的那两次）。
        watcher.start { locked in
            arbiter.set(.screenLocked, active: locked)

            if !syncDelivered {
                syncDelivered = true
                emit(String(format: "LOCK_START_SYNC_DELIVERED=1 locked=%d", locked ? 1 : 0))
                return
            }
            notificationsSeen += 1
            if locked {
                emit(String(format: "LOCK_HOLD_APPLIED holds=%@ resumeAt=%.3f",
                            holdList(arbiter.decision), target.position))
            } else {
                let anchored = !target.seeks.isEmpty
                let anchor = target.seeks.last ?? -1
                emit(String(format: "LOCK_RESUME seeks_to_anchor=%d seeks=%.3f holds=%@",
                            anchored ? 1 : 0, anchor, holdList(arbiter.decision)))
            }
        }

        emit("LOCK_SIGNAL_REGISTERED=1 center=DistributedNotificationCenter locked=\(names.locked) unlocked=\(names.unlocked)")

        // 第 2 秒：投合成锁屏信号（触发器）。夹具已是锁着 → 重读得到锁。
        RunLoop.main.run(until: Date().addingTimeInterval(2.0))
        fixture.locked = true
        emit("LOCK_SIGNAL_INJECTED name=\(names.locked) source=com.local.pic.tests")
        center.post(name: Notification.Name(names.locked), object: nil)
        RunLoop.main.run(until: Date().addingTimeInterval(2.0))

        // 第 4 秒：投合成解锁信号。**先翻夹具再投递** —— 否则重读仍是锁着，
        // 按 T-03-01 的纪律就不会恢复播放（那正是伪造投递防住的情形）。
        fixture.locked = false
        emit("LOCK_SIGNAL_INJECTED name=\(names.unlocked) source=com.local.pic.tests")
        center.post(name: Notification.Name(names.unlocked), object: nil)
        RunLoop.main.run(until: Date().addingTimeInterval(2.0))

        watcher.stop()

        // 真实跃迁：本会话屏幕一直锁着，没有跃迁可观测。如实记 unobservable。
        emit("LOCK_TRANSITION=unobservable reason=session_locked CGSSessionScreenIsLocked=\(realLocked ? 1 : 0)")

        emit("LOCK_SESSION_AT_START=1 real_CGSSessionScreenIsLocked=\(realLocked ? 1 : 0) session_keys=\(realSession?.count ?? 0)")
        emit("LOCK_SIGNAL_COUNT=\(notificationsSeen)")
        emit("LOCK_ANCHOR_PRESERVED=\(target.seeks.first == 42.0 ? 1 : 0) seeks=\(String(format: "%.3f", target.seeks.first ?? -1))")
    }
}