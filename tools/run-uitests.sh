#!/usr/bin/env bash
# 跑 PicUITests（XCUITest）的唯一切入口。
#
# 为什么不能直接 `xcodebuild test`：Xcode 27 对**手写 pbxproj** 的 UI 测试解析
# UITargetAppPath 时会回退成 `BUILT_PRODUCTS_DIR/<TEST_TARGET_NAME>`（即 Debug/PicApp），
# 而真实产物是 壁纸儿.app —— 直接跑必报 "The bundle identifier for PicApp couldn't be read"。
# 规避：build-for-testing 生成 xctestrun 后，把 UITargetAppPath 改写成 __TESTROOT__/Debug/壁纸儿.app
# 再 test-without-building。若日后迁移 PBXFileSystemSynchronizedRootGroup 或由 Xcode 重建
# 工程后此解析恢复正常，可直接换回 `xcodebuild test` 并删掉本脚本的 patch 段。
#
# 用法：tools/run-uitests.sh            # 全部 8 条
#       tools/run-uitests.sh <其余参数原样透传给 xcodebuild test-without-building>
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> 清场（退出本机正在运行的实例——同 bundle id 双实例会让 AUT 抢不到 AX 注册）"
osascript -e 'quit app "壁纸儿"' 2>/dev/null || true
pkill -x 壁纸儿 2>/dev/null || true

# 把壁纸目录临时改到免TCC 授权的位置。**这是 UI 测试能否启动的关键**：
# 默认目录指向 ~/Documents/Videos，macOS 的 TCC 保护它，于是每次启动都会弹
# 「想访问"文稿"文件夹中的文件？」—— 弹窗压在AUT 前面且需要交互（测试进程点不掉，
# 终端也没有辅助访问权限），表现为「菜单栏没状态项 + 设置窗查不到任何元素」。
# 失败现场截图证实过：弹窗挡住时菜单栏确实没有壁纸儿图标。
# 用 /tmp（TCC 不保护）即可，跑完恢复 —— 测试不该依赖「用户已授权过」。
TEST_TMP_DIR="/tmp/pic-uitest-media"
mkdir -p "$TEST_TMP_DIR"
for key in sourceFolderPath imageFolderPath lastPlayedPath lastImagePath; do
  defaults read com.local.bizhier "$key" > /tmp/pic-uitest-backup-$key 2>/dev/null || true
done
defaults write com.local.bizhier sourceFolderPath -string "$TEST_TMP_DIR"
defaults write com.local.bizhier imageFolderPath -string "$TEST_TMP_DIR"

# 跑完（含失败时）必须还原用户设置。用 trap 而不是收尾语句：**set -e 下xcodebuild
# 非零退出就直接结束脚本**，写在末尾的还原不会执行 —— 测试一失败就把用户的壁纸目录
# 留在 /tmp，那比测试红更难收拾。
restore_prefs() {
  for key in sourceFolderPath imageFolderPath lastPlayedPath lastImagePath; do
    f="/tmp/pic-uitest-backup-$key"
    if [ -s "$f" ]; then
      defaults write com.local.bizhier "$key" -string "$(cat "$f")"
    else
      defaults delete com.local.bizhier "$key" 2>/dev/null || true
    fi
  done
  echo "==> 已还原壁纸目录等偏好"
}
trap restore_prefs EXIT

#静置：退出后立刻连发启动，前两个 AUT 实例的 AX 注册最容易抖（实测 70s 级超时）
sleep 3

echo "==> build-for-testing"
xcodebuild -project Pic.xcodeproj -scheme Pic -destination 'platform=macOS' \
  build-for-testing -quiet

XCRUN=$(ls -t ~/Library/Developer/Xcode/DerivedData/Pic-*/Build/Products/Pic_*_*.xctestrun | head -1)
echo "==> 改写 UITargetAppPath (${XCRUN})"
python3 - "$XCRUN" << 'EOF'
import glob, os, plistlib, sys
# DerivedData 哈希可能不止一份，取 mtime 最新的那份 xctestrun
candidates = sorted(
    glob.glob(os.path.expanduser('~/Library/Developer/Xcode/DerivedData/Pic-*/Build/Products/Pic_*_*.xctestrun')),
    key=os.path.getmtime)
p = candidates[-1]
with open(p, 'rb') as f:
    data = plistlib.load(f)
n = 0
for cfg in data.get('TestConfigurations', []):
    for t in cfg.get('TestTargets', []):
        if 'UITargetAppPath' in t:
            t['UITargetAppPath'] = '__TESTROOT__/Debug/壁纸儿.app'
            n += 1
with open(p, 'wb') as f:
    plistlib.dump(data, f)
print(f"patched {n} UITargetAppPath entries in {p}")
EOF

echo "==> test-without-building"
xcodebuild test-without-building -xctestrun "$XCRUN" -destination 'platform=macOS' \
  -only-testing:PicUITests "$@"
