import XCTest
@testable import PicCore

final class ImageFitGeometryTests: XCTestCase {

    private func place(_ iw: Double, _ ih: Double, _ fit: ImageFit,
                       cw: Double = 1920, ch: Double = 1080) -> ImageFitGeometry.Placement {
        ImageFitGeometry.placement(imageWidth: iw, imageHeight: ih,
                                   canvasWidth: cw, canvasHeight: ch, fit: fit)
    }

    /// 竖图进宽屏：`fill` 按宽度撑满、上下各裁一半。
    func testFillScalesUpUntilBothSidesCovered() {
        let p = place(1000, 2000, .fill)
        XCTAssertEqual(p.rect.w, 1920, accuracy: 0.001)
        XCTAssertEqual(p.rect.h, 3840, accuracy: 0.001, "1.92 倍：高必然超出 1080")
        XCTAssertEqual(p.rect.x, 0, accuracy: 0.001)
        XCTAssertEqual(p.rect.y, -1380, accuracy: 0.001, "超出部分上下均分")
        XCTAssertFalse(p.tiles)
    }

    /// 横图（更宽的比例）进宽屏：这次轮到左右被裁。
    func testFillCropsTheOtherAxisForWideImage() {
        let p = place(4000, 2000, .fill)
        XCTAssertEqual(p.rect.h, 1080, accuracy: 0.001)
        XCTAssertEqual(p.rect.w, 2160, accuracy: 0.001)
        XCTAssertEqual(p.rect.x, -120, accuracy: 0.001)
        XCTAssertEqual(p.rect.y, 0, accuracy: 0.001)
    }

    /// `fill` 的不变量：铺满（两边都 ≥ 画布）、不变形（保持原比例）。
    func testFillAlwaysCoversCanvasAndKeepsAspect() {
        for (iw, ih) in [(1000, 2000), (4000, 2000), (1920, 1080), (300, 300)] {
            let p = place(Double(iw), Double(ih), .fill)
            XCTAssertGreaterThanOrEqual(p.rect.w, 1920 - 0.001, "\(iw)×\(ih)")
            XCTAssertGreaterThanOrEqual(p.rect.h, 1080 - 0.001, "\(iw)×\(ih)")
            XCTAssertEqual(p.rect.w / p.rect.h, Double(iw) / Double(ih), accuracy: 0.0001,
                           "\(iw)×\(ih) 不变形")
        }
    }

    func testFitScalesDownUntilWholeImageVisible() {
        let p = place(1000, 2000, .fit)
        XCTAssertEqual(p.rect.h, 1080, accuracy: 0.001)
        XCTAssertEqual(p.rect.w, 540, accuracy: 0.001)
        XCTAssertEqual(p.rect.x, 690, accuracy: 0.001)
        XCTAssertEqual(p.rect.y, 0, accuracy: 0.001)
    }

    /// `fit` 的不变量：完整可见（两边都 ≤ 画布）、不变形。
    func testFitAlwaysFitsInsideCanvasAndKeepsAspect() {
        for (iw, ih) in [(1000, 2000), (4000, 2000), (1920, 1080), (300, 300)] {
            let p = place(Double(iw), Double(ih), .fit)
            XCTAssertLessThanOrEqual(p.rect.w, 1920 + 0.001, "\(iw)×\(ih)")
            XCTAssertLessThanOrEqual(p.rect.h, 1080 + 0.001, "\(iw)×\(ih)")
            XCTAssertEqual(p.rect.w / p.rect.h, Double(iw) / Double(ih), accuracy: 0.0001)
        }
    }

    /// 居中**不缩放**：小图原尺寸居中，大图原尺寸溢出（不缩到能放下 —— 那是 `fit` 的活）。
    func testCenterNeverScales() {
        let small = place(100, 50, .center)
        XCTAssertEqual(small.rect.w, 100, accuracy: 0.001)
        XCTAssertEqual(small.rect.h, 50, accuracy: 0.001)
        XCTAssertEqual(small.rect.x, 910, accuracy: 0.001)
        XCTAssertEqual(small.rect.y, 515, accuracy: 0.001)

        let big = place(4000, 3000, .center)
        XCTAssertEqual(big.rect.w, 4000, accuracy: 0.001)
        XCTAssertEqual(big.rect.h, 3000, accuracy: 0.001)
        XCTAssertEqual(big.rect.x, -1040, accuracy: 0.001)
        XCTAssertEqual(big.rect.y, -960, accuracy: 0.001)
    }

    /// 平铺给的是**原始尺寸的一块砖、贴左上角**，不缩放也不居中 ——
    /// 缩放过的砖会露出接缝，居中的砖会让整片平铺错位半块。
    func testTileReturnsUnscaledTopLeftBrick() {
        let p = place(1000, 2000, .tile)
        XCTAssertTrue(p.tiles)
        XCTAssertEqual(p.rect.x, 0, accuracy: 0.001)
        XCTAssertEqual(p.rect.y, 0, accuracy: 0.001)
        XCTAssertEqual(p.rect.w, 1000, accuracy: 0.001)
        XCTAssertEqual(p.rect.h, 2000, accuracy: 0.001)
    }

    /// 退化输入不产生 NaN / 无穷：零矩形比「负数宽高的矩形」好处理得多。
    func testDegenerateInputsCollapseToEmptyRect() {
        for fit in ImageFit.allCases {
            XCTAssertEqual(place(0, 100, fit).rect.w, 0, "\(fit)")
            XCTAssertEqual(place(100, 0, fit).rect.h, 0, "\(fit)")
            let noCanvas = ImageFitGeometry.placement(imageWidth: 100, imageHeight: 100,
                                                      canvasWidth: 0, canvasHeight: 0, fit: fit)
            XCTAssertEqual(noCanvas.rect.w, 0, "\(fit)")
            XCTAssertFalse(noCanvas.tiles, "没有画布时连平铺也不该发生")
        }
    }
}
