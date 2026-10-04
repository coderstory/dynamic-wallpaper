import SwiftUI
import PicCore

// 设置窗组件层。只做三处合同覆盖：① pSep 的 opacity 用全局稿的 0.16；② Row 的 tileGap
// 用 12；③ 读数字号统一 11.5 / 节标题统一 semibold(600)。
// 字体一律系统默认（用户拍板，不打包字体文件）：等宽文本走 `mono(_:_)` 的
// `.system(design: .monospaced)`，单一入口留给未来换字体。

// ── 配色令牌（B1 深海）──
extension Color {
    static let pBg       = Color(red: 0x0A/255, green: 0x18/255, blue: 0x26/255)
    static let pFg       = Color(red: 0xDC/255, green: 0xE8/255, blue: 0xF4/255)
    static let pAccent   = Color(red: 0x4C/255, green: 0xC4/255, blue: 0xF5/255)
    static let pAccFg    = Color(red: 0x04/255, green: 0x20/255, blue: 0x2E/255)
    static let pCard     = Color(red: 13/255,  green: 32/255,  blue: 52/255).opacity(0.92)
    static let pSep      = Color(red: 90/255,  green: 170/255, blue: 240/255).opacity(0.16)
    static let pEdge     = Color(red: 90/255,  green: 190/255, blue: 255/255).opacity(0.32)
    static let pGlow     = Color(red: 76/255,  green: 196/255, blue: 245/255).opacity(0.32)
    static let pWarn     = Color(red: 0xF5/255, green: 0xB5/255, blue: 0x44/255)
    static let pWarnGlow = Color(red: 245/255, green: 181/255, blue: 68/255).opacity(0.30)
    static let pDim      = Color(red: 120/255, green: 180/255, blue: 240/255)
}

/// 等宽字体助手：数值/副标签/节标题/按钮。单一入口，防未来换字体时散改。
func mono(_ size: CGFloat, _ w: Font.Weight = .regular) -> Font {
    .system(size: size, weight: w, design: .monospaced)
}

// ── 图标瓷砖（双阴影发光）──
struct Tile: View {
    let symbol: String
    var warn = false
    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(LinearGradient(
                colors: warn ? [Color(red: 0xF7/255, green: 0xC4/255, blue: 0x63/255),
                                Color(red: 0xC4/255, green: 0x7A/255, blue: 0x10/255)]
                              : [Color(red: 0x5A/255, green: 0xC8/255, blue: 0xFA/255),
                                 Color(red: 0x16/255, green: 0x68/255, blue: 0xB8/255)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 26, height: 26)
            .overlay(RoundedRectangle(cornerRadius: 6)
                .stroke(warn ? Color.pWarn.opacity(0.55) : Color.pEdge, lineWidth: 1))
            .shadow(color: warn ? Color.pWarnGlow : Color.pGlow, radius: 4)
            .shadow(color: warn ? Color.pWarnGlow : Color.pGlow, radius: 11)
            .overlay(Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white))
    }
}

// ── 自定义开关 ───────────────────────────────────────────────
struct GlowToggle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            RoundedRectangle(cornerRadius: 11.5)
                .fill(configuration.isOn ? Color.pAccent : Color.pDim.opacity(0.16))
                .frame(width: 40, height: 23)
                .shadow(color: configuration.isOn ? Color.pGlow : Color.clear, radius: 8)
                .overlay(
                    Circle().fill(.white).frame(width: 19, height: 19)
                        .shadow(color: .black.opacity(0.4), radius: 1, y: 1)
                        .offset(x: configuration.isOn ? 8.5 : -8.5)
                        .animation(.easeInOut(duration: 0.15), value: configuration.isOn)
                )
        }.buttonStyle(.plain)
    }
}

// ── 自绘滑杆（SDK 27 无 SliderStyle，自造成本已锁定，UI-SPEC §10）──
struct GlowSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    /// 拖动中回调（当场生效，不写盘）；拖动结束回调（persist 恰一次）。
    /// tracer 的接线形态（节流纪律）由 SettingsView 传入。
    var onChanged: (() -> Void)? = nil
    var onEnded: (() -> Void)? = nil
    /// ⚠️ 自绘手势**不认** SwiftUI 的 disabled —— `.disabled(true)` 只置灰原生控件。
    /// 要求是「禁用交互，不是只调透明度」，所以这里自己读一次 isEnabled。
    @Environment(\.isEnabled) private var isEnabled
    @State private var dragging = false
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let pct = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.pDim.opacity(0.18)).frame(height: 4)
                Capsule().fill(Color.pAccent).frame(width: max(0, w * pct), height: 4)
                    .shadow(color: Color.pGlow, radius: dragging ? 9 : 5)
                Circle().fill(.white).frame(width: 14, height: 14)
                    .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                    .shadow(color: Color.pGlow, radius: dragging ? 8 : 3)
                    .offset(x: max(0, min(w - 14, w * pct - 7)))
            }
            .frame(height: 18)
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
        .frame(width: 92, height: 18)
    }
}

