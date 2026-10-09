import SwiftUI
import AppKit
import PicCore

// 菜单栏自绘面板（v2-flat），NSPopover 的内容。视觉同步
// `.planning/design/ui-redesign-v2-shell.html`：pGround 面板底、.cd 头部卡、
// 侧栏 navi 同语言的图标盒行。菜单项仍只由 `MenuItemID.allCases` 遍历产出、
// 动作仍只走 `MenuBarModel.perform` —— 换皮不是绕过 MenuBarModelTests 哨兵的理由。
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
    /// 切壁纸来源（视频 ⇄ 图片）。整条链在 AppDelegate 里，这里只转交意图。
    private let switchSource: () -> Void

    init(rotation: RotationController,
         dismiss: @escaping () -> Void,
         terminate: @escaping () -> Void,
         openSettings: @escaping (Int) -> Void,
         nextVideo: @escaping () -> Void,
         rescanFolder: @escaping () -> Void,
         deleteCurrent: @escaping () -> Void,
         requestFolder: @escaping () -> Void,
         switchSource: @escaping () -> Void) {
        self.rotation = rotation
        self.dismiss = dismiss
        self.terminate = terminate
        self.openSettings = openSettings
        self.nextVideo = nextVideo
        self.rescanFolder = rescanFolder
        self.deleteCurrent = deleteCurrent
        self.requestFolder = requestFolder
        self.switchSource = switchSource
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            header
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
                    // 分组靠留白，唯一保留的线在危险区（不可逆操作）前 —— 精修提案 v2.1。
                    if id == .deleteCurrent { divider }
                    MenuRow(glyph: glyph(for: id),
                            label: MenuBarModel.label(for: id, isPaused: isPaused,
                                                      kind: store.wallpaperKind),
                            shortcut: shortcutHint(for: id), style: rowStyle(for: id)) {
                        activate(id)
                    }
                    .padding(.top, startsGroup(id) ? 7 : 0)
                    .accessibilityIdentifier("menu-row-\(id.rawValue)")
                }
            }
        }
        .padding(10)
        .frame(width: 300)
        .background {
            // 液态玻璃开启时根背景是超薄材质，与设置窗根背景同一分派逻辑；
            // 关闭时是不透明 pGround，平面渲染路径零材质。
            Rectangle().fill(store.liquidGlassEnabled
                ? AnyShapeStyle(.ultraThinMaterial)
                : AnyShapeStyle(Color.pGround))
        }
        // 卡片面是否走液态玻璃只在根视图读一次 store，头部卡经环境量继承。
        .environment(\.liquidGlassActive, store.liquidGlassEnabled)
    }

    /// 组的起点（维护 / 系统）上方给 7pt 呼吸，代替原来的三条分隔线。
    private func startsGroup(_ id: MenuItemID) -> Bool {
        id == .rescanFolder || id == .openSettings
    }

    // ── 头部卡（v2 .cd）：品牌身份块 + 状态点/标题 + 副行 + 倒计时环 ──
    // 白底 + 1pt pLine 描边 + 圆角 14 + padding 14 的 CardSurface 语言，直接复用
    // 设置侧的 cardSurface() 修饰器（液态玻璃联动经环境量下传，这里零分支）。
    private var header: some View {
        HStack(spacing: 11) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.pBrand)
                        .frame(width: 28, height: 28)
                        .overlay(
                            Image(systemName: "play.rectangle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.pBrandInk)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text("壁纸儿")
                            .font(display(13))
                            .foregroundStyle(Color.pInk)
                        Text("v\(appVersion()) · arm64")
                            .font(mono(10))
                            .foregroundStyle(Color.pInk3)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Circle().fill(headerTint).frame(width: 8, height: 8)
                        Text(isEmpty || isHeld ? "已暂停" : "正在播放")
                            .font(display(13, .semibold))
                            .foregroundStyle(Color.pInk)
                    }
                    Text(headerSubline)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.pInk3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            countdownRing
        }
        .cardSurface()
    }

    private var headerTint: Color { isEmpty ? .pBad : (isHeld ? .pHold : .pOk) }

    /// 倒计时环的颜色与状态点解耦：播放中走品牌橙（用户拍板），让路仍用 hold 褐
    /// —— 环是「进行中」的仪表，点才是状态语义。
    private var ringTint: Color { isHeld ? Color.pHold : Color.pBrand }

    private var headerSubline: String {
        if let copy = emptyCopy {
            return "壁纸已隐藏 · \(copy.title)"
        }
        if isHeld {
            return "\(SettingsPresentation.joinedReasons(arbiter.decision.activeReasons)) · 条件解除后自动续播"
        }
        // 模式标签必须带 kind（图片不谈「循环」）；计数与量词同样按来源分派（`SettingsPresentation.libraryCountLine`）。
        return "\(SettingsPresentation.playModeLabel(store.playMode, kind: store.wallpaperKind))"
            + " · \(countText)"
    }

    private var countText: String {
        SettingsPresentation.libraryCountLine(kind: store.wallpaperKind,
                                              videoCount: session.playableCount,
                                              imageCount: session.imagePassing)
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
                        .stroke(ringTint, style: StrokeStyle(lineWidth: 3.6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(mmss(remaining))
                        .font(mono(11))
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
        session.lastLibraryState.flatMap { SettingsPresentation.emptyStateCopy($0, kind: store.wallpaperKind) }
    }

    /// 可见性照抄原型的 data-when：暂停/下一个只在有播放会话时出现。
    /// 刻意的偏离：删除项在空态也隐藏 —— 原型没给它写 data-when（全态可见），
    /// 但空态没有「当前壁纸」，留一个点了没反应的红色危险项是说谎。
    private func isVisible(_ id: MenuItemID) -> Bool {
        switch id {
        case .pauseResume, .nextVideo, .deleteCurrent: return !isEmpty
        case .rescanFolder, .switchSource, .openSettings, .quit: return true
        }
    }

    private func glyph(for id: MenuItemID) -> String {
        switch id {
        case .pauseResume: return isPaused ? "play.fill" : "pause.fill"
        case .nextVideo: return "forward.end.fill"
        case .rescanFolder: return "arrow.clockwise"
        // 图标说的是「切过去的那一边」：当前是图片 → 显示胶卷（切回视频）。
        case .switchSource: return store.wallpaperKind == .image ? "film" : "photo"
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
        case .pauseResume, .switchSource: return .primary
        case .deleteCurrent: return .danger
        default: return .normal
        }
    }

    private func activate(_ id: MenuItemID) {
        dismiss()
        MenuBarModel.perform(id, isPaused: isPaused, arbiter: arbiter,
                             quit: terminate, nextVideo: nextVideo,
                             rescanFolder: rescanFolder,
                             switchSource: switchSource,
                             deleteCurrent: deleteCurrent)
        // perform(.openSettings) 刻意是空操作：窗这一侧由调用方处理（与旧 MenuContentView 同一分工）。
        if id == .openSettings { openSettings(0) }
    }
}

// ── 面板行（v2：normal 带图标盒，primary 品牌实底 = gseg on 态，danger 红字照旧）──
/// 行样式的可见域 = 本文件：MenuPanelView 与 MenuRow 共用，不提到文件外。
fileprivate enum MenuRowStyle { case normal, primary, danger }

/// 统一按压语言：缩放代替透明度（精修提案 v2.1）。
private struct MenuRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct MenuRow: View {
    let glyph: String
    let label: String
    var shortcut: String? = nil
    var style: MenuRowStyle = .normal
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                glyphSlot
                Text(label)
                    .font(.system(size: 13, weight: style == .primary ? .semibold : .regular))
                Spacer(minLength: 0)
                if let shortcut {
                    Text(shortcut)
                        .font(mono(10))
                        .foregroundStyle(shortcutColor)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(textColor)
            .background(
                RoundedRectangle(cornerRadius: Metrics.ctlRadius, style: .continuous)
                    .fill(background)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuRowButtonStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    /// 图标槽：normal / primary 走 24pt 圆角 8 的图标盒（侧栏 navi 同语言，
    /// 图标 11pt 居中）；danger 不变 —— 裸 SF Symbol 13pt，仅占同一个 24pt 槽对齐。
    @ViewBuilder
    private var glyphSlot: some View {
        if style == .danger {
            Image(systemName: glyph)
                .font(.system(size: 13))
                .foregroundStyle(Color.pBad)
                .frame(width: 24, height: 24)
        } else {
            Image(systemName: glyph)
                .font(.system(size: 11))
                .foregroundStyle(boxGlyphColor)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(boxFill)
                )
        }
    }

    private var textColor: Color {
        switch style {
        case .primary: return .pBrandInk
        case .danger: return .pBad
        case .normal: return .pInk
        }
    }

    /// 图标盒底色：normal 用 surface-3（navi 的 .ic），primary 用 brandInk 淡染。
    private var boxFill: Color {
        switch style {
        case .primary: return .pBrandInk.opacity(0.18)
        case .normal: return .pSurface3
        case .danger: return .clear
        }
    }

    private var boxGlyphColor: Color {
        style == .primary ? .pBrandInk : .pInk3
    }

    private var shortcutColor: Color {
        style == .primary ? .pBrandInk.opacity(0.65) : .pInk3
    }

    /// hover 态：normal 白底（v2 navi:hover），danger 红软底，primary 恒为品牌实底。
    private var background: Color {
        switch style {
        case .primary: return .pBrand
        case .danger: return hovering ? .pBadSoft : .clear
        case .normal: return hovering ? .pSurface : .clear
        }
    }
}
