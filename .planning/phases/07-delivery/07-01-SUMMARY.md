---
phase: 07-delivery
plan: 01
subsystem: infra
tags: [swiftpm, conditional-compilation, codesign, adhoc, create-dmg, hdiutil, iconutil, nsimage-template, nm-symbol-count]

requires:
  - phase: 02-playback-core
    provides: LoopProbe / FrameDriver 测量类与 run-probe.sh 的 refresh/app 取证轮
  - phase: 04-rotation
    provides: AppDelegate 里 tick()/TICK emit 的现有结构（本次条件编译的改造面）
  - phase: 05-settings
    provides: PicOpenSettings 通知桥（MenuBarLabel 常驻壳）—— 决定了菜单栏图标不能换掉 label 闭包
provides:
  - `bash build.sh` 一条命令产出双产物 + DMG（交付 Pic.app 剥离探针 / PicProbe.app 保留探针 / dist/Pic-0.1.0.dmg）
  - 交付二进制三类探针符号计数 0，成对正控（debug 291 / PicProbe 195）
  - create-dmg 主路 + 显式 `DMG_FALLBACK=hdiutil` 降级（绝不静默换）
  - 图标全套：iconutil 出的 Pic.icns 进 Resources、CFBundleIconFile=Pic、菜单栏 menubar-v1 Template 三档
  - run-probe.sh 两处改道：APP_BIN→PicProbe.app（refresh 轮）、DELIVERY_BIN 钉死交付 app（app 轮）
affects: [07-02, 07-03, 07-04, "SYS-01 自启实测", "7 天长跑"]

actuals:
  tokens: 1600
  tasks: 3
  commits: 4

tech-stack:
  added: []
  patterns:
    - "成对判据：nm | grep -cE == 0 必须配同命令的 ≥ 1 正控（裸 grep 的 '|' 是字面量，恒 0 假绿灯）"
    - "双产物构建：交付带 -DPIC_NO_PROBE、探针不带；组装逻辑抽 assemble_app 一份实现"
    - "DMG 内容物只从 dist/stage 来，绝不指 build/（中间产物会混进去）"
    - "降级必须显式打一行标记再走，绝不静默换"

key-files:
  created:
    - .planning/phases/07-delivery/evidence/probe-strip.log
  modified:
    - build.sh
    - scripts/run-probe.sh
    - Sources/PicApp/AppDelegate.swift
    - Sources/PicApp/PicApp.swift
    - Sources/PicApp/Resources/Info.plist
    - Sources/PicCore/Playback/LoopProbe.swift
    - Sources/PicCore/Playback/WindowProbe.swift
    - Sources/PicCore/Playback/FrameDriver.swift

key-decisions:
  - "剥离用 `#if !PIC_NO_PROBE` 条件编译而非 strip：探针被 AppDelegate 活代码引用，纯 strip 无解（RESEARCH 2.2）。不传 define 是默认态，debug/swift test 零回归。"
  - "判据只锁三类符号（LoopProbe/WindowProbe/FrameDriver），可 grep 可证伪；`--quit-after`、`PIC_HOLD_OBSERVER_TICKS` 等其余 emit 不盖 —— 它们没有符号名可锁，盖了反而会打红 Phase 3/4 的按行判据。"
  - "cmd_app 钉死交付 app（方案 b）而非点名接受改道：app-bundle.log 判据名说的是「交付 app」，读数来自 PicProbe 就是标称与事实不符（假绿灯的跨文件形态）。"
  - "两套图标同源只断言到「同一生成器文件 + 同一手绘语言 + v1 构图一致」，**不写「同一绘制函数」** —— drawAppIcon 与 drawMenuBar 是两个函数，drawAppIcon 的 menuBar:true 分支是死代码。"

requirements-completed: [PACK-01, PACK-03, ASSET-01, ASSET-02, ASSET-03]

