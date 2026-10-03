import AppKit
import PicCore

/// 文件夹选择的面板 seam（Plan 04-04 T2 / SYS-03）。
///
/// 这是**全仓唯一**允许出现 `NSOpenPanel` 的地方（04-06 会把它变成 test.sh 常驻判据）。
/// 分层：决策（`FolderRequestPolicy`，纯函数）在 `PicCore/App/` —— 它零 AppKit、
/// 可在无 GUI 环境穷举；而面板这一侧本质是 AppKit 胶水，落在 PicApp。
/// 协议 `pickFolder() async -> URL?` 的形状一旦定了就不改（为将来 sheet 形态留的口）。
///
/// ⚠️ 本文件**不碰**激活策略（`NSApp.setActivationPolicy` 只在 AppDelegate 一处，
/// T-02-09 的单点纪律），也**不写**设置（不碰 UserDefaults）—— 协议只负责
/// 「拿到一个 URL 或 nil」，写不写由 AppDelegate 决定，这样「用户取消」这条
/// 路径不需要任何特殊分支。
@MainActor
public protocol FolderPicker {
    func pickFolder() async -> URL?
}

@MainActor
public final class NSOpenPanelFolderPicker: FolderPicker {

    public init() {}

    public func pickFolder() async -> URL? {
        let panel = NSOpenPanel()
        // 三个必设项一个不能少：canChooseFiles = false 缺了的话用户能选到单个
        // .mp4 文件，扫描器会在它上面枚举然后返回空 —— 表现是「我明明选对了
        // 却没反应」，排查时完全想不到是面板配置（T-04-18）。
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "选择壁纸文件夹"
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}
