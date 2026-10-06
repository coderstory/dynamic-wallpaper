import XCTest
@testable import PicCore

/// mkv/avi/webm 白名单、`Converted/` 精确排除、符号链接跳过。树全部用临时目录 + UUID 自造，绝不碰真实片库目录。
final class TranscodeCandidateFilterTests: XCTestCase {

    private var root: URL!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("p6-filter-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        root = nil
        super.tearDown()
    }

    /// 在 root 下造一个几字节的占位文件（支持多级相对路径）。
    @discardableResult
    private func makeFile(_ relativePath: String) -> URL {
        let parts = relativePath.split(separator: "/").map(String.init)
        var url: URL = root
        for (index, part) in parts.enumerated() {
            url = url.appendingPathComponent(part, isDirectory: index < parts.count - 1)
        }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? "placeholder".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testNonNativeFilesOutsideConvertedAreCandidates() {
        makeFile("a.mkv")
        makeFile("B.AVI")
        makeFile("c.webm")
        makeFile("sub/d.mkv")
        let candidates = TranscodeCandidateFilter.candidates(in: root)
        XCTAssertEqual(candidates.count, 4, "mkv / AVI(大写) / webm / 子目录 mkv 全部应被收（白名单大小写不敏感）")
        // 按完整路径排序：'B'(66) 排在 'a'(97) 之前 —— 跨平台确定的字节序。
        XCTAssertEqual(candidates.map { $0.lastPathComponent }, ["B.AVI", "a.mkv", "c.webm", "d.mkv"],
                       "结果按 url.path 排序")
    }

    func testFilesInsideConvertedAreNeverCandidates() {
        makeFile("Converted/x.mkv")
        makeFile("Converted/deep/y.avi")
        XCTAssertEqual(TranscodeCandidateFilter.candidates(in: root), [],
                       "Converted/ 子树整棵排除（TRANS-05 第一闸门）")
    }

    func testLowercaseConvertedDirIsAlsoExcludedNotSubstring() {
        makeFile("converted/x.mkv")
        makeFile("converted-lower/z.mkv")
        let names = Set(TranscodeCandidateFilter.candidates(in: root).map { $0.lastPathComponent })
        XCTAssertFalse(names.contains("x.mkv"),
                       "小写 converted/ 也必须排除 —— 目录名大小写不敏感全等")
        // 后半句才有牙齿：只判前半句的话，「子串匹配」的假实现照样绿。
        XCTAssertTrue(names.contains("z.mkv"),
                       "converted-lower/ 只是子串相似，z.mkv 必须照收 —— 排除不是子串匹配")
    }

    func testNativeFormatsAndTmpAreNotCandidates() {
        makeFile("a.mp4")
        makeFile("b.mov")
        makeFile("c.m4v")
        makeFile("done.mkv.mp4.tmp")
        XCTAssertEqual(TranscodeCandidateFilter.candidates(in: root), [],
                       "原生格式与 .tmp 中间态都不是转码候选（第二闸门 + SC#5 半成品不进）")
    }

    func testSymlinkedCandidatesAreSkipped() throws {
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("p6-outside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let target = outside.appendingPathComponent("secret.mkv")
        try "outside secret".write(to: target, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("link.mkv"), withDestinationURL: target)
        XCTAssertEqual(TranscodeCandidateFilter.candidates(in: root), [],
                       "指向根外的符号链接候选必须跳过（T-06-03，与 04-01 扫描器同规则）")
        try? FileManager.default.removeItem(at: outside)
    }

    func testMissingRootReturnsEmptyWithoutThrowing() {
        let missing = root.appendingPathComponent("no-such-\(UUID().uuidString)", isDirectory: true)
        XCTAssertEqual(TranscodeCandidateFilter.candidates(in: missing), [],
                       "根不存在 → 空数组，不抛（候选发现是尽力而为）")
    }
}
