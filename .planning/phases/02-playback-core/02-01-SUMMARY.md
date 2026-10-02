---
phase: 02-playback-core
plan: 01
subsystem: playback-core-foundation
tags: [swiftpm, xctest, holdarbiter, settingsstore, playercontroller, d-01, d-02, d-03, d-06]
requires: [Phase 1 GATE=A]
provides: [SettingsStore, HoldArbiter, PlayerController, PlaybackTarget, Seed, PlayMode, MenuBarModel]
affects: [02-02, 02-03, 02-04, phase-03, phase-04, phase-05]
tech-stack:
  added: [swiftpm, xctest]
  patterns: [veto-set, single-assembly-point, single-re-evaluate-entry]
key-files:
  created:
    - Package.swift
    - Sources/PicCore/State/HoldReason.swift
    - Sources/PicCore/State/PlaybackDecision.swift
    - Sources/PicCore/State/HoldArbiter.swift
    - Sources/PicCore/State/SettingsStore.swift
    - Sources/PicCore/Playback/PlayerController.swift
    - Sources/PicCore/App/MenuItem.swift
    - Sources/PicApp/PicApp.swift
    - Sources/PicApp/AppDelegate.swift
    - Tests/PicCoreTests/HoldArbiterTests.swift
    - Tests/PicCoreTests/SettingsStoreTests.swift
    - scripts/make-fixtures.sh
    - scripts/dev-seed.sh
    - .planning/phases/02-playback-core/evidence/gate-01-locked-session.log
    - .planning/phases/02-playback-core/evidence/gate-01-locked-session.md5
    - .planning/phases/02-playback-core/evidence/gate-rerun.log
    - .planning/phases/02-playback-core/evidence/lock-state.txt
  modified:
    - .gitignore
decisions:
  - "PDCA-A1 结论 = blocked（会话锁着，run-gate.sh 刻意未重跑）；GATE=A 的适用边界仍限定在锁屏会话"
  - "Seed 嵌套为 SettingsStore.Seed —— 计划符号块里的冻结签名要求限定名，顶层 Seed 解析不到"
  - "resumeAnchor 用 TimeInterval(秒) 而非 ARCHITECTURE §6.4 的 CMTime —— State/ 必须零 AVFoundation"
  - "多 reason 叠加（锁屏+全屏顺序、幂集 2^6）本 Phase 构造不出来，已登记为 Phase 3 的 TEST-01"
metrics:
  duration: 42min
  completed: 2026-10-03
  commits: 4
plan_head_before: 46bf4a4fbb03861e27c4330ac967efb3a85c51eb
plan_head_after: dd5adc4269494d0e28699eeb4d0e2e0264c14719
actuals:
  tokens: 41000
  tasks: 4
  commits: 4
status: complete
---

# Phase 02 Plan 01: 播放内核竖切地基 Summary

第一份产品代码落地：SwiftPM 包结构、14 条 XCTest、三个接口定稿、门禁复跑结论（BLOCKED）。

---

## 🔴 诚实基线

**产品未在解锁会话验证过。** 屏幕全程锁着（`CGSSessionScreenIsLocked=1`、`loginwindow` PID 489），
`run-gate.sh` 刻意**没有**重跑。下面「跑过」一栏里没有任何一条来自解锁会话。

### 跑过（命令可复现，数字来自实跑）

