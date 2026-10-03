# Phase 6: 转码与独立窗口 - Research

**Researched:** 2026-10-03
**Domain:** 外部 ffmpeg 子进程转码（mkv/avi/webm → H.264 MP4）+ 许可边界 + 降级策略
**Confidence:** MEDIUM（核心参数与许可结论 HIGH；若干 ffmpeg 细节为推断，见 Assumptions Log）

> 调研边界遵守：未运行任何 ffmpeg/ffprobe/转码命令（本会话一次都没跑）。全部结论来自 web 检索、官方文档、in-repo 已验证事实、二进制头读取（`file`/`ls`，不执行）。

---

## Summary

本 Phase 的架构骨架已被前面的决策锁死：**调系统 PATH 里的 ffmpeg 子进程，不内置不下载，缺了置灰降级**。本轮调研解决的是三件悬而未决的事：① 视觉无损参数基线（→ libx264 CRF 18 + preset medium，最终数值按已拍板的「本机 SSIM/VMAF 实测」流程定）；② GPL v3.0 义务边界（→ **自用零义务，分发 DMG 也无义务，GPL 是本架构下的非问题**，Blocker 解除）；③ 产物命名/防回流细节（→ 不加文件名后缀，纯目录隔离 + MP4 原生双保险足够）。

两个**新发现的硬事实**需要规划时吸收：① 本机 `/opt/homebrew/bin/ffmpeg` 是 **x86_64 静态二进制跑在 arm64 机器上（Rosetta 2 转译）**——软编会转译执行，性能/发热都要打折；② GUI app 从 Finder/DMG 启动时拿到的是 launchd 的最小 PATH（不含 `/opt/homebrew/bin`），**光靠 `which` 检测会漏掉本机已装的这份 ffmpeg**，必须显式探测常见安装路径。

另注意：`STACK.md §3` 推荐的 `AVAssetWriter + VideoToolbox` 系统内转码路线**早于**「调系统 ffmpeg」的拍板决策，已被覆盖为备选记录；但它验证过的 API 事实（`VTIsHardwareDecodeSupported` 门控等）仍然有效。

**Primary recommendation:** `libx264 -preset medium -crf 18 -pix_fmt yuv420p` + 音频统一 AAC 重编码 + 显式 `-map` 防 MKV 附件陷阱；参数最终值走「本机实测」流程（手动、单次、绝不进 test.sh）；GPL 结论写进决策记录，Blocker 关闭。

---

## User Constraints（已拍板，不要在计划里重开）

| # | 约束 | 出处 |
|---|------|------|
| C1 | 转码产物落 `<壁纸目录>/Converted/` 子目录；扫描器排除该目录名（D-21） | 04-CONTEXT D-21 / ROADMAP Notes |
| C2 | 调**系统已装 ffmpeg** 子进程（PATH 检测 + `Process`）；App **不内置、不联网下载** ffmpeg | PROJECT.md Key Decisions / memory |
| C3 | 缺 ffmpeg 时**降级不阻断**：转码入口置灰 + 多条安装途径提示 | PROJECT.md / TRANS-02 |
| C4 | 产物是 MP4（H.264），能硬解，人眼基本看不出差异 | ROADMAP SC#3 |
| C5 | macOS 27 上 `brew install ffmpeg` 会失败（lame/dav1d 无 bottle）；安装提示必须含静态二进制等替代途径 | PROJECT.md / PITFALLS #9(c) 实测 |
| C6 | **ffmpeg/转码类测试绝不进 test.sh / swift test / 任何自动验证路径**；可跑但必须手动单独跑 | PROJECT.md Key Decisions（2026-10-03） |
| C7 | 转码参数（CRF/preset）**本机实测确定**：从 484 个真实样本抽样，SSIM/VMAF 量出视觉无损数值，不依赖二手资料 | PROJECT.md Key Decisions（2026-10-03） |
| C8 | 真实 42GB 目录只采样一次，不做测试用例（D-22） | 04-CONTEXT D-22 |
| C9 | 转码窗口是**全 app 唯一允许出现列表的地方**（任务队列 ≠ 浏览式列表），写进计划防 scope creep | ROADMAP Notes / UI-SPEC §8 |
| C10 | 退出码必须用 `Process.terminationStatus`，**绝不用管道** | ROADMAP Notes / PITFALLS #9(d) |
| C11 | 输出写 `xxx.tmp` 再 rename；先检查剩余空间；转码与播放不抢资源（`nice` 或串行化） | ROADMAP Notes |

---

## Phase Requirements

