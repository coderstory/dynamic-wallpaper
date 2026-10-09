import XCTest

/// 设置窗的 XCUITest。
///
/// 跑法：`xcodebuild -project Pic.xcodeproj -scheme Pic -destination 'platform=macOS' test`
/// —— SwiftPM `swift test` 跑不到这里：本 target 只存在于 xcodeproj，刻意不进 Package.swift。
///
/// 两条与 App 形态有关的前提，写用例前先认下：
/// 1. Pic 是菜单栏常驻 App（`LSUIElement = true`），没有 Dock 图标也没有主窗口，
///    设置窗只能走「点状态栏图标 → 面板里的『打开设置』」这条路叫出来。
/// 2. 断言只用 `exists` 与 identifier，**不断言坐标、颜色、字号** —— 那些是下一次改版就要
///    重写的断言，留着只会让人不敢动 UI。这里守的是「控件还在、页面还能到」这种会真伤到用户的回归。
///
/// 导航 / 来源切换的 identifier（`nav-button-*` / `source-switch-*`）以
/// `.planning/design/ui-redesign-v2-shell.html` 契约为准，已与 SettingsTiles.swift
/// 的侧栏实现对齐：设置窗是「顶栏 + 侧栏四页导航」版，没有 main-tabs 页签。
/// 侧栏容器刻意不挂 `nav-sidebar`（AX 桥会把容器标识向下串染，见 SettingsTiles.swift），只用行级 id。
/// 类级 @MainActor：XCUITest 的 click()/waitForExistence 都是主 actor 隔离的，
/// 用例方法本就跑在主 actor 上，标上让 Swift 6 并发检查不再告警。
@MainActor
final class PicUITests: XCTestCase {

