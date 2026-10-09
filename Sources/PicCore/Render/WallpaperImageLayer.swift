import AppKit
import CoreGraphics
import QuartzCore

/// 图片壁纸的渲染层。**常驻、与 `AVPlayerLayer` 并列**，切换靠 `isHidden` 而不是
/// `add/removeSublayer` —— 反复增删子层会和 `HostView.layout()`（按 bounds 铺满两层）打架，
/// 表现为换来源后有一层停在旧尺寸上。
///
/// 四种适配模式**全部自己画**，不用 `contentsGravity`：`fill` / `fit` / `center` 系统确实有对应
/// gravity，但 `tile` 没有，两套机制并存会让「换适配模式」变成换绘制路径，
/// 出问题时分不清是几何算错还是 gravity 选错。
public final class WallpaperImageLayer: CALayer {

    private var image: CGImage?
    private var fit: ImageFit = .fill

    public override init() {
        super.init()
        // 窗口换屏重建后 bounds 会变，不重画的话图片会停在上一块画布的落位上。
        needsDisplayOnBoundsChange = true
    }

    public override init(layer: Any) {
        super.init(layer: layer)
        needsDisplayOnBoundsChange = true
    }

    required init?(coder: NSCoder) { nil }

    /// 赋图。**解码必须在调用方完成**（后台线程）：这里只接受已解好的 `CGImage`，
    /// 主线程不解图 —— 一张 4K HEIC 的解码足以让界面卡一帧。
    public func setImage(_ image: CGImage?, fit: ImageFit) {
        self.image = image
        self.fit = fit
        setNeedsDisplay()
    }

    /// 换铺法。**只翻 `fit`、保留 `image`** —— 语义是「同一张图换个摆法」，用户在设置窗里改
    /// 适配方式时要的就是当场重绘。不用「先 `setImage(nil, fit:)` 再重设」那条路：清图会让画布
    /// 闪一下黑，而且重新上图的成本全在解码，而这个 CGImage 已经在手上了。
    public func setFit(_ fit: ImageFit) {
        self.fit = fit
        setNeedsDisplay()
    }

    public override func draw(in ctx: CGContext) {
        guard let image, bounds.width > 0, bounds.height > 0 else { return }

        let placement = ImageFitGeometry.placement(
            imageWidth: Double(image.width), imageHeight: Double(image.height),
            canvasWidth: Double(bounds.width), canvasHeight: Double(bounds.height),
            fit: fit)

        ctx.saveGState()
        // 几何给的是**左上原点**；CG 上下文在 `isGeometryFlipped == false` 时原点在左下，
        // 翻一次即可直接画。不能假定宿主视图的 flipped 状态 —— 它随 layer 树而变，
        // 假定错了的表现是图片上下颠倒。
        if !isGeometryFlipped {
            ctx.translateBy(x: 0, y: bounds.height)
            ctx.scaleBy(x: 1, y: -1)
        }
        let rect = CGRect(x: placement.rect.x, y: placement.rect.y,
                          width: placement.rect.w, height: placement.rect.h)
        if placement.tiles {
            ctx.draw(image, in: rect, byTiling: true)
        } else {
            ctx.draw(image, in: rect)
        }
        ctx.restoreGState()
    }
}
