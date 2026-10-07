// swift-tools-version:6.4
import PackageDescription

// D-01：SwiftPM 包定义（Phase 5 才引入 .xcodeproj 以承载 XCUITest）。
// 本 Phase 零第三方依赖（下方包级依赖列表为空），swift build 不触网。
let package = Package(
    name: "Pic",
    // 只支持 macOS 27。这行是交付产物的真实下限 —— build.sh 走 swift build，不走 xcodebuild。
    platforms: [.macOS(.v27)],
    products: [
        .executable(name: "Pic", targets: ["PicApp"]),
        .library(name: "PicCore", targets: ["PicCore"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "PicCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "PicApp",
            dependencies: ["PicCore"],
            // 这份 plist 由 build.sh 的 `cp` 打进 .app，不进 SwiftPM 的资源 bundle。
            // 不 exclude 的话 swift build 每次都打一行 "found 1 file(s) which are
            // unhandled; … Info.plist" —— 非 error，但它会掩盖真正的告警。
            // 刻意**不**改成 resources: 那样它会同时被复制进 Pic_PicApp.bundle/Info.plist，
            // 两处同名 plist 比一处更难排查。
            exclude: ["Resources/Info.plist"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "PicCoreTests",
            dependencies: ["PicCore"],
            // 测试框架锁死为 XCTest：swift test 的汇总串是
            // "Executed N tests, with 0 failures"，Swift Testing 打的是另一种串。
            // SwiftPM 对 XCTest 无需额外声明，测试文件里 import XCTest 即被自动发现。
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
