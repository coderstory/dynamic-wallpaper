import AVFoundation
import XCTest

/// 设置窗控件的交互面（Plan 05-04）。
///
/// 置灰只认 `isEnabled` 与「点了没反应」；视觉变淡不算证据 —— UI-SPEC §8
/// 明令，且一个只调 opacity 的实现会让下面三条全绿。
final class SettingsControlsUITests: XCTestCase {

    private var evidenceURL: URL!
    private var sourceDir: URL!

    // SettingsStore.persist() 一次写全 7 键，跨用例串味会让「默认静音=false /
    // 默认单循环」这类起点假红。两端各清一次：跑前清、跑后清（不留给用户机器）。
    private static let storeKeys = ["sourceFolderPath", "rate", "volume", "muted",
                                    "playMode", "rotationInterval", "pauseOnBattery"]

    override func setUpWithError() throws {
        continueAfterFailure = false
        clearStoreDefaults()
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("pic-uitest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        sourceDir = base.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        evidenceURL = base.appendingPathComponent("evidence.log")
        FileManager.default.createFile(atPath: evidenceURL.path, contents: nil)
    }

    override func tearDownWithError() throws {
        clearStoreDefaults()
        try? FileManager.default.removeItem(at: evidenceURL.deletingLastPathComponent())
    }

    // MARK: - 脚手架

    /// `defaults delete <domain> <key>` 一次只删一个键 —— 传多个键会被整体忽略。
    private func clearStoreDefaults() {
        for key in Self.storeKeys {
            let p = Process()
            p.launchPath = "/usr/bin/defaults"
            p.arguments = ["delete", "com.local.pic", key]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try? p.run()
            p.waitUntilExit()
        }
    }

    private func launchApp(source: URL? = nil) -> XCUIApplication {
        let a = XCUIApplication()
        // frame 记忆由 run-uitests.sh 起测前清（cfprefsd 缓存让测试内清理不即时生效）。
        a.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "--open-settings"]
        a.launchEnvironment["PIC_SOURCE_FOLDER"] = (source ?? sourceDir).path
        a.launchEnvironment["PIC_EVIDENCE_FILE"] = evidenceURL.path
        a.launch()
        app = a
        return a
    }

    private var app: XCUIApplication!

