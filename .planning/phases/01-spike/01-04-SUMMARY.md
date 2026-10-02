---
phase: 01-spike
plan: 04
subsystem: spike
tags: [avfoundation, avqueueplayer, avplayerlooper, powermetrics, darwin-notification, cgsession, screenlock, isopaque, spike, throwaway, macos-27]

requires:
  - phase: 01-spike/01-01
    provides: WallpaperSpike 的窗口骨架 + 帧号叠加 + 层级写定案；WindowProbe 按 PID 认领窗口；run-gate.sh 的证据采集形态
provides:
  - WallpaperSpike 补齐 D-07 的四组播放模式（none / v1 / transparent / avplayerview）+ --video 参数 + PIC_ABORT 显式失败
  - LockProbe.swift —— com.apple.screenIsLocked / com.apple.screenIsUnlocked 分布式通知监听 + CGSession 心跳
  - powermetrics_ab.sh —— 四组 A/B 驱动，支持 --dry-run / --parse-selftest（两者都不需要 root）
  - out/ab-verdict.txt —— 终态 C：AB_STATUS=skipped reason=human_checkpoint_not_run / SCREENLOCK=unknown / OPAQUE_DELTA=SKIPPED=human_checkpoint
  - **ARCHITECTURE §12.1「锁屏通知失效则降级方案未找到公开资料」被本 plan 部分证伪** —— CGSession 字典里有两个公开的锁屏键（见「Plan 断言纠错」）
  - **实测发现：本机屏幕当前处于锁屏状态**（loginwindow 在跑、CGSSessionScreenIsLocked=1、已锁约 110 分钟）
affects: [03-全屏几何spike, 05-verdict, phase-3-播放内核, phase-2-产品代码骨架]

actuals:
  tokens: 6315
  tasks: 4
  commits: 4

# commits is MEASURED: git rev-list --count a20bd69..HEAD after this plan.
# 3 task commits + 1 docs commit carrying this SUMMARY.
# plan_head_after is deliberately omitted: a summary cannot contain the hash of
# the commit that contains it. Resolve it with the commit subject
# "docs(01-04): ..." instead.
commits: 4
plan_head_before: a20bd69a45efdb00234ae8b60534c9b0fb7d4b6c

tech-stack:
  added: []
  patterns:
    - "视频资产统一按 url.path 校验存在性（Pitfall 5），绝不喂 absoluteString"
    - "AVQueuePlayer + AVPlayerLooper，audioTimePitchAlgorithm / preferredForwardBufferDuration 都设在 AVPlayerItem 上"
    - "未文档化通知用 Darwin 通知中心 + 每个通知一个 C trampoline，回调里不碰 CFNotificationName 与 Swift String 的桥接"
    - "「探针起来了」与「通知来了」分两个日志文件承载，行数类判据才不会被重跑污染"
    - "sudo 采集脚本的安全形状：脚本自身普通用户运行，只对单条采集命令加 sudo，绝不 sudo bash 本脚本"

key-files:
  created:
    - .planning/spike/LockProbe.swift
    - .planning/spike/powermetrics_ab.sh
  modified:
    - .planning/spike/WallpaperSpike.swift

key-decisions:
  - "color 模式（Plan 01 的纯动画基线）不引入视频依赖，video=none hasVideoTrack=0 如实上报，不谎称校验过视频轨"
  - "none 组不挂 CADisplayLink，Pic_GATE 改由 main 打印一次 —— 让「恰好一次」与「hasVideoTrack 必须是已校验事实」两条同时成立"
  - "锁屏探针 120 秒真跑了但 SCREENLOCK=unknown：屏幕全程已锁且不许由我触发锁屏，无从制造跃迁，unknown 是唯一诚实取值"
  - "顺带实测到公开 API 层面的锁屏状态源（CGSSessionScreenIsLocked），写进 ab-verdict.txt 供 Phase 3 降级决策"

