import SwiftUI
import PicCore

// 设置窗结构件：卡片外观、卡片、页头、顶栏、侧栏、行、刻度选择器、状态胶囊、告警条。
// 视觉与尺寸照抄 `.planning/design/ui-redesign-v2-shell.html`（v2 shell：平面、描边、无投影）。

extension View {
    // v2 是平面风：白底 + 1pt pLine 描边 + 圆角 14，**无投影**（.cd）。
    func cardSurface() -> some View { modifier(CardSurface()) }
}

/// 液态玻璃是否激活。走环境量而不是 modifier 参数：glass 判断只在根视图读一次
/// `store.liquidGlassEnabled` 往下传，所有消费点（卡片面、顶栏底、侧栏底）零改动；
/// 覆盖范围 = **整窗**——开启时根背景是超薄材质，顶栏/侧栏底让位透明（透出材质），
/// 卡片走 glassEffect；默认 false，任何没挂环境量的视图（如 sheet）自动落在旧渲染路径上。
private struct LiquidGlassActiveKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var liquidGlassActive: Bool {
        get { self[LiquidGlassActiveKey.self] }
        set { self[LiquidGlassActiveKey.self] = newValue }
    }
}

struct CardSurface: ViewModifier {
    @Environment(\.liquidGlassActive) private var glass

    func body(content: Content) -> some View {
        if glass {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Metrics.tilePadding)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Metrics.cardRadius,
                                                            style: .continuous))
        } else {
            // 关闭分支与 v2 平面风原路径逐字节相同：不开玻璃时必须零视觉变化。
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Metrics.tilePadding)
                .background(
                    RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                        .fill(Color.pSurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                        .strokeBorder(Color.pLine, lineWidth: 1)
                )
        }
    }
}

// ── 四区身份色（HTML 的 Z 表）──
// play 复用 brand 四件套；每页用自己区的颜色染页头竖条与侧栏选中态。
struct ZonePalette {
    let base: Color
    let ink: Color
    let text: Color
    let soft: Color
}

func zonePalette(_ page: SettingsPresentation.SettingsPage) -> ZonePalette {
    switch page {
    case .play:    ZonePalette(base: .pBrand, ink: .pBrandInk, text: .pBrandText, soft: .pBrandSoft)
    case .library: ZonePalette(base: .pLib,   ink: .pLibInk,   text: .pLibText,   soft: .pLibSoft)
    case .queue:   ZonePalette(base: .pQueue, ink: .pQueueInk, text: .pQueueText, soft: .pQueueSoft)
    case .general: ZonePalette(base: .pGen,   ink: .pGenInk,   text: .pGenText,   soft: .pGenSoft)
    }
}

/// 侧栏行的 SF Symbol 与 identifier 后缀，随 SettingsPage 加 case 必须编译不过才算对。
private func navSymbol(_ page: SettingsPresentation.SettingsPage) -> String {
    switch page {
    case .play:    "play.circle"
    case .library: "folder"
    case .queue:   "list.bullet.rectangle"
    case .general: "gearshape"
    }
}

private func navIdentifier(_ page: SettingsPresentation.SettingsPage) -> String {
    switch page {
    case .play:    "nav-button-play"
    case .library: "nav-button-library"
    case .queue:   "nav-button-queue"
    case .general: "nav-button-general"
    }
}

// ── 页头：区色竖条 + 页标题 + 副题（.phead）──
struct SettingsPageHead: View {
    let page: SettingsPresentation.SettingsPage

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(zonePalette(page).base)
                    .frame(width: 4, height: 15)
                Text(page.title)
                    .font(display(17))
                    .foregroundStyle(Color.pInk)
            }
            Text(page.caption)
                .font(.system(size: 11))
                .foregroundStyle(Color.pInk3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// ── 卡片：标题行（图标 + 标题 + 尾部）+ 内容（.cd / .ch）──
struct SettingsCard<Content: View, Tail: View>: View {
    var icon: String? = nil
    let title: String
    @ViewBuilder var tail: () -> Tail
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.pInk3)
                }
                Text(title)
                    .font(display(13))
                    .foregroundStyle(Color.pInk)
                Spacer(minLength: 0)
                tail()
            }
            .frame(minHeight: 20)
            content()
        }
        .cardSurface()
    }
}

