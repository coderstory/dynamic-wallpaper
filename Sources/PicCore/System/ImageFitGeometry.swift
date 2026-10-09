import Foundation

/// 图片落位的纯值计算层，零 AppKit / CoreGraphics / AVFoundation。**不含任何判定阈值。**
///
/// 坐标系：**左上角原点、y 向下**，与 `CGImage` 的绘制方向一致（`CGContext` 默认原点在左下，
/// 由调用方在画之前翻转一次，不要让本文件去猜 layer 是否 flipped）。
public enum ImageFitGeometry {

    /// 一次落位的结果。
    public struct Placement: Equatable, Sendable {
        /// 落位矩形，相对画布左上角。`fill` 时它可以超出画布（超出部分由层裁掉）——
        /// 这是「填充」的定义，不是越界 bug。
        public let rect: ScreenRect
        /// 平铺标记。为 true 时 `rect` 是**一块砖**（原始像素尺寸、贴左上角），
        /// 由调用方在裁剪区域内重复铺；这时 `rect` 不需要居中，居中会让平铺错位半块砖。
        public let tiles: Bool

        public init(rect: ScreenRect, tiles: Bool) {
            self.rect = rect
            self.tiles = tiles
        }
    }

    /// 四个模式共用同一条公式，只有 `scale` 的取法不同：
    /// `fill` 取 max（铺满、超出裁掉）/ `fit` 取 min（完整、留边）/ `center` 取 1（原始尺寸）。
    /// 平铺不走缩放 —— 缩放过的砖会露出接缝。
    public static func placement(imageWidth: Double, imageHeight: Double,
                                 canvasWidth: Double, canvasHeight: Double,
                                 fit: ImageFit) -> Placement {
        // 任一边非正就没有可画的矩形。降级成零矩形而不是返回 nil：调用方拿到 nil 还得自己造一条
        // 「什么都不画」的分支，两条路径里迟早有一条忘了处理。
        guard imageWidth > 0, imageHeight > 0, canvasWidth > 0, canvasHeight > 0 else {
            return Placement(rect: ScreenRect(x: 0, y: 0, w: 0, h: 0), tiles: false)
        }

        if fit == .tile {
            return Placement(rect: ScreenRect(x: 0, y: 0, w: imageWidth, h: imageHeight), tiles: true)
        }

        let scale: Double
        switch fit {
        case .fill: scale = max(canvasWidth / imageWidth, canvasHeight / imageHeight)
        case .fit: scale = min(canvasWidth / imageWidth, canvasHeight / imageHeight)
        case .center: scale = 1
        case .tile: scale = 1   // 上面已返回，这里只为 switch 穷举
        }

        let w = imageWidth * scale
        let h = imageHeight * scale
        return Placement(
            rect: ScreenRect(x: (canvasWidth - w) / 2, y: (canvasHeight - h) / 2, w: w, h: h),
            tiles: false)
    }
}
