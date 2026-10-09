import Foundation

/// 设置窗的纯显示映射：只做「值 ↔ 显示形态」的换算，不碰 SwiftUI/AppKit/AVFoundation，
/// 不做任何决策。窗口常量是唯一来源，视图与单测都读它，不许在别处散落字面量。
public enum SettingsPresentation {
    /// 设置窗打开时的宽度（`.defaultSize` / `idealWidth` 读这里）。
    /// 新版 shell：216 侧栏 + 内容区，见 ui-redesign-v2-shell.html。
    public static let windowWidth: CGFloat = 1024
    /// 设置窗的最小内容宽度（`contentMinSize` 的来源）。同上：低于这个宽，内容区的两列
    /// 卡片会挤到放不下半宽卡。
    public static let windowMinWidth: CGFloat = 880
    /// 速度滑杆的合法区间。
    public static let rateBounds: ClosedRange<Float> = 0.5...2.0

    /// 速度读数（`1.00×`）。越界值先 clamp 进 `rateBounds` 再格式化。
    public static func rateLabel(_ rate: Float) -> String {
        let clamped = min(max(rate, rateBounds.lowerBound), rateBounds.upperBound)
        return String(format: "%.2f×", clamped)
    }

    /// store（Float 0–1）→ UI（0–100 整数）。映射红线。
    public static func volumePercent(_ volume: Float) -> Int {
        let clamped = min(max(volume, 0), 1)
        return Int((clamped * 100).rounded())
    }

    /// UI（0–100 整数）→ store（Float 0–1）。
    public static func volumeFromPercent(_ percent: Int) -> Float {
        min(max(Float(percent) / 100, 0), 1)
    }


    /// 轮换间隔的封闭值表（分钟）。换算只落在下面两个函数（视图里不出现第二份 ×60）。
    public static let rotationChoicesMinutes: [Int] = [5, 10, 15, 30, 60, 120]