| ID | 描述 | 研究支撑 |
|----|------|----------|
| TRANS-01 | 检测系统 PATH 中的 ffmpeg | Q7：`which` via Process + 常见路径显式探测（GUI PATH 陷阱） |
| TRANS-02 | 缺失时置灰 + 安装途径提示；其余功能不受影响 | Q5：三条途径（brew+警示 / 静态二进制+quarantine / build-from-source） |
| TRANS-03 | mkv/avi/webm → MP4(H.264) 视觉无损 | Q1/Q2/Q3：编码器、CRF/preset 基线、音轨与容器处理 |
| TRANS-04 | 产物落壁纸目录内，原视频保留 | Q4：命名规则 + 幂等冲突处理 |
| TRANS-05 | 产物不被再次扫成待转码输入 | Q4：目录隔离 + MP4 原生双保险；**语义对齐 Open Question 1** |
| TRANS-06 | 队列/进度/实际命令可审计 | 架构模式：`-progress pipe:1` + 命令展示 |

---

## Q1: 编码器选择 —— H.264（结论：定 H.264，SC 已锁）

**结论：H.264。不是开放选项——ROADMAP SC#3 已写死「转成 MP4（H.264）」，本轮只是确认它是对的。**

- H.264 是 AVFoundation/VideoToolbox 硬解的最保底格式，全线 Mac 无条件支持 `[ASSUMED]`（训练知识，通行事实；探测手段见下）。
- H.265/HEVC 同画质省 ~30-50% 码率 `[ASSUMED]`，但硬解**看设备**（Apple Silicon 全支持；部分 Intel 机型不支持），且**本场景不值得**：自用、非原生格式的存量文件不多（484 个样本全是 mp4），省的那点磁盘换不来兼容性风险。
- 若将来真要 HEVC：入列前用 `VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)`（macOS 10.13+）做能力门控——API 存在性已在 STACK.md 验证 `[VERIFIED: .planning/research/STACK.md:106]`。本 Phase 不做。
- 本机是 arm64（`uname -m` 实测）→ Apple Silicon，HEVC 硬解本身没问题；选 H.264 纯为普适与简单。

## Q2: 视觉无损参数（结论：libx264 CRF 18 / preset medium 起步，终值本机实测定）

**CRF：**
- x264 的 CRF 范围 0–51，**18 被广泛认为是「视觉无损」**（技术上有损，人眼分辨不出）；默认 23；CRF ±6 ≈ 码率/体积减半或加倍 `[CITED: trac.ffmpeg.org/wiki/Encode/H.264]`（注：trac 站点被 Anubis 反爬挡住无法直接抓取，结论经 web 检索多来源一致 + 与官方 wiki 译文吻合；置信 MEDIUM）。数学无损（`-qp 0` / CRF 0）体积大 2-5 倍、编码极慢，PROJECT.md 已明确不采用 `[VERIFIED: .planning/PROJECT.md:63]`。
- **建议基线 CRF 18**；实测流程（C7 已拍板）在 16/18/20 三档 + medium/slow 两 preset 之间量，SSIM/VMAF 达标即取最大 CRF。「视觉无损」的常用工程阈值 SSIM ≥ 0.98 / VMAF ≥ 95 属行业经验值 `[ASSUMED]`（推断，未验证——最终以你本机实测数据为准）。

**preset：**
- preset 只换「同画质下的体积/速度」，不改画质：越慢文件越小。序列 `ultrafast→…→medium(默认)→slow→…→placebo` `[CITED: ffmpeg wiki, web 检索]`。
- 自用、一次性、量小 → **medium 够用**；slow 省约 10-20% 体积但耗时显著增加 `[ASSUMED]`。不建议 veryslow（收益递减）。转码用 CRF 模式时 preset 影响的是码率效率，不是「视觉无损」本身。

**编码器对比：**

| 编码器 | 画质可控性 | 速度 | 结论 |
|--------|-----------|------|------|
| `libx264`（软编） | CRF 精确，视觉无损可达 | 慢（本机还叠加 Rosetta，见下） | ✅ **选定** |
| `libx265`（软编 HEVC） | CRF 可控 | 更慢 | ❌ Q1 已否 |
| `h264_videotoolbox`（硬编） | **质量旋钮语义与 CRF 不等价**（`-qp`/`-q:v`，无真正 constant-quality CRF 模式），PROJECT.md 前期结论「画质控制达不到视觉无损」`[VERIFIED: .planning/PROJECT.md:65]` | 快 | ❌ 主路径不用；留着当「大量文件快速转」的备选 `[ASSUMED]`（web 检索结果混杂，h264_videotoolbox 具体选项**未找到权威公开资料**——执行期可用 `ffmpeg -h encoder=h264_videotoolbox` 人工核对，该命令不转码不烤机） |

