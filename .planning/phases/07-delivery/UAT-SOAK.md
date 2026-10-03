# UAT-SOAK —— SC5 长跑验收人工清单

7 天在位是**人工周期**：采样器只能被动记录，机器得在、app 得开着、不主动重启。
本清单是执行者的一页纸；命令全部可直接复制。

---

## 前置

```bash
bash build.sh
# 从 dist/Pic-0.1.0.dmg 把 Pic.app 装到 /Applications 并启动
# （SC5 的判据锚 DMG 装出的 .app，不是开发期 build 的产物 —— 每次 build 签名都漂移）

bash scripts/soak-agent.sh start
launchctl print gui/$(id -u)/com.local.pic.soak > /dev/null; echo $?   # 必须是 0
```

`start` 不带第二参数 = 数据落 `.planning/phases/07-delivery/evidence/soak/soak.log`（默认值）。

## 7 天规则

- 不退出 Pic，不主动重启机器，正常使用（含日常锁屏睡眠 —— 采样器被动记录跃迁）
- **期间不要同时跑第二个 Pic 进程**（开发期另开一个 build、或手开一个都算）：
  `pgrep -x Pic` 取第一个，采错对象的话 7 天序列对着另一个进程
- 人工轮次不要挤在同一天末尾做完 —— 分散到 7 天里，跨睡眠/唤醒的跃迁才有代表性

## 人工轮次（一次做完约 40 分钟）

| 轮次 | 动作 | 记录什么 |
|---|---|---|
| 20 轮锁屏/解锁 | 每轮 `⌃⌘Q` 之外用 `Ctrl+↑` 锁屏 / `Fn` 或任意键解锁 | 解锁后壁纸在播、无黑屏灰屏（pass/fail + 肉眼结论） |
| 20 轮休眠/唤醒 | 主动休眠用 `pmset sleepnow`，**唤醒必须真人**（开盖/按键） | 同上（pass/fail + 肉眼结论） |
| 电池让路 1 次 | 设置里拨开「电池供电时暂停」→ 拔电源 → 壁纸让路 → 插回 → 续播 → 拨回 | 让路与续播各 pass/fail |
| 深浅色各 1 次 | 系统切深色 / 浅色，各看一眼菜单栏图标 | v1 单窗+三角，两态均清晰可辨 |
| 图标并排肉眼比对 | app 图标与菜单栏图标**并排**看是不是「一眼同一个 app」 | pass/fail + 一句结论（ASSET-03 的真判据 —— 07-01 明确不设自动门，判据只落在这里） |
| 重启自启确认 | 07-02 的 user_setup 项：安装版拨开自启 → 重启 → 确认自启在位 | 结果补记 `evidence/sys01.log`（两项人工项一起做，只重启一次机器） |

## 预期读数（结束时对照）

```
WAKES_DELTA   >= 20
SLEEPS_DELTA  >= 20
CRASH_DELTA   == 0
SOAK_VERDICT  == pass
```

## 结束动作

```bash
bash scripts/soak-agent.sh stop
bash scripts/soak-analyze.sh .planning/phases/07-delivery/evidence/soak/soak.log
```

把全部 `SOAK_*` 行与人工轮次结果（每项 pass/fail + 肉眼结论）抄进
`.planning/phases/07-delivery/evidence/soak/FINAL.md`。

## 异常处置

**`SOAK_VERDICT=invalid`（缺口 >5%）** —— 采样器自身不可信。修完后**重跑整个 7 天**，
不许拿残缺数据下结论。7 天采样器不是回归门禁：缺口超标就作废，不降级继续。

**`alive` 连续为 0 —— 先查采样器自己，再谈壁纸。** ⚠️ 顺序纪律：

`screencapture` 需要**屏幕录制**授权，而 launchd 拉起的进程**不继承终端会话的 TCC 授权**
（授权按调用方/会话记录，不是按用户）。症状是 `alive=0` 连续出现但壁纸肉眼完全正常。

1. 先在**同一 LaunchAgent 环境**下手工复现：
   `launchctl asuser $UID /bin/bash scripts/soak-sampler.sh`
2. 确认是授权问题后按授权问题处理（经一个已授权的中间层，或改用不依赖屏幕录制 TCC 的活性判据）
3. **只有排除了采样器侧原因**，才把 `alive=0` 当成壁纸故障报给主会话

反过来做 = 把工具缺陷当成产品缺陷上报，还白跑 7 天。
（`locked=1` 时的 `alive=0` 是预期，交给分析器区分，不走上面这条。）

**肉眼发现黑屏/灰屏/壁纸消失** —— 记录时间点与 soak.log 对应行，交回主会话。

---

## 两处诚实边界

- **功耗不在判据**：`powermetrics` 需 sudo，不可无人值守（RESEARCH 5.1）；
  用 `pmset -g batt` 记录供电状态，仅作参考读数
- **「看不出壁纸在播视频」是肉眼项不是仪器项**：`alive` 只能证明画面在变，
  证明不了「像不像壁纸」—— 后者只能靠上表的人工轮次