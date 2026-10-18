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

/// chrome 面（顶栏 / 侧栏）的液态玻璃。卡片面走 `cardSurface()`，这两片是窗壳 —— 形状是直角矩形，
/// 所以单独一个修饰器而不是把 cardSurface 参数化（参数化后两条路径只有形状不同，白付一次分支）。
/// 关闭分支是不透明 pSurface2：不开玻璃时必须零视觉变化。
private struct ChromeSurface: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content
                .background(Color.clear)
                .glassEffect(.regular, in: Rectangle())
        } else {
            content.background(Color.pSurface2)
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
        // 页头随 `page` 换区：竖条与标题的颜色得跟着过渡，否则切区时颜色「啪」地跳一下。
        .animation(Motion.state, value: page)
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
        .animation(Motion.state, value: index)
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
    /// 播放中时圆点呼吸：这是唯一一处「什么都没变也该动」的动画 —— 它说的是
    /// 「系统在跑」这件不可见的事。有余力才做，不做也不构成信息缺失。
    @State private var pulsing = false

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
                    // 只在播放中脉冲；让路/阻塞态的圆点是「不动的告警」，脉冲会读成「还在忙」。
                    .scaleEffect(kind == .playing && pulsing ? 1.35 : 1)
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
        // 文案变了（「播放中」→「已暂停」）不该硬切。
        .animation(Motion.state, value: kind)
        .onAppear {
            guard kind == .playing else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
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
        // 告警条随库状态出现/消失：滑入比硬切更容易被注意到（它出现就意味着出了事）。
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// ── 顶栏（.topbar，44pt）──
// 左端先让开系统红绿灯（hiddenTitleBar 下系统绘制在内容层左侧 78pt 内），再是身份块
// 「壁纸儿 + 版本号」—— 它从侧栏搬来，占据原先侧栏顶部的位置。
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
            brand
            Spacer(minLength: 0)
            // 右端两块收进同一个 trailing 组，用 **6pt** 固定间距。
            // 之前它们是 HStack 的两个平级子项（间距 10），而状态胶囊上挂着
            // `.frame(maxWidth: 320)` —— maxWidth 会先吃掉一段可用宽度再排版，
            // 于是「胶囊 →壁纸来源」之间的实际留白比设定值大得多（用户反馈「间隙太大」）。
            // 放进trailing 组后两块紧贴，间距就是那个 6。
            HStack(spacing: 6) {
                pill()
                    .lineLimit(1)
                    // 状态胶囊最大宽 320、中段截断：它是只读的派生信息，挤了先截它。
                    // 用 maxWidth 而不是 width：内容自适应窄宽，放不下才涨到 320。
                    .frame(maxWidth: 320)
                    .truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: true)
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
                .fixedSize(horizontal: true, vertical: false)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.leading, Metrics.trafficLightInset)
        .padding(.trailing, 14)
        // **强制 44pt**。`.frame(height:)` 是强制（装不下就裁）；
        // `minHeight/maxHeight` 只是「提议」—— 内容更高时 SwiftUI 照实排出去，
        // 实测顶栏被撑到 75pt（分隔线在 y=75）。
        .frame(height: Metrics.topbarHeight)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        // 液态玻璃开启时顶栏自身成为玻璃片（形状 = 直角矩形），底部分隔线保留出结构；
        // 关闭时不透明 pSurface2，与平面路径逐像素相同。
        .modifier(ChromeSurface(active: glass))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.pLine).frame(height: 1)
        }
    }

    /// 身份块：品牌图标 + 「壁纸儿」+ 版本号。从侧栏原样搬来，缩到 24pt 图标盒以塞进 44pt 顶栏。
    /// - 圆角 6.5：超椭圆（squircle）比例，小尺寸下才不像药丸。7 偏大。
    /// - 文字块与图标 `alignment: .center`：两行字 12+9pt 的视觉重心偏上，
    ///   `.top` 会让它比图标高一截，看着「没对齐」。
    /// - **不写竖向 fixedSize**：两行字（12pt + 9pt + 1pt 间距 ≈ 27pt）比 24pt 图标盒高，
    ///   锁死自然高度会把图标顶到上沿。水平方向单锁`horizontal: true` 即可。
    /// - 外层 `.frame(height: topbarHeight)` + `alignment: .center`：这一层是
    ///   **必需的**，不是冗余。hiddenTitleBar 下标题栏由系统在内容层之上叠加绘制，
    ///   SwiftUI 内容层的坐标原点与红绿灯的绘制位置差一个 titlebar 偏移；不显式给
    ///   44pt 高度并居中，brand 就会贴在内容层顶部而与红绿灯错位。
    private var brand: some View {
        HStack(alignment: .center, spacing: 9) {
            RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                .fill(Color.pBrand)
                .frame(width: 24, height: 24)
                .overlay(
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.pBrandInk)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text("壁纸儿")
                    .font(display(12))
                    .foregroundStyle(Color.pInk)
                Text("v\(appVersion()) · arm64")
                    .font(mono(9))
                    .foregroundStyle(Color.pInk3)
            }
            .fixedSize(horizontal: true, vertical: true)
        }
        // **只锁水平**。竖向什么都不写：brand 保持自然高度（两行字 ≈27pt），
        // 由顶栏的 `.frame(height: 44)` 强制塞进 44pt 并在其中居中。
        // 曾经在这里写 `.frame(height: topbarHeight)`是多余的 —— 它让 brand 变成
        // 44pt 高的子视图，顶栏再套44pt 约束时内容装不下就溢出，实测把图标推到
        // 顶栏下方 6.8pt（用户：「没变化啊」）。
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement()
        .accessibilityLabel(Text("壁纸儿，版本 \(appVersion())"))
        .accessibilityIdentifier("brand-block")
    }
}