**本机硬事实（本轮实测，未执行 ffmpeg）：** `/opt/homebrew/bin/ffmpeg` 存在（80.8MB，2026-10-03 安装），`file` 读头为 **Mach-O x86_64**，而主机是 arm64 → 该二进制经 **Rosetta 2 转译执行** `[VERIFIED: 本会话 ls+file]`。含义：软编全程转译，速度/发热都劣于原生 arm64 构建。与 evermeet.cx「只出 Intel 原生构建」的站方声明吻合 `[VERIFIED: evermeet.cx/ffmpeg 本会话抓取]`。→ 影响不大（自用量小 + 串行），但**实测计时时要意识到这个折损**，别把 Rosetta 下的耗时当成 libx264 的真实速度。arm64 原生静态构建来源见 Q5。

## Q3: 音轨处理（结论：统一重编码 AAC，不用 copy）

- MP4 容器 + AVFoundation 的最稳组合是 **AAC 音频**（Apple 官方推荐配对）`[CITED: web 检索多来源，MEDIUM]`。
- copy 的坑：mkv 里常见的 **AC-3 / DTS / FLAC / Vorbis / Opus** 塞进 MP4 后 AVPlayer 播放不可靠（Opus-in-MP4、FLAC-in-MP4 均非 Apple 生态标准组合；DTS 基本不行）`[CITED: web 检索，MEDIUM；部分为推断]`。`-c:a copy` 遇到 MP4 不收的流时 ffmpeg 会直接报错或产出播不了的文件 `[ASSUMED]`。
- 壁纸场景音频本来就无足轻重（桌面壁纸基本静音播放），**统一 `-c:a aac -b:a 192k` 重编码**——最确定、最少分支、音质足够。想省那一点转码时间去探测「源是否已是 AAC 再 copy」是给确定性买单，不值。
- 无音轨的源：`-map 0:a:0?`（带 `?` 的 optional map）无音轨时不报错 `[ASSUMED]`（训练知识，ffmpeg 标准语义）。
- 字幕/附件：**mkv 内嵌字幕、字体附件、封面图流塞进 mp4 muxer 会报错或产出垃圾**，用显式 `-map 0:v:0 -map 0:a:0? -sn -dn` 只取第一条视频+音频 `[ASSUMED]`（训练知识，经典 mkv→mp4 陷阱）。

## Q4: 产物命名防回流（结论：不加后缀，纯目录隔离够；大小写用精确匹配）

**不需要 `_converted.mp4` 之类的文件名后缀。** 理由：已有两道互相独立的闸门——
1. **目录隔离**（C1/D-21）：产物全在 `Converted/` 里，扫描器排除该目录名；
2. **格式天然免疫**：产物是 MP4 = 原生格式，永远不会进「非原生格式 → 待转码」队列（D-21 原文「双保险」`[VERIFIED: .planning/phases/04-media-library/04-CONTEXT.md:49]`）。

后缀是第三道冗余闸门，只换来：改名逻辑、与源文件对应的映射复杂度、用户在 Converted 里看到难看的文件名。不加。

**命名规则：** 产物名 = 源文件去扩展名 + `.mp4`（`foo.mkv` → `Converted/foo.mp4`）。

**冲突/幂等：** 目标已存在时——若产物 mtime ≥ 源 mtime 则跳过（已转过且源没变），否则加序号或重转。推荐「跳过 + 队列里标 skipped」，最简单且防重复烤机 `[ASSUMED]`（设计建议，非外部事实）。

**大小写：** macOS 默认 APFS 启动卷是**大小写不敏感**的（`Converted` 与 `converted` 是同一个目录）`[ASSUMED]`（通行事实，未本会话验证）。设计上：
- App **永远用字面常量 `"Converted"`（首字母大写）** 创建/写入——保证自家产物路径确定；
- 扫描器排除规则用**精确匹配 `"Converted"`**即可：大小写不敏感卷上天然覆盖各种写法；大小写敏感卷上（罕见、外接盘）用户手建的 `converted` 小写目录里本来就没有我们的产物，不需要排除。
- 不建议排除规则做成大小写不敏感的全局匹配——会把用户碰巧叫 `converted` 的正常视频目录也排除掉（false positive），而防回流只需要拦住**我们自己写的**产物。