    private func el(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func evidence() -> String {
        (try? String(contentsOf: evidenceURL, encoding: .utf8)) ?? ""
    }

    private func waitForEvidence(_ fragment: String, timeout: TimeInterval = 10) -> String {
        let deadline = Date().addingTimeInterval(timeout)
        var text = evidence()
        while Date() < deadline {
            if text.contains(fragment) { return text }
            Thread.sleep(forTimeInterval: 0.25)
            text = evidence()
        }
        return text
    }

    /// 断言「某键没被写过」用：等一会儿再读，把异步写盘的时间让出去。
    @discardableResult
    private func settle(_ seconds: TimeInterval = 2.0) -> String {
        Thread.sleep(forTimeInterval: seconds)
        return evidence()
    }

    private func waitEnabled(_ id: String, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let e = el(id)
            if e.exists && e.isEnabled { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return false
    }

    /// 自绘小视频（AVAssetWriter，零 ffmpeg —— 本机 ffmpeg 类调用绝不进自动路径）。
    /// 扫描器用 AVFoundationAssetProbe 判视频轨，占位文本过不了它。
    private func makePlayableVideos(count: Int) {
        for i in 0..<count {
            let url = sourceDir.appendingPathComponent("clip-\(i).mp4")
            let w = try! AVAssetWriter(outputURL: url, fileType: .mp4)
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 16, AVVideoHeightKey: 16])
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: input,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
                    kCVPixelBufferWidthKey as String: 16,
                    kCVPixelBufferHeightKey as String: 16])
            w.add(input)
            w.startWriting()
            w.startSession(atSourceTime: .zero)
            for f in 0..<3 {
                while !input.isReadyForMoreMediaData { usleep(3000) }
                var opt: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &opt)
                guard let pb = opt else { continue }
                CVPixelBufferLockBaseAddress(pb, [])
                memset(CVPixelBufferGetBaseAddress(pb), Int32(30 + f * 40), CVPixelBufferGetDataSize(pb))
                CVPixelBufferUnlockBaseAddress(pb, [])
                adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(f), timescale: 10))
            }
            input.markAsFinished()
            let sem = DispatchSemaphore(value: 0)
            w.finishWriting { sem.signal() }
            sem.wait()
        }
    }

    // MARK: - TEST-07 控件全景

    func testAllControlsExistAndTranscodeStaysDisabled() throws {
        _ = launchApp()
        XCTAssertTrue(app.windows.matching(NSPredicate(format: "title CONTAINS %@", "Pic 设置"))
            .firstMatch.waitForExistence(timeout: 10), "设置窗应经 --open-settings 打开")

        // 默认起点（loopSingle）下这两个本就置灰，可点性归 TEST-08 判。
        let conditional = ["rotation-stepper"]
        let interactive = ["rate-slider", "volume-slider", "sound-toggle", "mode-segmented",
                            "battery-toggle", "autostart-toggle", "select-button", "rescan-button"]
        let display = ["rate-value", "volume-value", "status-paused", "status-ffmpeg"]

        for id in interactive + conditional + display + ["transcode-open"] {
            XCTAssertTrue(el(id).waitForExistence(timeout: 5), "控件 \(id) 应存在（TEST-07）")
        }
        for id in interactive {
            XCTAssertTrue(el(id).isHittable, "控件 \(id) 应可点（TEST-07）")
        }
        // Phase 5 的转码入口是 disabled 占位；enabled 即等于把没做的功能说成做了。
        XCTAssertFalse(el("transcode-open").isEnabled, "转码入口是 disabled 占位，不得可点")

        el("sound-toggle").tap()
        XCTAssertTrue(waitForEvidence("PIC_SETTINGS_APPLY key=muted").contains("key=muted"),
                      "点静音开关必须真的走到 applier（TEST-07/T-05-16）")
    }

    // MARK: - TEST-08 两条置灰联动（以交互不生效为准）

    func testRotationRowIgnoresTapsInSingleLoopAndRecoversInListLoop() throws {
        _ = launchApp()
        let stepper = el("rotation-stepper")
        XCTAssertTrue(stepper.waitForExistence(timeout: 10))
        XCTAssertFalse(stepper.isEnabled, "单循环下轮换整行应 disabled（TEST-08 ①）")

        let before = settle()
        XCTAssertFalse(before.contains("key=rotationInterval"),
                       "起点就该没有 rotationInterval 证据行，实际：\(before)")
        if stepper.isHittable {
            // 步进器是自绘的：identifier 挂在整行上，落点取行内最右（下行箭头）。
            stepper.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        }
        XCTAssertFalse(settle().contains("key=rotationInterval"),
                       "置灰期间点步进器必须不生效（TEST-08 ①）")

        app.buttons["列表循环"].tap()
        XCTAssertTrue(waitEnabled("rotation-stepper"), "切回列表循环后轮换行应恢复可用（TEST-08 ①）")
        el("rotation-stepper").coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertTrue(waitForEvidence("PIC_SETTINGS_APPLY key=rotationInterval")
            .contains("key=rotationInterval"), "可用后点步进器必须当场生效（TEST-08 ①）")
    }

    func testVolumeSliderIgnoresDragWhenMutedAndRecoversAfterUnmute() throws {
        _ = launchApp()
        let slider = el("volume-slider")
        XCTAssertTrue(slider.waitForExistence(timeout: 10))

        el("sound-toggle").tap()
        XCTAssertTrue(waitForEvidence("key=muted value=1").contains("key=muted value=1"),
                      "第一次点开关应进入静音")
        XCTAssertFalse(el("volume-slider").isEnabled, "静音下滑杆应 disabled（TEST-08 ②）")

        let before = settle()
        XCTAssertFalse(before.contains("key=volume"), "起点不该有 volume 证据行，实际：\(before)")
        drag(el("volume-slider"), from: 0.15, to: 0.85)
        XCTAssertFalse(settle().contains("key=volume"),
                       "静音期间拖滑杆必须不生效（TEST-08 ②）")

        el("sound-toggle").tap()
        XCTAssertTrue(waitEnabled("volume-slider"), "开声后滑杆应恢复可用（TEST-08 ②）")
        drag(el("volume-slider"), from: 0.15, to: 0.85)
        XCTAssertTrue(waitForEvidence("PIC_SETTINGS_APPLY key=volume").contains("key=volume"),
                      "可用后拖滑杆必须当场生效（TEST-08 ②）")
    }

    // MARK: - TEST-09 空态

    func testEmptyFolderShowsVerbatimCopyAndRescanStaysEnabled() throws {
        // 空目录必须**真空**：Finder 或任何一次写目录元数据都会塞进 .DS_Store，
        // 那样 populated 与 empty 判不出差别，测试会假绿。
        let empty = FileManager.default.temporaryDirectory
            .appendingPathComponent("pic-empty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: empty) }

        let app2 = launchApp(source: empty)
        // 逐字相等，不是 contains 子串 —— 子串匹配放行改过标点的文案。
        let verbatim = "没找到能播的文件。壁纸已隐藏，桌面显示的是系统原壁纸。"
        let copy = app2.staticTexts
            .matching(NSPredicate(format: "label == %@", verbatim)).firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 15),
                      "空目录启动应逐字显示空态文案（TEST-09），实际静态文本：\(app2.staticTexts.allElementsBoundByIndex.map(\.label))")

        XCTAssertTrue(waitEnabled("rescan-button"), "空态下重扫必须保持可用（它是恢复路径）")
    }

    // MARK: - TEST-10 菜单栏实点

    func testMenuBarExposesFiveHittableItems() throws {
        _ = launchApp()
        let statusItem = app.descendants(matching: .statusItem).firstMatch
        guard statusItem.waitForExistence(timeout: 10) else {
            print("NOTE W-2026-10-03-31 menubar extra not reachable via XCUITest")
            throw XCTSkip("W-2026-10-03-31 menubar extra not reachable via XCUITest")
        }
        statusItem.click()

        // 逐字文案已由 MenuBarModelTests 锁；这里只钉「5 项都真的能点」。
        // BEGINSWED 不写死 ⌘, 后缀：那条渲染契约不在本用例的职责面。
        for prefix in ["暂停", "继续", "立即下一个", "重新扫描文件夹", "打开设置", "退出"] {
            let item = app.menuItems
                .matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
            XCTAssertTrue(item.waitForExistence(timeout: 5), "菜单应有「\(prefix)」项（TEST-10）")
            XCTAssertTrue(item.isHittable, "菜单项「\(prefix)」应可点（TEST-10）")
        }
    }

    // MARK: - G-04-3 回归：立即下一个在单循环下也要切

    func testNextVideoMenuItemAdvancesEvenInSingleLoopMode() throws {
        makePlayableVideos(count: 2)
        _ = launchApp()
        XCTAssertTrue(waitForEvidence("PIC_SETTINGS_BOOT").contains("playMode=loopSingle"),
                      "默认模式必须是单循环，这条回归就锁在这个起点上（G-04-3）")

        let statusItem = app.descendants(matching: .statusItem).firstMatch
        guard statusItem.waitForExistence(timeout: 10) else {
            print("NOTE W-2026-10-03-31 menubar extra not reachable via XCUITest")
            throw XCTSkip("W-2026-10-03-31 menubar extra not reachable via XCUITest")
        }
        statusItem.click()

        let next = app.menuItems
            .matching(NSPredicate(format: "label BEGINSWITH %@", "立即下一个")).firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 5), "菜单应有「立即下一个」（G-04-3）")
        next.click()

        let ev = waitForEvidence("PIC_MENU_ACTION=next_video")
        XCTAssertTrue(ev.contains("PIC_MENU_ACTION=next_video"), "实点菜单项必须真的走到 nextVideoNow")
        // 装载了哪一条不进证据（T-03-02 禁文件名）。advances 计数递增是它的可 grep 代理：
        // 列表空时 advance() 直接 return，计数恒 0 —— 于是这一行同时证明「有列表」与「切了」。
        XCTAssertTrue(ev.contains("PIC_ROT_ADVANCES=1"),
                      "单循环下用户请求仍应推进一次（G-04-3），实际证据：\(ev)")
    }

    // MARK: - 拖动助手

    private func drag(_ e: XCUIElement, from: CGFloat, to: CGFloat) {
        let start = e.coordinate(withNormalizedOffset: CGVector(dx: from, dy: 0.5))
        start.press(forDuration: 0.1,
                    thenDragTo: e.coordinate(withNormalizedOffset: CGVector(dx: to, dy: 0.5)))
    }
}