import XCTest
@testable import PicCore

/// 「该不该弹文件夹选择框」的纯函数判据（Plan 04-04 T2 / SYS-03 / SOURCE-07 / T-04-19）。
///
/// 不 import AppKit、不依赖 fixtures/ —— 干净 clone 上必须绿。
/// setUp/tearDown 形状沿用 SettingsStoreTests（独立 suite + unsetenv）：
/// 输入要能表达 `PIC_SOURCE_FOLDER` 那一级（Phase 2 的三级优先），
/// 测试进程里那个环境变量必须先摘掉，免得外部环境漏进来。
@MainActor
final class FolderRequestPolicyTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        unsetenv(SettingsStore.envSourceFolderKey)
    }

    override func tearDown() async throws {
        unsetenv(SettingsStore.envSourceFolderKey)
        try await super.tearDown()
    }

    func testEmptySourceFolderAndNoEnvOverrideRequestsFolder() {
        XCTAssertTrue(FolderRequestPolicy.shouldRequestFolder(sourceFolder: "", envOverride: nil),
                      "首次启动（SYS-03）：没选过目录必须弹框")
    }

    func testWhitespaceOnlySourceFolderIsTreatedAsUnconfigured() {
        XCTAssertTrue(FolderRequestPolicy.shouldRequestFolder(sourceFolder: "   ", envOverride: nil),
                      "纯空白的偏好值视同未配置 —— 否则产品永远不再弹框，用户被永久卡死（T-04-19：这条不会报错，只会静默失效）")
    }

    func testConfiguredSourceFolderDoesNotRequestFolder() {
        XCTAssertFalse(FolderRequestPolicy.shouldRequestFolder(sourceFolder: "/Users/someone/Movies/视频壁纸",
                                                               envOverride: nil),
                       "已配置过目录就不该再打扰（SOURCE-07）")
    }

    func testEnvOverrideSuppressesTheRequest() {
        XCTAssertFalse(FolderRequestPolicy.shouldRequestFolder(sourceFolder: "", envOverride: "/from/env"),
                       "开发期环境变量已给目录时不得弹框（否则挡住自动化）")
        XCTAssertFalse(FolderRequestPolicy.shouldRequestFolder(sourceFolder: "/configured", envOverride: "/from/env"),
                       "PIC_SOURCE_FOLDER 这一级压过偏好值（Phase 2 三级优先）")
    }

    func testIsAcceptableSelectionRejectsNilAndRegularFiles() {
        XCTAssertFalse(FolderRequestPolicy.isAcceptableSelection(nil),
                       "取消面板（nil）必须被拒")
        // 测试二进制自己必定存在且是普通文件 —— 不依赖 fixtures/（干净 clone 上没有）。
        let fileURL = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
        XCTAssertFalse(FolderRequestPolicy.isAcceptableSelection(fileURL),
                       "指向普通文件的 URL 必须被拒（否则扫描器在文件上枚举，表现是「选对了却没反应」）")
    }
}