coverage:
  - id: D1
    description: "交付二进制 build/Pic.app 里三类测量探针符号为 0，且同命令在 debug 构建上 ≥ 1（成对正控，防 grep 模式空集的假绿灯）"
    requirement: PACK-03
    verification:
      - kind: integration
        ref: "nm build/Pic.app/Contents/MacOS/Pic | grep -cE 'LoopProbe|WindowProbe|FrameDriver' → 0"
        status: pass
      - kind: integration
        ref: "nm .build/debug/Pic | grep -cE '...' → 291（正控）"
        status: pass
      - kind: integration
        ref: "nm build/PicProbe.app/Contents/MacOS/Pic | grep -cE '...' → 195"
        status: pass
      - kind: integration
        ref: "swift test --package-path . → Executed 163 tests, 0 failures"
        status: pass
    human_judgment: false
  - id: D2
    description: "PicProbe.app 第二产物：探针能力完整迁移，交付物与探针物的符号计数成对打点"
    requirement: PACK-03
    verification:
      - kind: integration
        ref: "bash build.sh → PROBE_SYMBOLS_PIC=0 / PROBE_SYMBOLS_PROBE=195"
        status: pass
      - kind: integration
        ref: "交付二进制探针输出行数 0 vs PicProbe 17 行（emitprobe 实测）"
        status: pass
    human_judgment: false
  - id: D3
    description: "dist/Pic-0.1.0.dmg 产出、校验通过、且内容物只有带图标的 Pic.app（PicProbe 永不进 DMG）"
    requirement: PACK-01
    verification:
      - kind: integration
        ref: "hdiutil verify dist/Pic-0.1.0.dmg → rc=0 VALID"
        status: pass
      - kind: integration
        ref: "挂载复查 → DMG_APPS=1 PIC_APP=1 PROBE_APP=0（PicProbe.app 已存在于 build/ 的时刻复验）"
        status: pass
    human_judgment: false
  - id: D4
    description: "图标集成：iconset 10 文件 → iconutil → Pic.icns 进 Resources + CFBundleIconFile=Pic + 菜单栏 menubar-v1 Template 三档（ASSET-01/02）"
    requirement: ASSET-01
    verification:
      - kind: integration
        ref: "find build/Pic.iconset -name 'icon_*.png' → 10；Pic.icns = 1,651,170 字节"
        status: pass
      - kind: integration
        ref: "plutil -extract CFBundleIconFile raw 两侧均输出 Pic（build 产物与真相源一致）"
        status: pass
      - kind: integration
        ref: "Bundle.image(forResource: 'menubar-v1Template') → ICON_LOADED=true TEMPLATE=true REPS=3 SIZE=16×16pt"
        status: pass
    human_judgment: false
  - id: D5
    description: "ASSET-03 两套图标「一眼同源」的视觉判据"
    requirement: ASSET-03
    verification: []
    human_judgment: true
    rationale: "同源性是肉眼判断，源码结构与像素计数都证不了 —— drawAppIcon 与 drawMenuBar 是两个函数（drawAppIcon 的 menuBar:true 分支是死代码），可断言的只有「同一生成器文件 + 同一手绘语言 + v1 构图一致」。按计划 07-01 不设自动门，真判据在 07-03 T3 的 UAT-SOAK 并排比对记录；07-04 T3 的 VERDICT 在该记录存在前不得给 SC 写 PASS。"
  - id: D6
    description: "create-dmg 主路的 Finder 美化布局（窗口位置、图标位置、Applications 拖入快捷方式）"
    verification: []
    human_judgment: true
    rationale: "本机从未授权 create-dmg 的 AppleScript 步骤（未获得授权将Apple事件发送给Finder (-1743)），主路**一次都没跑完过**，美化布局完全未验证。当前所有 DMG 都是 hdiutil 降级产物 —— 降级路径已实测，但「用 create-dmg 生成 DMG」这一半尚未在本机成立。解除需要人给终端一次性授予「自动化 → Finder」权限后重跑。"
    status_note: "未验证，不是已通过"

duration: 25min
completed: 2026-10-03
status: complete
---

# Phase 07 Plan 01: 双产物剥离 + DMG + 图标集成 Summary

**`bash build.sh` 一条命令：交付 Pic.app（剥离三类探针，nm 计数 0）与 PicProbe.app（保留探针，计数 195）双产物 + 经 hdiutil verify 的 DMG，且 run-probe 的 refresh/app 两轮证据链各自钉在正确的二进制上**

## Performance

- **Duration:** 25 min
- **Started:** 2026-10-03T15:09:59Z
- **Completed:** 2026-10-03T15:35:10Z
- **Tasks:** 3
- **Files modified:** 9

## Accomplishments