    /// 单条用例里第一次断言失败就停 —— UI 用例的后续步骤都建立在前一步落地的前提上，
    /// 继续跑只会拿「元素不存在」刷屏，把真正的第一现场埋掉。
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 启动参数钉死视频来源：本机 App 的持久化域里 wallpaperKind 可能是 image
    /// （用户上次真的切过来源），而多条用例的前提是「视频来源起步」。参数域
    /// （NSArgumentDomain）优先级最高，`-wallpaperKind video` 让 store 首读必得 video，
    /// 用例间不依赖机器残留状态。
    ///
    /// 代价（记下供主线程决策）：Xcode 27 的测试 runner 沙箱隔离了偏好域视图 ——
    /// runner 里既读不到、也持久改不动真实的 com.local.bizhier 域（实测：runner 写入
    /// shell 侧不可见，读取恒为空），所以「跑完把用户的来源偏好写回去」在测试进程内
    /// 无法做到。套件跑完后本机持久化的来源会停在 video，需要还原时在 shell 手动执行：
    /// `defaults write com.local.bizhier wallpaperKind -string <原值>`。
    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-wallpaperKind", "video"]
        // LSUIElement 应用连发启动偶发 AX 注册未就绪（实测窗口 ~70s，套件里最先
        // 启动的两个实例最容易中招，表现为 "has not loaded accessibility" 级超时）。
        // 最多重启 3 次、每次等状态项就绪；三次都失败才交出去，让断言展示真实现场。
        for _ in 0..<3 {
            app.launch()
            if app.menuBars.statusItems.firstMatch.waitForExistence(timeout: 20) {
                return app
            }
            app.terminate()
            Thread.sleep(forTimeInterval: 10)
        }
        return app
    }

    /// 唤设置窗：状态栏图标 → 面板里的「打开设置」。
    /// 菜单由 `MenuPanelView` 自绘，行 identifier 是 `menu-row-<MenuItemID.rawValue>`
    /// （见 `Sources/PicApp/App/MenuPanelView.swift`），「打开设置」即 `menu-row-openSettings`。
    /// 这条路径一旦改坏，设置窗就是个用户永远打不开的功能，所以每个用例都从它起步。
    private func openSettings(in app: XCUIApplication) {
        let statusItem = app.menuBars.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 20),
                      "防回归：菜单栏必须有常驻状态项，它是 LSUIElement App 唯一的入口")

        statusItem.click()

        let openSettingsRow = element("menu-row-openSettings", in: app)
        XCTAssertTrue(openSettingsRow.waitForExistence(timeout: 10),
                      "防回归：面板必须给出「打开设置」这一行（id 由 MenuItemID.openSettings 派生）")
        openSettingsRow.click()
    }

    /// 按 identifier 取元素，不限定元素类型。
    /// 契约写的是 identifier 而不是控件种类 —— 「这里是 Toggle 还是 Switch」属于实现的自由，
    /// 用 `buttons[...]`/`switches[...]` 去查会把这种自由锁死，改个控件类型就得改测试。
    private func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// 切设置窗页：侧栏导航按钮，契约 id `nav-button-*`（见 SettingsTiles.swift 的 SettingsSideBar）。
    /// 侧栏行是自绘 AX 元素，按 identifier 找，不按标题 —— 标题属于实现的自由。
    private func clickNav(_ identifier: String, in app: XCUIApplication) {
        let nav = element(identifier, in: app)
        XCTAssertTrue(nav.waitForExistence(timeout: 10),
                      "防回归：侧栏必须有导航项 \(identifier)")
        nav.click()
    }

    /// 点顶栏来源分段里的目标段。
    /// 契约上每段有自己的 identifier（source-switch-video / -image，SettingsTopBar 传的
    /// itemIdentifiers），但顶栏容器同时挂着 `source-switch`，macOS AX 桥把容器标识向下
    /// 串染（SettingsSideBar 注释记载的 nav-sidebar 同款实测问题，真机 AX 树里两段都
    /// 顶着 `source-switch` 且无 label）。所以先按段自身 identifier 查（产品修掉串染后
    /// 走这条路）；查不到就点「未选中的那段」—— 串染形态下 Selected 标记是两段间唯一
    /// 的语义区分，不赌坐标、不赌元素顺序。
    private func clickSourceSegment(_ title: String, identifier: String, in app: XCUIApplication) {
        let byID = element(identifier, in: app)
        if byID.waitForExistence(timeout: 3) {
            byID.click()
            return
        }
        let segments = app.descendants(matching: .any).matching(identifier: "source-switch")
        let offSegment = segments.matching(NSPredicate(format: "isSelected == NO")).firstMatch
        XCTAssertTrue(offSegment.waitForExistence(timeout: 10),
                      "防回归：顶栏来源分段必须有「\(title)」一段可点（段 identifier \(identifier) 或未选中段均可查到）")
        offSegment.click()
    }

    // MARK: - 用例

    /// ① 冒烟：菜单栏 App 叫得出设置窗。
    /// 防回归：换 AppKit 宿主方式（popover / NSWindow / Scene）时最容易整扇窗叫不出来，
    /// 而菜单栏 App 没有 Dock 图标可以点，窗打不开 = 功能全丢且用户无处求助。
    func testStatusBarCanRevealSettingsWindow() {
        let app = makeApp()
        openSettings(in: app)

        // 顶栏状态胶囊是设置窗所有页共有的骨架，它出现即代表窗已落地。
        XCTAssertTrue(element("status-paused", in: app).waitForExistence(timeout: 20),
                      "防回归：设置窗必须显示顶栏状态胶囊 status-paused")
        // 侧栏导航是现有导航骨架：恒定三项（队列页在图片来源下隐藏，不在此断言），
        // 少一个就有一页够不着。
        for id in ["nav-button-play", "nav-button-library", "nav-button-general"] {
            XCTAssertTrue(element(id, in: app).exists,
                          "防回归：侧栏缺 \(id)，对应的一页不可达")
        }
    }

    /// ② 默认落在播放页。
    /// 防回归：默认页错位会让用户在错误的上下文里找控件
    /// （历史 bug：把队列/片库当成第一页）。播放页按库状态二态渲染：
    /// 有料 → 控件（mode-segmented）；空 → 空态卡（empty-primary）。
    /// 断言「二选一必在」，把「整页空白」的回归挡住，又不依赖测试机的库状态。
    func testPlayPageRendersControlsOrEmptyState() {
        let app = makeApp()
        openSettings(in: app)

        XCTAssertTrue(element("status-paused", in: app).waitForExistence(timeout: 20),
                      "防回归：设置窗先落地，播放页断言才有意义")

        let modeSegmented = element("mode-segmented", in: app)
        if modeSegmented.waitForExistence(timeout: 3) {
            return // 库非空：播放页控件态，完事。
        }
        XCTAssertTrue(element("empty-primary", in: app).exists,
                      "防回归：播放页既没有控件也没有空态卡 —— 整页空白是最严重的回归")
    }

    /// ③ 切到片库页能看到「选择…」「重新扫描」。
    /// 防回归：页签在但命令跑去别的对象上时，页面是空的 —— 这是纯 SwiftUI 导航最典型的
    /// 静默失败，单元测试抓不到，因为 ViewModel 是好的，坏的是按钮的目标。
    /// 这两个按钮在 sourceTile 上、不依赖库状态，任何机器都应出现。
    func testLibraryPageExposesSelectAndRescan() {
        let app = makeApp()
        openSettings(in: app)

        clickNav("nav-button-library", in: app)

        XCTAssertTrue(element("select-button", in: app).waitForExistence(timeout: 10),
                      "防回归：片库页必须有「选择…」（select-button），否则用户无法配置目录")
        XCTAssertTrue(element("rescan-button", in: app).exists,
                      "防回归：片库页必须有「重新扫描」（rescan-button）")
    }

    /// ④ 通用页的开机自启开关存在。
    /// 防回归：这是唯一一个写入 SMAppService 的开关，UI 上加控件易、接对 AppService 难；
    /// identifier 在，至少保证用户点得到，配不配得上由单元测试那条线盯。
    func testGeneralPageExposesAutostartToggle() {
        let app = makeApp()
        openSettings(in: app)

        clickNav("nav-button-general", in: app)

        XCTAssertTrue(element("autostart-toggle", in: app).waitForExistence(timeout: 10),
                      "防回归：通用页必须有开机自启开关 autostart-toggle")
    }

    /// ⑤ 菜单面板的「切换壁纸来源」行存在。
    /// 防回归：设置窗顶栏的 source-switch 只在设置窗开着时够得着，菜单面板这一行是
    /// 全局最短路径 —— 它是图片壁纸功能的命脉，行丢了功能就只剩编译期存在。
    func testMenuPanelExposesSwitchSourceRow() {
        let app = makeApp()

        let statusItem = app.menuBars.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 20),
                      "防回归：菜单栏必须有常驻状态项")
        statusItem.click()

        XCTAssertTrue(element("menu-row-switchSource", in: app).waitForExistence(timeout: 10),
                      "防回归：面板必须有「切换壁纸来源」行（menu-row-switchSource）")
    }

    /// ⑥ 来源切换要换的是**控件集**，不是只换文案。
    /// 防回归：图片来源没有转码队列，侧栏必须收起 nav-button-queue，片库页必须换上
    /// tier-segmented / fit-segmented / image-stat-total 这组图片专属控件 —— 历史 bug 是
    /// 顶栏分段切了、状态文案变了，但页面主体还是视频那套（用户对着「转码队列」入口发呆）。
    /// 反向再切回视频，队列入口必须回来 —— 只验证单向会漏掉「切回后侧栏没恢复」的回归。
    func testImageSourceSwapsControlsAndHidesQueue() {
        let app = makeApp()
        openSettings(in: app)

        XCTAssertTrue(element("status-paused", in: app).waitForExistence(timeout: 20),
                      "防回归：设置窗先落地，来源切换断言才有意义")

        // 视频来源（默认）下队列入口在侧栏里，先确认起点成立。
        let queueButton = element("nav-button-queue", in: app)
        XCTAssertTrue(queueButton.waitForExistence(timeout: 10),
                      "防回归：视频来源下侧栏必须有队列入口，否则无从验证它会被收起")

        // 图片专属控件在片库页：切过去等它们落地 —— 控件出现即代表图片来源已生效，
        // 同一个渲染 pass 里侧栏也换完了，此时断言队列入口消失才不是和异步赛跑。
        clickSourceSegment("图片", identifier: "source-switch-image", in: app)
        clickNav("nav-button-library", in: app)
        XCTAssertTrue(element("tier-segmented", in: app).waitForExistence(timeout: 20),
                      "防回归：图片片库页必须有分辨率筛选 tier-segmented")
        XCTAssertTrue(element("fit-segmented", in: app).exists,
                      "防回归：图片片库页必须有图片适配 fit-segmented")
        XCTAssertTrue(element("image-stat-total", in: app).exists,
                      "防回归：图片片库页统计带必须有图片总数格 image-stat-total")
        XCTAssertFalse(queueButton.exists,
                       "防回归：图片来源没有转码队列，侧栏必须收起 nav-button-queue")

        // 切回视频：队列入口必须回归。
        clickSourceSegment("视频", identifier: "source-switch-video", in: app)
        XCTAssertTrue(queueButton.waitForExistence(timeout: 10),
                      "防回归：切回视频来源后侧栏必须恢复队列入口 nav-button-queue")
    }

    /// ⑦ 队列页经侧栏可达。
    /// 防回归：队列页只能从侧栏进来（视频来源下），导航按钮在但 page 状态没接线时，
    /// 点了没反应 —— 内容区还停在播放页，这种静默失败单元测试抓不到。
    /// 队列页按任务数二态渲染：有任务 → 头部筛选条（transcode-badge）；空 → 空态卡。
    /// 空态卡在产品侧没有 identifier（见汇报），只能按标题文案查 —— 二选一必在，
    /// 把「点导航整页没反应」和「依赖测试机队列状态」都挡住。
    func testQueuePageReachableViaNav() {
        let app = makeApp()
        openSettings(in: app)

        XCTAssertTrue(element("status-paused", in: app).waitForExistence(timeout: 20),
                      "防回归：设置窗先落地，队列页断言才有意义")

        clickNav("nav-button-queue", in: app)

        let badge = element("transcode-badge", in: app)
        let emptyTitle = app.staticTexts["没有需要处理的文件"]
        XCTAssertTrue(badge.waitForExistence(timeout: 10) || emptyTitle.waitForExistence(timeout: 1),
                      "防回归：队列页必须渲染出骨架（任务态 transcode-badge 或空态卡「没有需要处理的文件」）")
    }

    /// ⑧ 通用页的外观卡带液态玻璃开关。
    /// 防回归：外观卡是液态玻璃唯一入口，重排版把整卡误删时编译照过、功能静默蒸发
    /// （store 键还在，只是没有任何 UI 能碰到它）。
    func testGeneralPageExposesGlassToggle() {
        let app = makeApp()
        openSettings(in: app)

        clickNav("nav-button-general", in: app)

        XCTAssertTrue(element("glass-toggle", in: app).waitForExistence(timeout: 10),
                      "防回归：通用页外观卡必须有液态玻璃开关 glass-toggle")
    }
}
