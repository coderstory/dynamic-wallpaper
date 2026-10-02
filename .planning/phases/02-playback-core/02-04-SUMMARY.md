---
phase: 02-playback-core
plan: 04
subsystem: packaging
type: execute
wave: 4
status: complete
tags: [build, dmg, lsuielement, codesign, displaylink, verdict, test-harness]
requirements: [MENUBAR-01, MENUBAR-07]
depends_on: [02-03]
provides:
  - "build.sh: swift build → .app + DMG 一条命令（create-dmg 调用 0 次 / 注释保留 1 处）"
  - "Sources/PicApp/Resources/Info.plist —— bundle 声明的唯一真相源，LSUIElement=<true/>，零 UsageDescription"
  - "Sources/PicCore/Playback/FrameDriver.swift —— 显示刷新驱动的纯测量器（不参与渲染）"
  - "scripts/run-probe.sh 的 app / refresh 两个子命令"
  - ".planning/phases/02-playback-core/02-VERDICT.md —— Phase 2 的唯一判定文件"
requires:
  - "02-03 的 AppDelegate 装配点与 NSApp.terminate 单一落点"
affects: [Phase 3, Phase 5, Phase 7]
tech-stack:
  added: []
  patterns:
    - "Info.plist 单一真相源 + build.sh 只 cp（不做第二份手写副本）"
    - "判据数源码前先剥注释；被禁 API 的名字不写进注释，否则门禁自伤"
    - "test.sh 内部固定 LC_ALL=C，保证自身输出可被 grep"
key-files:
  created:
    - Sources/PicApp/Resources/Info.plist
    - Sources/PicCore/Playback/FrameDriver.swift
    - .planning/phases/02-playback-core/02-VERDICT.md
    - .planning/phases/02-playback-core/evidence/app-bundle.log
    - .planning/phases/02-playback-core/evidence/refresh.log
  modified:
    - build.sh
    - Package.swift
    - scripts/run-probe.sh
    - test.sh
    - Sources/PicApp/AppDelegate.swift
    - .planning/WINDOWS.md
    - ".planning/phases/02-playback-core/evidence/{order,inset,loop,quit}.log（用最终二进制重跑）"
decisions:
  - "Info.plist 用 cp 而非在 build.sh 里内联 heredoc（两份手写必然漂移，AC 的 diff 退出 0 就是防这个）"
  - "Package.swift 用 exclude 而非 resources:（resources 会让同名 plist 出现在两处，更难排查）"
  - "FrameDriver 测满 10 秒窗口即 invalidate —— 30Hz 兜底定时器长期跑在产品里没有收益"
  - "FrameDriver 不接任何渲染路径（剥注释后该文件内 AVPlayerLayer 计数 = 0）"
  - "test.sh 内部 export LC_ALL=C，固定字节处理而不改任何判据语义"
metrics:
  duration: "~35 分钟（含 300 秒 loop 复跑与两次 build.sh 的可复现性测量）"
  completed: 2026-10-03
  tasks: 3
  files_changed: 13
commits: 3
plan_head_before: "c127f9a~3 (= 047e1cf 的后继，Phase 2 Wave 3 末尾)"
plan_head_after: c127f9af7b68e79710a4c4f254ddd381d3dea462
actuals:
  tokens: 22425
  tasks: 3
  commits: 3
---

# Phase 2 Plan 4: 打包收口与阶段判定 — Summary

把产品从「`swift run` 能跑」变成「`.app` 能跑」，并把 Phase 2 的诚实基线逐条落盘。

**实测结论一句话：`.app` 产出正常（`LSUIElement=true`、ad-hoc、层级序 `ok`、Finder 重启后存活、
激活策略 = 1），但显示刷新回调在 `.app` 下**仍然**拿不到 —— 两个运行模式都是
`timer_fallback_hz30`、`TICK_RATE=27.2`，因此 `REFRESH_VERDICT=blocked`。**

## 交付了什么

| 产物 | 说明 |
|---|---|
| `build.sh` | 从 `swift build -c release` 出发，一条命令产出 `build/Pic.app` 与 `dist/Pic-0.1.0.dmg`。不再手编 spike 源（D-01），不用 `xcodebuild` |
| `Sources/PicApp/Resources/Info.plist` | bundle 声明的唯一真相源。`build.sh` 只 `cp` 一行，`diff` 两份退出 0 |
| `Package.swift` | `PicApp` target 加 `exclude: ["Resources/Info.plist"]`，消掉 SwiftPM 的 unhandled resource 告警 |
| `Sources/PicCore/Playback/FrameDriver.swift` | 显示刷新驱动的**纯测量器**：不碰渲染路径，测满 10 秒窗口自行 `invalidate()` |
| `scripts/run-probe.sh` | 新增 `app`（打包产物层级复验）与 `refresh`（两种运行模式的刷新驱动）两个子命令 |
| `test.sh` | 新增「打包产物」5 项；干净 clone 下走 skip 分支 |
| `02-VERDICT.md` | **Phase 2 的唯一判定文件** —— 四栏 + 5 条 SC 逐条判定 + 承接 WINDOWS.md 十条窗口 |

