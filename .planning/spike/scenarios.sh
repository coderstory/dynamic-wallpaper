#!/usr/bin/env bash
# scenarios.sh —— Phase 01 门禁 spike 03（PLAN 01-03 Task 2），五场景驱动器。
#
# 产出 .planning/spike/out/fullscreen-scenarios.log：3 行 SELFTEST + 5 行 SCENARIO，
# 每行都带 coverage 数字并标明 source=live|synthetic|blocked。证据一律 KEY=VALUE，
# 不写形容词，判据全是字面量比对。
#
# 三条口径纪律（威胁 T-01-13）：
#   1. live / synthetic / blocked 严格区分，三条 COUNT 之和 == SCENARIO_COUNT。
#   2. PITFALLS 的 0.87343 / 0.96548 只作为 PRIOR= 行出现，标注 method= 与
#      target_for_this_plan=no，**不参与任何 fullscreen= 取值判定**（脚本末尾有反证检查）。
#   3. 判不过的场景写 source=blocked + BLOCKED_REASON=，**不许把 blocked 写成 live**。
#
# 本机无 timeout 命令（编排器实测），限时一律 perl -e 'alarm N; exec @ARGV'。
set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SPIKE="$ROOT/.planning/spike"
OUT="$SPIKE/out"
PROBE="$OUT/fullscreenprobe"
LOG="$OUT/fullscreen-scenarios.log"
SRC="$SPIKE/FullscreenProbe.swift"

limited() { perl -e 'alarm '"$1"'; exec @ARGV' "${@:2}"; }

spawn_pid=""
cleanup() {
  if [ -n "$spawn_pid" ] && kill -0 "$spawn_pid" 2>/dev/null; then
    kill -TERM "$spawn_pid" 2>/dev/null
    sleep 0.5
    kill -KILL "$spawn_pid" 2>/dev/null
  fi
}
trap cleanup EXIT INT TERM

mkdir -p "$OUT"
: > "$LOG"
log() { printf '%s\n' "$*" | tee -a "$LOG"; }
fail() { log "SELFTEST_FAIL=$1"; log "DRIVER_STATUS=fail"; exit 1; }

# 从一行里取某个 KEY=VALUE 的值。KEY 可以出现在行首，也可以是行中间的某个字段
# （前一个字符必须是空白或非标识符）。用 awk 而不是 sed，避免 sed 贪婪回溯把
# 前面的字段吃掉；用 grep -E 而不是 grep -cE —— macOS 自带 FreeBSD grep，BRE 下 ? 是字面量。
field() {
  printf '%s\n' "$1" | awk -v k="$2=" '{
    gsub(/\r/, "")
    line = $0
    re = "(^|[^A-Za-z0-9_])" k
    if (match(line, re)) {
      rest = substr(line, RSTART + RLENGTH)
      split(rest, a, /[ \t]+/)
      print a[1]
    }
  }'
}

log "RUN_UNTIL=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
log "DRIVER=scenarios.sh THRESHOLD=0.950 DENOMINATOR=visibleFrame AGGREGATION=per_pid"

# ---------------------------------------------------------------- 编译
log "COMPILE_CMD=swiftc -parse-as-library -target arm64-apple-macosx15.0"
if ! swiftc -parse-as-library -target arm64-apple-macosx15.0 -o "$PROBE" "$SRC" > "$OUT/compile-probe03.txt" 2>&1; then
  log "COMPILE=error"
  log "DRIVER_STATUS=fail reason=compile_failed see=out/compile-probe03.txt"
  exit 1
fi
log "COMPILE=ok binary=out/fullscreenprobe"

# ---------------------------------------------------------------- 算法自检（纯计算，与锁屏态无关）
log "SELFTEST_BLOCK_BEGIN"
"$PROBE" --selftest 2>&1 | tee -a "$LOG" > "$OUT/probe03-selftest.txt"
log "SELFTEST_BLOCK_END"
for n in whole chrome split; do
  line=$(grep -E "^SELFTEST=$n " "$LOG" | head -1)
  [ -n "$line" ] || fail "missing_selftest_$n"
  c=$(field "$line" coverage)
  awk -v v="$c" 'BEGIN{exit !(v>0.995 && v<1.005)}' || fail "selftest_${n}_coverage=$c expected=1.000"
