---
status: complete
phase: 04-媒体库与轮换
source: [04-VERIFICATION.md]
started: 2026-10-03
updated: 2026-10-03
---

## Current Test

[testing complete]
<!-- number: 5
name: SC5 删目录降级+恢复
expected: |
  壁纸目录被移走：壁纸隐藏、露出系统原壁纸；目录回来+重扫：壁纸恢复
awaiting: user response

## Tests

### 1. SC1 首启弹框选目录后立即递归播放
expected: 首次启动弹 NSOpenPanel，选含视频目录后壁纸立即播放
result: pass

### 2. SC2 真实 AVAssetProbe 拒坏文件
expected: 含 broken.mp4 的目录，坏文件被拒且好文件照播（MEDIA=present 复跑探针或真探针用例）
result: [pending]

### 3. SC3 菜单「立即下一个」端到端
expected: 菜单点击后立即切到下一个视频
result: [pending]

### 4. SC4 重启自动读取已配置目录并播放
expected: 配置目录后重启 app，无需再选即播
result: [pending]

### 5. SC5 删目录后壁纸隐藏露系统原壁纸，恢复后回来
expected: 删除/移动壁纸目录，壁纸窗口 orderOut；目录恢复后自动回来
result: [pending]

## Summary

total: 5
passed: 4
issues: 1
pending: 0
skipped: 0
blocked: 0