**⚠️ 语义对齐（见 Open Question 1）：** SC#5 要求「转完的 MP4 **立即可被壁纸播到**」，而 D-21 说「扫描器排除该目录名」。两者兼容的唯一读法是：**排除只作用于「待转码输入发现」，播放用的白名单扫描仍要扫进 `Converted/` 里的 MP4**。规划时必须与 Phase 4 已实现的扫描器语义核对（当前 executor 在跑，勿扰；规划期核对产物即可）。若 Phase 4 做成了「全排除」，SC#5 就需要「转码完成后单独把产物注入播放列表」的补偿机制——这是一个计划级决策点。

## Q5: ffmpeg 获取方式（结论：三条途径写进提示；App 永不自带）

已拍板 App 不内置不下载（C2），所以「分发给别人」= DMG 里只有 app，**装 ffmpeg 是接收方自己的事，App 只负责把话说清楚**。安装途径（提示文案素材）：

1. **Homebrew**：`brew install ffmpeg` —— 但 macOS 27 会因 `lame`/`dav1d` 无 bottle 失败 `[VERIFIED: .planning/research/PITFALLS.md:240 实测记录]`；变通 `brew install --build-from-source ffmpeg`（慢，全程本地编译）`[CITED: PITFALLS #9]`。
2. **静态二进制（本机实际用的路线）**：evermeet.cx `[VERIFIED: evermeet.cx/ffmpeg 本会话抓取]`：
   - 提供 ffmpeg / ffprobe / ffplay，release 最新 **9.0.2（2026-09-18）**——与本机装的版本吻合 `[VERIFIED: ROADMAP:210 + 本会话站点抓取交叉确认]`；snapshot 跟进到 2026-10-01；
   - 要求 macOS 10.13+；**只出 Intel x86_64 原生构建**，站方明说「不计划提供 Apple Silicon ARM 原生二进制」——ARM 机器上即 Rosetta 转译（本机现状）；
   - 构建含 `--enable-gpl --enable-version3`，链接 libx264/libx265（GPL 二进制，见 Q6——对使用者无义务问题）；
   - **GPG 签名但无公证**：站方明拒 notarization；macOS 10.15+ 首次使用需 `xattr -dr com.apple.quarantine <二进制路径>` 清隔离属性——**提示文案里必须带这条命令**，否则用户解压后双击/调用直接被 Gatekeeper 拦；
   - 下载 API：`https://evermeet.cx/ffmpeg/getrelease/ffmpeg/zip` 等。
   - **arm64 原生构建来源**：站内头部有 ARM 专页链接（指向第三方，本会话未能验证其内容）——常见的是 osxexperts.net 的静态构建 `[ASSUMED]`（**未找到可验证的公开资料**，推断；需要时人工核对该站可信度）。
3. **MacPorts**：`sudo port install ffmpeg` `[ASSUMED]`（推断，未验证 macOS 27 上的可用性——brew 失败不必然代表 MacPorts 失败，但没查到实测资料）。

「自带二进制打进 DMG」路线：**不做**（C2 锁死）。若将来解禁：GPL 义务只落在 ffmpeg 二进制本身（附许可证文本 + 提供对应源码，evermeet 公开源码包），**不会传染 app 本体**（见 Q6）——但体积 +80-150MB 的问题仍在 `[ASSUMED: PROJECT.md 估计，未复核]`。

## Q6: GPL v3.0 义务边界（结论：本架构下 GPL 是非问题，Blocker 可关）

三个场景逐一定性：

**(a) 自用（现在的实际情况）——零义务。**
GPLv3 §2 Basic Permissions 原文 `[VERIFIED: gnu.org/licenses/gpl-3.0.txt 本会话抓取]`：

> "You may make, run and propagate covered works that you do not convey, without conditions so long as your license otherwise remains in force."

「convey」的定义（§0）：使他人能制作或收到副本的传播行为 `[VERIFIED: 同上]`。自己机器上跑 GPL 程序不 convey → 无任何条件约束。**不需要开源、不需要附任何文本。**

**(b) 把 DMG 分发给别人（app 调系统 ffmpeg）——app 本体无 GPL 义务。**
FSF GPL FAQ 及通行法务共识：以**独立子进程**方式调用 GPL 程序、只经标准 IPC（argv/pipe/stdout）通信、不链接不合并代码，两者是 **separate works**，调用方不构成衍生作品，GPL copyleft 不延伸到调用方 `[CITED: gnu.org/licenses/gpl-faq（本会话直接抓取被 429 限流，结论经 web 检索多来源一致佐证，含官方 FAQ 中文版条目「可以在同一台电脑上安装 GPL 程序与非自由程序」）]`。本项目正是这个形态：`Process` exec `ffmpeg`、命令行参数进、退出码出。**app 源码不因调 GPL ffmpeg 而须开源。** 边界提醒（写给未来的自己）：不要把 ffmpeg 静态/动态链接进 app、不要改 ffmpeg 源码后再分发——守住「子进程 + 不改」这条线就永远安全。

