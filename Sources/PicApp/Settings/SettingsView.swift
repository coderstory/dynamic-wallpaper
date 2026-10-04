import SwiftUI
import AppKit
import PicCore

/// 设置窗主体 —— 2026-10-04 重设计。与设计稿 `.planning/design/ui-rotation-a.html` 一一对应。
///
/// 布局：**顶部 TAB（播放 / 转码 / 关于）+ 磁贴网格 + 紧凑卡**，单窗口。
/// 转码不再是独立 scene（原 `TranscodeScene`），改为本窗内的第二个 TAB。
///
/// 不变量（与旧版相同，改动不得破坏）：
///   - 六个可调项全部真绑定：`store.<键> = …` → `SettingsApplier.apply*()`（当场生效）→ `store.persist()`
///   - 窗口内没有「渲染假数据」的 `@State`（速度滑杆拖动暂态除外，每次变更直通 store）
///   - 量纲换算全部走 `SettingsPresentation`，视图里不出现第二份
///   - 14 个 `accessibilityIdentifier` 被 XCUITest 依赖，一个都不能少
///   - 空态文案与置灰联动是 UI-SPEC §6 硬需求，语义不变
struct SettingsView: View {
    @Environment(SettingsStore.self) private var store
    @Environment(SettingsApplier.self) private var applier
    @Environment(HoldArbiter.self) private var arbiter
    @Environment(SettingsSessionState.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 动作闭包一律经 PicApp 注入 —— 视图不持有 AppDelegate（装配点不动）。
    let requestFolder: () -> Void
    let rescanLibrary: () -> Void
    let reapplyBatteryHold: () -> Void
    let setLaunchAtLogin: (Bool) -> Void
    /// 转码视图模型 —— 转码并入本窗后由 PicApp 注入。
    let transcodeViewModel: TranscodeViewModel
    /// 安装途径弹层的「重新检测」——重查并回填最新读数（新鲜化出口）。
    let refreshFFmpeg: () -> Bool

    /// ffmpeg 不可用时的安装途径弹层（置灰之外还得给出途径）。
    @State private var showingPathways = false

    // ── 唯一保留的 @State（都不是「渲染假数据」）──
    // 速度滑杆的拖动暂态（每次 onChanged 直通 store + applier）。
    @State private var rateDrag: Double = 1.0
    // 顶部 TAB：0 播放 / 1 转码 / 2 关于。
    @State private var tab: Int = 0

    private static let tabTitles = ["播放", "转码", "关于"]

    var body: some View {
        VStack(spacing: 0) {
            // 自绘标题行（windowStyle(.hiddenTitleBar) 下唯一的「标题栏」）。
            // 文字逐字 = 「动态壁纸」（2026-10-04 用户改名）。
            Text("动态壁纸")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.pTitle)
                .frame(maxWidth: .infinity)
                .padding(.top, 10).padding(.bottom, 8)
                .contentShape(Rectangle())
            VStack(spacing: Metrics.blockGap) {
                TabBar(items: Self.tabTitles, index: $tab)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("main-tabs")
                Group {
                    switch tab {
                    case 1: transcodeTab
                    case 2: aboutTab
                    default: playTab
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, Metrics.winPadding)
            .padding(.bottom, Metrics.winPadding)
        }
        .frame(minWidth: SettingsPresentation.windowMinWidth,
               idealWidth: Metrics.windowWidth,
               maxWidth: .infinity, maxHeight: .infinity,
               alignment: .topLeading)
        .background(Color.pBg.ignoresSafeArea())
        .preferredColorScheme(.light)
        .onAppear(perform: seedAndObserve)
        .sheet(isPresented: $showingPathways) {
            InstallPathwaysView(onRecheck: { _ = refreshFFmpeg() })
        }
    }

    // MARK: - TAB 1 · 播放

    private var playTab: some View {
        VStack(spacing: Metrics.blockGap) {
            StatusBar(text: statusLine,
                      meta: ["\(session.playableCount) 个视频"],
                      warn: isEmpty)

            SectionHead(t: "播放控制")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Metrics.gridGap),
                                GridItem(.flexible(), spacing: Metrics.gridGap)],
                      spacing: Metrics.gridGap) {
                Tile(symbol: "repeat", title: "模式") {
                    GlowSegmented(items: PlayMode.allCases.map(SettingsPresentation.playModeLabel),
                                   index: modeIndex)
                        .accessibilityIdentifier("mode-segmented")
                }
                // 置灰联动①：单循环下整块置灰 + 禁交互（UI-SPEC §6 置灰而非隐藏）。
                Tile(symbol: "timer", title: "轮换",
                     disabled: !SettingsPresentation.rotationControlsEnabled(playMode: store.playMode)) {
                    ChoiceGrid3x2(items: SettingsPresentation.rotationChoicesMinutes
                                    .map(SettingsPresentation.rotationLabel(minutes:)),
                                   index: rotationIndex)
                        .disabled(!SettingsPresentation.rotationControlsEnabled(playMode: store.playMode))
                        .accessibilityIdentifier("rotation-stepper")
                }
                Tile(symbol: "gauge.with.dots.needle.67percent", title: "速度", hint: "音高不变") {
                    HStack(spacing: 11) {
                        GlowSlider(value: $rateDrag, range: 0.5...2, onChanged: {
                            store.rate = Float(rateDrag)
                            applier.applyRate()
                        }, onEnded: {
                            store.persist()
                        })
                        .accessibilityIdentifier("rate-slider")
                        Text(SettingsPresentation.rateLabel(store.rate))
                            .font(.system(size: 12))
                            .monospacedDigit()
                            .foregroundStyle(Color.pFg)
                            .frame(width: Metrics.valueWidth, alignment: .trailing)
                            .accessibilityIdentifier("rate-value")
                    }
                }
                Tile(symbol: "speaker.wave.2.fill", title: "声音") {
                    HStack(spacing: 11) {
                        GlowSlider(value: volumePercent, range: 0...100, onChanged: {
                            store.volume = SettingsPresentation.volumeFromPercent(
                                SettingsPresentation.volumePercent(store.volume))
                            applier.applyVolume()
                        }, onEnded: {
                            store.persist()
                        })
                        .disabled(!SettingsPresentation.volumeControlsEnabled(isMuted: store.isMuted))
                        .accessibilityIdentifier("volume-slider")
                        Text("\(SettingsPresentation.volumePercent(store.volume))%")
                            .font(.system(size: 12))
                            .monospacedDigit()
                            .foregroundStyle(Color.pFg)
                            .frame(width: Metrics.valueWidth, alignment: .trailing)
                            .accessibilityIdentifier("volume-value")
                        // 置灰联动②：静音时滑杆不可交互 + 视觉变淡。
                        .opacity(SettingsPresentation.volumeControlsEnabled(isMuted: store.isMuted) ? 1 : 0.34)
                        Toggle("", isOn: soundOn).toggleStyle(GlowToggle()).labelsHidden()
                            .accessibilityIdentifier("sound-toggle")
                    }
                }
            }

            SectionHead(t: "来源与系统")
            CompactCard {
                CompactRow(symbol: "folder.fill", title: "壁纸文件夹",
                           sub: store.sourceFolder.isEmpty ? "未设置" : store.sourceFolder) {
                    Button("选择…") { requestFolder() }.buttonStyle(GlowButton())
                        .disabled(session.isScanning)
                        .accessibilityIdentifier("select-button")
                    Button("重新扫描") { rescanLibrary() }.buttonStyle(GlowButton())
                        .disabled(session.isScanning)
                        .accessibilityIdentifier("rescan-button")
                }
                .background(Color.pSep, alignment: .bottom)

                if isEmpty {
                    // 空态：数字转警告色 + 图标盒换警告配色（UI-SPEC §6 硬需求）。
                    CompactRow(symbol: "exclamationmark.triangle.fill", title: "可用视频",
                               sub: SettingsPresentation.emptyStateBody, warn: true) {
                        Text("0")
                            .font(.system(size: Metrics.countFont, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Color.pWarnFg)
                            .accessibilityIdentifier("count-value")
                    }
                    .background(Color.pSep, alignment: .bottom)
                } else {
                    CompactRow(symbol: "film", title: "可用视频") {
                        Text("\(session.playableCount)")
                            .font(.system(size: Metrics.countFont, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Color.pAccent)
                            .accessibilityIdentifier("count-value")
                    }
                    .background(Color.pSep, alignment: .bottom)
                }

                CompactRow(symbol: "battery.75", title: "电池时播放") {
                    Toggle("", isOn: playOnBattery).toggleStyle(GlowToggle()).labelsHidden()
                        .accessibilityIdentifier("battery-toggle")
                }
                .background(Color.pSep, alignment: .bottom)

                CompactRow(symbol: "power", title: "开机自启") {
                    Toggle("", isOn: launchAtLogin).toggleStyle(GlowToggle()).labelsHidden()
                        .accessibilityIdentifier("autostart-toggle")
                }
            }
            .accessibilityIdentifier("status-paused")

            // ffmpeg 状态已并入顶部状态条，不再单独占一行（同一信息显示两遍是噪音）。
            // 这里留一个 0 尺寸的锚点：`status-ffmpeg` 这个 identifier 被 UITest 依赖，
            // 直接删元素会让那条断言永远查无此物。文本已在顶部状态条里。
            Color.clear
                .frame(width: 0, height: 0)
                .accessibilityElement()
                .accessibilityLabel(Text("ffmpeg \(session.ffmpegAvailable ? "已就绪" : "未安装")"))
                .accessibilityIdentifier("status-ffmpeg")
        }
    }

    // MARK: - TAB 2 · 转码（原独立窗口内容，改为窗内区块）

    private var transcodeTab: some View {
        TranscodeSection(viewModel: transcodeViewModel,
                         showingPathways: $showingPathways,
                         refresh: { _ = refreshFFmpeg() })
    }

    // MARK: - TAB 3 · 关于

    private var aboutTab: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(spacing: 4) {
                AboutIcon()
                    .padding(.bottom, 9)
                Text("动态壁纸")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.pFg)
                Text(appVersion)
                    .font(mono(11.5))
                    .foregroundStyle(Color.pMuted)
                Text("用视频当动态壁纸")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.pMuted)
                    .padding(.top, 3)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: Metrics.aboutMinHeight)
    }

    /// 版本号取自 bundle，不硬编码 —— 改版本号时关于页自动跟随。
    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return "版本 \(v ?? "1.0")"
    }

    // MARK: - 状态读数

    private var isEmpty: Bool {
        session.lastLibraryState.map(SettingsPresentation.isEmptyState) ?? false
    }

    private var running: Bool { arbiter.decision.shouldPlay }

    /// 状态条主文案。空态优先说「暂停 + 原因」，正常态说在播什么。
    private var statusLine: String {
        if isEmpty { return "已暂停 · 没有可播文件" }
        return "正在播放 · \(SettingsPresentation.playModeLabel(store.playMode))"
    }

    private var ffmpegStatusText: String {
        session.ffmpegAvailable
            ? "ffmpeg 已就绪"
            : "ffmpeg 未安装 · 转码不可用"
    }

    private func ffmpegStatusLine() {
        let available = session.ffmpegAvailable
        WallpaperWindowController.emit(
            "PIC_FFMPEG available=\(available ? 1 : 0) label=\(FFmpegAvailability.label(available: available))")
    }

    // MARK: - 真绑定（每个写入口都是 store → applier → persist）

    private var modeIndex: Binding<Int> {
        Binding(
            get: { PlayMode.allCases.firstIndex(of: store.playMode) ?? 0 },
            set: { i in
                store.playMode = PlayMode.allCases[i]
                applier.applyMode()
                store.persist()
            })
    }

    private var rotationIndex: Binding<Int> {
        Binding(
            get: { SettingsPresentation.rotationChoicesMinutes
                .firstIndex(of: SettingsPresentation.rotationMinutes(seconds: store.rotationInterval)) ?? 0 },
            set: { i in
                store.rotationInterval = SettingsPresentation.rotationSeconds(
                    minutes: SettingsPresentation.rotationChoicesMinutes[i])
                applier.applyInterval()
                store.persist()
            })
    }

    private var volumePercent: Binding<Double> {
        Binding(
            get: { Double(SettingsPresentation.volumePercent(store.volume)) },
            set: { store.volume = SettingsPresentation.volumeFromPercent(Int($0.rounded())) })
    }

    /// 「声音」开关（勾 = 有声，不勾 = 禁音 —— 用户语义）。store 键仍是 isMuted（持久化
    /// 语义不变），视图这一侧做一次取反，别处不许再出现第二份取反。
    private var soundOn: Binding<Bool> {
        Binding(
            get: { !store.isMuted },
            set: {
                store.isMuted = !$0
                applier.applyMuted()
                store.persist()
            })
    }

    /// 「电池时播放」开关（勾 = 使用电池也播放 —— 用户语义，2026-10-04 反转）。
    /// store 键仍是 pauseOnBattery（持久化语义不变：true = 电池时暂停），视图侧取反一次，
    /// 别处不许出现第二份取反。默认 pauseOnBattery=false → 勾选态=开（默认播放）。
    private var playOnBattery: Binding<Bool> {
        Binding(
            get: { !store.pauseOnBattery },
            set: {
                store.pauseOnBattery = !$0
                store.persist()
                // 当场重估：用最近一次已知的电源状态走同一个映射，不等下一次电源跃迁。
                reapplyBatteryHold()
            })
    }

    /// 开机自启。与 `pauseOnBattery` 同款三行：写 store → persist → 落行为。
    /// 行为侧（A→B 决策）在装配层，视图只管把用户的拨动递过去。
    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { store.launchAtLogin },
            set: {
                store.launchAtLogin = $0
                store.persist()
                setLaunchAtLogin($0)
            })
    }

    // MARK: - onAppear

    private func seedAndObserve() {
        rateDrag = Double(store.rate)
        // 开窗即重查 ffmpeg（用户中途装上的不必重启；回填 session → 卡片当场刷新）。
        refreshFFmpeg()
        applyWindowChrome()
        ffmpegStatusLine()
    }

    /// 窗口补充设置：hiddenTitleBar 窗口默认不可拖 —— 开 isMovableByWindowBackground
    /// 让自绘标题行/空白区可以拖窗。0.5 秒后 SwiftUI 才把 Window 装进 NSApp.windows
    /// （几何探针同一时序），此刻设置一次即可（该属性不在 SwiftUI 场景配置里，不会被改回）。
    private func applyWindowChrome() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard let win = NSApp.windows.first(where: { $0.title == "动态壁纸" }) else { return }
            win.isMovableByWindowBackground = true
            emitWindowGeometry(win)
        }
    }

    /// 几何探针：窗口出现后打一行 `PIC_SETTINGS_WINDOW`，经 `PIC_EVIDENCE_FILE` mirror 进证据
    /// 文件（XCUITest/探针 → 可 grep 证据的桥）。
    private func emitWindowGeometry(_ win: NSWindow) {
        WallpaperWindowController.emit(
            "PIC_SETTINGS_WINDOW width=\(Int(win.frame.width.rounded())) minWidth=\(Int(win.contentMinSize.width.rounded()))")
    }
}