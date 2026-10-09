import XCTest
@testable import PicCore

/// 新版 shell 展示层（侧栏导航 / 旧页签映射 / 图片适配与档位脚注 / 片库计数带 / hero 文案）。
/// 每个方法防一件事：文案逐字锁死，谁改源码里的一个字这里当场红。
final class SettingsShellPresentationTests: XCTestCase {

    // ── 侧栏导航 ──

    /// 视频侧栏是全部四页，且顺序就是 `rawValue` 行序 —— 侧栏不重排，只按声明顺序渲染。
    func testNavPagesForVideoIsFourPagesInOrder() {
        XCTAssertEqual(SettingsPresentation.navPages(for: .video),
                       [.play, .library, .queue, .general])
        XCTAssertEqual(SettingsPresentation.navPages(for: .video).count, 4)
    }

    /// 图片没有转码语义，队列项必须是隐藏而不是置灰 —— 防「图片来源也出现转码队列」回归。
    func testNavPagesForImageOmitsQueue() {
        let pages = SettingsPresentation.navPages(for: .image)
        XCTAssertEqual(pages, [.play, .library, .general])
        XCTAssertFalse(pages.contains(.queue), "图片来源不许出现转码队列页")
    }

    /// 菜单栏传的还是老三页签 Int（0 播放 / 1 片库 / 2 通用）。只能查表：用 rawValue 直接构造
    /// 会把「通用」跳到处理队列页；越界值回落 play，不许崩。
    func testLegacyTabMappingAndOutOfRangeFallback() {
        XCTAssertEqual(SettingsPresentation.page(fromLegacyTab: 0), .play)
        XCTAssertEqual(SettingsPresentation.page(fromLegacyTab: 1), .library)
        XCTAssertEqual(SettingsPresentation.page(fromLegacyTab: 2), .general)
        XCTAssertEqual(SettingsPresentation.page(fromLegacyTab: -1), .play)
        XCTAssertEqual(SettingsPresentation.page(fromLegacyTab: 99), .play)
    }

    /// 四页的标题与副题逐字锁死 —— 侧栏是用户第一眼看到的导航，文案漂移要当场红。
    func testSettingsPageTitlesAndCaptionsMatchVerbatim() {
        XCTAssertEqual(SettingsPresentation.SettingsPage.play.title, "播放")
        XCTAssertEqual(SettingsPresentation.SettingsPage.library.title, "片库")
        XCTAssertEqual(SettingsPresentation.SettingsPage.queue.title, "队列")
        XCTAssertEqual(SettingsPresentation.SettingsPage.general.title, "通用")
        XCTAssertEqual(SettingsPresentation.SettingsPage.play.caption, "正在播什么、多快、什么时候让路")
        XCTAssertEqual(SettingsPresentation.SettingsPage.library.caption, "壁纸从哪来、有多少能用")
        XCTAssertEqual(SettingsPresentation.SettingsPage.queue.caption, "待转码 / 待降帧的处理进度")
        XCTAssertEqual(SettingsPresentation.SettingsPage.general.caption, "启动与版本")
    }

    // ── 图片适配方式 ──

    /// 文案走 `map(allCases)`：labels 必须与枚举一一对应且顺序一致，否则分段控件的下标
    /// 会指到错误的 mode 上。
    func testImageFitLabelsMatchAllCasesInOrder() {
        XCTAssertEqual(SettingsPresentation.imageFitLabels(),
                       ImageFit.allCases.map(SettingsPresentation.imageFitLabel))
        XCTAssertEqual(SettingsPresentation.imageFitLabels(), ["填充", "适应", "居中", "平铺"])
    }

    /// label → 下标 → label 的往返必须闭合：控件选中第几格就得是那个 mode 的标签，
    /// 往返对不上用户看到的就是 A、存进去的是 B。
    func testImageFitIndexRoundTripsThroughLabel() {
        for fit in ImageFit.allCases {
            let label = SettingsPresentation.imageFitLabel(fit)
            let index = SettingsPresentation.imageFitIndex(fit)
            XCTAssertEqual(SettingsPresentation.imageFitLabels()[index], label,
                           "\(label) 的下标 \(index) 在 labels 里对应的应是它自己")
        }
    }