**(c) 若把 GPL ffmpeg 二进制打进 DMG 一起分发——义务落在 ffmpeg 那个二进制上，不落在 app 上。**
需：附 GPL v3 文本 + 提供该二进制的对应源码（evermeet 公开）。app 仍是 separate work。**本项目 C2 已锁不做，仅记录。**

**LGPL 路径存在但不需要：** ffmpeg 以 `--disable-gpl` 构建时是 LGPL v2.1+（无 x264/x265/xvid 等 GPL 组件；H.264 编码只剩 `h264_videotoolbox` 硬编或 BSD 许可的 `libopenh264`）`[ASSUMED]`（训练知识；ffmpeg 构建标志语义，未本会话验证）。in-repo 的 `ffmpeg-kit-next` 克隆 LICENSE 头部确认是 **LGPL v3** `[VERIFIED: ffmpeg-kit-next/LICENSE 本会话读取]`——它是「摆脱 PATH 依赖」的记录在案备选（PROJECT.md:74），v1 不用。**结论：自用 + 子进程架构下，走 GPL 构建的 evermeet 二进制没有任何许可成本，无需为 LGPL 折损编码器选择。** STATE.md 的 GPL Blocker 据此关闭。

## Q7: 降级策略（结论：置灰不隐藏；检测 = which + 显式路径探测双管）

- **入口置灰（greyed-out）而非隐藏**——SC#1 原文就是「置灰并给出多条安装途径」`[VERIFIED: .planning/ROADMAP.md:199]`。隐藏让用户以为功能不存在；置灰 + 点击弹说明才是「降级不阻断」的正确表达。置灰态点一下弹出安装途径列表（Q5 的三条），列表里明示 brew 在 macOS 27 会失败（C5）。
- **检测方法**：`Process` 跑 `/usr/bin/which ffmpeg`，看 `terminationStatus == 0`（C10：绝不用管道读退出码）。
- **⚠️ GUI PATH 陷阱（本轮新识别，关键）**：菜单栏 app 从 Finder/DMG 启动时继承的是 **launchd 的最小 PATH**（`/usr/bin:/bin:/usr/sbin:/sbin` 量级），**不含 `/opt/homebrew/bin`** `[ASSUMED]`（macOS 通行行为，训练知识）。而本机 ffmpeg 恰在 `/opt/homebrew/bin/ffmpeg` `[VERIFIED: 本会话 ls]`——**纯 `which` 检测在 GUI 环境下会误报「未安装」**，直接违反「降级不阻断」的初衷。正确做法：`which` 之外**显式探测常见安装路径**：`/opt/homebrew/bin/ffmpeg`（Apple Silicon brew / 本机 evermeet 落点）、`/usr/local/bin/ffmpeg`（Intel brew / 手工安装惯例）`[ASSUMED]`。两者任一存在即视为已安装。
- **检测时机**：app 启动时一次 + 每次打开转码窗口时重查（用户中途装上 ffmpeg 不用重启 app）。检测结果只影响转码入口的可用态，**不触碰播放主链路**（C3）。

---

## Architectural Responsibility Map

| 能力 | 归属层 | 理由 |
|------|--------|------|
| ffmpeg 检测 | App（Process 探测层） | PATH + 常见路径双查；结果只喂 UI 态 |
| 转码执行 | **外部 ffmpeg 子进程** | C2 锁死；App 零转码代码 |
| 队列/进度/命令展示 | App（SwiftUI 独立 Window） | UI-SPEC §8；全 app 唯一列表 |
| 参数构造 | App（纯字符串/纯逻辑） | 唯一可单测的转码逻辑（C6） |
| 产物落盘规则 | App + 扫描器（Phase 4 已定排除语义） | D-21 |
| 播放产物 | AVFoundation（已有播放链路） | 产物=普通 MP4，无特权 |

## Standard Stack

**零第三方依赖不变**（全项目方针）。本 Phase 新增组件全在系统框架内：

| 组件 | 用途 | 说明 |
|------|------|------|
| `Foundation.Process` | exec ffmpeg、`terminationStatus` | 已在 PITFALLS #9(d) 定规矩 |
| `SwiftUI Window` scene | 转码独立窗口 | UI-SPEC §8；宽 ~640 高可调 |
| `ExternalToolLocator`（新，~30 行） | ffmpeg 检测 | which + 显式路径 |
| `TranscodeQueue`（新） | 串行任务队列 + 进度 | 见架构模式 |
| ffmpeg（外部，不打包） | 实际转码 | GPL 构建可用，见 Q6 |

