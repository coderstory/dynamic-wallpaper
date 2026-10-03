import SwiftUI
import AppKit
import PicCore

/// 设置窗主体（UI-SPEC §7 双列：左来源/播放，右电源与系统/维护/运行状态）。
///
/// 05-02 起六个可调项**全部**是真绑定：每个控件的写入口经
/// `store.<键> = …` → `SettingsApplier.apply*()`（当场生效）→ `store.persist()`
/// —— 窗口内没有任何「渲染假数据」的 `@State`（速度行的拖动暂态除外，
/// 它每次变更都直通 store）。量纲换算全部走 `SettingsPresentation`，视图里不出现第二份。
struct SettingsView: View {
    @Environment(SettingsStore.self) private var store
    @Environment(SettingsApplier.self) private var applier
    @Environment(HoldArbiter.self) private var arbiter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 「电池时播放」toggle 的当场重估。**闭包注入**，视图不持有 AppDelegate
    /// （与 terminate / presentSettings 同型的注入模式，D-10 装配点不动）。
    let reapplyBatteryHold: () -> Void

    // ── 唯一保留的 @State（都不是「渲染假数据」）──
    // 速度滑杆的拖动暂态（每次 onChanged 直通 store + applier）。
    @State private var rateDrag: Double = 1.0
    // 开机自启：本地 @State，不持久化（SettingsStore 7 键冻结，不加第 8 键）。
    // 行为接线：Phase 7 SYS-01
    @State private var launchAtLogin = false
    // 计数与空态皮的真数据源（MediaLibraryReport）在 05-03 接线。
    @State private var playableCount = 0
    @State private var breathe = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            leftColumn
                .frame(maxWidth: .infinity, alignment: .leading)
            rightColumn
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        // SC-1：宽 780 / min 680，两个数只从 SettingsPresentation 读。
        .frame(minWidth: SettingsPresentation.windowMinWidth,
               idealWidth: SettingsPresentation.windowWidth)
        // 高随内容撑，不写死（UI-SPEC §13 坑 2）。
        .fixedSize(horizontal: false, vertical: true)
        .background(
            ZStack {
                Color.pBg
                LinearGradient(colors: [Color(red: 76/255, green: 196/255, blue: 245/255).opacity(breathe ? 0.14 : 0.07), Color.clear],
                               startPoint: .top, endPoint: .center)
                RadialGradient(colors: [Color(red: 30/255, green: 120/255, blue: 220/255).opacity(breathe ? 0.30 : 0.18), Color.clear],
                               center: .init(x: 0.88, y: 0.96), startRadius: 0, endRadius: 300)
            }
        )
        .onAppear(perform: seedAndObserve)
    }

    // MARK: - 左列

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHead(t: "壁纸来源")
            Card {
                Row(symbol: "folder.fill", title: "文件夹",
                    sub: store.sourceFolder.isEmpty ? "未设置" : store.sourceFolder) {
                    // 行为接线：05-03（复用 Phase 4 的 NSOpenPanel + 重扫管线）
                    Button("选择…") {}.buttonStyle(GlowButton())
                }
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Color.pAccent).frame(width: 6, height: 6)
                            .shadow(color: Color.pGlow, radius: 4)
                            .frame(width: 26)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(playableCount)").font(mono(20, .semibold))
                            .foregroundStyle(Color.pAccent)
                            .shadow(color: Color.pGlow, radius: 7)
                        Text("个可用视频").font(mono(11.5)).foregroundStyle(Color.pFg.opacity(0.6))
                    }
                    Spacer(minLength: 12)
                    // 行为接线：05-03（与维护卡的「扫描」同一重扫动作）
                    Button("重新扫描") {}.buttonStyle(GlowButton())
                }
                .padding(.horizontal, 13).frame(minHeight: 42)
            }
            Hint(t: "递归扫子目录 · 只认 MP4 / MOV / M4V")

            SectionHead(t: "播放").padding(.top, 4)
            Card {
                Row(symbol: "repeat", title: "模式") {
                    GlowSegmented(items: PlayMode.allCases.map(SettingsPresentation.playModeLabel),
                                   index: modeIndex)
                        .accessibilityIdentifier("mode-segmented")
                }
                // 置灰联动①（UI-03）：单循环下整行不可交互 + 视觉变淡。
                Row(symbol: "timer", title: "轮换") {
                    GlowStepper(index: rotationIndex,
                                values: SettingsPresentation.rotationChoicesMinutes)
                }
                .disabled(!SettingsPresentation.rotationControlsEnabled(playMode: store.playMode))
                .opacity(SettingsPresentation.rotationControlsEnabled(playMode: store.playMode) ? 1 : 0.34)
                .accessibilityIdentifier("rotation-stepper")
                Row(symbol: "gauge.with.dots.needle.67percent", title: "速度", sub: "音高不变") {
                    HStack(spacing: 9) {
                        // 拖动中只对播放器生效不写盘；拖动结束 persist 恰一次。
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
                        // 置灰联动②（UI-03）：静音时滑杆不可交互 + 视觉变淡。
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
                        Toggle("", isOn: isMuted).toggleStyle(GlowToggle()).labelsHidden()
                            .accessibilityIdentifier("sound-toggle")
                    }
                }
            }
        }
    }

    // MARK: - 右列

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHead(t: "电源与系统")
            Card {
                Row(symbol: "battery.75", title: "电池时播放", sub: "默认关") {
                    Toggle("", isOn: pauseOnBattery).toggleStyle(GlowToggle()).labelsHidden()
                        .accessibilityIdentifier("battery-toggle")
                }
                Row(symbol: "power", title: "开机自启", hairline: false) {
                    // 行为接线：Phase 7 SYS-01（本地 @State，不持久化 —— SettingsStore 7 键冻结）
                    Toggle("", isOn: $launchAtLogin).toggleStyle(GlowToggle()).labelsHidden()
                        .accessibilityIdentifier("autostart-toggle")
                }
            }
            Hint(t: "全屏 / 锁屏 / 熄屏 / 睡眠时自动暂停")

            SectionHead(t: "维护").padding(.top, 4)
            Card {
                // 行为接线：05-03（同一重扫动作；spike 缺的行，UI-SPEC §13 要求补齐）
                Row(symbol: "arrow.triangle.2.circlepath", title: "重新扫描") {
                    Button("扫描") {}.buttonStyle(GlowButton())
                }
                Row(symbol: "arrow.left.arrow.right", title: "转码",
                    sub: "MKV / AVI → MP4 · 待后续版本", hairline: false) {
                    // 行为接线：Phase 6（disabled 占位，不做空窗口）
                    Button("打开…") {}.buttonStyle(GlowButton(primary: true)).disabled(true)
                        .accessibilityIdentifier("transcode-open")
                }
            }

            SectionHead(t: "运行状态").padding(.top, 4)
            Card {
                // 暂停与否是真值（arbiter 派生量）；原因文案的全 6 case 映射在 05-03，
                // 这里先渲染 reason token 列表。
                Row(symbol: arbiter.decision.shouldPlay ? "play.circle.fill" : "pause.circle.fill",
                    title: arbiter.decision.shouldPlay ? "播放中" : "已暂停",
                    sub: statusReasonTokens.isEmpty ? nil : statusReasonTokens) {
                    Text("").frame(width: 0)
                }
                // 行为接线：05-03（FFmpegAvailability 的 PATH 探测）
                Row(symbol: "checkmark.seal.fill", title: "ffmpeg", sub: "未检测", hairline: false) {
                    Text("").frame(width: 0)
                }
            }
        }
    }

    private var statusReasonTokens: String {
        arbiter.decision.activeReasons.map { String(describing: $0) }.joined(separator: "、")
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

    private var isMuted: Binding<Bool> {
        Binding(
            get: { store.isMuted },
            set: {
                store.isMuted = $0
                applier.applyMuted()
                store.persist()
            })
    }

    private var pauseOnBattery: Binding<Bool> {
        Binding(
            get: { store.pauseOnBattery },
            set: {
                store.pauseOnBattery = $0
                store.persist()
                // 当场重估：用最近一次已知的电源状态走同一个映射，
                // 不等下一次电源跃迁（PLAY-10）。
                reapplyBatteryHold()
            })
    }

    // MARK: - onAppear

    private func seedAndObserve() {
        rateDrag = Double(store.rate)
        // 呼吸动画只在窗口内容出现时启动（UI-SPEC §6 动画红线），关窗即停。
        if !reduceMotion {
            withAnimation(.easeInOut(duration: 10).repeatForever(autoreverses: true)) { breathe = true }
        }
        emitWindowGeometry()
    }

    /// 几何探针（SC-1 的探针半边）：窗口出现后打一行 `PIC_SETTINGS_WINDOW`，
    /// 经 `PIC_EVIDENCE_FILE` mirror 进证据文件（XCUITest/探针 → 可 grep 证据的桥）。
    /// 延迟半秒等 SwiftUI 把 Window 装进 NSApp.windows。
    private func emitWindowGeometry() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard let win = NSApp.windows.first(where: { $0.title == "Pic 设置" }) else { return }
            WallpaperWindowController.emit(
                "PIC_SETTINGS_WINDOW width=\(Int(win.frame.width.rounded())) minWidth=\(Int(win.contentMinSize.width.rounded()))")
        }
    }
}
