# Pic — 项目长期约定

## CI / Release（.github/workflows/）

- **runner 标签必须是 `xcode-27`**，不是 `macos-latest`。GitHub 托管镜像里 `xcode-27`
  是 OS 最新的一个（macOS 27 / Xcode 27 / arm64 / public preview）；`macos-latest` 仍停在
  macOS 26，而 `Package.swift` 的部署目标是 macOS 27，部署目标高于镜像 SDK 会
  直接构建失败。换标签前先确认这条。runner 实测 **Xcode 27.2 / Apple Swift 6.4 (swiftlang-6.4.0.34.1)**，
  与本机 Xcode 27.0 是同一个 swiftlang 构建号 —— 清单里的 `swift-tools-version:6.4` 在 CI 上安全。
- 分支分工互斥：`ci.yml` 用 `push.branches-ignore: [master]`（+ PR→master + workflow_dispatch），
  `release.yml` 用 `push.branches: [master]`。Release 不跑测试——**master 的提交不会过测试**。
- Release tag 格式 `vYYYY.MM.DD-<run_number>`，说明由上次 tag 以来的提交信息汇总；
  DMG 资产重命名成 `Pic-<tag>.dmg`（`build.sh` 里的 `VERSION="0.1.0"` 是写死的，不重命名各版本同名）。
  无 Secrets 依赖：ad-hoc 签名，`GITHUB_TOKEN` 靠 workflow 自带 `permissions: contents: write`。
- **发布动作 = `git push origin dev:master`**（master 是 dev 的祖先，一律快进，不要 merge commit）。
  已实测一次：run 37491851240 → tag `v2026.10.06-1`，资产 `Pic-v2026.10.06-1.dmg`（2.1 MB），
  产物校验通过（adhoc 签名有效 / `CFBundleIdentifier=com.local.pic` / `LSUIElement=true` /
  `LSMinimumSystemVersion=27.0` / arm64）。`brew install create-dmg` 在 runner 上走主路成功
  （卷里有 `Applications` 符号链接与 `.DS_Store`），`DMG_FALLBACK` 未触发。
  首次发布的说明会取最近 40 条提交（无上次 tag 可 diff），属预期。
- **CI 靠 `swift test --skip` 隔离了一条 VM 上必红的用例**：
  `PowerWatcherTests/testPowerSourceStateKeyIsTheRealSDKKeyAndValuesAreStrings`
  —— 它断言 `readPowerState()` 不得返回 `.failed`，前提是宿主真有电源源；runner 是 VM，
  `IOPSCopyPowerSourcesList` 返回空列表，源码**如实**返回 `.failed`（源码行为正确）。
  用户明确选择「不改代码与用例，只在 CI 侧隔离」。副作用：该用例若改名/删除，`--skip` 会静默
  退化成空匹配。⚠️ `ci.yml` 里那句注释仍写着「正常态 323 变 324」（写于测试数更少时），已过时，待改。
  本机测试数会随功能增长：图片轮播数据层落完后 **366**（CI 隔离后 365）——别把旧数字当基线。
- 缓存：`actions/cache@v6`，path `.build`，key `swiftpm-<OS>-<ARCH>-<sha>` + 前缀回溯。
  冷启 ~60 MB。任务失败时 post 步被 skip，红的运行攒不下缓存。

## 设计文档与 UI 层（`.planning/design/`，gitignored「不对外」）

- 三份设计资产：`DESIGN-SPEC.md` v1.3（令牌 / 刻度 / 状态矩阵 / 无障碍）、`SwiftUI-HANDOFF.md`
  （设计→代码映射 + 7 步迁移顺序）、`prototype.html` + `refinement-v2.html`（原型）、
  `contrast-audit.py`（对比度脚本，读 prototype.html）。
- 2026-10-08 新增两份稿：`image-carousel-design.html`（图片轮播六问定稿 + 高保真，决策：
  独立目录/总像素量三档/三格计数/默认填充/五格式白名单/轮换同视频）与
  `ui-redesign-flat.html`（整体扁平改版：分区身份色 播放橙#F4701B/片库蓝#2C7BE5/队列紫#8A63FF/
  通用青#0E9384，零投影+1px line 描边；`.scope` 块是 contrast-audit 的令牌源，
  `python3 contrast-audit.py ui-redesign-flat.html --dirs flat`，hash 可直达状态）。
- **改版 v2（用户嫌 v1 变化太小，重做整窗）**：`ui-redesign-v2-shell.html` —— 侧栏 216 + 四项导航
  （播放/片库/**队列**/通用，队列从片库分组升级为独立区）+ 两列卡片网格；窗 **1024×680 固定**、
  minWidth 900、AppDelegate fit 上限 900→1120；`tab`/`requestedTab` 改 `SettingsPage` 枚举（通用 2→3），
  `main-tabs` 标识退役换 `nav-*`；Eyebrow 删除；跨列卡不进 LazyVGrid；队列页唯一滚动；
  **来源切换在顶栏右端全局模式位**（用户否决侧栏方案：侧栏只做导航），控件永不截断、只读胶囊挤了先截；
  图片模式：侧栏队列项隐藏、停在队列页切来源须回落片库。令牌块与 v1 相同，40/40 过 AA。
  `contrast-audit.py` 已扩分区色配对（缺令牌自动跳过，向后兼容）。