**不装任何包，无 Package Legitimacy Audit 需求。**

## Architecture Patterns

### 转码数据流

```
非原生文件(mkv/avi/webm)
   │ (用户加入队列)
   ▼
TranscodeQueue ──串行,一次一个──> Process(nice) ──exec──> ffmpeg(系统 PATH)
   │                                │                      │
   │                                │<-stdout: -progress──>│ (进度解析)
   │                                │<-terminationStatus──>│ (成败判定,绝不看管道)
   ▼                                ▼
<壁纸目录>/Converted/xxx.tmp ──成功后 rename──> xxx.mp4
                                                        │
                                                        ▼
                                          播放扫描白名单(MP4 原生,立即可播)
                                          待转码发现: 排除 Converted/(防回流)
```

### 可审计命令模板（TRANS-06 直接展示这条）

```bash
# 参数为推荐基线,终值以 C7 本机实测为准
nice -n 10 ffmpeg -nostdin -y \
  -i /abs/path/src.mkv \
  -map 0:v:0 -map 0:a:0? \
  -c:v libx264 -preset medium -crf 18 -pix_fmt yuv420p \
  -c:a aac -b:a 192k \
  -sn -dn -movflags +faststart \
  -progress pipe:1 -nostats \
  /abs/path/wallpapers/Converted/src.mp4.tmp
# 成功(terminationStatus==0)后: rename .tmp -> .mp4
```

要点（逐条对应前面结论）：`-nostdin` 防 ffmpeg 吃掉父进程 stdin `[ASSUMED]`；绝对路径防「文件名长得像选项」被 ffmpeg 误解析（安全节）；`-pix_fmt yuv420p` 防 Hi10P 源产出 Apple 硬解不了的 10bit H.264 `[ASSUMED]`；`-movflags +faststart` 把 moov 挪前，本地播放无所谓但无害 `[ASSUMED]`；进度走 `-progress pipe:1` 的机器可读输出（`out_time_ms`/`frame=`），**读 stdout 管道拿进度没问题，判定成败只认 `terminationStatus`**——C10 禁的是「用管道的退出码」，不是禁读管道 `[ASSUMED]`（训练知识，执行期验证）。

### Anti-Patterns

- **`cmd | tail` 然后看 `$?`**——恒 0，等于没检测（PITFALLS #9(d)，三次事故级别）
- **shell 字符串拼接命令**——文件名带空格/引号/`-` 开头全爆，必须 `Process.arguments` 数组 + 绝对路径
- **转码并发跑**——串行队列锁死；`nice` 兜底（C11，779.9% CPU 烤机事故的防线）
- **把 ffmpeg 调用写进任何自动测试**——C6 铁律
- **纯 `which` 检测**——GUI PATH 陷阱，见 Q7

## Don't Hand-Roll

| 问题 | 别自建 | 用现成的 | 为什么 |
|------|--------|----------|--------|
| 转码本身 | 自研 AVAssetWriter 管线 | 系统 ffmpeg 子进程 | C2 锁死；STACK.md §3 的系统内路线备选记录在案 |
| 进度解析 | 正则啃 stderr 人话输出 | `-progress pipe:1` 结构化输出 | stderr 格式随版本漂 |
| 退出码 | 管道技巧 | `terminationStatus` | 已定论 |
| 队列持久化/断点续传 | — | 不做 | v2 范围（ROADMAP 155 行已推迟） |

## Common Pitfalls

### P1: GUI app 的 PATH 不含 /opt/homebrew/bin
**现象**：终端里 `which ffmpeg` 有，app 里检测不到，转码入口错误置灰。
**根因**：launchd 启动的 GUI 进程 PATH 极小（Q7）。
**避法**：显式路径探测列表。**本机必中此坑**（ffmpeg 就在 /opt/homebrew/bin）。
**预警信号**：用户明明装了 ffmpeg 却看到「未安装」提示。

### P2: Hi10P（10bit H.264）mkv 源
**现象**：转出的 MP4 AVPlayer 硬解失败/掉帧。
**根因**：libx264 跟随源像素格式产出 High 10 profile，Apple H.264 硬解只要 8bit 4:2:0 `[ASSUMED]`。
**避法**：固定 `-pix_fmt yuv420p`。动漫类壁纸源（Hi10P 重灾区）尤其注意。

### P3: MKV 附件/字幕流进 MP4 muxer
**避法**：显式 `-map 0:v:0 -map 0:a:0? -sn -dn`（Q3）。

