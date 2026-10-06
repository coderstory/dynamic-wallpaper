import SwiftUI
import PicCore

/// 转码区块 —— 设置窗的第二个 TAB。全 app 唯一出现列表的地方。
struct TranscodeSection: View {
    @ObservedObject var viewModel: TranscodeViewModel
    @Binding var showingPathways: Bool
    let refresh: () -> Void

    @State private var selectedJobID: TranscodeJob.ID?

    var body: some View {
        VStack(spacing: Metrics.blockGap) {
            availabilityBar

            SectionHead(t: "待转码", badge: viewModel.jobs.isEmpty ? nil : "\(viewModel.jobs.count) 个任务")
            CompactCard {
                if viewModel.jobs.isEmpty {
                    Text("没有待转码的文件。壁纸目录里的 MKV / AVI / WEBM 会出现在这里。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.pMuted)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .padding(Metrics.tilePaddingH)
                } else {
                    // 队列不设上限，maxHeight 必须封顶，否则窗口会长到几千 pt（与降帧页同规则）。
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
            .accessibilityIdentifier("transcode-badge")

            VStack(alignment: .leading, spacing: 6) {
                Text(commandOwner == nil ? "将要执行的命令" : "当前任务的命令")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.pLabel)
                Text(commandOwner?.commandDisplay ?? "选中一行查看它将要执行的完整命令。")
                    .font(mono(11))
                    .foregroundStyle(Color.pFg)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.pChipBg)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(Color.pEdge, lineWidth: 1)
                    )
            }
            .accessibilityIdentifier("transcode-command")

            Text("产物输出到壁纸目录的 Converted 子文件夹 · 自动扫描的源文件转码成功后自动删除 · 手动选择的源文件保留 · 产物不会再进入待转码队列")
                .font(.system(size: 11))
                .foregroundStyle(Color.pMuted)
                .fixedSize(horizontal: false, vertical: true)

            toolbar
        }
    }

    /// ffmpeg 可用性容器。已安装时不给「安装途径」入口：装好了还摆个安装按钮会让人以为没装成功。
    private var availabilityBar: some View {
        StatusBar(text: isAvailable ? "ffmpeg 已就绪" : "ffmpeg 未安装",
                  meta: isAvailable ? [] : ["其余壁纸功能不受影响"],
                  warn: !isAvailable)
            .overlay(alignment: .trailing) {
                if !isAvailable {
                    Button("安装途径…") { showingPathways = true }
                        .buttonStyle(GlowButton())
                        .accessibilityIdentifier("transcode-pathways")
                }
            }
            // 本区块的 onAppear 宿主不能删：不调 refresh 会让 availability 停在初始值 .unavailable
            .onAppear {
                refresh()
                viewModel.refresh()
                viewModel.loadCandidates()
            }
    }


    private var isAvailable: Bool {
        if case .available = viewModel.availability { return true }
        return false
    }


    private func jobRow(_ job: TranscodeJob) -> some View {
        HStack(spacing: Metrics.rowGap) {
            IconBox(symbol: stateSymbol(job.state), warn: isFailure(job.state))
            VStack(alignment: .leading, spacing: 2) {
                Text(job.sourceURL.lastPathComponent)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.pFg)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(job.sourceURL.pathExtension.uppercased()) · \(viewModel.sizeText(of: job))")
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
                // 未知进度时给一条固定细条，不假装知道百分比。
                progressBar(job)
                    .frame(width: 96, height: 4)
            }
        }
        .padding(.horizontal, Metrics.tilePaddingH)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { selectedJobID = job.id }
        .accessibilityIdentifier("transcode-job-\(job.id)")
    }

    /// `percent` 来自 `ProgressParser.percent`，量纲是 **0…1**（不是 0…100）——
    /// 先前这里又除了一次 100，进度条最大只有 0.96pt，肉眼恒为空。
    private func progressBar(_ job: TranscodeJob) -> some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.pTrack)
            if let percent = job.percent {
                Capsule().fill(Color.pAccent).frame(width: 96 * percent)
            }
            // 没有读数就不画填充条。给一条固定宽度的「占位细条」会被读成「已经开始了
            // 一点点」，而它代表的其实是「还没开始」——未开始就该是 0。
        }
    }

    private func stateSymbol(_ state: TranscodeJobState) -> String {
        switch state {
        case .pending: return "clock"
        case .running: return "play.circle.fill"
        case .succeeded: return "checkmark.circle.fill"
        case .skipped: return "minus.circle.fill"
        case .failed: return "xmark.octagon.fill"
        }
    }

    /// reason 是受控 token（`disk_space` / `ffmpeg_unavailable` / …），不是自由文本。
    private func stateLabel(_ state: TranscodeJobState) -> String {
        switch state {
        case .pending: return "待转码"
        case .running: return "转码中"
        case .succeeded: return "已完成"
        case .skipped: return "已跳过"
        case .failed(let reason): return "失败 · \(reason)"
        }
    }

    private func isFailure(_ state: TranscodeJobState) -> Bool {
        if case .failed = state { return true }
        return false
    }


    private var commandOwner: TranscodeJob? {
        viewModel.jobs.first { $0.state == .running }
            ?? viewModel.jobs.first { $0.id == selectedJobID }
    }


    private var toolbar: some View {
        HStack(spacing: 9) {
            // 手动来源：目录递归展开成候选，转码成功后源文件保留
            Button("选择目录或文件…") {
                Task { await viewModel.loadPickedSources() }
            }
            .buttonStyle(GlowButton())
            .accessibilityIdentifier("transcode-pick")
            Button("重新查找待转码文件") { viewModel.loadCandidates() }
                .buttonStyle(GlowButton())
                .accessibilityIdentifier("transcode-rescan")
            Button("开始转码") { viewModel.startTranscoding() }
                .buttonStyle(GlowButton(primary: true))
                .disabled(!canStart)
                .accessibilityIdentifier("transcode-start")
            Spacer(minLength: 0)
            if viewModel.isRunning {
                Text("转码中…")
                    .font(mono(11))
                    .foregroundStyle(Color.pAccent)
            }
        }
    }

    private var canStart: Bool {
        !viewModel.isRunning && viewModel.jobs.contains { $0.state == .pending }
    }
}