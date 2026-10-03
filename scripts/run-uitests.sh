#!/usr/bin/env bash
# run-uitests.sh —— Phase 5 的 XCUITest 运行器（锁屏守卫 + BLOCKED 纪律）。
#
#   bash scripts/run-uitests.sh
#     → plutil -lint pbxproj（失败即红）
#     → xcodebuild build（app target 能编过 —— 源文件与 SwiftPM 共享，
#       两套构建零漂移的证明；ad-hoc 签名显式传命令行，与 pbxproj 双保险）
#     → 锁屏检测（CGSessionCopyCurrentDictionary 的 CGSSessionScreenIsLocked，
#       与产品 run-probe.sh 走同一个 API）→ LOCKED=0|1
#     → LOCKED=1：UITEST_STATUS=blocked reason=screen_locked —— 必须先在
#       .planning/WINDOWS.md 里 grep 到 W-2026-10-03-25 才放行（登记后才走，
#       防静默跳过；blocked 与 failed 必须可区分）
#     → LOCKED=0：xcodebuild test，全部输出落 evidence/uitest.log，
#       打 UITEST_STATUS=passed|failed 与 UITEST_TEST_RC=
#
# 纪律照 probe-lock.sh：alarm 包装（本机无 timeout）、LC_ALL=C、不用 set -e、
# mktemp + trap。脚本与日志不出现任何真实素材路径。
#
# W 号段（Phase 5 占用，各 plan 分段不重叠）：
#   W-2026-10-03-25 —— 本脚本的锁屏 BLOCKED（XCUITest 需可交互会话，锁屏跑不了；
#                     解开条件 = 解锁后重跑本脚本）
#   W-2026-10-03-26 —— 备用：若执行期发现 Window 场景无法满足 SC-1 某属性需换
#                     Settings 场景，登记后按 UI-SPEC §7 重做，判据不放宽
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
# 先在**测试进程之外**清掉窗口 frame 记忆（cfprefsd 缓存让测试内的 defaults
# 清理不即时生效；SwiftUI Window 会把上次 frame 存进 com.local.pic 的
# "NSWindow Frame settings"，不清的话宽度断言读到上次的尺寸而非 defaultSize 的
# 780）。清了之后本会话内各测试开的窗都以默认宽度打开，断言可复现。
defaults delete com.local.pic "NSWindow Frame settings" 2>/dev/null || true

if alarm 600 xcodebuild -project Pic.xcodeproj -scheme Pic -destination 'platform=macOS' \
     CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual build > "$TMP/build.log" 2>&1; then
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

# 5. 解锁会话 → 跑测试（全部输出进 evidence；状态经 UITEST_STATUS 传递，
#    failed 也退出 0 —— RUNNER 的退出码只表达「流程走完」）
if alarm 600 xcodebuild -project Pic.xcodeproj -scheme Pic -destination 'platform=macOS' \
     CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual test > "$TMP/test.log" 2>&1; then
  echo "UITEST_TEST_RC=0" >> "$LOG"
  ST=passed
else
  echo "UITEST_TEST_RC=1" >> "$LOG"
  ST=failed
fi
cat "$TMP/test.log" >> "$LOG"
echo "UITEST_STATUS=$ST" >> "$LOG"
exit 0
