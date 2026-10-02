---
phase: 01-spike
plan: 05
subsystem: spike
tags: [verdict, gate, cgwindowlevel, nsstatusitem, avplayerlayer, screensaver, spike, throwaway, macos-27]

requires:
  - phase: 01-spike/01-01
    provides: "gate-01.log（ORDER / FINDER_RESTART_ALIVE / SELF_LEVEL / ICON_LEVEL / D-08 三项）"
  - phase: 01-spike/01-02
    provides: "menubar.log（MENUBAR_VERDICT=ok、policy=1、layer0=0、阳性对照 layer0=1）"
  - phase: 01-spike/01-03
    provides: "fullscreen-scenarios.log（SELFTEST_VERDICT=pass、FALSE_POSITIVE_OBSERVED=1、五场景 coverage）"
  - phase: 01-spike/01-04
    provides: "ab-verdict.txt（AB_STATUS=skipped / SCREENLOCK=unknown / OPAQUE_DELTA=SKIPPED）"
provides:
  - 01-VERDICT.md —— Phase 1 唯一判定文件，首行 GATE=A，5 条 SC 逐条结论 + 已知障碍表 + 四栏口径
  - test.sh 「── spike 门禁探针 ──」段 —— 编译期 probe ×2，PASS 计数 12 → 15
  - 「层级写法定案」段 —— Phase 2 照抄的层级 / 激活策略 / 刷新驱动三条写法
  - VERDICT 引用链入库 —— 7 份证据日志强制入库，clone 后引用不悬空
  - FALSE_POSITIVE_OBSERVED=1 写成 Phase 3 的显式设计约束
affects: [phase-2-产品代码骨架, phase-3-全屏检测, phase-3-锁屏仲裁, phase-4, phase-7-验收脚本]

actuals:
  tokens: 4659
  tasks: 2
  commits: 4

# commits is MEASURED: git rev-list --count 49fbfe5..HEAD at the moment this
# SUMMARY was written (0db6644, 9a4dea1, d507c8b, 84b1dd2). The docs commit
# carrying this SUMMARY is the 5th and is excluded, because a summary cannot
# contain the hash of the commit that contains it — resolve it by the subject
# "docs(01-05): ...".
commits: 4
plan_head_before: 49fbfe5932ba0ba53c5e9c5e99744a7726ef4047

tech-stack:
  added: []
  patterns:
    - "门禁判据写成两个字段的直接布尔表达式（ORDER=ok ∧ FINDER_RESTART_ALIVE=1），不可自由裁量，且与任何 BLOCKED 的 SC 解耦"
    - "SC 未采集时证据格只写「未采集 + 原因」，兜底产物的引用下沉到表格外的 SC5-注 脚注；证据格一旦写了路径就必须 test -f 且入库"
    - "自检判据分三层：文件存在 → 判据字面量比对 → 引用路径可解析（磁盘 + git 索引），第三层能抓出前两层都过的悬空引用"
    - "evidence-first：文档里每一个数字都从原始日志抄，不从 SUMMARY 转述"

key-files:
  created:
    - .planning/phases/01-spike/01-VERDICT.md
  modified:
    - test.sh
  gitignored-force-added:
    - .planning/spike/out/gate-01.log
    - .planning/spike/out/menubar.log
    - .planning/spike/out/task1-selftest.log
    - .planning/spike/out/ab-verdict.txt
    - .planning/spike/out/lock.log
    - .planning/spike/out/cgsession-keys.txt
    - .planning/spike/out/task3-selftest.log
    - .planning/spike/out/session-lockvalue.log

