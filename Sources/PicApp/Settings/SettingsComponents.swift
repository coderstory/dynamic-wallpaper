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

    // 行动色：草绿。
    // 双色规则：brand 只作填充底，上面放 brandInk（近黑）；
    // brand 作文字时用 brandText（白底达标）。白字在亮绿底对比不足，禁用。
    static let pBrand     = Color(red: 0x7C/255, green: 0xB3/255, blue: 0x42/255)
    static let pBrandInk  = Color(red: 0x0F/255, green: 0x23/255, blue: 0x05/255)
    /// brand 出现在文字位（徽标、状态字）时的替身。
    static let pBrandText = Color(red: 0x55/255, green: 0x8B/255, blue: 0x2F/255)
    /// 强调色的浅底。从 pBrand 派生，不手写第二份绿（用户拍板单一绿）。
    static let pBrandSoft = pBrand.opacity(0.2)

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

    // 状态色：三态语义。pOk 与强调色同色（用户拍板单一绿），不复用规则对其余各色仍成立。
    static let pOk       = pBrand
    static let pOkSoft   = pBrand.opacity(0.14)
    static let pHold     = Color(red: 0x8A/255, green: 0x5A/255, blue: 0x00/255)
    static let pHoldSoft = Color(red: 0xFA/255, green: 0xEF/255, blue: 0xD9/255)
    static let pBad      = Color(red: 0xC0/255, green: 0x2B/255, blue: 0x4E/255)
    /// 破坏性按钮上的字。**浅色主题下是白，深色主题下必须是近黑** —— 本版只出浅色，改主题时别忘。
    static let pBadInk   = Color.white
    static let pBadSoft  = Color(red: 0xFB/255, green: 0xE3/255, blue: 0xE8/255)
}

/// 字阶：正文/行 13 · 辅助 11 · 小徽标/chip 10 · 页标题 17 · hero 15 · 统计数字 21（mono）。
/// 数值一律 mono。例外：26 只用于 AboutIcon 占位图标的字形高，不是文字。

/// 动效令牌。**全站唯一一份时长/曲线出处** —— 之前各控件自带 `.easeOut(0.12)` 之类的字面量，
/// 同一个交互在按钮里是 0.12、在开关里是 0.15，攒多了就成了「动效很乱」的观感。
/// 三档语义：press 按压反馈（最快）／state 状态切换（默认）／enter 出入场。
enum Motion {
    /// 按压反馈。必须快：慢于 ~0.15s 手感就变成「卡了一下」。
    static let press = Animation.easeOut(duration: 0.12)
    /// 状态切换（选中态、开关、滑块位置）。用带轻微回弹的曲线，手感「有实体」。
    static let state = Animation.spring(response: 0.26, dampingFraction: 0.82)
    /// 出入场（页签内容、警示条、条件渲染的卡）。
    static let enter = Animation.easeOut(duration: 0.22)
    /// 悬停底色这类纯装饰变化：淡入即可，不需要弹簧。
    static let fade = Animation.easeOut(duration: 0.14)
}

/// 等宽字体：数值 / 副标签 / 版本号 / 命令。字体切换的唯一入口。
func mono(_ size: CGFloat, _ w: Font.Weight = .regular) -> Font {
    // 全档 +2 = 密度抬档 +1 与「最小档抬档后再全档 +1」（用户拍板 DPI 式整体放大）。
    // 9→10、10→11 的小档映射后再全体 +1；调用点不动。
    let raised = size <= 9 ? size + 1 : (size == 10 ? 11 : size)
    return .system(size: raised + 2, weight: w, design: .monospaced)
}

/// 版本号取自 bundle，不硬编码。侧栏身份区与「关于」卡共用这一份。
func appVersion() -> String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
}

/// 玻璃开：实色面同色染色 85%（子面档）。卡=根上浅一档（CardSurface 0.80，不走这里）。
/// 关：原色，平面路径零变化。
/// 只用于「面」——胶囊底 / 轨道 / 芯片 / 软底。旋钮、行动实底（pBrand/pBad）与图标盒不走这里。
func glassTinted(_ c: Color, _ glass: Bool) -> Color {
    glass ? c.opacity(0.85) : c
}