| 项 | 命令 | 结果 |
|---|---|---|
| 备份 Phase 1 门禁日志 + 当场比对 md5 | `cp` + `md5 -q` | 两份同为 `af32978a623e67d8afe9842368a47b8d`，`GATE01_MD5_MATCH_AT_BACKUP=1` |
| 锁状态探针（`mktemp -d`，跑完销毁） | `swiftc` + `CGSessionCopyCurrentDictionary()` | `LOCKED=1 LOCKEDTIME=1790976529 ONCONSOLE=1`，`loginwindow` PID 489 |
| 产品包编译 | `swift build` | 退出码 0，产出 `.build/debug/Pic`（67840 字节） |
| 单测 | `swift test` | `Executed 14 tests, with 0 failures`（6 仲裁 + 8 设置） |
| 测试语料生成 | `bash scripts/make-fixtures.sh` | `count=3 bytes=3968791`，三个 mp4 各 >0 字节 |
| 真实素材抽样 | `bash scripts/make-fixtures.sh --with-real 3` | `recursion=disabled`，3 个符号链接、3 个普通 mp4、`du -sk`=4272 KB |
| 设置预置 | `bash scripts/dev-seed.sh` | `defaults write com.local.pic sourceFolderPath` 已执行并回读成功 |
| T3 行为判据 | 剥注释 grep（AVFoundation / absoluteString / priority / NSApp / PlayMode case 数） | 全部 0 / 1，命中数与计划一致 |
| T4 行为判据 | `disableLooping`@42 < `removeAllItems`@43；`item.rate|item.volume` 计数 0 | `PLAYBACK_LAYER_OK` |

### 没跑过（没做，不是做不到）

| 项 | 为什么没跑 |
|---|---|
| **解锁会话的 `run-gate.sh` 复跑** | 屏幕锁着。这正是 PDCA-A1 的内容，结论已按 BLOCKED 落盘 |
| 视频真的在桌面图标后面播 | 渲染层是 Plan 02-02 的活；本 plan 只建播放内核与装配点 |
| 菜单栏图标肉眼确认 | 本机 `screencapture` 无屏幕录制权限，且会话锁定 |
| `load(url:)` 的运行时调用序 | 计划已说明不写调用序单测（`disableLooping()` 直连真实 `AVPlayerLooper`，无注入点可造 fake），改由行号判据承担 |
| 多 reason 叠加 / 幂集 2^6 | 本 Phase `HoldReason` 只有 1 个 case，构造不出来 —— **不冒充已验证**，见下 |

### 应该能跑但未测

| 项 | 逻辑依据 | 未测什么 |
|---|---|---|
| `HoldArbiter` 在多 reason 下锚点不被二次覆盖 | `set()` 的 `if before.isEmpty && !after.isEmpty` 只在空→非空时写锚点，与 reason 个数无关 | 只用单 reason 走过一遍；第二个 reason 叠加要到 Phase 3 才被真正压测 |
| `SettingsStore.persist()` 的完整往返 | 六个键都走 `defaults.set` | 只回读了 `rate`/`volume`/`muted`/`sourceFolderPath` 四个键 |
| `AVPlayerLooper` 真循环 | Phase 1 `WallpaperSpike` 的 `Playback` 类同形状已实跑过 | 产品的 `load(url:)` 路径本身没有真视频走过 |
| `resolvedFolderURL()` 指向真实视频目录 | 单测已验证路径语义 | 没有真拿它喂过 `MediaLibrary`（Phase 4） |

### 假定依赖

| 项 | 假定内容 | 未验证之处 |
|---|---|---|
| 打包成 `.app` 后 `bundle id = com.local.pic`，`UserDefaults.standard` 落进正确域 | 沿用 `build.sh` 现有的 `CFBundleIdentifier` | 未打包验证过；开发期靠 `dev-seed.sh` 的两条路径绕过 |
| `com.local.pic` 域里已预置 `sourceFolderPath` | 本 plan 实际执行了 `defaults write` 并回读确认 | Phase 4 起要换成用户自选目录 |
| Phase 1 的层级写法（`CGWindowLevelForKey(.desktopWindow)` = -2147483623）在解锁会话同样成立 | 原值来自 `gate-01.log` | **未在解锁会话复跑** —— 这是 BLOCKED 的直接后果 |

---

## 任务执行结果

