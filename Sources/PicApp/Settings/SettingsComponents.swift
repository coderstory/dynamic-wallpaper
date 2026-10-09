import SwiftUI
import AppKit
import PicCore

// 设置窗组件层：配色令牌、间距常量、通用控件。
// 字体一律系统默认（用户拍板，不打包字体文件），等宽走 `mono(_:_:)`。

// ── 配色令牌 ──
// v2 shell 令牌，来源 ui-redesign-v2-shell.html，对比度口径 4.5:1。
// 改值后重跑 `.planning/design/contrast-audit.py`，旧结论作废。
extension Color {
    // 结构
    static let pGround   = Color(red: 0xF3/255, green: 0xF4/255, blue: 0xF7/255)
    static let pSurface  = Color.white
    static let pSurface2 = Color(red: 0xED/255, green: 0xF0/255, blue: 0xF4/255)
    static let pSurface3 = Color(red: 0xE2/255, green: 0xE6/255, blue: 0xEC/255)
    /// 卡片描边（v2 是描边分层，不是投影）。
    static let pLine     = Color(red: 0xDA/255, green: 0xE0/255, blue: 0xE8/255)
    /// 卡片内部发丝线：取 surface2 而非 line —— 后者在白卡上太硬。
    static let pDivider  = pSurface2

    // 文字
    static let pInk  = Color(red: 0x15/255, green: 0x18/255, blue: 0x1E/255)
    static let pInk2 = Color(red: 0x5B/255, green: 0x63/255, blue: 0x71/255)
    static let pInk3 = Color(red: 0x64/255, green: 0x6C/255, blue: 0x79/255)

    // 行动色：暖橙（与 App 图标渐变同族）。
    // 双色规则：brand 只作填充底，上面放 brandInk（近黑）；
    // brand 作文字时用 brandText（白底达标）。白字在亮橙底对比不足，禁用。
    static let pBrand     = Color(red: 0xF4/255, green: 0x70/255, blue: 0x1B/255)
    static let pBrandInk  = Color(red: 0x2A/255, green: 0x11/255, blue: 0x04/255)
    /// brand 出现在文字位（徽标、状态字）时的替身。
    static let pBrandText = Color(red: 0xB2/255, green: 0x45/255, blue: 0x0A/255)
    static let pBrandSoft = Color(red: 0xFF/255, green: 0xE8/255, blue: 0xD8/255)

    // 播放区（play）身份色复用 brand 四件套，不另设。

    // 片库区身份色
    static let pLib      = Color(red: 0x2C/255, green: 0x7B/255, blue: 0xE5/255)
    static let pLibInk   = Color(red: 0x06/255, green: 0x10/255, blue: 0x1F/255)
    static let pLibText  = Color(red: 0x1A/255, green: 0x55/255, blue: 0xA8/255)
    static let pLibSoft  = Color(red: 0xDE/255, green: 0xE9/255, blue: 0xFC/255)

    // 队列区身份色
    static let pQueue     = Color(red: 0x8A/255, green: 0x63/255, blue: 0xFF/255)
    static let pQueueInk  = Color(red: 0x0A/255, green: 0x04/255, blue: 0x20/255)
    static let pQueueText = Color(red: 0x56/255, green: 0x28/255, blue: 0xCC/255)
    static let pQueueSoft = Color(red: 0xE9/255, green: 0xE1/255, blue: 0xFF/255)

    // 通用区身份色
    static let pGen      = Color(red: 0x0E/255, green: 0x93/255, blue: 0x84/255)
    static let pGenInk   = Color(red: 0x02/255, green: 0x11/255, blue: 0x10/255)
    static let pGenText  = Color(red: 0x0A/255, green: 0x6B/255, blue: 0x61/255)
    static let pGenSoft  = Color(red: 0xD6/255, green: 0xF3/255, blue: 0xEF/255)

