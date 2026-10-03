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

ASSETS=".planning/design/assets"

# 探针符号计数。必须 `grep -cE` —— 裸 grep 的 '|' 是字面量，恒 0 假绿灯
# （RESEARCH 坑 1 / W-2026-10-03-35）。
probe_symbols() { nm "$1/Contents/MacOS/$APP_NAME" | grep -cE 'LoopProbe|WindowProbe|FrameDriver'; }

# 组装 .app —— 交付与探针两条线**共用这一份实现**。两处手写同样的 mkdir/cp/
# codesign 块必然漂移，抽成函数是「为正确性花的钱」（反膨胀：抽，不复制）。
# $1 = 产物名；裸二进制已在 $OUT/$1 就位（bundle 内的可执行名恒为 $APP_NAME）。
assemble_app() {
  local app="$OUT/$1.app"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
  cp "$OUT/$1" "$app/Contents/MacOS/$APP_NAME"
  # Info.plist 的唯一真相源是 Sources/PicApp/Resources/Info.plist。
  # 刻意不在这里再内联一份 heredoc —— 两份手写同一份 plist 必然漂移，
  # 而 AC「diff 两份退出 0」就是防这件事的（cp 过去即可逐字一致）。
  cp "Sources/PicApp/Resources/Info.plist" "$app/Contents/Info.plist"
  # 图标：.icns 由 iconutil 出（CFBundleIconFile=Pic 指向它）；菜单栏用
  # menubar-v1 的 Template 三档。menubar-v2 是对照稿，一个都不拷。
  cp "$OUT/Pic.icns" "$app/Contents/Resources/Pic.icns"
  cp "$ASSETS/menubar-v1.png"     "$app/Contents/Resources/menubar-v1Template.png"
  cp "$ASSETS/menubar-v1@2x.png"  "$app/Contents/Resources/menubar-v1Template@2x.png"
  cp "$ASSETS/menubar-v1@3x.png"  "$app/Contents/Resources/menubar-v1Template@3x.png"
  codesign --force --deep -s - "$app"
}

# iconutil 路（不依赖 actool / .xcassets，与 SwiftPM 路线同构）：
# .planning/design/assets/ 里的文件名已经是 iconset 规范名，直接 cp 进 .iconset。
# iconset 目录刻意留在 build/ 里不清理 —— 判据要数它（ASSET-01）。
echo "==> 出 .icns（iconutil，图标真相源 = .planning/design/assets/）"
rm -rf "$OUT/${APP_NAME}.iconset"
mkdir -p "$OUT/${APP_NAME}.iconset"
cp "$ASSETS"/icon_*.png "$OUT/${APP_NAME}.iconset/"
iconutil -c icns "$OUT/${APP_NAME}.iconset" -o "$OUT/Pic.icns"

echo "==> 编译交付产物（D-01：走 SwiftPM，不走 xcodebuild）"
# 二进制出自 swift build 的 release 产物，不再手编 spike 源。
# -DPIC_NO_PROBE：剥离三个测量探针（LoopProbe/WindowProbe/FrameDriver）及其接线。
swift build --package-path . -c release -Xswiftc -DPIC_NO_PROBE
cp ".build/release/${APP_NAME}" "$OUT/${APP_NAME}"

echo "==> 组装交付 .app"
assemble_app "$APP_NAME"
APP="$OUT/${APP_NAME}.app"

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

# 第二遍构建：**不传** define，探针全保留 → PicProbe.app。
# 顺序必须「先交付后探针」：每遍都会覆盖 .build/release，组装必须在各自构建
# 之后立刻做（裸二进制已 cp 到 $OUT，后一遍覆盖 .build 无影响）。
# PicProbe.app 是测量取证体，**不进 staging、不进 DMG**。
echo "==> 编译探针产物（保留 LoopProbe/WindowProbe/FrameDriver）"
swift build --package-path . -c release
cp ".build/release/${APP_NAME}" "$OUT/PicProbe"

echo "==> 组装探针 .app"
assemble_app PicProbe

echo ""
echo "✅ 完成"
echo "   .app 交付 : $APP"
echo "   .app 探针 : $OUT/PicProbe.app（不进 DMG）"
echo "   .dmg      : $DIST/${APP_NAME}-${VERSION}.dmg"
ls -lh "$DIST"/*.dmg | awk '{print "   " $5 "  " $9}'

echo ""
echo "==> 签名与产物摘要（供 evidence/app-bundle.log 采集）"
codesign -dv --verbose=2 "$APP" 2>&1 | grep -E '^(Identifier|Signature|TeamIdentifier)='
md5 -q "$DIST/${APP_NAME}-${VERSION}.dmg"
# 一个数一行（D-17）：交付物与探针产物是两个数，不许合成一个读法。
# 成对出现才成判据 —— 只有 == 0 一条就是 grep 模式空集的假绿灯。
echo "PROBE_SYMBOLS_PIC=$(probe_symbols "$APP")"
echo "PROBE_SYMBOLS_PROBE=$(probe_symbols "$OUT/PicProbe.app")"
