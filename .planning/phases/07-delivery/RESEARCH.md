# Phase 7: 打包、开机自启与整机验收 - 前置技术调研

**Researched:** 2026-10-03
**Domain:** macOS 打包分发 / SMAppService 开机自启 / 测量脚手架剥离 / 长跑验收设计
**Confidence:** MEDIUM（打包与判据设计 HIGH；SMAppService 未签名行为本质上只能 Phase 7 实测定案）

> 本文件是**并行前置研究**：Phase 5/6 仍在规划中，本文只覆盖 Phase 7 自己的悬项，不阻塞等待。
> 证据分级：`[VERIFIED: 本机实测]` = 本次会话在本机跑过；`[VERIFIED: 仓库文件:行]` = 本次会话 Read 过源文件；
> `[CITED: url]` = 官方文档/论坛原文核对过；`[ASSUMED]` = 训练知识或仅搜索结果标题，未核对。

## Project Constraints (from CLAUDE.md / PROJECT.md)

- 联网弱：WebSearch 本次 1 次成功、1 次 403；WebFetch 对 developer.apple.com 普通页面拿不到正文（JS 渲染），**JSON API 端点可用**。查不到的一律写「未找到公开资料」
- 不签名、不公证，但要 DMG；create-dmg 1.3.0 已装（`/opt/homebrew/bin/create-dmg`）
- 最小代码量方针：优先系统现成命令（`xcodebuild`/`swiftc`/`create-dmg`/`iconutil`/`hdiutil`），不自己写逻辑
- 本 Phase 边界：不改 `test.sh` 的 ffmpeg 禁令；任何预期 CPU > 100% 的命令执行前先问用户
- 主屏、非 App Store、可用非公开 API —— 边界已封板（ROADMAP Notes）

## Summary

六个问题里，**四个已可定案、一个部分定案、一个必须留给实测**。打包链路（Q3/Q6）本机已有完整证据：现有 `build.sh` 产出的 ad-hoc app 上 `codesign -dv` 显示 `Signature=adhoc`、`TeamIdentifier=not set`，`spctl --assess --type execute` 拒绝（rc=3），本地构建的 DMG **不带 quarantine xattr**（自用安装不触发 Gatekeeper）。图标资产（Q4）**已生成完毕**——`tools/make-icons.swift` + `.planning/design/assets/` 里全套 10 尺寸 appiconset + 菜单栏模板图都在，Phase 7 只剩「集成进 bundle」这一步。探针剥离（Q2）的判据命令已实测可用：当前交付二进制里探针符号计数 **195**，剥离后目标为 0；但 `run-probe.sh` 的 app_bundle/refresh 轮依赖交付 .app 里的 `FrameDriver`，全剥会断证据链——解法是「双产物」：交付 .app 剥离、验证用 .app 保留探针。

SYS-01（Q1）是唯一真正悬的：**官方文档没有写 `register()` 是否要求签名身份**，唯一相关的一手资料（Apple DTS 工程师 Quinn）说的是 ad-hoc 签名导致「macOS 无法追踪代码身份，会引发各种奇怪问题」——这是风险提示不是结论。搜索摘要曾声称「ad-hoc 登录项会在启动时崩（CODESIGNING 4）」，但我逐字核对了那个论坛帖：那是**已签名** helper + BTM 状态腐坏，修复是 `sfltool resetbtm`，**不能作为 ad-hoc 失败的证据**。Phase 7 必须按「先 A 后 B」实测，本机已验证 `sfltool dumpbtm` 无需 sudo 可跑、`~/Library/LaunchAgents/` 在 macOS 27 上仍有第三方 plist 存活——两条路的判据命令都已备好。

**Primary recommendation:** 打包链路沿用现有 build.sh 骨架 + create-dmg（带 hdiutil 降级）；探针剥离走「方案 A 条件编译 + 双产物」；SYS-01 写一个一次性实测脚本先测路线 A（判据 = `SMAppService.status` + `sfltool dumpbtm`），失败即落路线 B plist；长跑验收用 launchd 挂每小时采样器。

---

## 问题 1：SYS-01 开机自启（最大悬项）

### 1.1 官方文档说了什么（核对过的）

`SMAppService` 官方文档（JSON API 抓取，普通页面 JS 渲染抓不到）：

> "Registers the service so it can begin launching subject to user approval."（`register()`）
> "In macOS 13 and later, use `SMAppService` to register and control `LoginItems`, `LaunchAgents`, and `LaunchDaemons` as helper executables for your app."

[CITED: developer.apple.com/documentation/servicemanagement/smappservice（经 tutorials/data JSON 端点核对）]