    /// `.fill` 是拍板过的默认值，说明文案必须同时交代「默认」与「不变形」——
    /// 少了任何一个词，用户要么不知道它是默认，要么以为会拉伸变形。
    func testImageFitCaptionForFillStatesDefaultAndNoDistortion() {
        let caption = SettingsPresentation.imageFitCaption(.fill)
        XCTAssertTrue(caption.contains("默认"), "fill 的说明必须交代它是默认值")
        XCTAssertTrue(caption.contains("不变形"), "fill 的说明必须交代不变形")
    }

    // ── 分辨率档位脚注 ──

    /// 阈值显示当前生效的原值（含千位分隔符）与档位名 —— 用户要能对上自己存的那个数。
    func testResolutionNoteIncludesThousandsSeparatorAndTierName() {
        let note = SettingsPresentation.resolutionNote(pixels: ImageResolutionTier.k2.pixels)
        XCTAssertTrue(note.contains("3,686,400"), "阈值要带千位分隔符，且显示原值")
        XCTAssertTrue(note.contains("(2K)"), "要带档位名")
        XCTAssertTrue(note.contains("低于档位的图片不参与轮播"), "脚注要交代判定后果")
    }

    /// 对不上任何档位的像素值（手改过 / 旧版本）必须就近吸附出文案，不许崩、不许空。
    func testResolutionNoteSnapsUnlistedPixelCount() {
        let note = SettingsPresentation.resolutionNote(pixels: 5_000_000)
        XCTAssertTrue(note.contains("5,000,000"), "显示的是传入的原值，不是吸附后的档位值")
        XCTAssertTrue(note.contains("(2K)"), "5,000,000 距 2K 最近，应吸附到 2K")
    }

    // ── 片库计数带 ──

    /// 图片只有「够不够格」一件事要说：恰好三格，values 依次对应 total / passing / filtered；
    /// 总数格是中性事实不强调，剩下两格才是「有事要说」。
    func testLibraryStatCellsForImageIsThreeCells() {
        let cells = SettingsPresentation.libraryStatCells(
            kind: .image,
            image: SettingsPresentation.ImageStat(total: 10, passing: 7, filtered: 3),
            video: SettingsPresentation.VideoStat(playable: 0, pending: 0, transcode: 0, fps: 0))
        XCTAssertEqual(cells.count, 3)
        XCTAssertEqual(cells.map(\.label), ["图片总数", "将参与轮播", "低于档位"])
        XCTAssertEqual(cells.map(\.value), ["10", "7", "3"])
        XCTAssertEqual(cells.map(\.emphasis), [false, true, true],
                       "图片总数格不强调，参与轮播与低于档位要强调")
    }

    /// 视频多出来的三项答「还要处理多久」：恰好四格，values 依次对应 playable / pending / transcode / fps。
    func testLibraryStatCellsForVideoIsFourCells() {
        let cells = SettingsPresentation.libraryStatCells(
            kind: .video,
            image: SettingsPresentation.ImageStat(total: 0, passing: 0, filtered: 0),
            video: SettingsPresentation.VideoStat(playable: 5, pending: 2, transcode: 1, fps: 3))
        XCTAssertEqual(cells.count, 4)
        XCTAssertEqual(cells.map(\.label), ["可用视频", "待处理", "需转码", "需降帧"])
        XCTAssertEqual(cells.map(\.value), ["5", "2", "1", "3"])
    }

    /// 零不是坏消息：待处理 / 需转码 / 需降帧为 0 时保持安静灰，>0 才亮 ——
    /// 防「0 也标橙」回归，亮起来会让用户以为有事要做。
    func testVideoStatEmphasisIsQuietAtZeroAndLitAboveZero() {
        let quiet = SettingsPresentation.libraryStatCells(
            kind: .video,
            image: SettingsPresentation.ImageStat(total: 0, passing: 0, filtered: 0),
            video: SettingsPresentation.VideoStat(playable: 4, pending: 0, transcode: 0, fps: 0))
        XCTAssertTrue(quiet[0].emphasis, "可用视频恒强调")
        XCTAssertFalse(quiet[1].emphasis)
        XCTAssertFalse(quiet[2].emphasis)
        XCTAssertFalse(quiet[3].emphasis)

        let lit = SettingsPresentation.libraryStatCells(
            kind: .video,
            image: SettingsPresentation.ImageStat(total: 0, passing: 0, filtered: 0),
            video: SettingsPresentation.VideoStat(playable: 4, pending: 1, transcode: 1, fps: 1))
        XCTAssertTrue(lit[1].emphasis)
        XCTAssertTrue(lit[2].emphasis)
        XCTAssertTrue(lit[3].emphasis)
    }

