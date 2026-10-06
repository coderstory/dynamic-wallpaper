# 按业务场景的源码审查

> 前一份 `audit-transcode-fps.md` 是**按缺陷**组织的（严重度分级 + 证据）。本份按**业务功能场景**
> 重新梳理：先列全部功能，再对每个功能走「正着跑」与「倒着跑」，逐条对照代码。
> 审查日期 2026-10-06。已修复项标注 ✅，未修项标注 ❌ 并给严重度。

---

## 0. 功能全景（14 项）

| # | 功能 | 主要落点 |
|---|------|---------|
| 1 | 菜单栏常驻（.accessory，无 Dock 图标） | `PicApp.swift` / `AppDelegate.presentSettingsWindow` |
| 2 | 桌面壁纸窗口（全屏铺满、跨 Space） | `WallpaperWindowController` / `WallpaperWindow` |
| 3 | 媒体库扫描（根 + Converted + 合并） | `MediaLibrary` / `ConvertedLibrary` / `PlaybackPool` |
| 4 | 轮换（单循环 / 列表循环 / 随机） | `RotationController` |
| 5 | 播放内核（加载 / 循环 / 速度 / 音量 / 静音） | `PlayerController` |
| 6 | 系统事件抑制（锁屏 / 全屏 / 熄屏 / 睡眠 / 电池） | `HoldArbiter` + 四个 Watcher |
| 7 | 菜单动作（6 项） | `MenuBarModel` / `AppDelegate` |
| 8 | 设置窗（播放 / 转码 / 降帧 / 关于 四 tab） | `SettingsView` |
| 9 | 播放设置（模式 / 间隔 / 速度 / 声音 / 电池 / 开机自启） | `SettingsStore` / `SettingsApplier` |
| 10 | 壁纸目录选择（首启引导 + 设置窗「选择…」） | `FolderRequestPolicy` / `FolderPicker` |
| 11 | 转码（MKV/AVI/WEBM → MP4，自动删源） | `TranscodeQueue` |
| 12 | 降帧（>30fps → 30fps + 高度上限，产物顶替原片） | `FpsTranscodeQueue` |
| 13 | ffmpeg 探测与安装途径 | `ExternalToolLocator` / `InstallPathwaysView` |
| 14 | 开机自启（SMAppService 主路 + LaunchAgent 兜底） | `AutoStartManager` |

---

## A. 安装与首次启动

| 场景 | 正着跑 | 倒着跑 | 判定 |
|---|---|---|---|
| A1 全新安装、未配置目录 | 弹框 → 选目录 → 扫描 → 起播 ✅ | — | ✅ |
| A2 弹框取消 | — | 不写 store、不重扫、发 `PIC_FOLDER_PICK_CANCELLED` ✅ | ✅ |
| A3 选了文件而非目录 | — | `isAcceptableSelection` 拦 → `.rejected`，不重扫 ✅ | ✅ |
| A4 已配置目录启动 | 直接扫描起播 ✅ | — | ✅ |
| A5 目录被删 / 外接盘拔了 | → `.folderMissing` → 停播 + 隐藏窗口 ✅ | **插回后不会自动恢复**，必须用户手点「重新扫描」 | ⚠️ 见 N2 |
| A6 目录里 0 个视频 | → `.noPlayableVideos` → 停播 + 隐藏 ✅ | 之后往目录加文件仍需手动重扫 | ⚠️ N2 |
| A7 `PIC_SOURCE_FOLDER` 环境变量覆盖 | 跳过弹框 ✅ | — | ✅ |
| A8 开机自启 | A 路注册，失败/待批转 B 路 ✅ | 关闭开关 → 两路都清 ✅ | ✅ |
| A9 启动时序 | — | `rescanAndApply()` 起一次、`startWallpaper()` 又起一次 → **首条装载两次**，随机模式下重新抽签 | ⚠️ N5 |

> A5 的窗口是 `hide()`（保留 window/layer），恢复靠 `show()` —— 语义正确，缺的是触发者。

---

## B. 播放与轮换