patterns-established:
  - "证据文件一律 KEY=VALUE，禁形容词；AB_STATUS=skipped reason=human_checkpoint_not_run 是与 Plan 05 的字面契约，一个字都不改写，补充说明另起行"
  - "shell 变量名先验一遍是不是 shell 特殊变量（bash 的 GROUPS 是当前用户的 gid 列表，赋值会被静默顶掉）"
  - "BSD sed 不支持 \\b，跨平台改写一律走 python re"

requirements-completed: []

coverage:
  - id: D1
    description: "WallpaperSpike 补齐四组播放模式，--mode v1 实测有真实视频轨在播"
    verification:
      - kind: integration
        ref: "out/ab-v1-stdout.txt → PIC_GATE level=-2147483623 pid=80762 mode=v1 video=002DE018-90F6-4867-81B7-A8E64DC9BCCA.mp4 hasVideoTrack=1（恰好 1 行）"
        status: pass
      - kind: integration
        ref: "out/task1-selftest.log → SOURCE_AVQueuePlayer=4 SOURCE_AVPlayerLooper=2 SOURCE_timeDomain=0 SOURCE_absoluteString=0 SOURCE_hardcoded_-21474836=0 SOURCE_desktopIconWindow=0 SOURCE_CGWindowLevelForKey_desktopWindow=1"
        status: pass
      - kind: integration
        ref: "--mode v1 --video /tmp/does-not-exist.mp4 → RC=2 / PIC_ABORT=video_missing:/tmp/does-not-exist.mp4"
        status: pass
    human_judgment: false
  - id: D2
    description: "D-06 帧号在三种播放模式下持续递增（画面在动的客观信号）"
    verification:
      - kind: integration
        ref: "out/ab-v1-stderr.txt → TICK 147 行、frame 1..147 全不重复；transparent 118 tick / avplayerview 117 tick；none 组 0 tick（按设计不跑动画）"
        status: pass
    human_judgment: false
  - id: D3
    description: "LockProbe 管道自测：--seconds 5 恰好 7 行，且不写 lock.log"
    verification:
      - kind: integration
        ref: "out/task2-selftest.log → SELFTEST_TOTAL_LINES=7 probe_start=1 session=5 lock=0 done=1 bad_prefix=0 lock_log_written=no"
        status: pass
    human_judgment: false
  - id: D4
    description: "powermetrics_ab.sh --dry-run 自检：四组命令可核对、不碰 sudo、无副作用"
    verification:
      - kind: integration
        ref: "out/task3-selftest.log → DRYRUN_LINES=4 GROUP_ORDER=none,v1,transparent,avplayerview HAS_GROUP_COUNT_4=1 HAS_SECONDS_300=1 SRC_POWERMETRICS_LEFT_OF_PIPE=0 SRC_SUDO_V=3 SRC_TRAP=1 JSON_CREATED_BY_DRYRUN=no"
        status: pass
    human_judgment: false
  - id: D5
    description: "A/B 脚本的解析与 JSON 组装路径（不依赖 root 的 harness 验证）"
    verification:
      - kind: integration
        ref: "隔离 /tmp harness：CPU(1000,1004,1008,1012) → CPU_MW_AVG=1006.000；JSON 解析为 4 元素且组序正确；把 EXPECTED_LEVEL 改成 -12345 后四组全部标 invalid=spike_window_missing（合成数字，已丢弃，未写入任何证据文件）"
        status: pass
    human_judgment: false
  - id: D6
    description: "四组 300 秒 powermetrics A/B 的 mW 数字（ROADMAP SC 5 后半）"
    verification: []
    human_judgment: true
    rationale: "本机 sudo 无免密，powermetrics 无 sudo 直接以 exit 1 拒绝（out/ab-blocker-evidence.txt）。这是根本不能跑，不是精度不够的降级，人不在场时无人能提供密码。按「无法解决的跳过」原则记为 AB_STATUS=skipped reason=human_checkpoint_not_run，不伪造任何 mW 数字。"
  - id: D7
    description: "com.apple.screenIsLocked 是否触发的三选一结论（ROADMAP SC 5 前半）"
    verification:
      - kind: integration
        ref: "out/lock.log → 122 行 = probe|start| 1 + session| 120 + LOCKPROBE_DONE events=0 locked=0 seconds=120；SCREENLOCK=unknown"
        status: pass
    human_judgment: false
    rationale: "探针确实跑满 120 秒且探针存在性证据成立；无跃迁可观察（屏幕全程已锁，且不得由执行者触发锁屏），故结论只能是 unknown，不写 fires 也不写 silent。"

