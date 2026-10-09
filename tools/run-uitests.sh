#!/usr/bin/env bash
# 跑 PicUITests（XCUITest）的唯一切入口。
#
# 为什么不能直接 `xcodebuild test`：Xcode 27 对**手写 pbxproj** 的 UI 测试解析
# UITargetAppPath 时会回退成 `BUILT_PRODUCTS_DIR/<TEST_TARGET_NAME>`（即 Debug/PicApp），
# 而真实产物是 Pic.app —— 直接跑必报 "The bundle identifier for PicApp couldn't be read"。
# 规避：build-for-testing 生成 xctestrun 后，把 UITargetAppPath 改写成 __TESTROOT__/Debug/Pic.app
# 再 test-without-building。若日后迁移 PBXFileSystemSynchronizedRootGroup 或由 Xcode 重建
# 工程后此解析恢复正常，可直接换回 `xcodebuild test` 并删掉本脚本的 patch 段。
#
# 用法：tools/run-uitests.sh            # 全部 5 条
#       tools/run-uitests.sh <其余参数原样透传给 xcodebuild test-without-building>
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> build-for-testing"
xcodebuild -project Pic.xcodeproj -scheme Pic -destination 'platform=macOS' \
  build-for-testing -quiet

XCRUN=$(ls -t ~/Library/Developer/Xcode/DerivedData/Pic-*/Build/Products/Pic_*_*.xctestrun | head -1)
echo "==> 改写 UITargetAppPath（$XCRUN）"
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
            t['UITargetAppPath'] = '__TESTROOT__/Debug/Pic.app'
            n += 1
with open(p, 'wb') as f:
    plistlib.dump(data, f)
print(f"patched {n} UITargetAppPath entries in {p}")
EOF

echo "==> test-without-building"
xcodebuild test-without-building -xctestrun "$XCRUN" -destination 'platform=macOS' \
  -only-testing:PicUITests "$@"
