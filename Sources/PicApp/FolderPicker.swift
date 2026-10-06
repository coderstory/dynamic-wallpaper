import AppKit
import PicCore

/// 全仓唯一碰 `NSOpenPanel` 的地方：只交出 URL 或 nil，写不写由调用方决定。
/// 不碰激活策略（`NSApp.setActivationPolicy` 只在 AppDelegate 一处），不碰 UserDefaults。
@MainActor
public protocol FolderPicker {
    func pickFolder() async -> URL?

    /// 转码源选择：目录与文件可混选、可多选。nil = 用户取消。目录的递归展开归调用方。
    func pickTranscodeSources() async -> [URL]?
}

@MainActor
public final class NSOpenPanelFolderPicker: FolderPicker {

    public init() {}

    /// 面板工厂：两个选择动作共用，差异只由三个参数表达。
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
        // canChooseFiles = false 不能省：省了用户能选到单个 .mp4，扫描器枚举后返回空
        let panel = makePanel(canChooseFiles: false, allowsMultipleSelection: false,
                              prompt: "选择壁纸文件夹")
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    public func pickTranscodeSources() async -> [URL]? {
        let panel = makePanel(canChooseFiles: true, allowsMultipleSelection: true,
                              prompt: "选择要转码的目录或文件")
        guard panel.runModal() == .OK else { return nil }
        return panel.urls
    }
}
