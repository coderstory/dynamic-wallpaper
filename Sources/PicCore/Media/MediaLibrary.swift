import Foundation

/// 一次扫描的结果。各阶段计数必须分字段记录：合并任何一个都会让「是哪一道过滤器吃掉的条目」无法定位。
public struct MediaLibraryReport: Equatable, Sendable {
    public let rootPath: String
    public let scannedEntryCount: Int
    public let acceptedByExtension: Int
    public let extensionRejected: Int
    public let excludedByConverted: Int
    public let excludedByContainment: Int
    public let rejectedByProbe: Int
    public let skippedByEntryCap: Bool
    public let items: [VideoItem]

    public var playableCount: Int { items.count }
}

/// 媒体库扫描内核：只做文件系统遍历与探针调用并返回数据，窗口操作是 `WallpaperWindowController` 的事。本文件**不 import AppKit / SwiftUI** —— 那会让分层判据被自己的 import 作废。
@MainActor
public final class MediaLibrary {

    /// 扩展名白名单（小写、无点、大小写不敏感）。
    public static let allowedExtensions: Set<String> = ["mp4", "mov", "m4v"]

    /// 转码产物目录名。被**整棵排除**，且比对是目录名**精确匹配**（`converted-lower` 不在排除之列）。`nonisolated`：后台队列的非隔离上下文要引用它。
    nonisolated public static let excludedDirectoryName = "Converted"

    /// 目录名大小写不敏感精确匹配 `Converted`（不是子串匹配）。`MediaLibrary` / `FpsTranscodeQueue` /
    /// `TranscodeCandidateFilter` 三处共用这一份判定，避免「排除规则」漂移导致漏扫或重复扫。
    nonisolated public static func isInsideConverted(_ url: URL) -> Bool {
        url.pathComponents.contains {
            $0.caseInsensitiveCompare(Self.excludedDirectoryName) == .orderedSame
        }
    }

    /// 探测阶段的并发上限。**别调大**：探测受磁盘 IO 限制，本机只有一块盘，
    /// 放开并发只会把 IO/CPU 打满而不更快；调小则首屏延迟线性变长。
    private static let probeConcurrency = 4

    private let probe: any VideoAssetProbe
    private let entryCap: Int

    private var cached: MediaLibraryReport?
    /// 缓存对应的目录（standardized 路径）。换目录后必须重扫，不能拿旧目录的 report 顶数。
    private var cachedRootPath: String?
    private var lastError: NSError?

    /// 真正执行过的扫描次数（缓存命中不算）。
    public private(set) var scanCount = 0

    /// `entryCap` 是 init 参数而非 static：调用方要能把它压小来验证「超过上限被截断且如实上报」。
    public init(probe: any VideoAssetProbe = AVFoundationAssetProbe(), entryCap: Int = 5000) {
        self.probe = probe
        self.entryCap = entryCap
    }

    /// 磁盘上有任何变化（新增/删除/转码或降帧产物落地）后必须先调它再重扫，否则 `scan` 默认吃缓存、拿回上一轮 report，新产物永远看不见。
    public func invalidateCache() {
        cached = nil
        cachedRootPath = nil
    }

    /// 递归扫描一个目录。`useCache: true` 时第二次起直接返回内存缓存。
    public func scan(folder: URL, useCache: Bool = true) async throws -> MediaLibraryReport {
        // 缓存必须**按目录**判等：只判「有没有」会让换了目录的调用方拿到旧目录的 report。
        // 设置窗「选择…」换目录走的就是这条路径（`requestFolderNow` 不失效缓存）。
        if useCache, let cached, cachedRootPath == folder.standardizedFileURL.path {
            return cached
        }

        // 存在性检查一律走 path；喂 URL 的字符串形态会让含中文/空格的路径恒为假。
        guard FileManager.default.fileExists(atPath: folder.path) else {
            throw MediaLibraryError.folderMissing
        }

        // 根必须是目录而不是文件。真实文件路径在这里被挡出 .folderUnreadable；
        // 「存在但枚举不出来」由枚举器是否返回 nil 判同一条错误。
        var isDirectory: ObjCBool = false
        _ = FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory)
        guard isDirectory.boolValue else {
            throw MediaLibraryError.folderUnreadable
        }

