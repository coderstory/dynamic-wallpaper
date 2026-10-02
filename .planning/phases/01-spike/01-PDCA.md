# PDCA 审计 — Phase 1（桌面层级门禁 spike）

**审计时间：** 2026-10-03 · **审计人：** 编排器（Claude）· **触发：** 用户指令「每个阶段完成后执行一次 pdca 审计」
**判定输入：** `.planning/phases/01-spike/01-VERDICT.md`（GATE=A）+ 5 份 SUMMARY + `git log`

---

## P — Plan（原本承诺什么）

ROADMAP Phase 1 的 **5 条 Success Criteria**，全部在 spike 阶段不交付 v1 需求，只消解可行性风险：

| SC | 承诺 |
|---|---|
| SC1 | 桌面层级方案成立（视频能待在图标后面，杀 Finder 后仍在） |
| SC2 | 层级写法定案（`CGWindowLevelForKey(.desktopWindow)`，`.desktopIconWindow` 禁用） |
| SC3 | `MenuBarExtra` 可用；不可用则 `NSStatusItem` 退路可编译 |
| SC4 | 全屏检测几何原型在**刘海屏 / Chrome / 超宽屏**三场景各产出一次判定 |
| SC5 | `com.apple.screenIsLocked` 是否触发有实测结论；`powermetrics` A/B 有**数字**结论 |

附加承诺：全程产出落在 `.planning/spike/`，不进产品代码库。

---

## D — Do（实际交付了什么）

| SC | 结果 | 真实数字 |
|---|---|---|
| SC1 | ✅ PASS | `SELF_LEVEL=-2147483623 < ICON_LEVEL=-2147483603`；`KILLALL_RC=0` / `SPIKE_ALIVE=1` / `FINDER_RESTART_ALIVE=1` / `ORDER_AFTER=ok` / 帧 1→225 |
| SC2 | ✅ PASS | 源码计数 `CGWindowLevelForKey_desktopWindow=1`、硬编码字面量 `=0`、`desktopIconWindow=0` |
| SC3 | ✅ PASS | `MENUBAR_VERDICT=ok`；两变体 `layer0=0`；`policy=1`；阳性对照 `layer0=1`（证探测器非瞎） |
| SC4 | ⚠️ PASS 但**证伪了既有思路** | 5 场景：1 live / 3 synthetic / 1 blocked；`SELFTEST_VERDICT=pass`；`FALSE_POSITIVE_OBSERVED=1` |
| SC5 | ❌ **BLOCKED** | `SCREENLOCK=unknown`；`OPAQUE_DELTA=SKIPPED`；`AB_GROUPS_MEASURED=0`（计划 4 组，量到 0 组） |

**纪律层面：完全达标。** 无产品脚手架、无伪造数字、无形容词留证（反形容词门返回 0）、`test.sh` 从 12 → **15 检查全绿**。

**额外产出（计划外但高价值）：** 5 个 plan 各自抓到一处「计划本身在本机的事实错误」，全部自行修正并留 `PLAN_DEVIATION` 行：

| Plan | 计划里的错 | 若照做会怎样 |
|---|---|---|
| 01-02 | `ActivationPolicy.accessory` rawValue 写成 `0` | `0` 是 `.regular` —— 正是**有 Dock 图标**那个，会造出假通过 |
| 01-03 | 「按 owner 名排除窗口」 | 被测窗口来自同一可执行文件，过滤器把被测对象删了 |
| 01-04 | `GROUPS` 当分组变量 | bash **保留数组**（用户 gid），静默覆盖不报错，dry-run 吐 16 个假分组 |
| 01-04 | ARCHITECTURE 称 `CGSession` 字典 5 键无锁键 | 实测 **14 键**，含 `CGSSessionScreenIsLocked`，推翻「降级方案未找到公开资料」 |
| 01-04 | `preferredForwardBufferDuration` 挂在 player | 它是 **`AVPlayerItem`** 属性 |

---

## C — Check（差距在哪）

### C1 🔴 **所有测量都在锁屏会话内完成** —— 方法论上最大的洞

`lock.log` 的 `SCREENLOCK_*` 采样显示 `SCREEN_LOCKED_AT_PROBE_START=1`、`UserIsActive 0`；每一条几何日志都带 `LOCK=1`。VERDICT 自己把它列进「假定依赖」：*「有前台进程时的窗口列表行为未验证」*。

**这意味着 `ORDER=ok`、`coverage=1.000` 这些数字全部来自一个没有前台 GUI 会话的 WindowServer 状态。** Phase 2 的产品代码跑在**解锁、有前台进程**的会话里 —— 那是一个**未测过的环境**。门禁的核心结论「路线 A 成立」建立在一个待验证的环境假设上。

严重度：高。这不是「差一点没测」，是**结论的适用边界没有被验证**。

### C2 🔴 SC5 整条 BLOCKED，零产出

`AB_GROUPS_MEASURED=0`（计划 4 组 × 5 分钟）。锁屏探针跑满 120 秒但屏幕全程已锁、无跃迁可观察 → `unknown`。

两半都没拿到结论。**这不是执行者的过失** —— `powermetrics must be invoked as the superuser` 是硬约束，我已在派发前实测确认。但它确实意味着 ROADMAP 承诺的 SC5 **零交付**，且**至今没有任何一条功耗数字**。

### C3 🟡 SC4 的三个指定场景全部没有真机样本

ROADMAP 点名「刘海屏 / Chrome 全屏 / 超宽屏」各一次判定。实际：