key-decisions:
  - "GATE=A —— 判据只看 gate-01.log 的 ORDER=ok 与 FINDER_RESTART_ALIVE=1，两字段皆真；路线 A 成立，Phase 2 起产品代码"
  - "SC5 判 BLOCKED 而非 PASS/FAIL：screenIsLocked 无跃迁可观察（SCREENLOCK=unknown）+ 四组 A/B 一组未量（OPAQUE_DELTA=SKIPPED）；BLOCKED 不参与 GATE 判定，已实测删掉 SC5 行后 GATE 仍为 A"
  - "第 3 条 test.sh 探针选 CGWindowLevelForKey(.screenSaverWindow)==1000 而非重复「图标层 − 桌面层 == 20」——后者与既有断言完全重复，实测基线 12 条里已含"
  - "8 份 VERDICT 引用的证据日志强制入库：.planning/spike/out/ 被 gitignore，不入库则 Phase 2–7 的引用链在 clone 后悬空"
  - "FALSE_POSITIVE_OBSERVED=1 写进 VERDICT 的「交给下游的三条硬约束」第 2 条，并点名 Phase 3 必须二选一：几何外判别信号，或显式接受误暂停方向并编码进 PauseReason"

patterns-established:
  - "文档级反形容词门（grep -v '^> ' … | grep -cE '正常|良好|看起来|没问题|差不多|应该能|预计' == 0）会连带约束正文注释：连「无 sudo」这种自述都不能写，必须写「无提权」"
  - "把 SC 行整行删掉后重新判定一次，是验证「门禁不被某条 SC 牵连」的最省事的做法"

requirements-completed: []

coverage:
  - id: D1
    description: "01-VERDICT.md 首行是单值 GATE=A/B，判据绑定 gate-01.log 两个字段"
    verification:
      - kind: integration
        ref: "01-VERDICT.md 首行 GATE=A；判据块 GATE=A ⟸ ORDER=ok 且 FINDER_RESTART_ALIVE=1；gate-01.log:ORDER=ok / :FINDER_RESTART_ALIVE=1；删掉 SC5 行后重判仍为 GATE=A"
        status: pass
    human_judgment: false
  - id: D2
    description: "ROADMAP 5 条 SC 逐条有结论，每条挂真实可解析的证据路径"
    verification:
      - kind: integration
        ref: "grep -cE '^\\| *SC[1-5] ' = 5；SC 表 4 条路径 test -f 全真且全部 git-tracked；SC5 证据格 0 个 / 与 0 个 .planning；SC5-注 脚注恰好 1 行且含 ab-verdict.txt 与 AB_STATUS=skipped reason=human_checkpoint"
        status: pass
    human_judgment: false
  - id: D3
    description: "已知障碍表齐全，含 D-02「事后补做，不阻塞」，无一条阻塞下游"
    verification:
      - kind: integration
        ref: "01-VERDICT.md「已知障碍」表 9 行，「是否阻塞」列 9 行全为否（第 6 行写作「否（不阻塞 Phase 2）」）；grep -c '事后补做，不阻塞' = 1"
        status: pass
    human_judgment: false
  - id: D4
    description: "四栏口径小节标题逐字齐备，反形容词门为 0"
    verification:
      - kind: integration
        ref: "grep -cE '^#{2,6} *跑过$' / '*没跑过$' / '*逻辑可行但本 Phase 未测$' / '*假定依赖$' 各 = 1；grep -v '^> ' 01-VERDICT.md | grep -cE '正常|良好|看起来|没问题|差不多|应该能|预计' = 0"
        status: pass
    human_judgment: false
  - id: D5
    description: "D-08 两条对照路线各有处置结论且如实标为部分确认"
    verification:
      - kind: integration
        ref: "01-VERDICT.md「层级写法定案」段：路线 C 原值 FRAMEWORK_TOTAL=5 / PRIVATE_FRAMEWORK_COUNT=0 / CGSSESSION_LINKED=0；路线 D 原值 D08_ROUTE_D_HARDCODED_LEVEL=-2147483623；两处均写明「只证明…不证明…」"
        status: pass
    human_judgment: false
  - id: D6
    description: "GATE=A 下全文不含路线 B 交接段"
    verification:
      - kind: integration
        ref: "grep -c '路线 B 交接' 01-VERDICT.md = 0"
        status: pass
    human_judgment: false
  - id: D7
    description: "test.sh 新增 3 条无 GUI / 无提权 / 无副作用探针，PASS 计数 12 → 15"
    verification:
      - kind: integration
        ref: "bash test.sh 退出码 0、汇总行「通过 15  失败 0」、末行「✅ 全绿」；输出含 NSStatusItem / AVPlayerLayer / screenSaverWindow 三项"
        status: pass
    human_judgment: false
  - id: D8
    description: "新探针段无副作用，且既有两条运行时断言未被破坏"
    verification:
      - kind: integration
        ref: "sed -n '/spike 门禁探针/,/── 渲染/p' test.sh | grep -cE 'sudo|screencapture|run-gate|menubar-check|scenarios' = 0；grep -c 'spike 门禁探针' test.sh = 1；grep -c 'desktopWindow = ' = 1；grep -c '与图标层差' = 1"
        status: pass
    human_judgment: false

