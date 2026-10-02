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
swift build --package-path . -c release
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

echo "==> 生成 DMG"
# 直接用 hdiutil：create-dmg 的 Finder 美化步骤需要「自动化」权限，会失败并留临时文件
rm -f "$DIST"/rw.*.dmg
hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$APP" \
  -ov -format UDZO "$DIST/${APP_NAME}-${VERSION}.dmg"

echo ""
echo "✅ 完成"
echo "   .app : $APP"
echo "   .dmg : $DIST/${APP_NAME}-${VERSION}.dmg"
ls -lh "$DIST"/*.dmg | awk '{print "   " $5 "  " $9}'

echo ""
echo "==> 签名与产物摘要（供 evidence/app-bundle.log 采集）"
codesign -dv --verbose=2 "$APP" 2>&1 | grep -E '^(Identifier|Signature|TeamIdentifier)='
md5 -q "$DIST/${APP_NAME}-${VERSION}.dmg"