duration: 22min
completed: 2026-10-03
status: complete
---

# Phase 01 Plan 04: 桌面层级门禁 04（播放性能 / 锁屏通知）— Summary

**四组播放配置全部可跑且帧号在动；锁屏通知跑了 120 秒但**无跃迁可观察**，结论诚实落在 `SCREENLOCK=unknown`；A/B 的 mW 数字因本机无免密 sudo **如实标为 skipped 而非编造**；顺带实测到 ARCHITECTURE 说「不存在」的公开锁屏状态源。**

## Performance

- **Duration:** 22 min
- **Tasks:** 4/4（Task 4 走终态 C 半跳过）
- **Commits:** 4 (3 task commits + 1 docs commit carrying this SUMMARY)
- **人工 checkpoint 耗时：** 0（无人值守）

## 终态：C（半跳过）

`.planning/spike/out/ab-verdict.txt` 的三行判定：

```
AB_STATUS=skipped reason=human_checkpoint_not_run
SCREENLOCK=unknown
OPAQUE_DELTA=SKIPPED=human_checkpoint
```

- `reason=` 保持兜底串**原样**，一个字未改（Plan 05 的 `SC5-注：` 按字面量引用它）。
- `SCREENLOCK=unknown` 是**跑出来的**结论，不是默认值：`lock.log` 存在，122 行，探针存在性证据成立。
- 四组 A/B 一个都没量到 → `powermetrics-ab.json` **未创建**，`pow-*.raw` **一个都没有**。

## 决定性证据：为什么 A/B 跑不了

`out/ab-blocker-evidence.txt`：

```
sudo -n true            → rc=1, "sudo: a password is required"
powermetrics ... (无 sudo) → rc=1, "powermetrics must be invoked as the superuser"
```

这不是「权限不够、降级代理凑合一下」，是**根本不能跑**。按不阻塞原则如实标 skipped，`powermetrics-ab.json` 宁可不建也不伪造。

## 本 plan 的最大收获：ARCHITECTURE §12.1 被部分证伪

ARCHITECTURE 与本 plan 的 action 都写死「`CGSessionCopyCurrentDictionary()` **只有 5 个键、没有锁屏键**」。**实测 14 个键，其中两个就是锁屏状态**（`out/cgsession-keys.txt`）：

```
KEY CGSSessionScreenIsLocked     type=__NSCFBoolean value=1
KEY CGSSessionScreenLockedTime   type=__NSCFNumber  value=1790961977
```

而且这个值在本机是**活的、可当状态源用**：40 秒 9 次采样全部返回 `1`（`out/session-lockvalue.log`）。

**含义**：ARCHITECTURE §12.1 写的「该通知若失效，真正的降级方案未找到公开资料」需要改写 —— 至少在 macOS 27 上，`CGSessionScreenIsLocked` 是一个走公开 API 的候选降级路径。这条直接降低 Phase 3 暂停仲裁的风险。**注意**：本 plan 只验证了它能**读出状态**，没有验证它在锁屏跃迁时**会翻转**（那需要一次真实锁屏），所以它是候选，不是已证实的降级方案。

## 顺带实测：屏幕当前就是锁着的

```
CGSSessionScreenIsLocked = 1
CGSSessionScreenLockedTime = 1790961977 → 2026-10-02T17:26:17Z（探针开始前约 110 分钟）
独立佐证：loginwindow 进程在跑（pid 489，与 kCGSSessionSecureInputPID=489 一致）；pmset -g assertions → UserIsActive 0
```

**这正是 `SCREENLOCK=unknown` 的成因**：通知只在跃迁时发，探针的 120 秒里屏幕从头到尾都是锁着的，没有任何跃迁。而制造跃迁就要去锁用户正在用的物理屏幕 —— 编排器明令禁止。`unknown` 是唯一诚实的取值，写 `silent` 会是凭空指控一个未文档化通知「已失效」。