duration: 22min
completed: 2026-10-03
status: complete
---

# Phase 01 Plan 05: 门禁判定 GATE=A + test.sh 收口

**Phase 1 判定为 `GATE=A`：路线 A（desktop-level `NSWindow`）在本机成立，Phase 2 可以直接用同一套写法起产品代码。** 5 条 Success Criteria 逐条有结论 —— SC1/2/3 PASS，SC4 PASS 但已实测到误判，SC5 BLOCKED（未采集，不伪造）。`bash test.sh` 仍是一条命令全绿，PASS 计数 12 → 15。

## 门禁结论

```
GATE=A  ⟸  ORDER=ok  且  FINDER_RESTART_ALIVE=1
GATE=B  ⟸  上述任一不成立
```

`.planning/spike/out/gate-01.log` 两个字段皆真 → **`GATE=A`**。`GATE=B` 的交接段按 plan 规定**全文不出现**（`grep -c '路线 B 交接'` = 0）。

## 5 条 SC 逐条结论

| SC | 结论 | 关键数字 |
|---|---|---|
| SC1 层级方案成立 | PASS | 我方 -2147483623 < Finder 图标层 -2147483603；KILLALL_RC=0、SPIKE_ALIVE=1、FINDER_RESTART_ALIVE=1、ORDER_AFTER=ok；FRAME 1→225。人工点击项 → 「事后补做，不阻塞」 |
| SC2 层级写法定案 | PASS | WINDOW_LEVEL_REPORTED=-2147483623；源码 CGWindowLevelForKey_desktopWindow=1 / hardcoded_-21474836=0 / desktopIconWindow=0；COMPILE_RC=0 errors=0 |
| SC3 菜单栏路线 | PASS | MENUBAR_VERDICT=ok；两变体 alive=1 layer0=0；policy=1；阳性对照 CONTROL_REGULARWINDOW layer0=1 |
| SC4 全屏几何原型 | PASS（含实测误判） | s0 live 1.000 / s1 blocked 0.886 / s2 synthetic 1.000 / s3 synthetic 1.000 / s4 synthetic 0.840；SELFTEST_VERDICT=pass；**FALSE_POSITIVE_OBSERVED=1** |
| SC5 锁屏 + 耗电 | BLOCKED | SCREENLOCK=unknown；OPAQUE_DELTA=SKIPPED=human_checkpoint；AB_GROUPS_MEASURED=0 |

## 本 Phase 最具后果的一条：`FALSE_POSITIVE_OBSERVED=1`

写进 `01-VERDICT.md` 的「交给下游的三条硬约束」第 2 条，一字未软化：

> Ghostty（pid 1227）与 CC Switch（pid 1228）两扇**真实**窗口各自把 `visibleFrame`（1470×833）铺满 → `coverage=1.000` ≥ 0.95 阈值 → 被判成 `fullscreen=true`。但两者 bounds 高 **833** 小于屏幕 frame 高 **956**，够不到刘海区，**结构上可证不是全屏**。coverage 已经顶在 **1.000 这个上限**，**任何阈值调整都改不了这个结果**。

