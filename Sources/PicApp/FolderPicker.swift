import AppKit
import PicCore

/// 文件夹选择的面板 seam。
///
/// 这是**全仓唯一**允许出现 `NSOpenPanel` 的地方（test.sh 的常驻判据）。
/// 分层：决策（`FolderRequestPolicy`，纯函数）在 `PicCore/App/` —— 它零 AppKit、
/// 可在无 GUI 环境穷举；而面板这一侧本质是 AppKit 胶水，落在 PicApp。
/// 协议 `pickFolder() async -> URL?` 的形状一旦定了就不改（新增面板能力走新方法，
/// 不改既有签名 —— 2026-10-04 转码源选择因此加 `pickTranscodeSources`）。
///
/// ⚠️ 本文件**不碰**激活策略（`NSApp.setActivationPolicy` 只在 AppDelegate 一处的
/// 单点纪律），也**不写**设置（不碰 UserDefaults）—— 协议只负责「拿到 URL 或 nil」，
/// 写不写由调用方决定，这样「用户取消」这条路径不需要任何特殊分支。
@MainActor
public protocol FolderPicker {
    func pickFolder() async -> URL?

    /// 转码源选择：目录与文件可混选、可多选。nil = 用户取消。
    /// 目录的递归展开（→ N 个候选文件）不在这里做 —— 面板只拿 URL，展开归调用方。
    func pickTranscodeSources() async -> [URL]?
}

@MainActor
public final class NSOpenPanelFolderPicker: FolderPicker {

    public init() {}

    /// 面板工厂：两个选择动作共用同一块 `NSOpenPanel(` 构造点（test.sh 的唯一落点判据数这个），
    /// 差异只由三个参数表达。
    private func makePanel(canChooseFiles: Bool, allowsMultipleSelection: Bool,
                           prompt: String) -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.canChooseFiles = canChooseFiles
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = allowsMultipleSelection
        panel.canCreateDirectories = false
        panel.prompt = prompt
        return panel
    }

    public func pickFolder() async -> URL? {
        // ⚠️ canChooseFiles = false 不能省：缺了的话用户能选到单个 .mp4 文件，
        // 扫描器会在它上面枚举然后返回空 —— 表现是「我明明选对了却没反应」，
        // 排查时完全想不到是面板配置。
        let panel = makePanel(canChooseFiles: false, allowsMultipleSelection: false,
                              prompt: "选择壁纸文件夹")
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    public func pickTranscodeSources() async -> [URL]? {
        // 目录与文件混选（用户需求「可以选择目录和文件」）：目录由调用方递归展开成
        // N 个候选文件；白名单外的文件由调用方过滤。
        let panel = makePanel(canChooseFiles: true, allowsMultipleSelection: true,
                              prompt: "选择要转码的目录或文件")
        guard panel.runModal() == .OK else { return nil }
        return panel.urls
    }
}
