import XCTest
@testable import PicCore

/// `LibraryAvailability` 纯函数决策的单测（决策半边）。
///
/// 六条全部是纯函数断言：不构造窗口、不碰 AVFoundation —— 决策层若是真的纯函数，
/// 就必须能在无屏幕、无播放器的环境里穷举它的全部输入空间。
@MainActor
final class LibraryAvailabilityTests: XCTestCase {

    // MARK: - 1 · 没选目录时不去问扫描结果

    func testUnconfiguredFolderWinsOverAnyScanOutcome() {
        // 配 .success(3)：哪怕「扫描出了 3 条」，没选目录也是 folderUnconfigured
        XCTAssertEqual(
            LibraryAvailability.evaluate(folderConfigured: false, scanOutcome: .success(3)),
            .folderUnconfigured,
            "folderConfigured == false 必须压过任何扫描结果 —— 「还没选目录」不是「目录没了」"
        )
        // 配 .failure(.folderMissing)：同一条优先级
        XCTAssertEqual(
            LibraryAvailability.evaluate(folderConfigured: false, scanOutcome: .failure(.folderMissing)),
            .folderUnconfigured,
            "没选目录时不去问扫描结果，否则首次启动会看到一条误导性的降级理由"
        )
    }

    // MARK: - 2 · 目录没了

    func testMissingFolderYieldsFolderMissingAndHidesWallpaper() {
        let state = LibraryAvailability.evaluate(folderConfigured: true, scanOutcome: .failure(.folderMissing))
        XCTAssertEqual(state, .folderMissing)
        XCTAssertFalse(state.shouldShowWallpaper, "目录没了必须隐藏壁纸窗口，露出系统原壁纸（D-11）")
        XCTAssertEqual(state.reasonToken, "folder_missing")
    }

    // MARK: - 3 · 目录在但读不了（与第 2 条分开：两个错误各自可测）

    func testUnreadableFolderAlsoYieldsFolderMissing() {
        let state = LibraryAvailability.evaluate(folderConfigured: true, scanOutcome: .failure(.folderUnreadable))
        XCTAssertEqual(
            state,
            .folderMissing,
            "不可读与不存在对用户的处置相同：隐藏。合并成一条断言就分不清是哪个分支坏了"
        )
        XCTAssertFalse(state.shouldShowWallpaper)
        XCTAssertEqual(state.reasonToken, "folder_missing")
    }

    // MARK: - 4 · 扫描成功但一条能播的都没有

    func testZeroPlayableVideosYieldsNoPlayableVideos() {
        let state = LibraryAvailability.evaluate(folderConfigured: true, scanOutcome: .success(0))
        XCTAssertEqual(state, .noPlayableVideos)
        XCTAssertFalse(state.shouldShowWallpaper, "空列表不是错误，是正常状态：静默隐藏")
        XCTAssertEqual(state.reasonToken, "no_playable_videos")
    }

    // MARK: - 5 · 有可用视频

    func testPositiveCountYieldsPlaying() {
        for n in [1, 2] {
            let state = LibraryAvailability.evaluate(folderConfigured: true, scanOutcome: .success(n))
            XCTAssertEqual(state, .playing, "playableCount >= 1 即播放态")
            XCTAssertTrue(state.shouldShowWallpaper)
        }
        XCTAssertEqual(LibraryAvailability.token(.playing), "playing")
    }

    // MARK: - 6 · 四态的自洽性（从 allCases 运行时生成，不写死清单）

    func testAllCasesHaveDistinctTokensAndExactlyThreeHideWallpaper() {
        let all = LibraryState.allCases
        XCTAssertEqual(all.count, 4, "LibraryState 必须恰好四个 case")

        let tokens = Set(all.map(\.reasonToken))
        XCTAssertEqual(tokens.count, 4, "四个 reasonToken 必须两两不同，实际得到 \(all.map(\.reasonToken))")

        let hidden = all.filter { !$0.shouldShowWallpaper }
        XCTAssertEqual(hidden.count, 3, "恰好三个隐藏态、一个显示态，实际隐藏态是 \(hidden)")

        for state in all {
            XCTAssertEqual(LibraryAvailability.token(state), state.reasonToken,
                           "token(_:) 只回 reasonToken，不带任何路径或文件名（T-03-02 隐私纪律）")
        }
    }
}