// ── 侧栏（.side，216pt）──
// 一段结构：只有导航。身份区（「壁纸儿 + 版本号」）已搬到顶栏 banner；页脚的状态点 +
// 版权行也已删除 —— 状态在顶栏胶囊与播放页 hero 卡里各有一份更完整的位置，
// 侧栏底部那份是同一信息的第三份拷贝，只会让用户怀疑哪个是真的。
// 每个导航项用**自己区**的身份色：选中 = soft 底 + text 色文字 + 实心图标盒；
// 未选中 = ink2 文字 + surface3 图标盒。
struct SettingsSideBar: View {
    @Environment(\.liquidGlassActive) private var glass
    let kind: WallpaperKind
    @Binding var page: SettingsPresentation.SettingsPage
    /// 队列徽标：只在 > 0 时出现，徽标只给「有事要做」的区。
    let queueCount: Int
    /// 当前悬停的导航项。按 id 存而不是 Bool：四个行各自的 hover 底色互不干扰。
    @State private var hovering: SettingsPresentation.SettingsPage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            navList
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .frame(width: Metrics.sidebarWidth, alignment: .topLeading)
        // 同顶栏：玻璃开启时侧栏自身成为玻璃片，关闭时不透明 pSurface2。
        .modifier(ChromeSurface(active: glass))
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color.pLine).frame(width: 1)
        }
        // 刻意**不给**容器挂 accessibilityIdentifier("nav-sidebar")：macOS AX 桥接会把容器
        // 标识向下串染，把四个导航行自己的 nav-button-* 全部覆盖成 nav-sidebar（XCUITest
        // 真机首跑实测，树里 9 处全被串染）。容器语义由子元素各自的 id 承载，别加回来。
    }

    private var navList: some View {
        VStack(spacing: 4) {
            ForEach(SettingsPresentation.navPages(for: kind), id: \.self) { item in
                navRow(item)
            }
        }
        // 队列徽标会随任务数出现/消失，整列一起做进出过渡。
        .animation(Motion.state, value: kind)
    }

    private func navRow(_ item: SettingsPresentation.SettingsPage) -> some View {
        let on = page == item
        let z = zonePalette(item)
        return Button {
            page = item
        } label: {
            // 显式 `.center`：与品牌块同款问题 —— 不写 alignment 时文字按自身行高贴在
            // 28pt 图标盒的上沿，看着「文字没跟图标对齐」。与顶栏那次是同一个根因。
            HStack(alignment: .center, spacing: 10) {
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
                    // 撑满图标盒高度：只写 font 时文字行高≈16pt，在 28pt 的行里
                    // 靠 `.center` 对齐仍有半 pt 上下差；给足高度后基线才真正落在中心。
                    .frame(height: 28)
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
                        // 徽标冒出来时不能「啪」地砸在行里：从右滑入 + 淡入。
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                Spacer(minLength: 0)
            }
            .frame(height: 38)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    // 悬停底压在选中底之下：未选中行才有 hover 反馈，选中行的颜色已经够说明了。
                    .fill(on ? z.soft : (hovering == item ? Color.pSurface3.opacity(0.55) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(NavRowButtonStyle())
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(navIdentifier(item))
        // 选中底/ 图标底 / 字色三处一起过渡；`page` 变化驱动（不是 `on`，否则行重建时动画不跑）。
        .animation(Motion.state, value: page)
        .animation(Motion.state, value: queueCount)
        .onHover { hovering = $0 ? item : (hovering == item ? nil : hovering) }
    }
}

/// 侧栏行的按压反馈。与按钮同一语言（缩放代替透明度），但幅度更小 ——
/// 侧栏是常驻控件，按下去弹得太明显会显得吵。
private struct NavRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}