    // ── hero ──

    /// 图片的「单张不变」是显示而不是轮播；同一个 mode 在视频那侧叫单循环 ——
    /// 四个组合的动词（显示 / 轮播 / 播放）一个都不能串。
    func testHeroHeadlineDistinguishesKindAndMode() {
        XCTAssertEqual(SettingsPresentation.heroHeadline(kind: .image, mode: .loopSingle),
                       "正在显示 · 单张不变")
        XCTAssertEqual(SettingsPresentation.heroHeadline(kind: .image, mode: .loopList),
                       "正在轮播 · 顺序轮播")
        XCTAssertEqual(SettingsPresentation.heroHeadline(kind: .video, mode: .loopSingle),
                       "正在播放 · 单循环")
        XCTAssertEqual(SettingsPresentation.heroHeadline(kind: .video, mode: .shuffle),
                       "正在播放 · 随机")
    }

    /// 图片三个分支：单张不变不提任何轮换语义（连 `every` 都不许出现 —— 不换片时
    /// 那个数字是死的）；顺序与随机各自说清轮法并带间隔文案。
    func testHeroSummaryImageBranches() {
        let single = SettingsPresentation.heroSummary(kind: .image, mode: .loopSingle,
                                                      count: 3, every: "15 分钟")
        XCTAssertTrue(single.contains("停在 3 张里的这一张"))
        XCTAssertTrue(single.contains("不会自动换"))
        XCTAssertFalse(single.contains("换一张"), "单张不变不含轮换语义")
        XCTAssertFalse(single.contains("每 15 分钟"), "不换片时间隔数字是死的，不许出现")

        let ordered = SettingsPresentation.heroSummary(kind: .image, mode: .loopList,
                                                       count: 3, every: "15 分钟")
        XCTAssertTrue(ordered.contains("3 张图片按顺序轮着放"))
        XCTAssertTrue(ordered.contains("每 15 分钟换一张"))

        let shuffled = SettingsPresentation.heroSummary(kind: .image, mode: .shuffle,
                                                        count: 3, every: "15 分钟")
        XCTAssertTrue(shuffled.contains("随机顺序"))
        XCTAssertTrue(shuffled.contains("每 15 分钟换一张"))
    }

    /// 视频三个分支：循环不提间隔，顺序 / 随机说清轮法并带「换一个」的间隔文案。
    func testHeroSummaryVideoBranches() {
        let single = SettingsPresentation.heroSummary(kind: .video, mode: .loopSingle,
                                                      count: 2, every: "15 分钟")
        XCTAssertTrue(single.contains("当前视频循环播放"))
        XCTAssertFalse(single.contains("每 15 分钟"), "单循环不换片，间隔数字不许出现")

        let ordered = SettingsPresentation.heroSummary(kind: .video, mode: .loopList,
                                                       count: 2, every: "15 分钟")
        XCTAssertTrue(ordered.contains("2 个视频按顺序轮着放"))
        XCTAssertTrue(ordered.contains("每 15 分钟换一个"))

        let shuffled = SettingsPresentation.heroSummary(kind: .video, mode: .shuffle,
                                                        count: 2, every: "15 分钟")
        XCTAssertTrue(shuffled.contains("2 个视频随机轮着放"))
        XCTAssertTrue(shuffled.contains("每 15 分钟换一个"))
    }

    /// 让路时的副题答「会不会从头重来」—— 承诺只有一份，逐字锁死。
    func testHeroHoldSummaryMatchesVerbatim() {
        XCTAssertEqual(SettingsPresentation.heroHoldSummary,
                       "条件解除后会自动续播，不会从头开始。")
    }

    /// 置灰理由按来源分派措辞：图片版说「单张不变」、视频版说「单循环」，互不串词 ——
    /// 图片用户看到「单循环」会不知道在说他。
    func testRotationDisabledNoteUsesKindSpecificWording() {
        XCTAssertEqual(SettingsPresentation.rotationDisabledNote(kind: .image),
                       "单张不变时不换片，轮换间隔无效。")
        XCTAssertEqual(SettingsPresentation.rotationDisabledNote(kind: .video),
                       "单循环时不换片，轮换间隔无效。")
        XCTAssertFalse(SettingsPresentation.rotationDisabledNote(kind: .image).contains("单循环"))
        XCTAssertFalse(SettingsPresentation.rotationDisabledNote(kind: .video).contains("单张不变"))
    }
}
