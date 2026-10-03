# PDCA 审计 — Phase 3（系统事件仲裁）

**审计时间：** 2026-10-03 · **审计人：** 编排器（Claude） · **触发：** 用户指令「每个阶段完成后执行一次 pdca 审计」
**判定输入：** `.planning/phases/03-system-events/03-VERDICT.md` + 5 份 SUMMARY + `.planning/WINDOWS.md`（Phase 3 的 `-14` ~ `-23` 十条窗口）

---

## P — Plan（原本承诺什么）

ROADMAP Phase 3 的 **5 条 Success Criteria**，交付 **7 条需求**（`PAUSE-01` ~ `PAUSE-07`）。

核心承诺是三件事：

1. **4 个 Watcher 各自独立可测** —— `FullscreenDetector` / `LockWatcher` / `PowerWatcher` / `DisplayWatcher` 只产出 `HoldReason`，不直接碰播放器。单向流 `Watcher → HoldArbiter → PlayerController`（D-09）。这是可测性与分层的前提，不是风格偏好。
2. **veto 集合仲裁** —— 多条件叠加时只有 `holds` 清空才续播；**明确禁用优先级链**（锁屏 + 全屏同时成立时，优先级链会在「退出全屏」时误恢复播放，D-10）。优先级只允许用于 UI 文案排序。
3. **解除后从原处续播** —— 续播锚点只在 `∅→非∅` 写入、`非∅→∅` 消费，叠加暂停期间不被二次覆盖（D-15）。

**本 Phase 零 UI 工作** —— 只把「当前为什么暂停」暴露成数据（`HoldStatus`），渲染留给 Phase 5（D-12）。**零第三方依赖**。

规模承诺：**5 个 plan，3 波**（Wave 1 tracer → Wave 2 三个 Watcher 并行 → Wave 3 装配 + 活体 evidence + VERDICT）。

---

## D — Do（实际交付了什么）

| SC | 结论 | 关键数字 |
|---|---|---|
| SC1 任意应用进入全屏 → 暂停；退出续播（不从头）；刘海屏 / Chrome / 超宽屏三场景各验证 | **PARTIAL** | 合取判定已跑通：`FULLSCREEN_VERDICT=0 reason=geometry_without_signal`、`COVERAGE=1.000`、`COVERING=1`、`NON_GEOMETRIC=0`、`WINDOW_COUNT=4`、`STYLEMASK_UNAVAILABLE=1`、`WINDOW_DICT_STYLE_KEY_COUNT=0`；`FullscreenGeometryTests` 5 条 + `FullscreenDetectorTests` 4 条；几何基准对齐 Phase 1 的 `1.000/1.000/1.000`。**缺口：真实跃迁与三场景各一遍均未做**（本机无 Chrome、单屏、锁屏会话）；另有一条反向实测：间歇性误暂停 |
| SC2 锁屏 / 熄屏 / 睡眠三类各自触发暂停，解除后各自正确续播 | **PARTIAL** | 锁屏与熄屏有活体证据：`PIC_HOLD active=1 reason=screenLocked holds=(screenLocked,displayAsleep)`、`PIC_HOLD_SUMMARY summary=锁屏,显示器熄屏 reasons=2`、`TICK_PAUSED_LINES=7`（`TICK_LINES=7`，7/7 `status=paused`）；续播锚点由单测锁住 `LOCK_ANCHOR_PRESERVED=1 seeks=42.000`。**缺口：三条跃迁与解除后的续播未观测**（会话自始至终锁着；显示器已熄屏稳态；睡眠被外部 `caffeinate` 挡着） |
| SC3 「电池供电时暂停」开关默认关闭；打开后拔电源暂停、插回续播 | **PARTIAL** | 默认关闭与判定逻辑已过：`BATTERY_HOLD enabled=0 verdict=0`、`IS_ON_BATTERY=0`、`POWER_SOURCE_VALUE=AC Power`、`INTERNAL_BATTERY_PRESENT=1`；`PowerWatcherTests` 6 条。**缺口：拔 / 插电源均未实测**（本机全程 AC，需物理动作） |
| SC4 veto 仲裁正确：锁屏中退出全屏不恢复；多条件叠加时只有集合清空才续播 | **PASS** | `Executed 67 tests, with 0 failures`；`HoldReason` 6 个 case → 运行时应 **64** 组子集，逐组断言 `decision.holds == subset` 与 `shouldPlay == subset.isEmpty`；反例用例断言「锁屏中退出全屏 `holds` 仍非空、不恢复播放」；**经注入式反向验证**（改掉耦合点后用例转红，`MUTATED_RC=1`）；`test.sh` 剥注释后 `player.player.play()` / `pause()` 计数各 = **0** |
| SC5 续播锚点不漂移：锚点在 `holds` 由空变非空时写入、由非空变空时消费，叠加暂停期间不被二次覆盖 | **PASS** | 6 个 reason 逆序解除下 `seeks == [42.0]`（一条 seek，锚点未被二次覆盖）；`∅ → 非∅ → ∅ → ∅` 四步下 `seeks` 恒为首次那个值；`LOCK_ANCHOR_PRESERVED=1 seeks=42.000` |

