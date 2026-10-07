import SwiftUI
import PicCore

/// 转码/降帧任务状态在 UI 上的统一展示。两个 Section 的 stateSymbol/stateLabel/isFailure
/// 三件套收敛到这里 —— 状态枚举各自实现，展示逻辑只有一份。
/// `Sendable` 是 `QueueRow` 要求的：它以 `any JobStatePresenting` 持有状态，要跨 MainActor 边界传。
/// 两份状态枚举都是带 String 负载的值类型，加这个约束零成本。
protocol JobStatePresenting: Sendable {
    var symbol: String { get }
    var label: String { get }
    var isFailure: Bool { get }
}

extension TranscodeJobState: JobStatePresenting {
    var symbol: String {
        switch self {
        case .pending: return "clock"
        case .running: return "play.circle.fill"
        case .succeeded: return "checkmark.circle.fill"
        case .skipped: return "minus.circle.fill"
        case .failed: return "xmark.octagon.fill"
        }
    }
    var label: String {
        switch self {
        case .pending: return "待转码"
        case .running: return "转码中"
        case .succeeded: return "已完成"
        case .skipped: return "已跳过"
        case .failed(let reason): return "失败 · \(reason)"
        }
    }
    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}

extension FpsTranscodeQueue.JobState: JobStatePresenting {
    var symbol: String {
        switch self {
        case .pending: return "clock"
        case .running: return "play.circle.fill"
        case .done: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        case .cancelled: return "slash.circle"
        }
    }
    var label: String {
        switch self {
        case .pending: return "待降帧"
        case .running: return "降帧中"
        case .done: return "已完成"
        case .cancelled: return "已取消"
        case .failed(let reason): return "失败 · \(reason)"
        }
    }
    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}
