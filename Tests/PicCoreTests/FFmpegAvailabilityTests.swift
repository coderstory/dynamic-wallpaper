import Foundation
import XCTest
@testable import PicCore

/// ffmpeg 可用性判定的单测（Plan 05-03 T1）。
///
/// ⚠️ 本文件**不依赖本机 PATH**：每条用例自建临时目录并注入权限位，干净 clone
/// 与任意 PATH 下读数一致。判定只看「可执行文件」，**零执行**（Phase 5 硬边界）——
/// 这里面的 `ffmpeg` 是占位文件，从不被运行过。
final class FFmpegAvailabilityTests: XCTestCase {

    private var sandbox: URL!

    override func setUp() async throws {
        sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("pic-ffmpeg-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: sandbox)
    }

    /// 造一个名字叫 ffmpeg 的占位文件并设权限位。内容与判定无关，只求 `isExecutableFile` 有对象可判。
    private func makeFfmpeg(in dir: URL, mode: Int) throws {
        let file = dir.appendingPathComponent("ffmpeg")
        try Data("#!".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: mode)],
                                              ofItemAtPath: file.path)
    }

    private func makeDir(_ name: String) throws -> URL {
        let dir = sandbox.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testExecutableFfmpegInSearchPathIsAvailable() throws {
        let dir = try makeDir("with")
        try makeFfmpeg(in: dir, mode: 0o755)
        XCTAssertTrue(FFmpegAvailability.resolve(searchPaths: [dir.path]))
    }

    func testMissingFfmpegYieldsUnavailable() throws {
        let dir = try makeDir("empty")
        XCTAssertFalse(FFmpegAvailability.resolve(searchPaths: [dir.path]))
    }

    /// 执行位是判定的一部分：有文件但 0644 等价于没装。
    func testNonExecutableFfmpegYieldsUnavailable() throws {
        let dir = try makeDir("noexec")
        try makeFfmpeg(in: dir, mode: 0o644)
        XCTAssertFalse(FFmpegAvailability.resolve(searchPaths: [dir.path]))
    }

    /// 畸形输入不抛不崩，只是「没找到」。
    func testEmptyAndMalformedPathsYieldUnavailable() {
        XCTAssertFalse(FFmpegAvailability.resolve(searchPaths: []))
        XCTAssertFalse(FFmpegAvailability.resolve(searchPaths: [""]))
        XCTAssertFalse(FFmpegAvailability.resolve(searchPaths: ["::", "", ":"]))
    }

    func testResolveFromPATHSplitsColonSeparatedDirs() throws {
        let missing = try makeDir("a")
        let found = try makeDir("b")
        try makeFfmpeg(in: found, mode: 0o755)
        XCTAssertTrue(FFmpegAvailability.resolveFromPATH(
            environment: ["PATH": "\(missing.path):\(found.path)"]))
        XCTAssertTrue(FFmpegAvailability.resolveFromPATH(
            environment: ["PATH": "\(missing.path)::\(found.path)"]))
        XCTAssertFalse(FFmpegAvailability.resolveFromPATH(environment: ["PATH": ""]))
        XCTAssertFalse(FFmpegAvailability.resolveFromPATH(environment: [:]))
    }

    /// 文案与「状态卡只报可用性」（UI-SPEC §12）——版本串属 Phase 6。
    func testLabelIsAvailableOrNotInstalledOnly() {
        XCTAssertEqual(FFmpegAvailability.label(available: true), "可用")
        XCTAssertEqual(FFmpegAvailability.label(available: false), "未安装")
    }
}