**关键空白：整页没有提到任何代码签名 / Developer ID 要求。** 未找到公开资料明确判定 ad-hoc 签名 app 上 `register()` 的行为——这正是 STATE.md 悬项的原始判断，维持「Phase 7 必须实测」。

### 1.2 一手风险资料（逐字核对）

Apple DTS 工程师 Quinn（论坛帖 739988，本次抓取核对）：

> "When your code is unsigned, or ad hoc signed, macOS is unable to track the code's identity, which can cause all sorts of weird problems. I discuss this in some detail in TN3127 [Inside Code Signing: Requirements]."

[CITED: developer.apple.com/forums/thread/739988]

**重要勘误（本次调研的核心修正）：** 搜索摘要曾给出「ad-hoc app 注册的登录项会在登录时崩，`Termination Reason: CODESIGNING 4 Launch Constraint Violation`」。我抓取了该结论的来源帖（forums/799933）逐字核对：**崩溃的是一个用 Xcode 26 正常签名的 helper**（`codesign -d -vvvv` 显示签名身份匹配），崩在 macOS 13/14 而 15/26 正常，最终修复是 `sfltool resetbtm` + 重启（BTM 状态腐坏）。该帖**不能**证明 ad-hoc 登录项会崩。结论：ad-hoc + SMAppService 的真实行为没有可靠公开资料，`[ASSUMED]` 都算不上，就是「未实测」。

### 1.3 本机已验证的判据基础设施

| 命令 | 本次实测结果 | 用途 |
|---|---|---|
| `sfltool dumpbtm` | rc=0，**无需 sudo**，正常输出 BTM 记录；当前 `grep -c com.local.pic` = 0 | 路线 A 的系统侧证据：register 成功后该计数应 ≥1 |
| `launchctl list` | rc=0，正常输出 PID/Status/Label 表 | 路线 B 的加载态查询 |
| `ls ~/Library/LaunchAgents/` | 有 3 个第三方 plist（EdgeUpdater / raylink / Lemon）在 macOS 27 上存活 | 证明路线 B 在本 OS 仍是真实可用的第三方做法 |
| `man launchd.plist` | 正常读出键定义 | plist 键的权威来源 |

[VERIFIED: 本机实测，2026-10-03]

`launchd.plist` man page 关键键（逐字）：

> "Label \<string\> — This required key uniquely identifies the job to launchd."
> "ProgramArguments \<array of strings\>" / "RunAtLoad \<boolean\>" / "KeepAlive \<boolean or dictionary of stuff\>" / "Disabled \<boolean\>"

[VERIFIED: man launchd.plist 本机读取]

API 形状（Phase 前已在本机 SDK 编译验证，记录于 PROJECT.md:81）：

> "`SMAppService.register()` 是 throwing；`SMAppService.Status` 无 `.disabled`（是 `notRegistered`/`enabled`/`requiresApproval`/`notFound`）"

[VERIFIED: .planning/PROJECT.md:81（SDK 编译验证记录，本次 Read）]

### 1.4 推荐实测设计（路线 A → 失败落 B）

**路线 A（SMAppService.mainApp）：**
1. app 内 Toggle → `SMAppService.mainApp.register()`（try-catch，错误原样落日志）
2. 判据（自动部分）：
   - `sfltool dumpbtm | grep -c com.local.pic` ≥ 1（BTM 侧登记）[命令本机已验证可跑]
   - app 启动时打一行 `SMAPP_STATUS=<status>`（`enabled` / `requiresApproval` 都算「注册成功但可能需手动批准」；`requiresApproval` 分支按 ROADMAP SC3 要求给引导 → `openSystemSettingsLoginItems()` [CITED: 同官方文档页]）
   - 错误形态：register() 抛错时记录 error domain/code；搜索结果里出现过 `serviceApplicationLaunchFailedError`（CocoaError code）[ASSUMED —— 仅见于搜索结果链接标题，未逐字核对页面]
3. 判据（必须人工）：注销/重启一次，确认真的自启。**这是 UAT 项，不是 test.sh 项**（REQUIREMENTS 已把「开机自启」列入人工验收）。

**路线 B（~/Library/LaunchAgents plist）：**
- plist 设计（最小集）：`Label=com.local.pic`、`ProgramArguments=[<app绝对路径>/Contents/MacOS/Pic]`、`RunAtLoad=true`。**不要** `KeepAlive`（壁纸 app 崩了不该被无限拉起，且与「退出」菜单项冲突）。
- 开 = 写 plist + `launchctl bootstrap gui/$(id -u) <plist>`；关 = `launchctl bootout gui/$(id -u)/com.local.pic` + 删 plist。**禁用** 已废弃的 `launchctl load/unload` [ASSUMED —— deprecation 是训练知识；bootstrap/bootout 是现代写法]。
- 判据：`launchctl print gui/$(id -u)/com.local.pic` 退出 0；`plutil -lint` 通过；macOS 13+ 系统「登录项与扩展」的「允许在后台」列表会出现该 agent [ASSUMED —— BTM 收编 legacy plist 是公开行为，未本次核对]。