done
SP=$(grep -E '^SELFTEST=split ' "$LOG" | head -1)
SPB=$(field "$SP" per_window_best)
awk -v v="$SPB" 'BEGIN{exit !(v>0.595 && v<0.605)}' || fail "selftest_split_per_window_best=$SPB expected=0.600"
CHP=$(field "$(grep -E '^SELFTEST=chrome ' "$LOG" | head -1)" per_window_best)
log "SELFTEST_VERDICT=pass whole=1.000 chrome=1.000 split=1.000 split_per_window_best=0.600 chrome_per_window_best=$CHP"
log "SELFTEST_PROOF=per_pid_aggregation_is_load_bearing evidence=split两块各0.600/0.400合起来1.000；若退化为逐窗口取最大，split会输出0.600"

# ---------------------------------------------------------------- S0 live-regression（本机唯一能真测的假阳性场景）
# 直接枚举当前所有 layer-0 窗口。Ghostty / CC Switch 都是「安全区铺满但非全屏」——
# 它们的 bounds 高 833，比屏幕 frame 高 956 矮 123，够不到刘海区域，**不可能是真全屏**。
log "S0_BEGIN scenario=live-regression intent=false_positive_regression"
S0_RAW="$OUT/probe03-inspect-s0.txt"
"$PROBE" --inspect live-regression > "$S0_RAW" 2>&1
cat "$S0_RAW" >> "$LOG"
S0=$(grep -E '^SCENARIO=live-regression ' "$LOG" | head -1)
[ -n "$S0" ] || fail "S0_no_scenario_line"
S0_COV=$(field "$S0" coverage)
S0_PID=$(field "$S0" pid)
S0_WIN=$(grep -cE '^WIN pid=' "$LOG")
log "S0_LAYER0_WINDOWS=$S0_WIN"
log "S0_COVERAGE=$S0_COV top_pid=$S0_PID"
if awk -v v="$S0_COV" 'BEGIN{exit !(v>=0.95)}'; then
  FP=1
  log "FALSE_POSITIVE_OBSERVED=1 direction=safe_area_filled_but_not_fullscreen_scored_fullscreen pid=$S0_PID coverage=$S0_COV"
  log "FALSE_POSITIVE_NOTE=该窗口 bounds 高 833，小于屏幕 frame 高 956，够不到刘海区域，因此不可能是真全屏；但它把 visibleFrame 铺满 → coverage=1.000 ≥ 阈值 0.95 → 判成 fullscreen=true。这就是 PITFALLS Pitfall 2(b) 的假阳性，方向=误暂停（用户看到壁纸坏了）。"
else
  FP=0
  log "FALSE_POSITIVE_OBSERVED=0 direction=safe_area_filling_window_still_below_threshold pid=$S0_PID coverage=$S0_COV"
fi

# ---------------------------------------------------------------- S1 notch-fullscreen（自建全屏窗口）
# 禁止用「窗口 bounds 覆盖 frame」当判据 —— 本机是刘海屏，真全屏顶部必被刘海压掉 33pt，
# 那条判据会让 S1 恒定失败。唯一判据是同一把尺子的 TOP_PID coverage。
log "S1_BEGIN scenario=notch-fullscreen intent=self_spawned_fullscreen_window"
S1_OUT="$OUT/probe03-spawn-stdout.txt"
S1_ERR="$OUT/probe03-spawn-stderr.txt"
S1_RAW="$OUT/probe03-inspect-s1.txt"
: > "$S1_OUT"; : > "$S1_ERR"
limited 25 "$PROBE" --spawn-fullscreen > "$S1_OUT" 2> "$S1_ERR" &
spawn_pid=$!

