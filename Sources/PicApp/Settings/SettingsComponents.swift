import SwiftUI
import PicCore

// 设置窗组件层 —— 2026-10-04 重设计。与设计稿 `.planning/design/ui-rotation-a.html` 一一对应，
// 数值（尺寸/间距/圆角/字号）全部照抄，不自由发挥。
//
// 改动摘要（对照旧版）：
//   ① 配色 B1 深海 → 晨雾浅色（底 #F4F5F7 / 强调 #0A6CFF）
//   ② 布局 双列 → 顶部 TAB（播放 / 转码 / 关于）+ 2×2 磁贴网格
//   ③ Tile 发光瓷砖 → 22pt 淡蓝图标盒（.icbox，无阴影）
//   ④ 步进器 → 3×2 档位网格（六档铺开，等差步进配不等差值域是旧设计最大问题）
//   ⑤ 副文不透明度 0.5/0.6 → 实色 #5C6065（0.5 不透明度在浅底上对比度不达 4.5:1）
//   ⑥ 滑杆命中区 18 → 26pt，步进器箭头 → 整格可点
//   ⑦ 节标题去 tracking（中文没有大写，tracking 会让标题散开）
//
// 字体一律系统默认（用户拍板，不打包字体文件）：等宽走 `mono(_:_)` 的
// `.system(design: .monospaced)`，单一入口留给未来换字体。

// ── 配色令牌（晨雾浅色，照抄设计稿 .win 令牌块）──
extension Color {
    /// 窗底 #F4F5F7
    static let pBg      = Color(red: 0xF4/255, green: 0xF5/255, blue: 0xF7/255)
    /// 主文字 #1D1D1F
    static let pFg      = Color(red: 0x1D/255, green: 0x1D/255, blue: 0x1F/255)
    /// 标题栏文字 #3A3D42
    static let pTitle   = Color(red: 0x3A/255, green: 0x3D/255, blue: 0x42/255)
    /// 强调 #0A6CFF —— 唯一强调色，选中态 / 主按钮 / 焦点
    static let pAccent  = Color(red: 0x0A/255, green: 0x6C/255, blue: 0xFF/255)
    /// 强调色上的文字 #FFFFFF
    static let pAccFg   = Color.white
    /// 副文字 #5C6065 —— 对比度 ≥4.5:1（旧版 0.5 不透明度不达标）
    static let pMuted   = Color(red: 0x5C/255, green: 0x60/255, blue: 0x65/255)
    /// 分隔线 #ECEEF1
    static let pSep     = Color(red: 0xEC/255, green: 0xEE/255, blue: 0xF1/255)
    /// 卡片描边 rgba(0,0,0,.07)
    static let pEdge    = Color.black.opacity(0.07)
    /// 卡片底 #FFFFFF
    static let pCard    = Color.white
    /// 档位格底 #F7F8FA
    static let pChipBg  = Color(red: 0xF7/255, green: 0xF8/255, blue: 0xFA/255)
    /// 滑杆轨道 / 开关关闭态 #D9DDE2
    static let pTrack   = Color(red: 0xD9/255, green: 0xDD/255, blue: 0xE2/255)
    /// TAB 条底 #E9EBEF
    static let pTabBg   = Color(red: 0xE9/255, green: 0xEB/255, blue: 0xEF/255)
    /// 分段控件底 #EDEFF2
    static let pSegBg   = Color(red: 0xED/255, green: 0xEF/255, blue: 0xF2/255)
    /// 节标题蓝 #0B5BD6（比强调色深一档，12pt 小字需要更高对比）
    static let pLabel   = Color(red: 0x0B/255, green: 0x5B/255, blue: 0xD6/255)
    /// 图标盒底 #E6EFFF
    static let pIconBg  = Color(red: 0xE6/255, green: 0xEF/255, blue: 0xFF/255)
    /// 警告（空态专用）#E8A33D
    static let pWarn    = Color(red: 0xE8/255, green: 0xA3/255, blue: 0x3D/255)
    /// 警告图标盒底 #FDF0D8
    static let pWarnBg  = Color(red: 0xFD/255, green: 0xF0/255, blue: 0xD8/255)
    /// 警告文字 #B0740F
    static let pWarnFg  = Color(red: 0xB0/255, green: 0x74/255, blue: 0x0F/255)
    /// 警告图标盒内的字 #8A5E12
    static let pWarnIc  = Color(red: 0x8A/255, green: 0x5E/255, blue: 0x12/255)
}

/// 等宽字体助手：数值/副标签/版本号/命令。单一入口，防未来换字体时散改。
func mono(_ size: CGFloat, _ w: Font.Weight = .regular) -> Font {
    .system(size: size, weight: w, design: .monospaced)
}

