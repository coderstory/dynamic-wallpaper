---
phase: 07-delivery
plan: 04
subsystem: delivery
tags: [packaging, dmg, codesign, adhoc, stress-test, memory, uninstall, defaults, gatekeeper]

requires:
  - phase: 07-delivery/07-01
    provides: "双产物构建（Pic.app + PicProbe.app）、图标资产、DMG 打包路径"
  - phase: 07-delivery/07-02
    provides: "SYS-01 开机自启实测证据与 emit 行、probe-sys01.sh 的起 app/kill 形状"
  - phase: 07-delivery/07-03
    provides: "soak 采样器与分析器、UAT-SOAK.md 人工清单、soak 证据目录"
  - phase: 06-transcode
    provides: "ffmpeg 红线判据写法（拆串构造）、Phase 6 人工项清单"
provides:
  - "AppDelegate 退出路径的 PIC_ROT_ADVANCES_TOTAL 快照（一行 emit）"
  - "scripts/stress-rotation.sh —— 50 次换片压测，RSS 回 warmup 基线 ±10%"
  - "scripts/verify-packaging.sh —— 双构建一致性（锚 .app）+ ad-hoc 形态正向断言"
  - "scripts/verify-uninstall.sh —— 四项卸载残留复查为 0 + 开发机偏好备份恢复"
  - "test.sh 的 Phase 7 交付判据段（11 条通过 + 1 条 skip）"
  - "07-VERDICT.md —— Phase 7 的唯一判定文件，四栏诚实基线"
affects: [07-delivery, PACK-01, PACK-02, PACK-03, PACK-04, ASSET-03, SC5]

actuals:
  tokens: 41000
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "重复构建一致性锚 .app 内容而非 DMG 容器（UDIF 不可复现）"
    - "spctl 拒绝 rc=3 是正向断言 —— 未签名未公证就该被拒"
    - "退出快照计数：自动轮换的累计值只在退出路径 emit，与菜单手动打点分离"
    - "test.sh 新增变量一律带 phase 前缀，避免跨段变量打架"

key-files:
  created:
    - scripts/stress-rotation.sh
    - scripts/verify-packaging.sh
    - scripts/verify-uninstall.sh
    - .planning/phases/07-delivery/07-VERDICT.md
    - .planning/phases/07-delivery/evidence/stress-rotation.log
    - .planning/phases/07-delivery/evidence/packaging.log
    - .planning/phases/07-delivery/evidence/uninstall.log
  modified:
    - Sources/PicApp/AppDelegate.swift
    - test.sh

key-decisions:
  - "「重复执行结果一致」的锚点是 .app 的二进制/plist md5 与 DMG 文件清单，不是 DMG md5 —— UDIF 容器层已实测不可复现，锚错会把好构建判坏；不可复现性以 PACK_DMG_MD5_NOTE 一行显式记录留给审计"
  - "PIC_ROT_ADVANCES_TOTAL 与既有 PIC_ROT_ADVANCES= 不是同一次读：后者只在菜单手动 next 打（压测全程无人点菜单），前者是退出快照；新增行不制造二义，但短 token 是长 token 的前缀，判据一律数长 token"
  - "7 天长跑在 test.sh 里是 skip 分支 —— 人工周期既不被自动判据卡死，也不被算成已通过"
  - "卸载脚本是校验路径不是真卸载：export → app 自己 disableBoth → 文件级补刀 → 复查为 0 → import 恢复，尾注 simulated_uninstall_then_restored"
  - "读数不合理时宁可 BLOCKED 也不交假绿：压测加了一道 RSS 合理性下限，读到壳进程直接 exit 2"

patterns-established:
  - "外部命令一律套 perl alarm（本机无 timeout 命令），不用 set -e，清理与断言同一条 trap 路径"
  - "test.sh 的 no() 文案必须带 ok() 的同一句判据名，红绿靠 ✅/❌ 前缀区分（D-14）"
  - "二进制符号计数必须 grep -cE；裸 grep 的 | 是字面量，恒 0 假绿灯"

requirements-completed: [PACK-01, PACK-02, PACK-03, PACK-04]

