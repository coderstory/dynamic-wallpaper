import Foundation
import XCTest
@testable import PicCore

/// ffmpeg 可用性判定的单测。
///
/// ⚠️ 不依赖本机 PATH / 文件系统：判定经 `ExternalToolLocator` 注入，which 与
/// 文件系统都是本文件自带的假件（不跨文件引用 06-02 的测试替身）。判定只看
/// 「可执行文件」，**零执行** —— 这里的 ffmpeg 只是路径串，从不被运行过。
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

    /// 状态卡的读数 = locator 结论经 `FFmpegAvailability.available` 的投影。
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

    /// 判定跟着 locator 的显式探测表走，不是自己数 PATH 目录 ——
    /// 不在探测表上的路径存在也算「没装」，这正是「两套判定」的形状之一。
    func testPathOutsideProbeTableYieldsUnavailable() {
        XCTAssertFalse(statusCardSays(executables: ["/opt/homebrew/bin/ffmpeg-not-exec"]))
    }

    /// which 命中也算装 —— 装在自定义路径、但不在两条显式探测路径上的机器靠它兜底。
    func testWhichFallbackIsReportedAvailable() {
        XCTAssertTrue(statusCardSays(whichStatus: 0, whichPath: "/opt/custom/bin/ffmpeg"))
    }

    /// 🔴 D-17 收编的核心判据：GUI 最小 PATH 下（`which` 失败）显式探测仍命中。
    /// 收编前这套判定读的是 `PATH` 环境变量，本机会误报「未安装」。
    func testGuiMinimalPathStillFindsHomebrewInstall() {
        XCTAssertTrue(statusCardSays(whichStatus: 1, executables: ["/opt/homebrew/bin/ffmpeg"]))
    }

    /// 文案与「状态卡只报可用性」（UI-SPEC §12）——版本串属 Phase 6。
    func testLabelIsAvailableOrNotInstalledOnly() {
        XCTAssertEqual(FFmpegAvailability.label(available: true), "可用")
        XCTAssertEqual(FFmpegAvailability.label(available: false), "未安装")
    }
}