        let rootRealPath = folder.resolvingSymlinksInPath().standardizedFileURL.path

        var scanned = 0
        var acceptedByExtension = 0
        var extensionRejected = 0
        var excludedByConverted = 0
        var excludedByContainment = 0
        var rejectedByProbe = 0
        var capped = false
        var items: [VideoItem] = []
        lastError = nil

        let enumOptions: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]
        let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: enumOptions,
            errorHandler: { _, err in
                // 必须返回 true：跳过那一项继续遍历，返回 false 会让一次无权限子目录提前终止整趟扫描。
                self.lastError = err as NSError
                return true
            }
        )
        guard let enumerator else {
            throw MediaLibraryError.folderUnreadable
        }

        // 第一段：纯同步筛选，把候选收齐。与探测分开是因为探测是这趟扫描唯一的重活，
        // 混在一起就没法给它定并发度。
        var candidates: [URL] = []
        while let entry = enumerator.nextObject() as? URL {
            scanned += 1
            if scanned > entryCap {
                capped = true
                break
            }

            // 符号链接一律不跟进：既挡「指向根外的符号链接」，也挡「符号链接目录」
            //（符号链接的 isRegularFile 为 false、isSymbolicLink 为 true）。
            guard let values = try? entry.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  values.isRegularFile == true,
                  values.isSymbolicLink != true else {
                continue
            }

            guard Self.allowedExtensions.contains(entry.pathExtension.lowercased()) else {
                extensionRejected += 1
                continue
            }
            acceptedByExtension += 1

            // 目录名精确匹配 Converted —— 不是子串匹配。
            if Self.isInsideConverted(entry) {
                excludedByConverted += 1
                continue
            }

            // 越界兜底，与上面的精确匹配重复是故意的纵深：符号链接解析后的真实路径必须仍在根内。
            let resolved = entry.resolvingSymlinksInPath().standardizedFileURL.path
            guard resolved.hasPrefix(rootRealPath + "/") else {
                excludedByContainment += 1
                continue
            }

            candidates.append(entry)
        }

        // 第二段：有界并发探测。首屏「壁纸出现」的延迟 = 候选数 × 单文件探测，串行时对视频数是**线性**的；
        // 这里把斜率压到 1/4。上限刻意是固定常数而不是「有多少发多少」：探测受磁盘 IO 限制，
        // 本机只有一块盘，放开并发只会把 IO/CPU 打满而不更快。
        let probe = self.probe
        await withTaskGroup(of: (URL, Bool).self) { group in
            var next = 0
            while next < candidates.count, next < Self.probeConcurrency {
                let url = candidates[next]
                next += 1
                group.addTask { (url, await probe.metadata(url).hasVideoTrack) }
            }
            // 每收一个补一个 —— 窗口始终填满到 probeConcurrency。
            while let (url, hasVideoTrack) = await group.next() {
                if hasVideoTrack {
                    items.append(VideoItem(url: url))
                } else {
                    rejectedByProbe += 1
                }
                if next < candidates.count {
                    let url = candidates[next]
                    next += 1
                    group.addTask { (url, await probe.metadata(url).hasVideoTrack) }
                }
            }
        }

        // 按完整路径排序而不是 lastPathComponent：跨子目录按文件名排出来的顺序对用户毫无意义。
        items.sort { $0.url.path < $1.url.path }

        let report = MediaLibraryReport(
            rootPath: folder.path,
            scannedEntryCount: scanned,
            acceptedByExtension: acceptedByExtension,
            extensionRejected: extensionRejected,
            excludedByConverted: excludedByConverted,
            excludedByContainment: excludedByContainment,
            rejectedByProbe: rejectedByProbe,
            skippedByEntryCap: capped,
            items: items
        )
        cached = report
        cachedRootPath = folder.standardizedFileURL.path
        scanCount += 1
        return report
    }

    public enum MediaLibraryError: Error, Equatable {
        case folderMissing
        case folderUnreadable
    }
}