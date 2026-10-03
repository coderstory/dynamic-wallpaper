# Phase 7 判定：打包、开机自启与整机验收

**本文件是 Phase 7 的唯一判定文件。** 判据输入来自
`.planning/phases/07-delivery/evidence/` 下的原始日志、`bash test.sh` 的实际输出与
`swift test` 汇总，不从 SUMMARY 转述。

🔴 **两条红线先行声明**

1. **本 Phase 的全部自动路径零 ffmpeg 进程调用。** 压测只播放 fixtures 里已有的 mp4
   （播放是 app 的日常行为，与日常看片同量级），不碰转码。
2. **两个核弹级禁令在判据里有牙齿**：`sfltool resetbtm`（会清掉**全部**登录项，不只是本 app
   的）在两个校验脚本里剥注释后计数均为 **0**（W-2026-10-03-41）。

## 5 条 Success Criteria 逐条结论

判据原文见 `.planning/ROADMAP.md` Phase 7 Success Criteria 第 1–5 条。
结论列只有 `PASS` / `PASS-with-gap` / `PARTIAL` / `PENDING-HUMAN` 四种取值。

| SC | 结论 | 证据（文件:字段） | 数字 |
|---|---|---|---|
| SC1 `build.sh` 一条命令跑完编译 → `.app` → DMG；零手工步骤，**重复执行结果一致** | **PASS-with-gap** | 一致性：`packaging.log:PACK_BIN_MD5_A/B`（两遍**逐字相同**）、`:PACK_PLIST_MD5_A/B`、`:PACK_REPEAT_CONSISTENT=1`；DMG 内容：`PACK_HDIUTIL_VERIFY=ok` `:PACK_MOUNT_BINARY_MD5_MATCH=1` `:PACK_DMG_APP_COUNT=1` | 二进制 md5 两遍同为 `a42bfb65a1c74ca723a70e4eeac648b4`；plist md5 两遍同为 `23bfbbf43ed66f23f0cc5db1b82e5426`；DMG 内 .app 计数 1<br>**缺口：「用 `create-dmg` 生成 DMG」这一半在本机从未成立** —— 见下 |
| SC2 `test.sh` 一条命令跑完全部可自动化验证；全绿退出 0，任一失败退出非零 | **PASS** | `bash test.sh` 实跑输出（见「跑过」表）；`probe-strip.log:PROBE_STRIP_DELIVERY_SYMBOLS=0` | 通过 **102** / 失败 **0** / 跳过 **1**（跳过的 1 项 = 7 天长跑，人工周期）。**对账**：改动前基线 86/0/5（当时 worktree 无 `build/`，打包段整段 skip）；补上 `build/` 后未改动的 test.sh 为 91/0/0；加本 Phase 段后为 102/0/1 → **净增 11 条通过 + 1 条 skip** |
| SC3 未签名 app 的开机自启有**实测结论**并落地 | **PARTIAL**（机制面）/ **PENDING-HUMAN**（重启后） | `sys01.log:SYS01_ACTIVE_ROUTE=smappservice` `:SYS01_SMAPP_STATUS=enabled` `:SYS01_ROUTE=smappservice`；`test.sh` 的「SYS-01 实测路线已判定」 | `ACTIVE_ROUTE=smappservice`（路线 A 成立）；`SYS01_REBOOT_CONFIRMED=pending_human`。**缺口：装版重启后自启是否真在位，从未验证** |
| SC4 压力验收：**连续换片 50 次内存回到基线 ±10%**；连续 **20 轮** 休眠/唤醒/锁屏/解锁状态 100% 正确、无黑屏灰屏 | **PASS**（前半）/ **PENDING-HUMAN**（后半） | 前半：`stress-rotation.log:STRESS_ADVANCES` `:STRESS_RSS_DRIFT_PCT` `:STRESS_VERDICT`；后半：UAT-SOAK.md 人工轮次表 | `STRESS_ADVANCES=100`（≥50）；`STRESS_RSS_DRIFT_PCT=-1.8%`（\|漂移\| ≤ 10%）；`STRESS_TERMINATE_PATH=applicationWillTerminate`；`STRESS_DEFAULTS_RESTORED=1`。<br>**缺口：20 轮休眠/唤醒/锁屏/解锁的人工轮次一次都没做** |
| SC5 长跑验收：DMG 装出的 `.app` 连续运行 **≥7 天**不重启、不崩溃、内存无单调上涨；电池供电按设置让路 | **PENDING-HUMAN** | `evidence/soak/soak.log`（**空占位**，0 字节）；`UAT-SOAK.md`（7 天人工周期一页清单） | `SOAK_VERDICT` **不存在**。采样器与判据已由 07-03 建好并用合成数据自证，但**真实 7 天数据一行都没有** |

