import SwiftUI
import AppKit
import PicCore

// 设置窗组件层：配色令牌、间距常量、通用控件。
// 数值全部照抄设计稿 `.planning/design/ui-rotation-a.html`，不自由发挥。
// 字体一律系统默认（用户拍板，不打包字体文件），等宽走 `mono(_:_:)`。

// ── 配色令牌 ──
// 数值来自 `.planning/design/DESIGN-SPEC.md` v1.3（D 圆润亲和）。
// 已由 `.planning/design/contrast-audit.py` 实测 36 组配对 ≥4.5:1，最低 4.56:1；改值后重跑。
extension Color {
    // 结构
    static let pGround   = Color(red: 0xF5/255, green: 0xF7/255, blue: 0xFB/255)
    static let pSurface  = Color.white
    static let pSurface2 = Color(red: 0xEE/255, green: 0xF1/255, blue: 0xF8/255)
    static let pSurface3 = Color(red: 0xE4/255, green: 0xE9/255, blue: 0xF4/255)
    /// 磁贴内部的分隔线。本设计靠投影分层、不用描边；但磁贴内部仍需分隔，
    /// 取 surface2 而非 line —— 后者在白卡上太硬。
    static let pDivider  = pSurface2

    // 文字
    static let pInk  = Color(red: 0x14/255, green: 0x18/255, blue: 0x21/255)
    static let pInk2 = Color(red: 0x5B/255, green: 0x64/255, blue: 0x74/255)
    static let pInk3 = Color(red: 0x62/255, green: 0x6C/255, blue: 0x7C/255)

    // 行动色：只用于主按钮 / 选中 / 焦点，不做装饰
    static let pBrand     = Color(red: 0xC0/255, green: 0x32/255, blue: 0x55/255)
    static let pBrandInk  = Color.white
    static let pBrandSoft = Color(red: 0xFC/255, green: 0xE7/255, blue: 0xEC/255)

    // 状态色：三态语义，不复用行动色
    static let pOk       = Color(red: 0x0A/255, green: 0x7C/255, blue: 0x5E/255)
    static let pOkSoft   = Color(red: 0xE2/255, green: 0xF5/255, blue: 0xEF/255)
    static let pHold     = Color(red: 0x9E/255, green: 0x5E/255, blue: 0x0A/255)
    static let pHoldSoft = Color(red: 0xFB/255, green: 0xEF/255, blue: 0xDE/255)
    static let pBad      = Color(red: 0x8E/255, green: 0x2B/255, blue: 0x3E/255)
    /// 破坏性按钮上的字。**浅色主题下是白，深色主题下必须是近黑** ——
    /// 深色的 bad 是亮砖红，白字压上去只有 2.49:1。本版只出浅色，改主题时别忘。
    static let pBadInk   = Color.white
    static let pBadSoft  = Color(red: 0xF7/255, green: 0xE4/255, blue: 0xE8/255)
}

/// 等宽字体：数值 / 副标签 / 版本号 / 命令。字体切换的唯一入口。
func mono(_ size: CGFloat, _ w: Font.Weight = .regular) -> Font {
    .system(size: size, weight: w, design: .monospaced)
}

/// 圆体：标题 / 眉标 / 关于页名称。本设计用系统圆体表达「亲和」，
/// 取不到时回退到系统无衬线。不打包字体文件。
func display(_ size: CGFloat, _ w: Font.Weight = .semibold) -> Font {
    .system(size: size, weight: w, design: .rounded)
}

// ── 间距 / 圆角常量 ──
enum Metrics {
    // 窗口
    static let windowWidth: CGFloat = 780
    static let winPadding: CGFloat = 16
    static let blockGap: CGFloat = 16

    // 磁贴网格
    static let gridGap: CGFloat = 12
    static let tilePadding: CGFloat = 14
    static let tileGap: CGFloat = 12
    static let tileRadius: CGFloat = 14
    static let ctlRadius: CGFloat = 12

    // 磁贴内的一行
    static let rowMinHeight: CGFloat = 34
    static let rowGap: CGFloat = 11

    // 开关
    static let toggleW: CGFloat = 42
    static let toggleH: CGFloat = 24
    static let toggleKnob: CGFloat = 18

    // 滑杆。**没有定宽常量** —— 本设计里滑杆铺满磁贴，
    // 旧的 sliderWidth=128 定宽会让两条轨道右端对齐的诉求变成「一起挤在左边」。
    static let sliderHeight: CGFloat = 26    // 命中区 ≥24
    static let sliderTrack: CGFloat = 5
    static let sliderKnob: CGFloat = 15

    // 刻度选择器 / 分段控件
    static let tickMinWidth: CGFloat = 20
    static let segMinHeight: CGFloat = 30
    static let segPadding: CGFloat = 3

    // 关于页
    static let aboutIcon: CGFloat = 58
    static let aboutIconRadius: CGFloat = 15

    // 数字
    static let countFont: CGFloat = 17
    static let countTopFont: CGFloat = 21

    /// 滑杆与开关右侧那个定宽读数。定宽才让几行读数的小数点对齐。
    static let valueWidth: CGFloat = 46
}

// ── 关于页图标 ──
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
                            .foregroundStyle(Color.pBrand)
                    )
            }
        }
        .frame(width: Metrics.aboutIcon, height: Metrics.aboutIcon)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.aboutIconRadius, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 6, y: 3)
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
        // 不给定宽：本设计里滑杆铺满磁贴。旧的 sliderWidth=128 定宽会让
        // 「两条轨道右端对齐」退化成「一起挤在左边」。
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

// ── 分段控件：播放模式用，3 格等分 ──
struct GlowSegmented: View {
    let items: [String]
    @Binding var index: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(items.indices, id: \.self) { i in
                let on = index == i
                let fill: Color = on ? Color.pBrand : .clear
                let fg: Color = on ? Color.pBrandInk : Color.pInk2
                Button { index = i } label: {
                    Text(items[i])
                        .font(.system(size: 11.5, weight: on ? .semibold : .regular))
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

// ── 顶部 TAB：选中态是淡色底片，不是实心块 ──
struct TabBar: View {
    let items: [String]
    @Binding var index: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items.indices, id: \.self) { i in
                let on = index == i
                Button { index = i } label: {
                    Text(items[i])
                        .font(.system(size: 12.5, weight: on ? .semibold : .regular))
                        .foregroundStyle(on ? Color.pBrand : Color.pInk2)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(on ? Color.pBrandSoft : .clear))
                        // 同上：没 contentShape 时只有文字可点
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement()
            }
        }
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
            .font(.system(size: 12, weight: primary || destructive ? .semibold : .regular))
            .foregroundStyle(fg)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: Metrics.ctlRadius, style: .continuous).fill(bg)
            )
            .opacity(configuration.isPressed ? 0.78 : 1)
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

/// 小号按钮：磁贴尾部那一排（选择… / 重新扫描）用它，与磁贴标题同排不能太大。
struct GlowSmallButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5))
            .foregroundStyle(Color.pInk)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: Metrics.ctlRadius, style: .continuous)
                    .fill(Color.pSurface2)
            )
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}