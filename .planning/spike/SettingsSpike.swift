import SwiftUI
import AppKit

// ── 配色令牌（照抄 UI-SPEC §3）──────────────────────────
extension Color {
    static let pBg      = Color(red: 0x0A/255, green: 0x18/255, blue: 0x26/255)
    static let pFg      = Color(red: 0xDC/255, green: 0xE8/255, blue: 0xF4/255)
    static let pAccent  = Color(red: 0x4C/255, green: 0xC4/255, blue: 0xF5/255)
    static let pAccFg   = Color(red: 0x04/255, green: 0x20/255, blue: 0x2E/255)
    static let pCard    = Color(red: 13/255,  green: 32/255,  blue: 52/255).opacity(0.92)
    static let pSep     = Color(red: 90/255,  green: 170/255, blue: 240/255).opacity(0.22)  // ↑ 0.16→0.22
    static let pEdge    = Color(red: 90/255,  green: 190/255, blue: 255/255).opacity(0.32)
    static let pGlow    = Color(red: 76/255,  green: 196/255, blue: 245/255).opacity(0.32)
    static let pWarn    = Color(red: 0xF5/255, green: 0xB5/255, blue: 0x44/255)
    static let pWarnGlow = Color(red: 245/255, green: 181/255, blue: 68/255).opacity(0.30)
    static let pDim     = Color(red: 120/255, green: 180/255, blue: 240/255)
}
func mono(_ size: CGFloat, _ w: Font.Weight = .regular) -> Font {
    .system(size: size, weight: w, design: .monospaced)
}

// ── 图标瓷砖（发光加强：双阴影 + 环）────────────────────
struct Tile: View {
    let symbol: String
    var warn = false
    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(LinearGradient(
                colors: warn ? [Color(red:0xF7/255,green:0xC4/255,blue:0x63/255),
                                Color(red:0xC4/255,green:0x7A/255,blue:0x10/255)]
                              : [Color(red:0x5A/255,green:0xC8/255,blue:0xFA/255),
                                 Color(red:0x16/255,green:0x68/255,blue:0xB8/255)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 26, height: 26)
            .overlay(RoundedRectangle(cornerRadius: 6)
                .stroke(warn ? Color.pWarn.opacity(0.55) : Color.pEdge, lineWidth: 1))
            .shadow(color: warn ? Color.pWarnGlow : Color.pGlow, radius: 4)          // 近层
            .shadow(color: warn ? Color.pWarnGlow : Color.pGlow, radius: 11)         // 远层
            .overlay(Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white))
    }
}

// ── 自定义开关 ───────────────────────────────────────
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

// ── 自绘滑杆 ─────────────────────────────────────────
struct GlowSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
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
                dragging = true
                let p = min(max(0, g.location.x / w), 1)
                value = range.lowerBound + p * (range.upperBound - range.lowerBound)
            }.onEnded { _ in dragging = false })
        }
        .frame(width: 92, height: 18)
    }
}

// ── 自绘分段控件 ─────────────────────────────────────
struct GlowSegmented: View {
    let items: [String]
    @Binding var index: Int
    var body: some View {
        HStack(spacing: 2) {
            ForEach(items.indices, id: \.self) { i in
                Button { index = i } label: {
                    Text(items[i])
                        .font(mono(11, index == i ? .semibold : .regular))
                        .foregroundStyle(index == i ? Color.pAccFg : Color.pFg.opacity(0.6))
                        .padding(.horizontal, 9).padding(.vertical, 3.5)
                        .background(RoundedRectangle(cornerRadius: 5)
                            .fill(index == i ? Color.pAccent : Color.clear)
                            .shadow(color: index == i ? Color.pGlow : Color.clear, radius: 7))
                }.buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color(red:90/255,green:190/255,blue:255/255).opacity(0.09)))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.pEdge, lineWidth: 1))
    }
}

// ── 步进器 ───────────────────────────────────────────
struct GlowStepper: View {
    @Binding var index: Int
    let values: [Int]
    var body: some View {
        HStack(spacing: 0) {
            stepBtn("chevron.up", -1)
            Text(values[index] >= 60 ? "\(values[index]/60) 小时" : "\(values[index]) 分钟")
                .font(mono(11)).foregroundStyle(Color.pAccent)
                .frame(minWidth: 68).padding(.vertical, 4)
                .background(Color(red:90/255,green:190/255,blue:255/255).opacity(0.05))
                .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.pSep), alignment: .top)
                .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.pSep), alignment: .bottom)
            stepBtn("chevron.down", 1)
        }
    }
    func stepBtn(_ s: String, _ d: Int) -> some View {
        Button { index = max(0, min(values.count-1, index + d)) } label: {
            Image(systemName: s).font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color.pAccent).frame(width: 22, height: 25)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.pSep, lineWidth: 1))
        }.buttonStyle(.plain)
    }
}

// ── 行 / 卡片 ────────────────────────────────────────
struct Row<C: View>: View {
    let symbol: String
    let title: String
    var sub: String? = nil
    var warn = false
    var hairline = true
    @ViewBuilder var control: () -> C
    var body: some View {
        HStack(spacing: 11) {
            Tile(symbol: symbol, warn: warn)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12.5)).foregroundStyle(Color.pFg)
                if let sub { Text(sub).font(mono(10.5)).foregroundStyle(Color.pFg.opacity(0.6)) }
            }
            Spacer(minLength: 11)
            control()
        }
        .padding(.horizontal, 13).frame(minHeight: 42)      // ↓ 48→42
        .overlay(alignment: .bottom) {
            if hairline { Rectangle().frame(height: 1).foregroundStyle(Color.pSep) }
        }
    }
}