| Task | 内容 | Commit | 结果 |
|---|---|---|---|
| T1 | PDCA-A1 门禁复跑 | `6969738` | BLOCKED，如实落盘 |
| T2 | SwiftPM 骨架 + ffmpeg 语料 + dev-seed | `22a3c6d` | `FIXTURES_AND_PACKAGE_OK` |
| T3 | State 层三接口 + 14 条单测 | `4a9741e` | RED 7 failures → GREEN 0 failures |
| T4 | Playback 层 + `wiring()` | `dd5adc4` | `PLAYBACK_LAYER_OK` |

---

## T1：PDCA-A1 门禁复跑 —— **BLOCKED**

证据四件（全部在 `.planning/phases/02-playback-core/evidence/`）：

```
gate-01-locked-session.md5   三行 md5 记录，GATE01_MD5_MATCH_AT_BACKUP=1
gate-01-locked-session.log    Phase 1 唯一原始证据的整份备份
lock-state.txt                LOCKED=1 LOCKEDTIME=1790976529 ONCONSOLE=1 / LOGINWINDOW_PID=489
gate-rerun.log                GATE_RERUN=blocked（首行）
```

`gate-rerun.log` 全文：

```
GATE_RERUN=blocked
REASON=session_locked CGSSessionScreenIsLocked=1 loginwindow_pid=489
CONSEQUENCE=门禁 GATE=A 的适用边界仍限定在锁屏会话；Phase 2 SUMMARY 必须写明「产品未在解锁会话验证过」
SOURCE_LOG=.planning/phases/02-playback-core/evidence/gate-01-locked-session.log
```

**备份先于一切。** `run-gate.sh` 会把结果写进 `.planning/spike/out/gate-01.log`，直接跑会覆盖 Phase 1
唯一的锁屏会话原始证据。md5 在跑之前就记下来了，且此后**不再**与可能已被覆盖的 `gate-01.log` 比对
（重跑之后两者必然不等，那不是备份失败）。

---

## 三个接口的定稿签名

这是本 plan 除播放内核外的第二产出 —— Phase 3 与 Phase 4 只接它们，不重写。

### ★ 之一 `SettingsStore`（`Sources/PicCore/State/SettingsStore.swift`）

```swift
@MainActor @Observable public final class SettingsStore {
    public enum Key {                          // scripts/dev-seed.sh 写的键必须与此一致
        public static let sourceFolderPath = "sourceFolderPath"
        public static let rate = "rate"
        public static let volume = "volume"
        public static let muted = "muted"
        public static let playMode = "playMode"
        public static let rotationInterval = "rotationInterval"
    }
    public static let envSourceFolderKey = "PIC_SOURCE_FOLDER"

    public struct Seed: Sendable {             // 形状定死
        public var sourceFolder: String
        public var rate: Float
        public var volume: Float
        public var isMuted: Bool
        public var playMode: PlayMode
        public var rotationInterval: TimeInterval
        public init(sourceFolder: String = "", rate: Float = 1.0, volume: Float = 1.0,
                    isMuted: Bool = false, playMode: PlayMode = .loopSingle,
                    rotationInterval: TimeInterval = 300)
    }

    public var sourceFolder: String
    public var rate: Float
    public var volume: Float
    public var isMuted: Bool
    public var playMode: PlayMode
    public var rotationInterval: TimeInterval

    public init(defaults: UserDefaults, seed: SettingsStore.Seed)
    public func resolvedFolderURL() -> URL?
    public func fileExists(at url: URL) -> Bool
    public func persist()
}

public enum PlayMode: String, CaseIterable, Sendable { case loopSingle }   // 其余 case 属 Phase 4
```

解析三级优先：`PIC_SOURCE_FOLDER` 环境变量 > `UserDefaults` 键 > `init(defaults:seed:)` 的 seed。
`resolvedFolderURL()` 只走 `URL(fileURLWithPath:)`，`fileExists(at:)` 只走 `url.path` —— Pitfall 5 的
「喂 URL 字符串导致检查恒为 false」在单测里被锁住（`testResolvedFolderURLHasNoSchemeSeparator`）。