## 关键数字（全部来自真跑过的命令）

- `bash build.sh` → 退出 0；`.app` 二进制 403696 bytes，DMG 141K
- `plutil -extract LSUIElement raw` → `true`（不是 `1`）；`UsageDescription` 计数 = 0
- `diff build/Pic.app/Contents/Info.plist Sources/PicApp/Resources/Info.plist` → 退出 0
- `codesign -dv` → `Signature=adhoc`、`Identifier=com.local.pic`、`Authority=Developer ID` 计数 = 0
- `create-dmg` 两侧判据：剥注释后 **0** 次调用，剥注释前 **1** 处注释保留
- `evidence/app-bundle.log`：`ORDER=ok`、`ORDER_AFTER=ok`、`ALIVE_AFTER_FINDER_RESTART=1`、
  `APP_ACTIVATION_POLICY=1`、`SELF_LEVEL=-2147483623`、`ICON_LEVEL=-2147483603`
- `evidence/refresh.log`：两种模式 `DRIVER=timer_fallback_hz30`、`TICK_RATE=27.2`（272 tick / 10.0s）
- `bash test.sh` → **通过 32  失败 0  跳过 0**；干净环境（无 `build/`）→ **通过 27  失败 0  跳过 5**，退出码仍 0
- `swift test` → `Executed 24 tests, with 0 failures`
- `grep -rn 'NSApp.terminate' Sources/` → **1**（改完 build.sh 与新增 FrameDriver 后重验）
- `bash build.sh` 重复四次 → DMG md5 **四次全不同**（`9b4c7e31…`/`1e685a43…`/`166e336a…`/`e391cb5f…`）

## SC 判定（详见 `02-VERDICT.md`）

SC1 `PASS-with-gap` · SC2 `PARTIAL` · SC3 `PASS-with-gap` · SC4 `PASS` · SC5 `PARTIAL`。

自动部分过了但人工部分没过的，一律不写 `PASS`（Phase 1 SC4 就是这么翻车的）。

## Deviations from Plan

### 1. `PACKAGE.swift` 的 `exclude` 实测生效，无需退路

计划预留了「若 `exclude` 在本机 Swift 6.4 上不生效，退路是登记成已知非致命告警」。
实测**生效**：用 `/tmp` 下一个 scratch 包做 A/B —— 不加 `exclude` 时报
`warning: found 1 file(s) which are unhandled`，加上后无告警。本机是
`Apple Swift version 6.4 (swiftlang-6.4.0.34.1)`。

### 2. `PIC_POLICY=` 这个 key 在产品里不存在，用的是 `ACTIVATION_POLICY_RAW=`

计划写「从进程内打的一行 `PIC_POLICY=<rawValue>` 取」，产品实际 emit 的是
`ACTIVATION_POLICY_RAW=`（02-02 已定）。**未改产品代码** —— 改 key 只会让既有证据失效。
探针按真实 key 取值，在日志里以 `APP_POLICY_SOURCE_KEY=` 显式记下这处命名差异。

### 3. `DMG_REPRODUCIBLE=0`，且比计划多排除了一层

计划只要求「如实记 `DMG_REPRODUCIBLE=0` 并写明原因」。实测多做了两步定位：
先把两个 DMG 分别挂载，证明**内容逐字节相同**（二进制 md5 `662e6321…`、Info.plist md5 `f85a5701…`），
差异只在 UDIF 容器层；再把源树 mtime 全部 pin 成同一时刻重跑 `hdiutil`，
**仍**产出不同 md5（`9e20b8a9…` vs `936dab1c…`），故 mtime 不是唯一变量。
未定位到容器内具体哪几个字节在变 —— 这一点也如实写进日志与 WINDOWS.md。

### 4. 证据全部用最终二进制重跑