结论写死为二选一，不留默认值：**Phase 3 必须设计一个几何之外的判别信号，或者明确写下接受「误暂停」这一方向的错误并编码进 PauseReason —— 不能默认沿用 0.95 阈值。**

另一侧方向是对的：`NEAR_FULLSCREEN_GUARD=pass coverage=0.840 fullscreen=false`（差一点满屏不误暂停）。

## 「层级写法定案」段（Phase 2 照抄）

| 项 | 定案 | 禁用理由 / 实测值 |
|---|---|---|
| 层级唯一写法 | `NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))` | 实测 **-2147483623**（`gate-01.log:SELF_LEVEL`） |
| `CGWindowLevelForKey(.desktopIconWindow)` | **禁用** | 实测 **-2147483603**，差 20，会盖住桌面图标（`gate-01.log:ICON_LEVEL`，该值仅在此处为对比而列） |
| 硬编码字面量 | **禁用** | 骨架代码里 `-21474836` 计数必须为 0 |
| `.accessory` rawValue | **是 1，不是 0** | `menubar.log`：`regular=0 accessory=1 prohibited=2`。0 是 `.regular`，恰是有 Dock 图标的那一个 |
| 刷新驱动 | `NSScreen.displayLink` + `preferredFrameRateRange` | macOS 27 SDK 上 `CADisplayLink(target:selector:)` 是 `API_UNAVAILABLE(macos)` |

**D-08 两条对照路线如实标为「部分确认」：** 路线 C 的 `FRAMEWORK_TOTAL=5 / PRIVATE_FRAMEWORK_COUNT=0 / CGSSESSION_LINKED=0` **只**证明「零私有框架即可过门禁」，**不**证明「私有框架会坏」；路线 D 的 `D08_ROUTE_D_HARDCODED_LEVEL=-2147483623` **只**证明「今天硬编码的数值与 `CGWindowLevelForKey` 一致」，**不**证明「该数值在未来 macOS 上不变」。禁用的理由是**未文档化、不受支持**，不是「今天跑不通」。

## test.sh：12 → 15

```
── spike 门禁探针 ─────────────────────
  ✅ NSStatusItem 退路可编译
  ✅ isOpaque=true 的 borderless NSWindow 可挂 AVPlayerLayer
── 运行时值 ───────────────────────────
  ✅ desktopWindow = -2147483623
  ✅ 与图标层差 20 级
  ✅ screenSaverWindow = 1000        ← 新增的第 3 条
───────────────────────────────────────
  通过 15  失败 0
  ✅ 全绿
```

第 3 条选 `CGWindowLevelForKey(.screenSaverWindow) == 1000`（本机实测 1000），**不是**再断言一次「图标层 − 桌面层 == 20」—— 那条在既有基线 12 条里已经有了，重复断言等于没加。

## 已知障碍（9 条，全部「是否阻塞 = 否」）

`SCREENSHOT=blocked`（无录屏权限，PNG 与对照图 md5 逐字节相同）、D-02 人工 10 秒确认（**事后补做，不阻塞**）、Chrome / 超宽屏为 synthetic、S1 blocked（`MAX_OBSERVED_FULLSCREEN=0`）、**几何误判**、`SCREENLOCK=unknown`、`powermetrics` A/B skipped、plan 04 的 bash 保留变量 `GROUPS` 陷阱。

## Deviations from Plan

### PLAN_DEVIATION

**`PLAN_DEVIATION=01 [自纠] SC5 标签里的斜杠违反 plan 自己的约束`**
第一稿把 SC5 命名为「锁屏触发 + 耗电 A/B」，其中的 `/` 触发 plan 的硬约束「SC5 行格内文本不含 `/`」。改为「锁屏触发与耗电四组」，**判据与数字一个没动**。