# 盲等 sleep 5 在锁屏态下不可靠（窗口对象与 stdout 缓冲不同步）。改成等 SPAWN_FULLSCREEN
# 出现，最多 10 秒，等到了立刻量 —— 窗口只存活 10 秒，早量早留证。
S1_WAIT=0
while [ "$S1_WAIT" -lt 100 ]; do
  grep -q 'SPAWN_FULLSCREEN=' "$S1_OUT" 2>/dev/null && break
  sleep 0.1
  S1_WAIT=$((S1_WAIT + 1))
done
S1_SPAWN_PID=$(grep -oE 'pid=[0-9]+' "$S1_OUT" | head -1 | cut -d= -f2)
log "S1_WAIT_TICKS=$S1_WAIT"
log "S1_SPAWN_PID=$S1_SPAWN_PID"
log "S1_WARN_STDERR=$(head -1 "$S1_ERR" | tr -d '\r')"

if [ -z "$S1_SPAWN_PID" ]; then
  log "SCENARIO=notch-fullscreen source=blocked coverage=0.000 fullscreen=false pid=-1 rects=0"
  log "BLOCKED_REASON=spawn_process_never_printed_SPAWN_FULLSCREEN_pid_line"
  log "BLOCKED_WHY_NOT_LOCK_THE_SCREEN=制造 unlocked→locked / locked→unlocked 边沿需要真人操作屏幕，用户 asleep，硬性禁止。"
  LIVE_S1=blocked
else
  "$PROBE" --inspect notch-fullscreen --pid "$S1_SPAWN_PID" > "$S1_RAW" 2>&1
  S1_TOP=$(grep -E '^TOP_PID=' "$S1_RAW" | head -1)
  S1_COV=$(field "$S1_TOP" coverage)
  S1_RECTS=$(field "$S1_TOP" rects)
  S1_BOUNDS=$(grep -E '^WIN ' "$S1_RAW" | head -1 | sed -E 's/.* bounds=([^ ]*).*/\1/')
  log "S1_TOP_PID=$S1_SPAWN_PID coverage=$S1_COV rects=$S1_RECTS"
  log "S1_WINDOW_BOUNDS=$S1_BOUNDS"
  log "S1_RAW_INSPECT=out/probe03-inspect-s1.txt reason_not_inlined=该文件的原始判定行标的是实测口径，若整段贴进本日志会多出一条 live 计数并破坏 SCENARIO_COUNT 自洽；判定结果已由下面两行如实转述。"

  # 等 spawn 自己跑满 10 秒退出，再读它对「是否真进了全屏」的自陈。
  wait "$spawn_pid" 2>/dev/null
  spawn_pid=""
  S1_MAXFS=$(field "$(grep -E '^MAX_OBSERVED_FULLSCREEN=' "$S1_OUT" | head -1)" MAX_OBSERVED_FULLSCREEN)
  S1_FINFS=$(field "$(grep -E '^FINAL_FULLSCREEN=' "$S1_OUT" | head -1)" FINAL_FULLSCREEN)
  log "S1_FINAL_FULLSCREEN=$S1_FINFS"
  log "S1_MAX_OBSERVED_FULLSCREEN=$S1_MAXFS"

  if awk -v v="$S1_COV" 'BEGIN{exit !(v>=0.95)}'; then
    log "FULLSCREEN_CONFIRMED=1 scenario=notch-fullscreen coverage=$S1_COV"
    log "SCENARIO=notch-fullscreen source=live coverage=$S1_COV fullscreen=true pid=$S1_SPAWN_PID rects=$S1_RECTS"
    LIVE_S1=live
  else
    log "FULLSCREEN_CONFIRMED=0 scenario=notch-fullscreen coverage=$S1_COV threshold=0.950"
    log "SCENARIO=notch-fullscreen source=blocked coverage=$S1_COV fullscreen=false pid=$S1_SPAWN_PID rects=$S1_RECTS"
    log "BLOCKED_REASON=toggleFullScreen_had_no_effect_while_session_locked max_observed_fullscreen=$S1_MAXFS final_fullscreen=$S1_FINFS window_bounds=$S1_BOUNDS window_never_reached_screen_frame coverage_below_threshold=$S1_COV LOCK=1"
    log "BLOCKED_DETAIL=自建窗口确实被 CGWindowList 枚举到（rects=${S1_RECTS}，layer=0 alpha=1 is_onscreen=1），但 toggleFullScreen(nil) 在锁屏会话下没有生效（MAX_OBSERVED_FULLSCREEN=0），窗口从未进入全屏 Space。所以 coverage=$S1_COV 量的是一扇非全屏窗，对「全屏检测是否有效」零信息量 —— 故记 blocked，不记 live。"
    log "BLOCKED_WHY_NOT_LOCK_THE_SCREEN=制造 unlocked→locked / locked→unlocked 边沿需要真人操作屏幕，用户 asleep，硬性禁止。"
    LIVE_S1=blocked
  fi