- **探针剥离贯穿源码到产物**：三个测量类的声明区 + AppDelegate 七处引用全部包进 `#if !PIC_NO_PROBE`；交付二进制 nm `grep -cE` 计数 **0**，同命令在 debug 上 **291**、PicProbe 上 **195**（成对正控，证明 grep 模式非空集）。不传 define 的一切照旧 —— `swift test` 163 个用例 0 失败。
- **双产物 + 显式降级的 DMG**：`assemble_app` 抽成一份实现供两条线调用；create-dmg 主路失败时**先打一行** `DMG_FALLBACK=hdiutil reason=create_dmg_failed_automation_permission` 再降级，DMG 照常产出。staging 是 DMG 唯一内容物来源。
- **run-probe 证据链两处改道**：`APP_BIN`→PicProbe.app 供 refresh 轮；新增 `DELIVERY_BIN` 钉死交付 app 供 app 轮。实测交付二进制探针输出 **0 行**、PicProbe **17 行** —— 若 cmd_app 跟 APP_BIN 改道，那轮就会带上 REFRESH_ 行。
- **图标全套**：iconutil 出的 Pic.icns（1,651,170 字节）进 Resources、`CFBundleIconFile=Pic` 两侧一致、菜单栏 menubar-v1 Template 三档加载为 `isTemplate=true REPS=3 16×16pt`。工具链零新依赖，`tools/` 零改动。

## Task Commits

1. **Task 1: 探针条件编译剥离 + create-dmg 主路交付构建** — `4f8e5d1`
2. **Task 2: PicProbe.app 第二产物 + run-probe 证据链迁移** — `90d9953`
3. **Task 3: 图标集成（icns / CFBundleIconFile / 菜单栏 Template 图）** — `e4c5edf`

**Plan metadata:** 本 SUMMARY 提交

## Files Created/Modified

- `Sources/PicCore/Playback/{LoopProbe,WindowProbe,FrameDriver}.swift` — 声明区包进 `#if !PIC_NO_PROBE`，文件头注释留在 guard 外
- `Sources/PicApp/AppDelegate.swift` — 七处引用（两个存储属性、launch 里的两次调用、两个 start 方法、tick() 的 TICK emit）
- `build.sh` — define + staging + create-dmg/降级 + `assemble_app` + 图标组装 + 双产物 + PROBE_SYMBOLS 两行
- `scripts/run-probe.sh` — `APP_BIN`→PicProbe；新增 `DELIVERY_BIN`，cmd_app 三处文本引用钉死交付 app
- `Sources/PicApp/Resources/Info.plist` — 只加一个键 `CFBundleIconFile=Pic`
- `Sources/PicApp/PicApp.swift` — `Image(systemName:)` → `Image("menubar-v1Template")`
- `.planning/phases/07-delivery/evidence/probe-strip.log` — Phase 7 自己的剥离证据（未碰 Phase 2/3 的目录）

## Decisions Made

1. **条件编译而非 strip** —— 探针被 AppDelegate 活代码引用，strip 无解；不传 define 是默认态，debug/`swift test`/探针产物零回归。
2. **判据只锁三类符号** —— 其余 emit（`--quit-after`、`PIC_HOLD_OBSERVER_TICKS`、`PIC_ROT_*` 等）没有符号名可锁，且 Phase 3/4 的既有判据按行读它们，盖了反而打红。判据窄，靠「类没了接线也没了」的编译结构兜其余部分。
3. **`cmd_app` 钉死交付 app（方案 b）** —— `app-bundle.log` 判据名说的是「交付 app」，读数却来自 PicProbe 就是标称与事实不符。代价是「只改一行」的口径要按方案重述，已在偏离记录里交代。
4. **ASSET-03 如实分层** —— 只断言「同一生成器文件 + 同一手绘语言 + v1 构图一致」；**明确不写「同一绘制函数」**，那是假事实（两个函数，且 `drawAppIcon` 的 `menuBar: true` 分支是死代码）。

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 — 计划引用漂移] 菜单栏图标的改造点与计划写的不一样**
- **Found during:** Task 3
- **Issue:** 计划写 `Sources/PicApp/PicApp.swift:27` 是 `MenuBarExtra("Pic", systemImage: "photo.on.rectangle")`。真实代码不是这样：`MenuBarExtra` 用的是 `label:` 闭包，闭包里是 Phase 5 的 `MenuBarLabel` 常驻壳，SF Symbol 在壳的 `body` 里（`Image(systemName: "photo.on.rectangle")`）。若照计划改成 `MenuBarExtra("Pic", image:)`，会把承载 `PicOpenSettings` 通知桥的 label 壳整个删掉 —— Phase 5 的回归。
- **Fix:** 只把壳里的 `Image(systemName:)` 换成 `Image("menubar-v1Template")`，不动 `MenuBarExtra` 的结构。连带地，计划的验收 grep 形态 `image: "menubar-v1Template"` 与真实形态 `Image("menubar-v1Template")` 不符，判据按真实形态取。
- **Files modified:** `Sources/PicApp/PicApp.swift`
- **Verification:** 剥注释后 `Image("menubar-v1Template")` 计数 1、`photo.on.rectangle` 计数 0；`swift test` 163 用例 0 失败；`Bundle.image(forResource:)` 读出 `TEMPLATE=true REPS=3`
- **Committed in:** `e4c5edf`

