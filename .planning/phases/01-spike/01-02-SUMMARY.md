---
phase: 01-spike
plan: 02
subsystem: ui
tags: [swiftui, appkit, menubarextra, nsstatusitem, activation-policy, swiftc, throwaway-spike]

requires:
  - phase: 01-spike
    plan: 01
    provides: "spike 目录与 swiftc 编译先例（Render.swift / WallpaperSpike.swift / run-gate.sh）"
provides:
  - "MenuBarExtra + .accessory 主路线：单文件可编译可运行，stdout 打出 PIC_MENU 行"
  - "NSStatusItem 退路：独立二进制可编译可运行（ROADMAP SC 3 兜底条款无条件成立）"
  - "menubar-check.sh：一条命令产出 menubar.log，含 MENUBAR_VERDICT"
  - "「无 Dock 图标」的可自动核对留证：policy=<accessory rawValue> + layer0=0"
  - "本机实测：NSApplication.ActivationPolicy regular=0 / accessory=1 / prohibited=2"
  - "layer-0 探针的阳性对照（CONTROL_REGULARWINDOW layer0=1）"
affects: [02-product-core, ui-layer, settings-window, menubar]

actuals:
  tokens: 3462
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "throwaway spike：单文件 + swiftc -parse-as-library -target arm64-apple-macosx15.0，不组装 .app bundle"
    - "证据即 stdout：变体只打印一行 PIC_MENU，判定全交给 grep/字段比对，不肉眼断言"
    - "无 Dock 图标 = policy(accessory rawValue) + 本进程 layer0 窗口数 == 0（按 kCGWindowOwnerPID 认领）"

key-files:
  created:
    - ".planning/spike/MenuBarSpike.swift"
    - ".planning/spike/MenuBarFallback.swift"
    - ".planning/spike/menubar-check.sh"
    - ".planning/spike/out/menubar.log (gitignored, 存在于工作树)"
  modified: []

key-decisions:
  - "MENUBAR_VERDICT=ok —— MenuBarExtra 主路线本机实测可用，Phase 2 走主路线"
  - "PLAN DEVIATION：plan 写 accessory rawValue=0 是错的（实测 1）。policy 打印 setActivationPolicy 之后的生效值，判定期望值由探针当场实测，不写死 0 —— 0 是 .regular（有 Dock 图标），照抄 plan 会得到假通过"
  - "日志用 VARIANT=（2 行，alive/layer0）+ VARIANT_PIC_MENU=（转发 PIC_MENU 原文），因为 plan 的 step 5 与它自己的 fails_when「VARIANT= 行数必须等于 2」互相冲突，以机器门为准"
  - "加阳性对照：同一探针必须能看见自建 layer0 窗口（实测 1），否则 layer0=0 无法区分「无窗口」与「探针瞎了」"

patterns-established:
  - "PIC_MENU 统一行格式：policy=<n> ok=<bool> menubarExtra=<ok|fallback> dock=hidden_by_policy —— 两条路径同形，一条 grep 同时核对"
  - "限时统一 perl -e 'alarm N; exec @ARGV'（本机无 timeout 命令）"
  - "trap cleanup 同时 kill 进程与删 mktemp 目录；收尾用 pgrep 断言无残留"

requirements-completed: []

coverage:
  - id: D1
    description: "MenuBarExtra 在 .accessory 激活策略下可编译可运行并常驻菜单栏"
    requirement: omit
    verification:
      - kind: automated_ui
        ref: "swiftc -parse-as-library -target arm64-apple-macosx15.0 -o .planning/spike/out/menubarspike .planning/spike/MenuBarSpike.swift"
        status: pass
  - id: D2
    description: "NSStatusItem 退路独立二进制可编译可运行"
    requirement: omit
    verification:
      - kind: automated_ui
        ref: "swiftc -parse-as-library -target arm64-apple-macosx15.0 -o .planning/spike/out/menubarfallback .planning/spike/MenuBarFallback.swift"
        status: pass
  - id: D3
    description: "一条命令产出 menubar.log 并给出 MENUBAR_VERDICT，退出码 0"
    requirement: omit
    verification:
      - kind: other
        ref: "bash .planning/spike/menubar-check.sh"
        status: pass

commits: 3
plan_head_before: 845609b
plan_head_after: 68bfbc0fc66d75a33e82851b248d8048ce75237c

status: complete
---

# Phase 01 Plan 02: 菜单栏路线门禁（MenuBarExtra 主路线 + NSStatusItem 退路）

