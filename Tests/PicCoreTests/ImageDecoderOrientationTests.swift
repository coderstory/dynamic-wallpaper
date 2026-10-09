import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import PicCore

/// EXIF orientation 摆正口径的回归测试。
///
/// 只测「decode 返回的 CGImage 已按 EXIF 摆正」，不测解码缓存。
/// 口径约定见 `ImageDecoder.decode` 与 `ImageIOSizeProbe` 的成对注释：显示用摆正后宽高，
/// 档位判定用存储像素 —— 这里验证的是显示侧那一半。
final class ImageDecoderOrientationTests: XCTestCase {

    private var root: URL!

    override func setUp() async throws {
        try await super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pic-orientation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
        root = nil
        try await super.tearDown()
    }

    /// 生成 2 宽 × 3 高的实心 JPEG，把 EXIF orientation 写进属性。
    private func makeFixture(name: String, orientation: Int) throws -> URL {
        let width = 2, height = 3
        let ctx = CGContext(data: nil, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = ctx.makeImage()!

        let url = root.appendingPathComponent(name)
        let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil)!
        let properties = [kCGImagePropertyOrientation: orientation] as CFDictionary
        CGImageDestinationAddImage(dest, image, properties)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return url
    }

    /// orientation = 6（Right, 90° CW）：存储 2×3，摆正后宽高互换为 3×2。
    func testDecodeAppliesRightOrientationBySwappingDimensions() throws {
        let url = try makeFixture(name: "right.jpg", orientation: 6)
        let decoded = try XCTUnwrap(ImageDecoder.decode(url: url))
        XCTAssertEqual(decoded.width, 3, "摆正后宽应是存储的高")
        XCTAssertEqual(decoded.height, 2, "摆正后高应是存储的宽")
    }

    /// 对照组：orientation = 1（Up）不解重排路径，存储 2×3 解出来还是 2×3。
    func testDecodeKeepsDimensionsForUpOrientation() throws {
        let url = try makeFixture(name: "up.jpg", orientation: 1)
        let decoded = try XCTUnwrap(ImageDecoder.decode(url: url))
        XCTAssertEqual(decoded.width, 2)
        XCTAssertEqual(decoded.height, 3)
    }
}
