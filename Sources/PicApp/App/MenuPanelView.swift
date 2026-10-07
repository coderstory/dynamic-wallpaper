import SwiftUI
import AppKit
import PicCore

// 菜单栏自绘面板（原型 D），NSPopover 的内容。视觉与尺寸照抄
// `.planning/design/prototype.html` 的 .panel / .mhead / .mrow / .mdiv / .mfoot。
// 菜单项仍只由 `MenuItemID.allCases` 遍历产出、动作仍只走 `MenuBarModel.perform` ——
// 换成自绘面板不是绕过 MenuBarModelTests 哨兵的理由。
struct MenuPanelView: View {
    @Environment(HoldArbiter.self) private var arbiter
    @Environment(SettingsStore.self) private var store
    @Environment(SettingsSessionState.self) private var session

    /// 轮换内核，只读倒计时。
    private let rotation: RotationController
    /// 动作前关面板（AppDelegate 注入 `popover.close()`）。
    private let dismiss: () -> Void
    private let terminate: () -> Void
    /// 打开设置窗并落地到指定页（0 播放 / 1 片库 / 2 通用）。
    private let openSettings: (Int) -> Void
    private let nextVideo: () -> Void
    private let rescanFolder: () -> Void
    private let deleteCurrent: () -> Void
    private let requestFolder: () -> Void

    init(rotation: RotationController,
         dismiss: @escaping () -> Void,
         terminate: @escaping () -> Void,
         openSettings: @escaping (Int) -> Void,
         nextVideo: @escaping () -> Void,
         rescanFolder: @escaping () -> Void,
         deleteCurrent: @escaping () -> Void,
         requestFolder: @escaping () -> Void) {
        self.rotation = rotation
        self.dismiss = dismiss
        self.terminate = terminate
        self.openSettings = openSettings
        self.nextVideo = nextVideo
        self.rescanFolder = rescanFolder
        self.deleteCurrent = deleteCurrent
        self.requestFolder = requestFolder
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            header
            divider
            // 空态的主行动（.mrow.primary）：三种原因三个出口，文案的唯一来源是 emptyStateCopy。
            if let copy = emptyCopy {
                MenuRow(glyph: emptyPrimaryGlyph, label: copy.primaryAction, style: .primary) {
                    dismiss()
                    if session.lastLibraryState == .noPlayableVideos {
                        openSettings(1)
                    } else {
                        requestFolder()
                    }
                }
                .accessibilityIdentifier("menu-empty-primary")
            }
            ForEach(MenuItemID.allCases, id: \.self) { id in
                if isVisible(id) {
                    // 分组线位置照抄原型：维护 / 不可逆 / 系统各起一组。
                    if id == .rescanFolder || id == .deleteCurrent || id == .openSettings { divider }
                    MenuRow(glyph: glyph(for: id), label: MenuBarModel.label(for: id, isPaused: isPaused),
                            shortcut: shortcutHint(for: id), style: rowStyle(for: id)) {
                        activate(id)
                    }
                    .accessibilityIdentifier("menu-row-\(id.rawValue)")
                }
            }
            if showsFooter {
                Text("菜单里始终不显示文件名——片库里的文件名多为无语义串。")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.pInk3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 11)
                    .padding(.top, 5)
                    .padding(.bottom, 6)
            }
        }
        .padding(9)
        .frame(width: 300)
        .background(Color.pSurface)
    }

    // ── 头部：状态点 + 标题 + 副行 + 倒计时环（.mhead） ──
    private var header: some View {
        HStack(spacing: 11) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Circle().fill(headerTint).frame(width: 8, height: 8)
                    Text(isEmpty || isHeld ? "已暂停" : "正在播放")
                        .font(display(13, .semibold))
                        .foregroundStyle(Color.pInk)
                }
                Text(headerSubline)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.pInk3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            countdownRing
        }
        .padding(.top, 9)
        .padding(.bottom, 10)
        .padding(.horizontal, 10)
    }

    private var headerTint: Color { isEmpty ? .pBad : (isHeld ? .pHold : .pOk) }

    private var headerSubline: String {
        if let copy = emptyCopy {
            return "壁纸已隐藏 · \(copy.title)"
        }
        if isHeld {
            return "\(SettingsPresentation.joinedReasons(arbiter.decision.activeReasons)) · 条件解除后自动续播"
        }
        return "\(SettingsPresentation.playModeLabel(store.playMode)) · \(session.playableCount) 个视频"
    }

    /// 倒计时环。与设置窗 hero 环是同族两尺寸（46 vs 78），小而各自内联 —— 不为两处用例起抽象。
    /// 轮换器说「不轮换」（单循环 / 单条目 / 未运行）时整环消失，不画一条「—」占位。
    @ViewBuilder
    private var countdownRing: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            if let remaining = rotation.secondsUntilNextRotation() {
                ZStack {
                    Circle().stroke(Color.pSurface3, lineWidth: 3.6)
                    Circle()
                        .trim(from: 0, to: ringFraction(remaining))
                        .stroke(headerTint, style: StrokeStyle(lineWidth: 3.6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(mmss(remaining))
                        .font(mono(10.5))
                        .monospacedDigit()
                        .foregroundStyle(Color.pInk)
                }
                .frame(width: 46, height: 46)
                .accessibilityElement()
                .accessibilityLabel(Text("距下次换片还有 \(mmss(remaining))"))
            }
        }
    }

    private func ringFraction(_ remaining: TimeInterval) -> Double {
        guard rotation.interval > 0 else { return 0 }
        return max(0, min(1, remaining / rotation.interval))
    }

    private func mmss(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.pDivider)
            .frame(height: 1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
    }

    // ── 行规格 ──
    private var isPaused: Bool { arbiter.isManuallyPaused }
    private var isHeld: Bool { !arbiter.decision.activeReasons.isEmpty }
    private var isEmpty: Bool {
        session.lastLibraryState.map(SettingsPresentation.isEmptyState) ?? false
    }
    private var emptyCopy: SettingsPresentation.EmptyStateCopy? {
        session.lastLibraryState.flatMap(SettingsPresentation.emptyStateCopy)
    }
    /// 脚注只在「正在放」时写：那时用户最可能想找文件名。
    private var showsFooter: Bool { !isEmpty && !isHeld }

    /// 可见性照抄原型的 data-when：暂停/下一个只在有播放会话时出现。
    /// 刻意的偏离：删除项在空态也隐藏 —— 原型没给它写 data-when（全态可见），
    /// 但空态没有「当前壁纸」，留一个点了没反应的红色危险项是说谎。
    private func isVisible(_ id: MenuItemID) -> Bool {
        switch id {
        case .pauseResume, .nextVideo, .deleteCurrent: return !isEmpty
        case .rescanFolder, .openSettings, .quit: return true
        }
    }

    private func glyph(for id: MenuItemID) -> String {
        switch id {
        case .pauseResume: return isPaused ? "play.fill" : "pause.fill"
        case .nextVideo: return "forward.end.fill"
        case .rescanFolder: return "arrow.clockwise"
        case .deleteCurrent: return "trash"
        case .openSettings: return "gearshape"
        case .quit: return "power"
        }
    }

    private var emptyPrimaryGlyph: String {
        session.lastLibraryState == .noPlayableVideos ? "film" : "folder"
    }

    private func shortcutHint(for id: MenuItemID) -> String? {
        switch id {
        case .openSettings: return "⌘,"
        case .quit: return "⌘Q"
        default: return nil
        }
    }

    private func rowStyle(for id: MenuItemID) -> MenuRowStyle {
        switch id {
        case .pauseResume: return .primary
        case .deleteCurrent: return .danger
        default: return .normal
        }
    }

    private func activate(_ id: MenuItemID) {
        dismiss()
        MenuBarModel.perform(id, isPaused: isPaused, arbiter: arbiter,
                             quit: terminate, nextVideo: nextVideo,
                             rescanFolder: rescanFolder, deleteCurrent: deleteCurrent)
        // perform(.openSettings) 刻意是空操作：窗这一侧由调用方处理（与旧 MenuContentView 同一分工）。
        if id == .openSettings { openSettings(0) }
    }
}