**共同坑（写进 plan 的 verification）：**
- **app 移动即失效**：plist 存绝对路径，.app 挪位置 → 路径失效。缓解：app 启动时若检测到已启用但 `Bundle.main` 路径 ≠ plist 里的路径，重写 plist（路线 B）；路线 A 的 BTM 同样按路径追踪，移动后需重新 register [ASSUMED]。
- **开发期签名漂移**：ad-hoc 签名每次 build 都变，BTM「identity 追踪」会失效（Quinn 引文的风险面）。**验收必须在最终 DMG 装出的 .app 上做**，开发期反复 build 的观察只作参考，不作判据。
- Phase 7 的 SYS-01 实测脚本应设计成「A 失败自动落 B 并记录 A 失败形态」，符合自主推进方针（卡住就跳、记 Deferred）。

## 问题 2：探针剥离落地方案

### 2.1 现状（本机实测）

- 当前交付二进制 `build/Pic.app/Contents/MacOS/Pic` 上：`nm <bin> | grep -cE 'LoopProbe|WindowProbe|FrameDriver'` = **195**（符号以 mangled 名含类名出现，局部符号 `t` 也可见）→ **判据命令形态已被证实可用** [VERIFIED: 本机实测]
- 探针被**活代码引用**：`AppDelegate.swift:31,39` 持有 `loopProbe`/`frameDriver` 属性，`applicationDidFinishLaunching` 调 `startFrameDriver()`/`startLoopProbeIfRequested()` [VERIFIED: Sources/PicApp/AppDelegate.swift:31-50（本次 Read grep 定位）] → 纯 `strip` 无解，必须条件编译（与已知审计结论一致）
- `FrameDriver.swift` 文档注释明确：「本类不参与渲染」「`AppDelegate` 启动它只是为了回答一个问题：打包成 .app 后能不能拿到显示刷新回调」[VERIFIED: Sources/PicCore/Playback/FrameDriver.swift:1-30（本次 Read）] → 剥离不影响产品行为

### 2.2 方案 A 落地要点 + 证据链修复

方案 A（已知审计结论）：`#if !PIC_NO_PROBE` 包住探针类型 + AppDelegate 接线；`build.sh` 交付构建加 `swift build -c release -Xswiftc -DPIC_NO_PROBE`。

**判据修正（重要）：** 任务书里的 `nm ... | grep -c 'LoopProbe|FrameDriver' == 0` 写法有坑——**裸 `grep` 不带 `-E` 时 `|` 是字面量，永远计数 0，假绿灯**（本项目「禁裸 grep -c」纪律的第 N 次适用）。必须写成：

```bash
nm "$APP/Contents/MacOS/Pic" | grep -cE 'LoopProbe|WindowProbe|FrameDriver'   # 目标 0
```

**证据链断裂点与修复：** `run-probe.sh` 的 `refresh` 子命令的 app_bundle 轮（`cmd_refresh` → `refresh_one app_bundle "$APP_BIN"`）直接跑交付 `build/Pic.app`，读它 emit 的 `REFRESH_DRIVER=` 行 [VERIFIED: scripts/run-probe.sh:408-454（本次 Read）]。全剥后这轮拿不到 `REFRESH_DRIVER`，display_link 证据链断。**推荐：双产物**：

- `build.sh`（交付）：`-DPIC_NO_PROBE` 构建 → `build/Pic.app`（剥离）→ DMG。判据 nm 计数 0 挂在这里。
- 探针产物：`swift build -c release`（不带 define，或 debug）→ 组装 `build/PicProbe.app`（**不进 DMG**），供 `run-probe.sh` 的 `app`/`refresh` 轮采证。`run-probe.sh` 只改一处：`APP_BIN` 指向 PicProbe.app。
- 开发期 debug 构建（`run-probe.sh` 现用的 `.build/debug/Pic`）不受影响——`#if !PIC_NO_PROBE` 在不传 define 时默认保留探针，现有 order/inset/loop/quit/holds 子命令零改动。

代价评估：build.sh 多一次编译 + 一个约 10 行的组装块（复用同一套 mkdir/cp/codesign），符合最小代码方针的「为正确性花的钱」。

