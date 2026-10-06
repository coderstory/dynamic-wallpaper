import SwiftUI
import AppKit
import PicCore

// 设置窗组件层：配色令牌、间距常量、通用控件。
// 数值全部照抄设计稿 `.planning/design/ui-rotation-a.html`，不自由发挥。
// 字体一律系统默认（用户拍板，不打包字体文件），等宽走 `mono(_:_:)`。

// ── 配色令牌 ──
extension Color {
    /// 窗底
    static let pBg      = Color(red: 0xF4/255, green: 0xF5/255, blue: 0xF7/255)
    /// 主文字
    static let pFg      = Color(red: 0x1D/255, green: 0x1D/255, blue: 0x1F/255)
    /// 标题栏文字
    static let pTitle   = Color(red: 0x3A/255, green: 0x3D/255, blue: 0x42/255)
    /// 强调色，唯一。用于选中态 / 主按钮 / 焦点
    static let pAccent  = Color(red: 0x0A/255, green: 0x6C/255, blue: 0xFF/255)
    /// 强调色上的文字
    static let pAccFg   = Color.white
    /// 副文字，对比度 ≥4.5:1
    static let pMuted   = Color(red: 0x5C/255, green: 0x60/255, blue: 0x65/255)
    /// 分隔线
    static let pSep     = Color(red: 0xEC/255, green: 0xEE/255, blue: 0xF1/255)
    /// 卡片描边
    static let pEdge    = Color.black.opacity(0.07)
    /// 卡片底
    static let pCard    = Color.white
    /// 档位格底
    static let pChipBg  = Color(red: 0xF7/255, green: 0xF8/255, blue: 0xFA/255)
    /// 滑杆轨道 / 开关关闭态
    static let pTrack   = Color(red: 0xD9/255, green: 0xDD/255, blue: 0xE2/255)
    /// TAB 条底
    static let pTabBg   = Color(red: 0xE9/255, green: 0xEB/255, blue: 0xEF/255)
    /// 分段控件底
    static let pSegBg   = Color(red: 0xED/255, green: 0xEF/255, blue: 0xF2/255)
    /// 节标题色。比强调色深一档，12pt 小字要更高对比
    static let pLabel   = Color(red: 0x0B/255, green: 0x5B/255, blue: 0xD6/255)
    /// 图标盒底
    static let pIconBg  = Color(red: 0xE6/255, green: 0xEF/255, blue: 0xFF/255)
    /// 警告（空态专用）
    static let pWarn    = Color(red: 0xE8/255, green: 0xA3/255, blue: 0x3D/255)
    /// 警告图标盒底
    static let pWarnBg  = Color(red: 0xFD/255, green: 0xF0/255, blue: 0xD8/255)
    /// 警告文字
    static let pWarnFg  = Color(red: 0xB0/255, green: 0x74/255, blue: 0x0F/255)
    /// 警告图标盒内的字
    static let pWarnIc  = Color(red: 0x8A/255, green: 0x5E/255, blue: 0x12/255)
}

/// 等宽字体：数值 / 副标签 / 版本号 / 命令。字体切换的唯一入口。
func mono(_ size: CGFloat, _ w: Font.Weight = .regular) -> Font {
    .system(size: size, weight: w, design: .monospaced)
}

// ── 间距 / 圆角常量 ──
enum Metrics {
    static let windowWidth: CGFloat = 780
    static let aboutMinHeight: CGFloat = 340
    static let winPadding: CGFloat = 16
    static let blockGap: CGFloat = 14
    static let gridGap: CGFloat = 10
    static let tilePaddingV: CGFloat = 11
    static let tilePaddingB: CGFloat = 12
    static let tilePaddingH: CGFloat = 13
    static let tileRadius: CGFloat = 11
    static let tileInnerGap: CGFloat = 9
    static let tileIcon: CGFloat = 15
    static let chipGap: CGFloat = 5
    static let chipRadius: CGFloat = 7
    static let chipMinHeight: CGFloat = 32   // 命中区 ≥24
    static let sliderWidth: CGFloat = 128    // 定宽，两条轨道右端才对齐
    static let sliderHeight: CGFloat = 26    // 命中区 ≥24
    static let sliderTrack: CGFloat = 5
    static let sliderKnob: CGFloat = 15
    static let valueWidth: CGFloat = 46
    static let toggleW: CGFloat = 42
    static let toggleH: CGFloat = 24
    static let toggleKnob: CGFloat = 19
    static let rowGap: CGFloat = 11
    static let iconBox: CGFloat = 22
    static let iconBoxRadius: CGFloat = 6
    static let countFont: CGFloat = 17
    static let countTopFont: CGFloat = 20    // 空态 / 强调场景用的大号数字
    static let aboutIcon: CGFloat = 76
    static let aboutIconRadius: CGFloat = 17
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
                    .fill(Color.pIconBg)
                    .overlay(
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(Color.pLabel)
                    )
            }
        }
        .frame(width: Metrics.aboutIcon, height: Metrics.aboutIcon)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.aboutIconRadius, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 6, y: 3)
    }
}

