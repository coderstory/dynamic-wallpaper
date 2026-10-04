import SwiftUI
import PicCore

/// 转码窗口主体（UI-SPEC §8 —— 全 app 唯一出现列表的地方，例外已存档）。
///
/// 四要素：ffmpeg 徽章 / 待转码队列表 / 底部实际命令（可审计）/ 产物规则说明。
/// 深色令牌与组件全部复用设置窗那一套，不自造。
struct TranscodeWindowView: View {

    @ObservedObject var viewModel: TranscodeViewModel

    @State private var showingPathways = false
    /// 底部命令区展示谁：running 优先，其次用户点选的那条。
    @State private var selectedJobID: TranscodeJob.ID?

    var body: some View {
        VStack(spacing: 0) {
            // 自绘标题行（hiddenTitleBar 下唯一的「标题栏」，与设置窗同款深蓝主题）。
            Text("转码")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.pFg)
                .frame(maxWidth: .infinity)
                .padding(.top, 10).padding(.bottom, 8)
                .contentShape(Rectangle())
            VStack(alignment: .leading, spacing: 12) {
                badge
                SectionHead(t: "待转码")
                jobList
                commandBlock
                rules
                toolbar
            }
            .padding(.horizontal, 14).padding(.bottom, 14)
        }
        // max 系列让深色背景填满窗口任意尺寸 —— 内容紧贴高度时，状态恢复把窗口撑大
        // 会露出大片系统默认白底（用户报「大白的空白」）。
        .frame(minWidth: 520, idealWidth: 640,
               maxWidth: .infinity, maxHeight: .infinity,
               alignment: .topLeading)
        .background(
            ZStack {
                Color.pBg
                LinearGradient(colors: [Color(red: 76/255, green: 196/255, blue: 245/255).opacity(0.07), Color.clear],
                               startPoint: .top, endPoint: .center)
            }
            .ignoresSafeArea()
        )
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingPathways) {
            InstallPathwaysView(onRecheck: { viewModel.refresh() })
        }
    }

    // MARK: - 徽章

    private var badge: some View {
        Card {
            Row(symbol: badgeSymbol, title: badgeTitle, sub: badgeSub, warn: !isAvailable, hairline: false) {
                if !isAvailable {
                    // 徽章这一侧是「提示」，不是入口 —— 点它弹途径说明即可。
                    Button("安装途径…") { showingPathways = true }
                        .buttonStyle(GlowButton())
                        .accessibilityIdentifier("transcode-pathways")
                } else {
                    Text("").frame(width: 0)
                }
            }
            .accessibilityIdentifier("transcode-badge")
        }
    }

    private var isAvailable: Bool {
        if case .available = viewModel.availability { return true }
        return false
    }

    private var badgeSymbol: String { isAvailable ? "checkmark.seal.fill" : "exclamationmark.triangle.fill" }

    private var badgeTitle: String { isAvailable ? "ffmpeg 已就绪" : "ffmpeg 未安装" }

    private var badgeSub: String? {
        if case .available(let path) = viewModel.availability { return path }
        return "其余壁纸功能不受影响 · 点右侧查看三条安装途径"
    }

    // MARK: - 队列表

    /// 表格壳**常驻**：空态也显示卡片框（用户语义「待转码就是个表格」），空文案画在框内。
    private var jobList: some View {
        Card {
            if viewModel.jobs.isEmpty {
                Text("没有待转码的文件。壁纸目录里的 MKV / AVI / WEBM 会出现在这里。")
                    .font(mono(10.5))
                    .foregroundStyle(Color.pFg.opacity(0.5))
                    .frame(maxWidth: .infinity, minHeight: 56)
            } else {
                ForEach(viewModel.jobs) { job in
                    jobRow(job)
                    if job.id != viewModel.jobs.last?.id {
                        Divider().overlay(Color.pSep)
                    }
                }
            }
        }
    }

    private func jobRow(_ job: TranscodeJob) -> some View {
        Row(symbol: stateSymbol(job.state), title: job.sourceURL.lastPathComponent,
            sub: "\(job.sourceURL.pathExtension.uppercased()) · \(viewModel.sizeText(of: job))",
            warn: isFailure(job.state), hairline: false) {
            VStack(alignment: .trailing, spacing: 3) {
                Text(stateLabel(job.state)).font(mono(10.5))
                    .foregroundStyle(isFailure(job.state) ? Color.pWarn : Color.pAccent)
                progressBar(job)
                    .frame(width: 96, height: 4)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { selectedJobID = job.id }
    }

    /// 未知进度时给一条不确定态细条，不假装知道百分比。
    private func progressBar(_ job: TranscodeJob) -> some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.pDim.opacity(0.18))
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

    // MARK: - 底部命令

    private var commandBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(commandOwner == nil ? "将要执行的命令" : "当前任务的命令")
                .font(mono(10.5, .semibold))
                .foregroundStyle(Color(red: 120/255, green: 200/255, blue: 255/255).opacity(0.62))
            Text(commandOwner?.commandDisplay ?? "选中一行查看它将要执行的完整命令。")
                .font(mono(10.5))
                .foregroundStyle(Color.pFg.opacity(0.9))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.pCard))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.pSep, lineWidth: 1))
        }
        .accessibilityIdentifier("transcode-command")
    }

    private var commandOwner: TranscodeJob? {
        viewModel.jobs.first { $0.state == .running }
            ?? viewModel.jobs.first { $0.id == selectedJobID }
    }

    // MARK: - 产物规则 + 工具行

    private var rules: some View {
        Hint(t: "产物输出到壁纸目录的 Converted 子文件夹 · 自动扫描的源文件转码成功后自动删除 · 手动选择的源文件保留 · 产物不会再进入待转码队列")
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
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
            Spacer()
            if viewModel.isRunning {
                Text("转码中…").font(mono(10.5)).foregroundStyle(Color.pAccent)
            }
        }
    }

    private var canStart: Bool {
        !viewModel.isRunning && viewModel.jobs.contains { $0.state == .pending }
    }
}