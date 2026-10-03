#!/usr/bin/env bash
# run-uitests.sh —— Phase 5 的 XCUITest 运行器（锁屏守卫 + BLOCKED 纪律）。
#
#   bash scripts/run-uitests.sh
#     → plutil -lint pbxproj（失败即红）
#     → xcodebuild build-for-testing（app target 能编过 —— 源文件与 SwiftPM 共享，
#       两套构建零漂移的证明；ad-hoc 签名显式传命令行，与 pbxproj 双保险）
#     → 锁屏检测（CGSessionCopyCurrentDictionary 的 CGSSessionScreenIsLocked，
#       与产品 run-probe.sh 走同一个 API）→ LOCKED=0|1
#     → LOCKED=1：UITEST_STATUS=blocked reason=screen_locked —— 必须先在
#       .planning/WINDOWS.md 里 grep 到 W-2026-10-03-25 才放行（登记后才走，
#       防静默跳过；blocked 与 failed 必须可区分）
#     → 屏幕录制未授权：UITEST_STATUS=skipped reason=screen_capture_unauthorized
#       （同样必须先有 W-2026-10-03-48 才放行；绝不硬闯授权弹窗）
#     → LOCKED=0 且已授权：xcodebuild test-without-building，全部输出落
#       evidence/uitest.log，打 UITEST_STATUS=passed|failed 与 UITEST_TEST_RC=
#
# ⚠️ 为什么 build-for-testing + test-without-building 而不是一个 `xcodebuild test`：
#    单个 `xcodebuild test` 偶发在「边建边测」时解析 app 产物失败
#    （实测「The bundle identifier for PicApp couldn't be read」间歇复现，同源码
#    重跑即过）。拆开后 app 与测试包先全部构建完、由生成的 .xctestrun 带上
#    UITargetAppPath 再跑，消掉那个竞态。
#
# 纪律照 probe-lock.sh：alarm 包装（本机无 timeout）、LC_ALL=C、不用 set -e、
# mktemp + trap。脚本与日志不出现任何真实素材路径。
#
# W 号段（Phase 5 占用，各 plan 分段不重叠）：
#   W-2026-10-03-25 —— 本脚本的锁屏 BLOCKED（XCUITest 需可交互会话，锁屏跑不了；
#                     解开条件 = 解锁后重跑本脚本）
#   W-2026-10-03-26 —— 备用：若执行期发现 Window 场景无法满足 SC-1 某属性需换
#                     Settings 场景，登记后按 UI-SPEC §7 重做，判据不放宽
#   W-2026-10-03-48 —— 本脚本的屏幕录制未授权 SKIPPED（XCUITest 抓界面要屏幕录制
#                     权限；未授权会弹「打开系统设置」的授权链打断会话；
#                     解开条件 = 系统设置 → 隐私与安全性 → 屏幕录制 授权后重跑）。
#                     ⚠️ 不用 -27：05-02 已把该号标记为 moot 且不回收（原字体回退
#                     场景），重用它会破坏 D-18「全 Phase 唯一 + uniq -d 为 0」。
set -u
export LC_ALL=C

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

EV="$ROOT/.planning/phases/05-settings/evidence"
LOG="$EV/uitest.log"
TMP="$(mktemp -d)"

alarm() { perl -e "alarm $1; exec @ARGV" "${@:2}"; }
cleanup() { rm -rf "$TMP"; return 0; }
trap cleanup EXIT INT TERM

mkdir -p "$EV"
# 每次全量重采。
: > "$LOG"

# 1. pbxproj lint（旧式 plist）
if plutil -lint Pic.xcodeproj/project.pbxproj > /dev/null 2>&1; then
  echo "PBXPROJ_LINT=ok" >> "$LOG"
else
  echo "PBXPROJ_LINT=failed" >> "$LOG"
  plutil -lint Pic.xcodeproj/project.pbxproj 2>&1 >> "$LOG"
  echo "UITEST_STATUS=failed reason=pbxproj_lint" >> "$LOG"
  exit 1
fi

# 2. app target 编译（交付仍走 swift build —— D-01；本步只为证明共享源零漂移）
# 先在**测试进程之外**清掉窗口 frame 记忆并确认 cfprefsd 已落地：SwiftUI Window 会
# 把 frame 存进 com.local.pic 的 "NSWindow Frame settings"（bundle-id 域），任何
# 一次手动改宽都会让「打开即 780」的断言失真。实测单独跑一次 defaults delete 会
# 被 cfprefsd 缓存吃掉（连续三轮：2 绿 1 红），故删完轮询确认。
FRAME_KEY="NSWindow Frame settings"
defaults delete com.local.pic "$FRAME_KEY" 2>/dev/null || true
for _ in 1 2 3 4 5 6 7 8 9 10; do
  defaults read com.local.pic "$FRAME_KEY" > /dev/null 2>&1 || break
  sleep 0.5
