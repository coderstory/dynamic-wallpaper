import SwiftUI

// 设置窗磁贴层：网格容器、磁贴、磁贴内的行、刻度选择器、状态胶囊、告警条、眉标。
// 视觉与尺寸照抄 `.planning/design/prototype.html` 的 .grid / .tile / .row-item / .ticks / .status / .strip / .eyebrow。

// ── 磁贴外观的唯一定义 ──
// SettingsTile 与设置窗里那个「正在播放」hero 磁贴都用它 —— hero 是磁贴，不是另一种东西，
// 两处各写一份圆角/投影会在改设计时漏掉一处。
struct TileSurface: ViewModifier {
    var wide = false

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity)
            .padding(Metrics.tilePadding)
            .background(
                RoundedRectangle(cornerRadius: Metrics.tileRadius, style: .continuous)
                    .fill(Color.pSurface)
            )
            // 不描边：分层只靠下面两层投影，补描边会毁掉柔和观感。
            .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
            .shadow(color: .black.opacity(0.10), radius: 10, y: 6)
            .gridCellColumns(wide ? 2 : 1)
    }
}

extension View {
    func tileSurface(wide: Bool = false) -> some View { modifier(TileSurface(wide: wide)) }
}

// ── 磁贴容器 ──
struct SettingsTile<Content: View, Tail: View>: View {
    var icon: String? = nil
    let title: String
    var wide = false
    @ViewBuilder var tail: () -> Tail
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: Metrics.tileGap) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.pInk3)
                }
                Text(title)
                    .font(display(12.5))
                    .foregroundStyle(Color.pInk)
                Spacer(minLength: 0)
                tail()
            }
            content()
        }
        .tileSurface(wide: wide)
    }
}

// tail 排在 content 前 —— 少了这个重载，无尾部的磁贴写 `{ content }` 会被绑到 tail 上并报错。
extension SettingsTile where Tail == EmptyView {
    init(icon: String? = nil, title: String, wide: Bool = false,
         @ViewBuilder content: @escaping () -> Content) {
        self.init(icon: icon, title: title, wide: wide, tail: { EmptyView() }, content: content)
    }
}

// ── 2 列磁贴网格。跨列由 SettingsTile.wide 自己声明，网格不认内容 ──
struct TileGrid<Content: View>: View {
    @ViewBuilder var content: () -> Content

    private let columns = [
        GridItem(.flexible(), spacing: Metrics.gridGap),
        GridItem(.flexible(), spacing: Metrics.gridGap),
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: Metrics.gridGap) {
            content()
        }
    }
}

// ── 磁贴内的一行 ──
struct TileRow<Content: View>: View {
    let title: String
    var sub: String? = nil
    /// 磁贴里的首个行不该有线：那条线是给「行与行之间」用的。
    var divider = true
    @ViewBuilder var trailing: () -> Content

    var body: some View {
        HStack(spacing: Metrics.rowGap) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(display(12.5, .medium))
                    .foregroundStyle(Color.pInk)
                if let sub {
                    Text(sub)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.pInk3)
                }
            }
            Spacer(minLength: 0)
            trailing()
        }
        .frame(minHeight: Metrics.rowMinHeight)
        // 分隔线走 overlay(.top)：画进布局会多占 1pt 高度，与调用方的行距叠成双份。
        .overlay(alignment: .top) {
            Rectangle()
                .fill(divider ? Color.pDivider : .clear)
                .frame(height: 1)
        }
    }
}

// ── 刻度选择器：轮换间隔 ──
struct TickSelector: View {
    let items: [String]
    @Binding var index: Int

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(items.indices, id: \.self) { i in
                let on = index == i
                Button { index = i } label: {
                    VStack(spacing: 5) {
                        Capsule()
                            .fill(on ? Color.pBrand : Color.pSurface3)
                            .frame(height: on ? 11 : 6)
                            .frame(minWidth: Metrics.tickMinWidth, maxWidth: .infinity)
                        Text(items[i])
                            .font(mono(9.5, on ? .semibold : .regular))
                            .foregroundStyle(on ? Color.pInk : Color.pInk3)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement()
                .accessibilityLabel(Text(items[i]))
                .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
            }
        }
        // 选中刻度从 6 长到 11：不写这行，高度突变会把整行往下顶再弹回。
        .animation(.easeInOut(duration: 0.12), value: index)
    }
}

// ── 标题栏状态胶囊 ──
// 颜色不单独承载语义：圆点只是扫读锚点，两段文字才是确定含义 —— 别把它简化成只剩一个圆点。
struct StatusPill: View {
    enum Kind { case playing, hold, blocked }

    let kind: Kind
    let lead: String
    let rest: String

    private var tint: Color {
        switch kind {
        case .playing: Color.pOk
        case .hold:    Color.pHold
        case .blocked: Color.pBad
        }
    }

    var body: some View {
        HStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.22))
                    .frame(width: 14, height: 14)
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
            }
            HStack(spacing: 3) {
                Text(lead)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color.pInk)
                Text(rest)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.pInk2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.pSurface2))
    }
}

// ── 告警条：视觉上是一条，不是磁贴 ──
struct WarningStrip<Action: View>: View {
    let text: String
    @ViewBuilder var action: () -> Action

    var body: some View {
        HStack(spacing: 11) {
            Circle()
                .fill(Color.pHold)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Color.pInk)
            Spacer(minLength: 0)
            action()
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 15)
        .background(
            RoundedRectangle(cornerRadius: Metrics.tileRadius, style: .continuous)
                .fill(Color.pHoldSoft)
        )
    }
}

// ── 分区眉标 ──
struct Eyebrow: View {
    let text: String
    var badge: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            Text(text)
                .font(display(12, .semibold))
                .foregroundStyle(Color.pInk)
            if let badge {
                Text(badge)
                    .font(mono(9.5))
                    .foregroundStyle(Color.pInk2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.pSurface2))
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 4)
    }
}
