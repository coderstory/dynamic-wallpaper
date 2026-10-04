import SwiftUI
import PicCore

/// 转码区块 —— 原「转码窗口」内容，2026-10-04 起并入设置窗，作为第二个 TAB。
///
/// 与设计稿 `.planning/design/ui-rotation-a.html` 的转码页一一对应。
/// 全 app 唯一出现列表的地方（例外已在 UI-SPEC §8 存档）。
///
/// 四要素：ffmpeg 徽章 / 待转码队列表 / 底部实际命令（可审计）/ 产物规则说明。
/// 深色令牌已换晨雾浅色，组件复用设置窗那一套，不自造。
struct TranscodeSection: View {
    @ObservedObject var viewModel: TranscodeViewModel
    @Binding var showingPathways: Bool
    let refresh: () -> Void

    /// 底部命令区展示谁：running 优先，其次用户点选的那条。
    @State private var selectedJobID: TranscodeJob.ID?

    var body: some View {
        VStack(spacing: Metrics.blockGap) {
            availabilityBar

            SectionHead(t: "待转码", badge: viewModel.jobs.isEmpty ? nil : "\(viewModel.jobs.count) 个任务")
            CompactCard {
                if viewModel.jobs.isEmpty {
                    // 空态画在卡内：用户语义「待转码就是个表格」。
                    Text("没有待转码的文件。壁纸目录里的 MKV / AVI / WEBM 会出现在这里。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.pMuted)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .padding(Metrics.tilePaddingH)
                } else {
                    ForEach(viewModel.jobs) { job in
                        jobRow(job)
                        if job.id != viewModel.jobs.last?.id {
                            Rectangle().fill(Color.pSep).frame(height: 1)
                        }
                    }
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

    /// ffmpeg 可用性容器。**已安装时只显示一行状态，不给「安装途径」入口** ——
    /// 装好了还摆个安装按钮会让人以为没装成功。容器本身就是未安装时的出口。
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
            // ⚠️ 转码并入设置窗后本区块不再有 `.onAppear` 的宿主（旧版是 TranscodeScene 的
            // 壳在 onAppear 调 refresh + loadCandidates）。不补这里，availability 会停在
            // 初始值 `.unavailable`，装好的 ffmpeg 也显示「未安装」。
            .onAppear {
                refresh()
                viewModel.refresh()
                viewModel.loadCandidates()
            }
    }

    // MARK: - 状态

    private var isAvailable: Bool {
        if case .available = viewModel.availability { return true }
        return false
    }

    // MARK: - 队列行

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
                // 未知进度时给一条不确定态细条，不假装知道百分比。
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

    private func progressBar(_ job: TranscodeJob) -> some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.pTrack)
            if let percent = job.percent {
                Capsule().fill(Color.pAccent).frame(width: 96 * percent / 100)
            } else {
                Capsule().fill(Color.pAccent.opacity(0.5)).frame(width: 28)
            }
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

    // MARK: - 命令

    private var commandOwner: TranscodeJob? {
        viewModel.jobs.first { $0.state == .running }
            ?? viewModel.jobs.first { $0.id == selectedJobID }
    }

    // MARK: - 工具行

    private var toolbar: some View {
        HStack(spacing: 9) {
            // 用户手动选择目录/文件（目录递归展开成 N 个候选）—— 手动来源的源文件不删。
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