// tail 排在 content 前 —— 少了这个重载，无尾部的卡片写 `{ content }` 会被绑到 tail 上并报错。
extension SettingsCard where Tail == EmptyView {
    init(icon: String? = nil, title: String,
         @ViewBuilder content: @escaping () -> Content) {
        self.init(icon: icon, title: title, tail: { EmptyView() }, content: content)
    }
}

// ── 2 列卡片网格。只放真正的半宽卡对 ──
// 全宽卡不进网格、直接做 VStack 子节点：gridCellColumns(2) 穿过自定义 ViewModifier /
// 条件内容后会被 LazyVGrid 静默丢掉 —— 症状是全宽 hero 塌成左半列。不赌这个行为。
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

// ── 卡片内的一行 ──
struct TileRow<Content: View>: View {
    let title: String
    var sub: String? = nil
    /// 卡片里的首个行不该有线：那条线是给「行与行之间」用的。
    var divider = true
    @ViewBuilder var trailing: () -> Content

    var body: some View {
        HStack(spacing: Metrics.rowGap) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(display(13, .medium))
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
                            .font(mono(10, on ? .semibold : .regular))
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

// ── 顶栏状态胶囊 ──
// 颜色不单独承载语义：圆点只是扫读锚点，两段文字才是确定含义。
// 底色是白 + pLine 描边：顶栏底色就是 surface2，同色胶囊会隐形。
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
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.pInk)
                Text(rest)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.pInk2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.pSurface)
                .overlay(Capsule().strokeBorder(Color.pLine, lineWidth: 1))
        )
    }
}

// ── 告警条：视觉上是一条，不是卡片 ──
struct WarningStrip<Action: View>: View {
    let text: String
    @ViewBuilder var action: () -> Action

    var body: some View {
        HStack(spacing: 11) {
            Circle()
                .fill(Color.pHold)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Color.pInk)
            Spacer(minLength: 0)
            action()
        }
        // 12/14 内边距 + 1pt line 描边，与 HTML .warn 一致：视觉上是一条，不是卡片。
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .fill(Color.pHoldSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(Color.pLine, lineWidth: 1)
        )
    }
}

// ── 顶栏（.topbar，44pt）──
// 左端 14pt 起是系统红绿灯的占位（hiddenTitleBar 下系统绘制，不再画假红绿灯）；
// 右端秩序固定：状态胶囊（只读，挤了先截）→ 壁纸来源标签 → 来源切换（永不截断）。
// 来源切换不染分区色：它切的是内容类型，不是「去哪个区」。
struct SettingsTopBar<Pill: View>: View {
    @Environment(\.liquidGlassActive) private var glass
    let kind: WallpaperKind
    /// 仅当目标来源 != 当前来源时由内部保证调用；动作本身由装配层注入。
    let switchSource: (WallpaperKind) -> Void
    @ViewBuilder var pill: () -> Pill

    private var sourceIndex: Binding<Int> {
        Binding(
            get: { kind == .image ? 1 : 0 },
            set: { i in
                let target: WallpaperKind = i == 1 ? .image : .video
                if target != kind { switchSource(target) }
            })
    }