**One-liner:** MenuBarExtra 与 NSStatusItem 两条路线都在 `.accessory` 策略下实测可用，`MENUBAR_VERDICT=ok`，Phase 2 走 MenuBarExtra。

## 结论（ROADMAP Success Criteria 第 3 条）

| 判据 | 结果 |
|---|---|
| `MENUBAR_VERDICT` | **`ok`** |
| `menubarspike` | `alive=1` `layer0=0` `PIC_MENU policy=1 ok=true menubarExtra=ok dock=hidden_by_policy` |
| `menubarfallback` | `alive=1` `layer0=0` `PIC_MENU policy=1 ok=true menubarExtra=fallback dock=hidden_by_policy` |
| 本机激活策略 rawValue | `regular=0` `accessory=1` `prohibited=2`（实测，见下） |
| 探针阳性对照 | `CONTROL_REGULARWINDOW layer0=1` —— 同一探针确实能看见 layer0 窗口 |
| 收尾残留 | `pgrep -f 'out/menubar(spike|fallback)'` 无输出 |
| 脚本退出码 | 0 |

**留下的唯一未知**：菜单栏图标的**存在与外观没有肉眼确认**，也不需要 —— `policy=1`（.accessory，进程不注册为普通 GUI app）+ `layer0=0`（本进程无 layer-0 窗口）是它的可自动核对代理，日志里 `NOTE=` 那一行就是这个口径。本机 `screencapture` 无录屏权限（plan 01-01 实测返回占位图），本 plan 不做任何截图断言。

## 与 plan 的偏差

### 1. [Rule 1 - Bug] plan 写错了 accessory 的 rawValue

plan 在 Task 1 / Task 2 / Task 3 三处都断言 `NSApplication.ActivationPolicy.accessory` 的 rawValue 是 `0`，并把 `policy=0` 写进验收判据。本机实测：

```
regular=0  accessory=1  prohibited=2
```

`0` 是 **`.regular`** —— 恰恰是「有 Dock 图标」的那一个。若照抄 plan，`policy=0` 会把「.regular」判成「.accessory」，直接伪造出一个通过。

修法：`policy` 打印 `setActivationPolicy` 之后的**生效值**（左到右插值会先读到调用前的旧策略，本来也是无效证据）；`menubar-check.sh` 不写死期望值，由探针当场实测 `POLICY_ACCESSORY` 再作为 `EXPECT_POLICY`。日志里保留一行 `PLAN_DEVIATION=` 记着这件事。

### 2. [Rule 1 - Bug] plan 内部自相矛盾：step 5 要 4 行 `VARIANT=`，fails_when 要恰好 2 行

plan Task 3 的 action 说「每个变体两行」且两行都以 `VARIANT=` 开头（`alive/layer0` 行 + 转发 PIC_MENU 行），但同一任务的 `fails_when` 与 acceptance 要求 `VARIANT=` **恰好 2 行**。以机器门为准：日志用 `VARIANT=<名> alive=.. layer0=..`（2 行）+ `VARIANT_PIC_MENU=<名> <PIC_MENU 原文>`（转发，不改一个字节）。`grep -c 'VARIANT='` 与 `grep -c '^VARIANT='` 都是 2。

### 3. [Rule 2 - 补关键功能] 加探针阳性对照

`layer0=0` 若探针本身瞎了就是假通过。加一个同样 `.accessory`、只多一扇 60×60 无边框 level-0 窗口 3 秒的对照进程（不产生 Dock 图标），要求同一探针对它报 `layer0>=1`。实测 `CONTROL_REGULARWINDOW layer0=1`，探针有效。对照失败只落 `CONTROL_NOTE=`，不改判定的口径（判定条件仍按 plan 三条）。

### 4. [Rule 1 - Bug] 对照进程漏了 `@main`

初版对照源文件写了 `static func main()` 却没写 `@main`，进程走 C 运行时默认 `main` 静默退出 0（stderr 全空、alive=0）。加上 `@main` 并改用 `-parse-as-library` 后正常。

### 5. [Rule 3 - 阻塞修复] `struct` 不能继承 `NSObject`

`StatusMain` 原本写成 `struct StatusMain: NSObject`，编译报 `inheritance from non-protocol type 'NSObject'` + `#selector` 无法暴露。改成 `final class`。

## 各任务结果