// ── 自绘分段控件（`.tint()` 对 macOS 分段控件着色有限，UI-SPEC §10）──
struct GlowSegmented: View {
    let items: [String]
    @Binding var index: Int
    var body: some View {
        HStack(spacing: 2) {
            ForEach(items.indices, id: \.self) { i in
                Button { index = i } label: {
                    Text(items[i])
                        .font(mono(11.5, index == i ? .semibold : .regular))
                        .foregroundStyle(index == i ? Color.pAccFg : Color.pFg.opacity(0.6))
                        .padding(.horizontal, 9).padding(.vertical, 3.5)
                        .background(RoundedRectangle(cornerRadius: 5)
                            .fill(index == i ? Color.pAccent : Color.clear)
                            .shadow(color: index == i ? Color.pGlow : Color.clear, radius: 7))
                }.buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color(red: 90/255, green: 190/255, blue: 255/255).opacity(0.09)))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.pEdge, lineWidth: 1))
    }
}

// ── 步进器 ──
struct GlowStepper: View {
    @Binding var index: Int
    let values: [Int]
    var body: some View {
        HStack(spacing: 0) {
            // 水平排布配左右箭头（◀ 小 ▶ 大）—— 原先 ▲▼ 竖排箭头放在横排里，
            // 「上=更小」反直觉且顶到最大档时点着没反应，被当成坏了。
            stepBtn("chevron.left", -1)
            // 「N 小时 / N 分钟」的换算是 SettingsPresentation 的唯一来源（视图里不出现第二份）。
            Text(SettingsPresentation.rotationLabel(minutes: values[index]))
                .font(mono(11.5)).foregroundStyle(Color.pAccent)
                .frame(minWidth: 68).padding(.vertical, 4)
                .background(Color(red: 90/255, green: 190/255, blue: 255/255).opacity(0.05))
                .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.pSep), alignment: .top)
                .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.pSep), alignment: .bottom)
            stepBtn("chevron.right", 1)
        }
    }
    func stepBtn(_ s: String, _ d: Int) -> some View {
        Button { index = max(0, min(values.count - 1, index + d)) } label: {
            Image(systemName: s).font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color.pAccent).frame(width: 22, height: 25)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.pSep, lineWidth: 1))
        }.buttonStyle(.plain)
    }
}

// ── 行 / 卡片 ──
struct Row<C: View>: View {
    let symbol: String
    let title: String
    var sub: String? = nil
    var warn = false
    var hairline = true
    @ViewBuilder var control: () -> C
    var body: some View {
        HStack(spacing: 12) {
            Tile(symbol: symbol, warn: warn)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12.5)).foregroundStyle(Color.pFg).lineLimit(1)
                if let sub {
                    Text(sub).font(mono(10.5)).foregroundStyle(Color.pFg.opacity(0.6))
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: 12)
            control()
        }
        .padding(.horizontal, 13).frame(minHeight: 42)
        .overlay(alignment: .bottom) {
            if hairline { Rectangle().frame(height: 1).foregroundStyle(Color.pSep) }
        }
    }
}

struct SectionHead: View {
    let t: String
    var body: some View {
        Text(t.uppercased())
            .font(mono(10.5, .semibold)).tracking(1.3)
            .foregroundStyle(Color(red: 120/255, green: 200/255, blue: 255/255).opacity(0.62))
            .padding(.horizontal, 4).padding(.bottom, 6)
    }
}

// ⚠️ 无 clipShape —— 它会把瓷砖的外发光裁掉（UI-SPEC §13 已修的坑 1）
struct Card<C: View>: View {
    @ViewBuilder var content: () -> C
    var body: some View {
        VStack(spacing: 0) { content() }
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.pCard))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.pSep, lineWidth: 1))
    }
}

struct Hint: View {
    let t: String
    var body: some View {
        Text(t).font(mono(10.5)).foregroundStyle(Color.pFg.opacity(0.5))
            .padding(.horizontal, 4)
    }
}

// ── 按钮样式 ──
struct GlowButton: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(mono(11.5, primary ? .semibold : .regular))
            .foregroundStyle(primary ? Color.pAccFg : Color.pAccent)
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 7).fill(primary ? Color.pAccent : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(primary ? Color.clear : Color.pEdge, lineWidth: 1))
            .shadow(color: primary ? Color.pGlow : Color.clear, radius: 8)
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