`order` / `inset` / `loop`（300 秒）/ `quit` / `app` 五个探针都在 `FrameDriver` 合入后重跑了一遍，
避免 VERDICT 里出现「证据来自旧二进制」。`loop` 重跑结果与 02-02 一致：
`LOOP_VERDICT=pass`、`LOOP_SAMPLES=150`、`LOOP_CYCLES=37`、`LOOP_ENDED=37`、`LOOP_FAILED=0`。

### 5. `FrameDriver` 的注释不能写出被禁 API 的字面量

T2 的验收判据是**全文** `grep -c 'preferredFramesPerSecond\|CADisplayLink(target:' == 0`（不剥注释）。
第一版我把这两个名字写进了文件头的说明注释，判据当场变红。**改注释不放宽判据**：
注释改用文字描述被禁的 API，并写明「别把它"修复"回字面量」。

### 6. 修了一处 02-03 遗留的输出缺陷（`test.sh`）

`test.sh` 在 UTF-8 locale 下运行会**按字节偏移丢掉 2 字节**，且丢点与脚本内容无关
（同一份脚本在 `LC_ALL=C` 下输出逐字节有效）。最小复现：33 行中文填充 + 一行含
`…行数 $MF）` 的 `ok`，UTF-8 locale 下 `1）`（`31 EF BC 89`）变成 `\xbc\x89`。
后果很实际：输出里只要有一个非法字节，`grep` 就会中止整份文件 ——
本 plan 的「干净环境输出含 `跳过`」判据因此无法通过。
**处置**：`test.sh` 内 `export LC_ALL=C`，只固定脚本自身的字节处理，**不改变任何判据的语义**。
修后默认 UTF-8 环境跑 `bash test.sh` → `通过 32  失败 0  跳过 0`，输出逐字节有效。

### 7. 计划自带的 heredoc/`cp` 表述冲突，以 `cp` 为准

计划 action 自己在「heredoc 保留」与「改成 `cp`」之间自相矛盾（并在括号里指明了以 `cp` 为唯一答案）。
照 `cp` 执行：heredoc 整段删除。

## 自造的问题与处置（未走 checkpoint）

- `build.sh` 改造时用 slice 替换 heredoc 块，遗留了一行裸 `PLIST`（heredoc 终止符）。
  `bash -n` 立即抓到，已删。
- `refresh` 子命令第一版的 `REFRESH_SESSION` 判定写成了残缺的算式，改为先算变量再写进日志。
- `app_bundle` 那轮第一次跑出 `DRIVER=none`：`.app` 里还是 T1 打的旧二进制
  （`FrameDriver` 是 T2 才加的）。重建后复测，两轮读到同一驱动。

## 交给下一阶段

1. **Phase 3 之前**：解锁会话重跑 `bash .planning/spike/run-gate.sh`（约 1 分钟，脚本无需修改）；
   授屏幕录制权限（或真人观察 5 分钟）解开 SC2 的黑帧缺口；真人切一次 Space 解开 SC5。
2. **Phase 3 内**：`REFRESH_VERDICT=blocked` → 逐帧轮询这条路作废，四类检测必须走事件通知；
   PDCA-A2 的 0.95 阈值仍未解（`FALSE_POSITIVE_OBSERVED=1`，coverage 顶在 1.000）；
   PDCA-A7 锁屏跃迁仍未验证；复核 W-2026-10-03-10 的 `player.play()` 直连。
3. **Phase 5 内**：引入 `.xcodeproj`，解开 W-2026-10-03-07（真人点菜单退出）
   与 W-2026-10-03-08（删除 `--quit-after` 脚手架）。
4. **Phase 7 内**：若验收需要「重复执行结果一致」，判据落在 **`.app` 内容的 md5** 上，
   不要落在 DMG 容器的 md5 上。

完整判定读 `.planning/phases/02-playback-core/02-VERDICT.md`，不回翻本文件。

## Self-Check: PASSED

- 三个 task 的产物文件全部存在并已提交（`git status` 干净）
- `build.sh` / `test.sh` / `Package.swift` / `run-probe.sh` / `AppDelegate.swift` / `FrameDriver.swift` /
  `Info.plist` / `02-VERDICT.md` / 两份新 evidence 全部 `FOUND`
- 三个 commit 全部存在于 `git log`
- `build/` `dist/` 仍在 `.gitignore`（`git check-ignore` 命中），**无构建产物入库**
- `NSApp.terminate` 在 `Sources/` 内仍恰好 1 处
- 无残留进程（`pgrep` 空）；`killall Finder` 由 launchd 拉起（`ALIVE_AFTER_FINDER_RESTART=1`）
- STATE.md / ROADMAP.md **未被修改**（本 plan 不碰，交给编排器）