**剥离范围注意：** `--quit-after`、`PIC_TERMINATED`、`PIC_HOLD_OBSERVER_TICKS` 等 emit/参数同属脚手架，但它们不像三个类那样有符号名可 grep。判据只锁三类符号（可 grep、可 falsify）；其余靠 `#if` 与接线同处一个编译开关来保证（探针类没了， AppDelegate 接线也没了，emit 自然没了）。

## 问题 3：DMG 打包（create-dmg vs hdiutil）

### 3.1 本机事实

- create-dmg 1.3.0 已装且 `--help` 正常输出 [VERIFIED: 本机实测]。能力面（`--help` 逐项）：`--volname`、`--volicon`、`--background <png>`、`--window-pos/--window-size`、`--icon <file> <x> <y>`、`--icon-size`、`--app-drop-link <x> <y>`、`--hide-extension`、`--no-internet-enable`、`--format UDZO|UDBZ|...`、`--eula` [VERIFIED: 本机 `create-dmg --help`]。即：背景图 / 图标布局 / 拖入 Applications 快捷方式全支持。
- 现有 build.sh:34-35 注释记录了已知失败模式：「create-dmg 的 Finder 美化步骤需要『自动化』权限，会失败并留临时文件」[VERIFIED: build.sh:34-35（本次 Read）]。
- ROADMAP SC1 已**锁定**「用 create-dmg 生成 DMG」——不是取舍题，是落地题。

### 3.2 推荐落地

```bash
# 骨架（非完整脚本，plan 里细化）
create-dmg --volname "Pic" --app-drop-link 480 180 \
  --icon "Pic.app" 180 180 --hide-extension "Pic.app" \
  --no-internet-enable \
  "dist/Pic-0.1.0.dmg" "build/" ||  hdiutil 降级路径（沿用现有命令）
```

- **「零手工步骤」的解法**：给跑 build.sh 的终端（或 CI 用户）**一次性授予**「自动化 → Finder」权限；此后重复执行零手工。降级路径（hdiutil）保证未授权环境也能出 DMG——SC1 的「重复执行结果一致」不断。
- 降级判定要诚实：create-dmg 失败时打一行 `DMG_FALLBACK=hdiutil reason=automation_permission`，不用静默换。

### 3.3 Gatekeeper（自用场景）

- 本地构建的 `dist/Pic-0.1.0.dmg` **没有** `com.apple.quarantine` xattr（只有 FinderInfo/recentcksum/provenance）[VERIFIED: 本机 xattr 实测] → **本机自装 DMG 完全不触发 Gatekeeper**，右键/Open 那套根本用不上。
- quarantine 只在「经浏览器下载 / AirDrop 传输」等场景被附加；届时首次打开会遇到「无法验证开发者」类提示，解法（用户已熟悉的顺序）：右键 → 打开，或系统设置 → 隐私与安全性 → 仍要打开，或 `xattr -dr com.apple.quarantine /Applications/Pic.app` [CITED: 多份中文技术资料交叉（php.cn 系列），一致性高但非 Apple 原文 → 实际按 MEDIUM 处理；自用场景基本不会走到这步]。
- 结论：**自用可接受**，无需为此改变不签名决策。

### 3.4 「重复执行结果一致」的判据口径

已有实测记录（run-probe.sh:391-396 固化进 app-bundle.log 的笔记）：多次 build 的 **DMG md5 互不相同**，但 **DMG 内 Pic.app 逐字节相同**（二进制/Info.plist md5 稳定），差异在 UDIF 容器层；mtime 全部 pin 住仍不同，hdiutil 无可复现开关 [VERIFIED: scripts/run-probe.sh:391-396（本次 Read）]。→ SC1 的「结果一致」判据应落在：**.app 内二进制 md5 一致 + DMG 内文件清单一致**，而不是 DMG md5。写 plan 时把这条钉死，避免验收时误判。

## 问题 4：ASSET-01~03（图标资源）

### 4.1 重大发现：资产已经做完了

- `tools/make-icons.swift`（约 200 行 Swift + CoreGraphics）**已经实现**：app 图标（暖白渐变底 + 橙色前窗 + 播放三角 + 基线）与菜单栏模板图（纯黑 + alpha，v1 单窗 / v2 双窗两版） [VERIFIED: tools/make-icons.swift（本次 Read）]
- `.planning/design/assets/` 里**全套产物已在**：`icon_16x16` 到 `icon_512x512@2x` 共 10 个 PNG + 合规的 `Contents.json`（idiom=mac，1x/2x 齐全，与 REQUIREMENTS ASSET-01 的尺寸清单逐项吻合）+ `menubar-v1/v2` 各 1x/2x/3x [VERIFIED: 本机 ls + Contents.json Read]