// ── 图标盒：22pt 淡蓝圆角方块 ──
struct IconBox: View {
    let symbol: String
    var warn = false

    var body: some View {
        RoundedRectangle(cornerRadius: Metrics.iconBoxRadius, style: .continuous)
            .fill(warn ? Color.pWarnBg : Color.pIconBg)
            .frame(width: Metrics.iconBox, height: Metrics.iconBox)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(warn ? Color.pWarnIc : Color.pLabel)
            )
    }
}

// ── 自定义开关：42×24，滑块 19pt ──
struct GlowToggle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            Capsule()
                .fill(configuration.isOn ? Color.pAccent : Color.pTrack)
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

// ── 自绘滑杆：轨道定宽 128pt，命中区 26pt ──
// 手势不认 SwiftUI 的 .disabled（那只置灰原生控件），自己读一次 isEnabled。
struct GlowSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
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
                Capsule().fill(Color.pTrack)
                    .frame(width: w, height: Metrics.sliderTrack)
                Capsule().fill(Color.pAccent)
                    .frame(width: max(0, w * pct), height: Metrics.sliderTrack)
                Circle().fill(.white)
                    .frame(width: Metrics.sliderKnob, height: Metrics.sliderKnob)
                    .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
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
        .frame(width: Metrics.sliderWidth, height: Metrics.sliderHeight)
    }
}

// ── 档位网格：3×N 铺开 ──
// 值域不等差（5/10/15/30/60/120），铺开让人直接选；每格都是可点目标，命中区 32pt。
struct ChoiceGrid: View {
    let items: [String]
    @Binding var index: Int
    /// 置灰态的配色分支。不能靠外层 .opacity(0.34)：透明度不保住格子内部的前后景
    /// 对比度，蓝底白字的格子会变成「浅蓝底 + 几乎透明的白字」。
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: Metrics.chipGap) {
            ForEach(items.indices, id: \.self) { i in
                let on = index == i
                // 禁用态不区分选中 / 未选中，六格一律同色：换个色会被当成「另一种状态」。
                let fill: Color = isEnabled ? (on ? Color.pAccent : Color.pChipBg) : Color.pSep
                let fg: Color = isEnabled ? (on ? Color.pAccFg : Color.pMuted)
                                         : Color.pMuted.opacity(0.75)
                let stroke: Color = (isEnabled && !on) ? Color.pEdge : .clear
                let weight: Font.Weight = (isEnabled && on) ? .semibold : .regular
                Button { index = i } label: {
                    Text(items[i])
                        .font(.system(size: 11.5, weight: weight))
                        .monospacedDigit()
                        .foregroundStyle(fg)
                        .frame(maxWidth: .infinity)
                        .frame(height: Metrics.chipMinHeight)
                        .background(RoundedRectangle(cornerRadius: Metrics.chipRadius,
                                                     style: .continuous).fill(fill))
                        .overlay(RoundedRectangle(cornerRadius: Metrics.chipRadius,
                                                  style: .continuous).stroke(stroke, lineWidth: 1))
                        // 必须显式 contentShape，否则命中区只按渲染出的文字算，padding 点不动。
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement()
                // .buttonStyle(.plain) 的自绘 Button 默认不进 AX 树，必须显式合成。
                .accessibilityElement()
                .accessibilityLabel(Text(items[i]))
                .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
                .accessibilityValue(Text(isEnabled ? "已选择" : "不可用"))
            }
        }
        .frame(height: Metrics.chipMinHeight)
    }
}

/// 3×2 档位网格（两行）。
struct ChoiceGrid3x2: View {
    let items: [String]
    @Binding var index: Int

    var body: some View {
        VStack(spacing: Metrics.chipGap) {
            ForEach(0..<2, id: \.self) { row in
                ChoiceGrid(items: Array(items[row * 3..<min(row * 3 + 3, items.count)]),
                           index: Binding(
                            // getter 必须给行内局部索引：用全局 index 会让两行同时各高亮一格。
                            get: { index - row * 3 },
                            set: { index = row * 3 + $0 }))
            }
        }
    }
}

