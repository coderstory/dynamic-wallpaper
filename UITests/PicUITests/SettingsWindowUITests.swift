import XCTest

/// 设置窗首批 XCUITest（Plan 05-01 T2）。
///
/// 断言只锁**行为属性**（宽度 / 存在 / 进程活），不锁内部实现。
/// 开窗走 `--open-settings` 脚手架（复用用户路径的两个函数），读数经
/// `PIC_EVIDENCE_FILE` 证据桥落盘再断言 —— 不拿「设置能开」冒充「用户能开」。
final class SettingsWindowUITests: XCTestCase {

    private var evidenceURL: URL!
    private var sourceDir: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("pic-uitest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        // 空 source 隔离（D-22 精神）：不碰真实素材目录，也避免首启弹 NSOpenPanel。
        sourceDir = base.appendingPathComponent("source-empty", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        evidenceURL = base.appendingPathComponent("evidence.log")
        FileManager.default.createFile(atPath: evidenceURL.path, contents: nil)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: evidenceURL.deletingLastPathComponent())
    }

    private func launchApp(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        // 窗口 frame 记忆由 run-uitests.sh 在起测前清掉（cfprefsd 缓存让测试内的
        // defaults 清理不即时生效）；-ApplePersistenceIgnoreState 兜底禁状态恢复。
        // 不清的话宽度断言读到上次关窗时的尺寸，不是 defaultSize 的 780。
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"] + extraArguments
        app.launchEnvironment["PIC_SOURCE_FOLDER"] = sourceDir.path
        app.launchEnvironment["PIC_EVIDENCE_FILE"] = evidenceURL.path
        app.launch()
        return app
    }

    private func settingsWindow(in app: XCUIApplication) -> XCUIElement {
        app.windows.matching(NSPredicate(format: "title CONTAINS %@", "Pic 设置")).firstMatch
    }

    /// 证据文件里的行由 onAppear 延迟半秒后写出 —— 轮询等它落盘。
    private func waitForEvidence(containing fragment: String, timeout: TimeInterval = 10) -> String {
        let deadline = Date().addingTimeInterval(timeout)
        var text = ""
        while Date() < deadline {
            if let current = try? String(contentsOf: evidenceURL, encoding: .utf8) {
                text = current
                if current.contains(fragment) { return current }
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return text
    }

    /// SC-1 的 XCUITest 半边：宽 780（±1.5）；minWidth 680 由探针行断言
    /// （XCUITest 读不到 contentMinSize 就不假装读得到）。
    func testWindowOpensAt780WideViaDebugSwitch() throws {
        let app = launchApp(extraArguments: ["--open-settings"])
        let settings = settingsWindow(in: app)
        XCTAssertTrue(settings.waitForExistence(timeout: 10), "设置窗应经 --open-settings 打开")
        XCTAssertEqual(settings.frame.width, 780, accuracy: 1.5)

        let evidence = waitForEvidence(containing: "PIC_SETTINGS_WINDOW width=780")
        XCTAssertTrue(evidence.contains("PIC_SETTINGS_WINDOW width=780"),
                      "证据桥应含窗口几何行，实际：\(evidence)")
    }

    /// MENUBAR-02：关窗后进程不退、设置窗消失；菜单栏图标仍可寻
    /// （statusItems 找不到就不硬拗，登记 NOTE，真人验证留 UAT）。
    func testClosingWindowKeepsProcessAlive() throws {
        let app = launchApp(extraArguments: ["--open-settings"])
        let settings = settingsWindow(in: app)
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.buttons[XCUIIdentifierCloseWindow].click()
        Thread.sleep(forTimeInterval: 1.0)

        // SDK 27 起 XCUIApplication.State 的 case 改名（NotRunning 大写开头）；
        // 「进程未退」的等价断言：state 不等于 notRunning。
        XCTAssertNotEqual(app.state, .notRunning, "关窗后进程不退（MENUBAR-02）")
        XCTAssertFalse(settings.exists, "关窗后设置窗应消失")

        app.activate()
        let statusItem = app.descendants(matching: .statusItem).firstMatch
        if !statusItem.waitForExistence(timeout: 3) {
            print("NOTE statusItems not found via XCUITest —— MENUBAR-02「图标仍在」未以 XCUITest 断言，留 UAT 人工确认")
        }
    }

    /// MENUBAR-06：⌘, 的功能绑定（不带 debug 开关启动，走真实快捷键路径）。
    func testCommandCommaOpensSettings() throws {
        let app = launchApp()
        app.activate()
        // SDK 27 起 typeKey 的参数标签改为 modifierFlags:。
        app.typeKey(",", modifierFlags: .command)

        let settings = settingsWindow(in: app)
        XCTAssertTrue(settings.waitForExistence(timeout: 5), "⌘, 应打开设置窗（MENUBAR-06）")
    }
}