    /// 步进器读数：`>= 60` 显示「N 小时」，否则「N 分钟」。
    public static func rotationLabel(minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60) 小时" : "\(minutes) 分钟"
    }

    /// UI 分钟 → store 秒（`rotationInterval` 的量纲是秒）。
    public static func rotationSeconds(minutes: Int) -> TimeInterval {
        TimeInterval(minutes) * 60
    }

    /// store 秒 → 表内分钟，就近吸附：对不上值表的旧值回落到最近的表项，否则步进器会索引越界。
    public static func rotationMinutes(seconds: TimeInterval) -> Int {
        let target = seconds / 60
        return rotationChoicesMinutes.min {
            abs(Double($0) - target) < abs(Double($1) - target)
        } ?? rotationChoicesMinutes[0]
    }

    /// 置灰联动①。判据只允许出现在下面这一行 return 上。
    public static func rotationControlsEnabled(playMode: PlayMode) -> Bool {
        return playMode != .loopSingle
    }

    /// 置灰联动②。同上。
    public static func volumeControlsEnabled(isMuted: Bool) -> Bool {
        return !isMuted
    }

    /// 视频口径的分段控件文案（按 `PlayMode.allCases` 顺序渲染）。
    public static func playModeLabel(_ mode: PlayMode) -> String {
        switch mode {
        case .loopSingle: return "单循环"
        case .loopList: return "列表循环"
        case .shuffle: return "随机"
        }
    }

    /// 轮播方式文案，按来源分派。**枚举（PlayMode）共用一份，只有标签分派**：三个 case 的语义
    /// 与媒体类型无关（换不换、什么顺序换），但图片不谈「循环」——同一张图不会「循环播放」，
    /// 它是「不变」。写成「单图循环」会让用户以为图片自己在动。
    public static func playModeLabel(_ mode: PlayMode, kind: WallpaperKind) -> String {
        guard kind == .image else { return playModeLabel(mode) }
        switch mode {
        case .loopSingle: return "单张不变"
        case .loopList: return "顺序轮播"
        case .shuffle: return "随机轮播"
        }
    }

    /// 分辨率档位分段控件的三档文案（按 `ImageResolutionTier.allCases` 顺序渲染）。
    public static func resolutionTierLabels() -> [String] {
        ImageResolutionTier.allCases.map(\.label)
    }

    /// store 像素值 → 档位下标。**必须吸附而不是精确匹配**：用户手改过 / 旧版本的像素值
    /// 可能对不上任何一档，不吸附会让分段控件的选中索引越界。与 `rotationMinutes` 同款处理。
    public static func resolutionTierIndex(pixels: Int) -> Int {
        let tiers = ImageResolutionTier.allCases
        return tiers.firstIndex { $0.pixels == pixels }
            ?? tiers.indices.min { abs(tiers[$0].pixels - pixels) < abs(tiers[$1].pixels - pixels) }
            ?? tiers.startIndex
    }

    /// 档位下标 → 像素阈值。越界下标回落首档，不给调用方造 nil 分支。
    public static func resolutionTierPixels(index: Int) -> Int {
        let tiers = ImageResolutionTier.allCases
        guard tiers.indices.contains(index) else { return tiers[tiers.startIndex].pixels }
        return tiers[index].pixels
    }


    /// 空态副行（逐字硬需求）。全仓唯一一份：视图与单测都引用它。
    public static let emptyStateBody = "没找到能播的文件。壁纸已隐藏，桌面显示的是系统原壁纸。"

    ///  三态一张皮：没配过 / 目录没了 / 扫到 0 在 UI 上**不区分**， 判定就是「不该显示壁纸」的反面。
    public static func isEmptyState(_ state: LibraryState) -> Bool {
        return !state.shouldShowWallpaper
    }

    /// 空态的标题 / 原因说明 / 主行动。
    public struct EmptyStateCopy: Equatable, Sendable {
        public let title: String
        public let reason: String
        public let primaryAction: String

        public init(title: String, reason: String, primaryAction: String) {
            self.title = title
            self.reason = reason
            self.primaryAction = primaryAction
        }
    }

    /// LibraryState → 空态文案。`.playing` 返回 nil（那时不该显示空态）。
    /// 与 isEmptyState(_:) 平行而非替代：那个回答「该不该显示壁纸」，这个回答「怎么告诉用户」。
    public static func emptyStateCopy(_ state: LibraryState, kind: WallpaperKind = .video) -> EmptyStateCopy? {
        switch state {
        case .folderUnconfigured:
            return kind == .image
                ? EmptyStateCopy(
                    title: "还没选图片文件夹",
                    reason: "Pic 还不知道该去哪里找图片。选一个文件夹，里面所有 JPG / PNG / HEIC / WEBP 都会进轮播池。",
                    primaryAction: "选择文件夹…")
                : EmptyStateCopy(
                    title: "还没选壁纸文件夹",
                    reason: "Pic 还不知道该去哪里找视频。选一个文件夹，里面所有能播的视频都会进轮换池。",
                    primaryAction: "选择文件夹…")
        case .folderMissing:
            return EmptyStateCopy(
                title: "壁纸文件夹不见了",
                reason: "上次选的位置现在不存在或读不了。可能被改名、被移动，或在没挂载的磁盘上。",
                primaryAction: "重新选择文件夹…")
        case .noPlayableVideos:
            // 同一个状态在图片来源下是另一件事：不是「不能播」，是「不够档位」。
            // 主行动也因此不同 —— 图片没有转码这条路，只能降档位（去设置窗）。
            return kind == .image
                ? EmptyStateCopy(
                    title: "没有够档位的图片",
                    reason: "文件夹能正常读取，但没有一张图片达到当前分辨率档位。把档位降到 1080P，或换一个图片更大的文件夹。",
                    primaryAction: "去片库调整档位")
                : EmptyStateCopy(
                    title: "没有能直接播的文件",
                    reason: "文件夹能正常读取，但里面 0 个能直接播的文件。MKV / AVI / WEBM 需要先转成 MP4 才能当壁纸。",
                    primaryAction: "去片库转码")
        case .playing:
            return nil
        }
    }

    /// 暂停原因 → 副标签。刻意**不写 `default:`**：`HoldReason` 加 case 时编译不过，
    /// 比漏一分支静默显示错文案安全。
    public static func holdReasonLabel(_ reason: HoldReason) -> String {
        switch reason {
        case .manualPause: return "手动暂停"
        case .fullscreen: return "检测到全屏/最大化窗口"
        case .screenLocked: return "屏幕已锁定"
        case .displayAsleep: return "显示器已熄屏"
        case .systemSleeping: return "系统正在睡眠"
        case .battery: return "电池供电中"
        }
    }

    /// 多原因按 `order` 排序后顿号连接（veto 集合下叠加原因必须全列 —— 只列一个会让用户
    /// 误判成 bug）。空集合 → 空串，调用方据此走「播放中」分支。排序只允许出现在本函数。
    public static func joinedReasons(_ reasons: [HoldReason]) -> String {
        guard !reasons.isEmpty else { return "" }
        return reasons.sorted().map(holdReasonLabel).joined(separator: "、")
    }


    // ── 侧栏导航 ──

    /// 侧栏的四区。`rawValue` 就是侧栏行序，`navPages(for:)` 只做裁切不复排。
    public enum SettingsPage: Int, CaseIterable, Sendable {
        case play, library, queue, general

        public var title: String {
            switch self {
            case .play: return "播放"
            case .library: return "片库"
            case .queue: return "队列"
            case .general: return "通用"
            }
        }

        /// 页标题下那行副题，回答「这页管什么事」。
        public var caption: String {
            switch self {
            case .play: return "正在播什么、多快、什么时候让路"
            case .library: return "壁纸从哪来、有多少能用"
            case .queue: return "待转码 / 待降帧的处理进度"
            case .general: return "启动与版本"
            }
        }
    }

    /// 侧栏实际渲染哪些页。**图片没有转码语义，队列项是隐藏而不是置灰** —— 置灰招来的第一个
    /// 疑问是「什么时候能用」，而答案是永远不会。
    public static func navPages(for kind: WallpaperKind) -> [SettingsPage] {
        kind == .image ? [.play, .library, .general] : SettingsPage.allCases
    }

    /// 菜单栏 `openSettings(Int)` 传的还是老三页签索引（0 播放 / 1 片库 / 2 通用）。**只能查表**：
    /// 新 shell 里「通用」从 2 挪到了 3，用 rawValue 直接构造会把「设置」跳到处理队列页。
    public static func page(fromLegacyTab tab: Int) -> SettingsPage {
        switch tab {
        case 1: return .library
        case 2: return .general
        default: return .play
        }
    }


    // ── 图片专属：适配方式 / 分辨率档位 ──

    /// 控件用的短标签与说明文案**分家**：分段控件只有四格宽，把句子塞进去会全变成省略号。
    public static func imageFitLabel(_ fit: ImageFit) -> String {
        switch fit {
        case .fill: return "填充"
        case .fit: return "适应"
        case .center: return "居中"
        case .tile: return "平铺"
        }
    }

    /// 分段控件文案。走 `map` 而不是手写数组：枚举加 case 时这里自动跟上，不会渲染出
    /// 一个下标与实际 mode 对不上的控件。
    public static func imageFitLabels() -> [String] {
        ImageFit.allCases.map(imageFitLabel)
    }

    /// 每个铺法在 `ImageFitGeometry` 下到底怎么摆。
    public static func imageFitCaption(_ fit: ImageFit) -> String {
        switch fit {
        case .fill: return "默认。等比放大到铺满屏幕，超出部分裁掉，不变形。"
        case .fit: return "等比缩放到完整显示，四周留黑边（窗口底色就是黑的）。"
        case .center: return "按原始尺寸居中显示，不放大也不缩小。"
        case .tile: return "按原始尺寸重复铺满屏幕。"
        }
    }

    /// mode → 分段控件下标。取不到回落首档：渲染控件的那一侧不该为了枚举加 case 处理 nil。
    public static func imageFitIndex(_ fit: ImageFit) -> Int {
        ImageFit.allCases.firstIndex(of: fit) ?? 0
    }

    /// 分辨率档位卡的脚注。阈值显示**当前生效的原值**而不是吸附后的档位值：store 存的是绝对值，
    /// 用户（或旧版本）可能落在两档之间，显示档位名义值会让他以为设置没存住。
    public static func resolutionNote(pixels: Int) -> String {
        let tier = ImageResolutionTier.allCases[resolutionTierIndex(pixels: pixels)]
        return "按总像素量判定：宽 × 高 ≥ \(thousands(pixels))(\(tier.label))。低于档位的图片不参与轮播。"
    }

    /// 千位分隔符。**不走 `NumberFormatter`**：它读 locale，同一段文案在不同语言环境下会变，
    /// 而这是要被单测逐字断言的字符串。
    private static func thousands(_ value: Int) -> String {
        var out = ""
        for (offset, digit) in String(value).reversed().enumerated() {
            if offset > 0, offset % 3 == 0 { out = "," + out }
            out = String(digit) + out
        }
        return out
    }


    // ── 片库计数带 / hero ──

    public struct ImageStat: Equatable, Sendable {
        public let total: Int
        public let passing: Int
        public let filtered: Int

        public init(total: Int, passing: Int, filtered: Int) {
            self.total = total
            self.passing = passing
            self.filtered = filtered
        }
    }

    public struct VideoStat: Equatable, Sendable {
        public let playable: Int
        public let pending: Int
        public let transcode: Int
        public let fps: Int

        public init(playable: Int, pending: Int, transcode: Int, fps: Int) {
            self.playable = playable
            self.pending = pending
            self.transcode = transcode
            self.fps = fps
        }
    }

    /// 计数带的一格。`emphasis` 是「有事要说」的语义开关 —— 具体染什么色是 UI 的事。
    public struct StatCell: Equatable, Sendable {
        public let value: String
        public let label: String
        public let emphasis: Bool

        public init(value: String, label: String, emphasis: Bool) {
            self.value = value
            self.label = label
            self.emphasis = emphasis
        }
    }

    /// 片库页三格 / 四格的分派只在这里：图片只有「够不够格」一件事要说，
    /// 视频多出来的三项答的是「还要处理多久」。
    public static func libraryStatCells(kind: WallpaperKind, image: ImageStat, video: VideoStat) -> [StatCell] {
        if kind == .image {
            return [
                StatCell(value: "\(image.total)", label: "图片总数", emphasis: false),
                StatCell(value: "\(image.passing)", label: "将参与轮播", emphasis: true),
                StatCell(value: "\(image.filtered)", label: "低于档位", emphasis: true),
            ]
        }
        // 后三项为零时保持安静灰 —— 零不是坏消息，亮起来会让人以为有事要做。
        return [
            StatCell(value: "\(video.playable)", label: "可用视频", emphasis: true),
            StatCell(value: "\(video.pending)", label: "待处理", emphasis: video.pending > 0),
            StatCell(value: "\(video.transcode)", label: "需转码", emphasis: video.transcode > 0),
            StatCell(value: "\(video.fps)", label: "需降帧", emphasis: video.fps > 0),
        ]
    }

    /// 头部计数的取数口径，唯一一份：图片走 imagePassing、视频走 playableCount ——
    /// 图片路径从不更新 playableCount，拿它计数在图片模式下永远是 0。
    public static func libraryCount(kind: WallpaperKind, videoCount: Int, imageCount: Int) -> Int {
        kind == .image ? imageCount : videoCount
    }

    /// 头部计数整段文案（量词跟着口径走：张 / 个视频）。
    public static func libraryCountLine(kind: WallpaperKind, videoCount: Int, imageCount: Int) -> String {
        let count = libraryCount(kind: kind, videoCount: videoCount, imageCount: imageCount)
        return kind == .image ? "\(count) 张" : "\(count) 个视频"
    }

    /// hero 主标。图片的「单张不变」是显示而不是轮播 —— 同一个 mode 在视频那侧叫单循环，
    /// 写成「正在轮播 · 单张不变」会自相矛盾。
    public static func heroHeadline(kind: WallpaperKind, mode: PlayMode) -> String {
        let label = playModeLabel(mode, kind: kind)
        if kind == .video { return "正在播放 · \(label)" }
        return mode == .loopSingle ? "正在显示 · \(label)" : "正在轮播 · \(label)"
    }

    /// 让路时的 hero 副题。**与下面那个函数平行而非替代**：那边只答「播出中怎麼轮」，这边答
    /// 「暂停了会不会从头重来」—— 用户真正担心的是后者。
    public static let heroHoldSummary = "条件解除后会自动续播，不会从头开始。"

    /// hero 副题。`every` 是已经格式化好的轮换间隔文案（如 `15 分钟`）；`.loopSingle` 两个分支
    /// 都不提它 —— 不换片时那个数字是死的，写出来就是一行谎话。
    public static func heroSummary(kind: WallpaperKind, mode: PlayMode, count: Int, every: String) -> String {
        switch (kind, mode) {
        case (.image, .loopSingle):
            return "停在 \(count) 张里的这一张，不会自动换。关掉窗口也不会变。"
        case (.video, .loopSingle):
            return "当前视频循环播放，关掉窗口也不会停。"
        case (.image, .loopList):
            return "\(count) 张图片按顺序轮着放，每 \(every)换一张。关掉窗口也不会停。"
        case (.image, .shuffle):
            return "\(count) 张图片按随机顺序轮着放，每 \(every)换一张。关掉窗口也不会停。"
        case (.video, .loopList):
            return "\(count) 个视频按顺序轮着放，每 \(every)换一个。关掉窗口也不会停。"
        case (.video, .shuffle):
            return "\(count) 个视频随机轮着放，每 \(every)换一个。关掉窗口也不会停。"
        }
    }

    /// 轮换间隔整块置灰时给的理由。**随来源分派措辞**：用户看到的是他那侧的 mode 名字，
    /// 说「单循环」会让图片用户不知道在说他。
    public static func rotationDisabledNote(kind: WallpaperKind) -> String {
        kind == .image ? "单张不变时不换片，轮换间隔无效。" : "单循环时不换片，轮换间隔无效。"
    }
}