    // 状态色：三态语义，不复用行动色与身份色
    static let pOk       = Color(red: 0x09/255, green: 0x70/255, blue: 0x55/255)
    static let pOkSoft   = Color(red: 0xE0/255, green: 0xF5/255, blue: 0xEF/255)
    static let pHold     = Color(red: 0x8A/255, green: 0x5A/255, blue: 0x00/255)
    static let pHoldSoft = Color(red: 0xFA/255, green: 0xEF/255, blue: 0xD9/255)
    static let pBad      = Color(red: 0xC0/255, green: 0x2B/255, blue: 0x4E/255)
    /// 破坏性按钮上的字。**浅色主题下是白，深色主题下必须是近黑** —— 本版只出浅色，改主题时别忘。
    static let pBadInk   = Color.white
    static let pBadSoft  = Color(red: 0xFB/255, green: 0xE3/255, blue: 0xE8/255)
}

/// 字阶：正文/行 13 · 辅助 11 · 小徽标/chip 10 · 页标题 17 · hero 15 · 统计数字 21（mono）。
/// 数值一律 mono。例外：26 只用于 AboutIcon 占位图标的字形高，不是文字。

/// 等宽字体：数值 / 副标签 / 版本号 / 命令。字体切换的唯一入口。
func mono(_ size: CGFloat, _ w: Font.Weight = .regular) -> Font {
    .system(size: size, weight: w, design: .monospaced)
}

/// 版本号取自 bundle，不硬编码。侧栏身份区与「关于」卡共用这一份。
func appVersion() -> String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
}

/// 圆体：卡片标题 / 行标题 / hero。取不到时回退到系统无衬线，不打包字体文件。
func display(_ size: CGFloat, _ w: Font.Weight = .semibold) -> Font {
    .system(size: size, weight: w, design: .rounded)
}

// ── 间距 / 圆角常量 ──
enum Metrics {
    // v2 shell 骨架（ui-redesign-v2-shell.html §02）。窗宽唯一来源是
    // SettingsPresentation.windowWidth，这里不再存第二份拷贝。
    static let sidebarWidth: CGFloat = 216
    static let topbarHeight: CGFloat = 44
    static let cardRadius: CGFloat = 14
    static let contentPadding: CGFloat = 18

    // 磁贴网格（v2 g2：gap 14）
    static let gridGap: CGFloat = 14
    static let tilePadding: CGFloat = 14
    static let tileGap: CGFloat = 12
    // 圆角：磁贴/卡片 14、控件/行 10。
    static let tileRadius: CGFloat = 14
    static let ctlRadius: CGFloat = 10

    // 卡片内的一行
    static let rowMinHeight: CGFloat = 34
    static let rowGap: CGFloat = 11

    // 开关（HTML .tgl：42×24，滑块 20pt）
    static let toggleW: CGFloat = 42
    static let toggleH: CGFloat = 24
    static let toggleKnob: CGFloat = 20

    // 滑杆。**没有定宽常量** —— 滑杆铺满卡片，
    // 定宽会让两条轨道右端对齐的诉求变成「一起挤在左边」。
    static let sliderHeight: CGFloat = 26    // 命中区 ≥24
    static let sliderTrack: CGFloat = 5
    static let sliderKnob: CGFloat = 15

    // 刻度选择器 / 分段控件
    static let tickMinWidth: CGFloat = 20
    static let segMinHeight: CGFloat = 30
    static let segPadding: CGFloat = 3

    // 关于卡
    static let aboutIcon: CGFloat = 58
    static let aboutIconRadius: CGFloat = 15

    /// 滑杆与开关右侧那个定宽读数。定宽才让几行读数的小数点对齐。
    static let valueWidth: CGFloat = 46
}

// ── 关于卡图标 ──
// 必须显式 NSImage 加载：app 图标编译成 bundle 根部的 Pic.icns（CFBundleIconFile），
// 不在 Resources/，SwiftUI 按名查找取不到 —— Image("AppIcon") 渲染为空白。
struct AboutIcon: View {
    private let image: NSImage?

