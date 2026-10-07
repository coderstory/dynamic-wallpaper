import SwiftUI
import AppKit
import PicCore

/// 设置窗主体：自绘标题行（状态胶囊常驻）+ 三个工作区（播放 / 片库 / 通用）+ 磁贴网格。
/// 六个可调项全部真绑定：`store.<键> = …` → `SettingsApplier.apply*()` → `store.persist()`，
/// 窗内不出现渲染假数据的 @State。
///
/// **`select-button` / `rescan-button` 从播放页位移到了片库页** —— 它们原本挂在「来源与系统」
/// 卡片上，而新 IA 把那块整体搬进了片库。依赖这两个标识的 XCUITest 断言要先去片库页。
struct SettingsView: View {
    @Environment(SettingsStore.self) private var store
    @Environment(SettingsApplier.self) private var applier
    @Environment(HoldArbiter.self) private var arbiter
    @Environment(SettingsSessionState.self) private var session

    /// 动作闭包一律经 PicApp 注入，视图不持有 AppDelegate。
    let requestFolder: () -> Void
    let rescanLibrary: () -> Void
    let reapplyBatteryHold: () -> Void
    let setLaunchAtLogin: (Bool) -> Void
    /// 转码视图模型，由 PicApp 注入。
    let transcodeViewModel: TranscodeViewModel
    /// 降帧视图模型，同样由 PicApp 注入，生命周期跟 AppDelegate。
    let fpsViewModel: FpsTranscodeViewModel
    /// 安装途径弹层的「重新检测」：重查并回填最新读数。
    let refreshFFmpeg: () -> Void
    /// 轮换内核。只读它的 `secondsUntilNextRotation()` / `interval` 画倒计时，不调任何行为方法。
    let rotation: RotationController

    /// ffmpeg 不可用时的安装途径弹层（置灰之外还得给出途径）。
    @State private var showingPathways = false

    // 速度滑杆的拖动暂态，每次 onChanged 直通 store + applier。
    @State private var rateDrag: Double = 1.0
    // 顶部 TAB：0 播放 / 1 片库 / 2 通用。
    @State private var tab: Int = 0
    @State private var queueFilter: QueueFilter = .all
    @State private var selectedJobID: String?

    private static let tabTitles = ["播放", "片库", "通用"]

    var body: some View {
        VStack(spacing: 0) {
            titleRow
            // TabBar 钉在顶部不跟滚：三页内容高度差很多，滚动时页签必须原地可点。
            TabBar(items: Self.tabTitles, index: $tab)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("main-tabs")
                .padding(.horizontal, Metrics.winPadding)
            // 窗口固定 760 高（AppDelegate 按最高的播放页给足），正常状态不出滚动条；
            // ScrollView 只是溢出的兜底：片库队列超长、或用户把窗拉小时才滚动。
            ScrollView {
                Group {
                    switch tab {
                    case 1: libraryTab
                    case 2: generalTab
                    // default 兜底回播放页。
                    default: playTab
                    }
                }
                .frame(maxWidth: .infinity)
                // 上下也用 blockGap：磁贴投影（y6 r10）需要这个余量，贴边会被 ScrollView 裁掉。
                .padding(.horizontal, Metrics.winPadding)
                .padding(.vertical, Metrics.blockGap)
            }
            // 极端小屏的保护：窗口被拉到比内容短时由滚动接住，不裁磁贴投影。
            .frame(maxHeight: max(480, (NSScreen.main?.visibleFrame.height ?? 900) - 120))
        }
        .frame(minWidth: SettingsPresentation.windowMinWidth,
               idealWidth: Metrics.windowWidth,
               maxWidth: .infinity, maxHeight: .infinity,
               alignment: .topLeading)
        .background(Color.pGround.ignoresSafeArea())
        .preferredColorScheme(.light)
        .onAppear(perform: seedAndObserve)
        // 窗已开时面板再发落地页请求（典型：设置开着，菜单里点「去片库转码」）。
        .onChange(of: session.requestedTab) { _, requested in
            guard let requested else { return }
            tab = requested
            session.requestedTab = nil
        }
        .sheet(isPresented: $showingPathways) {
            InstallPathwaysView(onRecheck: { refreshFFmpeg() })
        }
    }