### SC1 的缺口说清楚：为什么不是 PASS

ROADMAP SC1 原文要求「**用 `create-dmg`** 生成 DMG」。本机这件事**一次都没成功过**：

```
execution error: 未获得授权将Apple事件发送给Finder。 (-1743)
```

`create-dmg` 的 Finder 美化步骤需要**终端对 Finder 的「自动化」权限**，这是一次性人工授权，
不在 executor 的自动化范围内。`build.sh` 的降级路径（`hdiutil create`）每次都成功兜住，
所以**「DMG 产出了」成立，「用 create-dmg 生成 DMG」不成立**。

因此本 Phase 的三次构建（含本次两遍）走的都是降级路，evidence 里如实记为
`PACK_DMG_ROUTE_A=hdiutil_fallback` / `PACK_DMG_ROUTE_B=hdiutil_fallback`。
窗口布局、图标位置、Applications 拖入快捷方式**全部未验证**。
解除方式：人给终端授予「自动化 → Finder」权限，之后 `bash build.sh` 零手工重复。

### SC1 的一致性锚点为什么是 `.app` 而不是 DMG（W-2026-10-03-45）

DMG 的 md5 **已实测不可复现** —— 四次独立 `build.sh` 得到四个不同的值，
而两次 DMG 内的 `Pic.app` 逐字节相同。差异在 UDIF 容器层（即使把源树 mtime 全部 pin 成
同一时刻，相隔 2 秒的两次 `hdiutil create` 仍产出不同 md5）。

所以「重复执行结果一致」锚 **.app 的内容 + DMG 的文件清单**，`verify-packaging.sh`
**不打 DMG md5 对比**，改打一行 `PACK_DMG_MD5_NOTE=anchor_app_not_dmg
reason=udif_container_nondeterministic` 把「为什么不断言它」显式留给审计。
把锚点写成 DMG md5 会把好构建判坏 —— 那是一个必然假红的判据。

## ASSET-03 的诚实特例：视觉同源不是自动判据

`ASSET-03`（「两套图标视觉上同源，一眼能看出是同一个 app」）**在本 VERDICT 里不是 PASS**。

07-01 明确**不设自动门**：可断言的只有「同一生成器文件 + 同一手绘语言 + v1 构图一致」，
而 `drawAppIcon` 与 `drawMenuBar` 是**两个函数**（`drawAppIcon` 的 `menuBar: true` 分支是死代码）。
**同一生成器 ≠ 视觉同源** —— 拿结构性事实冒充视觉结论，正是 Phase 1 SC4 翻车的那类错误。

它的**唯一真判据**是 `UAT-SOAK.md` 人工轮次里那一行：
「app 图标与菜单栏图标**并排**看是不是『一眼同一个 app』」（pass/fail + 一句结论）。

**该记录目前不存在**（7 天人工周期尚未开始），故 ASSET-03 = **PENDING-HUMAN**。
本 Phase 自动侧只证明了「两套图标出自同一个 `tools/make-icons.swift`、v1 构图一致」，
这**不足以**支撑「一眼同源」的结论。

## 四栏口径

### 跑过