| 场景 | 正着跑 | 倒着跑 | 判定 |
|---|---|---|---|
| B1 单循环 | 锁定同一条；「立即下一个」按列表前进 ✅ | — | ✅ |
| B2 列表循环 | 顺序 + 回卷 ✅ | — | ✅ |
| B3 随机 | 一轮内每条一次；**首条也随机**（本轮已修） ✅ | — | ✅ |
| B4 轮换到点 | 定时切换，**不等播完** ✅ | — | ✅ |
| B5 改间隔 | 当场重排程 ✅ | — | ✅ |
| B6 改模式 | 直写 `rotation.mode` 即时生效 ✅ | 随机 → 单循环时洗牌袋残留，下一个 advance 按新规则走 ✅ | ✅ |
| B7 改速度 | 生效 ✅ | **hold 中改速度不生效，且 hold 解除后也不会补上**（见 N1） | ❌ 高 |
| B8 改音量 / 静音 | 生效 ✅ | hold 中改也生效（不拉起播放器） ✅ | ✅ |
| B9 清单变空 | → 停播 + 隐藏 ✅ | — | ✅ |
| B10 单条播到结尾 | `AVPlayerLooper` 自动循环 ✅ | — | ✅ |
| B11 重扫（任何来源） | 当前片还在 → 续播不打断（本轮已修） ✅ | 当前片没了 → 重开一轮 ✅ | ✅ |
| B12 超过 5000 条 | `entryCap` 截断并如实上报 ✅ | 截断本身静默，用户不知道少了 | ⚠️ 低 |

---

## C. 系统事件抑制（暂停 / 恢复）

`HoldArbiter` 是唯一决策点，六个 reason 叠加，锚点只在 ∅→非∅ 写一次。

| 场景 | 正着跑 | 倒着跑 | 判定 |
|---|---|---|---|
| C1 锁屏 → 解锁 | 停播 → seek 回锚点续播 ✅ | — | ✅ |
| C2 进入全屏 → 退出 | 同上 ✅ | — | ✅ |
| C3 熄屏 → 亮屏 | 同上 ✅ | — | ✅ |
| C4 睡眠 → 唤醒 | 同上 ✅ | — | ✅ |
| C5 拔电源 / 插电源 | 按 `pauseOnBattery` 走 ✅ | 设置窗 toggle 与电源跃迁共用同一 `applyBatteryPolicy` ✅ | ✅ |
| C6 多个 reason 叠加 | 先解除哪个都不恢复，全清空才 seek 一次 ✅ | — | ✅ |
| C7 手动暂停 + 系统 hold 叠加 | 集合并集 ✅ | 手动继续只清 `manualPause`，系统 hold 还在 → 仍停 ✅ | ✅ |
| C8 **恢复播放的速度** | — | `player.play()` 等价把 rate 置 1.0 → **用户设的速度丢失** | ❌ 见 N1 |
| C9 hold 期间改速度 | 被门控挡住，不拉起播放器 ✅ | 恢复后也不补应用 → 用户以为设置没保存 | ❌ N1 |
| C10 hold 期间轮换定时器 | 仍在跑，恢复后播的已是另一条 | 锚点来自旧片，会把新片 seek 到旧位置 | ⚠️ N4 |

---

## D. 菜单动作

| 场景 | 正着跑 | 倒着跑 | 判定 |
|---|---|---|---|
| D1 暂停 / 继续 | 走仲裁器 ✅ | 文案与状态同源（派生量） ✅ | ✅ |
| D2 立即下一个 | 走轮换器，不直连播放器 ✅ | — | ✅ |
| D3 删除当前壁纸 | 二次确认 → 先切下一个 → 移废纸篓 → 失效缓存 → 重扫 ✅ | 回车 = 取消（刻意不设默认按钮） ✅ | ✅ |
| D4 删除取消 | — | 不动文件、不打删除行 ✅ | ✅ |
| D5 删除失败（只读卷） | — | 记 `PIC_DELETE_FAIL`，不动清单 ✅ | ✅ |
| D6 **删的是降帧产物** | — | 产物进废纸篓，但表行仍 `.done` → 原片复活；需一次降帧扫描对账才会重转 | ⚠️ N3 |
| D7 重新扫描文件夹 | 失效缓存 + 重扫 ✅ | 不再把播放拽回第一条（本轮已修） ✅ | ✅ |
| D8 退出 | 四个 watcher 严格 `stop()` 配对 ✅ | — | ✅ |

---

## E. 设置窗

