#!/usr/bin/env bash
# 编译 → 打包 .app → 生成 DMG。不签名。
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Pic"
BUNDLE_ID="com.local.pic"
VERSION="0.1.0"
MIN_MACOS="15.0"
SRC_DIR=".planning/spike"          # 真实 app 落地后改成 Sources/
OUT="build"
DIST="dist"

echo "==> 清理"
rm -rf "$OUT" "$DIST"
mkdir -p "$OUT" "$DIST"

echo "==> 编译"
# 单文件 spike；真实 app 落地后换成 xcodebuild
swiftc -O -parse-as-library \
  -target "arm64-apple-macosx${MIN_MACOS}" \
  -o "$OUT/${APP_NAME}" \
  "$SRC_DIR/SettingsSpike.swift" "$SRC_DIR/Render.swift"

echo "==> 组装 .app"
APP="$OUT/${APP_NAME}.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$OUT/${APP_NAME}" "$APP/Contents/MacOS/${APP_NAME}"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleExecutable</key><string>${APP_NAME}</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>${MIN_MACOS}</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

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