/// 圆体：卡片标题 / 行标题 / hero。取不到时回退到系统无衬线，不打包字体文件。
func display(_ size: CGFloat, _ w: Font.Weight = .semibold) -> Font {
    // 全档 +1（DPI 式整体放大）；小档映射 9→11、10→12 先行。调用点不动。
    let raised = size <= 9 ? 11 : (size == 10 ? 12 : size)
    return .system(size: raised + 1, weight: w, design: .rounded)
}

// ── 间距 / 圆角常量 ──
enum Metrics {
    // v2 shell 骨架（ui-redesign-v2-shell.html §02）。窗宽唯一来源是
    // SettingsPresentation.windowWidth，这里不再存第二份拷贝。
    static let sidebarWidth: CGFloat = 216
    static let topbarHeight: CGFloat = 44
    /// 顶栏左端让开系统红绿灯的宽度 = 「壁纸儿」的 leading。
    /// 灯由 rearmTrafficLights 定到 close 左缘 x=20，灯群右缘 ≈74（20 + 灯径与间距）；
    /// 84 使文字与灯右缘保持 10pt 间距。灯位若再调，这里与 AppDelegate 一起重排。
    static let trafficLightInset: CGFloat = 90
    /// 灯心「距窗顶」的几何推导回落值：标准标题栏 28pt、灯垂直居中 → 14。
    /// 灯心距窗顶的标准几何位：标题栏 28pt 的垂直中心。
    static let defaultLightCenterFromTop: CGFloat = 14
    static let cardRadius: CGFloat = 14
    static let contentPadding: CGFloat = 18