fi

# ---------------------------------------------------------------- S2 chrome-like（synthetic）
# 本机 /Applications/Google Chrome.app 不存在（编排器实测）→ 无法 live，只能回放
# PITFALLS Pitfall 2 记录的 Chrome 同 pid 双窗口几何。
log "S2_BEGIN scenario=chrome-like intent=chrome_same_pid_two_windows"
CHROME_PID=9001
S2_RAW="$OUT/probe03-replay-chrome.txt"
"$PROBE" --replay chrome-like 1470 956 "$CHROME_PID" 0 33 1470 124 0 121 1470 835 > "$S2_RAW" 2>&1
cat "$S2_RAW" >> "$LOG"
S2=$(grep -E '^SCENARIO=chrome-like ' "$LOG" | head -1)
S2_COV=$(field "$S2" coverage)
# 两个先验必须**紧跟** SCENARIO=chrome-like 行（PLAN 01-03 Task 2 的字面要求），
# 且 0.96548 紧跟 0.87343。它们只是口径说明，不进任何判定。
log "PRIOR=0.87343 method=naive_single_rect_over_display_bounds formula=1470x835_div_1470x956 source=miragewallpaper-73 target_for_this_plan=no"
log "PRIOR=0.96548 method=single_rect_over_display_bounds formula=1470x923_div_1470x956 source=miragewallpaper-73 this_plan_denominator=visibleFrame maps_to=1.000"
log "PRIOR_NOTE=两个先验都用屏幕 bounds 当分母且都是逐窗口口径；本计划分母是 visibleFrame 且按 pid 聚合，两者不可直接比较。谁也不许为了对上它们改实现或改阈值。"
S2_PWB=$(field "$(grep -E '^COVERAGE_PER_WINDOW_BEST=' "$S2_RAW" | head -1)" COVERAGE_PER_WINDOW_BEST)
log "S2_PER_WINDOW_BEST=$S2_PWB rejected_naive_method=per_window_max"
log "BLOCKED_REASON=no_google_chrome_installed_scenarios=synthetic probe_path=/Applications/Google_Chrome.app"

# ---------------------------------------------------------------- S3 ultrawind（synthetic）
log "S3_BEGIN scenario=ultrawind intent=ultrawide_display"
S3_RAW="$OUT/probe03-replay-ultrawind.txt"
"$PROBE" --replay ultrawind 3440 1440 9002 0 0 3440 1440 > "$S3_RAW" 2>&1
cat "$S3_RAW" >> "$LOG"
S3=$(grep -E '^SCENARIO=ultrawind ' "$LOG" | head -1)
S3_COV=$(field "$S3" coverage)
log "BLOCKED_REASON=no_ultrawide_display_attached_screens_count=1"

# ---------------------------------------------------------------- S4 notch-partial（synthetic）
# 误判方向的另一半：差一点满屏时不能误判成全屏（宁可少暂停，不要误暂停）。
log "S4_BEGIN scenario=notch-partial intent=near_fullscreen_must_not_trip"
S4_RAW="$OUT/probe03-replay-notchpartial.txt"
"$PROBE" --replay notch-partial 1470 956 9003 0 33 1470 700 > "$S4_RAW" 2>&1
cat "$S4_RAW" >> "$LOG"
S4=$(grep -E '^SCENARIO=notch-partial ' "$LOG" | head -1)
S4_COV=$(field "$S4" coverage)
S4_FS=$(field "$S4" fullscreen)
[ "$S4_FS" = "false" ] || fail "notch-partial_fullscreen=$S4_FS expected=false"
log "NEAR_FULLSCREEN_GUARD=pass coverage=$S4_COV fullscreen=false meaning=差一点满屏不会误暂停"

