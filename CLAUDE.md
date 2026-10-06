# CLAUDE.md — Pic

macOS 动态壁纸播放器。菜单栏常驻（`.accessory`，无 Dock 图标），全屏视频铺满桌面并按设置轮换，
系统事件（锁屏 / 全屏 / 熄屏 / 睡眠 / 电池）会压住播放。

- **包**：`PicApp`（可执行，AppKit + SwiftUI）/ `PicCore`（纯逻辑库），仅 macOS 27，零第三方依赖
- **构建**：`swift build`；打包 .app + DMG 走 `./build.sh`（不签名）
- **测试**：XCTest，`swift test`（框架锁死 XCTest，汇总串被 `test.sh` 依赖）
- **验证脚本**：`./test.sh` 是端到端验收，单测 + 探针脚本 + 打包检查都串在里面

## 架构

单向数据流，四层各自独立可测：

```
Watcher（系统信号源）→ HoldArbiter（唯一决策点）→ PlayerController（播放）
RotationController（轮换）→ PlaybackRouter（装载分派）
```

- `PicCore` 不含 AppKit 依赖的判定逻辑，几何 / 策略 / 命名判定都是纯函数
- `AppDelegate` 是**唯一装配点**，也是全仓唯一把系统信号变成 `HoldReason` 的地方
- 播放状态只由 `HoldArbiter` 一处决定，菜单与设置窗不得直连播放器

## 注释纪律（硬规则，写代码时同步遵守）

> **出发点：代码的唯一读者是 AI，不是人。** 这一条决定其余全部——AI 解析代码零成本、
> 记得住文件里的每条约束，**但会自作主张地"改进"它认为冗余的代码**。
> 注释的唯一任务是帮 AI 在「该做什么、该不做什么」上不犯错。

**唯一判据**——对每条注释问一句：*这句话是在帮 AI 少犯一条错，还是在浪费它的注意力？*
少犯错就留，浪费就删。没有第三档，没有「以防万一」。

- **必留 · 反重构警告（最高优先级）**：凡是「看起来该被清理」但其实不能动的，必须写明为什么。
  人类不会擅自重构，AI 会，而且很自信。典型：顺序不可换（反了会怎样）／刻意不用某 API（用了会怎样）／
  看似冗余但必需（省了会怎样）／缺省值陷阱（漏了会怎样）／不许顺手清理的怪异写法。
  例：`// setRate 必须门在「应当播放」之后：非零 rate 会让已 hold 的播放器重新拉起`
- **必留 · 契约**：① 接口契约（参数单位 / 返回语义含三态与哨兵值 / 前置条件）
  ② 并发与线程约束（`@MainActor` 边界、`MainActor.assumeIsolated` 的合法前提、哪把锁）
  ③ 错误码语义（枚举值到底代表什么）④ 非显然的坑（只陈述规则，不写发现过程与调试故事）
- **必留 · 跨文件不变量**：单文件里推不出来的规则。例：
  「四个 Watcher 都必须强持有，谁创建谁 stop()，否则回调永久泄漏」
  「`invalidateCache()` 必须同步排在重扫之前，否则新产物永远看不见」
- **必删**：复述代码行为／复述命名／演变叙事（「此前」「改成」「旧实现」——AI 会自己 `git log`）／
  出处与证据（`SDK AVPlayer.h:150`、`本机实测`、`见 XxxTests.swift`）／
  验证体系自解说（「判据锁着」「守卫：探针组 K」，AI 不参与该体系）／
  设计推演（「为什么不抽出来」，结构本身已表达答案）／告警符号（⚠️🔴 与「这行最容易被顺手删掉」——
  AI 不会因恐吓而更小心，只会很困惑到底哪里危险，写事实即可）／纯装饰分隔线。
- **注释是负资产**。默认不写，只在「AI 会犯的具体错误」前写，且一句话说完。
  反重构警告只写「为什么不能动 + 动了会怎样」，不写发现过程、不写调试故事、不写历史。
  一条注释超过 2 行，先怀疑它在复述行为或讲故事，删到只剩那条「AI 会犯的错」。
  现状限制（「暂不支持 X」）一句话即可。

## 改代码时的红线

- `emit("...")` 是遗留的字符串验收锚点，**正在逐步废弃**，由 XCTest 替代。改产品逻辑时
  不得新增 `emit` 打点；已有的打点可以删（同步删 `test.sh` / `scripts/` 里对应的 grep）。
- 只改注释时，验证方式：剥掉所有 `//` 行后与 `HEAD` 逐字节比对，应完全相同。
- 不改构建产物、不碰 `build/` `dist/` `fixtures/`。

## Agent skills

### Issue tracker

票在 `coderstory/dynamic-wallpaper` 的 GitHub Issues 里，读写一律走 deck 的 `deck_*` 工具，不手敲 `gh`。See `docs/agents/issue-tracker.md`.

### Triage labels

triage 的五个规范角色，标签串与角色同名（`needs-triage` / `needs-info` / `ready-for-agent` / `ready-for-human` / `wontfix`）。See `docs/agents/triage-labels.md`.

### Domain docs

single-context —— 一个仓库共用根目录一份 `CONTEXT.md`，架构决策放 `docs/adr/`。See `docs/agents/domain.md`.