    init() {
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") as? String
        let candidates = [name, "Pic", "AppIcon"].compactMap { $0 }
        var found: NSImage?
        for key in candidates {
            if let url = Bundle.main.url(forResource: key, withExtension: "icns"),
               let img = NSImage(contentsOf: url) { found = img; break }
            // Bundle.image 层（含 @2x/@3x 变体）
            if let img = Bundle.main.image(forResource: key) { found = img; break }
        }
        image = found
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
            } else {
                // 取不到时给占位块，空白会被误读成「图标丢了」
                RoundedRectangle(cornerRadius: Metrics.aboutIconRadius, style: .continuous)
                    .fill(Color.pBrandSoft)
                    .overlay(
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(Color.pBrandText)
                    )
            }
        }
        .frame(width: Metrics.aboutIcon, height: Metrics.aboutIcon)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.aboutIconRadius, style: .continuous))
    }
}

// ── 自定义开关：42×24，滑块 18pt ──
struct GlowToggle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            Capsule()
                .fill(configuration.isOn ? Color.pBrand : Color.pSurface3)
                .frame(width: Metrics.toggleW, height: Metrics.toggleH)
                .overlay(
                    Circle()
                        .fill(.white)
                        .frame(width: Metrics.toggleKnob, height: Metrics.toggleKnob)
                        .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
                        .offset(x: configuration.isOn
                                ? (Metrics.toggleW - Metrics.toggleKnob) / 2 - 2.5
                                : -(Metrics.toggleW - Metrics.toggleKnob) / 2 + 2.5)
                        .animation(.easeInOut(duration: 0.15), value: configuration.isOn)
                )
        }
        .buttonStyle(.plain)
        // 自绘开关经 ToggleStyle 包裹后仍不进 AX 树，必须显式合成，
        // 否则 VoiceOver 读不到、XCUITest 的 `battery-toggle` 查不到。
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
    }
}

// ── 自绘滑杆：铺满可用宽度 ──
// 手势不认 SwiftUI 的 .disabled（那只置灰原生控件），自己读一次 isEnabled。
struct GlowSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    /// VoiceOver 的标签与读数。自绘控件**没有任何内建无障碍语义** —— 不补，这把滑杆对读屏用户
    /// 等于不存在。读数由调用方传进来：它与旁边那个数字用同一个 formatter，格式化规则不能有两份。
    let label: String
    let valueText: String
    /// 拖动中回调（当场生效，不写盘）；拖动结束回调（persist 恰一次）。
    var onChanged: (() -> Void)? = nil
    var onEnded: (() -> Void)? = nil
    @Environment(\.isEnabled) private var isEnabled
    @State private var dragging = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let pct = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.pSurface3)
                    .frame(width: w, height: Metrics.sliderTrack)
                Capsule().fill(Color.pBrand)
                    .frame(width: max(0, w * pct), height: Metrics.sliderTrack)
                Circle().fill(.white)
                    .frame(width: Metrics.sliderKnob, height: Metrics.sliderKnob)
                    .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
                    .overlay(Circle().strokeBorder(Color.pBrand, lineWidth: 2))
                    .offset(x: max(0, min(w - Metrics.sliderKnob, w * pct - Metrics.sliderKnob / 2)))
            }
            .frame(height: Metrics.sliderHeight)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                guard isEnabled else { return }
                dragging = true
                let p = min(max(0, g.location.x / w), 1)
                value = range.lowerBound + p * (range.upperBound - range.lowerBound)
                onChanged?()
            }.onEnded { _ in
                guard isEnabled else { return }
                dragging = false
                onEnded?()
            })
        }
        // 不给定宽：滑杆铺满所在卡片。
        .frame(height: Metrics.sliderHeight)
        .accessibilityElement()
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(valueText))
        // 读屏用户没有「拖」这个动作，必须给可调节语义，否则控件的值不可达也不可改。
        .accessibilityAdjustableAction { direction in
            guard isEnabled else { return }
            // 步长取量程的 1/20：速度档 0.5…2 一格约 0.075，音量 0…100 一格 5。
            let step = (range.upperBound - range.lowerBound) / 20
            switch direction {
            case .increment: value = min(range.upperBound, value + step)
            case .decrement: value = max(range.lowerBound, value - step)
            @unknown default: return
            }
            onChanged?()
            onEnded?()
        }
    }
}