coverage:
  - id: D1
    description: "50 次换片压测：进程内计数 ≥50 且 RSS 回 warmup 基线 ±10%"
    requirement: PACK-04
    verification:
      - kind: integration
        ref: "scripts/stress-rotation.sh → evidence/stress-rotation.log:STRESS_ADVANCES=100 STRESS_RSS_DRIFT_PCT=-1.8"
        status: pass
    human_judgment: false
  - id: D2
    description: "重复执行结果一致（锚 .app 二进制/plist md5 + DMG 清单），并显式记录 DMG md5 不可复现"
    requirement: PACK-01
    verification:
      - kind: integration
        ref: "scripts/verify-packaging.sh → evidence/packaging.log:PACK_REPEAT_CONSISTENT=1 PACK_DMG_MD5_NOTE="
        status: pass
    human_judgment: false
  - id: D3
    description: "无上架动作的形态面：adhoc + TeamIdentifier not set + spctl rc=3 + 无 .pkg + 无沙盒 entitlements"
    requirement: PACK-02
    verification:
      - kind: integration
        ref: "scripts/verify-packaging.sh → evidence/packaging.log:PACK_SPCTL_RC=3 PACK_NO_APPSTORE_ARTIFACTS=1"
        status: pass
    human_judgment: false
  - id: D4
    description: "DMG 挂载校验：hdiutil verify + 挂载点内二进制 md5 == 构建产物 + 图标三项"
    requirement: PACK-01
    verification:
      - kind: integration
        ref: "evidence/packaging.log:PACK_HDIUTIL_VERIFY=ok PACK_MOUNT_BINARY_MD5_MATCH=1"
        status: pass
    human_judgment: false
  - id: D5
    description: "卸载残留四项复查为 0 且开发机偏好原样恢复"
    requirement: PACK-04
    verification:
      - kind: integration
        ref: "scripts/verify-uninstall.sh → evidence/uninstall.log:UNINSTALL_RESIDUE_TOTAL=0 UNINSTALL_RESTORED=1"
        status: pass
    human_judgment: false
  - id: D6
    description: "test.sh 一条命令收口全部可自动化验证，全绿退出 0"
    requirement: PACK-04
    verification:
      - kind: integration
        ref: "bash test.sh → 通过 102 失败 0 跳过 1（退出码 0；跳过项为 7 天长跑）"
        status: pass
    human_judgment: false
  - id: D7
    description: "create-dmg 主路生成 DMG（窗口布局/图标位置/Applications 快捷方式）"
    requirement: PACK-03
    verification: []
    human_judgment: true
    rationale: "本机 create-dmg 的 Finder 美化步骤需要终端对 Finder 的「自动化」权限（AppleEvent -1743），三次构建全部走 hdiutil 降级。降级路径只保证 DMG 产出，窗口布局与拖入体验从未跑过。解除方式是人一次性授权，非自动化可及。"
  - id: D8
    description: "ASSET-03 两套图标视觉同源（一眼看出是同一个 app）"
    requirement: ASSET-03
    verification: []
    human_judgment: true
    rationale: "视觉判据。自动侧只证了「同一生成器文件 + 同一手绘语言 + v1 构图一致」—— 同一生成器不等于视觉同源，拿结构性事实冒充视觉结论。真判据是 UAT-SOAK.md 人工轮次里那条并排肉眼比对记录，该记录目前不存在。"
  - id: D9
    description: "SC5 7 天在位长跑（不重启、不崩溃、内存无单调上涨、电池让路）"
    requirement: PACK-04
    verification: []
    human_judgment: true
    rationale: "人工周期。采样器与判据 07-03 已建好并用合成数据自证有牙齿，但 evidence/soak/soak.log 是 0 字节空占位，真实数据一行都没有。"
  - id: D10
    description: "SC4 后半：20 轮休眠/唤醒/锁屏/解锁状态 100% 正确、无黑屏灰屏"
    requirement: PACK-04
    verification: []
    human_judgment: true
    rationale: "需真人操作（唤醒必须真人开盖/按键），executor 不能代做。UAT-SOAK.md 人工轮次表一条都未执行。"
  - id: D11
    description: "SC3 装版重启后开机自启在位"
    requirement: PACK-04
    verification: []
    human_judgment: true
    rationale: "需装 DMG 版并重启机器。机制面已证（ACTIVE_ROUTE=smappservice），但重启后的持久化从未验证，07-02 已登记为 user_setup 项。"

duration: 42min
completed: 2026-10-04
status: complete
---

# Phase 7 Plan 04: 压测 + 打包校验 + 卸载校验 + VERDICT 收官 Summary

**50 次换片压测拿到进程内计数与真实 RSS 读数（ADVANCES=100、漂移 -1.8%），双构建一致性以 `.app` 内容为锚成立（两遍二进制 md5 逐字相同），卸载四项残留复查为 0 且开发机偏好原样恢复，`test.sh` 收口全绿 102/0/1，Phase 7 VERDICT 四栏如实登记五个人工项。**

## Performance

- **Duration:** 42 min
- **Tasks:** 3
- **Files modified:** 7（3 新建脚本 + VERDICT + AppDelegate 一行 + test.sh 段 + 3 份 evidence）