**2. [Rule 1 — 临时文件泄漏] create-dmg 的残留临时文件会混进产物摘要**
- **Found during:** Task 1
- **Issue:** 计划要求「保留现有的 `rm -f "$DIST"/rw.*.dmg`」。原位在 create-dmg **之前**，只能清上一轮的残留；本轮 create-dmg 失败后自己留的那个 `dist/rw.*.dmg` 依然在，于是摘要里打出两个「dmg」（373K 真件 + 25M 假件）。
- **Fix:** 把这一行移到 create-dmg/降级块**之后**（一行移位，不新增逻辑），语义仍是「清 create-dmg 失败留下的临时文件」。
- **Files modified:** `build.sh`
- **Verification:** 重跑 build.sh，摘要只列 `373K dist/Pic-0.1.0.dmg` 一行
- **Committed in:** `4f8e5d1`

**3. [Rule 1 — 逻辑不自洽] 只钉死 cmd_app 的执行行会留下错误的存在性守卫**
- **Found during:** Task 2
- **Issue:** 计划只点名 `cmd_app` 里那处 `PIC_SOURCE_FOLDER=... "$APP_BIN" ... &`。但 `cmd_app` 里还有一处 `if [ ! -x "$APP_BIN" ]` 存在性守卫和它的 log 行。只改执行行的话，守卫校验的是 PicProbe、执行的却是交付 app。
- **Fix:** `cmd_app` 内三处文本引用（守卫、log、执行）全部指向新增的 `DELIVERY_BIN`；交付路径**字面量**只出现一次（`DELIVERY_BIN=` 赋值行），满足计划的 `DELIVERY_PATH_REFS == 1` 计数门。
- **Files modified:** `scripts/run-probe.sh`
- **Verification:** 剥注释后 `PicProbe` 引用 1 处、`^APP_BIN=.*build/Pic\.app` 计数 0、交付路径字面量计数 1；实测两二进制探针输出行数 0 vs 17
- **Committed in:** `90d9953`

**4. [Rule 1 — shell 解析] 全角括号紧邻变量名在 `set -u` 下炸**
- **Found during:** Task 3
- **Issue:** `echo "==> 出 .icns（iconutil，图标真相源 = $ASSETS）"` 报 `ASSETS?: unbound variable` —— 变量名紧邻多字节全角字符时被吞进名字里。
- **Fix:** 该行改成字面路径（`.planning/design/assets/`），不内联插值。
- **Files modified:** `build.sh`
- **Verification:** `bash build.sh` 退出 0
- **Committed in:** `e4c5edf`

**5. [Rule 3 — 判据路径] 计划的 `<automated>` 全部以 `cd /Users/coderstory/dev/pic` 开头**
- **Found during:** 三个任务的验证
- **Issue:** 那是**主 checkout**，不是本 worktree。照写执行会去验证错误的 checkout（绿得毫无意义）。
- **Fix:** 全部重锚到本 worktree 根（`/Users/coderstory/dev/pic/.claude/worktrees/agent-ac619da36e247812b`）。
- **Verification:** 产物、evidence、nm 计数全部落在 worktree 内；`git status` 只出现 plan 声明的文件
- **Committed in:** n/a（验证侧，未改仓库文件）

**6. [Rule 1 — 判据形态] 计划里 `hdiutil attach … | tail -1 | cut -f3` 取挂载点取不到**
- **Found during:** Task 1 / Task 2 的 DMG 复查
- **Issue:** 现代 `hdiutil attach` 会在挂载行之后多打分区表行，`tail -1` 取到的是分区类型；且挂载点路径可能含空格（`/Volumes/Pic 1`），`cut -f3` 会截断。
- **Fix:** 改从 attach 输出里取带 `/Volumes/` 前缀的整行并保留空格。
- **Verification:** 每次复查都稳定取到 `MNT=/Volumes/Pic`，并正常 detach
- **Committed in:** n/a（验证侧）

---

**Total deviations:** 6 auto-fixed（5 build/code 侧，1 判据重锚 + 1 判据形态修正）
**Impact on plan:** 全部是「照字面执行会出错」类的前置修正，无功能范围扩张。三处改了计划写死的形态（cmd_app 钉死范围、菜单栏改造点、临时文件清理时机），均已在上面逐条给出理由；产物形态与计划的目标一致。

