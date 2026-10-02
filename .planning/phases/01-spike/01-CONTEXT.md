# Phase 1: 桌面层级门禁 spike - Context

**Gathered:** 2026-10-03
**Status:** Ready for planning
**Mode:** mvp (Walking Skeleton not applicable — 本 Phase 不交付产品代码，是 throwaway 验证)

<domain>
## Phase Boundary

**只回答一个问题：「视频能不能真的待在桌面图标后面」。**

答「能」→ Phase 2 用同一套写法起产品代码。
答「不能」→ **自动转路线 B（`.saver` 屏保 bundle）**，不回头问用户（见 D-01）。

本 Phase **不交付任何 v1 需求**。它消解的是 PLAY-01 / PLAY-02 / PAUSE-01 / PAUSE-02 / SYS-02 的**可行性风险**。

产出是 `.planning/spike/` 下的一次性验证 app / 脚本 —— **throwaway，不进产品代码库**。

</domain>

<decisions>
## Implementation Decisions

### 门禁失败与验收（用户 2026-10-03 拍板）
- **D-01:** 门禁**证伪**（桌面层级方案不成立）→ **自动转路线 B**：`.saver` 屏保 bundle（`CFBundlePackageType=BNDL`）。不回头问用户，做完再报。
- **D-02:** 「桌面图标仍可点选 / 可拖动」**无法自动化**（需真人手点）。用**强证据**推进，不阻塞 Phase 2：① 我方窗口 level 严格低于 Finder 桌面图标窗口 ② `CGWindowListCopyWindowInfo` 里 Finder 图标窗口在我方之上 ③ 截图 ④ `killall Finder` 后仍在。**人工 10 秒肉眼确认事后补做。**

### 层级写法（已编译+运行实测，不得再议）
- **D-03:** 层级 = `NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))` = **-2147483623**。**不硬编码数字。**
- **D-04:** `.desktopIconWindow`（-2147483603，差 20）**显式列为禁用项** —— 会盖住桌面图标。
- **D-05:** AppKit 无 `NSDesktopWindowLevel` 常量（已 grep 确认），`CGWindowLevelForKey` 是唯一来源。

### spike 的形态
- **D-06:** throwaway app：一个挂在桌面层级的窗口，跑动态内容 + **叠加帧号**（证明在动、能看出卡没卡）。
- **D-07:** `powermetrics` A/B **四组**，每组 5 分钟：① 不播 ② v1 配置（`isOpaque=true` + `AVPlayerLayer`）③ `isOpaque=false` ④ `AVPlayerView`。产出数字，不产出形容词。
- **D-08:** 路线 C（`CGSSession` 私有框架）/ 路线 D（硬编码 WindowServer level 数字）作为**对照项**顺带测，用于确认禁用理由成立。

### 不做
- **D-09:** **不跑 research-phase。** ROADMAP 明确：「它本身就是研究，不是需要调研 —— 需要的是执行」。ARCHITECTURE.md / PITFALLS.md 已有足够原材料。

### Claude's Discretion
- spike app 的具体文件组织、测量脚本的实现方式、判定阈值的具体数值（刘海屏全屏覆盖率的容差）
- `MenuBarExtra` vs `NSStatusItem` 的取舍：先试 `MenuBarExtra`（代码少），失败则退 `NSStatusItem`

</decisions>

<specifics>
## Specific Ideas

**必须在刘海屏 / Chrome 全屏 / 超宽屏三种场景各产出一次判定结果。** PITFALLS.md 实测过：刘海屏下全屏应用只覆盖 96.548%，Chrome 只有 87.343% —— 用「窗口 bounds == 屏幕 bounds」做全屏判定会漏判/误判。误判方向必须是「**宁可少暂停，不要误暂停**」。

**`com.apple.screenIsLocked` 在本机 macOS 27 上是否触发必须有明确实测结论** —— 它未文档化。若失效，Phase 3 升级为需 research（真正降级方案未找到公开资料）。

</specifics>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

- `.planning/research/ARCHITECTURE.md` §2 — 路线对比表、层级数值表（**全部【实测】**）
- `.planning/research/PITFALLS.md` — 9 条关键坑，含刘海屏 96.548% / Chrome 87.343% 实测数字
- `.planning/PROJECT.md` — Core Value、Key Decisions、已编译验证的 API 事实清单
- `.planning/ROADMAP.md` — Phase 1 的 5 条 Success Criteria（本 Phase 的验收标准）
- `test.sh` / `build.sh` — 已有的工具链验证脚本与打包流水线（spike 可复用编译方式）

</canonical_refs>

<existing_artifacts>
## 已有的可复用资产

- **`.planning/spike/SettingsSpike.swift`** — 已编译、已渲染的 SwiftUI spike（`swiftc -parse-as-library -target arm64-apple-macosx15.0` 通过）。**编译方式可直接抄。**
- **`test.sh`** — 12/12 全绿，含 5 个编译期 API 探针 + 2 个运行时数值验证。**新加的探针往这里挂。**
- **`build.sh`** — 已验证的 DMG 流水线（swiftc → .app bundle → codesign adhoc → hdiutil）。
- **工具链已就绪**：Xcode 27.0，`xcodebuild` / `actool` / macOS 27 SDK 全部可用。

</existing_artifacts>

<constraints>
## Constraints

