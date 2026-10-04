import SwiftUI
import AppKit
import PicCore

/// 设置窗主体（UI-SPEC §7 双列：左来源/播放，右电源与系统/维护/运行状态）。
///
/// 六个可调项**全部**是真绑定：每个控件的写入口经 `store.<键> = …` →
/// `SettingsApplier.apply*()`（当场生效）→ `store.persist()` —— 窗口内没有任何「渲染假数据」
/// 的 `@State`（速度行的拖动暂态除外，它每次变更都直通 store）。量纲换算全部走
/// `SettingsPresentation`，视图里不出现第二份。
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
    /// 「开机自启」的行为侧 —— 与上面同一条装配通道，经 PicApp 注入。
    let setLaunchAtLogin: (Bool) -> Void
    /// 「打开…」的条件分派：注入 `openWindow` 动作，可用则开窗返回 true。
    let openTranscode: ((() -> Void) -> Bool)
    /// 安装途径弹层里的「重新检测」——重查并回填最新读数（新鲜化出口）。
    let refreshFFmpeg: () -> Bool

    @Environment(\.openWindow) private var openWindow
    /// ffmpeg 不可用时的安装途径弹层（置灰之外还得给出途径）。
    @State private var showingPathways = false

    // ── 唯一保留的 @State（都不是「渲染假数据」）──
    // 速度滑杆的拖动暂态（每次 onChanged 直通 store + applier）。
    @State private var rateDrag: Double = 1.0
    // 开机自启：真绑定 store —— 不持久化的话用户拨开的开关重启即丢。
    @State private var breathe = false

    var body: some View {
        VStack(spacing: 0) {
            // 自绘标题行（windowStyle(.hiddenTitleBar) 下唯一的「标题栏」—— 深蓝底白字，
            // 左侧红绿灯由系统浮在上面）。文字逐字 = 「动态壁纸」（2026-10-04 用户改名）。
            Text("动态壁纸")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.pFg)
                .frame(maxWidth: .infinity)
                .padding(.top, 10).padding(.bottom, 8)
                .contentShape(Rectangle())
            HStack(alignment: .top, spacing: 14) {
                leftColumn
                    .frame(maxWidth: .infinity, alignment: .leading)
                rightColumn
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14).padding(.bottom, 14)
        }
        // 高随内容撑，不写死（UI-SPEC §13 坑 2）。max 系列让内容填满窗口任意尺寸 ——
        // 背景（深色）盖住整个窗口，状态恢复把窗口撑大时不再露出系统白底。
        .frame(minWidth: SettingsPresentation.windowMinWidth,
               idealWidth: SettingsPresentation.windowWidth,
               maxWidth: .infinity, maxHeight: .infinity,
               alignment: .topLeading)
        .background(
            ZStack {
                Color.pBg
                LinearGradient(colors: [Color(red: 76/255, green: 196/255, blue: 245/255).opacity(breathe ? 0.14 : 0.07), Color.clear],
                               startPoint: .top, endPoint: .center)
                RadialGradient(colors: [Color(red: 30/255, green: 120/255, blue: 220/255).opacity(breathe ? 0.30 : 0.18), Color.clear],
                               center: .init(x: 0.88, y: 0.96), startRadius: 0, endRadius: 300)
            }
            // 深入安全区：fullSizeContentView 下标题栏底下露的也是这块深蓝，而不是系统窗底色。
            .ignoresSafeArea()
        )
        // 深色外观由 SwiftUI 管理（窗口外观、标题文字颜色跟着走），不手动碰 win.appearance ——
        // 手设会被 SwiftUI 的环境传播改回去。
        .preferredColorScheme(.dark)
        .onAppear(perform: seedAndObserve)
        .sheet(isPresented: $showingPathways) {
            InstallPathwaysView(onRecheck: { _ = refreshFFmpeg() })
        }
    }

    // MARK: - 左列

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHead(t: "壁纸来源")
            Card {
                Row(symbol: "folder.fill", title: "文件夹",
                    sub: store.sourceFolder.isEmpty ? "未设置" : store.sourceFolder) {
                    Button("选择…") { requestFolder() }.buttonStyle(GlowButton())
                        .disabled(session.isScanning)
                        .accessibilityIdentifier("select-button")
                }
                countRow
            }

            SectionHead(t: "播放").padding(.top, 4)
            Card {
                Row(symbol: "repeat", title: "模式") {
                    GlowSegmented(items: PlayMode.allCases.map(SettingsPresentation.playModeLabel),
                                   index: modeIndex)
                        .accessibilityIdentifier("mode-segmented")
                }
                // 置灰联动①：单循环下整行不可交互 + 视觉变淡。
                Row(symbol: "timer", title: "轮换") {
                    GlowStepper(index: rotationIndex,
                                values: SettingsPresentation.rotationChoicesMinutes)
                }
                .disabled(!SettingsPresentation.rotationControlsEnabled(playMode: store.playMode))
                .opacity(SettingsPresentation.rotationControlsEnabled(playMode: store.playMode) ? 1 : 0.34)
                .accessibilityIdentifier("rotation-stepper")
                Row(symbol: "gauge.with.dots.needle.67percent", title: "速度", sub: "音高不变") {
                    HStack(spacing: 9) {
                        GlowSlider(value: $rateDrag, range: 0.5...2, onChanged: {
                            store.rate = Float(rateDrag)
                            applier.applyRate()
                        }, onEnded: {
                            store.persist()
                        })
                        .accessibilityIdentifier("rate-slider")
                        Text(SettingsPresentation.rateLabel(store.rate))
                            .font(mono(11.5))
                            .foregroundStyle(Color.pFg.opacity(0.75))
                            .frame(width: 42, alignment: .trailing)
                            .accessibilityIdentifier("rate-value")
                    }
                }
                Row(symbol: "speaker.wave.2.fill", title: "声音", hairline: false) {
                    HStack(spacing: 9) {
                        // 置灰联动②：静音时滑杆不可交互 + 视觉变淡。
                        GlowSlider(value: volumePercent, range: 0...100, onChanged: {
                            store.volume = SettingsPresentation.volumeFromPercent(
                                SettingsPresentation.volumePercent(store.volume))
                            applier.applyVolume()
                        }, onEnded: {
                            store.persist()
                        })
                        .disabled(!SettingsPresentation.volumeControlsEnabled(isMuted: store.isMuted))
                        .opacity(SettingsPresentation.volumeControlsEnabled(isMuted: store.isMuted) ? 1 : 0.34)
                        .accessibilityIdentifier("volume-slider")
                        Text("\(SettingsPresentation.volumePercent(store.volume))%").font(mono(11.5))
                            .foregroundStyle(Color.pFg.opacity(0.75)).frame(width: 42, alignment: .trailing)
                            .accessibilityIdentifier("volume-value")
                        Toggle("", isOn: soundOn).toggleStyle(GlowToggle()).labelsHidden()
                            .accessibilityIdentifier("sound-toggle")
                    }
                }
            }
        }
    }

    // MARK: - 右列

    private var rightColumn: some View {        VStack(alignment: .leading, spacing: 12) {
            SectionHead(t: "电源与系统")
            Card {
                Row(symbol: "battery.75", title: "电池时播放", sub: "默认开") {
                    Toggle("", isOn: playOnBattery).toggleStyle(GlowToggle()).labelsHidden()
                        .accessibilityIdentifier("battery-toggle")
                }
                Row(symbol: "power", title: "开机自启", hairline: false) {
                    Toggle("", isOn: launchAtLogin).toggleStyle(GlowToggle()).labelsHidden()
                        .accessibilityIdentifier("autostart-toggle")
                }
            }

            SectionHead(t: "维护").padding(.top, 4)
            Card {
                Row(symbol: "arrow.left.arrow.right", title: "转码",
                    sub: "MKV / AVI → MP4", hairline: false) {
                    // ⚠️ 不可用时**只**调 opacity（UI-SPEC §6 的置灰视觉），绝不用 .disabled(true) ——
                    // 那会吃掉点击，三途径说明就永远弹不出来（置灰 + 给途径，必须同时成立）。
                    Button("打开…") {
                        if !openTranscode({ openWindow(id: TranscodeScene.windowID) }) {
                            showingPathways = true
                        }
                    }
                        .buttonStyle(GlowButton(primary: true))
                        .opacity(session.ffmpegAvailable ? 1 : 0.34)
                        .help(session.ffmpegAvailable ? "打开转码窗口"
                                                      : "未检测到 ffmpeg —— 点击查看安装途径")
                        .accessibilityIdentifier("transcode-open")
                }
            }

            SectionHead(t: "运行状态").padding(.top, 4)
            Card {
                Row(symbol: running ? "play.circle.fill" : "pause.circle.fill",
                    title: running ? SettingsPresentation.playbackRunningTitle
                                   : SettingsPresentation.playbackPausedTitle,
                    sub: joinedReasons.isEmpty ? nil : joinedReasons) {
                    Text("").frame(width: 0)
                }
                .accessibilityIdentifier("status-paused")
                Row(symbol: "checkmark.seal.fill", title: "ffmpeg",
                    sub: FFmpegAvailability.label(available: session.ffmpegAvailable), hairline: false) {
                    Text("").frame(width: 0)
                }
                .accessibilityIdentifier("status-ffmpeg")
            }
        }
    }

    // MARK: - 来源卡计数行（空态皮）

    private var isEmpty: Bool {
        session.lastLibraryState.map(SettingsPresentation.isEmptyState) ?? false
    }

    private var countRow: some View {
        HStack(spacing: 12) {
            if isEmpty {
                Tile(symbol: "exclamationmark", warn: true)
            } else {
                Circle().fill(Color.pAccent).frame(width: 6, height: 6)
                    .shadow(color: Color.pGlow, radius: 4)
                    .frame(width: 26)
            }
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(session.playableCount)").font(mono(20, .semibold))
                        .foregroundStyle(isEmpty ? Color.pWarn : Color.pAccent)
                        .shadow(color: isEmpty ? Color.pWarnGlow : Color.pGlow, radius: 7)
                    Text("个可用视频").font(mono(11.5)).foregroundStyle(Color.pFg.opacity(0.6))
                }
                if isEmpty {
                    Text(SettingsPresentation.emptyStateBody).font(mono(10.5))
                        .foregroundStyle(Color.pFg.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            // 空态下**保持可用**：它是恢复路径，置灰等于把用户锁在坏掉的屏幕上。
            Button("重新扫描") { rescanLibrary() }.buttonStyle(GlowButton())
                .disabled(session.isScanning)
                .accessibilityIdentifier("rescan-button")
        }
        .padding(.horizontal, 13).frame(minHeight: 42)
    }

    // MARK: - 运行状态卡读数

    private var running: Bool { arbiter.decision.shouldPlay }

    private var joinedReasons: String {
        SettingsPresentation.joinedReasons(arbiter.decision.activeReasons)
    }

    /// ffmpeg 可用性读数来自 session（AppDelegate.refreshFFmpegAvailability 回填，可观察）——
    /// 视图不再自己扫 PATH，也不直读 AppDelegate 的非观察量（假死卡片的坑）。
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
        // 呼吸动画只在窗口内容出现时启动（UI-SPEC §6 动画红线），关窗即停。
        if !reduceMotion {
            withAnimation(.easeInOut(duration: 10).repeatForever(autoreverses: true)) { breathe = true }
        }
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