| 项 | 命令 | 产物 | 数字 |
|---|---|---|---|
| 交付构建 | `bash build.sh` | `build/Pic.app`、`build/PicProbe.app`、`dist/Pic-0.1.0.dmg` | `Signature=adhoc`、`TeamIdentifier=not set`；`PROBE_SYMBOLS_PIC=0`、`PROBE_SYMBOLS_PROBE=195`（成对判据，正控非零） |
| 50 换片压测（SC4 前半） | `bash scripts/stress-rotation.sh` | `evidence/stress-rotation.log` | `STRESS_ADVANCES=100`；`RSS_START=118784KB` → `RSS_END=116704KB`；`STRESS_RSS_DRIFT_PCT=-1.8%`；`STRESS_DEFAULTS_RESTORED=1`；`STRESS_VERDICT=pass`；残留进程 0 |
| 重复构建一致性（SC1） | `bash scripts/verify-packaging.sh` | `evidence/packaging.log` | 两遍构建；二进制 md5 两遍同为 `a42bfb65…`；plist md5 两遍同为 `23bfbbf4…`；`PACK_REPEAT_CONSISTENT=1` |
| 打包形态面（PACK-02） | 同上 | 同上 | `PACK_SPCTL_RC=3`（**预期拒绝**）、`PACK_HDIUTIL_VERIFY=ok`、`PACK_MOUNT_BINARY_MD5_MATCH=1`、`PACK_PKG_COUNT=0`、`PACK_APP_SANDBOX_ENTITLEMENTS=0`、`PACK_NO_APPSTORE_ARTIFACTS=1` |
| 卸载残留复查（SC 尾项） | `bash scripts/verify-uninstall.sh` | `evidence/uninstall.log` | `UNINSTALL_RESIDUE_TOTAL=0`；域 / Preferences plist / LaunchAgent / BTM 四项复查全 absent-或-0；`UNINSTALL_RESTORED=1` |
| 无头回归收口（SC2 / PACK-04） | `bash test.sh` | 终端输出 | 通过 **102** / 失败 **0** / 跳过 **1**；退出码 0。**对账**：无 `build/` 时基线 86/0/5 → 有 `build/` 且未改 test.sh 时 91/0/0 → 加本 Phase 段后 102/0/1，**净增 11 通过 + 1 skip**（跳过的 1 项即 7 天长跑） |
| 产品单测 | `swift test` | 终端输出 | 由 test.sh 既有段承担，全绿 |

### 没跑过

| 项 | 为什么没跑 | 证据 |
|---|---|---|
| SC5 的 7 天在位长跑 | **人工周期** —— 机器得在、app 得开着、不主动重启。采样器与判据 07-03 已建好（`soak-sampler.sh` / `soak-analyze.sh`），并用五份合成数据自证有牙齿，但真实数据一行都没有 | `evidence/soak/soak.log` **0 字节**；`SOAK_VERDICT` 不存在。`test.sh` 里它是 **skip 分支** —— 既不被自动判据卡死，也不被算成已通过 |
| SC4 后半的 20 轮休眠/唤醒/锁屏/解锁 | 需真人操作（唤醒必须真人开盖/按键），本会话不可代做 | `UAT-SOAK.md` 人工轮次表；一条都未执行 |
| SC3 的重启后自启确认 | 需装 DMG 版并**重启机器**，07-02 已登记为 user_setup 项 | `sys01.log:SYS01_REBOOT_CONFIRMED=pending_human` |
| ASSET-03 的并排肉眼比对 | 视觉判据，executor 不能代判 | `UAT-SOAK.md` 人工轮次表；该记录不存在 |
| SC1 的 `create-dmg` 主路 | 需人给终端授予「自动化 → Finder」权限（AppleEvent -1743） | `packaging.log:PACK_DMG_ROUTE_A/B=hdiutil_fallback` |
| **继承自 Phase 6 的人工项** | 见下节 | — |
| **继承自 07-01 的缺口** | `fixtures/` 不在 worktree（gitignored），影响 07-01 的 `run-probe.sh app` 一组读数（`ORDER=fail` / `SELF_LEVEL=none`，会随 session 锁定态变化） | 07-01-SUMMARY「Issues Encountered」 |