struct SectionHead: View {
    let t: String
    var body: some View {
        Text(t.uppercased())
            .font(mono(10.5, .medium)).tracking(1.3)
            .foregroundStyle(Color(red:120/255,green:200/255,blue:255/255).opacity(0.62))
            .padding(.horizontal, 4).padding(.bottom, 6)
    }
}

// 去掉 clipShape —— 它把瓷砖的外发光裁掉了
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

// ── 主视图 ───────────────────────────────────────────
struct SettingsSpike: View {
    @State private var mode = 1
    @State private var rot = 2
    @State private var speed = 1.0
    @State private var volume = 60.0
    @State private var sound = true
    @State private var battery = false
    @State private var login = false
    @State private var count = 12
    @State private var breathe = false

    let rotVals = [5, 10, 15, 30, 60, 120]

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // ── 左列 ──
            VStack(alignment: .leading, spacing: 12) {
                SectionHead(t: "壁纸来源")
                Card {
                    Row(symbol: "folder.fill", title: "文件夹", sub: "~/Movies/Wallpapers") {
                        Button("选择…") {}.buttonStyle(GlowButton())
                    }
                    HStack(spacing: 11) {
                        ZStack {
                            if count == 0 {
                                Tile(symbol: "exclamationmark", warn: true)
                            } else {
                                Circle().fill(Color.pAccent).frame(width: 6, height: 6)
                                    .shadow(color: Color.pGlow, radius: 4)
                                    .frame(width: 26)
                            }
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(count)").font(mono(20, .semibold))
                                .foregroundStyle(count == 0 ? Color.pWarn : Color.pAccent)
                                .shadow(color: count == 0 ? Color.pWarnGlow : Color.pGlow, radius: 7)
                            Text("个可用视频").font(mono(11.5)).foregroundStyle(Color.pFg.opacity(0.6))
                        }
                        Spacer(minLength: 11)
                        Button("重新扫描") { count = count == 12 ? 37 : 12 }.buttonStyle(GlowButton())
                    }
                    .padding(.horizontal, 13).frame(minHeight: 42)
                }
                Hint(t: "递归扫子目录 · 只认 MP4 / MOV / M4V")

                SectionHead(t: "播放").padding(.top, 4)
                Card {
                    Row(symbol: "repeat", title: "模式") {
                        GlowSegmented(items: ["单循环", "列表循环", "随机"], index: $mode)
                    }
                    Row(symbol: "timer", title: "轮换") {
                        GlowStepper(index: $rot, values: rotVals)
                    }.opacity(mode == 0 ? 0.34 : 1)
                    Row(symbol: "gauge.with.dots.needle.67percent", title: "速度", sub: "音高不变") {
                        HStack(spacing: 9) {
                            GlowSlider(value: $speed, range: 0.5...2)
                            Text(String(format: "%.2f×", speed)).font(mono(11))
                                .foregroundStyle(Color.pFg.opacity(0.75)).frame(width: 42, alignment: .trailing)
                        }
                    }
                    Row(symbol: "speaker.wave.2.fill", title: "声音", hairline: false) {
                        HStack(spacing: 9) {
                            GlowSlider(value: $volume, range: 0...100).opacity(sound ? 1 : 0.34)
                            Text("\(Int(volume))%").font(mono(11))
                                .foregroundStyle(Color.pFg.opacity(0.75)).frame(width: 42, alignment: .trailing)
                            Toggle("", isOn: $sound).toggleStyle(GlowToggle()).labelsHidden()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // ── 右列 ──
            VStack(alignment: .leading, spacing: 12) {
                SectionHead(t: "电源与系统")
                Card {
                    Row(symbol: "battery.75", title: "电池时播放", sub: "默认关") {
                        Toggle("", isOn: $battery).toggleStyle(GlowToggle()).labelsHidden()
                    }
                    Row(symbol: "power", title: "开机自启", hairline: false) {
                        Toggle("", isOn: $login).toggleStyle(GlowToggle()).labelsHidden()
                    }
                }
                Hint(t: "全屏 / 锁屏 / 熄屏 / 睡眠时自动暂停")

                SectionHead(t: "维护").padding(.top, 4)
                Card {
                    Row(symbol: "arrow.left.arrow.right", title: "转码", sub: "MKV / AVI → MP4", hairline: false) {
                        Button("打开…") {}.buttonStyle(GlowButton(primary: true))
                    }
                }

                // ── 运行状态：填掉右列空白，且本身是真需求 ──
                SectionHead(t: "运行状态").padding(.top, 4)
                Card {
                    Row(symbol: "pause.circle.fill", title: "已暂停", sub: "检测到全屏应用", hairline: true) {
                        Text("").frame(width: 0)
                    }
                    Row(symbol: "checkmark.seal.fill", title: "ffmpeg", sub: "9.0.2 · 可用", hairline: false) {
                        Text("").frame(width: 0)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(width: 780)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            ZStack {
                Color.pBg
                LinearGradient(colors: [Color(red:76/255,green:196/255,blue:245/255).opacity(breathe ? 0.14 : 0.07), Color.clear],
                               startPoint: .top, endPoint: .center)
                RadialGradient(colors: [Color(red:30/255,green:120/255,blue:220/255).opacity(breathe ? 0.30 : 0.18), Color.clear],
                               center: .init(x: 0.88, y: 0.96), startRadius: 0, endRadius: 300)
            }
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 10).repeatForever(autoreverses: true)) { breathe = true }
        }
    }
}

// ── 按钮样式 ─────────────────────────────────────────
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
