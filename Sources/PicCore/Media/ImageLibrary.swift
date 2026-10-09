import Foundation
import ImageIO

/// 一个被扫描器接受的图片条目。尺寸是**参与判定**的两个维度，不是装饰：
/// 换档位要能立刻重算，不能回磁盘再读一遍。
public struct ImageItem: Equatable, Sendable {
    public let url: URL
    public let pixelWidth: Int
    public let pixelHeight: Int

    public init(url: URL, pixelWidth: Int, pixelHeight: Int) {
        self.url = url
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }

    /// 判定口径是**总像素量**（宽 × 高），UI 的三格统计也按它切分。
    public var pixels: Int { pixelWidth * pixelHeight }
}

/// 一次图片扫描的结果。各阶段计数必须分字段记录：合并任何一个都会让「是哪一道过滤器吃掉的条目」无法定位。
public struct ImageLibraryReport: Equatable, Sendable {
    public let rootPath: String
    public let scannedEntryCount: Int
    public let acceptedByExtension: Int
    public let extensionRejected: Int
    /// 扩展名对了但读不出像素尺寸（损坏、不是真图、无权限）。**单独记**：
    /// 混进「低于档位」会让用户以为自己的图太小，实际是文件打不开。
    public let undecodable: Int
    public let excludedByContainment: Int
    public let skippedByEntryCap: Bool
    /// 通过档位的条目，即真正参与轮播的那些。
    public let items: [ImageItem]

    /// 受支持且能解码的图片总数（三格统计第一格）。
    public var total: Int { acceptedByExtension - undecodable }
    /// 三格统计第二格：将参与轮播。
    public var passing: Int { items.count }
    /// 三格统计第三格：低于档位被忽略。
    public var filteredOut: Int { total - passing }
}

/// 图片尺寸探针，可注入。
public protocol ImageSizeProbe: Sendable {
    /// 读不出尺寸返回 nil —— 扫描器跳过这一条计入 `undecodable`，**不抛错、不中断整轮扫描**。
    func pixelSize(_ url: URL) async -> (width: Int, height: Int)?
}

/// 默认实现：只解析文件头取宽高，不解码整图。
///
/// ImageIO 的 `PixelWidth` / `PixelHeight` 是**存储尺寸，不应用 EXIF orientation**。
/// 对当前的「总像素量」口径无影响（宽高互换不改变乘积），但若哪天改成按**短边**判定，
/// 这里必须先按 orientation 交换宽高（orientation >= 5 时），否则竖图会拿成横尺寸。
public struct ImageIOSizeProbe: ImageSizeProbe {
    public init() {}

    public func pixelSize(_ url: URL) async -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else {
            return nil
        }
        return (width, height)
    }
}

/// 图片库扫描内核。与 `MediaLibrary` 同构（同一套遍历与缓存纪律），但**没有转码产物排除**：
/// 图片不经转码，目录里不存在 `Converted`。本文件不 import AppKit / SwiftUI。
@MainActor
public final class ImageLibrary {

