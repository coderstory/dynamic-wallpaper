import Foundation
import PicCore

/// 统一队列的一行 —— 转码与降帧各自映射到这里，合并只发生在视图层。
/// 不合并两个 ViewModel：它们有 9 处语义差异，见 SwiftUI-HANDOFF.md 第 7 节。
struct QueueRow: Identifiable {
    enum Kind { case transcode, fps }
    let kind: Kind
    /// sourceURL.path —— 两个队列各自内部都唯一。
    let id: String
    let fileName: String
    /// 「MKV · 412 MB」（转码）/「120fps → 60 · 284 MB」（降帧）。
    let meta: String
    let state: any JobStatePresenting
    /// 未知进度必须是 nil，不要用 0 冒充（0 是「已开始但还没进度」）。
    let percent: Double?

    init(_ job: TranscodeJob, sizeText: String) {
        self.kind = .transcode
        self.id = job.sourceURL.path
        self.fileName = job.sourceURL.lastPathComponent
        self.meta = "\(job.sourceURL.pathExtension.uppercased()) · \(sizeText)"
        self.state = job.state
        self.percent = job.percent
    }

    init(_ job: FpsTranscodeQueue.Job, sizeText: String) {
        self.kind = .fps
        self.id = job.sourceURL.path
        self.fileName = job.sourceURL.lastPathComponent
        self.meta = "\(Int(job.fps))fps → \(Int(FpsDownscaleCommand.maxFrameRate)) · \(sizeText)"
        self.state = job.state
        self.percent = job.percent
    }

    /// 两个队列的行**各自保持原顺序、转码整段排在降帧之前**：队列顺序就是执行顺序。
    static func rows(transcode: [TranscodeJob], fps: [FpsTranscodeQueue.Job],
                     sizeText: (URL) -> String) -> [QueueRow] {
        transcode.map { QueueRow($0, sizeText: sizeText($0.sourceURL)) }
            + fps.map { QueueRow($0, sizeText: sizeText($0.sourceURL)) }
    }
}
