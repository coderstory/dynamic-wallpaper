# 重构方案（修订版）：诚实量化可缩减量

> 前版说「只能减 40 行」是错的（漏算了队列重复）；但「能减几百行」也是错的。
> 本版用数据说话。

## 真实可缩减量：约 60-80 行（非 40，也非几百）

### 为什么「减几百行」不成立

项目 7185 行 = 注释约 1200 行（刻意、面向 AI，不可删）+ 代码约 6000 行。
代码已高度复用（struct 56 / enum 31 / protocol 14 / 依赖注入）。

两个转码队列（625 行）看似同构，但差异点多达 6-7 处：
1. 幂等跳过时机（Transcode 在 runJob，Fps 在 scan）
2. 产物命名（outputURL vs derivativeURL）
3. 成功钩子（删源+校验 vs 写帧率表）
4. 失败分支（Fps 有取消 vs 失败区分 + 写可重试态）
5. argv（TranscodeCommand vs FpsDownscaleCommand）
6. 进度时长来源（durationProvider vs specProvider）

硬抽「模板方法」会引入 6-7 个钩子，抽象成本 > 省下的重复。这是「DRY 陷阱」：
为了消除表面重复，引入更难维护的隐式耦合。

## 可安全缩减点（无差异的纯重复）

### R1. 预检流水线抽公共辅助（~30 行）
「预检1可用性 + 预检3建目录 + 预检4磁盘」三段在两个队列逐行相同，
抽成 `@MainActor` 的公共枚举 `TranscodePreflight` 静态方法。

### R2. ProgressState 去重（~8 行）
两个队列各自的 `ProgressState` 累加器壳完全一样，抽成共享类型。

### R3. 状态展示协议（~40 行）
两个 Section 的 stateSymbol/stateLabel/isFailure/progressBar 收敛成协议扩展。

### R4. sizeText + isAvailable 去重（~15 行）
两个 ViewModel 的 sizeText 相同；`if case .available` 收敛成 `FFmpegToolStatus.isAvailable`。

## 结论

**净减约 60-80 行，占代码 1%，风险可控（TDD 保护）。**

「多用设计模式」的正确落点是 R3 的协议扩展（Swift 版策略模式），不是引入继承层次。
强行对两个队列上模板方法（R2 旧版）是 DRY 陷阱，明确不做。