- **主机**：macOS 27.0.1 / Apple Silicon（本机）
- **权限**：调研已实测确认**无需**辅助功能权限、无需私有框架、无需屏幕录制权限。若 spike 中发现需要权限，**记为发现并如实报告**，不要静默降级。
- **不写生产代码**：本 Phase 的一切产出都在 `.planning/spike/`，不建产品目录结构。
- **最小代码量**：spike 也要少写 —— 能用一个 `swiftc` 命令编译的单文件就不要建 Xcode 工程。
- **「无法解决的问题能跳过就跳过」**（用户 2026-10-03）：卡住的问题标记为已知障碍继续推进，不阻塞整条流水线。

</constraints>

---

<orchestrator_directives>
## 编排器硬性指令（planning 时必须遵守）

### 产出位置 —— 这是 throwaway spike，不是产品阶段
违反下列任何一条即为计划失败：

1. **产出全部在 `.planning/spike/`** —— 不得创建产品目录结构（不要建 `Sources/`、`Pic/`、`Package.swift`、Xcode 工程）。Phase 2 才起产品代码。
2. **能用一个 `swiftc` 命令编译的单文件就不要建 Xcode 工程。** 已有先例：`.planning/spike/SettingsSpike.swift` 用 `swiftc -parse-as-library -target arm64-apple-macosx15.0` 编译 —— 照抄。
3. **不生成 `SKELETON.md`。** MVP 规则会机械匹配「Phase 01 + 无前序 summary」为 Walking Skeleton，但 Walking Skeleton 要求「scaffold 项目 + 路由 + 一次真实 DB 读写 + 一次真实 UI 交互」，与本 Phase「不产出产品代码」直接冲突。**已裁定为 false。**
4. **不跑 research-phase**（D-09 已定）。ARCHITECTURE.md / PITFALLS.md 已有足够原材料。

### requirements 字段
本 Phase **不交付任何 v1 需求** → `requirements` 字段写 `[]` 或省略，**不要**把 PLAY-01 / PAUSE-01 等 ID 塞进去。用 `must_haves.truths` 承载 ROADMAP 的 5 条 Success Criteria。

### 每个判定都要可复现
**只接受可复现的原始数字或截图**，不接受「看起来正常」「性能良好」这类形容词。ROADMAP Success Criteria 明确要求「有明确实测结论」「有数字结论」。

### 不阻塞原则
**「无法解决的问题能跳过就跳过」**（用户 2026-10-03 明确授权）：某探针若在本机不可行（缺权限 / 系统不给 / 工具缺失），计划里要有明确的「标记为已知障碍 + 继续推进」路径，**不得写成阻塞性任务**让整条流水线卡死。

### 验收不得安排需要人手点击的阻塞项
D-02 已定：「桌面图标仍可点选/可拖动」无法自动化，**本次不阻塞 Phase 2**。证据用四项客观信号：① 我方窗口 level 严格低于 Finder 桌面图标窗口 ② `CGWindowListCopyWindowInfo` 里 Finder 图标窗口在我方之上 ③ 截图 ④ `killall Finder` 后仍在。**人工 10 秒肉眼确认事后补做。**

### 待覆盖的 5 条 Success Criteria（逐条落到任务）
1. 桌面层级彩色窗口 + 帧号出现后，桌面图标可点选可拖动，`killall Finder` 后壁纸仍在 → **层级方案成立**
2. 层级写法定案并落进骨架代码：`NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))` 编译+运行通过；`.desktopIconWindow`（差 20）**显式列为禁用项**
3. `MenuBarExtra` 在 `.accessory` 激活策略 + 无 Dock 图标下实测可用；若不可用，`NSStatusItem` 退路**已验证可编译**
4. 全屏检测几何原型在**刘海屏 / Chrome 全屏 / 超宽屏**三种场景各产出一次判定结果，误判方向确认为「**宁可少暂停，不要误暂停**」
5. `com.apple.screenIsLocked` 在本机 macOS 27 上**是否触发**有明确实测结论；`isOpaque = true` 的 `powermetrics` A/B 有**数字**结论

外加 D-06 / D-07 / D-08：
- 帧号叠加（证明画面在动、能看出卡顿）
- `powermetrics` A/B **四组**，每组 5 分钟：① 不播 ② v1 配置（`isOpaque=true` + `AVPlayerLayer`）③ `isOpaque=false` ④ `AVPlayerView`
- 路线 C（`CGSSession` 私有框架）/ 路线 D（硬编码 WindowServer level 数字）作为**对照项**，确认禁用理由成立

### 违反即失败的质量门
- 不得创建产品目录结构、不得有 Xcode 工程、不得有 `SKELETON.md`
- 每个可运行 `<automated>` 命令后紧跟 `<fails_when>`（写明可观察的失败信号，禁止 `TBD`/`TODO`/`N/A`/`none`/`unknown`）
- 每任务含 `<read_first>`（至少含被修改的文件）+ `<acceptance_criteria>`（无主观语言）+ `<action>`（具体标识符，无代码块）
- 含 "Artifacts this phase produces" 段

</orchestrator_directives>

---

<planner_partial_findings>
## Planner 中途发现（agent 被中止前的实测观察，**未完成验证，标注为待复核**）

- **坐标系陷阱（重要，影响 Phase 3 全屏检测）**：`CGWindowListCopyWindowInfo` 返回的窗口 bounds 是**左上角原点**（实测主屏 Y=33），而 `NSScreen.frame` 是**左下角原点**。两者直接比较会得到错误的「全屏覆盖比例」。全屏判定必须先做坐标翻转（`y_converted = screenHeight - (y + height)`）再比。
  —— 来源：planner agent 实测观察后被中止，**本 Phase 必须复现并给出确认数字**，不能直接当既成事实用。

</planner_partial_findings>