**交付量：**

- 5 个 plan 全部执行（03-01 ~ 03-05）。
- `HoldReason` 从 1 → **6 个 case**（`manualPause` + 全屏 / 锁屏 / 熄屏 / 睡眠 / 电池）。
- 4 个**事件** Watcher 装配完成（`LockWatcher` / `DisplayWatcher` / `PowerWatcher` / `FullscreenDetector`）：`wiring()` 接四根线，`applicationWillTerminate` 摘四个 `stop()`，两侧成对。
- 判定口径落地为 `verdict = nonGeometricActive && covering`（D-02「几何之外加判别信号」）。
- `PIC_HOLD` 从 0.5 秒轮询改**事件驱动**（D-05）：12 秒零决策变化窗口里 `OBSERVER_TICKS_MAX=1`（0.5 秒轮询会涨到约 24）。
- `W-2026-10-03-10` 直连 `player.player.play()` 收口为 `arbiter.applyCurrentDecision()`（`-22` resolved）。
- `test.sh` **32 → 50 项全绿**；`swift test` **24 → 67 tests 全绿**；幂集测试自动从 2 组扩到 **64 组**。

---

## C — Check（差距在哪）

### C1 🔴 真实跃迁从未观测 —— SC1 / SC2 / SC3 三条 PARTIAL 的共同根因

屏幕在本 Phase 执行期间**全程锁着**（`evidence/lock-state` 的 `LOCKED=1 LOCKEDTIME=1790976529 ONCONSOLE=1 LOGINWINDOW_PID=489`）。因此跃迁的**投递那一跳**一次都没跑过：

| 跃迁 | 证据 | 缺口 |
|---|---|---|
| 全屏（SC1） | `FULLSCREEN_TRANSITION=unobservable reason=session_locked CGSSessionScreenIsLocked=1` | 真实进入 / 退出全屏未观测；三场景各一遍未做（本机无 Chrome、单屏 `SCREENS_COUNT=1`） |
| 锁屏（SC2） | `LOCK_TRANSITION=unobservable reason=session_locked CGSSessionScreenIsLocked=1` | lock → unlock **没有边沿可等**；合成通知那条只验接线，不冒充真实跃迁 |
| 熄屏 / 睡眠（SC2） | `DISPLAY_SLEEP_TRANSITION=unobservable` / `SYSTEM_SLEEP_TRANSITION=unobservable` | 显示器已处于熄屏稳态（`CGDisplay_IS_ASLEEP=1`，`pmset displaysleep 5`），点亮那一下没发生；系统睡眠被外部 `caffeinate -i -t 300` 挡着（`POWER_PREVENT_SYSTEM_SLEEP=1`） |
| 拔电源（SC3） | `POWER_TRANSITION=unobservable reason=requires_physical_unplug … action=unplug_power_cord_required` | 本机全程 AC（`PMSET_CROSSCHECK=Now drawing from 'AC Power'`），需物理动作 |

即：`-20` 收口的**四类跃迁**（锁屏 / 熄屏 / 睡眠 / 拔电源）四条 `*_TRANSITION=unobservable`，**外加 SC1 的 `FULLSCREEN_TRANSITION`** 一条。
**缺口全部落在结论列，未塞脚注**（Phase 1 SC4 的教训：`01-VERDICT.md` 自述 overstate 了 LOCK 证据链，SC4 被重标 PARTIAL）。