### P4: Rosetta 转译的性能误判
**现象**：实测 CRF/preset 计时时得出「libx264 慢得离谱」的错误结论。
**根因**：本机 ffmpeg 是 x86_64（Q2 硬事实），全程转译执行。
**避法**：实测报告里注明 Rosetta 折损；数据只用于横向比较（同机同二进制），不当绝对值。

### P5: 产物回流死循环（TRANS-05 本体）
**避法**：双闸门（目录排除 + MP4 原生）+ `.tmp` 中间名不进白名单（C11）。**注意 Open Question 1 的语义对齐**——排除过宽会反过来弄死 SC#5。

### P6: 磁盘写满
**避法**：转码前查目标卷剩余空间 vs 源文件大小（C11；MP4/H.264 产物一般 ≤ 源，按源体积预判即可 `[ASSUMED]`）。

## State of the Art

| 旧 | 新 | 时间 | 影响 |
|----|----|------|------|
| FFmpegKit（进程内） | 已退役（repo archived）；接棒 ffmpeg-kit-next 仅源码分发 | 2026-07 | `[VERIFIED: PITFALLS #9(a) GitHub API 实测]`；本 Phase 无感（走子进程） |
| STACK.md §3 的 AVAssetWriter 系统内转码 | 被拍板决策覆盖为备选 | 2026-10-02/03 | 规划时**不要**按 STACK.md §3 走；其 API 验证成果仍可引用 |

## Assumptions Log（需确认/执行期验证的推断）

| # | 内容 | 章节 | 错了的风险 |
|---|------|------|-----------|
| A1 | CRF 18 = 视觉无损（trac 直接抓取被反爬挡，靠检索佐证） | Q2 | 实测流程兜底，C7 本来就要量 |
| A2 | SSIM≥0.98 / VMAF≥95 阈值是行业经验值 | Q2 | 只影响实测判据的初值 |
| A3 | h264_videotoolbox 无真 CRF 模式 | Q2 | 仅影响备选路线，主路线不受影响；`ffmpeg -h encoder=h264_videotoolbox` 人工可核 |
| A4 | Hi10P→`-pix_fmt yuv420p`、MKV 附件陷阱、`-progress pipe:1`、`-nostdin` | Q2/Q3/模式 | 全是 ffmpeg 标准语义，执行期首个真文件上机即验 |
| A5 | GUI PATH 最小化 + `/opt/homebrew/bin`、`/usr/local/bin` 探测列表 | Q7 | 漏探测路径 → 误报未安装（本机路径已实测确认存在） |
| A6 | APFS 默认大小写不敏感 | Q4 | 排除规则设计已兼容两种卷 |
| A7 | LGPL 构建 = `--disable-gpl`（无 x264/x265） | Q6 | 本架构不需要 LGPL，纯记录 |
| A8 | osxexperts.net 等 arm64 静态构建来源 | Q5 | 只影响安装提示文案的一个候选项 |
| A9 | MacPorts 在 macOS 27 可用 | Q5 | 同上，文案候选项 |

## Open Questions

1. **Phase 4 扫描器的「排除 Converted」语义**（本轮最重要悬项）：是「整个目录不扫」还是「只从待转码候选里排除、播放白名单照扫」？SC#5（转完立即可播）要求后者。**规划期**（Phase 4 executor 完工后）核对 `MediaLibrary` 实际实现；若做成全排除，需补「转码完成后注入播放列表」机制。本轮遵守边界未读 Phase 4 计划/源码。
2. **arm64 原生 ffmpeg 来源**：本机 x86_64+Rosetta 可用但折损；若追求原生，需人工验证一个可信的 arm64 静态构建源（A8）。不阻塞本 Phase。
3. **CRF/preset 终值**：C7 的本机实测流程产出，属 Phase 6 执行期动作（手动、单次），不是调研能定的。
4. **`h264_videotoolbox` 选项细节**：A3，执行期人工 `ffmpeg -h encoder=...` 核对（不转码不烤机）。

## Environment Availability

| 依赖 | 需要 | 可用 | 版本/状态 | 兜底 |
|------|------|------|-----------|------|
| ffmpeg（系统 PATH） | 转码执行 | ✓ | `/opt/homebrew/bin/ffmpeg`，9.0.2（evermeet 静态, x86_64/Rosetta）`[VERIFIED: 本会话 ls+file+站点交叉]` | 缺失→置灰降级（C3） |
| nice | 低优先级 | ✓ | /usr/bin/nice（系统自带）`[ASSUMED]` | 串行队列本身已限资源 |
| XCTest | 测试 | ✓ | 项目已用，零三方依赖 `[VERIFIED: 04-CONTEXT 环境事实]` | — |
| brew | 安装提示 | ⚠️ | macOS 27 装 ffmpeg 失败（C5） | 提示静态二进制路线 |

