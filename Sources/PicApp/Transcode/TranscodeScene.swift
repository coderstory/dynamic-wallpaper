import SwiftUI
import PicCore

/// 转码窗口 scene —— 全 app 唯一出现列表的地方（UI-SPEC §8 例外，Phase 6 存档）。
///
/// `Window` 场景 + 固定 id：设置窗「打开…」用 `openWindow(id: "transcode")` 唤起，
/// 与设置窗本身同一套开窗机制（D-10：不引入第二套窗口管理）。
struct TranscodeScene: Scene {

    /// 队列 / 判定 / 壁纸目录由装配层注入，视图自己不造（D-10）。
    let queue: TranscodeQueue
    let locator: ExternalToolLocator
    let wallpaperRootProvider: () -> URL?

    var body: some Scene {
        Window("转码", id: TranscodeScene.windowID) {
            TranscodeWindowHost(queue: queue, locator: locator,
                                wallpaperRootProvider: wallpaperRootProvider)
        }
        .defaultSize(width: 640, height: 420)
    }

    /// 窗 id 的唯一一份 —— 设置窗的开窗动作按它拼。
    static let windowID = "transcode"
}

/// `@StateObject` 只能挂在 View 上，所以 scene 的内容是一层薄壳。
/// `.onAppear` 就是「每次开窗重查」的唯一触发点（RESEARCH Q7）：
/// 用户中途装上 ffmpeg 不必重启 app。
private struct TranscodeWindowHost: View {

    @StateObject private var viewModel: TranscodeViewModel

    init(queue: TranscodeQueue, locator: ExternalToolLocator,
         wallpaperRootProvider: @escaping () -> URL?) {
        _viewModel = StateObject(wrappedValue: TranscodeViewModel(
            queue: queue, locator: locator,
            wallpaperRootProvider: wallpaperRootProvider))
    }

    var body: some View {
        TranscodeWindowView(viewModel: viewModel)
            .onAppear {
                viewModel.refresh()
                viewModel.loadCandidates()
            }
    }
}