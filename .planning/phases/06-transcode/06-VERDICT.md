# Phase 6 判定：转码

**本文件是 Phase 6 的唯一判定文件。Phase 7 只引用它**，不回翻五份 SUMMARY 与 git log。
判据输入来自 `.planning/phases/06-transcode/evidence/transcode-tracer.log`、`swift test` 汇总与
`test.sh` 输出，不从 SUMMARY 转述。

🔴 **ffmpeg 红线先行声明**：本 Phase 的**全部自动路径零 ffmpeg 进程调用**。
`test.sh` 的「Phase6 红线 test.sh 零 ffmpeg 调用与零 bench 引用」用**拆串构造**
（模式在文件里以 `"a""b"` 两段字面存在）做自匹配防线，剥注释后 bench 引用与编码形态调用各为 0。
唯一会真跑 ffmpeg 的是 `scripts/transcode-bench.sh`（MANUAL ONLY、`-t 5 -threads 2`），
**本 Phase 执行期从未运行**（一次 libvmaf 实测跑出过 779.9% CPU，用户红线）。

## 5 条 Success Criteria 逐条结论

判据原文见 `.planning/ROADMAP.md` Phase 6 Success Criteria。结论列只有
`PASS` / `PARTIAL` / `BLOCKED(manual)` 三种，每行挂真实证据路径与数字。

| SC | 结论 | 证据（文件:字段 / 判据名） | 数字 |
|---|---|---|---|
| SC#1 检测 ffmpeg 存在性；不可用时入口置灰并给出安装途径 | PASS（自动面）/ 待人工（行为面） | 自动：`ExternalToolLocatorTests` + `FFmpegAvailabilityTests` 共 6 条（06-04 收编）；`test.sh` 的「安装说明含静态二进制的去隔离命令」「安装说明含 Homebrew 途径」。**行为面未做**：见「人工清单」①② | 6 tests, 0 failures；三途径标记 `pathway:brew/static/source` 各 1 处 |
| SC#2 队列串行执行 + 进度实时刷新 + 命令可审计展示 | PASS（自动面）/ 待人工（行为面） | `TranscodeQueueTests` 6 条（单列门）；`TranscodeMainActorFreezeTests` 1 条（主 actor 冻结回归门，判据 = run 未返回时 percent 已送达，**修此 BLOCKER 前实测 0 / 修后 130~170**）；`transcode-tracer.log:PIC_TRC_RUNNER_CALLS_TOTAL=1`；`TranscodeCommandTests` 的 argv 与审计串断言 | 队列 6 tests；freeze 门 run 期间进度 **>1**（实测 137）；runner 全程调用 **1** 次（证明不重复烤机）；`PIC_TRC_JOB_STATE=succeeded` |
| SC#3 视觉无损（人眼基本看不出差异） | **PARTIAL** —— 参数侧 PASS，画质侧 **BLOCKED(manual)** | 参数侧：`TranscodeCommandTests` 锁死 argv 形状 + 基线 CRF 18 / preset medium；`PIC_TRC_ARGV_TOKENS=28`。画质侧：`scripts/transcode-bench.sh` 的 SSIM/VMAF 实测**从未运行** | argv 28 token；**SSIM/VMAF 无数值** —— 阈值 SSIM≥0.98 / VMAF≥95 是行业经验值 `[ASSUMED]`，非本机实测 |
| SC#4 产物落壁纸目录内（原视频保留不删） | PASS | `testSuccessfulJobRenamesTmpToMp4AndKeepsSource`；`transcode-tracer.log:PIC_TRC_SOURCE_INTACT=1` `:PIC_TRC_TMP_GONE=1` `:PIC_TRC_PRODUCT_EXISTS=1` | 源完好 1 / tmp 已清 1 / 产物存在 1 |
| SC#5 不回流（产物不重进转码队列）+ 不污染播放源 + 转完即播 | PASS（数据侧 + 装配侧）/ 画面侧待人工 | 数据侧：`transcode-tracer.log:PIC_TRC_REFILTER_CANDIDATES=0` `:PIC_TRC_CONVERTED_PLAYABLE=1` `:PIC_TRC_SECOND_PASS_SKIPPED=1`；装配侧：`AppDelegate.mergedPlaybackItems` / `onBatchFinished` / `invalidateCache` 三条 test.sh 门；D-23 见 `W-2026-10-03-34` | 候选集回流 **0**；产物可播 **1**；二次批次跳过 **1**；runner 总调用 **1** |

**SC#3 不写 `PASS`。** 参数构造正确不等于画质达标 —— 「人眼基本看不出差异」这句话在
本 Phase **没有被任何读数证明过**，bench 真跑与 CRF/preset 终值采纳都是人工动作（见「人工清单」③）。

## GPL Blocker 关闭声明

STATE.md 的「GPL v3.0 自用义务边界【待验证】」**就此关闭**。

- GPLv3 §0 与 §2 的义务只在「 conveying a verbatim copy of the Program」时触发；本项目**不复制、
  不修改、不分发任何 GPL 程序的源码**，只以 `Process` 调起用户自己装的 ffmpeg 可执行文件。
