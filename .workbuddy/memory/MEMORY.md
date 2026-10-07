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
  退化成空匹配（正常态 323 tests，退化成 324）——摘要行是唯一线索。
- 缓存：`actions/cache@v6`，path `.build`，key `swiftpm-<OS>-<ARCH>-<sha>` + 前缀回溯。
  冷启 ~60 MB。任务失败时 post 步被 skip，红的运行攒不下缓存。

## 本机环境（与 CI 对齐的依据）

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