→ **Phase 7 的 ASSET 工作量只剩「集成进 .app」**，不含设计/生成。ASSET-03（同源性）由 make-icons.swift 同一函数 `drawAppIcon(menuBar:)` 出两版天然满足 [VERIFIED: 源码结构]。

### 4.2 集成路径（关键决策点）

SwiftPM 的 `swift build` **不会**把 `.xcassets` 编译成 Assets.car（那是 Xcode/actool 的活）[ASSUMED —— 广为人知但未本次证伪；方案选择刻意绕开它]。两条路：

| 路线 | 做法 | 依赖 | 评价 |
|---|---|---|---|
| **(a) .icns（推荐）** | `iconutil -c icns Pic.iconset -o Pic.icns` → 放 `Contents/Resources/` → Info.plist 加 `CFBundleIconFile=Pic`；菜单栏 PNG 也放 Resources，`NSImage(contentsOfFile:)` + `isTemplate = true` | 仅 iconutil（本机已验证用法：`iconutil --convert icns [--output file] file` [VERIFIED: 本机 iconutil 无参输出]） | 纯 SwiftPM 路线，与现有 build.sh 的 cp 组装模式完全同构，改动最小 |
| (b) Assets.xcassets + actool | actool 编译 Assets.car + Info.plist 写 ASSETCATALOG 键 | actool（本机有 [VERIFIED]）；且 Package.swift 注释说「Phase 5 才引入 .xcodeproj」[VERIFIED: Package.swift:3（本次 Read）] | 若 Phase 5 真建了 xcodeproj，此路变顺手；但依赖 Phase 5 的产出，与「并行前置、不等 5/6」方针相抵 |

**推荐 (a)**：不依赖 Phase 5 是否建 xcodeproj，命令链全在本机验证过。menu bar template 的 `isTemplate = true` 让系统自动适配深浅色 [ASSUMED —— AppKit 标准行为]。注意菜单栏图标实际显示高度约 16-18pt，PNG 内容要按 menubar-v1/v2 的构图用 `NSImage(size:)` 指定 points 而非像素。

## 问题 5：7 天长跑验收设计

### 5.1 本机可用的采样工具（全部实测可用）

`pgrep` / `lsof` / `pmset` / `log` / `memory_pressure` / `leaks` / `screencapture` / `sips` 全部 OK [VERIFIED: 本机 command -v]。屏幕录制权限已授予（screencapture YAVG 242 = 真实画面）[VERIFIED: STATE.md:176-203]。`powermetrics` 仍需 sudo、不可无人值守 [VERIFIED: STATE.md:167]。

### 5.2 推荐架构：launchd 挂每小时采样器

用一个独立 LaunchAgent（如 `com.local.pic.soak.plist`，`RunAtLoad` + `KeepAlive` + 内部 1 小时 sleep 循环）跑采样脚本——KeepAlive 让采样器自身崩溃也能被拉起，比 cron/nohup 稳。plist 键集问题 1.3 已验证。产出落 `.planning/phases/07-delivery/evidence/soak/dayN.log`。

每次采样记录（一行 CSV + 摘要）：

| 指标 | 命令 | 判据用途 |
|---|---|---|
| RSS/VSZ | `ps -o rss,vsz -p $(pgrep -x Pic)` | 7 天无单调上涨（对 7 天序列做线性拟合，斜率显著 > 0 即 FAIL；比「回到基线±10%」更适合长跑） |
| 文件句柄数 | `lsof -p $(pgrep -x Pic) \| wc -l` | fd 泄漏（稳定小波动 = PASS） |
| 崩溃/退出记录 | `ls ~/Library/Logs/DiagnosticReports/ \| grep -c '^Pic-'` | 7 天 = 0 |
| 睡眠/唤醒计数 | `pmset -g log \| grep -cE 'Entering Sleep\|Wake from'` | 证明期间真的经历了睡眠唤醒（SC5 的「电池供电让路」配合 `pmset -g batt`） |
| 壁纸活性 | `screencapture -x` 两次 + md5 比较 + YAVG | 复用 Phase 1/2 已验证的黑帧/活性判据模式（内容在变 = 在播；纯黑 = 有问题） |
| 内存压力 | `memory_pressure` 尾行 | 环境前提记录 |

**注意：** `leaks` 对别的进程可能要权限，设计成「尽力采样、失败记 blocked」，不硬断言 [ASSUMED]。20 轮休眠/唤醒/锁屏（SC4）里「主动休眠」可用 `pmset sleepnow`，但「唤醒/解锁」需要真人或电源事件——这部分是 UAT 人工项，采样器只负责记录跃迁确实发生（`pmset -g log`）。50 次换片压测（SC4 前半）是短脚本（设短轮换时间跑 N 分钟），归 test.sh 可自动化部分。