**附加脆弱点 —— 会话锁定态在本 Phase 执行期间变了四次**（`evidence/session-state-changed.log` 的 `READ_1` ~ `READ_5`）：
03-05 开工时 `HAS_KEY=false KEYS=11`（未锁）、显示器 `CGDisplay_IS_ASLEEP=0`，产品实跑读到 `holds=(none) status=playing`；到 11:47 采集活体 evidence 时会话已重新锁上、显示器也已熄。
**所有活体读数只是「采集时刻」的读数，不是常量**：`holds-live.log` 里的 `displayAsleep` 只对采集那 **12 秒**窗口成立（采集后 11:50 前后显示器又亮了，独立复读 `CGDisplay_IS_ASLEEP=0`）。引用它时不得当成「本机显示器一直熄着」。03-02 已入库的 evidence 未被覆盖，复采另记在 `session-state-changed.log`。

### C2 🔴 SC1 的反向实测：全屏间歇性误暂停（`-23`）

装配后 `FullscreenDetector` **间歇性**把 `.fullscreen` 置位：一次插桩观测（3 轮中 1 轮）读到 `DBG_SET after=fullscreen before=`，随后 5 轮复跑**均未复现** → **给不出稳定复现率**。
成因属 03-02 的判定口径（Ghostty 恒覆盖 → `covering` 恒真，前台应用一变即误判），**不是本 plan 装配引入的回归** —— 装配前该 detector 从未 `start()` 过。
已登记 `W-2026-10-03-23`，**未改判定口径**（改它属 D-02 的架构决策，且需要真实跃迁样本）。**未为了让它非 0 去制造应用切换事件。**

### C3 🟡 判据自伤再 +4 次 —— 累计 12 次，仍是「源码字面量 grep」这一类

Phase 3 新增 4 次自伤（Phase 1 五次 + Phase 2 三次 + Phase 3 四次 = **12 次**），并暴露出三个新变体，已提炼成 D-13 ~ D-18：

| # | 事件 | 已定的处置 |
|---|---|---|
| 1 | 注释里的字面量污染 `grep -c`（本 Phase 4 次） | 必须用 `test.sh` 的 `src_count()`（4 条 `-e` 剥注释），或改行为断言 —— **D-13** |
| 2 | `no()` 文案里带了 `ok()` 的同一句判据名（03-01 / 03-02 / 03-04 连续三次） | 判据转红了但 `grep -c '❌ …'` 命中 0 → **判据一个不放宽，改文案** —— **D-14** |
| 3 | 反向验证的插桩打在自己写的注释上（03-04）；编译失败冒充「判据转红」（W-17） | 改注释不改判据；插桩要保证 `MUTATED_RC` 来自**断言失败**而非编译失败 —— **D-15 / D-16** |
| 4 | 一个计数器同时承载两种含义（03-04）；W 编号撞号（03-03 / 03-04 撞过 `-19`） | 拆成多行分开打点；分配不重叠号段并加 `uniq -d` 为 0 的判据 —— **D-17 / D-18** |

### C4 🟡 抓出的「计划事实错误」共 4 处（规划期 2 + 执行期 2）

| # | 计划里的错 | 若照做 / 实际后果 |
|---|---|---|
| 1（规划期） | `HoldReason.swift` 的 Phase 2 注释给 `fullscreen` 的 `order = 0`，与 `manualPause` 撞值 | `activeReasons` 排序不确定 → 03-01 取 1…5，`manualPause` 的 0 不动 |
| 2（规划期） | CONTEXT 称 `SettingsStore` 已含 battery 开关位，实际没有 | 03-04 以**带默认值的参数纯追加**（不改既有签名） |
| 3（执行期） | `scripts/probe-lock.sh` 的 `SRC=` 手写清单漏了新增的 `HoldStatus.swift` | 编译失败 `PROBE_COMPILE_RC=1`，并把日志清空 → **判据会静默变成假绿**。已在脚本里补上并写明「新增 / 删除 `State/` 下的文件时必须同步改这里」 |
| 4（执行期） | 计划 AC 的两条期望值与实测不符（期望 `holds=(screenLocked)` / `summary=锁屏 reasons=1`；实测 `holds=(screenLocked,displayAsleep)` / `summary=锁屏,显示器熄屏 reasons=2`） | **没有为了凑单 reason 去改产品** —— 两个 reason 都是真实读数（`CGDisplay_IS_ASLEEP=1`），按实际读数记录 |

### C5 ⚪ 三处「不制造数据」的选择