// ── 间距/圆角常量（照抄设计稿，避免视图里散写数字）──
enum Metrics {
    static let windowWidth: CGFloat = 780
    static let aboutMinHeight: CGFloat = 340
    static let winPadding: CGFloat = 16      // .wbody padding
    static let blockGap: CGFloat = 14        // .wbody gap / .grid gap
    static let gridGap: CGFloat = 10         // .grid gap（磁贴之间）
    static let tilePaddingV: CGFloat = 11    // .t padding-top
    static let tilePaddingB: CGFloat = 12    // .t padding-bottom
    static let tilePaddingH: CGFloat = 13    // .t padding-left/right
    static let tileRadius: CGFloat = 11      // .t border-radius
    static let tileInnerGap: CGFloat = 9     // .t gap（标签↔控件）
    static let tileIcon: CGFloat = 15        // .t .lab .ic
    static let chipGap: CGFloat = 5          // .chips gap
    static let chipRadius: CGFloat = 7       // .chips span border-radius
    static let chipMinHeight: CGFloat = 32   // .chips span min-height（命中区 ≥24）
    static let sliderWidth: CGFloat = 128    // .sld flex-basis（定宽，两条轨道右端才对齐）
    static let sliderHeight: CGFloat = 26    // .sld height（命中区 ≥24）
    static let sliderTrack: CGFloat = 5      // .sld .track height
    static let sliderKnob: CGFloat = 15      // .sld .knob
    static let valueWidth: CGFloat = 46      // .val flex-basis
    static let toggleW: CGFloat = 42         // .tog
    static let toggleH: CGFloat = 24         // .tog
    static let toggleKnob: CGFloat = 19      // .tog::after
    static let rowGap: CGFloat = 11          // .crow gap
    static let iconBox: CGFloat = 22         // .icbox
    static let iconBoxRadius: CGFloat = 6    // .icbox border-radius
    static let countFont: CGFloat = 17       // .count
    static let countTopFont: CGFloat = 20    // 旧版大数字（保留给空态/强调场景）
    static let aboutIcon: CGFloat = 76       // .appicon
    static let aboutIconRadius: CGFloat = 17 // .appicon border-radius
}

// ── 图标盒（.icbox）：22pt 淡蓝圆角方块，替代旧版 26pt 发光瓷砖 ──
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

// ── 自定义开关（.tog）：42×24，滑块 19pt ──
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
    }
}

// ── 自绘滑杆（.sld）：轨道定宽 128pt，命中区 26pt ──
// ⚠️ 自绘手势**不认** SwiftUI 的 disabled —— `.disabled(true)` 只置灰原生控件。
// 这里自己读一次 isEnabled（沿用旧版做法，见 UI-SPEC §10）。
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

// ── 档位网格（.chips）：3×N 铺开，替掉旧的细长步进器 ──
// 旧版用等差步进器选不等差值域（5/10/15/30/60/120），到 2 小时要按 6 次；
// 六档封闭值域应铺开让人直接选。每格都是可点目标，命中区 32pt。
struct ChoiceGrid: View {
    let items: [String]
    @Binding var index: Int
    var columns = 3

    var body: some View {
        HStack(spacing: Metrics.chipGap) {
            ForEach(items.indices, id: \.self) { i in
                let on = index == i
                let fill: Color = on ? Color.pAccent : Color.pChipBg
                let fg: Color = on ? Color.pAccFg : Color.pMuted
                let stroke: Color = on ? .clear : Color.pEdge
                Button { index = i } label: {
                    Text(items[i])
                        .font(.system(size: 11.5, weight: on ? .semibold : .regular))
                        .monospacedDigit()
                        .foregroundStyle(fg)
                        .frame(maxWidth: .infinity)
                        .frame(height: Metrics.chipMinHeight)
                        .background(RoundedRectangle(cornerRadius: Metrics.chipRadius,
                                                     style: .continuous).fill(fill))
                        .overlay(RoundedRectangle(cornerRadius: Metrics.chipRadius,
                                                  style: .continuous).stroke(stroke, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: Metrics.chipMinHeight)
    }
}

/// 3×2 档位网格（两行）。旧版步进器 → 这个。
struct ChoiceGrid3x2: View {
    let items: [String]
    @Binding var index: Int

    var body: some View {
        VStack(spacing: Metrics.chipGap) {
            ForEach(0..<2, id: \.self) { row in
                ChoiceGrid(items: Array(items[row * 3..<min(row * 3 + 3, items.count)]),
                           index: Binding(
                            get: { index },
                            set: { index = row * 3 + $0 }),
                           columns: 3)
            }
        }
    }
}

// ── 分段控件（.seg）：模式用，3 格等分 ──
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
                }
                .buttonStyle(.plain)
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

// ── 磁贴（.t）：标签 + 控件，内容整体垂直居中 ──
// ⚠️ 用 flex 等价的 Spacer 对称撑高，不要用 grid-template-rows + align-self：
// 后者在被拉伸到等高时多余高度会被 1fr 行吃掉，居中失效（HTML 版实测 padT 35.1 / padB 11.7）。
struct Tile<C: View>: View {
    let symbol: String
    let title: String
    var hint: String? = nil
    /// 置灰：整卡降到 34%（UI-SPEC §6 置灰而非隐藏）
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
        .opacity(disabled ? 0.34 : 1)
    }
}

// ── 顶部 TAB（.tabs）──
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
                }
                .buttonStyle(.plain)
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

// ── 状态条（.statusbar）：圆点 + 文字双编码（skill ux 域：不能只用颜色传递信息）──
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

// ── 紧凑卡（.compact + .crow）：设一次就不动的项走这里，不占磁贴 ──
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

// ── 按钮（.btn）──
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

// ── 节标题（.sect）：靠字重 + 蓝色区分，不加 tracking ──
// ⚠️ 中文没有大写，旧版 tracking(1.3) 会让中文标题散开像标签纸。
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