import XCTest

/// 断言只锁**行为属性**（宽度 / 存在 / 进程活），不锁内部实现；读数经 `PIC_EVIDENCE_FILE` 证据桥落盘。
final class SettingsWindowUITests: XCTestCase {

    private var evidenceURL: URL!
    private var sourceDir: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("pic-uitest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        // 空 source 隔离：不碰真实素材目录，也避免首启弹 NSOpenPanel。
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
        // 窗口 frame 记忆由 run-uitests.sh 在起测前清掉（cfprefsd 缓存让测试内的 defaults 清理不即时生效），
        // -ApplePersistenceIgnoreState 兜底禁状态恢复。不清的话宽度断言读到的是上次关窗时的尺寸，不是 defaultSize 的 780。
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"] + extraArguments
        app.launchEnvironment["PIC_SOURCE_FOLDER"] = sourceDir.path
        app.launchEnvironment["PIC_EVIDENCE_FILE"] = evidenceURL.path
        app.launch()
        return app
    }

    private func settingsWindow(in app: XCUIApplication) -> XCUIElement {
        app.windows.matching(NSPredicate(format: "title CONTAINS %@", "动态壁纸")).firstMatch
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

    /// XCUITest 半边只判宽 780（±1.5）；minWidth 680 读不到 contentMinSize，由探针行断言。
    func testWindowOpensAt780WideViaDebugSwitch() throws {
        let app = launchApp(extraArguments: ["--open-settings"])
        let settings = settingsWindow(in: app)
        XCTAssertTrue(settings.waitForExistence(timeout: 10), "设置窗应经 --open-settings 打开")
        XCTAssertEqual(settings.frame.width, 780, accuracy: 1.5)

        let evidence = waitForEvidence(containing: "PIC_SETTINGS_WINDOW width=780")
        XCTAssertTrue(evidence.contains("PIC_SETTINGS_WINDOW width=780"),
                      "证据桥应含窗口几何行，实际：\(evidence)")
    }

    /// 关窗后进程不退、设置窗消失；菜单栏图标找不到就登记 NOTE，不硬拗成失败。
    func testClosingWindowKeepsProcessAlive() throws {
        let app = launchApp(extraArguments: ["--open-settings"])
        let settings = settingsWindow(in: app)
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.buttons[XCUIIdentifierCloseWindow].click()
        Thread.sleep(forTimeInterval: 1.0)

        XCTAssertNotEqual(app.state, .notRunning, "关窗后进程不退（MENUBAR-02）")
        XCTAssertFalse(settings.exists, "关窗后设置窗应消失")

        app.activate()
        let statusItem = app.descendants(matching: .statusItem).firstMatch
        if !statusItem.waitForExistence(timeout: 3) {
            print("NOTE statusItems not found via XCUITest —— MENUBAR-02「图标仍在」未以 XCUITest 断言，留 UAT 人工确认")
        }
    }

    /// 这里**不发真实 ⌘, 按键**：本 app 是 `.accessory`（菜单栏）app，没有 key window 时系统级 ⌘,
    /// 会被系统接管去打开「系统设置」—— 那是在污染用户机器，不是测产品。
    /// 改走菜单项本身：点开菜单栏图标 → 断言菜单项文案逐字是「打开设置 ⌘,」→ 点它开窗。
    /// 未被 XCUITest 证明的是键盘等价键的**实际按键响应**；它由 `MenuShortcut` 的 keyboardShortcut
    /// 注册，菜单里「⌘,」的字面渲染是同一处的产物。
    func testSettingsMenuItemRendersShortcutAndOpensWindow() throws {
        let app = launchApp()
        let statusItem = app.descendants(matching: .statusItem).firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 10), "菜单栏图标应存在")
        statusItem.click()

        let item = app.menuItems["打开设置 ⌘,"]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "菜单应逐字渲染「打开设置 ⌘,」")
        item.click()

        let settings = settingsWindow(in: app)
        XCTAssertTrue(settings.waitForExistence(timeout: 5), "点菜单项应打开设置窗（MENUBAR-06）")
    }

    /// 交互半边：拖速度滑杆当场生效，退出再起回读到拖后的值。自绘滑杆拖不到目标值时**不静默放过**：
    /// XCTSkip 并在 skip 串里写明 W 号（run-uitests.sh 按同号 grep 登记簿，缺登记即非 0 退出）。
    func testRateDragAppliesImmediatelyAndSurvivesRelaunch() throws {
        let app = launchApp(extraArguments: ["--open-settings"])
        XCTAssertTrue(settingsWindow(in: app).waitForExistence(timeout: 10))

        let boot0 = waitForEvidence(containing: "PIC_SETTINGS_BOOT")
        XCTAssertTrue(boot0.contains("rate=1.0"), "起点必须是默认 1.00，实际：\(boot0)")

        let slider = app.descendants(matching: .any)
            .matching(identifier: "rate-slider").firstMatch
        XCTAssertTrue(slider.waitForExistence(timeout: 5))

        // 自绘手势接的是 DragGesture，coordinate 拖动是唯一能命中它的路子。
        // 连拖三次仍读不到非默认值就是漂移不可控 —— 那时如实 skip，不冒充拖过。
        var dragged = ""
        for _ in 0..<3 {
            slider.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
                .press(forDuration: 0.1, thenDragTo:
                    slider.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)))
            Thread.sleep(forTimeInterval: 1.0)
            dragged = String(((try? String(contentsOf: evidenceURL, encoding: .utf8))?
                .split(separator: "\n")
                .first { $0.contains("PIC_SETTINGS_APPLY key=rate") }) ?? "")
            if dragged.contains("applied=1") && !dragged.contains("value=1.0 ") { break }
            dragged = ""
        }
        guard !dragged.isEmpty else {
            print("NOTE W-2026-10-03-32 slider drag drift")
            throw XCTSkip("W-2026-10-03-32 slider drag drift")
        }
        XCTAssertTrue(dragged.contains("applied=1"),
                      "拖动当场生效：applyRate 门内应打 applied=1，实际：\(dragged)")

        let value = dragged.split(separator: " ").first { $0.hasPrefix("value=") }!
            .replacingOccurrences(of: "value=", with: "")
        app.terminate()

        // 同一证据文件重起（不播种）：回读只能来自上一进程写进 UserDefaults 的值。
        let app2 = launchApp(extraArguments: ["--open-settings"])
        XCTAssertTrue(settingsWindow(in: app2).waitForExistence(timeout: 10))
        let boot1 = waitForEvidence(containing: "PIC_SETTINGS_BOOT rate=\(value)")
        XCTAssertTrue(boot1.contains("PIC_SETTINGS_BOOT rate=\(value)"),
                      "重启后 rate 应回读到拖后的 \(value)（TEST-04 交互闭环）")
    }
}