本 Phase 有三次面对「要不要造一个数」的岔路，**全部选了不造**：
① 不合成 `com.apple.screenIsLocked` 之外的系统跃迁去凑 SC1 / SC2；
② 不为了凑单 reason 去改产品（见 C4 #4）；
③ 不为了制造非 0 复现率去制造应用切换事件（见 C2）。
**这是本 Phase 最该被后续 Phase 继承的部分。**

---

## A — Act（下一步怎么改）

### 立刻生效（三条 ROADMAP 硬约束）

| # | 动作 | 落到哪 |
|---|---|---|
| **A1** | 🔴 **`-20` 四类跃迁（锁屏 / 熄屏 / 睡眠 / 拔电源）：解锁会话后各跑一次** `bash scripts/probe-lock.sh` / `probe-display.sh` / `probe-power.sh`。脚本无需修改（`-22` 收口时修过 `probe-lock.sh` 的源码清单） | ROADMAP Phase 4（不阻塞） |
| **A2** | 🔴 **`-23` 全屏误暂停：改判定口径前先重跑** `bash scripts/probe-fullscreen.sh` 采一份「真实进入全屏时的信号长什么样」，否则会在没有证据的情况下改架构 | ROADMAP Phase 4（不阻塞） |
| **A3** | 🔴 **判据禁裸 `grep -c`（累计自伤 12 次）；`no()` 文案不得含 `ok()` 判据名** | 已进 04-CONTEXT 的 D-13 / D-14，Phase 4 起执行 |

### 项目层面（跨阶段，影响 Phase 4–7）

| # | 动作 |
|---|---|
| **A4** | 判据写作规范 **D-13 ~ D-18** 已从 Phase 3 的自伤里提炼，写进 `04-CONTEXT.md`，后续 Phase 一律照用 |
| **A5** | **活体读数必须带「采集时刻」限定** —— 会话锁定态一天内变过四次，引用 `holds-live.log` 时不得当成常量（C1） |
| **A6** | `-22` 已 resolved（起播路径零播放器直连），但 `W-2026-10-03-21`（起播设置必须门在 `shouldPlay` 后）留档防 Phase 4–7 清理时回退 |
| **A7** | `test.sh` / `run-probe.sh` 的口径在 Phase 7 收口 —— 本 plan 给 `test.sh` 加了 6 项、给 `run-probe.sh` 加了 `holds` 子命令，两处都会被后续 Phase 复用 |

### 需要你本人（解锁会话后，不阻塞）

| # | 事项 | 为什么必须人工 | 依据 |
|---|---|---|---|
| **A8** | 解锁会话后各跑一次三探针（解除 `-20` 四类跃迁） | 屏幕当前锁着，无跃迁边沿可等 | C1 |
| **A9** | 真实进入 / 退出全屏一次（解除 SC1 缺口 + 给 `-23` 采样本） | 需真实应用切换 | C1 / C2 |
| **A10** | 拔 / 插电源一次（解除 SC3 缺口） | 需物理动作，本机全程 AC | C1 |
| **A11** | 锁屏 / 解锁各一次（解除 SC2 的 lock → unlock 边沿） | 需真实锁屏跳变 | C1 |

---

## 审计结论

**Phase 3 目标达成**：4 个事件 Watcher 装配完成并各自独立可测，veto 集合仲裁经 **64 组幂集**逐组断言 + 注入式反向验证锁死，续播锚点不漂移；`test.sh` 32 → **50 项全绿**、`swift test` 24 → **67 全绿**；`PIC_HOLD` 从 0.5 秒轮询改为事件驱动。

**过程纪律仍是本项目最大的资产**：`probe-lock.sh` 漏源码清单导致「判据静默假绿」被执行器自行抓出并留痕；计划 AC 的两条期望值与实测不符时，**没有为了凑单 reason 去改产品**；三处面对「要不要造一个数」的岔路**全部选了不造**（C5）。

**但 SC1 / SC2 / SC3 三条 PARTIAL，共同根因是同一个**：屏幕全程锁着，四类真实跃迁那一跳从未观测（`*_TRANSITION=unobservable`）；且所有活体读数只是「采集时刻」读数 —— 会话锁定态在执行期间变过四次。缺口全部落在结论列。

**Phase 3 应记为：完成（含 3 条 SC PARTIAL、1 条 `-23` 全屏误暂停未解、移交 Phase 4 / 5 / 7 共 6 项）。**