### 5.3 证据价值原则

长跑日志的价值 = **每次采样自带时间戳 + 采样器自身的存活证明**（日志连续无缺口）。plan 里加一条自检：dayN.log 的条目数 ≥ 期望小时数 × 0.95，缺口大 = 采样器本身不可信，长跑结论作废。

## 问题 6：PACK-01~04（产物校验 / ad-hoc 形态 / 卸载残留）

### 6.1 ad-hoc 签名的显示形态（本机实测，直接可抄进判据）

```
$ codesign -dv --verbose=2 build/Pic.app
Identifier=com.local.pic
CodeDirectory v=20400 size=998 flags=0x2(adhoc) hashes=25+3 location=embedded
Signature=adhoc
TeamIdentifier=not set
```
`$ spctl --assess --type execute --verbose build/Pic.app` → `build/Pic.app: rejected`，**rc=3**。[VERIFIED: 本机实测，2026-10-03]

→ 判据设计：`codesign -dv` 必须含 `Signature=adhoc` + `TeamIdentifier=not set`（证明「确实没签」而非「签坏了」）；`spctl` **预期就是 rejected + rc=3**，把它写成正向断言（预期拒绝），不要当失败。

### 6.2 DMG 产物校验（PACK-01/03）

- `hdiutil verify dist/Pic-0.1.0.dmg` → `checksum ... is VALID` [VERIFIED: 本机实测]
- 挂载校验：`hdiutil attach -nobrowse -readonly` → 对挂载点里 `Pic.app/Contents/MacOS/Pic` 取 md5，与 build 产物一致 → 卸载 `hdiutil detach`。体积：`du -sh` + 与上一版对比（无异常膨胀）。
- 全链重复执行：见 3.4 —— 判据锚在 .app 二进制 md5 + 清单，不在 DMG md5。

### 6.3 卸载残留清单（实测已存在一处）

| 残留 | 现状 | 清理 |
|---|---|---|
| UserDefaults `com.local.pic` | **已存在**（`defaults domains` 里可见）[VERIFIED: 本机实测] | `defaults delete com.local.pic` |
| `~/Library/Preferences/com.local.pic.plist` | 同上的落盘形态 | rm（或交给 defaults delete） |
| 路线 B 的 LaunchAgent plist | Phase 7 落地后会有 | rm + `launchctl bootout` |
| BTM 记录 | 路线 A 启用后会有；`sfltool dumpbtm \| grep -c com.local.pic` 可查 [VERIFIED 命令可跑] | unregister()；顽固残留 `sfltool resetbtm`（会清掉**所有**登录项，慎用，只作最后手段 [CITED: forums/799933]） |
| `Converted/` 转码产物目录 | 用户数据 | **不清**（在壁纸目录内，属用户文件） |
| Application Support / Caches | Phase 5/6 若引入才有 | Phase 7 验收时以 Phase 5/6 实际落点为准（本调研不预设） |

卸载验收 = 上述各项「存在性检查 + 清除后复查为 0」，全部命令已验证可跑。

## Don't Hand-Roll

| 问题 | 不要自造 | 用现成的 | 为什么 |
|---|---|---|---|
| DMG 美化 | 自写 AppleScript 布局 | `create-dmg --app-drop-link/--icon/--background` | 已装 1.3.0，能力面 `--help` 全验证 |
| .icns 生成 | 自写 PNG→icns 拼包 | `iconutil -c icns` | 系统命令，本机验证 |
| 图标绘制 | —— | `tools/make-icons.swift`（已存在） | 资产已生成，勿重做 |
| 长跑调度 | 自写 daemon/while+nohup | LaunchAgent（RunAtLoad+KeepAlive） | launchd 自带崩溃拉起；plist 键有 man page 背书 |
| 内存/fd 采样 | 自写内存读取 API | `ps`/`lsof`/`memory_pressure` | 全部本机可用 |
| 登录项注册（若 A 可用） | 自写 plist | `SMAppService.mainApp` | 系统 API，且 SC3 锁定「需手动设一次」的 requiresApproval 分支天然由它表达 |

## Common Pitfalls

