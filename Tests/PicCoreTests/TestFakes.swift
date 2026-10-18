// 仅供测试的假观察者/探针，别在生产代码引用。
// 由多份测试文件里逐字节相同的替身收敛而来；各文件改用同一份后，替身与被测协议
// 同形变化时只需改这里。

import Foundation
@testable import PicCore

/// `PlaybackTarget` 替身：记录 seek / apply 调用序列，位置可编程。
final class FakeTarget: PlaybackTarget {
    var position: TimeInterval = 0
    var seeks: [TimeInterval] = []
    var applies: [PlaybackDecision] = []

    func arbiterCurrentPosition() -> TimeInterval { position }
    func arbiterSeek(to seconds: TimeInterval) { seeks.append(seconds) }
    func arbiterApply(_ decision: PlaybackDecision) { applies.append(decision) }
}

/// which 替身：status 是 terminationStatus 语义，path 是 stdout 去空白（nil = 空串）。
struct FakeWhich: WhichProbing {
    let status: Int32
    let path: String?
    func whichFFmpeg() -> (status: Int32, path: String?) { (status, path) }
}

/// 文件系统替身：集合外的路径 = 不存在**或**存在但不可执行（判定不可区分，故并为一类）。
struct FakeFS: ExecutableFileProbing {
    let executables: Set<String>
    func isExecutableFile(atPath path: String) -> Bool { executables.contains(path) }
}