### ★ 之二 `HoldArbiter`（`Sources/PicCore/State/HoldArbiter.swift`）

```swift
@MainActor public protocol PlaybackTarget: AnyObject {
    func arbiterCurrentPosition() -> TimeInterval
    func arbiterSeek(to seconds: TimeInterval)
    func arbiterApply(_ decision: PlaybackDecision)
}

@MainActor public final class HoldArbiter {
    public private(set) var decision: PlaybackDecision
    public init(target: PlaybackTarget? = nil)
    public func attach(_ target: PlaybackTarget)
    public func set(_ reason: HoldReason, active: Bool)
}

public enum HoldReason: Hashable, Comparable, CaseIterable, Sendable {
    case manualPause                    // order 0；Phase 3 加 fullscreen/screenLocked/…
    public var order: Int { get }
}

public struct PlaybackDecision: Equatable, Sendable {
    public let holds: Set<HoldReason>
    public var shouldPlay: Bool { get }          // holds.isEmpty
    public var activeReasons: [HoldReason] { get }   // 仅供 UI 文案
}
```

`Set<HoldReason>` veto 集合，**不是**优先级链（D-11）。四个不变式全部被单测锁住：

1. `holds` 是唯一播放判据
2. 锚点在 ∅→非∅ 写入，非∅→∅ 消费并清空
3. 锚点生命周期内不被二次暂停覆盖
4. 重复 `set(reason, active:)` 幂等（`guard before != after`）

### ★ 之三 `PlayerController`（`Sources/PicCore/Playback/PlayerController.swift`）

```swift
@MainActor public final class PlayerController: NSObject, PlaybackTarget {
    public let player: AVQueuePlayer
    public private(set) var playerLayer: AVPlayerLayer?
    public func attach(to layer: AVPlayerLayer)
    public func load(url: URL)
    public func setRate(_ r: Float)
    public func setVolume(_ v: Float)
    public func setMuted(_ m: Bool)
    // + PlaybackTarget 的三个 arbiter* 方法
}
```

`rate` / `volume` / `isMuted` 挂在 `player` 上，**不挂 item**（D-13）—— `AVPlayerLooper` 的模板 item
属性在 init 时就冻结，挂 item 会让 Phase 5 的 PLAY-10「改设置当场生效」变成假的。判据是
`grep -cE 'item\.(rate|volume)' == 0`。

### `MenuBarModel`（菜单文案的唯一来源）

```swift
public enum MenuItemID: String, CaseIterable { case pauseResume, openSettings, quit }
public struct MenuBarModel {
    public static func label(for id: MenuItemID, isPaused: Bool) -> String
    public static func labels(isPaused: Bool) -> [String]        // 恰好 3 项
    @MainActor public static func perform(_ id: MenuItemID, isPaused: Bool,
                                          store: SettingsStore, arbiter: HoldArbiter,
                                          quit: () -> Void)
}
```

「菜单里不出现当前播放的文件名」（MENUBAR-08）之所以在 Plan 02-03 能变成一条 `swift test` 断言：
`MenuContentView` 必须遍历 `MenuItemID.allCases` 渲染，哨兵串 `clip-sentinel.mp4` 写死在测试里。

---

## 「接口定死」的确切边界

**不再变**：三个接口的**公开签名** + `Seed` / `PlayMode` 的**形状**。
**随阶段增长（已登记归属，不是漏定）**：

| 归属 | 内容 |
|---|---|
| Phase 3 | `HoldReason` 新增 `.fullscreen` / `.screenLocked` / `.displayAsleep` / `.systemSleeping` / `.battery` |
| Phase 4 | `PlayMode` 新增随机轮换 / 顺序轮播 / 播完停止 |

两处都只加 `case` 与 `order` 分支，**不改任何已有签名**。

---