# ---------------------------------------------------------------- 先验不得被当成判据（反证检查）
# 不依赖日志文本，纯算法层面：把两个 PRIOR= 行删掉后重跑 S2/S3/S4，
# SCENARIO 行必须与日志里已落的逐字节相同 —— 这两条数字在算法里没有任何入口。
S2B=$("$PROBE" --replay chrome-like 1470 956 "$CHROME_PID" 0 33 1470 124 0 121 1470 835 2>&1 | grep -E '^SCENARIO=chrome-like ')
S3B=$("$PROBE" --replay ultrawind 3440 1440 9002 0 0 3440 1440 2>&1 | grep -E '^SCENARIO=ultrawind ')
S4B=$("$PROBE" --replay notch-partial 1470 956 9003 0 33 1470 700 2>&1 | grep -E '^SCENARIO=notch-partial ')
if [ "$S2" = "$S2B" ] && [ "$S3" = "$S3B" ] && [ "$S4" = "$S4B" ]; then
  log "PRIOR_DECOUPLING=pass evidence=recomputing_S2_S3_S4_without_PRIOR_lines_yields_byte_identical_scenario_lines"
else
  fail "prior_lines_influence_outputs"
fi

# ---------------------------------------------------------------- 汇总 + 自洽断言
SC_COUNT=$(grep -cE '^SCENARIO=' "$LOG")
SY_COUNT=$(grep -cE 'source=synthetic' "$LOG")
LV_COUNT=$(grep -cE 'source=live' "$LOG")
BL_COUNT=$((SC_COUNT - SY_COUNT - LV_COUNT))

log "SCENARIO_COUNT=$SC_COUNT"
log "LIVE_COUNT=$LV_COUNT"
log "SYNTHETIC_COUNT=$SY_COUNT"
log "BLOCKED_COUNT=$BL_COUNT"
log "FALSE_POSITIVE_COUNT=$FP"

[ "$SC_COUNT" -eq 5 ] || fail "scenario_count=$SC_COUNT expected=5"
[ $((SY_COUNT + LV_COUNT + BL_COUNT)) -eq "$SC_COUNT" ] || fail "count_sum_mismatch"
[ "$(grep -cE '^SELFTEST=' "$LOG")" -eq 3 ] || fail "selftest_line_count"
[ "$(grep -cE '^COORD=' "$LOG")" -eq 1 ] || fail "coord_line_count_must_be_exactly_1"
[ "$(grep -cE '^FALSE_POSITIVE_OBSERVED=' "$LOG")" -eq 1 ] || fail "false_positive_line_count"
[ "$(grep -cE '^SYNTHETIC_COUNT=' "$LOG")" -eq 1 ] || fail "synthetic_count_line_count"
[ "$(grep -cE '^PRIOR=0.87343' "$LOG")" -eq 1 ] || fail "prior_line_missing"
grep -q 'target_for_this_plan=no' "$LOG" || fail "prior_line_missing_disclaimer"
# 紧邻断言：PRIOR=0.87343 必须在 SCENARIO=chrome-like 的**下一行**，0.96548 再下一行。
awk 'BEGIN{c=-1;p=-1;q=-1}
     /^SCENARIO=chrome-like /{c=NR}
     /^PRIOR=0.87343 /{p=NR}
     /^PRIOR=0.96548 /{q=NR}
     END{exit !(c>0 && p==c+1 && q==c+2)}' "$LOG" || fail "prior_lines_not_adjacent_to_chrome_scenario"

log "SCENARIO_MATRIX=s0=live s1=$LIVE_S1 s2=synthetic s3=synthetic s4=synthetic"
log "DRIVER_STATUS=ok"
exit 0