### 继承 Phase 6 的人工项（如实登记，不得记作 PASS）

以下几项**没有任何自动读数**，Phase 6 已登记，Phase 7 **未解除**：

1. **SC#3 的画质侧** —— `scripts/transcode-bench.sh` 的 SSIM/VMAF 实测**从未运行**
   （零 ffmpeg 红线）。参数侧 PASS ≠ 画质达标。阈值 SSIM≥0.98 / VMAF≥95 仍是
   `[ASSUMED]` 的行业经验值，不是本机实测。
2. **转码窗的活体目视** —— 打开转码窗看徽章文案、队列条目与命令展示是否成行
   （结构有断言，屏上像素无）。
3. **入口置灰 + 三途径弹层** —— 临时挪走 ffmpeg 可执行文件后打开设置窗验证（须复原并重查）。
4. **SC#2 的行为面** —— 队列串行 + 进度实时刷新 + 命令可审计展示，自动侧（纯逻辑 + 桩）已过，
   活体行为未验。
5. **SC#4 的听音（W-33）** —— 变速后的保音高效果无自动读数。

### 逻辑可行但本 Phase 未测

| 项 | 逻辑依据 | 未测什么 |
|---|---|---|
| 卸载路径的「app 自己清登录项」 | `verify-uninstall.sh` 第 3 段已实现（起 app 让 `disableBoth` 跑一遍，因为 BTM 只能由活着的 app unregister） | **本机基线本就没有本 app 的登录项**，故 `UNINSTALL_APP_DISABLEBOTH_RAN=0 reason=no_baseline_login_item` —— 这条路径**没有真跑过**。脚本形状正确，但未在有登录项的机器上验证 |
| 卸载后的偏好恢复 | `defaults export` → `defaults import` 备份链已验证 | 本机 `sourceFolderPath` **基线即 `__ABSENT__`**，所以 W-2026-10-03-46 点名的那个具体风险（把用户的 sourceFolderPath 弄丢）**这次没有被真正触发**。恢复链实际恢复的是 `NSWindow Frame settings`，跑完仍在 —— 链条工作正常，但没有在最危险的输入上考验过它 |
| DMG 的窗口布局与拖入体验 | create-dmg 降级路只做 `hdiutil create` | 用户拖 DMG 装进去的完整体验（布局、图标位置、Applications 快捷方式）**从未跑过 create-dmg 主路** |

### 假定依赖

| 项 | 假定内容 | 未验证之处 |
|---|---|---|
| `sfltool dumpbtm` 读得到本 app 的 BTM 记录 | 假定读得到 | 本机两次调用都超时/不可用（`SYS01_BTM_AFTER_AVAILABLE=0`、`UNINSTALL_BTM_AFTER_AVAILABLE=0`），BTM 计数恒记 0。**「读到 0」与「读不到」在本 Phase 无法区分** —— 两处都打了独立的可用性行，不把不可用粉饰成 0 |
| ad-hoc 签名在分发场景下的 Gatekeeper 行为 | 本机自用不触发 | 经浏览器/AirDrop 外传时首次打开会有「无法验证开发者」提示。**已接受**：自用产品不签名不公证（用户拍板） |
| UDIF 容器的不可复现性是稳定的 | 假定它**不可复现** | 已定位到「不在 .app 内容层」，但**未定位到 UDIF 容器内具体哪几个字节在变** |

## 判据纪律备注

- **`no()` 文案带 `ok()` 的同一句判据名**（逐字相同，D-14）：Phase 7 段沿用既有写法，
  红绿靠 ✅ / ❌ 前缀区分。下游在红日志里按 `❌ <判据名>` 定位。
- **二进制符号计数一律 `grep -cE`** —— 裸 `grep` 的 `|` 是字面量，恒 0 假绿灯
  （07-01 立的成对判据，本 Phase 沿用：交付产物 == 0 **且** PicProbe ≥ 1）。