// ── 分段控件：值选择用，3–4 格等分，选中段 brand 实心 ──
struct GlowSegmented: View {
    let items: [String]
    @Binding var index: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items.indices, id: \.self) { i in
                let on = index == i
                let fill: Color = on ? Color.pBrand : .clear
                let fg: Color = on ? Color.pBrandInk : Color.pInk2
                Button { index = i } label: {
                    Text(items[i])
                        .font(.system(size: 11, weight: on ? .semibold : .regular))
                        .foregroundStyle(fg)
                        .frame(maxWidth: .infinity)
                        .frame(height: Metrics.segMinHeight - 6)
                        .background(RoundedRectangle(cornerRadius: Metrics.ctlRadius - 3,
                                                     style: .continuous).fill(fill))
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

// ── 滑块分段：导航/筛选这类中性选择 ──
/// iOS 式「灰轨道 + 白滑块」，滑块 0.2s 弹簧滑移。brand 实心只留给值选择（GlowSegmented），
/// 这类导航保持中性 —— 一屏内橙色块才不会失控。
/// 控件铺满调用方给定的宽度、段宽均分；外层用 .frame(width:height:) 控制总宽。
/// `track` 可换：顶栏底色就是 surface2，轨道同色会看不见，那里传 surface3。
/// `itemIdentifiers` 逐段挂 identifier（如顶栏来源切换的两段），不需要就不传。
struct SlideSegmented: View {
    let items: [String]
    @Binding var index: Int
    var track: Color = .pSurface2
    var itemIdentifiers: [String]? = nil

    var body: some View {
        GeometryReader { geo in
            let segmentWidth = geo.size.width / CGFloat(items.count)
            ZStack(alignment: .leading) {
                // 白滑块：位置随 index 弹簧滑移，不逐段淡入淡出。圆角 6 与 HTML .seg .knob 一致。
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.pSurface)
                    .shadow(color: .black.opacity(0.10), radius: 2, y: 1)
                    .frame(width: segmentWidth - 4, height: geo.size.height - 4)
                    .offset(x: CGFloat(index) * segmentWidth + 2)
                HStack(spacing: 0) {
                    ForEach(items.indices, id: \.self) { i in
                        Button { index = i } label: {
                            Text(items[i])
                                .font(.system(size: 11, weight: index == i ? .semibold : .regular))
                                .foregroundStyle(index == i ? Color.pInk : Color.pInk2)
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        // 自绘分段没有内建 AX 语义：逐段合成，选中段标 isSelected。
                        .accessibilityElement()
                        .accessibilityAddTraits(index == i ? [.isSelected, .isButton] : .isButton)
                        .modifier(OptionalSegmentID(id: itemIdentifiers.flatMap { i < $0.count ? $0[i] : nil }))
                    }
                }
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: Metrics.ctlRadius - 3, style: .continuous)
                .fill(track)
        )
        .animation(.spring(response: 0.22, dampingFraction: 0.85), value: index)
    }
}

/// identifier 只在给了值时挂：空串 identifier 会污染 AX 查询。
private struct OptionalSegmentID: ViewModifier {
    let id: String?
    func body(content: Content) -> some View {
        if let id { content.accessibilityIdentifier(id) } else { content }
    }
}

// ── 按钮 ──
struct GlowButton: ButtonStyle {
    var primary = false
    /// 破坏性操作用实心 bad 底 + badInk 字。**不用 outline 红字** —— 那与「失败状态」的文案色
    /// 撞在一起，用户分不清哪个是状态、哪个是可点的动作。
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: primary || destructive ? .semibold : .regular))
            .foregroundStyle(fg)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: Metrics.ctlRadius, style: .continuous).fill(bg)
            )
            // 统一按压语言：缩放代替透明度。
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var bg: Color {
        if destructive { return .pBad }
        if primary { return .pBrand }
        return .pSurface2
    }

    private var fg: Color {
        if destructive { return .pBadInk }
        if primary { return .pBrandInk }
        return .pInk
    }
}

/// 小号按钮：卡片尾部那一排（选择… / 重新扫描）用它，与卡片标题同排不能太大。
struct GlowSmallButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11))
            .foregroundStyle(Color.pInk)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: Metrics.ctlRadius, style: .continuous)
                    .fill(Color.pSurface2)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
