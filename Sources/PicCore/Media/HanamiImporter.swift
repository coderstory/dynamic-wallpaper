import CryptoKit
import Foundation

/// 一次导入的读数。各道过滤器分字段 —— 合并任何一个都会让「是哪一道吃掉的条目」无法定位。
public struct HanamiImportReport: Sendable, Equatable {
    public var tombstoneSeededFromTrash: Int  // 废纸篓回填新插入数
    public var imported: Int
    public var skippedTombstone: Int
    public var skippedExisting: Int
    public var skippedDuplicate: Int          // 同轮 MD5 重复
    public var rejectedByProbe: Int
    public var failedCopy: Int
    public var sourceMissing: Bool            // 花見目录不存在或读不了，两者不区分
}

/// 把花見下载的视频导入所选视频目录；每次 run 先把废纸篓顶层 mp4 幂等哈希进墓碑。
/// `FileManager.default` 直接用，不造 copier/resolver 抽象（同 `MediaLibrary`）。
public struct HanamiImporter: Sendable {

    public static let defaultSourceDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Containers/whbalzac.Huajian/Data/Documents/Videos", isDirectory: true)

    public static let defaultTrashDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".Trash", isDirectory: true)

    private static let chunkSize = 1_048_576

    private let destinationDirectory: URL
    private let sourceDirectory: URL
    private let trashDirectory: URL?
    private let probe: any VideoAssetProbe
    private let ledger: HanamiVideoLedger

    public init(destinationDirectory: URL,
                sourceDirectory: URL = HanamiImporter.defaultSourceDirectory,
                trashDirectory: URL? = HanamiImporter.defaultTrashDirectory,
                probe: any VideoAssetProbe = AVFoundationAssetProbe(),
                ledger: HanamiVideoLedger = HanamiVideoLedger()) {
        self.destinationDirectory = destinationDirectory
        self.sourceDirectory = sourceDirectory
        self.trashDirectory = trashDirectory
        self.probe = probe
        self.ledger = ledger
    }

    /// 文件 MD5：视频几十上百 MB，整读进内存不可接受，按 1MB 流式分块。失败回 nil。
    public static func md5(at url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = Insecure.MD5()
        do {
            while let chunk = try handle.read(upToCount: Self.chunkSize), !chunk.isEmpty {
                hasher.update(data: chunk)
            }
        } catch {
            return nil
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// 串行导入：废纸篓回填 → 候选枚举 → 逐文件判定 → tmp 拷贝+rename → 报告。
    ///
    /// 预接受的竞态（不加锁，均一次性、下轮自愈）：① 导入跑时用户并发删某候选，本轮仍可能拷入，
    /// 下一轮导入即收敛（手动按钮，窗口仅数秒）；② 删除后、哈希完成前清空废纸篓 → 墓碑缺失，
    /// 该素材回来一次，用户再删即记。
    public func run() async -> HanamiImportReport {
        var report = HanamiImportReport(
            tombstoneSeededFromTrash: 0, imported: 0, skippedTombstone: 0, skippedExisting: 0,
            skippedDuplicate: 0, rejectedByProbe: 0, failedCopy: 0, sourceMissing: false)

        // 废纸篓回填：读不了（TCC）静默跳过，不拦导入。
        if let trashDirectory {
            report.tombstoneSeededFromTrash = seedTombstones(from: trashDirectory)
        }

        // 目录缺失或枚举失败（权限/IO）一律同一降级：summary 文案写「读不了或不存在」，用户无从也不必区分。
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: sourceDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]) else {
            report.sourceMissing = true
            return report
        }
        let candidates = contents
            .filter { url in
                guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                      values.isRegularFile == true,
                      values.isSymbolicLink != true else { return false }
                return url.pathExtension.lowercased() == "mp4"
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var seen = Set<String>()
        for url in candidates {
            let target = destinationDirectory.appendingPathComponent(url.lastPathComponent)
            // exists-check 必须先于拷贝：dest==source（用户把视频目录指到花見容器）时全部
            // skippedExisting，绝不往花見容器写 .tmp。放最前还省掉同名文件的哈希。
            if FileManager.default.fileExists(atPath: target.path) {
                report.skippedExisting += 1
                continue
            }
            guard let hash = Self.md5(at: url) else {
                report.failedCopy += 1
                continue
            }
            if ledger.contains(hash) {
                report.skippedTombstone += 1
                continue
            }
            if !seen.insert(hash).inserted {
                report.skippedDuplicate += 1
                continue
            }
            guard await probe.metadata(url).hasVideoTrack else {
                report.rejectedByProbe += 1
                continue
            }
            copy(url, to: target, into: &report)
        }
        return report
    }

    /// 拷贝 = copy 到 `<同名>.tmp` 再 moveItem（同卷 rename）。`.tmp` 不过扫描白名单，半截拷贝永不会被当成品。
    private func copy(_ url: URL, to target: URL, into report: inout HanamiImportReport) {
        let tmp = destinationDirectory.appendingPathComponent(url.lastPathComponent + ".tmp")
        do {
            try FileManager.default.copyItem(at: url, to: tmp)
        } catch {
            // 预置 tmp 是上次崩溃残留：清掉计失败（自愈，下轮重导）。
            try? FileManager.default.removeItem(at: tmp)
            report.failedCopy += 1
            return
        }
        do {
            try FileManager.default.moveItem(at: tmp, to: target)
            report.imported += 1
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            if (error as NSError).domain == NSCocoaErrorDomain,
               (error as NSError).code == NSFileWriteFileExistsError {
                report.skippedExisting += 1  // rename 时目标已被并发导入抢先放好：成品没丢，按已存在计。
            } else {
                report.failedCopy += 1
            }
        }
    }

    /// 把废纸篓顶层 mp4 幂等哈希进墓碑 —— 历史删除一次补齐、覆盖 Finder 删除。
    private func seedTombstones(from trash: URL) -> Int {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: trash,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]) else { return 0 }
        var seeded = 0
        for url in contents where url.pathExtension.lowercased() == "mp4" {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  let hash = Self.md5(at: url),
                  !ledger.contains(hash) else { continue }
            // 写失败静默：墓碑缺失的代价只是「素材多导一次」。
            if (try? ledger.insert(hash)) != nil { seeded += 1 }
        }
        return seeded
    }
}