## 登记给下游的未验证项（不冒充已验证）

| 判据 | 落在 | 为什么不在本 Phase |
|---|---|---|
| 多 reason 叠加（锁屏状态下退出全屏不恢复播放） | **Phase 3 TEST-01** | 本 Phase `HoldReason` 只有 1 个 case，构造不出来 |
| 幂集 2^6 = 64 子集全覆盖 | **Phase 3 TEST-01** | 同上；本 Phase 幂集只有 2 个子集 |
| 锚点不被第二个 reason 二次覆盖 | 02-03 T2（用「暂停期间 position 被别路改掉」模拟） | 不需要第二个 reason，本 Phase 也没测 |

幂集测试写成**运行时**从 `HoldReason.allCases` 生成子集，Phase 3 加 case 后自动从 2 个扩到
32 个，测试代码一个字都不用改。

---

## Deviations from Plan

### 1. [Rule 3 - Blocking] SwiftPM 拒绝空 target

- **发现于**：T2 `swift build`
- **问题**：计划说 T2「建空骨架即可」，但 SwiftPM 对空 target 直接报
  `error: 'pic': target 'PicCore' referenced in product 'PicCore' is empty`，`swift build` 无法退出 0。
- **处理**：T2 加一个只含注释的 `Sources/PicCore/PicCoreShim.swift` 让 PicCore 非空；
  T3 写入 `State/` 四个文件的同一次提交里删掉它。
- **净结果**：该文件在本 plan 的最终 diff 里**不存在**（创建与删除都在 plan 内）。

### 2. [Rule 3 - Blocking] `SettingsStore.Seed` 在顶层解析不到

- **发现于**：T3 首次编译
- **问题**：计划 action 段把 `Seed` 写成顶层类型，但符号块里冻结的签名是
  `init(defaults: UserDefaults, seed: SettingsStore.Seed)`。顶层 `Seed` 在 Swift 里是 `PicCore.Seed`，
  限定名 `SettingsStore.Seed` **解析失败**（`'Seed' is not a member type of class 'PicCore.SettingsStore'`）。
- **处理**：把 `Seed` 嵌套进 `SettingsStore`。符号块（下游真正依赖的那份）优先于 action 段的排版。
- **判据仍成立**：`public struct Seed` 与 `public enum PlayMode` 都在 `SettingsStore.swift` 内可 grep 到。

### 3. [Rule 3 - Blocking] `AppDelegate` 存储属性需要 `@MainActor`

- **发现于**：T4 首次编译
- **问题**：`SettingsStore` / `HoldArbiter` / `PlayerController` 全是 `@MainActor`，
  在非隔离的 `NSApplicationDelegate` conformance 里初始化它们报 `ActorIsolatedCall`。
- **处理**：`final class AppDelegate` 标 `@MainActor`。这与「装配点在主线程」的语义一致。

### 4. [Plan defect - 判据] 注释里的字面串会让 grep 计数判据失真

三处都是同一个坑：计划用**计数**做判据（`grep -c`），而我在注释里写了那个字面串。

| 文件 | 注释里的串 | 后果 | 处理 |
|---|---|---|---|
| `Package.swift` | `dependencies: []` | `grep -c` 得 2（判据要 1） | 改写注释 |
| `AppDelegate.swift` | `NSApp.terminate(nil)` | `grep -c` 得 2（判据要 1） | 改写注释 |
| `PlayerController.swift` | `disableLooping()` / `removeAllItems()` | `head -1` 取到注释行 33 而非代码行，行号比较测的不是真代码序 | 改写注释 |

**保留真值**：代码行一个字都没改，判据测的仍然是真实的代码顺序与真实的调用点。

### 5. [Rule 1 - Test bug] `SettingsStoreTests` 的临时文件夹具本身有 bug