**`PLAN_DEVIATION=02 [自纠] test.sh 新段的注释含 `sudo`，触发 plan 自己的 T-01-16 门`**
注释原写「全部无 GUI、无 sudo、无副作用」。plan 的 T-01-16 判据是 `sed -n '/spike 门禁探针/,/── 渲染/p' test.sh | grep -cE 'sudo|screencapture|run-gate|menubar-check|scenarios'` = 0 —— 自述「无 sudo」同样会被抓到。改为「无提权」，门回到 0。**这条门确实有牙齿，不是纸面条款。**

**`PLAN_DEVIATION=03 [Rule 2 - 补关键功能] 8 份 VERDICT 引用的证据日志强制入库`**
plan 的 `files_modified` 只列了 `01-VERDICT.md` 与 `test.sh`。但威胁 T-01-18 要求「判定文件会被 Phase 2–7 当作事实引用，**引用链不能断**」，而 `.planning/spike/out/` 在 `.gitignore:4`。实测：SC 表 4 条证据路径里有 3 条在 git 索引里根本不存在 —— clone 后 VERDICT 的引用链直接悬空。按编排器 `<sequential_execution>` 的明确指示 `git add -f` 入库 8 份日志（含 plan 01-03 已入库的 `fullscreen-scenarios.log` 之外的 7 份）。
**只入库日志，不入库编译产物**（`wallpaperspike` / `windowprobe` / `menubarspike` / `menubarfallback` / `fullscreenprobe` / `lockprobe` / `lockval` / `diag-locked-window` 全部保持忽略）。
入库前对 8 份日志逐份扫过 `coderstory` / `/Users/` / `UID=` / `GID=`，无一命中；`cgsession-keys.txt` 的用户名 / uid / session UUID / audit id 在 plan 01-04 已按 T-01-03 脱敏。

**`PLAN_DEVIATION=04 [仓库流程] 提交落在 master`**
GSD 通用规程要求拒绝在受保护分支上提交；编排器 `<sequential_execution>` 明确要求「用普通 git 提交（带 hook）、不要 `--no-verify`」，且 01-01 / 01-02 / 01-04 的提交均在 `master`。以编排器指令为准。

**`PLAN_DEVIATION=05 [仓库流程] VERDICT 曾引用编译产物 `out/lockprobe` 作为跑过证据`**
`.planning/spike/out/lockprobe` 是编译出来的可执行文件，按编排器指令不得入库，一旦 clone 引用即悬空。改写为引用已入库的源码 `.planning/spike/LockProbe.swift`，产物仍指向 `lock.log`。

**`PLAN_DEVIATION=06 [plan 估算偏差，不改判据] plan 的威胁表估「新段跨约 30 行，含 1 条运行时断言」，实际不是这样`**
plan 的 action 要求第 3 条断言「在现有两行断言之后追加」，即留在「运行时值」段内；因此 `sed` 区段抽取只覆盖 2 条 `probe`。threat 表的 30 行是估算，**无任何验收判据依赖该行数**（门禁只查禁用字符串），不改判据、只在此登记以免日后被当成缺陷。

### 计划断言核对：本 plan 无一条事实性断言需要纠错

| plan 断言 | 本机实测 | 结论 |
|---|---|---|
| 既有基线 `通过 12  失败 0` | `通过 12  失败 0`（exit 0） | 成立 |
| 编排器称改动前 `grep -c '✅'` = 13 | = **13**（12 条断言 + 末行 `✅ 全绿`） | 成立，**不能用它当条数** |
| `CGWindowLevelForKey(.screenSaverWindow)` == 1000 | **1000** | 成立 |
| 既有两行 `desktopWindow = ` / `与图标层差` 各 1 处 | 各 1 处 | 成立 |

## Threat Model 落实