- **`PIC_ROT_ADVANCES_TOTAL` 判据数长 token**。短 token `PIC_ROT_ADVANCES` 是它的**前缀**：
  将来任何人要数「菜单手动 next 打点」那条线，**必须**写成带等号的 `'PIC_ROT_ADVANCES=\('`，
  裸 token 会被退出快照那行 +1。
- **干净 clone 纪律**：无 `build/` 与无 evidence 的判据走 **skip 不走红**，
  `test.sh` 在没打过包的机器上退出码仍是 0。
- **变量名会跨段打架（本段实际踩到）**：spctl 那条判据最初把退出码存进 `SRC`，
  而 `test.sh:30` 的 `SRC` 是**渲染段的源文件清单** —— 覆盖它之后「设置窗渲染」编译了一个
  空列表，恒红。这条判据离自己两百行外，且失败现场指向的是另一段（不是新加的那段），
  排查成本远高于收益。**本段新增变量一律带 `P7` 前缀**（`P7APP` / `P7PROBE` / `P7RES` /
  `SPCTL_RC`），与既有段的 `SRC` / `RES` / `MENU` 等短名彻底分开。

## 与 test.sh 的关系

Phase 7 段共 **8 条判据**：产物形态 5 条（零探针成对判据 ×2、spctl rc=3、图标两项）+
evidence 关键行 6 条 + 7 天长跑 1 条（skip 分支）。

- **不重跑任何探针**，只读 Phase 7 自己已入库的 evidence（照 Phase 4 的 `p4_line` 纪律）。
- **不复用** Phase 3 的 probe 读法 —— 那个 helper 把 evidence 路径硬编码在 Phase 3 的目录下，
  读不到 Phase 7 的目录，复用会假红。本段另起 `p7_line`。
- **零 ffmpeg 进程调用**，与 Phase 6 的红线段同一条纪律。

## 交给用户/下一阶段必须处理什么

**阻塞级**

1. **7 天人工周期** —— 按 `UAT-SOAK.md` 跑满：`bash scripts/soak-agent.sh start`，
   期间正常使用（含日常锁屏睡眠），结束后 `soak-agent.sh stop` + `soak-analyze.sh`，
   结果抄进 `evidence/soak/FINAL.md`。**这是 SC5 唯一的解锁路径。**
2. **人工轮次（约 40 分钟，分散到 7 天里做完）** —— 20 轮锁屏/解锁、20 轮休眠/唤醒、
   电池让路一次、深浅色各看一眼、**图标并排肉眼比对**（ASSET-03 的唯一判据）、
   重启自启确认（SC3，07-02 的 user_setup 项）。
3. **`create-dmg` 的「自动化 → Finder」授权** —— 一次性人工动作，授了 SC1 才能写 PASS。

**不阻塞但别忘**

4. **Phase 6 的四项人工项**（画质 bench / 转码窗目视 / 入口置灰 / 听音）仍未解除，
   SC#3 在 VERDICT 里至今是 PARTIAL。
5. **`fixtures/` 不在 git 里** —— 新 clone 或新 worktree 上，跑任何需要 fixture 的脚本前
   先 `bash scripts/make-fixtures.sh`（会调 ffmpeg，属手动路径）。

## 复现命令

```bash
bash build.sh                              # → build/Pic.app + PicProbe.app + dist/*.dmg
bash scripts/stress-rotation.sh            # → evidence/stress-rotation.log（约 100 秒）
bash scripts/verify-packaging.sh           # → evidence/packaging.log（两遍构建，约 10 分钟）
bash scripts/verify-uninstall.sh           # → evidence/uninstall.log（会短暂删改偏好域，自动恢复）
bash test.sh                               # 通过 102 失败 0 跳过 1
# 7 天长跑（人工周期，见 UAT-SOAK.md）
bash scripts/soak-agent.sh start
# … 7 天 …
bash scripts/soak-agent.sh stop && bash scripts/soak-analyze.sh .planning/phases/07-delivery/evidence/soak/soak.log
```

---
*Phase: 07-delivery*
*本文件为 Phase 7 的唯一判定文件*