## Accomplishments

- **SC4 前半钉死**：AppDelegate 退出路径加一行 `PIC_ROT_ADVANCES_TOTAL` 快照，
  `scripts/stress-rotation.sh` 用 1 秒自动轮换跑 90 秒（warmup 15 + 采样窗 75），
  实测 **ADVANCES=100**（≥50）、**RSS 漂移 -1.8%**（118784KB → 116704KB）、
  走的是 `applicationWillTerminate` 而非 SIGTERM、两个 defaults 键恢复原值、零残留进程。
- **SC1 以正确锚点成立**：两遍 `build.sh`，二进制 md5 两遍同为 `a42bfb65a1c74ca723a70e4eeac648b4`、
  plist md5 两遍同为 `23bfbbf43ed66f23f0cc5db1b82e5426`、DMG 文件清单一致。
  **不打 DMG md5 对比**（UDIF 容器层已实测不可复现），改打 `PACK_DMG_MD5_NOTE` 把理由留给审计。
- **PACK-02 形态面全部正向断言**：`Signature=adhoc`、`TeamIdentifier=not set`、
  `spctl rc=3`（**预期拒绝**）、`hdiutil verify ok`、挂载点二进制 md5 与产物一致、
  `.pkg` 计数 0、`app-sandbox` entitlements 计数 0。
- **卸载残留四项为 0**：defaults 域 / Preferences plist / LaunchAgent / BTM 全部复查干净，
  `defaults export → import` 恢复链工作正常（跑完 `NSWindow Frame settings` 仍在）。
- **test.sh 收口**：Phase 7 段 11 条通过 + 1 条 skip（7 天长跑 = 人工周期，
  既不被卡死也不被算成已通过）。对账可查。
- **07-VERDICT.md**：5 条 SC 逐条结论 + 四栏（跑过 / 没跑过 / 逻辑可行但未测 / 假定依赖）。

## Task Commits

1. **Task 1: PIC_ROT_ADVANCES_TOTAL 退出计数 + stress-rotation.sh** — `0157247`
2. **Task 2: verify-packaging.sh + verify-uninstall.sh** — `7992724`
3. **Task 3: test.sh Phase 7 判据段 + 07-VERDICT.md** — `7b405cb`

## Files Created/Modified

- `Sources/PicApp/AppDelegate.swift` — `applicationWillTerminate` 里加一行退出快照 emit
- `scripts/stress-rotation.sh` — 50 换片压测（备份/写入/warmup/采样/恢复/判定）
- `scripts/verify-packaging.sh` — 双构建一致性 + 形态断言 + 无上架产物
- `scripts/verify-uninstall.sh` — 四项残留复查 + 偏好备份恢复
- `test.sh` — Phase 7 交付判据段（插在 Phase 6 段之后、渲染段之前）
- `.planning/phases/07-delivery/07-VERDICT.md` — Phase 7 唯一判定文件

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] 压测的 RSS 读数读的是壳进程，漂移判据是空判**
- **Found during:** Task 1（首跑压测）
- **Issue:** `alarm 200 env … "$APP" … &` 之后 `$!` 取到的是**跑 `alarm` 函数的子 shell**
  （`comm=bash`），不是 app 本身。读它的 RSS 恒为 1.7MB，两次读数**完全相同** →
  漂移恒 0.0，`STRESS_VERDICT=pass` 是个假绿。首跑证据
  `STRESS_RSS_START_KB=1808 / STRESS_RSS_END_KB=1808` 就是征兆：1.8MB 对一个
  AppKit + AVFoundation 进程不可能，而 117MB 才是真实值。
- **Fix:** 改为按 app 二进制路径 `pgrep -f` 反查真实 PID；并加一道 RSS 合理性下限
  （< 20000KB 判 `STRESS_BLOCKED reason=rss_reading_implausible` 并退出 2）——
  宁可报 blocked，也不拿假绿交差。
- **Files modified:** `scripts/stress-rotation.sh`
- **Verification:** 复跑后 `STRESS_APP_PID=35699`、`RSS_START=118784`、`RSS_END=116704`、
  `DRIFT_PCT=-1.8`，读数真实且漂移非零。
- **Committed in:** `0157247`

**2. [Rule 1 - Bug] `test.sh` 的新段覆盖了 `SRC`，把渲染段打成恒红**
- **Found during:** Task 3（首跑 test.sh）
- **Issue:** spctl 判据把退出码存进 `SRC`，而 `test.sh:30` 的 `SRC` 是**渲染段的源文件清单**。
  覆盖后渲染段编译了一个空列表 → 「设置窗渲染失败」恒红。失败现场指向的是两百行外的
  另一段，不是新加的那段。