    // 磁贴网格（v2 g2：gap 14）
    static let gridGap: CGFloat = 14
    static let tilePadding: CGFloat = 16
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
                        // 这里**保留** y: 1 的向下阴影（全站唯一例外）：旋钮是「压在轨道上」
                        // 的语义，向下投影就是接触感。与 SlideSegmented 那个不同 ——
                        // 滑块的阴影没有任何语义，只有视觉重心偏移的副作用。
                        .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
                        .offset(x: configuration.isOn
                                ? (Metrics.toggleW - Metrics.toggleKnob) / 2 - 2.5
                                : -(Metrics.toggleW - Metrics.toggleKnob) / 2 + 2.5)
                        .animation(Motion.state, value: configuration.isOn)
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
    @Environment(\.liquidGlassActive) private var glass
    @State private var dragging = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let pct = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            ZStack(alignment: .leading) {
                Capsule().fill(glassTinted(Color.pSurface3, glass))
                    .frame(width: w, height: Metrics.sliderTrack)
                Capsule().fill(Color.pBrand)
                    .frame(width: max(0, w * pct), height: Metrics.sliderTrack)
                Circle().fill(.white)
                    .frame(width: Metrics.sliderKnob, height: Metrics.sliderKnob)
                    .shadow(color: .black.opacity(0.22), radius: dragging ? 3 : 2, y: 0)
                    .overlay(Circle().strokeBorder(Color.pBrand, lineWidth: 2))
                    // 按下时放大一点：滑杆是连续量控件，用户的手指会挡住滑块，
                    // 放大是「我抓到了」的触觉替代反馈。
                    .scaleEffect(dragging ? 1.15 : 1)
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
        // 拖动中**不**加动画 —— 手指驱动的东西加了动画会变成「跟手延迟」，
        // 反而更难停到目标值。只有非拖动的跳变（VoiceOver 调节、设置写回）才过渡。
        .animation(dragging ? nil : Motion.state, value: value)
        .animation(Motion.press, value: dragging)
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
    @Environment(\.liquidGlassActive) private var glass

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
                        // 垂直居中靠「铺满段高 + 内容自身居中」两件事一起成立：只写
                        // frame(height:) 时 Text 在该框内居中，但 Button 的命中区仍按
                        // 文字固有高度算 —— 两者不一致就会出现视觉偏上。两行都给足。
                        .frame(maxWidth: .infinity)
                        .frame(height: Metrics.segMinHeight - 6)
                        .background(RoundedRectangle(cornerRadius: Metrics.ctlRadius - 3,
                                                     style: .continuous).fill(fill))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxHeight: .infinity)
                .accessibilityElement()
            }
        }
        .frame(height: Metrics.segMinHeight - Metrics.segPadding * 2)
        .padding(Metrics.segPadding)
        .background(
            RoundedRectangle(cornerRadius: Metrics.ctlRadius, style: .continuous)
                .fill(glassTinted(Color.pSurface2, glass))
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
    @Environment(\.liquidGlassActive) private var glass
    /// 局部样式开关（默认 nil = 其余调用点渲染逐字节不变）：传值后每段 = SF Symbol + 文字。
    /// 只有顶栏「壁纸来源」切换用（用户拍板的升级版滑轨）。
    var icons: [String]? = nil

    var body: some View {
        GeometryReader { geo in
            let segmentWidth = geo.size.width / CGFloat(items.count)
            // 轨道高 = geo 高 - 上下各2 内缩。**滑块与文字共用这一个值**：
            // 之前滑块走绝对 offset(x) 定位、段文字走 HStack 布局，两者在
            // `ZStack(alignment: .leading)` 里的垂直基准不同（leading 只管水平），
            // 于是文字比滑块高一点 —— 选中段看起来「没垂直居中」。
            // 现在两层都用同一个 `segHeight` 且都用 .frame 定位，基准必然一致。
            let segHeight = geo.size.height - 4
            ZStack(alignment: .leading) {
                // 白滑块：位置随 index 弹簧滑移，不逐段淡入淡出。圆角 6 与 HTML .seg .knob 一致。
                //
                // **阴影刻意不给 y 偏移**（y: 1 → y: 0）。实测截图量化：几何上白块与轨道
                // 中心完全一致（都是 36px），但 `y: 1` 的阴影把视觉重心往下拽了 1pt，
                // 于是看着「沉在下面」。**这是阴影造成的错觉，不是布局 bug** ——
                // 但用户看到的是真实观感，所以修阴影而不是动 frame（后者会真的错位）。
                // 半径也收一点：2 → 1.5，避免白块下缘透出灰底像有双层边。
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.pSurface)
                    .shadow(color: .black.opacity(0.13), radius: 1.5, y: 0)
                    .frame(width: segmentWidth - 4, height: segHeight)
                    .offset(x: CGFloat(index) * segmentWidth + 2)
                HStack(spacing: 0) {
                    ForEach(items.indices, id: \.self) { i in
                        Button { index = i } label: {
                            HStack(spacing: 3) {
                                if let icons {
                                    Image(systemName: icons[i])
                                        .font(.system(size: 11))
                                        .foregroundStyle(index == i ? Color.pInk : Color.pInk2)
                                }
                                Text(items[i])
                                    .font(.system(size: 11, weight: index == i ? .semibold : .regular))
                                    .foregroundStyle(index == i ? Color.pInk : Color.pInk2)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: segHeight)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        // 自绘分段没有内建 AX 语义：逐段合成，选中段标 isSelected。
                        .accessibilityElement()
                        .accessibilityAddTraits(index == i ? [.isSelected, .isButton] : .isButton)
                        .modifier(OptionalSegmentID(id: itemIdentifiers.flatMap { i < $0.count ? $0[i] : nil }))
                    }
                }
                .frame(height: segHeight)
            }
            // GeometryReader 默认 topLeading 落子：不补这一帧，segHeight 的内容贴 GR 顶，
            // 段在轨里整体偏上（图标入段后偏移更扎眼）。补满 GR 后 ZStack 才能垂直居中。
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: Metrics.ctlRadius - 3, style: .continuous)
                .fill(glassTinted(track, glass))
        )
        .animation(Motion.state, value: index)
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
    @Environment(\.liquidGlassActive) private var glass

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
            .animation(Motion.press, value: configuration.isPressed)
    }

    private var bg: Color {
        if destructive { return .pBad }
        if primary { return .pBrand }
        return glassTinted(.pSurface2, glass)
    }

    private var fg: Color {
        if destructive { return .pBadInk }
        if primary { return .pBrandInk }
        return .pInk
    }
}

/// 小号按钮：卡片尾部那一排（选择… / 重新扫描）用它，与卡片标题同排不能太大。
struct GlowSmallButton: ButtonStyle {
    @Environment(\.liquidGlassActive) private var glass
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // 下限对齐 GlowButton 基线（13/14/7，「打开队列」档）——任何按钮不得更小。
            .font(.system(size: 13))
            .foregroundStyle(Color.pInk)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: Metrics.ctlRadius, style: .continuous)
                    .fill(glassTinted(Color.pSurface2, glass))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}