    /// 扩展名白名单（小写、无点、大小写不敏感）。
    /// **不收 gif**：动图会把「图片模式」混回视频语义（帧率 / 时长 / 是否需要转码），
    /// 而图片模式的全部前提就是「静止、不需要解码器以外的东西」。
    public static let allowedExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "webp"]

    /// 探测并发上限。与视频侧同一取值：受磁盘 IO 限制，调大只会打满 IO 而不更快。
    private static let probeConcurrency = 4

    private let probe: any ImageSizeProbe
    private let entryCap: Int

    private var cached: ImageLibraryReport?
    /// 缓存对应的目录（standardized 路径）。
    private var cachedRootPath: String?
    /// 缓存对应的档位。**必须纳入缓存判等**：只按目录缓存的话，用户把档位从 4K 降到 1080P
    /// 会拿回上一轮的 report，「将参与轮播」永远不变。
    private var cachedMinPixels: Int?

    /// 真正执行过的扫描次数（缓存命中不算）。
    public private(set) var scanCount = 0

    public init(probe: any ImageSizeProbe = ImageIOSizeProbe(), entryCap: Int = 5000) {
        self.probe = probe
        self.entryCap = entryCap
    }

    /// 磁盘有变化或换档位后必须先调它，否则默认吃缓存、拿回上一轮 report。
    public func invalidateCache() {
        cached = nil
        cachedRootPath = nil
        cachedMinPixels = nil
    }

    /// 递归扫描图片目录。`minPixels` 是**总像素阈值**（宽 × 高的下限），低于它的图片不进 `items`。
    public func scan(folder: URL, minPixels: Int, useCache: Bool = true) async throws -> ImageLibraryReport {
        if useCache, let cached,
           cachedRootPath == folder.standardizedFileURL.path,
           cachedMinPixels == minPixels {
            return cached
        }

        // 存在性检查一律走 path；喂 URL 的字符串形态会让含中文/空格的路径恒为假。
        guard FileManager.default.fileExists(atPath: folder.path) else {
            throw MediaLibrary.MediaLibraryError.folderMissing
        }

        var isDirectory: ObjCBool = false
        _ = FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory)
        guard isDirectory.boolValue else {
            throw MediaLibrary.MediaLibraryError.folderUnreadable
        }

        let rootRealPath = folder.resolvingSymlinksInPath().standardizedFileURL.path

        var scanned = 0
        var acceptedByExtension = 0
        var extensionRejected = 0
        var excludedByContainment = 0
        var undecodable = 0
        var capped = false
        var items: [ImageItem] = []

        let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles],
            // 必须返回 true：跳过该项继续遍历。返回 false 会让一次无权限子目录提前终止整趟扫描。
            errorHandler: { _, _ in true }
        )
        guard let enumerator else {
            throw MediaLibrary.MediaLibraryError.folderUnreadable
        }

        var candidates: [URL] = []
        while let entry = enumerator.nextObject() as? URL {
            scanned += 1
            if scanned > entryCap {
                capped = true
                break
            }

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

            let resolved = entry.resolvingSymlinksInPath().standardizedFileURL.path
            guard resolved.hasPrefix(rootRealPath + "/") else {
                excludedByContainment += 1
                continue
            }

            candidates.append(entry)
        }

        let probe = self.probe
        let threshold = minPixels
        await withTaskGroup(of: (URL, Int, Int)?.self) { group in
            var next = 0
            while next < candidates.count, next < Self.probeConcurrency {
                let url = candidates[next]
                next += 1
                group.addTask {
                    guard let size = await probe.pixelSize(url) else { return nil }
                    return (url, size.width, size.height)
                }
            }
            while let result = await group.next() {
                if let (url, width, height) = result {
                    let item = ImageItem(url: url, pixelWidth: width, pixelHeight: height)
                    if item.pixels >= threshold {
                        items.append(item)
                    }
                    // 未过档的**不单独计数**：`filteredOut` 由 total - passing 推，
                    // 多加一个字段就多一处可能与之对不上的数字。
                } else {
                    undecodable += 1
                }
                if next < candidates.count {
                    let url = candidates[next]
                    next += 1
                    group.addTask {
                        guard let size = await probe.pixelSize(url) else { return nil }
                        return (url, size.width, size.height)
                    }
                }
            }
        }

        // 按完整路径排序而不是 lastPathComponent：跨子目录按文件名排出来的顺序对用户毫无意义。
        items.sort { $0.url.path < $1.url.path }

        let report = ImageLibraryReport(
            rootPath: folder.path,
            scannedEntryCount: scanned,
            acceptedByExtension: acceptedByExtension,
            extensionRejected: extensionRejected,
            undecodable: undecodable,
            excludedByContainment: excludedByContainment,
            skippedByEntryCap: capped,
            items: items
        )
        cached = report
        cachedRootPath = folder.standardizedFileURL.path
        cachedMinPixels = minPixels
        scanCount += 1
        return report
    }
}
