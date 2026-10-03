import Foundation

/// 一次扫描的结果。每个计数一个独立字段：『扫了多少条』与『收了多少条』
/// 必须能分开打点，任何一个合并都会让探针输出无法定位是哪一道过滤器吃掉的条目。
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

    /// 最终真的能播的条数。
    public var playableCount: Int { items.count }
}

/// 媒体库扫描内核。只做文件系统遍历与探针调用并返回数据；任何窗口操作是
/// `WallpaperWindowController` 的事。本文件**不 import AppKit / SwiftUI** ——
/// 那会让分层判据被自己的 import 作废。
@MainActor
public final class MediaLibrary {

    /// 扩展名白名单（小写、无点、大小写不敏感）—— SOURCE-03。
    public static let allowedExtensions: Set<String> = ["mp4", "mov", "m4v"]

    /// 转码产物目录名。该目录被**整棵排除**，且比对是目录名**精确匹配**
    ///（converted-lower 不在排除之列）。
    public static let excludedDirectoryName = "Converted"

    private let probe: any VideoAssetProbe
    private let entryCap: Int

    private var cached: MediaLibraryReport?
    private var lastError: NSError?

    /// 真正执行过的扫描次数（缓存命中不算）。SOURCE-05 的可测读数。
    public private(set) var scanCount = 0

    /// `entryCap` 是 init 参数（不是 static let）：单测要能把它压到很小的值来验证
    /// 「超过上限被截断且如实上报」。
    public init(probe: any VideoAssetProbe = AVFoundationAssetProbe(), entryCap: Int = 5000) {
        self.probe = probe
        self.entryCap = entryCap
    }

    public func invalidateCache() {
        cached = nil
    }

    /// 递归扫描一个目录。`useCache: true` 时第二次起直接返回内存缓存
    ///（明确 `invalidateCache()` 后才触发真正重扫）。
    public func scan(folder: URL, useCache: Bool = true) async throws -> MediaLibraryReport {
        if useCache, let cached {
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
                // 必须返回 true：跳过那一项、继续遍历。返回 false 会让一次无权限
                // 子目录提前终止整趟扫描。
                self.lastError = err as NSError
                return true
            }
        )
        guard let enumerator else {
            throw MediaLibraryError.folderUnreadable
        }

        while let entry = enumerator.nextObject() as? URL {
            scanned += 1
            if scanned > entryCap {
                capped = true
                break
            }

            // 符号链接一律不跟进：既挡「指向根外的符号链接」，也挡「符号链接目录」
            // （本机实测符号链接的 isRegularFile 为 false、isSymbolicLink 为 true）。
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
            let isInsideConverted = entry.pathComponents.contains { component in
                component.caseInsensitiveCompare(Self.excludedDirectoryName) == .orderedSame
            }
            if isInsideConverted {
                excludedByConverted += 1
                continue
            }

            // 越界兜底：与上面的精确匹配重复是故意的纵深 —— 符号链接解析后的真实路径
            // 必须仍在根内，否则排除。
            let resolved = entry.resolvingSymlinksInPath().standardizedFileURL.path
            guard resolved.hasPrefix(rootRealPath + "/") else {
                excludedByContainment += 1
                continue
            }

            if await probe.hasVideoTrack(entry) {
                items.append(VideoItem(url: entry))
            } else {
                rejectedByProbe += 1
            }
        }

        // 按完整路径排序（不是 lastPathComponent）—— 跨子目录按文件名排得到的顺序
        // 对用户毫无意义。
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
        scanCount += 1
        return report
    }

    public enum MediaLibraryError: Error, Equatable {
        case folderMissing
        case folderUnreadable
    }
}