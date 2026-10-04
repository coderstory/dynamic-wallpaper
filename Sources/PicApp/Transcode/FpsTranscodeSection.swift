import SwiftUI
import PicCore

/// 降帧区块 —— 设置窗的第三个 TAB。照 `.planning/design/ui-fps-tab.html` 五个状态。
///
/// 复用转码页那一套组件（CompactCard / IconBox / StatusBar / SectionHead / GlowButton），
/// 不自造。⚠️ 进度条宽度是 `96 * percent` 而不是 `96 * percent / 100` ——
/// `ProgressParser.percent` 返回的已经是 0…1（转码页那个除以 100 是既有的 bug，
/// 本页不跟）。
struct FpsTranscodeSection: View {
    @ObservedObject var viewModel: FpsTranscodeViewModel
    @Binding var showingPathways: Bool

    private let progressWidth: CGFloat = 96

    var body: some View {
        VStack(spacing: Metrics.blockGap) {
            availabilityBar
            SectionHead(t: "帧率表", badge: tableBadge)
            tableCard
            SectionHead(t: "待降帧", badge: queueBadge)
            queueCard
            hint
            toolbar
        }
    }

    // MARK: - 帧率表卡

    private var tableBadge: String? {
        guard viewModel.tableTotal > 0 else { return nil }
        return "\(viewModel.tableTotal) 行"
    }

    private var tableCard: some View {
        CompactCard {
            CompactRow(symbol: "cylinder.split.1x2", title: "帧率表",
                       sub: tableSubLine) {
                countText(viewModel.tableTotal, dim: viewModel.tableTotal == 0)
            }
            CompactRow(symbol: viewModel.jobs.isEmpty ? "checkmark" : "exclamationmark.triangle",
                       title: "高于 \(Int(FpsDownscaleCommand.maxFrameRate))fps",
                       sub: "解码省 4.5×，缩到 2560×1440", warn: !viewModel.jobs.isEmpty) {
                countText(viewModel.jobs.count, warn: !viewModel.jobs.isEmpty)
            }
            CompactRow(symbol: "checkmark", title: "已是 \(Int(FpsDownscaleCommand.maxFrameRate))fps",
                       sub: "无需处理") {
                countText(viewModel.okAt30Count, ok: viewModel.okAt30Count > 0)
            }
        }
        .accessibilityIdentifier("fps-scan-badge")
    }

    /// 副行要说清「哪些读表、哪些探测」—— 否则用户看到 491 会以为是全量重扫。
    private var tableSubLine: String {
        if viewModel.isScanning { return "本次探测 \(viewModel.scannedCount - viewModel.reusedCount) · 表内复用 \(viewModel.reusedCount)" }
        guard viewModel.scannedCount > 0 else { return "尚未扫描" }
        return "上次扫描 \(viewModel.scannedCount) 个文件"
    }

    // MARK: - 队列卡

    private var queueBadge: String? {
        if viewModel.isScanning { return "探测中" }
        guard !viewModel.jobs.isEmpty else { return nil }
        return "\(viewModel.jobs.count) 个文件"
    }

