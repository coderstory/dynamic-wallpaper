import Foundation

/// 图片分辨率档位。`rawValue` 就是该档位的**总像素阈值**（宽 × 高），全仓唯一一份 ——
/// store 存的是这个绝对值而不是档位下标：将来加「8K」只是多一个 case，已存的值不用迁移。
///
/// 判定口径是**总像素量**（`宽 × 高 ≥ 阈值`），不是短边 / 长边。已知取舍：全景图
/// 8000×1200 能通过 4K 但只有 1200 高，铺满宽屏会被放大得很糊 —— 这是口径的代价，不是 bug。
public enum ImageResolutionTier: Int, CaseIterable, Sendable {
    /// 1920 × 1080
    case p1080 = 2_073_600
    /// 2560 × 1440。**不取 DCI 的 2048 × 1080**：它只比 1080P 高 6.6%，中间档等于不存在。
    case k2 = 3_686_400
    /// 3840 × 2160
    case k4 = 8_294_400

    /// 档位名，直接用作分段控件文案。
    public var label: String {
        switch self {
        case .p1080: return "1080P"
        case .k2: return "2K"
        case .k4: return "4K"
        }
    }

    public var pixels: Int { rawValue }
}