done
if defaults read com.local.pic "$FRAME_KEY" > /dev/null 2>&1; then
  echo "FRAME_STATE_CLEAR=failed" >> "$LOG"
else
  echo "FRAME_STATE_CLEAR=ok" >> "$LOG"
fi

if alarm 600 xcodebuild -project Pic.xcodeproj -scheme Pic -destination 'platform=macOS' \
     CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual build-for-testing > "$TMP/build.log" 2>&1; then
  echo "XCODEBUILD_BUILD_RC=0" >> "$LOG"
else
  echo "XCODEBUILD_BUILD_RC=1" >> "$LOG"
  grep -E 'error:' "$TMP/build.log" | head -20 >> "$LOG"
  echo "UITEST_STATUS=failed reason=xcodebuild_build" >> "$LOG"
  exit 1
fi

# 3. 锁屏检测（与产品 run-probe.sh:503-540 同一个 API）
LOCK_LINE=$(alarm 90 swift -e '
import CoreGraphics
import Foundation
let session = CGSessionCopyCurrentDictionary() as? [String: Any]
let locked = ((session?["CGSSessionScreenIsLocked"] as? NSNumber)?.intValue ?? 0) != 0
print("LOCKED=\(locked ? 1 : 0)")
' 2>/dev/null || true)
LOCKED=$(printf '%s' "$LOCK_LINE" | sed -n 's/^LOCKED=\([01]\)$/\1/p')
[ -n "$LOCKED" ] || LOCKED=unknown
echo "SCREEN_LOCKED=$LOCKED" >> "$LOG"

# 4. 锁屏 → BLOCKED（登记了 W 才放行）
if [ "$LOCKED" = 1 ]; then
  if grep -q 'W-2026-10-03-25' .planning/WINDOWS.md; then
    echo "UITEST_STATUS=blocked reason=screen_locked" >> "$LOG"
    echo "UITEST_STATUS=blocked reason=screen_locked（解开条件：解锁后重跑 bash scripts/run-uitests.sh）" >&2
    exit 0
  fi
  echo "W_ENTRY_MISSING=.planning/WINDOWS.md 里没有 W-2026-10-03-25 —— 先登记 unrun-verify 条目（描述/证据/影响/解开条件）再重跑" >> "$LOG"
  echo "W_ENTRY_MISSING —— 先在 .planning/WINDOWS.md 登记 W-2026-10-03-25 再重跑" >&2
  exit 1
fi

# 4b. 屏幕录制授权预检（与锁屏分支同纪律）。
#     XCUITest 抓界面要屏幕录制权限；未授权时 macOS 会弹「打开系统设置」的授权
#     链，弹到一半会话就被打断。预检未过就**不硬闯**：记 skipped + W 条目，
#     与 LOCKED 分支同形，绝不把 skipped 记成 passed。
CAP_LINE=$(alarm 90 swift -e '
import CoreGraphics
print("SCREEN_CAPTURE=\(CGPreflightScreenCaptureAccess() ? 1 : 0)")
' 2>/dev/null || true)
CAP=$(printf '%s' "$CAP_LINE" | sed -n 's/^SCREEN_CAPTURE=\([01]\)$/\1/p')
[ -n "$CAP" ] || CAP=unknown
echo "SCREEN_CAPTURE_AUTHORIZED=$CAP" >> "$LOG"
if [ "$CAP" = 0 ]; then
  if grep -q 'W-2026-10-03-48' .planning/WINDOWS.md; then
    echo "UITEST_STATUS=skipped reason=screen_capture_unauthorized" >> "$LOG"
    echo "UITEST_STATUS=skipped reason=screen_capture_unauthorized（解开条件：在 系统设置 → 隐私与安全性 → 屏幕录制 里给终端/Xcode 授权后重跑本脚本）" >&2
    exit 0
  fi
  echo "W_ENTRY_MISSING=.planning/WINDOWS.md 里没有 W-2026-10-03-48 —— 先登记 unrun-verify 条目再重跑" >> "$LOG"
  echo "W_ENTRY_MISSING —— 先在 .planning/WINDOWS.md 登记 W-2026-10-03-48 再重跑" >&2
  exit 1
fi

# 5. 解锁会话 → 跑测试（全部输出进 evidence；状态经 UITEST_STATUS 传递，
#    failed 也退出 0 —— RUNNER 的退出码只表达「流程走完」）
if alarm 600 xcodebuild -project Pic.xcodeproj -scheme Pic -destination 'platform=macOS' \
     CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual test-without-building > "$TMP/test.log" 2>&1; then
  echo "UITEST_TEST_RC=0" >> "$LOG"
  ST=passed
else
  echo "UITEST_TEST_RC=1" >> "$LOG"
  ST=failed
fi
cat "$TMP/test.log" >> "$LOG"
echo "UITEST_STATUS=$ST" >> "$LOG"
exit 0