    @ViewBuilder
    private var queueCard: some View {
        CompactCard {
            if viewModel.isEmpty {
                // 空态要说清「为什么空」和「下一步」—— 这是「不需要处理」不是「没找到文件」。
                Text("片库里没有高于 \(Int(FpsDownscaleCommand.maxFrameRate))fps 的文件，无需处理。新增文件后点「重新扫描」。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.pMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .padding(Metrics.tilePaddingH)
            } else if viewModel.jobs.isEmpty {
                Text("扫描完成，没有需要降帧的文件。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.pMuted)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .padding(Metrics.tilePaddingH)
            } else {
                // ⚠️ 全 app 第二个 ScrollView（第一个是转码队列，例外已存档 UI-SPEC §8）。
                // 198 行不滚会让窗口长到几千 pt。
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.jobs) { job in
                            jobRow(job)
                            if job.id != viewModel.jobs.last?.id {
                                Rectangle().fill(Color.pSep).frame(height: 1)
                            }
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .accessibilityIdentifier("fps-queue-badge")
    }

    private func jobRow(_ job: FpsTranscodeQueue.Job) -> some View {
        HStack(spacing: Metrics.rowGap) {
            IconBox(symbol: stateSymbol(job.state), warn: isFailure(job.state))
            VStack(alignment: .leading, spacing: 2) {
                Text(job.sourceURL.lastPathComponent)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.pFg)
                    .lineLimit(1)
                    .truncationMode(.middle)
                // 副标题写成「60fps → 30」而不是只写源帧率 —— 箭头那一侧就是这行存在的理由。
                Text("\(Int(job.fps))fps → \(Int(FpsDownscaleCommand.maxFrameRate)) · \(viewModel.sizeText(of: job))")
                    .font(mono(11))
                    .monospacedDigit()
                    .foregroundStyle(Color.pMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                Text(stateLabel(job.state))
                    .font(mono(10.5))
                    .foregroundStyle(isFailure(job.state) ? Color.pWarnFg : Color.pAccent)
                progressBar(job)
                    .frame(width: progressWidth, height: 4)
            }
        }
        .padding(.horizontal, Metrics.tilePaddingH)
        .padding(.vertical, 10)
        .accessibilityIdentifier("fps-job-\(job.id)")
    }

    private func progressBar(_ job: FpsTranscodeQueue.Job) -> some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.pTrack)
            if let percent = job.percent {
                Capsule().fill(Color.pAccent).frame(width: progressWidth * percent)
            } else {
                Capsule().fill(Color.pAccent.opacity(0.5)).frame(width: 28)
            }
        }
    }

    private func stateSymbol(_ state: FpsTranscodeQueue.JobState) -> String {
        switch state {
        case .pending: return "clock"
        case .running: return "play.circle.fill"
        case .done: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        }
    }

    /// reason 是受控 token，不是 ffmpeg 原始日志。
    private func stateLabel(_ state: FpsTranscodeQueue.JobState) -> String {
        switch state {
        case .pending: return "待降帧"
        case .running: return "降帧中"
        case .done: return "已完成"
        case .failed(let reason): return "失败 · \(reason)"
        }
    }

    private func isFailure(_ state: FpsTranscodeQueue.JobState) -> Bool {
        if case .failed = state { return true }
        return false
    }

    private func countText(_ n: Int, warn: Bool = false, ok: Bool = false, dim: Bool = false) -> some View {
        Text("\(n)")
            .font(mono(17, .semibold))
            .monospacedDigit()
            .foregroundStyle(warn ? Color.pWarnFg : ok ? Color(red: 0.12, green: 0.48, blue: 0.30)
                                   : dim ? Color.pMuted : Color.pAccent)
    }

    // MARK: - 状态条 / 提示 / 工具行

    private var availabilityBar: some View {
        StatusBar(text: statusText,
                  meta: statusMeta,
                  warn: !isAvailable)
            .overlay(alignment: .trailing) {
                if !isAvailable {
                    Button("安装途径…") { showingPathways = true }
                        .buttonStyle(GlowButton())
                        .accessibilityIdentifier("fps-pathways")
                }
            }
            .onAppear {
                viewModel.refresh()
                viewModel.scan()
            }
    }

    private var isAvailable: Bool {
        if case .available = viewModel.availability { return true }
        return false
    }

    private var statusText: String {
        if !isAvailable { return "ffmpeg 未安装" }
        if viewModel.isScanning { return "扫描中 · 已探测 \(viewModel.scannedCount)" }
        if viewModel.isRunning { return "降帧中 · \(doneCount) / \(viewModel.jobs.count) 完成" }
        if viewModel.isPaused { return "已暂停 · \(doneCount) / \(viewModel.jobs.count) 完成" }
        if viewModel.jobs.isEmpty { return "无需降帧 · 片库帧率都已达标" }
        return "就绪 · \(viewModel.jobs.count) 个文件高于 \(Int(FpsDownscaleCommand.maxFrameRate))fps"
    }

    private var statusMeta: [String] {
        guard isAvailable else { return ["其余壁纸功能不受影响"] }
        if viewModel.isScanning { return ["本次探测 \(viewModel.scannedCount)"] }
        var meta: [String] = []
        if viewModel.okAt30Count > 0 { meta.append("\(viewModel.okAt30Count) 个无需处理") }
        meta.append("ffmpeg 就绪")
        return meta
    }

    private var doneCount: Int {
        viewModel.jobs.filter { $0.state == .done }.count
    }

    private var hint: some View {
        Text("产物输出到 Converted 子文件夹，原文件不动 · 转码成功后壁纸轮换池里那一条替换成产物，池大小不变 · 帧率表记住每个文件的帧率，再次扫描只探新文件")
            .font(.system(size: 11))
            .foregroundStyle(Color.pMuted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var toolbar: some View {
        HStack(spacing: 9) {
            Button("重新扫描") { viewModel.scan() }
                .buttonStyle(GlowButton())
                .disabled(viewModel.isRunning || viewModel.isScanning)
                .accessibilityIdentifier("fps-rescan")
            // 暂停时「继续」才是主按钮，「开始降帧」退为次要。
            if viewModel.isPaused {
                Button("继续") { viewModel.resume() }
                    .buttonStyle(GlowButton(primary: true))
                    .accessibilityIdentifier("fps-resume")
            } else {
                Button("开始降帧") { viewModel.start() }
                    .buttonStyle(GlowButton(primary: true))
                    .disabled(!viewModel.canStart)
                    .accessibilityIdentifier("fps-start")
            }
            Button("暂停") { viewModel.pause() }
                .buttonStyle(GlowButton())
                .disabled(!viewModel.canPause)
                .accessibilityIdentifier("fps-pause")
            Button("取消") { viewModel.cancel() }
                .buttonStyle(GlowButton())
                .disabled(!viewModel.canCancel)
                .accessibilityIdentifier("fps-cancel")
            Spacer(minLength: 0)
            if viewModel.isRunning {
                Text(viewModel.isPaused ? "已暂停" : "降帧中…")
                    .font(mono(11))
                    .foregroundStyle(Color.pAccent)
            }
        }
    }
}