- FSF FAQ 对 separate works 的口径：把另一个程序作为**独立进程**调用、数据经管道/文件边界交换，
  不构成衍生作品，聚合器的许可证不传染到被调用的程序。
- 「不分发 GPL 二进制」由 C2 锁定：App 不内置、不下载 ffmpeg；DMG 里也没有它。
- **结论**：自用 + 子进程架构下零义务。保留的不确定性只有一条 —— 若将来把 ffmpeg 静态二进制
  **打包进 DMG**，本条立即失效，须重新评估。

## 人工清单（不阻塞，共约 5 分钟）

以下四项**没有任何自动读数**，逐字保留为人工项，不得记作 PASS：

1. **开转码窗目视**：打开转码窗，看徽章文案、队列条目与命令展示是否成行（结构有断言，屏上像素无）。
2. **入口置灰 + 三途径弹层**：临时 `mv /opt/homebrew/bin/ffmpeg{,.bak}` → 打开设置窗维护行
   应弹出三途径安装说明 → 复原后**重查**徽章应回到「可用」。**验完必须复原并重查**。
3. **跑 bench 决定 CRF/preset 终值**：`bash scripts/transcode-bench.sh`。
   **跑前先确认 CPU 占用**（STATE.md 规则）。结束后按 `BENCH_RECOMMEND` 决定是否改
   `Sources/PicCore/Transcode/TranscodeCommand.swift` 的 `baselineCRF` / `baselinePreset`，
   改了必须同 commit 更新 `TranscodeCommandTests` 测试 3。
4. **核对 videotoolbox 可用性（不转码不烤机）**：`ffmpeg -h encoder=h264_videotoolbox`
   人工确认 A3 的假定。

## A1–A9 假定状态

| # | 假定 | 状态 | 依据 |
|---|---|---|---|
| A1 | CRF 18 是视觉无损的行业共识起点 | 已证（参数侧） | `TranscodeCommand.baselineCRF = 18` 写入常量并被单测锁死；**画质侧未证**，见 SC#3 |
| A2 | SSIM≥0.98 / VMAF≥95 是「视觉无损」经验阈值 | **待人工** | bench 脚本里是可调变量（`SSIM_MIN` / `VMAF_MIN`），本 Phase 未跑过 |
| A3 | VideoToolbox 可用 | **待人工** | 人工清单④；未选它做默认（Q2 选定 libx264，CRF 精确） |
| A4 | map/tmp/pipe/µs 四项 ffmpeg 行为 | 部分已证 | map/tmp/pipe 由 06-03 桩测 + `PIC_TRC_*` 证实；**µs 终值**由 bench 的 `BENCH_PROGRESS_RAW` 核对项收尾（未跑） |
| A5 | GUI app 拿 launchd 最小 PATH，`which` 会漏 | 已证 | 06-02 `ExternalToolLocatorTests` 的 PATH 扫描用例 |
| A6 | 视频壁纸目录约 484 文件 / 42GB | 已证 | `04-CONTEXT.md` D-22；bench 脚本据此只做一层 `ls -1 \| head -n 3` |
| A7 | 单个视频 5 秒段可在可接受时间内转完 | **待人工** | bench 的 `-t 5 -threads 2` 矩阵未跑 |
| A8 | arm64 原生静态 ffmpeg 可获得 | 纯记录 | 不阻塞本 Phase；本机现役是 x86_64 经 Rosetta，bench 已就此打 `BENCH_TIME_NOTE rosetta=…` |
| A9 | `-nostats -progress pipe:1` 的输出格式稳定 | 部分已证 | `ProgressParser` 单测覆盖解析；真机输出未采（转码红线） |

## 没跑过 / 未验证（不得混淆）

- **没跑过**：bench 全流程（18 次 5 秒编码 + SSIM/VMAF 度量）、任何真实转码、
  转码窗的活体目视、入口置灰的活体行为、videotoolbox 探测。
- **跑过**：`swift build`（RC=0）、`swift test` 全量（190 tests, 2 skipped, 0 failures）、
  `bash test.sh` 全量（**通过 79 / 失败 0 / 跳过 5**，含本 Phase 新增 16 条门）、
  `06-03` 的 tracer 探针（`PIC_TRC_*` 15 行，已入库，本 Phase **只读不重跑**）。
- **应该能跑但未测**：bench 脚本本身只过了 `bash -n` 与 token 计数门；真跑路径（ffmpeg 调用、
  SSIM/VMAF 解析、BENCH_RECOMMEND 的 awk 判定）一行都没执行过。
- **假定的依赖**：系统已装 ffmpeg（本机 `/opt/homebrew/bin/ffmpeg`，x86_64 经 Rosetta）。
  缺失时入口置灰降级，Phase 6 不因此失效。

## 与 test.sh 的关系

Phase 6 段共 **16 条门**，全部是纯逻辑判据（分层计数 + 装配计数 + 单测数 + 已入库 evidence 只读 +
红线拆串门）。**零 ffmpeg 进程调用**，由「Phase6 红线 test.sh 零 ffmpeg 调用与零 bench 引用」自锁。
判据写法照 D-14：`no()` 文案带 `ok()` 的同一句判据名，红绿靠 ✅ / ❌ 前缀。