// ── 面板行（.mrow）。三态：normal / primary（品牌底）/ danger（红字，hover 红底）──
/// 行样式的可见域 = 本文件：MenuPanelView 与 MenuRow 共用，不提到文件外。
fileprivate enum MenuRowStyle { case normal, primary, danger }

private struct MenuRow: View {
    let glyph: String
    let label: String
    var shortcut: String? = nil
    var style: MenuRowStyle = .normal
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: glyph)
                    .font(.system(size: 12))
                    .opacity(0.8)
                    .frame(width: 16)
                Text(label)
                    .font(.system(size: 12.5, weight: style == .primary ? .semibold : .regular))
                Spacer(minLength: 0)
                if let shortcut {
                    Text(shortcut)
                        .font(mono(10))
                        .foregroundStyle(shortcutColor)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .foregroundStyle(textColor)
            .background(
                RoundedRectangle(cornerRadius: Metrics.ctlRadius, style: .continuous)
                    .fill(background)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.12), value: hovering)
    }

    private var textColor: Color {
        switch style {
        case .primary: return .pBrandInk
        case .danger: return .pBad
        case .normal: return .pInk
        }
    }

    private var shortcutColor: Color {
        style == .primary ? .pBrandInk.opacity(0.65) : .pInk3
    }

    private var background: Color {
        switch style {
        case .primary: return .pBrand
        case .danger: return hovering ? .pBadSoft : .clear
        case .normal: return hovering ? .pSurface2 : .clear
        }
    }
}