## 各任务实测数字

### Task 1 — WallpaperSpike 四组播放模式（`out/task1-selftest.log`）

```
COMPILE_RC=0 errors=0
MODE_v1_GATE=PIC_GATE level=-2147483623 pid=80762 mode=v1 video=002DE018-90F6-4867-81B7-A8E64DC9BCCA.mp4 hasVideoTrack=1（恰好 1 行）
MODE_v1_TICKS=147 FRAMES_DISTINCT=147 FIRST=frame=1 LAST=frame=147
MODE_NONE_TICKS=0（按设计不跑动画，用于隔离解码耗电与动画耗电）
MODE_TRANSPARENT_TICKS=118   MODE_AVPLAYERVIEW_TICKS=117
四组 WindowProbe SELF_LEVEL 全为 -2147483623，ORDER=ok
ABORT_missing_rc=2 / ABORT_notrack_rc=2 / ABORT_badmode_rc=3
```

源码计数判据（Plan 01 的三条 + 本 plan 的三条）全部保持：

```
SOURCE_AVQueuePlayer=4  SOURCE_AVPlayerLooper=2  SOURCE_spectral=1
SOURCE_timeDomain=0  SOURCE_absoluteString=0
SOURCE_hardcoded_-21474836=0  SOURCE_desktopIconWindow=0  SOURCE_CGWindowLevelForKey_desktopWindow=1
```

### Task 2 — LockProbe 管道自测（`out/task2-selftest.log`）

```
SELFTEST_TOTAL_LINES=7  probe_start=1  session=5  lock=0  done=1  bad_prefix=0
SELFTEST_wrote_lock_log=no（lock.log 留给 120 秒真实跑）
```

### Task 3 — powermetrics_ab.sh dry-run（`out/task3-selftest.log`）

```
DRYRUN_LINES=4  GROUP_ORDER=none,v1,transparent,avplayerview
HAS_GROUP_COUNT_4=1  HAS_SECONDS_300=1
SRC_POWERMETRICS_LEFT_OF_PIPE=0（powermetrics 从不接管道，退出码不丢）
SRC_SUDO_V=3  SRC_TRAP=1
RAW_FILES_BEFORE=0  RAW_FILES_AFTER=0  JSON_CREATED_BY_DRYRUN=no（dry-run 无副作用）
```

## Plan 断言纠错（`PLAN_DEVIATION=`）

四条，全部记录在 `ab-verdict.txt`，数值保留实测值，**没有为了让断言过而改产物**：

| # | plan 里的断言 | 本机实测 | 处置 |
|---|---|---|---|
| 1 | `CGSessionCopyCurrentDictionary()` 只有 5 个键、没有锁屏键 | **14 个键，含 `CGSSessionScreenIsLocked` / `CGSSessionScreenLockedTime`** | 保留实测值；锁屏心跳照写全部键；结论写进本 SUMMARY 供 Phase 3 |
| 2 | `player.preferredForwardBufferDuration = 3.0` | 该属性属于 **`AVPlayerItem`**，`AVQueuePlayer` 上没有这个成员（编译报 `has no member`） | 改设在 item 上 |
| 3 | 用 bash 数组 `GROUPS` 存四组 | **bash 把 `GROUPS` 保留为当前用户的 gid 列表**，赋值被静默顶掉，`--dry-run` 打出 16 组 `group=20/12/61/…` | 改名 `AB_GROUPS` |
| 4 | `color` 模式与四组同规格 | `color` 是 Plan 01 的纯动画基线，若也强制校验视频会让已记录的 D-06 门禁新增对 `~/Movies/视频壁纸/` 的依赖 | `color` 不校验视频，如实打 `video=none hasVideoTrack=0` |

另有两处 grep/正则误报，一并记下（都是**改正则不改数字**）：