- **RED 阶段暴露**：`testFileExistsUsesPathAndSeesTempFile` 红了。
- **真因**不是产品行为：`FileManager.default.temporaryDirectory` 自带尾斜杠，
  `resolvedFolderURL().path`（URL 规范化后无尾斜杠）与 `tmp.path` 比不相等；
  且 `createFile` 前没有建父目录。
- **处理**：改测试夹具（显式 `URL(fileURLWithPath:isDirectory:)` + 先建目录），产品代码不动。
  这是测试的错，不是实现的错 —— 修正判据，不是修正产物。

### 6. [Rule 3 - Environment] `swift test` 在 T2 结束时仍报 `no tests found`

- T2 的行为描述已写明「本任务尚无测试，测试由 T3/T4 提供」，且 T2 的验收清单里**没有**
  `swift test` 这一条。命令本身可用（能编译、能发现 test target、只是没有测试）。
- T3 落地后 `Executed 14 tests, with 0 failures` 满足 plan 级验收的第 2 条。
- **不是**跳过：整体验收要求 N ≥ 14，实际 14。

---

## 与计划的已知偏离（环境类，非改动类）

- **在 `master` 上提交。** 仓库无 remote、单分支，Phase 1 的全部 plan 提交也都在 `master`。
  编排器明确要求在本工作树正常提交，故沿用既有做法。

---

## Verification（整体验收逐条）

| # | 判据 | 实测 |
|---|---|---|
| 1 | `swift build` 退出 0 | `BUILD_RC=0` |
| 2 | `swift test` 退出 0，`Executed N tests, with 0 failures`，N ≥ 14 | `Executed 14 tests, with 0 failures` |
| 3 | `gate-rerun.log` 首行是 `GATE_RERUN=…`，文件内无 `GATE=01` | 首行 `GATE_RERUN=blocked`；`grep -cE '^GATE=01$'` = 0 |
| 4 | md5 三行齐全且 `GATE01_MD5_MATCH_AT_BACKUP=1` | 三行齐，末行 `=1` |
| 5 | `du -sk fixtures` < 8192，符号链接 = 3 | 4272 KB，3 个符号链接 |
| 6 | `disableLooping` 行号 < `removeAllItems` 行号；`item.rate`/`item.volume` = 0 | 42 < 43；计数 0 |

---

## 给下游的硬约束

1. **Phase 3 加 `HoldReason` 的 case 时只加 `case` 与 `order` 分支。** 幂集测试自动从 2 个子集扩到 32 个。
2. **Phase 3 必须实测锁屏跃迁**（PDCA-A7）：Phase 1 只验证了「能读出状态」，跃迁时是否翻转未验证。
3. **Phase 3 的全屏检测禁用 0.95 覆盖率阈值**（PDCA-A2）：Phase 1 已实测 `FALSE_POSITIVE_OBSERVED=1`，
   coverage 顶在 1.000 上限，调阈值改不了。
4. **Phase 3/4 不得改 `HoldArbiter` 的签名**，只新增 `HoldReason` 的 case。
5. **Phase 4 加 `PlayMode` 的 case 时不动 `SettingsStore` 的签名。**
6. **`scripts/dev-seed.sh` 写的键名 == `SettingsStore.Key` 的字面量**，改一处就断链。
7. **解锁后补跑 `bash .planning/spike/run-gate.sh`**，把 `GATE_RERUN=blocked` 升级为 `pass` 或 `fail`。
   脚本无需修改，Phase 1 的门禁复跑只需 ~1 分钟。这是本 plan 唯一挂着的未闭合项。

---

## Self-Check: PASSED

- 14 个创建文件 + 1 个修改文件全部存在于磁盘
- 4 个任务提交全部存在于 `46bf4a4..dd5adc4`（`git rev-list --count` = 4）
- `swift build` / `swift test` 绿
- `STATE.md` 与 `ROADMAP.md` **未被修改**（编排器拥有这两处写入）
- `.planning/state.json` 的改动保持未暂存，未被本 plan 的任何提交带入
