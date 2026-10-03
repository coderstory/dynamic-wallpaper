import XCTest
@testable import PicCore

/// `MediaCoordinator` 单测 —— 降级路径的**执行半边**。
///
/// 文件内自带两个记录式替身（不 import AVFoundation / AppKit）：
/// 协调器只对着 `WallpaperPresenting` / `PlaybackStopping` 两个协议说话，
/// 所以整条「隐藏 → 恢复 → 再隐藏」的行为链都能在无屏幕环境下断言。
@MainActor
final class MediaCoordinatorTests: XCTestCase {

    final class RecordingPresenter: WallpaperPresenting {
        private(set) var showCount = 0
        private(set) var hideCount = 0
        func show() { showCount += 1 }
        func hide() { hideCount += 1 }
    }

    final class RecordingStopper: PlaybackStopping {
        private(set) var stopCount = 0
        func stopPlayback() { stopCount += 1 }
    }

    private var presenter: RecordingPresenter!
    private var stopper: RecordingStopper!
    private var coordinator: MediaCoordinator!

    override func setUp() async throws {
        try await super.setUp()
        presenter = RecordingPresenter()
        stopper = RecordingStopper()
        coordinator = MediaCoordinator(presenting: presenter, stopping: stopper)
    }

    override func tearDown() async throws {
        coordinator = nil
        stopper = nil
        presenter = nil
        try await super.tearDown()
    }

    // MARK: - 1 · 播放态只显示，从不停

    func testPlayingStateShowsWallpaperAndNeverStops() {
        let state = coordinator.apply(scanOutcome: .success(3), folderConfigured: true)

        XCTAssertEqual(state, .playing)
        XCTAssertEqual(coordinator.lastState, .playing)
        XCTAssertEqual(presenter.showCount, 1, "播放态必须显示壁纸窗口")
        XCTAssertEqual(presenter.hideCount, 0, "显示路径里不得混进隐藏")
        XCTAssertEqual(stopper.stopCount, 0, "播放态不得停播放器 —— 真实内容由 04-05 的 onAdvance 去 load，先有内容再显示")
    }

    // MARK: - 2 · 空列表：停 + 隐藏，各恰好一次

    func testEmptyLibraryStopsAndHidesExactlyOnce() {
        let state = coordinator.apply(scanOutcome: .success(0), folderConfigured: true)

        XCTAssertEqual(state, .noPlayableVideos)
        XCTAssertEqual(coordinator.lastState, .noPlayableVideos)
        XCTAssertEqual(stopper.stopCount, 1)
        XCTAssertEqual(presenter.hideCount, 1)
        XCTAssertEqual(presenter.showCount, 0)
    }

    // MARK: - 3 · 目录没了：同一条降级路径

    func testMissingFolderStopsAndHides() {
        let state = coordinator.apply(scanOutcome: .failure(.folderMissing), folderConfigured: true)

        XCTAssertEqual(state, .folderMissing)
        XCTAssertEqual(coordinator.lastState, .folderMissing)
        XCTAssertEqual(stopper.stopCount, 1)
        XCTAssertEqual(presenter.hideCount, 1)
        XCTAssertEqual(presenter.showCount, 0)
    }

    // MARK: - 4 · 幂等（上面三条的牙齿来源）

    func testRepeatedIdenticalInputIsIdempotent() {
        for _ in 0..<5 {
            coordinator.apply(scanOutcome: .success(0), folderConfigured: true)
        }

        XCTAssertEqual(presenter.hideCount, 1,
                       "同一输入连投 5 次，hide() 只能执行 1 次 —— 每轮都重复调 hide 的实现照样让第 2/3 条绿")
        XCTAssertEqual(stopper.stopCount, 1)
        XCTAssertEqual(presenter.showCount, 0)
    }

    // MARK: - 5 · 恢复路径

    func testRecoveryFromHiddenToPlayingResumesWithoutRestart() {
        // 进隐藏
        coordinator.apply(scanOutcome: .success(0), folderConfigured: true)
        // 文件夹恢复（重新出现）→ 壁纸自己回来，不需要重启 app
        let recovered = coordinator.apply(scanOutcome: .success(2), folderConfigured: true)

        XCTAssertEqual(recovered, .playing)
        XCTAssertEqual(coordinator.lastState, .playing)
        XCTAssertEqual(presenter.showCount, 1, "恢复后 show() 必须把窗口原样叫回来（hide 保留、teardown 销毁）")
        XCTAssertEqual(presenter.hideCount, 1)

        // 又失效 → 再隐藏
        coordinator.apply(scanOutcome: .success(0), folderConfigured: true)
        XCTAssertEqual(presenter.hideCount, 2, "再次失效必须再次隐藏 —— 恢复不得把降级路径焊死在打开态")
        XCTAssertEqual(presenter.showCount, 1)
    }
}
