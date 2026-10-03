#!/usr/bin/env bash
# 编译 → 打包 .app → 生成 DMG。不签名。
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Pic"
BUNDLE_ID="com.local.pic"
VERSION="0.1.0"
MIN_MACOS="15.0"
OUT="build"
DIST="dist"

echo "==> 清理"
rm -rf "$OUT" "$DIST"
mkdir -p "$OUT" "$DIST"

echo "==> 编译（D-01：走 SwiftPM，不走 xcodebuild）"
# 二进制出自 swift build 的 release 产物，不再手编 spike 源。
# -DPIC_NO_PROBE：剥离三个测量探针（LoopProbe/WindowProbe/FrameDriver）及其接线。
# 不传该 define 的构建（debug / swift test / PicProbe）探针全保留，是默认态。
swift build --package-path . -c release -Xswiftc -DPIC_NO_PROBE
cp ".build/release/${APP_NAME}" "$OUT/${APP_NAME}"

echo "==> 组装 .app"
APP="$OUT/${APP_NAME}.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$OUT/${APP_NAME}" "$APP/Contents/MacOS/${APP_NAME}"
# Info.plist 的唯一真相源是 Sources/PicApp/Resources/Info.plist。
# 刻意不在这里再内联一份 heredoc —— 两份手写同一份 plist 必然漂移，
# 而 AC「diff 两份退出 0」就是防这件事的（build.sh 里 cp 过去即可逐字一致）。
cp "Sources/PicApp/Resources/Info.plist" "$APP/Contents/Info.plist"

echo "==> ad-hoc 签名（本地能跑即可，非 Developer ID）"
codesign --force --deep -s - "$APP"

# DMG 的内容物只从 staging 来，绝不指 build/ —— build/ 里还住着 PicProbe.app
# 与 iconset 等中间产物，指错就把第二产物装进用户要安装的 DMG（W-2026-10-03-37）。
echo "==> 准备 staging（只放 Pic.app）"
STAGE="$DIST/stage"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/${APP_NAME}.app"

echo "==> 生成 DMG（create-dmg 主路）"
DMG="$DIST/${APP_NAME}-${VERSION}.dmg"
# create-dmg 的 Finder 美化步骤需要「自动化」权限，未授权时会失败并留临时文件。
if ! create-dmg --volname "$APP_NAME" --app-drop-link 480 180 \
  --icon "${APP_NAME}.app" 180 180 --hide-extension "${APP_NAME}.app" \
  --no-internet-enable "$DMG" "$STAGE"; then
  echo "DMG_FALLBACK=hdiutil reason=create_dmg_failed_automation_permission"
  hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$STAGE/${APP_NAME}.app" \
    -ov -format UDZO "$DMG"
fi
# 收尾清临时文件：create-dmg 失败会留 dist/rw.*.dmg，混进下面的摘要就多出一个假 DMG。
rm -f "$DIST"/rw.*.dmg

echo ""
echo "✅ 完成"
echo "   .app : $APP"
echo "   .dmg : $DIST/${APP_NAME}-${VERSION}.dmg"
ls -lh "$DIST"/*.dmg | awk '{print "   " $5 "  " $9}'

echo ""
echo "==> 签名与产物摘要（供 evidence/app-bundle.log 采集）"
codesign -dv --verbose=2 "$APP" 2>&1 | grep -E '^(Identifier|Signature|TeamIdentifier)='
md5 -q "$DIST/${APP_NAME}-${VERSION}.dmg"
# 一个数一行（D-17）：交付二进制必须为 0；探针产物那一列在第二产物存在后才成立。
# 必须 grep -cE —— 裸 grep 的 '|' 是字面量，恒 0 假绿灯（RESEARCH 坑 1）。
echo "PROBE_SYMBOLS_PIC=$(nm "$APP/Contents/MacOS/${APP_NAME}" | grep -cE 'LoopProbe|WindowProbe|FrameDriver')"
