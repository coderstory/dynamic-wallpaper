// swift-tools-version:6.0
import PackageDescription

// D-01：SwiftPM 包定义（Phase 5 才引入 .xcodeproj 以承载 XCUITest）。
// 本 Phase 零第三方依赖（下方包级依赖列表为空），swift build 不触网。
let package = Package(
    name: "Pic",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Pic", targets: ["PicApp"]),
        .library(name: "PicCore", targets: ["PicCore"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "PicCore",
            // Swift 6 语言模式会把 @MainActor + NSObject + SwiftUI 组合报成并发错误。
            // Phase 1 已实跑验证 v5 形状：swift build + swift test 全绿。
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "PicApp",
            dependencies: ["PicCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "PicCoreTests",
            dependencies: ["PicCore"],
            // 测试框架锁死为 XCTest：swift test 的汇总串是
            // "Executed N tests, with 0 failures"，Swift Testing 打的是另一种串。
            // SwiftPM 对 XCTest 无需额外声明，测试文件里 import XCTest 即被自动发现。
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
