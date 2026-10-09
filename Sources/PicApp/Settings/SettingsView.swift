import SwiftUI
import AppKit
import PicCore

/// 设置窗主体：顶栏（状态胶囊 + 来源切换）+ 216pt 侧栏导航 + 两列卡片网格。
/// 视觉与骨架照抄 `.planning/design/ui-redesign-v2-shell.html`。
/// 六个可调项全部真绑定：`store.<键> = …` → `SettingsApplier.apply*()` → `store.persist()`，
/// 窗内不出现渲染假数据的 @State。
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
    /// 内容高度变了（切页）请窗口重新贴合 —— 由 AppDelegate 在布局周期外异步读 fittingSize。
    let requestWindowFit: () -> Void
    /// 带默认值的可选闭包：AppDelegate 未接线时为 nil，UI 照常编译、动作只是不落行为。
    var switchSource: ((WallpaperKind) -> Void)? = nil
    var applyImageFit: (() -> Void)? = nil
    var applyImageFilter: (() -> Void)? = nil

    /// ffmpeg 不可用时的安装途径弹层（置灰之外还得给出途径）。
    @State private var showingPathways = false

    // 速度滑杆的拖动暂态，每次 onChanged 直通 store + applier。
    @State private var rateDrag: Double = 1.0
    // 当前页：侧栏四区导航（播放 / 片库 / 队列 / 通用）。
    @State private var page: SettingsPresentation.SettingsPage = .play
    @State private var queueFilter: QueueFilter = .all
    @State private var selectedJobID: String?

    var body: some View {
        VStack(spacing: 0) {
            SettingsTopBar(kind: store.wallpaperKind, switchSource: { switchSource?($0) }) {
                statusPill
            }
            HStack(spacing: 0) {
                SettingsSideBar(kind: store.wallpaperKind, page: $page,
                                queueCount: rows.count,
                                statusTint: statusTint, statusText: sidebarStatusText)
                // 唯一允许滚动的是队列页（任务数天然不定），其余页一屏看全。
                ScrollView {
                    contentColumn
                        .padding(Metrics.contentPadding)
                }
            }
        }
        .frame(minWidth: SettingsPresentation.windowMinWidth,
               idealWidth: SettingsPresentation.windowWidth,
               maxWidth: .infinity, maxHeight: .infinity,
               alignment: .topLeading)
        .background {
            // 液态玻璃开启时根背景是超薄材质（配合窗体透明透出桌面模糊）；
            // 关闭时是不透明 pGround，与原状逐像素相同。
            Rectangle().fill(store.liquidGlassEnabled
                ? AnyShapeStyle(.ultraThinMaterial)
                : AnyShapeStyle(Color.pGround))
                .ignoresSafeArea()
        }
        // 卡片面是否走液态玻璃只在根视图读一次 store，卡片调用点经环境量继承。
        .environment(\.cardSurfaceGlass, store.liquidGlassEnabled)
        .preferredColorScheme(.light)
        .onAppear(perform: seedAndObserve)
        // 窗已开时面板再发落地页请求（典型：设置开着，菜单里点「去片库转码」）。
        // 菜单传的还是老三页签索引，只能查表映射。
        .onChange(of: session.requestedTab) { _, requested in
            guard let requested else { return }
            page = SettingsPresentation.page(fromLegacyTab: requested)
            session.requestedTab = nil
        }
        .onChange(of: page) { _, _ in requestWindowFit() }
        // 图片来源没有队列语义：切到图片时若正停在队列页，必须回落片库 ——
        // 否则用户停在侧栏里已经消失的一项上。
        .onChange(of: store.wallpaperKind) { _, kind in
            if kind == .image && page == .queue { page = .library }
        }
        .sheet(isPresented: $showingPathways) {
            InstallPathwaysView(onRecheck: { refreshFFmpeg() })
        }
    }

    // ── 内容区 ──
    private var contentColumn: some View {
        VStack(alignment: .leading, spacing: Metrics.gridGap) {
            SettingsPageHead(page: page)
            switch page {
            case .play: playPage
            case .library: libraryPage
            case .queue: queuePage
            case .general: generalPage
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // ── 状态（顶栏胶囊与侧栏页脚同一套判定，文案只在这里派生一份） ──
    private var isHeld: Bool { !arbiter.decision.activeReasons.isEmpty }

    private var statusTint: Color {
        if isEmpty { return .pBad }
        return isHeld ? .pHold : .pOk
    }

    private var statusKind: StatusPill.Kind {
        isEmpty ? .blocked : isHeld ? .hold : .playing
    }

    private var statusLead: String {
        isEmpty || isHeld ? "已暂停" : "播放中"
    }

    private var statusRest: String {
        if isEmpty { return "· 没有可播文件" }
        if isHeld { return "· \(SettingsPresentation.joinedReasons(arbiter.decision.activeReasons))" }
        return "· \(SettingsPresentation.playModeLabel(store.playMode, kind: store.wallpaperKind))"
    }

    private var statusPill: some View {
        StatusPill(kind: statusKind, lead: statusLead, rest: statusRest)
    }

    private var sidebarStatusText: String {
        "\(statusLead) \(statusRest)"
    }

    // ── 播放页 ──
    // 图片模式掉的是速度/音频整块，不是置灰；下方空着不补占位卡。
    private var playPage: some View {
        VStack(spacing: Metrics.gridGap) {
            heroCard
            if !isEmpty {
                TileGrid {
                    modeCard
                    rotationCard
                }
                if store.wallpaperKind == .video {
                    TileGrid {
                        speedCard
                        volumeCard
                    }
                }
            }
            rulesCard
        }
    }

    @ViewBuilder
    private var heroCard: some View {
        if isEmpty {
            emptyCard
        } else {
            nowCard
        }
    }

    // ── 正在播放 / 让路（hero 卡，通栏） ──
    private var nowCard: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 9) {
                    Circle()
                        .fill(heroTint)
                        .frame(width: 8, height: 8)
                        .background(
                            Circle().fill(heroTint.opacity(0.22)).frame(width: 15, height: 15)
                        )
                    Text(heroHeadline)
                        .font(display(15))
                        .foregroundStyle(Color.pInk)
                }
                Text(heroSummary)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.pInk2)
                    .fixedSize(horizontal: false, vertical: true)
                heroTags
            }
            Spacer(minLength: 0)
            if !isHeld && store.playMode == .loopSingle {
                staticRing
            } else {
                rotationRing
            }
        }
        .cardSurface()
    }

    private var heroTint: Color { isHeld ? .pHold : .pOk }

    /// 倒计时环的颜色与状态点解耦：播放中走品牌橙，让路仍用 hold 褐。
    private var heroRingTint: Color { isHeld ? Color.pHold : Color.pBrand }

    private var heroHeadline: String {
        if isHeld {
            return "已暂停 · \(SettingsPresentation.joinedReasons(arbiter.decision.activeReasons))"
        }
        return SettingsPresentation.heroHeadline(kind: store.wallpaperKind, mode: store.playMode)
    }

    private var heroSummary: String {
        if isHeld {
            return SettingsPresentation.heroHoldSummary
        }
        let every = SettingsPresentation.rotationLabel(
            minutes: SettingsPresentation.rotationMinutes(seconds: store.rotationInterval))
        let count = SettingsPresentation.libraryCount(kind: store.wallpaperKind,
                                                      videoCount: session.playableCount,
                                                      imageCount: session.imagePassing)
        return SettingsPresentation.heroSummary(kind: store.wallpaperKind, mode: store.playMode,
                                                count: count, every: every)
    }

    private var heroTags: some View {
        // 只在让路时显示原因标签；播放中不放数值行。
        HStack(spacing: 7) {
            if isHeld {
                ForEach(arbiter.decision.activeReasons.sorted(), id: \.self) { reason in
                    TagChip(text: SettingsPresentation.holdReasonLabel(reason))
                }
            }
        }
    }

    /// 倒计时环。TimelineView 每秒重算，不存 @State —— 读数是轮换器的纯派生量，
    /// 存一份就会在 setInterval / advance 之后与真值对不上。
    private var rotationRing: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let remaining = rotation.secondsUntilNextRotation()
            ZStack {
                Circle().stroke(Color.pSurface3, lineWidth: 6)
                Circle()
                    .trim(from: 0, to: ringFraction(remaining))
                    .stroke(heroRingTint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 1) {
                    Text(remaining.map { mmss($0) } ?? "—")
                        .font(mono(12, .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.pInk)
                    Text(remaining == nil ? "不轮换" : "换下一个")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.pInk3)
                }
            }
            .frame(width: 78, height: 78)
            .accessibilityElement()
            .accessibilityLabel(Text(remaining.map { "距下次换片还有 \(mmss($0))" } ?? "当前不轮换"))
        }
    }

    /// 「单张不变 / 单循环」没有倒计时：环底只剩轨道，中心给 — / 不轮换。
    private var staticRing: some View {
        ZStack {
            Circle().stroke(Color.pSurface3, lineWidth: 6)
            VStack(spacing: 1) {
                Text("—")
                    .font(mono(12, .semibold))
                    .foregroundStyle(Color.pInk)
                Text("不轮换")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.pInk3)
            }
        }
        .frame(width: 78, height: 78)
        .accessibilityElement()
        .accessibilityLabel(Text("当前不轮换"))
    }

    private func ringFraction(_ remaining: TimeInterval?) -> Double {
        guard let remaining, rotation.interval > 0 else { return 0 }
        return max(0, min(1, remaining / rotation.interval))
    }

    private func mmss(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // ── 空态（三变体完整区分，共用同一张通栏卡） ──
    private var emptyCard: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: emptyMark)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.pHold)
                .frame(width: 38, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: Metrics.ctlRadius, style: .continuous)
                        .fill(Color.pHoldSoft)
                )
            VStack(alignment: .leading, spacing: 0) {
                Text(emptyCopy?.title ?? "没有可播文件")
                    .font(display(15))
                    .foregroundStyle(Color.pInk)
                    .padding(.bottom, 7)
                // 逐字硬需求，三种变体共用同一句。
                Text(SettingsPresentation.emptyStateBody)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.pInk2)
                    .fixedSize(horizontal: false, vertical: true)
                if let reason = emptyCopy?.reason {
                    Text(reason)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.pInk3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                }
                if let folder = missingFolderPath {
                    Text(folder)
                        .font(mono(11))
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
        .cardSurface()
    }

    /// 三种空态各配一个有图形语义的 SF Symbol。
    private var emptyMark: String {
        switch session.lastLibraryState {
        case .folderUnconfigured: "folder.badge.questionmark"
        case .folderMissing: "exclamationmark.triangle"
        default: "film"
        }
    }

    /// 目录没了才显示上次的路径：让用户知道是「哪个位置」没了。
    private var missingFolderPath: String? {
        session.lastLibraryState == .folderMissing && !store.sourceFolder.isEmpty
            ? store.sourceFolder : nil
    }

    private func emptyPrimaryAction() {
        // 「扫到 0」的下一步是去片库（调档位 / 转码），不是再选一次文件夹 —— 选了也还是 0。
        if session.lastLibraryState == .noPlayableVideos {
            page = .library
        } else {
            requestFolder()
        }
    }

    // ── 播放模式 / 轮播方式 ──
    private var modeCard: some View {
        SettingsCard(title: store.wallpaperKind == .image ? "轮播方式" : "播放模式") {
            GlowSegmented(
                items: PlayMode.allCases.map {
                    SettingsPresentation.playModeLabel($0, kind: store.wallpaperKind)
                },
                index: modeIndex)
                .accessibilityIdentifier("mode-segmented")
        }
    }

    // ── 轮换间隔 ──
    private var rotationEnabled: Bool {
        SettingsPresentation.rotationControlsEnabled(playMode: store.playMode)
    }

    private var rotationCard: some View {
        SettingsCard(title: "轮换间隔") {
            VStack(alignment: .leading, spacing: 11) {
                TickSelector(items: SettingsPresentation.rotationChoicesMinutes
                                .map(SettingsPresentation.rotationLabel(minutes:)),
                             index: rotationIndex)
                    .accessibilityIdentifier("rotation-stepper")
                    .disabled(!rotationEnabled)
                    .opacity(rotationEnabled ? 1 : 0.42)
                if !rotationEnabled {
                    Text(SettingsPresentation.rotationDisabledNote(kind: store.wallpaperKind))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.pInk3)
                }
            }
        }
    }

    // ── 播放速度 / 音频（仅视频来源） ──
    private var speedCard: some View {
        SettingsCard(title: "播放速度", tail: {
            Text("音高不变").font(.system(size: 11)).foregroundStyle(Color.pInk3)
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

    private var volumeCard: some View {
        SettingsCard(title: "音频") {
            // 与「播放速度」同构：滑杆满宽 + 右侧读数 + 开关，单行等高。
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
                .disabled(!volumeEnabled)
                .opacity(volumeEnabled ? 1 : 0.34)
                .accessibilityIdentifier("volume-slider")
                Text("\(SettingsPresentation.volumePercent(store.volume))%")
                    .font(mono(12))
                    .monospacedDigit()
                    .foregroundStyle(Color.pInk)
                    .frame(width: Metrics.valueWidth, alignment: .trailing)
                    .opacity(volumeEnabled ? 1 : 0.34)
                    .accessibilityIdentifier("volume-value")
                Toggle("", isOn: soundOn).toggleStyle(GlowToggle()).labelsHidden()
                    .accessibilityIdentifier("sound-toggle")
            }
            .animation(.easeOut(duration: 0.15), value: store.isMuted)
        }
    }

    /// 静音时音量滑杆与读数置灰。volumeCard 内三处共用这一份判定。
    private var volumeEnabled: Bool {
        SettingsPresentation.volumeControlsEnabled(isMuted: store.isMuted)
    }

    // ── 让路规则：四条不可关 + 一条可关 ──
    private var rulesCard: some View {
        SettingsCard(icon: "hand.raised", title: "这些情况会让路", tail: {
            Text("前四项不可关闭").font(.system(size: 11)).foregroundStyle(Color.pInk3)
        }) {
            VStack(alignment: .leading, spacing: Metrics.tileGap) {
                HStack(spacing: 7) {
                    ForEach(Self.fixedHoldReasons, id: \.self) { reason in
                        TagChip(text: SettingsPresentation.holdReasonLabel(reason))
                    }
                }
                // 「电池供电」行：不用 TileRow（它的文本在 34pt 行内垂直居中，与顶部分隔线的
                // 距离是固定的）—— 这里展开手写，给文本单独的上边距。
                HStack(spacing: Metrics.rowGap) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("电池供电")
                            .font(display(13, .medium))
                            .foregroundStyle(Color.pInk)
                        Text("关掉它，用电池时也继续放（更费电）")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.pInk3)
                    }
                    Spacer(minLength: 0)
                    Toggle("", isOn: playOnBattery).toggleStyle(GlowToggle()).labelsHidden()
                        .accessibilityIdentifier("battery-toggle")
                }
                .padding(.top, 10)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.pDivider)
                        .frame(height: 1)
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

    // ── 片库页 ──
    private var libraryPage: some View {
        VStack(spacing: Metrics.gridGap) {
            folderCard
            if store.wallpaperKind == .image {
                TileGrid {
                    tierCard
                    fitCard
                }
            } else {
                if !session.ffmpegAvailable {
                    WarningStrip(text: "ffmpeg 未安装 · 转码与降帧用不了，其余壁纸功能不受影响。") {
                        Button("安装途径…") { showingPathways = true }
                            .buttonStyle(GlowSmallButton())
                            .accessibilityIdentifier("transcode-pathways")
                    }
                }
                queueShortcutCard
            }
            // 0 尺寸锚点：`status-ffmpeg` 这个 identifier 被 UITest 依赖，删元素会让断言查无此物。
            Color.clear
                .frame(width: 0, height: 0)
                .accessibilityElement()
                .accessibilityLabel(Text("ffmpeg \(session.ffmpegAvailable ? "已就绪" : "未安装")"))
                .accessibilityIdentifier("status-ffmpeg")
        }
    }

    // ── 壁纸文件夹（通栏） ──
    private var folderCard: some View {
        SettingsCard(icon: "folder", title: "壁纸文件夹", tail: {
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
                pathRow
                if session.isScanning {
                    scanningRow
                } else {
                    // 统计带与路径行之间有一条发丝线（HTML .strip：margin 14 + border + padding 14）。
                    statStrip
                        .padding(.top, 14)
                        .overlay(alignment: .top) {
                            Rectangle()
                                .fill(Color.pDivider)
                                .frame(height: 1)
                        }
                }
            }
        }
    }

    // ── 路径行 ──
    /// 一行完整路径，mono 12，不拆段不加粗 —— 路径就是路径。
    /// 缺失态行尾追加琥珀「· 目录不见了」，未设置给引导文案。
    private var pathRow: some View {
        pathText
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.vertical, 2)
    }

    private var isFolderMissing: Bool { session.lastLibraryState == .folderMissing }

    private var resolvedFolder: String {
        store.wallpaperKind == .image ? store.imageFolderPath : store.sourceFolder
    }

    private var pathText: Text {
        if resolvedFolder.isEmpty {
            return Text(store.wallpaperKind == .image
                        ? "未设置 —— 选一个装图片的文件夹"
                        : "未设置 —— 选一个装视频的文件夹")
                .font(.system(size: 12))
                .foregroundStyle(Color.pInk3)
        }
        let folder = Text(resolvedFolder).font(mono(12)).foregroundStyle(Color.pInk2)
        guard isFolderMissing else { return folder }
        // 必须走 Text 插值，不能用 `folder + Text(...)`：Text 的 `+` 在 macOS 26 已废弃。
        // 返回单个 Text 而非 HStack —— pathRow 的 lineLimit(1) + 中段截断要作用在整行上。
        return Text("\(folder)\(Text("  · 目录不见了").font(.system(size: 12)).foregroundStyle(Color.pHold))")
    }

    // ── 统计带 ──
    /// 格子与格数由 `libraryStatCells` 分派（图片三格 / 视频四格），本侧只管渲染与标识。
    /// 颜色按「语义」说话：emphasis 是「有事要说」→ 品牌深琥珀；否则安静灰。
    private var statStrip: some View {
        let kind = store.wallpaperKind
        let cells = SettingsPresentation.libraryStatCells(
            kind: kind,
            image: SettingsPresentation.ImageStat(total: session.imageTotal,
                                                  passing: session.imagePassing,
                                                  filtered: session.imageFiltered),
            video: SettingsPresentation.VideoStat(playable: session.playableCount,
                                                  pending: pendingCount,
                                                  transcode: transcodeCount,
                                                  fps: fpsCount))
        let ids: [String] = kind == .image
            ? ["image-stat-total", "image-stat-passing", "image-stat-filtered"]
            : ["video-stat-playable", "video-stat-pending", "video-stat-transcode", "video-stat-fps"]
        return HStack(spacing: 0) {
            ForEach(cells.indices, id: \.self) { i in
                if i > 0 { stripDivider }
                statCell(cells[i], identifier: ids[i],
                         legacy: kind == .video && i == 0 ? "count-value" : nil)
            }
        }
    }

    private var stripDivider: some View {
        Rectangle()
            .fill(Color.pDivider)
            .frame(width: 1, height: 30)
    }

    private func statCell(_ cell: SettingsPresentation.StatCell, identifier: String,
                          legacy: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(cell.value)
                .font(mono(21, .semibold))
                .monospacedDigit()
                .foregroundStyle(cell.emphasis ? Color.pBrandText : Color.pInk2)
                .modifier(LegacyStatID(id: legacy))
            Text(cell.label)
                .font(.system(size: 11))
                .foregroundStyle(Color.pInk3)
        }
        // contain：格容器与内部数字/标签是父子两个 AX 元素 —— 旧 count-value 挂在数字上，
        // 与容器的 identifier 互不顶掉。
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
        .frame(maxWidth: .infinity)
    }

    /// 扫描中的就地反馈：转圈 + 文案，代替原来「按钮变灰但不知道在干嘛」。
    private var scanningRow: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("正在扫描…")
                .font(.system(size: 11))
                .foregroundStyle(Color.pInk3)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
    }

    // ── 图片来源专属：分辨率筛选 / 图片适配 ──
    private var tierCard: some View {
        SettingsCard(title: "分辨率筛选") {
            VStack(alignment: .leading, spacing: 11) {
                SlideSegmented(items: SettingsPresentation.resolutionTierLabels(), index: tierIndex)
                    .accessibilityIdentifier("tier-segmented")
                Text(SettingsPresentation.resolutionNote(pixels: store.imageMinPixels))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.pInk3)
            }
        }
    }

    private var fitCard: some View {
        SettingsCard(title: "图片适配") {
            VStack(alignment: .leading, spacing: 11) {
                GlowSegmented(items: SettingsPresentation.imageFitLabels(), index: fitIndex)
                    .accessibilityIdentifier("fit-segmented")
                Text(SettingsPresentation.imageFitCaption(store.imageFit))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.pInk3)
            }
        }
    }

    // ── 视频来源专属：处理队列入口（通栏） ──
    private var queueShortcutCard: some View {
        SettingsCard(icon: "list.bullet.rectangle", title: "处理队列") {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("\(rows.count) 个任务 · \(queueProgressText)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.pInk)
                    ProgressBar(percent: queueOverallProgress)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button("打开队列") { page = .queue }
                    .buttonStyle(GlowButton())
                    .accessibilityIdentifier("queue-shortcut")
            }
        }
    }

    // ── 队列页。全宽件（头/命令/尾）直接排，只有任务卡进 2 列网格 ──
    @ViewBuilder
    private var queuePage: some View {
        if rows.isEmpty {
            SettingsCard(icon: "checkmark.circle", title: "没有需要处理的文件") {
                Text("壁纸目录里的 MKV / AVI / WEBM 会自动出现在这里；高于 \(Int(FpsDownscaleCommand.maxFrameRate))fps 的文件会归到降帧。")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.pInk3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            queueHeaderCard
            TileGrid {
                ForEach(filteredRows) { row in
                    queueJobCard(row)
                }
            }
            if let command = previewCommand {
                commandCard(command)
            }
            queueFooterCard
        }
    }

    private var queueHeaderCard: some View {
        SettingsCard(title: "队列") {
            HStack(spacing: 10) {
                QueueFilterBar(index: $queueFilter, counts: (transcodeCount, fpsCount, rows.count))
                Spacer(minLength: 0)
                Text(queueProgressText)
                    .font(.system(size: 11))
                    .foregroundStyle(queueHasFailure ? Color.pBad : Color.pInk3)
            }
            .accessibilityIdentifier("transcode-badge")
        }
    }

    private func queueJobCard(_ row: QueueRow) -> some View {
        Button {
            selectedJobID = row.id
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                Text(row.kind == .transcode ? "转码" : "降帧")
                    .font(mono(10, .semibold))
                    // brand 作文字：用 brandText（亮橙作文字在白底不达标）。
                    .foregroundStyle(row.kind == .transcode ? Color.pBrandText : Color.pInk2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: Metrics.ctlRadius - 4, style: .continuous)
                            .fill(row.kind == .transcode ? Color.pBrandSoft : Color.pSurface2)
                    )
                Text(row.fileName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.pInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(row.meta)
                    .font(mono(11))
                    .foregroundStyle(Color.pInk3)
                    .lineLimit(1)
                HStack(spacing: 10) {
                    ProgressBar(percent: row.percent, failed: row.state.isFailure)
                    Text(row.state.label)
                        .font(mono(11))
                        .foregroundStyle(row.state.isFailure ? Color.pBad : Color.pInk3)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
            // 选中描边用队列区的身份色：v2 卡片选中态走 2px 区色描边。
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .strokeBorder(Color.pQueue, lineWidth: selectedJobID == row.id ? 2 : 0)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement()
        .accessibilityLabel(Text("\(row.fileName)，\(row.meta)，\(row.state.label)"))
        .accessibilityIdentifier("\(row.kind == .transcode ? "transcode" : "fps")-job-\(row.id)")
    }

    private func commandCard(_ command: String) -> some View {
        SettingsCard(title: "将要执行的命令") {
            Text(command)
                .font(mono(11))
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

    private var queueFooterCard: some View {
        SettingsCard(title: "操作") {
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
                        .foregroundStyle(Color.pBrandText)
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

    // ── 通用页 ──
    private var generalPage: some View {
        TileGrid {
            aboutCard
            autostartCard
            appearanceCard
        }
    }

    private var aboutCard: some View {
        SettingsCard(title: "关于") {
            HStack(spacing: 15) {
                AboutIcon()
                VStack(alignment: .leading, spacing: 0) {
                    Text("壁纸儿")
                        .font(display(15))
                        .foregroundStyle(Color.pInk)
                    Text("版本 \(appVersion()) · arm64 · GPL v2")
                        .font(mono(11))
                        .foregroundStyle(Color.pInk3)
                        .padding(.top, 4)
                    Text("用视频（或图片）当壁纸。菜单栏常驻，全屏 / 锁屏 / 熄屏 / 睡眠时自动让路。")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.pInk2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var autostartCard: some View {
        SettingsCard(title: "开机自启") {
            TileRow(title: "登录后在菜单栏待命",
                    sub: "不弹窗口；需要时从菜单栏打开设置。", divider: false) {
                Toggle("", isOn: launchAtLogin).toggleStyle(GlowToggle()).labelsHidden()
                    .accessibilityIdentifier("autostart-toggle")
            }
        }
    }

    private var appearanceCard: some View {
        SettingsCard(title: "外观") {
            TileRow(title: "液态玻璃效果",
                    sub: "窗口与卡片改用系统液态玻璃材质", divider: false) {
                Toggle("", isOn: liquidGlass).toggleStyle(GlowToggle()).labelsHidden()
                    .accessibilityIdentifier("glass-toggle")
            }
        }
    }

    // ── 派生量 ──
    private var isEmpty: Bool {
        session.lastLibraryState.map(SettingsPresentation.isEmptyState) ?? false
    }

    private var emptyCopy: SettingsPresentation.EmptyStateCopy? {
        session.lastLibraryState.flatMap { SettingsPresentation.emptyStateCopy($0, kind: store.wallpaperKind) }
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

    private var queueProgressText: String {
        if !session.ffmpegAvailable { return "等待 ffmpeg" }
        if anyRunning { return anyPaused ? "已暂停" : "处理中" }
        if queueHasFailure { return "有失败项" }
        return "全部待处理"
    }

    /// 队列入口卡的总进度：各任务百分比的均值（nil 视为 0），是个概览不是承诺。
    private var queueOverallProgress: Double? {
        guard !rows.isEmpty else { return nil }
        let total = rows.reduce(0.0) { $0 + ($1.percent ?? 0) }
        return total / Double(rows.count)
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

    private var tierIndex: Binding<Int> {
        Binding(
            get: { SettingsPresentation.resolutionTierIndex(pixels: store.imageMinPixels) },
            set: { i in
                store.imageMinPixels = SettingsPresentation.resolutionTierPixels(index: i)
                store.persist()
                // 档位变了要当场重筛：由 AppDelegate 接线触发重扫/重贴。
                applyImageFilter?()
            })
    }

    private var fitIndex: Binding<Int> {
        Binding(
            get: { SettingsPresentation.imageFitIndex(store.imageFit) },
            set: { i in
                store.imageFit = ImageFit.allCases[i]
                store.persist()
                // 适配方式直接改窗口内容的摆放，不必重扫。
                applyImageFit?()
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

    /// 液态玻璃。与 launchAtLogin 同款写 store → persist 两步——**没有第三步**：
    /// 纯展示偏好不走 Applier、不需要动窗口，@Observable 让 SwiftUI 即时重渲染。
    private var liquidGlass: Binding<Bool> {
        Binding(
            get: { store.liquidGlassEnabled },
            set: {
                store.liquidGlassEnabled = $0
                store.persist()
            })
    }

    private func seedAndObserve() {
        // 菜单面板指定了落地页（打开设置 / 去片库转码）时先消费掉，再铺默认状态。
        if let requested = session.requestedTab {
            page = SettingsPresentation.page(fromLegacyTab: requested)
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

    var body: some View {
        Text(text)
            .font(mono(10))
            .foregroundStyle(Color.pInk2)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.pSurface2))
    }
}

/// 队列筛选条。视觉语言统一为滑块分段（SlideSegmented），本结构只负责把
/// QueueFilter 枚举适配成 Int 下标、拼带计数的标签。
private struct QueueFilterBar: View {
    @Binding var index: QueueFilter
    let counts: (transcode: Int, fps: Int, all: Int)

    /// 全部 / 转码 / 降帧 的声明顺序就是 chips 顺序，别重排。
    private var items: [String] {
        ["全部 \(counts.all)", "转码 \(counts.transcode)", "降帧 \(counts.fps)"]
    }

    private var selectedIndex: Binding<Int> {
        Binding(
            get: { index.rawValue },
            set: { index = QueueFilter(rawValue: $0) ?? .all }
        )
    }

    var body: some View {
        SlideSegmented(items: items, index: selectedIndex)
            .frame(width: 300, height: 30)
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
    }
}

/// legacy identifier 只在给了值时挂：同一格要同时留旧 `count-value` 和新 `video-stat-playable`，
/// 旧标识挂在数字 Text 上（与格容器是父子两个 AX 元素，互不顶掉）。
private struct LegacyStatID: ViewModifier {
    let id: String?
    func body(content: Content) -> some View {
        if let id { content.accessibilityIdentifier(id) } else { content }
    }
}
