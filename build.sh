#!/usr/bin/env bash
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

ASSETS=".planning/design/assets"

# 组装 .app。$1 = 产物名；裸二进制已在 $OUT/$1 就位。
assemble_app() {
  local app="$OUT/$1.app"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
  cp "$OUT/$1" "$app/Contents/MacOS/$APP_NAME"
  # Info.plist 的唯一真相源是 Sources/PicApp/Resources/Info.plist，刻意不再内联一份 heredoc —— 两份手写同一份 plist 必然漂移。
  cp "Sources/PicApp/Resources/Info.plist" "$app/Contents/Info.plist"
  # 菜单栏只拷 menubar-v1 的 Template 三档，menubar-v2 是对照稿，一个都不拷。
  cp "$OUT/Pic.icns" "$app/Contents/Resources/Pic.icns"
  cp "$ASSETS/menubar-v1.png"     "$app/Contents/Resources/menubar-v1Template.png"
  cp "$ASSETS/menubar-v1@2x.png"  "$app/Contents/Resources/menubar-v1Template@2x.png"
  cp "$ASSETS/menubar-v1@3x.png"  "$app/Contents/Resources/menubar-v1Template@3x.png"
  codesign --force --deep -s - "$app"
}

# iconutil 路（不依赖 actool / .xcassets，与 SwiftPM 路线同构）。
echo "==> 出 .icns（iconutil，图标真相源 = .planning/design/assets/）"
rm -rf "$OUT/${APP_NAME}.iconset"
mkdir -p "$OUT/${APP_NAME}.iconset"
cp "$ASSETS"/icon_*.png "$OUT/${APP_NAME}.iconset/"
iconutil -c icns "$OUT/${APP_NAME}.iconset" -o "$OUT/Pic.icns"

echo "==> 编译交付产物（D-01：走 SwiftPM，不走 xcodebuild）"
swift build --package-path . -c release
cp ".build/release/${APP_NAME}" "$OUT/${APP_NAME}"

echo "==> 组装交付 .app"
assemble_app "$APP_NAME"
APP="$OUT/${APP_NAME}.app"

# DMG 的内容物只从 staging 来，绝不指 build/ —— 那里还住着 iconset 等中间产物。
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
echo "   .app 交付 : $APP"
echo "   .dmg      : $DIST/${APP_NAME}-${VERSION}.dmg"
ls -lh "$DIST"/*.dmg | awk '{print "   " $5 "  " $9}'

echo ""
echo "==> 签名与产物摘要"
codesign -dv --verbose=2 "$APP" 2>&1 | grep -E '^(Identifier|Signature|TeamIdentifier)='
md5 -q "$DIST/${APP_NAME}-${VERSION}.dmg"