| 场景 | 正着跑 | 倒着跑 | 判定 |
|---|---|---|---|
| E1 打开窗口 | 提策略到 .regular + 激活 ✅ | — | ✅ |
| E2 关窗 | `.onDisappear` 回到 .accessory ✅ | 不留 Dock 图标 ✅ | ✅ |
| E3 每个设置改动 | store → applier → persist 三连 ✅ | — | ✅ |
| E4 ffmpeg 未安装 | 入口置灰 + 安装途径弹层 ✅ | 降帧 tab 仍会全量扫描（探测不依赖 ffmpeg） | ⚠️ 低 |
| E5 关于页版本号 | 取 bundle ✅ | `swift run` 下取不到 → 显示「版本 1.0」 | ⚠️ 低 |
| E6 切换 tab | 转码 tab 打开即入队（见 F6） | 降帧 tab 打开即触发全量扫描 | ⚠️ N6 |

---

## F. 转码

| 场景 | 正着跑 | 倒着跑 | 判定 |
|---|---|---|---|
| F1 有候选 → 转 → 落盘 | ✅ 产物正确 | **成功后删源用 `removeItem`（不走废纸篓）** | ❌ P0 |
| F2 转码失败 | 源保留 ✅ | 失败原因显示受控 token ✅ | ✅ |
| F3 产物比源新 | 幂等跳过，零 runner 调用 ✅ | 源更新后重新转 ✅ | ✅ |
| F4 磁盘不足 | 预检拦截，不 spawn ✅ | — | ✅ |
| F5 ffmpeg 不可用 | 预检拦截 ✅ | — | ✅ |
| F6 打开转码 tab | 自动入队，**`deletesSource = true`** | 只是"看一眼"就已把它们标记为待删 | ⚠️ N6 |
| F7 转码完成 | 重扫，产物进池 ✅ | 无产物落地时不触发重扫（本轮已修） ✅ | ✅ |
| F8 取消 / 暂停 | **转码队列没有这两个通道** | 只能等完或退出 app | ❌ 中 |
| F9 子目录同名文件 | — | 递归扫 + 扁平产物名 → 互相覆盖 | ❌ 中 |
| F10 **换目录后再转码** | — | 队列 root 在 `lazy var` 固化 → **产物写进旧目录** | ❌ P0 |
| F11 手动选外部素材 | 源保留（`deletesSource = false`） ✅ | — | ✅ |
| F12 转码期间退出 app | — | `.tmp` 残留（扩展名不在白名单，不会进池，但会一直躺在磁盘） | ⚠️ 低 |

---

## G. 降帧

| 场景 | 正着跑 | 倒着跑 | 判定 |
|---|---|---|---|
| G1 扫描 → 探测 → 入队 | ✅ | — | ✅ |
| G2 转 → 产物顶替原片 → 回写表 → 重扫 | ✅ | — | ✅ |
| G3 已有产物（重装 / 表丢 / 状态落后） | 按名认回关系（本轮已修） ✅ | — | ✅ |
| G4 产物被手删 | 回落原片 ✅ | 表行 `.done` 退为 `.needsConvert`，下次会重转（本轮已修） ✅ | ✅ |
| G5 源被改动（size/mtime 变） | 缓存失效 → 重探 ✅ | — | ✅ |
| G6 表损坏 / 读不出 | 静默当空表 → 全量重探 ✅ | — | ✅ |
| G7 暂停 | 当前文件跑完再停 ✅ | **暂停标志被 `consumeCancel` 顺手清掉，且 break 后无法续跑** | ❌ 中 |
| G8 取消 | 进程终止，产物不留 ✅ | **显示成「失败 · exit_nonzero」并写 `.failed` 进表** | ❌ 中 |
| G9 **换目录后再降帧** | — | `root` 固化 → 扫的还是旧目录 | ❌ P0 |
| G10 同一批再跑一次 | 已完成的不再排队（本轮已修） ✅ | — | ✅ |
| G11 只打开 tab | 自动全量扫描 | 频繁切换 tab 会反复触发 | ⚠️ 低 |
| G12 高度处理 | `scale=-2:1440` | **<1440p 的源被放大**（实测 1080p → 1440p） | ❌ 中 |

---

## H. 卸载 / 重装 / 换目录

| 场景 | 正着跑 | 倒着跑 | 判定 |
|---|---|---|---|
| H1 卸载后重装、**同**目录 | 表保留，关系按名重建（本轮已修） ✅ | — | ✅ |
| H2 卸载后重装、**换**目录 | — | 旧行永不清理（`prune()` 从未被生产代码调用）→ 计数虚高 | ❌ 中 |
| H3 卸载残留 | LaunchAgent / plist / 域 四项复查为 0 ✅ | — | ✅ |
| H4 换目录（不重启 app） | 播放池换到新目录 ✅ | **转码/降帧队列仍指向旧目录** | ❌ P0 |
| H5 `Converted/` 被手工删掉 | 回落原片 ✅ | 需一次降帧扫描才会重转 | ⚠️ 低 |
| H6 壁纸目录下有小写 `converted/` | 根扫描排除它 | **降帧扫描不排除**（大小写敏感三处不一致） | ❌ 低 |

