import Foundation
import XCTest
@testable import PicCore

/// 不依赖本机 PATH / 文件系统，换台机器也必须照样过：判定经 `ExternalToolLocator` 注入，which 与文件系统都是本文件自带的假件（不跨文件复用）。判定只看「可执行文件」，零执行 —— 这里的 ffmpeg 只是路径串，从不被运行过。
final class FFmpegAvailabilityTests: XCTestCase {

    /// which 替身：status 是 terminationStatus 语义，path 是 stdout 去空白（nil = 空串）。
    private struct FakeWhich: WhichProbing {
        let status: Int32
        let path: String?
        func whichFFmpeg() -> (status: Int32, path: String?) { (status, path) }
    }

    /// 文件系统替身：集合外的路径 = 不存在**或**存在但不可执行（判定不可区分，故并为一类）。
    private struct FakeFS: ExecutableFileProbing {
        let executables: Set<String>
        func isExecutableFile(atPath path: String) -> Bool { executables.contains(path) }
    }

    private func statusCardSays(
        whichStatus: Int32 = 1,
        whichPath: String? = nil,
        executables: Set<String> = []
    ) -> Bool {
        let locator = ExternalToolLocator(
            which: FakeWhich(status: whichStatus, path: whichPath),
            fileSystem: FakeFS(executables: executables)
        )
        return FFmpegAvailability.available(locator.locate())
    }

    func testExplicitProbePathIsReportedAvailable() {
        XCTAssertTrue(statusCardSays(executables: ["/opt/homebrew/bin/ffmpeg"]))
    }

    func testMissingFFmpegYieldsUnavailable() {
        XCTAssertFalse(statusCardSays())
    }

    /// 判定跟着 locator 的显式探测表走，不是自己数 PATH 目录 —— 不在探测表上的路径存在也算「没装」。
    func testPathOutsideProbeTableYieldsUnavailable() {
        XCTAssertFalse(statusCardSays(executables: ["/opt/homebrew/bin/ffmpeg-not-exec"]))
    }

    /// which 命中也算装 —— 装在自定义路径、但不在两条显式探测路径上的机器靠它兜底。
    func testWhichFallbackIsReportedAvailable() {
        XCTAssertTrue(statusCardSays(whichStatus: 0, whichPath: "/opt/custom/bin/ffmpeg"))
    }

    /// GUI 从 Dock 启动时 PATH 极简、which 失败，此时必须靠显式探测兜住，否则本机会误报「未安装」。
    func testGuiMinimalPathStillFindsHomebrewInstall() {
        XCTAssertTrue(statusCardSays(whichStatus: 1, executables: ["/opt/homebrew/bin/ffmpeg"]))
    }

    /// 状态卡只报可用性，版本串不在这一层。
    func testLabelIsAvailableOrNotInstalledOnly() {
        XCTAssertEqual(FFmpegAvailability.label(available: true), "可用")
        XCTAssertEqual(FFmpegAvailability.label(available: false), "未安装")
    }
}