// ── 分段控件：模式用，3 格等分 ──
struct GlowSegmented: View {
    let items: [String]
    @Binding var index: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(items.indices, id: \.self) { i in
                let on = index == i
                let fill: Color = on ? Color.pAccent : .clear
                let fg: Color = on ? Color.pAccFg : Color.pMuted
                Button { index = i } label: {
                    Text(items[i])
                        .font(.system(size: 11.5, weight: on ? .semibold : .regular))
                        .foregroundStyle(fg)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(fill))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement()
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.pSegBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.pEdge, lineWidth: 1)
        )
    }
}

// ── 磁贴：标签 + 控件，内容整体垂直居中 ──
struct Tile<C: View>: View {
    let symbol: String
    let title: String
    var hint: String? = nil
    /// 置灰而非隐藏
    var disabled = false
    @ViewBuilder var control: () -> C

    var body: some View {
        VStack(spacing: Metrics.tileInnerGap) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: Metrics.tileIcon, weight: .regular))
                    .foregroundStyle(Color.pLabel)
                    .frame(width: Metrics.tileIcon, height: Metrics.tileIcon)
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.pMuted)
                if let hint {
                    Text(hint)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.pMuted.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            // 置灰只调暗标签，不整体降 opacity：整体降会把控件里的「蓝底白字」一起冲淡。
            .opacity(disabled ? 0.55 : 1)
            control()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Metrics.tilePaddingH)
        .padding(.top, Metrics.tilePaddingV)
        .padding(.bottom, Metrics.tilePaddingB)
        .background(
            RoundedRectangle(cornerRadius: Metrics.tileRadius, style: .continuous)
                .fill(Color.pCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.tileRadius, style: .continuous)
                .stroke(Color.pEdge, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 1, y: 0)
    }
}

// ── 顶部 TAB ──
struct TabBar: View {
    let items: [String]
    @Binding var index: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(items.indices, id: \.self) { i in
                let on = index == i
                let fill: Color = on ? Color.pCard : .clear
                let fg: Color = on ? Color.pAccent : Color.pMuted
                let shadow: Double = on ? 0.10 : 0
                Button { index = i } label: {
                    Text(items[i])
                        .font(.system(size: 12.5, weight: on ? .semibold : .regular))
                        .foregroundStyle(fg)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(fill))
                        .shadow(color: .black.opacity(shadow), radius: 1, y: 0)
                        // 同上：没 contentShape 时只有文字可点
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement()
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.pTabBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.pSep, lineWidth: 1)
        )
    }
}

// ── 状态条：圆点 + 文字双编码，不能只用颜色传递信息 ──
struct StatusBar: View {
    let text: String
    var meta: [String] = []
    var warn = false

    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(warn ? Color.pWarn : Color.pAccent)
                .frame(width: 7, height: 7)
                .shadow(color: (warn ? Color.pWarn : Color.pAccent).opacity(0.55), radius: 3.5)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Color.pFg)
            Spacer(minLength: 0)
            ForEach(meta.indices, id: \.self) { i in
                if i > 0 {
                    Text("·").foregroundStyle(Color.pMuted)
                }
                Text(meta[i])
                    .font(mono(11))
                    .monospacedDigit()
                    .foregroundStyle(Color.pMuted)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.pCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.pEdge, lineWidth: 1)
        )
    }
}

// ── 紧凑卡：设一次就不动的项走这里，不占磁贴 ──
struct CompactCard<C: View>: View {
    @ViewBuilder var content: () -> C

    var body: some View {
        VStack(spacing: 0) { content() }
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.pCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Color.pEdge, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

struct CompactRow<C: View>: View {
    let symbol: String
    let title: String
    var sub: String? = nil
    var warn = false
    @ViewBuilder var trailing: () -> C

    var body: some View {
        HStack(spacing: Metrics.rowGap) {
            IconBox(symbol: symbol, warn: warn)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.pFg)
                if let sub {
                    Text(sub)
                        .font(mono(11))
                        .foregroundStyle(Color.pMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, Metrics.tilePaddingH)
        .padding(.vertical, 10)
        .frame(minHeight: 40)
        .background(Color.pSep, alignment: .bottom)
    }
}

// ── 按钮 ──
struct GlowButton: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: primary ? .semibold : .regular))
            .foregroundStyle(primary ? Color.pAccFg : Color.pAccent)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(primary ? Color.pAccent : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(primary ? .clear : Color.black.opacity(0.10), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

// ── 节标题：靠字重 + 蓝色区分 ──
// 不加 tracking：中文没有大写，tracking 会让标题散开。
struct SectionHead: View {
    let t: String
    var badge: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text(t)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.pLabel)
            if let badge {
                Text(badge)
                    .font(mono(10))
                    .foregroundStyle(Color.pMuted)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(Color.pSep, lineWidth: 1)
                    )
            }
        }
        .padding(.horizontal, 2)
    }
}