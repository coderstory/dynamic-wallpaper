// 满覆盖检测的行为锁（2026-10-07 用户拍板：**屏幕被铺满就该让路，最大化也不例外**）。
// 判定 = 覆盖率 ≥ 1.0（参照 visibleFrame，内缩补偿后最大化窗口恰好 1.000 —— 语义上
// 「最大化 = 让路」就是靠这一条成立的）。几何数字由 FullscreenGeometryTests 锁；
// 本文件锁「检测器把几何变成回调」的行为：启动评估、事件重估、不记边沿。
// 轮询（2s）不可单测（真时钟），由真机验证。

import XCTest
import AppKit
@testable import PicCore

@MainActor
final class FullscreenDetectorTests: XCTestCase {

    private let screenHeight: Double = 956

    /// 最大化：铺满 visibleFrame（0,33,1470,833），内缩补偿后 coverage=1.000。
    private static let maximizedSamples = [WindowRectSample(pid: 1, raw: ScreenRect(x: 0, y: 33, w: 1470, h: 833))]

    /// 真全屏：覆盖整块屏幕框（0,0,1470,956）。
    private static let fullscreenSamples = [WindowRectSample(pid: 1, raw: ScreenRect(x: 0, y: 0, w: 1470, h: 956))]

    /// 半屏窗口：明显不满覆盖。
    private static let halfSamples = [WindowRectSample(pid: 1, raw: ScreenRect(x: 0, y: 33, w: 735, h: 833))]

    private final class BoolLog: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [Bool] = []
        func append(_ v: Bool) { lock.lock(); items.append(v); lock.unlock() }
        var all: [Bool] { lock.lock(); defer { lock.unlock() }; return items }
    }

    @MainActor
    private func makeDetector(samples: @escaping () -> [WindowRectSample])
        -> (log: BoolLog, detector: FullscreenDetector) {
        let log = BoolLog()
        let detector = FullscreenDetector(
            geometryReader: {
                // 真实几何（与下方真机夹具同源）：屏幕框 956，visibleFrame 底部留 33px Dock。
                ScreenGeometry(frame: ScreenRect(x: 0, y: 0, w: 1470, h: self.screenHeight),
                               visible: ScreenRect(x: 0, y: 90, w: 1470, h: 833))
            },
            sampleReader: samples,
            inset: .measured1470x956)
        detector.start { log.append($0) }
        return (log, detector)
    }

    /// 模拟一次前台应用切换。
    @MainActor
    private func postFrontmostChange() {
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: NSRunningApplication.current])
    }

    @MainActor
    private func waitMainQueue() {
        let exp = expectation(description: "main queue drained")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: 2)
    }

    /// 启动即满覆盖（最大化 / 真全屏都一样）→ **立即判 true**。
    /// 旧设计里启动评估永不激活让路，重启于满覆盖状态会「显示正在播放」，已按用户拍板废除。
    func testLaunchWhileCoveredPausesImmediately() {
        for samples in [Self.maximizedSamples, Self.fullscreenSamples] {
            let (log, detector) = makeDetector(samples: { samples })
            XCTAssertEqual(log.all, [true], "启动即满覆盖 → 立即让路")
            detector.stop()
        }
    }

    /// 半屏窗口 → false；前台切换事件后重估 → 仍然 false（不记边沿，事件只是触发重读）。
    func testHalfScreenStaysFalseAcrossFrontmostChanges() {
        let (log, detector) = makeDetector(samples: { Self.halfSamples })
        XCTAssertEqual(log.all, [false])

        postFrontmostChange()
        waitMainQueue()
        XCTAssertEqual(log.all, [false, false], "半屏不满覆盖，事件重估后依旧 false")
        detector.stop()
    }

    /// 最大化窗口 + 任何事件重估 → 恒 true（满覆盖是持续状态，不是一次性信号）。
    func testMaximizedStaysTrueAcrossFrontmostChanges() {
        let (log, detector) = makeDetector(samples: { Self.maximizedSamples })
        XCTAssertEqual(log.all, [true])

        postFrontmostChange()
        waitMainQueue()
        XCTAssertEqual(log.all, [true, true], "满覆盖状态下事件重估不翻转判定")
        detector.stop()
    }

    /// 无窗口（纯桌面）→ false。
    func testEmptyDesktopIsFalse() {
        let (log, detector) = makeDetector(samples: { [] })
        XCTAssertEqual(log.all, [false], "没有窗口铺屏 → 正常播放")
        detector.stop()
    }
}