| # | 任务 | 结果 | Commit |
|---|---|---|---|
| 1 | MenuBarExtra 主路线（tracer） | 编译 exit=0 / 0 error；启动存活；`PIC_MENU policy=1 ok=true menubarExtra=ok dock=hidden_by_policy` | `afe4698` |
| 2 | NSStatusItem 退路 | 编译 exit=0 / 0 error；启动存活；`PIC_MENU policy=1 ok=true menubarExtra=fallback dock=hidden_by_policy` | `5272b17` |
| 3 | menubar-check.sh | exit=0；`MENUBAR_VERDICT=ok`；两个变体 `layer0=0`；无残留 | `68bfbc0` |

tracer 反馈门：human_verify_mode=`end-of-phase` 且 Task 1 的 verify 全自动 → 重跑一遍 end-to-end（exit=0 / error_lines=0 / binary=executable）通过，不设人工卡点，继续。

## 源码级判据核对

```
grep -v '^[[:space:]]*//' MenuBarSpike.swift  | grep -c MenuBarExtra  → 1   (≥1 ✓)
grep -v '^[[:space:]]*//' MenuBarSpike.swift  | grep -c LSUIElement  → 0   (不打包 ✓)
grep -v '^[[:space:]]*//' MenuBarSpike.swift  | grep -c 'Button("'   → 5   (固定 5 条，退出含在内 ✓)
grep -v '^[[:space:]]*//' MenuBarSpike.swift  | grep -c '当前播放'    → 0   (菜单不显示文件名 ✓)
退路五个标题各出现次数：暂停=1 立即下一个=1 重新扫描文件夹=1 打开设置窗口=1 退出=1
grep -v '^[[:space:]]*//' MenuBarFallback.swift | grep -c MenuBarExtra → 0  (退路不依赖 SwiftUI ✓)
```

## 给 Phase 2 的落点

- **菜单栏走 `MenuBarExtra`**，不再退 `NSStatusItem`（退路代码已验证可编译可运行，存档备用）
- `.accessory` + 无 Dock 图标的写法照抄 `MenuBarSpike.swift` 的 `MenuBarSpikeDelegate`；**`policy` 断言用 1**
- 菜单体固定 5 条 / 无子层级 / 不显示文件名，`MenuBarBody` 的结构可直接搬
- 退路里「退出」带真实 `#selector`（`keyEquivalent: "q"`），Phase 2 的「退出能真正结束进程」有现成写法
- 本 spike 的 5 个按钮是空实现（plan 明写「本 spike 只验证能否弹出，行为是空实现」）

## 已知障碍 / 留白

| 项 | 状态 | 处置 |
|---|---|---|
| 菜单栏图标的肉眼确认 | 未做 | 不需要。`policy=1` + `layer0=0` 是可自动核对的代理，日志 NOTE 行已声明口径；本机 screencapture 无录屏权限 |
| 「点开菜单后 5 条是否如预期渲染」 | 未做 | 本 plan 只验「能否挂上 / 能否弹出」，`POLICY` 与 `layer0` 都不覆盖菜单内容 |
| `.planning/WINDOWS.md` 缺陷台账 | 未写入 | `gsd_run` 不在本机 PATH，best-effort 项，跳过（下方无遗留 stub / skipped test） |

## Known Stubs

| 位置 | 内容 | 原因 |
|---|---|---|
| `MenuBarSpike.swift` `MenuBarBody` 5 个 `Button` | 行为全为空 `{}` | plan 明写「本 spike 只验证能否弹出，行为是空实现」。这是 throwaway spike，不进产品代码库 |
| `MenuBarFallback.swift` 4 个 `NSMenuItem` | `action: nil` | 同上；只有「退出」给了真实 target，因为它是唯一能结束进程的一项 |

两个 stub 都不影响本 plan 的目标（判定的是「路线可不可用」），也不需要后续 plan 收拾 —— spike 目录不进产品代码库。

## Threat Flags

无新增。菜单栏插入 / Dock 抢焦点两条已在 plan 的 threat register（T-01-04 / T-01-05）里，mitigation 均已落地：不写 Info.plist、不调 `NSApplication.shared.activate`、`trap` + 显式 `kill` + `pgrep` 三重收尾。

## Self-Check: PASSED

- `.planning/spike/MenuBarSpike.swift` — FOUND
- `.planning/spike/MenuBarFallback.swift` — FOUND
- `.planning/spike/menubar-check.sh` — FOUND（`-rwxr-xr-x`）
- `.planning/spike/out/menubar.log` — FOUND（717 bytes，工作树内；`.planning/spike/out/` 按 plan 01-01 的约定在 .gitignore 里）
- commits `afe4698` / `5272b17` / `68bfbc0` — FOUND（`git log --oneline -3`）
- `MENUBAR_VERDICT=ok` — FOUND