- **既有无障碍缺陷（改版要顺手修）**：代码 `ink-3=#8A92A3` 白底仅 3.12:1 不达 AA；
  `ok/ok-soft` 4.46:1 也差线。新版取 ink-3 #646C79、ok #097055 + #E0F5EF。
- ⚠️ **规范与实现已漂移**（2026-10-08 核实）：文档里的 `--brand` 仍是红色 `#C03255`，
  代码（`SettingsComponents.swift`）已是暖橙 `#E8862B`；`brandInk`/`brandSoft`/`ink-3`
  (626C7C→8A92A3)/`tileRadius`(14→16)/`ctlRadius`(12→10) 也不一致，且代码多一个文档没有的
  `pBrandText`（brand 作文字时的替身）。**新增任何配色前先对齐文档，别照 §5.4 选色。**
- `SwiftUI-HANDOFF.md` §4 的标识契约已失效：它引用的 `TranscodeSection.swift` /
  `FpsTranscodeSection.swift` **已删除**；「37 个标识被 XCUITest 依赖」不实 ——
  `Tests/` 下 `XCUI` 零命中（无消费方），源码实为 **33 个调用点**（2 个是插值模板）。
  标识的真实价值只剩 VoiceOver。
- UI 层的禁用态是**已知缺口**：`GlowSlider` 读了 `\.isEnabled`，但 `TickSelector` /
  `GlowSegmented` / `SlideSegmented` 都没有（颜色硬编码）；DESIGN-SPEC §7 要求的 0.42 透明
  没有常量，视图手写 0.34。另：字阶无常量，`.system(size:)` 字面量 33 处。
- 在无头 chromium（playwright 缓存里的 `Google Chrome for Testing`）里渲染 + Pillow 切片，
  是复核 HTML 设计产物排版与标注点位置的可靠办法。

## 图片轮播（新功能，数据层已落、UI 未接）

- 核心决策（用户拍板）：独立图片目录（与视频目录并存，可切换）／判定口径 = **总像素量**／
  三格计数（总数·将参与轮播·低于档位）／适配默认「填充」／白名单 jpg,jpeg,png,heic,webp（**不收 gif**）／
  轮换间隔与视频共用同一张值表。轮播方式标签按来源分派：视频=单循环·列表循环·随机，
  图片=**单张不变·顺序轮播·随机轮播**（枚举 `PlayMode` 共用，只有标签分派）。
- 文件：`Sources/PicCore/Media/ImageResolutionTier.swift`（档位 rawValue = 像素阈值）、
  `Sources/PicCore/Media/ImageLibrary.swift`（`ImageSizeProbe` 可注入 + `ImageIOSizeProbe`）。
- 两条易错点：**图片库缓存判等必须含 minPixels**（只按目录缓存会让降档位拿回旧 report，有单测锁）；
  **ImageIO 的 PixelWidth/Height 不应用 EXIF orientation** —— 总像素口径下无影响，若改按短边判定必须先交换宽高。
- `SettingsStore` 的图片键 5 个；`persist()` 写出的键总数 15，被 `PlayModeTests` 的契约锁着（加键必顶红，正常）。

## 本机环境（与 CI 对齐的依据）

- **`swift test` 有 5 个类会挂起**（沙箱限制启子进程 / AVPlayer）：`ProcessCancellationTests`、
  `ProcessTranscodeRunnerTests`、`TranscodeMainActorFreezeTests`、`PlayerControllerFreezeTests`、
  `PlayerControllerSwapTests`。基线副本（worktree @ HEAD）同样挂起 → **不是回归**。
  全量跑前先排除它们，别把「xctest 卡住」误读成自己的改动坏了。
  判据：起 `git worktree add /tmp/<name> HEAD` 跑基线对比。

macOS 27.0.1 / Xcode 27 / Swift 6.4 / arm64。

## 编译零告警门槛（四条路，别只跑一条）

- 真正的门槛是 `swift build --build-tests`、`swift build -c release`、`swift test` 三条。
  **`swift build` 不编译测试目标**，且**增量重建不重报旧告警** —— 判「零告警」必须
  `swift package clean` 后跑，或至少带 `--build-tests`。
- `xcodebuild -project Pic.xcodeproj -scheme Pic` 另有一条**改不掉的**工具提示：
  `appintentsmetadataprocessor … warning: Metadata extraction skipped, no AppIntents.framework dependency found`。
  核实过：该 bool 在 xcspec 里叫 `LM_FILTER_WARNINGS`（对应 `--quiet-warnings`），
  **Pic.app 那次调用已带上它也不管**；工程级设置不下发给 SwiftPM 目标；SWBCore 无可关闭该任务的设置。
  它只是工具级提示，不是编译器诊断，`swift build` / `build.sh` / CI 都不经过 Xcode，看不到它。
- **`Pic.xcodeproj` 的源文件清单是手写的**：Xcode app target 直编 `Sources/PicApp/*.swift`
  并链接本地包的 PicCore 产品（刻意不走 SwiftPM 编 app，避免重复构建）。**每次增删 PicApp
  源文件都必须同步 pbxproj**，否则报 `error: Build input files cannot be found`（曾漏 4 加 3 个僵尸引用）。
  一劳永逸的替代是改用 `PBXFileSystemSynchronizedRootGroup`（尚未做）。