## Issues Encountered

**create-dmg 主路在本机从未跑通 —— DMG 全部是降级产物**

三次 build.sh 都在同一点失败：
```
execution error: 未获得授权将Apple事件发送给Finder。 (-1743)
Failed running AppleScript
```
create-dmg 的 Finder 美化步骤需要终端对 Finder 的「自动化」权限。这是 RESEARCH 3.1 早就记录在案的已知失败模式（`build.sh:34-35` 原注释）。

**这意味着什么，说清楚：**
- ✅ 已成立：DMG 产出、`hdiutil verify` VALID、挂载复查内容物只有带图标的 Pic.app。
- ❌ **未成立**：ROADMAP SC1「用 create-dmg 生成 DMG」这一半在本机一次都没跑完过 —— 窗口布局、图标位置、Applications 拖入快捷方式**全部未验证**。`coverage` 里 D6 单列了这一条并标 `human_judgment: true`，不冒充已通过。
- 解除方式：给人（不是 agent）一次性授予终端「自动化 → Finder」权限，之后 `bash build.sh` 零手工重复。这是一次性人工动作，不在本 plan 的自动化范围内。

**`fixtures/` 不在本 worktree —— 影响 `run-probe.sh app` 的一组读数**

`fixtures/` 在 `.gitignore` 里（ffmpeg 生成的测试语料），新 worktree 没有它；生成它要跑 `scripts/make-fixtures.sh` → ffmpeg，而用户红线是「ffmpeg 测试只能手动跑」。于是 `app` 轮跑出来的是：

| 读数 | Phase 2 基线 | 本次 |
|---|---|---|
| `ORDER` | ok | fail |
| `SELF_LEVEL` | -2147483623 | none |
| `FOREIGN_SAME_LEVEL` | 1 | 0 |

这是**环境缺媒体**的如实结果（无 mp4 → 不装载 → 不建壁纸窗口），不是产品回归，也不是本次改动引入的。

**Phase 2 的两份 evidence 被覆盖了 —— 按计划声明处理，未提交**

计划已预告：`run-probe.sh refresh` 里的 `> "$EV/refresh.log"` 与 `cmd_app` 写的 `$EV/app-bundle.log` 都是**截断重写**，$EV 指向 Phase 2 的 evidence 目录。两份都确实被本 plan 的读数覆盖了。

处置：**已 `git checkout --` 还原到 HEAD，没有提交**。理由有两条 —— ① Phase 2 evidence 不在本 plan 的 `files_modified` 里（越界）；② 本次读数受 `fixtures/` 缺失影响而退化，把 `ORDER=fail` 提交进 Phase 2 的证据会让那份证据比原来更差、且把环境问题记成产品结论。

因此本 plan 交付的证据只有 Phase 7 自己的 `.planning/phases/07-delivery/evidence/probe-strip.log`。

**刷新轮结论未变**：refresh 的 app_bundle 轮打出 `DRIVER=timer_fallback_hz30`（非 `none`），证据链没断 —— 注意这是读 PicProbe.app 读出来的，符合迁移预期。

## User Setup Required

无 `USER-SETUP.md`。但有一件**非阻塞**的一次性人工动作，见上面 Issues：`create-dmg` 主路要人给终端授予「自动化 → Finder」权限。不授予也出 DMG（降级路径已实测），只是 SC1 的「用 create-dmg」那一半不成立。

## Next Phase Readiness

**可以开始的：**
- SYS-01 开机自启实测（07-02）：形态已锁死 —— ad-hoc、`Signature=adhoc` + `TeamIdentifier=not set`、spctl `rejected` rc=3 全部实测确认。
- 7 天长跑（07-03/07-04）：交付 .app 的真实形态已定，长跑可以在确定的二进制上跑。

**要盯的：**
- **07-03 T3 的 UAT-SOAK 必须加一条「app 图标与菜单栏图标并排肉眼比对」并记录** —— ASSET-03 的真判据在这里，07-01 没有也不该有自动门。
- **07-04 T3 的 VERDICT 在那条 UAT-SOAK 记录存在之前，不得给 ASSET-03 写 PASS。**
- **07-04 的统一收口 `bash test.sh` 本 plan 没跑** —— 它的四段 probe 会重写 Phase 3 已入库的 evidence（波次纪律同 04-04）。到 07-04 再跑。
- create-dmg 主路若在 07-04 之前仍未获授权，PACK-03 的 SC1 描述需要如实改成「降级路径产出 DMG，主路待授权」。

---
*Phase: 07-delivery*
*Completed: 2026-10-03*