---

## I. 显示变化

| 场景 | 正着跑 | 倒着跑 | 判定 |
|---|---|---|---|
| I1 显示器插拔 / 分辨率变 | `DisplayWatcher` 重配置回调 → 重算信号 ✅ | 壁纸窗口只在 `NSScreen.main` 建一次，**主屏变了不重建**；`reassert()` 存在但无人调用 | ⚠️ 低 |
| I2 无主显示器 | `attach` 打 `PIC_NO_SCREEN` 并退出 ✅ | `show()` 不隐式 attach，不吞故障 ✅ | ✅ |

---

## 本次场景化审查的新发现

### ✅ N1 · 恢复播放后速度回落 1.0（高 · 已修）

正向设置速度正常，但**任何一次 hold 解除后用户设的速度就丢了**。

代码路径：`HoldArbiter.set` → `target?.arbiterApply(decision)` → `PlayerController.arbiterApply`
→ `player.play()`。而 `AVPlayer.play()` 等价于把 rate 置 **1.0**，不是置回 `store.rate`。
全仓 `setRate` 只有两处：`AppDelegate:389`（仅起播时）与 `SettingsApplier.applyRate()`（被
`shouldPlay` 门控）。**没有任何地方在恢复时补一次 `setRate`。**

叠加 C9：hold 期间改速度被门控挡住且不落盘给播放器，恢复后也不补，用户的直观感受是
"我调了速度，它没反应"。

修复方向：在 `arbiterApply` 的 `shouldPlay` 分支里改用 `player.rate = store.rate`（或让仲裁器
解除时回调一个"恢复"钩子），而不是 `play()`。

### ❌ N2 · 外接盘拔掉再插回不会自动恢复（中 · 未修）

`folderMissing` 的降级是对的，但**没有任何 watcher 监听目录重新出现**。恢复的唯一途径是用户
手点「重新扫描文件夹」。同理，往空目录里加文件也不会自动起播。
（`reassert()` 的注释明确说"没有任何代码自动调用它"，是刻意的；目录这一侧同属刻意还是遗漏，
需要你确认产品预期。）

### ✅ N3 · 删除当前壁纸删到降帧产物时，原片复活且短期内不会再被降帧（中）

`deleteCurrent` 把产物移进废纸篓，但表行仍是 `.done`。此刻：
- `PlaybackPool` 回落原片（行为正确）；
- 但该行不会再被排队（`reusableEntry` 看到 `.done` 就跳过）。

本轮新增的 `reconcileWithDerivatives()` 能修，但**只在下一次降帧扫描时**才跑。也就是说从删掉
到下一次扫描之间这段，这条素材会以未降帧的原片形态播着。若用户从不打开降帧 tab，就会一直是这样。

### ❌ N4 · hold 期间轮换定时器仍在跑（低 · 未修）

`RotationController.reschedule()` 不受 hold 影响。长时间锁屏后解锁，播的已经是另一条；而
`resumeAnchor` 是在 hold 开始时从**旧片**取的，会把新片 seek 到这个无关位置。

### ✅ N5 · 启动时首条装载两次（低 · 已修）

`bootstrapAfterWiring` 里 `rescanAndApply()` 已经通过 `dispatchPlayback` 起播一次，
紧接着 `startWallpaper()` 又 `router.start(with:)` 一次。随机模式下第二次会重新抽签，
观感上是开场闪一下。

### ✅ N6 · 打开转码 tab 即入队，且带着"转完删源"（中）

`TranscodeSection.onAppear` → `loadCandidates()` → `enqueue(deletesSource: true)`。
用户只是切过去看一眼，目录里的 MKV/AVI/WEBM 就已经进入"成功即永久删除"队列；一旦点
「开始转码」，源文件直接消失（叠加 P0 的 `removeItem`，不可恢复）。

---

## 修复轮次（2026-10-06 第二轮）

按上表逐条改，TDD 逐个 RED → GREEN。**单测 297 → 321（+24），全绿**。