    // ── 标题行 ──
    /// `windowStyle(.hiddenTitleBar)` 下唯一的「标题栏」。
    /// 状态胶囊放这里而不是播放页首行：状态是全局的，任何页都该看得见。
    /// 左内边距留给系统红绿灯，不能省 —— 省了「Pic」会压在关闭按钮上。
    private var titleRow: some View {
        HStack(spacing: 10) {
            Text("Pic")
                .font(display(13.5, .semibold))
                .foregroundStyle(Color.pInk)
            Spacer(minLength: 0)
            statusPill
                .lineLimit(1)
                .accessibilityIdentifier("status-paused")
        }
        .padding(.leading, 76)
        .padding(.trailing, Metrics.winPadding)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var statusPill: some View {
        if isEmpty {
            StatusPill(kind: .blocked, lead: "已暂停", rest: "· 没有可播文件")
        } else if arbiter.decision.activeReasons.isEmpty {
            StatusPill(kind: .playing, lead: "播放中",
                       rest: "· \(SettingsPresentation.playModeLabel(store.playMode))")
        } else {
            StatusPill(kind: .hold, lead: "已暂停",
                       rest: "· \(SettingsPresentation.joinedReasons(arbiter.decision.activeReasons))")
        }
    }

    // ── 播放 ──
    private var playTab: some View {
        VStack(spacing: Metrics.blockGap) {
            // 全宽磁贴是 VStack 直接子节点，不进 TileGrid（跨列声明会被静默丢掉，见 TileGrid 注释）。
            heroTile

            if !isEmpty {
                Eyebrow(text: "播放控制")
                // 半宽磁贴对，照抄原型：播放模式/轮换间隔、速度/声音都是 .tile 非 wide。
                TileGrid {
                    modeTile
                    rotationTile
                }
                TileGrid {
                    speedTile
                    volumeTile
                }
            }

            Eyebrow(text: "让路规则", badge: "什么时候不播")
            rulesTile
        }
    }

    @ViewBuilder
    private var heroTile: some View {
        if isEmpty {
            emptyTile
        } else {
            nowTile
        }
    }

    // ── 正在播放 / 让路（hero 磁贴，宽） ──
    private var nowTile: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 9) {
                    Circle()
                        .fill(heroTint)
                        .frame(width: 9, height: 9)
                        .background(
                            Circle().fill(heroTint.opacity(0.22)).frame(width: 15, height: 15)
                        )
                    Text(heroHeadline)
                        .font(display(16))
                        .foregroundStyle(Color.pInk)
                }
                Text(heroSummary)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.pInk2)
                    .fixedSize(horizontal: false, vertical: true)
                heroTags
            }
            Spacer(minLength: 0)
            rotationRing
        }
        .tileSurface()
    }

    private var isHeld: Bool { !arbiter.decision.activeReasons.isEmpty }
    private var heroTint: Color { isHeld ? .pHold : .pOk }

    private var heroHeadline: String {
        if isHeld {
            return "已暂停 · \(SettingsPresentation.joinedReasons(arbiter.decision.activeReasons))"
        }
        return "正在播放 · \(SettingsPresentation.playModeLabel(store.playMode))"
    }

    private var heroSummary: String {
        if isHeld {
            return "条件解除后会自动续播，不会从头开始。"
        }
        let every = SettingsPresentation.rotationLabel(
            minutes: SettingsPresentation.rotationMinutes(seconds: store.rotationInterval))
        return "\(session.playableCount) 个视频轮着放，每 \(every)换一个。关掉窗口也不会停。"
    }

    private var heroTags: some View {
        HStack(spacing: 7) {
            if isHeld {
                ForEach(arbiter.decision.activeReasons.sorted(), id: \.self) { reason in
                    TagChip(text: SettingsPresentation.holdReasonLabel(reason))
                }
            } else {
                TagChip(text: SettingsPresentation.rateLabel(store.rate), accent: true)
                TagChip(text: "\(SettingsPresentation.volumePercent(store.volume))% 音量")
                TagChip(text: "\(session.playableCount) 个视频")
            }
        }
    }

    // 倒计时环。TimelineView 每秒重算，不存 @State —— 读数是轮换器的纯派生量，
    // 存一份就会在 setInterval / advance 之后与真值对不上。
    private var rotationRing: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let remaining = rotation.secondsUntilNextRotation()
            ZStack {
                Circle().stroke(Color.pSurface3, lineWidth: 6)
                Circle()
                    .trim(from: 0, to: ringFraction(remaining))
                    .stroke(heroTint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 1) {
                    Text(remaining.map { mmss($0) } ?? "—")
                        .font(mono(13.5, .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.pInk)
                    Text(remaining == nil ? "不轮换" : "换下一个")
                        .font(.system(size: 8.5))
                        .foregroundStyle(Color.pInk3)
                }
            }
            .frame(width: 78, height: 78)
            .accessibilityElement()
            .accessibilityLabel(Text(remaining.map { "距下次换片还有 \(mmss($0))" } ?? "当前不轮换"))
        }
    }

    private func ringFraction(_ remaining: TimeInterval?) -> Double {
        guard let remaining, rotation.interval > 0 else { return 0 }
        return max(0, min(1, remaining / rotation.interval))
    }

    private func mmss(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // ── 空态（三变体完整区分） ──
    private var emptyTile: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(emptyMark)
                .font(.system(size: 17))
                .foregroundStyle(Color.pHold)
                .frame(width: 38, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: Metrics.ctlRadius, style: .continuous)
                        .fill(Color.pHoldSoft)
                )
            VStack(alignment: .leading, spacing: 0) {
                Text(emptyCopy?.title ?? "没有可播文件")
                    .font(display(14.5))
                    .foregroundStyle(Color.pInk)
                    .padding(.bottom, 7)
                // 逐字硬需求，三种变体共用同一句。
                Text(SettingsPresentation.emptyStateBody)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.pInk2)
                    .fixedSize(horizontal: false, vertical: true)
                if let reason = emptyCopy?.reason {
                    Text(reason)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.pInk3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                }
                if let folder = missingFolderPath {
                    Text(folder)
                        .font(mono(10.5))
                        .foregroundStyle(Color.pInk2)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: Metrics.ctlRadius, style: .continuous)
                                .fill(Color.pSurface2)
                        )
                        .padding(.top, 11)
                }
                HStack(spacing: 9) {
                    Button(emptyCopy?.primaryAction ?? "选择文件夹…") { emptyPrimaryAction() }
                        .buttonStyle(GlowButton(primary: true))
                        .accessibilityIdentifier("empty-primary")
                    Button("重新扫描") { rescanLibrary() }
                        .buttonStyle(GlowButton())
                        .disabled(session.isScanning)
                        .accessibilityIdentifier("empty-rescan")
                }
                .padding(.top, 15)
            }
            Spacer(minLength: 0)
        }
        .tileSurface()
    }

    private var emptyMark: String {
        switch session.lastLibraryState {
        case .folderUnconfigured: "▣"
        case .folderMissing: "!"
        default: "▤"
        }
    }

    /// 目录没了才显示上次的路径：让用户知道是「哪个位置」没了。
    private var missingFolderPath: String? {
        session.lastLibraryState == .folderMissing && !store.sourceFolder.isEmpty
            ? store.sourceFolder : nil
    }

    private func emptyPrimaryAction() {
        // 「扫到 0」的下一步是去片库转码，不是再选一次文件夹 —— 选了也还是 0。
        if session.lastLibraryState == .noPlayableVideos {
            tab = 1
        } else {
            requestFolder()
        }
    }

    // ── 播放模式 ──
    private var modeTile: some View {
        SettingsTile(title: "播放模式") {
            GlowSegmented(items: PlayMode.allCases.map(SettingsPresentation.playModeLabel),
                          index: modeIndex)
                .accessibilityIdentifier("mode-segmented")
        }
    }

    // ── 轮换间隔 ──
    private var rotationTile: some View {
        SettingsTile(title: "轮换间隔") {
            TickSelector(items: SettingsPresentation.rotationChoicesMinutes
                            .map(SettingsPresentation.rotationLabel(minutes:)),
                         index: rotationIndex)
                .accessibilityIdentifier("rotation-stepper")
        }
    }

    private var speedTile: some View {
        SettingsTile(title: "速度", tail: {
            Text("音高不变").font(.system(size: 10.5)).foregroundStyle(Color.pInk3)
        }) {
            HStack(spacing: 11) {
                GlowSlider(value: $rateDrag, range: 0.5...2,
                           label: "播放速度",
                           valueText: SettingsPresentation.rateLabel(store.rate), onChanged: {
                    store.rate = Float(rateDrag)
                    applier.applyRate()
                }, onEnded: {
                    store.persist()
                })
                .accessibilityIdentifier("rate-slider")
                Text(SettingsPresentation.rateLabel(store.rate))
                    .font(mono(12))
                    .monospacedDigit()
                    .foregroundStyle(Color.pInk)
                    .frame(width: Metrics.valueWidth, alignment: .trailing)
                    .accessibilityIdentifier("rate-value")
            }
        }
    }

    private var volumeTile: some View {
        SettingsTile(title: "声音") {
            HStack(spacing: 11) {
                GlowSlider(value: volumePercent, range: 0...100,
                           label: "音量",
                           valueText: "\(SettingsPresentation.volumePercent(store.volume))%",
                           onChanged: {
                    store.volume = SettingsPresentation.volumeFromPercent(
                        SettingsPresentation.volumePercent(store.volume))
                    applier.applyVolume()
                }, onEnded: {
                    store.persist()
                })
                .disabled(!SettingsPresentation.volumeControlsEnabled(isMuted: store.isMuted))
                .accessibilityIdentifier("volume-slider")
                Text("\(SettingsPresentation.volumePercent(store.volume))%")
                    .font(mono(12))
                    .monospacedDigit()
                    .foregroundStyle(Color.pInk)
                    .frame(width: Metrics.valueWidth, alignment: .trailing)
                    .accessibilityIdentifier("volume-value")
                // 静音时滑杆不可交互 + 视觉变淡。
                .opacity(SettingsPresentation.volumeControlsEnabled(isMuted: store.isMuted) ? 1 : 0.34)
                Toggle("", isOn: soundOn).toggleStyle(GlowToggle()).labelsHidden()
                    .accessibilityIdentifier("sound-toggle")
            }
        }
    }

    // ── 让路规则：四条不可关 + 一条可关 ──
    private var rulesTile: some View {
        SettingsTile(icon: "hand.raised", title: "这些情况会让路", tail: {
            Text("前四项不可关闭").font(.system(size: 10.5)).foregroundStyle(Color.pInk3)
        }) {
            VStack(alignment: .leading, spacing: Metrics.tileGap) {
                HStack(spacing: 7) {
                    ForEach(Self.fixedHoldReasons, id: \.self) { reason in
                        TagChip(text: SettingsPresentation.holdReasonLabel(reason))
                    }
                }
                TileRow(title: "电池供电", sub: "关掉它，用电池时也继续放（更费电）") {
                    Toggle("", isOn: playOnBattery).toggleStyle(GlowToggle()).labelsHidden()
                        .accessibilityIdentifier("battery-toggle")
                }
                Text("任何一项解除后自动续播，播放位置从暂停处继续——不会重头开始。")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.pInk3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 四条由系统信号决定、不可关的规则。`manualPause` 是用户自己的暂停不是让路条件，
    /// `battery` 是下面那个开关管的，两者都不进这个列表。
    private static let fixedHoldReasons: [HoldReason] =
        HoldReason.allCases.filter { $0 != .manualPause && $0 != .battery }

    // ── 片库 ──
    private var libraryTab: some View {
        VStack(spacing: Metrics.blockGap) {
            sourceTile
            if !session.ffmpegAvailable {
                WarningStrip(text: "ffmpeg 未安装 · 转码与降帧用不了，其余壁纸功能不受影响。") {
                    Button("安装途径…") { showingPathways = true }
                        .buttonStyle(GlowSmallButton())
                        .accessibilityIdentifier("transcode-pathways")
                }
            }

            Eyebrow(text: "处理队列", badge: queueBadge)
            queueBody

            // 0 尺寸锚点：`status-ffmpeg` 这个 identifier 被 UITest 依赖，删元素会让断言查无此物。
            Color.clear
                .frame(width: 0, height: 0)
                .accessibilityElement()
                .accessibilityLabel(Text("ffmpeg \(session.ffmpegAvailable ? "已就绪" : "未安装")"))
                .accessibilityIdentifier("status-ffmpeg")
        }
    }

    private var sourceTile: some View {
        SettingsTile(icon: "folder", title: "壁纸文件夹", tail: {
            HStack(spacing: 7) {
                Button("选择…") { requestFolder() }
                    .buttonStyle(GlowSmallButton())
                    .disabled(session.isScanning)
                    .accessibilityIdentifier("select-button")
                Button("重新扫描") { rescanLibrary() }
                    .buttonStyle(GlowSmallButton())
                    .disabled(session.isScanning)
                    .accessibilityIdentifier("rescan-button")
            }
        }) {
            VStack(alignment: .leading, spacing: Metrics.tileGap) {
                Text(store.sourceFolder.isEmpty ? "未设置" : store.sourceFolder)
                    .font(mono(11))
                    .foregroundStyle(Color.pInk2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(alignment: .top, spacing: 26) {
                    LibStat(value: "\(session.playableCount)", label: "可用视频",
                            alert: isEmpty, identifier: "count-value")
                    LibStat(value: "\(pendingCount)", label: "待处理")
                    LibStat(value: "\(transcodeCount)", label: "需转码")
                    LibStat(value: "\(fpsCount)", label: "需降帧")
                }
            }
        }
    }

    // ── 统一队列。全宽件（头/命令/尾）直接排，只有任务卡进 2 列网格 ──
    @ViewBuilder
    private var queueBody: some View {
        if rows.isEmpty {
            SettingsTile(icon: "checkmark.circle", title: "没有需要处理的文件") {
                Text("壁纸目录里的 MKV / AVI / WEBM 会自动出现在这里；高于 \(Int(FpsDownscaleCommand.maxFrameRate))fps 的文件会归到降帧。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.pInk3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            queueHeaderTile
            TileGrid {
                ForEach(filteredRows) { row in
                    queueJobTile(row)
                }
            }
            if let command = previewCommand {
                commandTile(command)
            }
            queueFooterTile
        }
    }

    private var queueHeaderTile: some View {
        SettingsTile(title: "队列") {
            HStack(spacing: 10) {
                QueueFilterBar(index: $queueFilter, counts: (transcodeCount, fpsCount, rows.count))
                Spacer(minLength: 0)
                Text(queueProgressText)
                    .font(.system(size: 11.5))
                    .foregroundStyle(queueHasFailure ? Color.pBad : Color.pInk3)
            }
            .accessibilityIdentifier("transcode-badge")
        }
    }

    private func queueJobTile(_ row: QueueRow) -> some View {
        Button {
            selectedJobID = row.id
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                Text(row.kind == .transcode ? "转码" : "降帧")
                    .font(mono(9.5, .semibold))
                    .foregroundStyle(row.kind == .transcode ? Color.pBrand : Color.pInk2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: Metrics.ctlRadius - 4, style: .continuous)
                            .fill(row.kind == .transcode ? Color.pBrandSoft : Color.pSurface2)
                    )
                Text(row.fileName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.pInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(row.meta)
                    .font(mono(10.5))
                    .foregroundStyle(Color.pInk3)
                    .lineLimit(1)
                HStack(spacing: 10) {
                    ProgressBar(percent: row.percent, failed: row.state.isFailure)
                    Text(row.state.label)
                        .font(mono(10.5))
                        .foregroundStyle(row.state.isFailure ? Color.pBad : Color.pInk3)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .tileSurface()
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.tileRadius, style: .continuous)
                    .strokeBorder(Color.pBrand, lineWidth: selectedJobID == row.id ? 2 : 0)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement()
        .accessibilityLabel(Text("\(row.fileName)，\(row.meta)，\(row.state.label)"))
        .accessibilityIdentifier("\(row.kind == .transcode ? "transcode" : "fps")-job-\(row.id)")
    }

    private func commandTile(_ command: String) -> some View {
        SettingsTile(title: "将要执行的命令") {
            Text(command)
                .font(mono(10.5))
                .foregroundStyle(Color.pInk)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: Metrics.ctlRadius, style: .continuous)
                        .fill(Color.pSurface2)
                )
                .accessibilityIdentifier("transcode-command")
        }
    }

    private var queueFooterTile: some View {
        SettingsTile(title: "操作") {
            HStack(spacing: 9) {
                if anyPaused {
                    Button("继续") { resumeQueues() }
                        .buttonStyle(GlowButton(primary: true))
                        .accessibilityIdentifier("transcode-resume")
                } else {
                    Button("开始处理") { startQueues() }
                        .buttonStyle(GlowButton(primary: true))
                        .disabled(!canStartQueues)
                        .accessibilityIdentifier("transcode-start")
                }
                Button("暂停") { pauseQueues() }
                    .buttonStyle(GlowButton())
                    .disabled(!canPauseQueues)
                    .accessibilityIdentifier("transcode-pause")
                Button("取消") { cancelQueues() }
                    .buttonStyle(GlowButton())
                    .disabled(!canCancelQueues)
                    .accessibilityIdentifier("transcode-cancel")
                Spacer(minLength: 0)
                if anyRunning {
                    Text(anyPaused ? "已暂停" : "处理中…")
                        .font(mono(11))
                        .foregroundStyle(Color.pBrand)
                }
                Button("选择目录或文件…") { Task { await transcodeViewModel.loadPickedSources() } }
                    .buttonStyle(GlowSmallButton())
                    .accessibilityIdentifier("transcode-pick")
                Button("重新查找") { rescanQueues() }
                    .buttonStyle(GlowSmallButton())
                    .accessibilityIdentifier("transcode-rescan")
            }
        }
    }

    // ── 通用 ──
    private var generalTab: some View {
        VStack(spacing: Metrics.blockGap) {
            Eyebrow(text: "启动")
            SettingsTile(title: "开机自启") {
                TileRow(title: "登录后在菜单栏待命，不弹窗口", divider: false) {
                    Toggle("", isOn: launchAtLogin).toggleStyle(GlowToggle()).labelsHidden()
                        .accessibilityIdentifier("autostart-toggle")
                }
            }

            Eyebrow(text: "关于")
            SettingsTile(title: "关于 Pic") {
                HStack(spacing: 17) {
                    AboutIcon()
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Pic")
                            .font(display(17))
                            .foregroundStyle(Color.pInk)
                        Text("版本 \(appVersion) · arm64 · GPL v2")
                            .font(mono(11))
                            .foregroundStyle(Color.pInk3)
                            .padding(.top, 4)
                        Text("用视频当动态壁纸。菜单栏常驻，全屏 / 锁屏 / 熄屏 / 睡眠时自动让路。")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.pInk2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 8)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// 版本号取自 bundle，不硬编码。
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    // ── 派生量 ──
    private var isEmpty: Bool {
        session.lastLibraryState.map(SettingsPresentation.isEmptyState) ?? false
    }

    private var emptyCopy: SettingsPresentation.EmptyStateCopy? {
        session.lastLibraryState.flatMap(SettingsPresentation.emptyStateCopy)
    }

    /// 两个队列只在**视图层**合并，底层仍是两个 ViewModel（9 处语义差异，见 SwiftUI-HANDOFF 第 7 节）。
    private var rows: [QueueRow] {
        QueueRow.rows(transcode: transcodeViewModel.jobs,
                      fps: fpsViewModel.jobs,
                      sizeText: { $0.fileSizeText })
    }

    private var filteredRows: [QueueRow] {
        switch queueFilter {
        case .all: rows
        case .transcode: rows.filter { $0.kind == .transcode }
        case .fps: rows.filter { $0.kind == .fps }
        }
    }

    private var transcodeCount: Int { transcodeViewModel.jobs.count }
    private var fpsCount: Int { fpsViewModel.jobs.count }
    private var pendingCount: Int {
        transcodeViewModel.jobs.filter { $0.state == .pending }.count
            + fpsViewModel.jobs.filter { $0.state == .pending }.count
    }

    private var anyRunning: Bool { transcodeViewModel.isRunning || fpsViewModel.isRunning }
    private var anyPaused: Bool { transcodeViewModel.isPaused || fpsViewModel.isPaused }
    private var canPauseQueues: Bool { transcodeViewModel.canPause || fpsViewModel.canPause }
    private var canCancelQueues: Bool { transcodeViewModel.canCancel || fpsViewModel.canCancel }
    private var canStartQueues: Bool {
        // ffmpeg 不具备时不能起：按钮留着可点会让人以为点了没反应。
        guard session.ffmpegAvailable, !anyRunning else { return false }
        return pendingCount > 0
    }

    private var queueHasFailure: Bool { rows.contains { $0.state.isFailure } }

    private var queueBadge: String? { rows.isEmpty ? nil : "\(rows.count) 个任务" }

    private var queueProgressText: String {
        if !session.ffmpegAvailable { return "等待 ffmpeg" }
        if anyRunning { return anyPaused ? "已暂停" : "处理中" }
        if queueHasFailure { return "有失败项" }
        return "全部待处理"
    }

    /// 正在跑的转码任务优先，否则看选中项。**降帧任务没有命令串** —— 只有转码有。
    private var previewCommand: String? {
        if let running = transcodeViewModel.jobs.first(where: { $0.state == .running }) {
            return running.commandDisplay
        }
        guard let selectedJobID else { return nil }
        return transcodeViewModel.jobs.first { $0.sourceURL.path == selectedJobID }?.commandDisplay
    }

    // ── 队列动作。一个按钮要覆盖两条队列：哪个有 pending 就起哪个 ──
    private func startQueues() {
        if transcodeViewModel.jobs.contains(where: { $0.state == .pending }) {
            transcodeViewModel.startTranscoding()
        }
        if fpsViewModel.jobs.contains(where: { $0.state == .pending }) {
            fpsViewModel.start()
        }
    }

    private func pauseQueues() {
        if transcodeViewModel.canPause { transcodeViewModel.pause() }
        if fpsViewModel.canPause { fpsViewModel.pause() }
    }

    private func cancelQueues() {
        if transcodeViewModel.canCancel { transcodeViewModel.cancel() }
        if fpsViewModel.canCancel { fpsViewModel.cancel() }
    }

    private func resumeQueues() {
        if transcodeViewModel.isPaused { transcodeViewModel.resume() }
        if fpsViewModel.isPaused { fpsViewModel.resume() }
    }

    private func rescanQueues() {
        transcodeViewModel.loadCandidates()
        fpsViewModel.scan()
    }

    // ── 绑定 ──
    private var modeIndex: Binding<Int> {
        Binding(
            get: { PlayMode.allCases.firstIndex(of: store.playMode) ?? 0 },
            set: { i in
                store.playMode = PlayMode.allCases[i]
                applier.applyMode()
                store.persist()
            })
    }

    private var rotationIndex: Binding<Int> {
        Binding(
            get: { SettingsPresentation.rotationChoicesMinutes
                .firstIndex(of: SettingsPresentation.rotationMinutes(seconds: store.rotationInterval)) ?? 0 },
            set: { i in
                store.rotationInterval = SettingsPresentation.rotationSeconds(
                    minutes: SettingsPresentation.rotationChoicesMinutes[i])
                applier.applyInterval()
                store.persist()
            })
    }

    private var volumePercent: Binding<Double> {
        Binding(
            get: { Double(SettingsPresentation.volumePercent(store.volume)) },
            set: { store.volume = SettingsPresentation.volumeFromPercent(Int($0.rounded())) })
    }

    /// 「声音」开关（勾 = 有声）。store 键仍是 isMuted，视图这一侧做一次取反，别处不许再取反。
    private var soundOn: Binding<Bool> {
        Binding(
            get: { !store.isMuted },
            set: {
                store.isMuted = !$0
                applier.applyMuted()
                store.persist()
            })
    }

    /// 「电池时播放」开关（勾 = 使用电池也播放）。store 键仍是 pauseOnBattery
    /// （true = 电池时暂停），视图侧取反一次，别处不许再取反。
    private var playOnBattery: Binding<Bool> {
        Binding(
            get: { !store.pauseOnBattery },
            set: {
                store.pauseOnBattery = !$0
                store.persist()
                // 当场重估：用最近一次已知电源状态重算，不等下一次电源跃迁。
                reapplyBatteryHold()
            })
    }

    /// 开机自启。与 `pauseOnBattery` 同款三行：写 store → persist → 落行为，决策在装配层。
    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { store.launchAtLogin },
            set: {
                store.launchAtLogin = $0
                store.persist()
                setLaunchAtLogin($0)
            })
    }

    private func seedAndObserve() {
        // 菜单面板指定了落地页（打开设置 / 去片库转码）时先消费掉，再铺默认状态。
        if let requested = session.requestedTab {
            tab = requested
            session.requestedTab = nil
        }
        rateDrag = Double(store.rate)
        // 开窗即重查 ffmpeg：用户中途装上的不必重启，回填 session 卡片当场刷新。
        refreshFFmpeg()
        transcodeViewModel.refresh()
        fpsViewModel.refresh()
        transcodeViewModel.loadCandidates()
    }
}

// ── 页内小件 ──

/// 统一队列的筛选维度。**声明顺序就是 chips 顺序**，别重排。
enum QueueFilter: Int {
    case all, transcode, fps
}

/// 只读的规则标签。
private struct TagChip: View {
    let text: String
    var accent = false

    var body: some View {
        Text(text)
            .font(mono(9.5))
            .foregroundStyle(accent ? Color.pBrand : Color.pInk2)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Capsule().fill(accent ? Color.pBrandSoft : Color.pSurface2))
    }
}

/// 统计读数。`alert` 为真时数字换成让路色 —— 空态下「0 个可用视频」要跳出来。
private struct LibStat: View {
    let value: String
    let label: String
    var alert = false
    var identifier: String? = nil

    var body: some View {
        if let identifier {
            core.accessibilityElement().accessibilityIdentifier(identifier)
        } else {
            core
        }
    }

    private var core: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(mono(21, .semibold))
                .monospacedDigit()
                .foregroundStyle(alert ? Color.pHold : Color.pInk)
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(Color.pInk3)
        }
    }
}

/// 队列筛选条。
private struct QueueFilterBar: View {
    @Binding var index: QueueFilter
    let counts: (transcode: Int, fps: Int, all: Int)

    private var items: [(String, QueueFilter)] {
        [("全部 \(counts.all)", .all),
         ("转码 \(counts.transcode)", .transcode),
         ("降帧 \(counts.fps)", .fps)]
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(items, id: \.0) { label, value in
                let on = index == value
                Button { index = value } label: {
                    Text(label)
                        .font(.system(size: 11.5, weight: on ? .semibold : .regular))
                        .foregroundStyle(on ? Color.pInk : Color.pInk2)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: Metrics.ctlRadius - 3, style: .continuous)
                                .fill(on ? Color.pSurface : .clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement()
            }
        }
        .padding(Metrics.segPadding)
        .background(
            RoundedRectangle(cornerRadius: Metrics.ctlRadius, style: .continuous)
                .fill(Color.pSurface2)
        )
    }
}

/// 进度条。`percent` 为 nil 时只画空轨道 —— 画一条固定细条会被读成「已经开始了」。
private struct ProgressBar: View {
    let percent: Double?
    var failed = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.pSurface3)
                if let percent {
                    Capsule()
                        .fill(failed ? Color.pBad : Color.pOk)
                        .frame(width: geo.size.width * max(0, min(1, percent)))
                }
            }
        }
        .frame(height: 5)
        .frame(maxWidth: 108)
    }
}