1. **裸 `grep -c 'A|B'`** —— `|` 在无 `-E` 时是字面量，恒 0，假绿灯。探针判据必须 `grep -cE`。（累计自伤 12 次的家族第 13 次，这次在判据设计阶段就掐掉）
2. **DMG md5 当可复现判据** —— 已实测不可复现（容器层差异），判据锚 .app 内容。
3. **create-dmg 静默降级** —— 失败要显式打 `DMG_FALLBACK=` 行，否则「用了 create-dmg」这条 SC 无法审计。
4. **开发期 ad-hoc 签名漂移做 SYS-01 结论** —— 每次 build 签名都变，BTM 追踪失效是 Quinn 明示的风险面；结论只能出自最终 DMG 装出的 .app。
5. **剥离后 run-probe.sh 静默断链** —— `cmd_refresh`/`cmd_app` 直接读交付 .app 的 emit；不给探针产物就全断。
6. **`launchctl load/unload`** —— 已废弃；用 bootstrap/bootout。
7. **KeepAlive 挂壁纸 app 本体** —— 会和「退出」菜单打架；KeepAlive 只给采样器用。
8. **`sfltool resetbtm` 当常规清理** —— 它清全部登录项，是核弹；仅 unregister 失效时最后手段。

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | XCTest（swift test）+ test.sh 行式判据（现 50 项）[VERIFIED: STATE.md:117] |
| Config file | Package.swift（testTarget PicCoreTests） |
| Quick run command | `bash test.sh`（现状，Phase 7 会扩展） |
| Full suite command | `swift test && bash test.sh` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| PACK-03 | build.sh 一条命令 + 可重复 | smoke | `bash build.sh && bash build.sh`（二次执行比对 .app 二进制 md5） | ❌ Wave 0（build.sh 已有，比对判据待加） |
| 探针剥离 | 交付二进制零探针符号 | smoke | `nm build/Pic.app/Contents/MacOS/Pic \| grep -cE 'LoopProbe\|WindowProbe\|FrameDriver'`（断言 =0） | ❌ Wave 0 |
| PACK-01 | DMG 挂载校验 | smoke | `hdiutil verify` + attach/md5/detach | ❌ Wave 0 |
| PACK-04 | test.sh 全绿退出码 | smoke | `bash test.sh; echo $?` | ✅ 已有（扩展项另计） |
| SYS-01-A | SMAppService 注册判据 | integration（一次性实测脚本） | `sfltool dumpbtm \| grep -c com.local.pic` | ❌ Wave 0 |
| SYS-01-B | LaunchAgent plist 判据 | integration | `launchctl print gui/$UID/com.local.pic` + `plutil -lint` | ❌ Wave 0 |
| ASSET-01~03 | 图标进 bundle | smoke | `ls` Resources + `CFBundleIconFile` 断言 | ❌ Wave 0 |
| SC4 压测 | 50 换片内存回基线 | integration | 短脚本（Phase 4 既有压测模式延伸） | ❌ Wave 0 |
| SC5 长跑 | 7 天 | manual+采样器 | launchd 采样（见问题 5） | ❌ Wave 0（含人工 UAT：真实重启自启、休眠唤醒轮次） |

### Wave 0 Gaps
- [ ] `scripts/`（或 phase 目录）需新增：sys01-probe 脚本、soak-sampler 脚本、DMG 校验段、压测脚本
- [ ] build.sh 需改造（create-dmg + 双产物 + -DPIC_NO_PROBE）——**注意 build.sh 当前在禁改清单里（本次只读），改造落在 Phase 7 执行期**

## Security Domain

`security_enforcement` = true（config），ASVS L1。本 Phase 面很小：

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2/V3/V4 认证/会话/访问控制 | no | 无用户体系、无网络 |
| V5 输入校验 | 部分 | 路线 B plist 内容全部由代码常量生成（Label/路径），无用户输入拼入；soak 采样器读的是固定路径 |
| V6 密码学 | no | 无 |

| Threat | STRIDE | Mitigation |
|--------|--------|-----------|
| LaunchAgent plist 被第三方预置（ planting） | Tampering/EoP | 写入前检查已存在内容并覆盖记录；plist 路径固定无用户输入 |
| DMG 传输后 quarantine 误导用户 | Social eng | 文档明示自用场景不受影响；外部传输时右键打开流程 |

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | ad-hoc app 上 `SMAppService.mainApp.register()` 的真实行为（成功/拒绝形态）——无公开资料，**Phase 7 实测定案** | Q1 | 低：双路线设计已兜底，实测脚本就是为此写的 |
| A2 | SwiftPM `swift build` 不编译 .xcassets | Q4 | 低：推荐路线 (a) iconutil 完全绕开 |
| A3 | `isTemplate = true` 的深浅色自适应行为 | Q4 | 低：菜单栏图标不符合可即时换资源 |
| A4 | `serviceApplicationLaunchFailedError` 是 register() 的错误形态之一 | Q1 | 低：实测脚本记录实际 error，不预设 |
| A5 | `launchctl load/unload` 已废弃、bootstrap/bootout 为现代写法 | Q1 | 低：两者当前都能用，只是规范问题 |
| A6 | BTM 会在「登录项与扩展」里收编展示 legacy LaunchAgent | Q1 | 低：不影响功能本体，只影响可见性 |
| A7 | `leaks` 对外部进程可能需要权限 | Q5 | 低：设计为尽力采样 |
| A8 | 右键→打开 在 macOS 27 上的具体文案形态 | Q3 | 低：自用本地 DMG 无 quarantine，几乎不触发 |
| A9 | `-Xswiftc -DPIC_NO_PROBE` 对多 target 的传播细节 | Q2 | 中：若只传到部分 target，剥离不彻底 → nm 判据恰好能抓住（计数 >0 即红），有兜底 |