- 我第一次统计 `SELFTEST_DONE=0` 是因为 grep 用了 `^LOCKPROBE_DONE events=0 locked=0$`，而产物行尾还有 `seconds=5`。**正则去掉 `$` 后即为 1**，产物未动。
- `GROUP_ORDER` / `MODES_IN_CMD` 第一次统计用 `[a-z]*` 把 `v1` 截成 `v`。**改用 `[a-z0-9]*` 后为 `none,v1,transparent,avplayerview`**，产物未动。

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `GROUPS` 是 bash 保留变量，导致 `--dry-run` 打出 16 组乱码**
- **Found during:** Task 3 自检
- **Issue:** `AB_GROUPS` 前身 `GROUPS=(none v1 transparent avplayerview)` 在 bash 里被解释成「当前用户所属的 16 个 gid」，四组配置整个丢失且**不报错**
- **Fix:** 改名 `AB_GROUPS`
- **Files modified:** `.planning/spike/powermetrics_ab.sh`
- **Commit:** `f19a99c`

**2. [Rule 3 - Blocking] `preferredForwardBufferDuration` 挂在 player 上编译不过**
- **Found during:** Task 1 编译
- **Fix:** 改挂在 `AVPlayerItem` 上（见上表 #2）

**3. [Rule 3 - Blocking] `CFNotificationName` 无法与 Swift `String` 比较**
- **Found during:** Task 2 编译
- **Issue:** 计划要求回调里判名字；macOS 27 SDK 上 `CFNotificationName` 与 `CFString` 是不同类型，`name as String` 不成立
- **Fix:** 两个通知各挂一个专属 trampoline，回调里根本不碰名字 —— 比名字更不可能认错
- **Commit:** `6925c62`

**4. [Rule 1 - Bug] BSD `sed` 不支持 `\b`，`GROUPS` 的批量改名静默无效**
- **Fix:** 改用 `python3 re.sub` 做替换，并核对替换计数

### 已识别但刻意不改的

- `tracks(withMediaType:)` 在 macOS 13 起 deprecated。spike 需要**同步**取视频轨（异步版要引入 semaphore/runloop），保留同步调用；仅 warning，`-o` 编译无 `error:`，不影响任何判据。

## 已知障碍（Plan 05 必须如实写进 VERDICT）

1. **ROADMAP SC 5 后半（isOpaque 的 mW delta）BLOCKED** —— `AB_STATUS=skipped reason=human_checkpoint_not_run`。要解封只需一次真人在场跑 `bash .planning/spike/powermetrics_ab.sh`（约 21 分钟，期间别切 Space / 别最小化 / 别锁屏）。四组命令已在 `--dry-run` 里逐字核对过，跑起来不需要再设计。
2. **ROADMAP SC 5 前半（screenIsLocked 是否触发）= `unknown`** —— 探针跑满 120 秒但无跃迁。要得出 `fires` / `silent`，必须有一次真实的手动锁屏 10 秒再解锁；**不要**在无人值守时重试到出结果为止。
3. **ARCHITECTURE §12.1 需改写** —— 「真正的降级方案未找到公开资料」在 macOS 27 上不再准确，`CGSSessionScreenIsLocked` 是公开 API 的候选降级路径。**但只验证了能读出状态，没验证跃迁时会翻转**，Phase 3 必须实测后者才能写进产品代码。

## 自检

- [x] 四个任务全部执行，Task 4 落在终态 C 且内部自洽
- [x] 每个任务单独提交（`12fc554` / `6925c62` / `f19a99c`）
- [x] `.planning/spike/out/ab-verdict.txt` 存在，三行判定齐备，`SCREENLOCK=` 与 `OPAQUE_DELTA=` 各恰好一行
- [x] `out/lock-selftest.log` 含 `probe|start|` ≥ 1（无条件成立）
- [x] `out/lock.log` 存在且含 `probe|start|` ≥ 1
- [x] `powermetrics-ab.json` 未创建（终态 B/C 的要求）
- [x] plan 的 `<verify>` 逐条命令退出码 0
- [x] STATE.md / ROADMAP.md 未改动
- [x] 无遗留后台进程（spike / lockprobe 全部已收，`trap` 生效）
- [x] 证据文件无形容词，全部 KEY=VALUE
- [x] `cgsession-keys.txt` 已按 T-01-03 脱敏（用户名 / uid / session UUID / audit id 全部 `<redacted>`）

## Self-Check: PASSED