| Threat | 处置 | 证据 |
|--------|------|------|
| T-01-18 Repudiation | 反形容词门 = 0；判据写成两个字段的布尔表达式；8 条引用路径逐条 `test -f` **且**逐条查 git 索引，全部 disk=ok + repo=yes | 见上方 Verification 表 |
| T-01-16 Tampering | 区段抽取门 = 0 —— 且本 plan **真的被这条门拦下过一次**（见 PLAN_DEVIATION=02） | `sed -n '/spike 门禁探针/,/── 渲染/p' test.sh \| grep -cE 'sudo\|screencapture\|run-gate\|menubar-check\|scenarios'` = 0 |
| T-01-17 Information Disclosure | VERDICT 只引用结论字段（`ORDER` / `SELF_LEVEL` / `ICON_LEVEL` / `SCENARIO` 的 coverage / `SCREENLOCK` / `OPAQUE_DELTA`），不贴窗口枚举明细；8 份入库日志无 `kCGWindowName`、无用户名、无 home 路径 | grep 全部为 0 |

## Verification

| 检查 | 结果 |
|------|------|
| VERDICT 首行非空行 | `GATE=A` |
| `grep -cE '^\| *SC[1-5] '` | `5` |
| 四个小节标题各计数 | 跑过 1 / 没跑过 1 / 逻辑可行但本 Phase 未测 1 / 假定依赖 1 |
| 反形容词门 | `0` |
| `grep -c '路线 B 交接'` | `0` |
| `grep -c '^SC5-注：'` | `1`（含 `ab-verdict.txt` 与 `AB_STATUS=skipped reason=human_checkpoint`） |
| SC5 行内 `/` 数 / `.planning` 数 | `0` / `0` |
| SC1–SC4 证据路径 `test -f` | 4/4 为真 |
| 全部 8 条引用路径 disk + git 索引 | 8/8 `disk=ok repo=yes` |
| 删掉 SC5 行后重判 | 仍为 `GATE=A` |
| `bash test.sh` | exit `0`，`通过 15  失败 0`，末行 `✅ 全绿`，输出无 `❌` |
| `grep -c 'spike 门禁探针' test.sh` | `1` |
| `grep -c 'desktopWindow = '` / `grep -c '与图标层差'` | `1` / `1` |
| 新段禁用字符串计数 | `0` |
| 入库产物中是否混入可执行文件 | 无 |
| `STATE.md` / `ROADMAP.md` 是否被本 plan 改动 | 否（`git diff --name-only 49fbfe5..HEAD` 不含两者；两者在会话开始前即已是脏状态） |

## 交给 Phase 2 / Phase 3

1. **Phase 2 可以启动。** 层级 / `.accessory` / 刷新驱动三条写法照抄 VERDICT 的「层级写法定案」段，不重新推导。
2. **Phase 3 的全屏检测不能只靠几何**（见上），二选一，不留默认值。
3. **本 Phase 的降级证据不等于产品行为**：`FRAME_DRIVER=timer_fallback_hz30` 是无前台会话的降级路径，打包成 `.app` 后必须复测；`CGSSessionScreenIsLocked` 只验证了能读出状态，**未**验证跃迁时会翻转。

## Self-Check: PASSED

- [x] `.planning/phases/01-spike/01-VERDICT.md` 存在，`GATE=A` 单值明确
- [x] 5 条 SC 行齐备，无一条是空的
- [x] 已知障碍表 9 行，含 D-02「事后补做，不阻塞」
- [x] 四栏口径标题逐字齐备；反形容词门 0
- [x] `test.sh` exit 0 / `通过 15  失败 0` / `✅ 全绿`
- [x] 提交 `0db6644` / `9a4dea1` / `d507c8b` / `84b1dd2` 均存在于 `49fbfe5..HEAD`
- [x] `STATE.md` / `ROADMAP.md` 未被本 plan 修改
- [x] 无编译产物入库；无残留后台进程（本次未启动任何 GUI 进程）