    var body: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            pill()
                .lineLimit(1)
                // 状态胶囊最大宽 320、中段截断：它是只读的派生信息，挤了先截它（HTML §02）。
                .frame(maxWidth: 320, alignment: .leading)
                .truncationMode(.middle)
                .accessibilityIdentifier("status-paused")
            HStack(spacing: 8) {
                Text("壁纸来源")
                    .font(mono(10))
                    .foregroundStyle(Color.pInk3)
                SlideSegmented(items: ["视频", "图片"], index: sourceIndex, track: .pSurface3,
                               itemIdentifiers: ["source-switch-video", "source-switch-image"])
                    .frame(width: 132, height: 26)
                // 刻意**不给**容器挂 accessibilityIdentifier("source-switch")：与侧栏同款
                // AX 串染——容器标识会向下覆盖 SlideSegmented 的 itemIdentifiers
                // （source-switch-video/-image 真机实测查不到）。契约 id 在段上，别加回来。
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 14)
        .frame(maxWidth: .infinity, minHeight: Metrics.topbarHeight, maxHeight: Metrics.topbarHeight)
        // 液态玻璃开启时顶栏让位给根材质（整窗统一玻璃），底部分隔线保留出结构；
        // 关闭时不透明 pSurface2，与原状逐像素相同。
        .background(glass ? AnyShapeStyle(.clear) : AnyShapeStyle(Color.pSurface2))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.pLine).frame(height: 1)
        }
    }
}

// ── 侧栏（.side，216pt）──
// 三段结构：身份区 → 导航 → 页脚状态。只做导航，不放任何设置控件。
// 每个导航项用**自己区**的身份色：选中 = soft 底 + text 色文字 + 实心图标盒；
// 未选中 = ink2 文字 + surface3 图标盒。
struct SettingsSideBar: View {
    @Environment(\.liquidGlassActive) private var glass
    let kind: WallpaperKind
    @Binding var page: SettingsPresentation.SettingsPage
    /// 队列徽标：只在 > 0 时出现，徽标只给「有事要做」的区。
    let queueCount: Int
    let statusTint: Color
    let statusText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            identity
            navList
                .padding(.top, 20)
            Spacer(minLength: 0)
            footer
        }
        .padding(14)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .frame(width: Metrics.sidebarWidth, alignment: .topLeading)
        // 同顶栏：玻璃开启让位根材质，右缘分隔线保留；关闭时不透明 pSurface2。
        .background(glass ? AnyShapeStyle(.clear) : AnyShapeStyle(Color.pSurface2))
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color.pLine).frame(width: 1)
        }
        // 刻意**不给**容器挂 accessibilityIdentifier("nav-sidebar")：macOS AX 桥接会把容器
        // 标识向下串染，把四个导航行自己的 nav-button-* 全部覆盖成 nav-sidebar（XCUITest
        // 真机首跑实测，树里 9 处全被串染）。容器语义由子元素各自的 id 承载，别加回来。
    }

    private var identity: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.pBrand)
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 15))
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
    }

    private var navList: some View {
        VStack(spacing: 4) {
            ForEach(SettingsPresentation.navPages(for: kind), id: \.self) { item in
                navRow(item)
            }
        }
    }

    private func navRow(_ item: SettingsPresentation.SettingsPage) -> some View {
        let on = page == item
        let z = zonePalette(item)
        return Button {
            page = item
        } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(on ? z.base : Color.pSurface3)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Image(systemName: navSymbol(item))
                            .font(.system(size: 13))
                            .foregroundStyle(on ? z.ink : Color.pInk3)
                    )
                Text(item.title)
                    .font(.system(size: 13, weight: on ? .semibold : .regular))
                    .foregroundStyle(on ? z.text : Color.pInk2)
                if item == .queue, queueCount > 0 {
                    Text("\(queueCount)")
                        .font(mono(10))
                        .foregroundStyle(Color.pInk2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.pSurface)
                                .overlay(Capsule().strokeBorder(Color.pLine, lineWidth: 1))
                        )
                }
                Spacer(minLength: 0)
            }
            .frame(height: 38)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(on ? z.soft : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(navIdentifier(item))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Circle()
                    .fill(statusTint)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.pInk2)
                    .lineLimit(1)
            }
            Text("GPL v2 · 无第三方依赖")
                .font(mono(10))
                .foregroundStyle(Color.pInk3)
        }
    }
}
