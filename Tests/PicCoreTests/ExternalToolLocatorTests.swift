import XCTest
@testable import PicCore

/// 全部走 Fake 注入，不真跑 which（`ProcessWhichProbe` 不在本文件实例化）；样本路径硬编码、不依赖 `fixtures/`，干净 clone 上 `swift test` 也必须绿。
final class ExternalToolLocatorTests: XCTestCase {

    private func makeLocator(
        whichStatus: Int32 = 1,
        whichPath: String? = nil,
        executables: Set<String> = []
    ) -> ExternalToolLocator {
        ExternalToolLocator(
            which: FakeWhich(status: whichStatus, path: whichPath),
            fileSystem: FakeFS(executables: executables)
        )
    }

    func testAvailableWhenHomebrewPathExists() {
        let locator = makeLocator(
            whichStatus: 1,
            executables: ["/opt/homebrew/bin/ffmpeg"]
        )
        XCTAssertEqual(locator.locate(), .available(path: "/opt/homebrew/bin/ffmpeg"))
    }

    func testAvailableWhenIntelBrewPathExists() {
        let locator = makeLocator(
            whichStatus: 1,
            executables: ["/usr/local/bin/ffmpeg"]
        )
        XCTAssertEqual(locator.locate(), .available(path: "/usr/local/bin/ffmpeg"))
    }

    func testAvailableWhenWhichSucceeds() {
        let locator = makeLocator(
            whichStatus: 0,
            whichPath: "/some/custom/ffmpeg",
            executables: []
        )
        XCTAssertEqual(locator.locate(), .available(path: "/some/custom/ffmpeg"))
    }

    func testUnavailableWhenNothingFound() {
        let locator = makeLocator(whichStatus: 1, executables: [])
        XCTAssertEqual(locator.locate(), .unavailable)
    }

    func testNotExecutableProbePathIsSkippedNotFatal() {
        let locator = makeLocator(
            whichStatus: 1,
            executables: ["/usr/local/bin/ffmpeg"]
        )
        XCTAssertEqual(locator.locate(), .available(path: "/usr/local/bin/ffmpeg"))
    }

    func testGuiMinimalPathStillFindsHomebrewInstall() {
        let locator = makeLocator(
            whichStatus: 1,
            executables: ["/opt/homebrew/bin/ffmpeg"]
        )
        XCTAssertEqual(locator.locate(), .available(path: "/opt/homebrew/bin/ffmpeg"))
    }
}