## Validation Architecture

**框架**：XCTest，`swift test`，零第三方依赖 `[VERIFIED: .planning/config.json + 04-CONTEXT 环境事实]`。

**C6 铁律下的测试形态**——能自动测的只有**纯逻辑**，且必须全部不触 ffmpeg：

| 需求 | 测试形态 | 命令 | 说明 |
|------|----------|------|------|
| TRANS-01 | 单测：`ExternalToolLocator` 的路径决策表（注入假 PATH/假文件系统结果） | `swift test --filter ExternalToolLocator` | 不真跑 which |
| TRANS-03 | 单测：**参数构造**断言（给定输入 → 期望的 argv 数组逐 token 相等） | `swift test --filter TranscodeCommand` | C6 原文「断言参数构造，不是实际转码」 |
| TRANS-04 | 单测：产物路径推导（源→Converted/名.tmp→名.mp4）+ 冲突/跳过规则 | `swift test --filter TranscodeOutputNaming` | 临时目录造假文件 |
| TRANS-05 | 单测：候选过滤纯函数（Converted 内的 mkv 不进队列 / Converted 外的 mkv 进） | `swift test --filter TranscodeCandidateFilter` | fixture 树（D-22：小树，绝不用 42GB 真目录） |
| TRANS-06 | 单测：进度解析纯函数（喂固定 `-progress` 样本串 → 解析出百分比） | `swift test --filter ProgressParser` | 样本串硬编码在测试里 |
| 真转码画质 | **手动、单次**：C7 的 SSIM/VMAF 实测脚本（独立于 test.sh） | 手动执行，勿自动化 | 779.9% CPU 事故的直接防线 |

**Sampling rate**：任务提交 → `swift test`（纯逻辑部分，秒级）；Phase gate → `test.sh` 全绿（其中不含任何 ffmpeg 调用）。
**Wave 0 gaps**：无新框架需求；新增测试文件按上表命名。

## Security Domain（ASVS L1）

| 类别 | 适用 | 控制措施 |
|------|------|----------|
| V5 输入校验 | **是（本 Phase 主风险）** | 文件名→命令：`Process.arguments` 数组（无 shell 拼接）+ 全部用绝对路径（首字符 `/`，杜绝「文件名像选项」被 ffmpeg 误读）；扩展名白名单（mkv/avi/webm 之外拒收） |
| V4 访问控制 | 否 | 单用户自用工具，无多主体 |
| V6 密码学 | 否 | 无密钥无网络 |
| 注入面 | 注意 | ffmpeg argv 注入是唯一外部执行面；`-progress pipe:1` 只读 stdout；不给 ffmpeg 任何来自用户的自由文本参数位 |

## Sources

### Primary（HIGH，本会话直接验证）
- gnu.org/licenses/gpl-3.0.txt — §0/§2 逐字引用（GPL 自用零义务）
- evermeet.cx/ffmpeg — 构建配置/GPL、GPG 签名/无公证、xattr 指引、9.0.2 版本、Intel-only 声明
- in-repo：ROADMAP:192-214、PROJECT.md:44-114、PITFALLS #9、STACK.md §3、04-CONTEXT D-21/D-22、ffmpeg-kit-next/LICENSE、`/opt/homebrew/bin/ffmpeg`（ls+file 头读取）

### Secondary（MEDIUM，web 检索佐证、未能直抓一手源）
- trac.ffmpeg.org/wiki/Encode/H.264 — CRF 18 视觉无损、preset 序列（Anubis 反爬挡直抓，检索多来源一致）
- gnu.org/licenses/gpl-faq — 子进程 separate-works 论（直抓被 429 限流，检索佐证含官方中文版条目）
- web 检索（AVPlayer 音频兼容矩阵、h264_videotoolbox 选项）— 质量混杂，结论已降级标注

### Tertiary（LOW，纯推断）
- A1–A9 全表（见 Assumptions Log）

## Metadata

**Confidence breakdown**：许可结论/降级策略/防回流设计 HIGH（一手或 in-repo 实测）；编码参数 MEDIUM（权威源被反爬挡，检索佐证 + 本机实测流程兜底）；ffmpeg 细节陷阱 MEDIUM-LOW（训练知识，标注清楚）。
**Research date:** 2026-10-03
**Valid until:** 2026-11-02（ffmpeg/evermeet 版本面貌月级稳定；GPL 结论长期有效）
