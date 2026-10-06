import XCTest
@testable import PicCore

/// 全部是纯函数断言：不构造窗口、不碰 AVFoundation，换台机器也必须照样过 —— 决策层若是真的纯函数，就能在无屏幕、无播放器的环境里穷举它的全部输入空间。
@MainActor
final class LibraryAvailabilityTests: XCTestCase {

    func testUnconfiguredFolderWinsOverAnyScanOutcome() {
        XCTAssertEqual(
            LibraryAvailability.evaluate(folderConfigured: false, scanOutcome: .success(3)),
            .folderUnconfigured,
            "folderConfigured == false 必须压过任何扫描结果 —— 「还没选目录」不是「目录没了」"
        )
        XCTAssertEqual(
            LibraryAvailability.evaluate(folderConfigured: false, scanOutcome: .failure(.folderMissing)),
            .folderUnconfigured,
            "没选目录时不去问扫描结果，否则首次启动会看到一条误导性的降级理由"
        )
    }

    func testMissingFolderYieldsFolderMissingAndHidesWallpaper() {
        let state = LibraryAvailability.evaluate(folderConfigured: true, scanOutcome: .failure(.folderMissing))
        XCTAssertEqual(state, .folderMissing)
        XCTAssertFalse(state.shouldShowWallpaper, "目录没了必须隐藏壁纸窗口，露出系统原壁纸（D-11）")
        XCTAssertEqual(state.reasonToken, "folder_missing")
    }

    /// 不可读与目录没了刻意分成两条：合并就分不清坏的是哪个分支。
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

    func testZeroPlayableVideosYieldsNoPlayableVideos() {
        let state = LibraryAvailability.evaluate(folderConfigured: true, scanOutcome: .success(0))
        XCTAssertEqual(state, .noPlayableVideos)
        XCTAssertFalse(state.shouldShowWallpaper, "空列表不是错误，是正常状态：静默隐藏")
        XCTAssertEqual(state.reasonToken, "no_playable_videos")
    }

    func testPositiveCountYieldsPlaying() {
        for n in [1, 2] {
            let state = LibraryAvailability.evaluate(folderConfigured: true, scanOutcome: .success(n))
            XCTAssertEqual(state, .playing, "playableCount >= 1 即播放态")
            XCTAssertTrue(state.shouldShowWallpaper)
        }
        XCTAssertEqual(LibraryAvailability.token(.playing), "playing")
    }

    /// 从 `allCases` 运行时生成，不写死清单 —— 加一个 case 本条自动跟上。
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
