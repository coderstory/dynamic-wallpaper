import Foundation

/// 供 `MediaLibraryTests` 复用的 fixture 树构建器（**非 XCTestCase**）。
///
/// 结构与 `scripts/make-media-fixture-tree.sh` 的产物逐项一致 —— 两处的树若有漂移，
/// 单测与探针的读数就会对不上。单测走 `FakeAssetProbe`，因此视频文件只需占位内容；
/// 本类完全不碰 AVFoundation，干净 clone 上 `swift test` 也绿。
///
/// 每个条目的存在理由（不是靠文件名能看出来的那些）：
///
/// | 路径 | 存在理由 |
/// |---|---|
/// | `B.MOV` | 扩展名匹配必须大小写不敏感 |
/// | `broken.mp4` | 假探针拒绝它 → 走「视频轨拒绝」这条路 |
/// | `sub/skip.mkv` `sub/y.avi` `sub/z.webm` | 假探针会接受它们，只靠扩展名拒绝（反证） |
/// | `sub/deep/deeper/d.MP4` | 三次目录深度 |
/// | `Converted/out.mp4` | 假探针会接受，但整棵被排除 |
/// | `converted-lower/keep.mp4` | **必须收** —— 排除是目录名精确匹配，不是子串 |
/// | `视频壁纸/e.mp4` | 目录名含空格与中文，URL 的字符串形态会被百分号编码，只能走 `path` |
/// | `link-out.mp4` → `<tmp>/pic-outside-<uuid>/secret.mp4` | 根外符号链接要排除 |
///
/// 期望读数：`acceptedByExtension == 8`、`excludedByConverted == 1`、
/// `rejectedByProbe == 1`、`items.count == 6`（a / B.MOV / c.m4v / d.MP4 /
/// converted-lower-keep / 视频壁纸-e）。`scannedEntryCount` 不断言精确值。
enum MediaFixtureTree {

    struct Tree {
        let rootURL: URL
        let outsideRootURL: URL
        let cjkDirectoryURL: URL
        var rootPath: String { rootURL.path }
    }

    static func makeTree() throws -> Tree {
        let fm = FileManager.default
        let base = fm.temporaryDirectory
        let root = base.appendingPathComponent("pic-media-\(UUID().uuidString)", isDirectory: true)
        let outside = base.appendingPathComponent("pic-outside-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)

        let entries: [(relativePath: String, content: String)] = [
            ("a.mp4", "video placeholder"),
            ("B.MOV", "video placeholder"),
            ("notes.txt", "plain text"),
            ("broken.mp4", "ascii text that is not a video"),
            ("sub/c.m4v", "video placeholder"),
            ("sub/skip.mkv", "mkv placeholder"),
            ("sub/y.avi", "avi placeholder"),
            ("sub/z.webm", "webm placeholder"),
            ("sub/deep/deeper/d.MP4", "video placeholder"),
            ("Converted/out.mp4", "video placeholder"),
            ("converted-lower/keep.mp4", "video placeholder"),
            ("视频壁纸/e.mp4", "video placeholder"),
        ]
        for e in entries {
            let parts = e.relativePath.split(separator: "/")
            var url = root
            for (index, part) in parts.enumerated() {
                let isLast = index == parts.count - 1
                url = isLast
                    ? url.appendingPathComponent(String(part))
                    : url.appendingPathComponent(String(part), isDirectory: true)
            }
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try e.content.write(to: url, atomically: true, encoding: .utf8)
        }

        let secret = outside.appendingPathComponent("secret.mp4")
        try "outside secret".write(to: secret, atomically: true, encoding: .utf8)
        try fm.createSymbolicLink(at: root.appendingPathComponent("link-out.mp4"), withDestinationURL: secret)

        return Tree(
            rootURL: root,
            outsideRootURL: outside,
            cjkDirectoryURL: root.appendingPathComponent("视频壁纸", isDirectory: true)
        )
    }

    static func remove(_ tree: Tree) {
        let fm = FileManager.default
        try? fm.removeItem(at: tree.rootURL)
        try? fm.removeItem(at: tree.outsideRootURL)
    }
}