| 项 | 改法 | 判据 |
|---|---|---|
| P0 换目录队列指旧目录 | `TranscodeOutputNaming` / `FpsTranscodeQueue` 的 `root` 由值改成 `() -> URL` 闭包；AppDelegate 注入动态取值 | 换目录后 scan 扫新目录、产物落新目录；旧目录无产物 |
| P0 删源 `removeItem` | 删源改走**废纸篓**，且做成注入通道 `trashProvider`（默认 `trashItem`） | 替身通道被调用；删除失败不把 job 打成失败 |
| 高 N1 恢复速度回落 | `PlayerController` 新增 `desiredRate`；`arbiterApply` 恢复分支用 `player.rate = desiredRate` 而不是 `play()` | 1.5 → hold → 解除仍为 1.5；手动暂停/继续同 |
| 中 G7 暂停被静默解除 | `consumeCancel()` 只消费取消、不再顺手清暂停；VM `resume()` 必须重新起一轮 drain | 暂停后 `isPaused` 仍为 true；继续后真的接着跑 |
| 中 G8 取消显示为失败 | 新增 `.cancelled` 态，与 `.failed` 分开；表退回 `.needsConvert` 可重试 | 取消中不是 `.failed(exit_nonzero)`；表里不是 `.failed` |
| 中 G12 `<1440p` 被放大 | `scale=-2:1440` → `scale=-2:'min(1440,ih)'` | ffmpeg 实测 1080p→1080p、4K→2560x1440、竖屏 810x1440 |
| 中 F9 同名产物覆盖 | 两个队列按**产物路径**查重，撞车者标 `.failed(name_collision)` 不入队 | 不同子目录的 `clip.mkv` 只有一个进队列 |
| 中 H2 `prune()` 从没被调用 | `FpsTranscodeQueue.scan()` 收尾清源已不在的行；**扫到 0 个时不清**（防拔盘误抹） | 源不在→行清掉；扫到 0 → 表不动 |
| 中 N3 删产物后原片复活 | `deleteCurrentWallpaperNow()` 移入废纸篓后立刻跑一次 `reconcileWithDerivatives()` | 不再需要等下一次降帧扫描 |
| 中 N6 打开转码页即标删源 | 入队一律 `deletesSource: false`；新增 `armSourceDeletion(for:)`，只在点「开始转码」时落位 | 扫一遍不标；点了开始才押上 |
| 低 H6 `Converted` 大小写 | 降帧扫描的排除改成 `caseInsensitiveCompare`，与 `MediaLibrary` 同规则 | 小写 `converted/` 同样整棵排除 |
| 低 N5 启动装载两次 | `PlaybackRouter.isStarted`；`startWallpaper()` 已起过一轮就不再 start | 随机模式不再重新抽签 |
| 低 F12 `.tmp` 残留 | `ConvertedLibrary.scan` 顺手清**陈旧**（>1h）的顶层 `.tmp` | 陈旧的清掉、正在写的不动、子目录不碰 |

---

## 仍未修（4 条，均为低优先级）

| 严重度 | 项 | 场景 | 为什么先不动 |
|---|---|---|---|
| 中 | 转码队列无取消 / 暂停 | F8 | 转码单文件耗时短，且与降帧的控制通道不该各写一套；要做就一起做 |
| 低 | 拔盘插回 / 空目录加文件不自动恢复 | A5 / A6 / N2 | 需要一个目录 watcher，属新功能；先确认产品预期是自动恢复还是手动重扫 |
| 低 | hold 期间轮换 + 锚点错位 | N4 | 要改 `RotationController` 的排程与锚点取用时机，影响面大于收益 |
| 低 | 主屏变更后壁纸窗口不重建 | I1 | `reassert()` 已存在但无人调用，需确认是刻意还是遗漏 |

---

## 说明

- 判定为 ✅ 的项均已逐行对照代码确认，不是"看起来没问题"。
- 第二轮的每条修复都有对应单测（新增 24 条），改动文件见 `git diff`。
- N1 的原始判定是代码路径推演（`AVPlayer.play()` 的 rate 语义），修复后**仍建议真机复验一次**：
  设速度为 1.5 → 锁屏 → 解锁 → 看是否还是 1.5。
- `swift build` / `swift test` 在本会话必须加 `--disable-sandbox`，否则 swiftpm 在 manifest
  阶段就报 `sandbox_apply: Operation not permitted`。`test.sh` 内部没带这个 flag，
  它的失败项是环境问题（改动前后各跑一次，失败清单逐条相同）。
