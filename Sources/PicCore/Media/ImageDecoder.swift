import CoreGraphics
import Foundation
import ImageIO

/// 图片解码。**同步、必须在后台线程调用** —— 一张 4K HEIC 的解码足以卡住主线程一帧，
/// 而轮换是定时触发的，卡帧会被读成「换壁纸时整个系统顿一下」。
public enum ImageDecoder {

    /// 解码一张图。返回 nil = 打不开（损坏 / 不是真图 / 无权限），调用方按「跳过这一张」处理，
    /// **不要抛错** —— 一张坏图不该中断整轮轮播。
    ///
    /// EXIF orientation **在本函数内应用**：返回的 CGImage 已经是摆正后的像素（竖拍图不再横躺）。
    /// 口径约定（两处注释成对出现，另一处在 `ImageIOSizeProbe`）：**显示用摆正后的宽高，
    /// 轮播档位的「总像素量」判定用存储像素** —— 宽高互换乘积不变，判定不受 EXIF 旋转影响，
    /// 不要为了「对齐显示尺寸」把两边改成同一口径。
    ///
    /// `shouldCacheImmediately` 是真需要的：不立刻缓存的话，解码结果会在首次绘制时才真正生成，
    /// 那一步落到主线程上，等于把后台解码的努力又还回去。
    public static func decode(url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            // 连属性头都读不出来：orientation 与像素尺寸都拿不到，退回原始路径。
            let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
            return CGImageSourceCreateImageAtIndex(source, 0, options)
        }

        // 非 Up 才走重摆正路径：绝大多数图是 Up，保留最快的直通解码。
        let orientation = (props[kCGImagePropertyOrientation] as? Int) ?? 1
        guard orientation != 1 else {
            let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
            return CGImageSourceCreateImageAtIndex(source, 0, options)
        }

        // 摆正路径：`CreateThumbnailAtIndex` + `WithTransform` 让 ImageIO 按 EXIF 旋转重绘，
        // 比 draw + CGAffineTransform 自己拼一遍少一个出错面。
        // `ThumbnailMaxPixelSize` 设成存储像素的最大边（先读真实尺寸）—— 约束是「不超过」而非
        // 「缩放到」，等于原尺寸时**不发生缩放**，只拿到旋转效果；不设的话缩略图路径会真把大图缩掉。
        let pixelWidth = (props[kCGImagePropertyPixelWidth] as? Int) ?? 0
        let pixelHeight = (props[kCGImagePropertyPixelHeight] as? Int) ?? 0
        let maxPixelSize = max(pixelWidth, pixelHeight)
        guard maxPixelSize > 0 else {
            let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
            return CGImageSourceCreateImageAtIndex(source, 0, options)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// 自己切到后台线程的 async 版本，供 MainActor 侧的调用方直接用。
    /// 同步那个版本给已经在后台的调用方（扫描、批量处理）。
    public static func decodeInBackground(_ url: URL) async -> CGImage? {
        await Task.detached(priority: .utility) { decode(url: url) }.value
    }
}