## Open Questions

1. **SYS-01 路线 A 是否成立** — 本调研无法闭合（无公开资料，一手资料仅风险提示）。处置：Phase 7 第一个任务就是实测脚本，A/B 自动切换，结论落 evidence。
2. **Phase 5 是否真的引入 .xcodeproj** — Package.swift:3 注释如此计划。若引入，ASSET 集成可改走 actool 路线；不影响本调研推荐（iconutil 路线两者皆可用）。
3. **create-dmg 的自动化权限授予是否算「零手工步骤」** — 语义问题：一次性授权 vs 每次构建。建议 SC1 判据写「授权后重复执行零手工」，降级路径保底。

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| create-dmg | PACK-01 | ✓ | 1.3.0 (`/opt/homebrew/bin/create-dmg`) | hdiutil（build.sh 现有命令） |
| hdiutil | PACK-01/03 | ✓ | 系统自带 | — |
| codesign / spctl | 签名形态判据 | ✓ | 系统自带 | — |
| nm | 探针剥离判据 | ✓ | 系统自带 | — |
| iconutil / actool / sips | ASSET | ✓ | 系统自带（actool 需 Xcode 27，已装 [VERIFIED: PROJECT.md:72]） | — |
| sfltool / launchctl | SYS-01 | ✓ | 系统自带（dumpbtm 无需 sudo，实测） | — |
| ps / lsof / pmset / log / memory_pressure / screencapture | 长跑采样 | ✓ | 系统自带 | — |
| powermetrics | 功耗采样 | ✗（需 sudo，不可无人值守）[VERIFIED: STATE.md:167] | — | 用 pmset -g batt + 日志侧写代替 |
| 真人（重启/解锁/唤醒轮次） | SC4/SC5 部分 | ✗ | — | 采样器记录跃迁 + UAT 清单 |

**Missing dependencies with no fallback:** 无阻塞项 —— powermetrics 与真人项均为已知降级/人工项，不阻塞 plan。

## Sources

### Primary (HIGH)
- 本机实测（codesign/spctl/xattr/hdiutil/nm/sfltool/launchctl/iconutil/create-dmg --help/defaults/ls）——全部 2026-10-03 本次会话执行
- 本机 `man launchd.plist` 键定义
- 仓库文件 Read：build.sh、scripts/run-probe.sh、tools/make-icons.swift、Package.swift、Sources/PicCore/Playback/FrameDriver.swift、.planning/design/assets/Contents.json、STATE.md、PROJECT.md、ROADMAP.md、REQUIREMENTS.md

### Secondary (MEDIUM)
- [SMAppService 官方文档](https://developer.apple.com/documentation/servicemanagement/smappservice)（JSON API 抓取核对：register() 语义 / LoginItems+LaunchAgents+LaunchDaemons / openSystemSettingsLoginItems）
- [Apple Developer Forums 739988](https://developer.apple.com/forums/thread/739988) — Quinn 关于 unsigned/ad-hoc 身份追踪的逐字引文
- [Apple Developer Forums 799933](https://developer.apple.com/forums/thread/799933) — CODESIGNING 4 帖的**勘误性核对**（签名 helper + sfltool resetbtm，非 ad-hoc 证据）

### Tertiary (LOW)
- 中文 Gatekeeper 绕过资料（php.cn 系列，交叉一致但非 Apple 原文）
- 其余见 Assumptions Log

## Metadata

**Confidence breakdown:**
- 打包/判据设计（Q2/Q3/Q6）: HIGH — 关键命令全部本机实测
- 图标资产（Q4）: HIGH — 资产已存在且本次 Read 核对
- 长跑设计（Q5）: MEDIUM — 工具可用性实测，方案本身未经 7 天检验（本就是 Phase 7 要跑的）
- SYS-01（Q1）: LOW→待实测 — 无公开资料可依赖，双路线 + 判据命令已备好

**Research date:** 2026-10-03
**Valid until:** 2026-11-02（稳定域；SYS-01 部分随时可被 Phase 7 实测覆盖）