| 场景 | source | 原因 |
|---|---|---|
| 刘海屏全屏 | **blocked** | 会话锁定，`toggleFullScreen` 无效果（`MAX_OBSERVED_FULLSCREEN=0`） |
| Chrome 全屏 | **synthetic** | `/Applications/Google Chrome.app` 不存在 |
| 超宽屏 | **synthetic** | 只有 1 块屏 |

只有 S0 是 live，且它测的是**假阳性**而非真全屏。**「全屏检测能识别真全屏」这一命题，本 Phase 没有取得任何真机证据。**

### C4 🟡 视觉证据全缺

`screencapture` 无屏幕录制权限。D-02 的四条客观证据拿到 ①②④，**第 ③ 条（截图）与「人工 10 秒点选拖拽」都没有**。桌面层窗口「看起来对不对」至今无人用眼睛确认过。

处理方式本身是**诚实的**（对照抓图 md5 自检 → 报 `SCREENSHOT=blocked` 而非假装），但缺口是真实的。

### C5 🟡 估算偏差

5 个 plan 合计 estimate **292k tokens**；实际 subagent 消耗约 **530k**（planner+checker 另计约 350k）。01-05 自己发现单 plan 估算比实际高约 10×，建议按 chars/4 重校准。
→ **对 Phase 2–7 的影响：** 若沿用同一估算方式，排期会系统性偏乐观。

### C6 ⚪ 规划开销

3 轮 checker（1 blocker → 3 新 blocker → 1 blocker）。**对 spike 而言偏重**，但抓到的全是「执行者照做就失败」级的真问题（不可达阈值、判据互斥、事实错误前提），值得。

### C7 ⚪ 环境干扰未测

本机常驻 4 个同类动态壁纸 app（`Dynamic Wallpaper` / `Hanami Live Wallpaper` / `Wallpaper Monster` / `DevDesk`），至少一个同处 `-2147483623`。本 Phase 一律按 PID 认领，**未做 z-order 竞争测试**。Phase 2 产品运行时若与其抢层级，属未测风险。

---

## A — Act（下一步怎么改）

### 立刻生效（写进 Phase 2/3 的启动条件）

| # | 动作 | 落到哪 |
|---|---|---|
| **A1** | **在解锁会话中重跑 `run-gate.sh` 一次**，确认 `ORDER=ok` / `FINDER_RESTART_ALIVE=1` 在有前台进程时同样成立。**这是 Phase 2 的第一个任务**，不通过则门禁结论降级为「仅锁屏会话下成立」 | Phase 2 Task 1 前置 |
| **A2** | **Phase 3 全屏检测禁用 0.95 阈值**。`FALSE_POSITIVE_OBSERVED=1` 已证明几何阈值不可用。必须二选一：设计几何外判别信号（如 `activeSpaceDidChangeNotification` 关联），或明确接受「误暂停」方向并编码进 `PauseReason` | Phase 3 CONTEXT + ROADMAP |
| **A3** | 层级写法照抄 VERDICT「层级写法定案」段，不重新推导；`.accessory` 断言用 **1** 不是 0；显示刷新用 `NSScreen.displayLink`（`CADisplayLink(target:)` 在 macOS 27 已 `API_UNAVAILABLE`） | Phase 2 全程 |
| **A4** | 打包成 `.app` 后**必须复测显示刷新回调** —— spike 的 `FRAME_DRIVER=timer_fallback_hz30` 是降级路径，不等于产品行为 | Phase 2 验收项 |
| **A5** | 桌面层窗口有 **14pt/9pt 系统性内缩**（叠加刘海 33pt 共 47pt），任何覆盖率/全屏几何计算必须先处理 | Phase 2/3 |

### 需要你本人（无法自动化）

| # | 事项 | 成本 |
|---|---|---|
| **A6** | **跑 `bash .planning/spike/powermetrics_ab.sh`**（四组 × 5 分钟）补 SC5 后半 | 需你在场输入密码，约 21 分钟 |
| **A7** | **锁屏 / 解锁各一次**，观察 `com.apple.screenIsLocked` 与 `CGSSessionScreenIsLocked` 是否跃迁 | 10 秒 |
| **A8** | **人工 10 秒**：确认桌面图标可点选、可拖动，且壁纸确实在图标后面 | 10 秒 |
| **A9** | 决定是否申请屏幕录制权限（决定后续能否用截图做证据） | 一次设置 |

### 方法论修正（影响 Phase 2–7）

| # | 动作 |
|---|---|
| **A10** | 估算按 **chars/4** 校准，不要用 planner 的 token estimate 排期 |
| **A11** | 后续阶段的 spike/探针**优先在解锁会话跑**；无法保证时，结论必须显式标注环境（本次做得对，每条日志带 `LOCK=1`） |
| **A12** | 产品代码（Phase 2+）必须考虑与本机 4 个同类壁纸 app 的 z-order 竞争；建议 Phase 2 验收时**临时退掉**它们跑一次对照 |

---

## 审计结论

**门禁本身成功**：路线 A 成立，Phase 2–7 可以按原计划启动。**过程纪律优秀**：三处「计划事实错误」被 executor 自行抓出并留痕，无伪造数字，无形容词留证。

**但门禁结论的适用边界未被验证**（C1）—— 所有数字来自锁屏会话，而产品将跑在解锁会话。这是本 Phase 最重要的未闭合项，已列为 Phase 2 的第一个前置任务（A1）。

**Phase 1 应记为：完成（含 1 项 BLOCKED、1 项待重测）。**