- **Fix:** 本段新增变量一律带 `P7` 前缀（`P7APP` / `P7PROBE` / `P7RES` / `SPCTL_RC`），
  与既有段的短名彻底分开；并在注释里写明这条跨段变量打架的坑。
- **Files modified:** `test.sh`
- **Verification:** 用「删掉 Phase 7 段的 test.sh」跑一遍得 91/0/0（渲染绿），
  保留则 102/0/1（渲染绿）—— 确证因果。修复后渲染段 `✅ 设置窗渲染成功 (459633 bytes)`。
- **Committed in:** `7b405cb`

**3. [Rule 2 - Missing Critical] 计划的 ffmpeg 门禁命令自身有缺陷**
- **Found during:** Task 1
- **Issue:** 计划给的 `grep -v '^[[:space:]]#'`（少一个 `*`）无法剥掉行首列 0 的注释 ——
  `[[:space:]]` 是单字符类，一个都不匹配。实测该命令仍数出 2 处转码字样，
  而 `test.sh:601` 自己的同类门禁用的是正确写法 `'^[[:space:]]*#'`。
- **Fix:** 让脚本内容同时满足两种写法 —— 注释里改用不含该字样的表述，
  非注释行零出现。两种门禁实测均为 0。
- **Files modified:** `scripts/stress-rotation.sh`
- **Verification:** `/usr/bin/grep -v '^[[:space:]]#' … | grep -c` 与
  `… '^[[:space:]]*#' …` 两条路径都返回 0。
- **Committed in:** `0157247`

---

**Total deviations:** 3 auto-fixed（1 空判 bug、1 跨段变量 bug、1 计划判据缺陷）
**Impact on plan:** 三处都是「判据会假绿/假红」的性质 —— 正是本 plan 的立论目标
（SC1/SC4 最容易被形容词糊弄）。修复后所有判据都真的会在违规时转红。
无 scope creep。

## Issues Encountered

- **plan 的 T1 `<verify>` 命令里写了 `cd /Users/coderstory/dev/pic`** —— 那是主仓路径，
  在 worktree 隔离下必须改用 worktree 自身的 toplevel，否则会验错 checkout
  （worktree-path-safety §0c 明令禁止）。
- **`fixtures/` 不在 git 里**（gitignored，ffmpeg 生成）。worktree 里没有，
  压测脚本按计划先跑一次 `scripts/make-fixtures.sh` 补齐。这是 ffmpeg 调用，
  但它发生在**手动执行的采集脚本**里，不在任何自动测试路径上，与用户红线
  「ffmpeg 只能手动跑」不冲突（`test.sh` 全程零 ffmpeg，有专门判据锁）。
- **卸载脚本本机没有触发最危险的输入**：`sourceFolderPath` 基线即 `__ABSENT__`，
  所以 W-2026-10-03-46 点名的「把用户 sourceFolderPath 弄丢」这次没有被真正考验。
  已在 VERDICT 的「逻辑可行但未测」里如实登记，没有拿「恢复链工作正常」
  冒充「最坏情况已验证」。

## User Setup Required

无新的 USER-SETUP.md。已有的人工动作见 VERDICT「交给用户/下一阶段」：
7 天长跑、约 40 分钟人工轮次（含 ASSET-03 并排比对）、
`create-dmg` 的「自动化 → Finder」一次性授权。

## Next Phase Readiness

Phase 7 的**自动化面全部收口**：`test.sh` 一条命令全绿退出 0（PACK-04）。

尚未解锁的三条都不是自动化能解的：
- **SC5 长跑**（7 天人工周期，`SOAK_VERDICT` 至今不存在）
- **SC3 重启后自启**（需装版重启）
- **SC4 后半 20 轮**（需真人操作）
- **SC1 的 create-dmg 主路**（需一次性人工授权）

Phase 6 的四项人工项（画质 bench / 转码窗目视 / 入口置灰 / 听音 W-33）在本 Phase
**未解除**，SC#3 在 Phase 6 VERDICT 里至今是 PARTIAL —— Phase 7 VERDICT 已如实继承登记。

## Self-Check: PASSED

- 三个 task 的 `<acceptance_criteria>` 逐条跑过并通过
- plan 级 `<verification>` 的五条全部实跑
- `swift test` 全绿 198 项（与基线一致）
- `bash test.sh` 退出码 0，通过 102 / 失败 0 / 跳过 1
- 无遗留进程、无未提交文件、无临时脚本残留

---
*Phase: 07-delivery · Plan: 04*
*Completed: 2026-10-04*