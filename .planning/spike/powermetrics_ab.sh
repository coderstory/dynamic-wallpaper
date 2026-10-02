#!/usr/bin/env bash
# powermetrics_ab.sh —— Phase 01 门禁 spike，一次性 throwaway A/B 驱动（D-07）。
#
# 目的：为「isOpaque = true 省不省电」产出 mW 数字，而不是形容词。
# 四组固定顺序，mode 与 WallpaperSpike 的解析表逐字对齐：
#   1 none            窗口在，不解码（基线）
#   2 v1              isOpaque = true + AVPlayerLayer（Phase 2 的生产配置）
#   3 transparent     isOpaque = false + 同一个 AVPlayerLayer
#   4 avplayerview    AVKit.AVPlayerView（对照组，产品不采用）
#
# 安全形状（T-01-08）：脚本自身以普通用户运行，只对**单条** powermetrics 命令加 sudo。
# 绝不用 `sudo bash powermetrics_ab.sh` —— 那等于把仓库代码的执行权交给 root。
# 开头 sudo -v 一次把凭据缓存住，四组复用，不再重复提示。
#
# 有效性（T-01-09）：每组开跑前用 windowprobe --pid 断言我方窗口仍在桌面层；
# 不在则该组标 invalid 并跳过，绝不用 0 mW 参与均值（0 会把均值拉到虚假低位）。
#
# 用法：
#   bash .planning/spike/powermetrics_ab.sh --dry-run
#   bash .planning/spike/powermetrics_ab.sh --seconds 300
#   bash .planning/spike/powermetrics_ab.sh --parse-selftest <rawfile>

set -uo pipefail

SPIKE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$SPIKE_DIR/out"
SPIKE_BIN="$OUT/wallpaperspike"
PROBE_BIN="$OUT/windowprobe"
EXPECTED_LEVEL=-2147483623
AB_GROUPS=(none v1 transparent avplayerview)

DRY_RUN=0
SECONDS_PER_GROUP=300
VIDEO_ARG=""
RAW_OVERRIDE=""
SPIKE_PID=""

log() { printf '%s\n' "$*" >&2; }

cleanup() {
  if [ -n "$SPIKE_PID" ] && kill -0 "$SPIKE_PID" 2>/dev/null; then
    kill "$SPIKE_PID" 2>/dev/null || true
    wait "$SPIKE_PID" 2>/dev/null || true
  fi
  SPIKE_PID=""
}
trap cleanup EXIT INT TERM

# 从 powermetrics 原始输出里取 CPU/GPU 功耗均值。
# awk 自己维护计数与总和 —— powermetrics 的输出里 mW 与 mWh 混杂，不能靠 wc -l。
parse_raw() {
  awk '
    function numval(   i) {
      for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+(\.[0-9]+)?$/) return $i + 0
      return -1
    }
    /CPU[ \t]+Power:/ { v = numval(); if (v >= 0) { cpusum += v; cpucount++ } }
    /GPU[ \t]+Power:/ { v = numval(); if (v >= 0) { gpusum += v; gpucount++ } }
    END {
      printf "CPU_MW_AVG=%.3f\n", (cpucount > 0 ? cpusum / cpucount : 0)
      printf "CPU_SAMPLES=%d\n", cpucount
      printf "GPU_MW_AVG=%.3f\n", (gpucount > 0 ? gpusum / gpucount : 0)
      printf "GPU_SAMPLES=%d\n", gpucount
    }
  ' "$1"
}

if [ "${1:-}" = "--parse-selftest" ]; then
  # 无需 root 的解析器自检：对着一个 raw 文件跑解析路径并打印 KEY=VALUE。
  parse_raw "${2:?raw file required}"
  exit 0
fi

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --seconds) SECONDS_PER_GROUP="${2:?}"; shift 2 ;;
    --video)   VIDEO_ARG="$2"; shift 2 ;;
    *) log "ABORT=unknown_arg:$1"; exit 64 ;;
  esac
done

[ -x "$SPIKE_BIN" ] || { log "ABORT=spike_binary_missing:$SPIKE_BIN"; exit 66; }
[ -x "$PROBE_BIN" ] || { log "ABORT=probe_binary_missing:$PROBE_BIN"; exit 66; }

SPIKE_SAMPLES=$(( SECONDS_PER_GROUP / 5 ))
[ "$SPIKE_SAMPLES" -ge 1 ] || SPIKE_SAMPLES=1

spike_cmd_for() {
  if [ -n "$VIDEO_ARG" ]; then
    printf '%s --mode %s --video %s' "$SPIKE_BIN" "$1" "$VIDEO_ARG"
  else
    printf '%s --mode %s' "$SPIKE_BIN" "$1"
  fi
}

if [ "$DRY_RUN" -eq 1 ]; then
  for g in "${AB_GROUPS[@]}"; do
    printf 'DRYRUN group=%s cmd=%s\n' "$g" "$(spike_cmd_for "$g")"
    printf 'DRYRUN_PM group=%s cmd=perl -e %s sudo powermetrics --samplers cpu_power,gpu_power -i 5000 -n %s > %s 2>&1\n' \
      "$g" "'alarm $((SECONDS_PER_GROUP + 60)); exec @ARGV'" "$SPIKE_SAMPLES" "$OUT/pow-$g.raw"
  done
  printf 'GROUP_COUNT=%s\n' "${#AB_GROUPS[@]}"
  printf 'SECONDS_PER_GROUP=%s\n' "$SECONDS_PER_GROUP"
  printf 'SPIKE_SAMPLES_PER_GROUP=%s\n' "$SPIKE_SAMPLES"
  printf 'EXPECTED_SELF_LEVEL=%s\n' "$EXPECTED_LEVEL"
  exit 0
fi

# ---- 真正采集 ----
# sudo -v 一次，四组复用（凭据缓存）
sudo -v || { log "ABORT=sudo_failed"; exit 77; }

JSON="$OUT/powermetrics-ab.json"
printf '[\n' > "$JSON"
FIRST=1

for g in "${AB_GROUPS[@]}"; do
  RAW="$OUT/pow-$g.raw"
  INVALID="null"
  CPU_AVG=0
  GPU_AVG=0
  SAMPLES=0

  log "GROUP_START=$g seconds=$SECONDS_PER_GROUP"

  # 1) 起 spike
  # shellcheck disable=SC2046
  $(spike_cmd_for "$g") > "$OUT/spike-$g-stdout.txt" 2> "$OUT/spike-$g-stderr.txt" &
  SPIKE_PID=$!
  sleep 5

  # 2) 断言我方窗口仍在桌面层（T-01-09）—— 同层级有第三方壁纸 app，只能按 pid 认领
  PROBE_OUT="$("$PROBE_BIN" --pid "$SPIKE_PID" 2>&1 || true)"
  SELF_LEVEL="$(printf '%s\n' "$PROBE_OUT" | sed -n 's/^SELF_LEVEL=//p' | head -1)"
  if [ "$SELF_LEVEL" != "$EXPECTED_LEVEL" ]; then
    INVALID="\"spike_window_missing\""
    log "GROUP_INVALID=$g reason=spike_window_missing SELF_LEVEL=${SELF_LEVEL:-none}"
  else
    # 3) 采样：stdout/stderr 直接重定向到文件，不接管道（ROADMAP Phase 6：管道吞退出码）
    #    限时用 perl alarm（本机没有 timeout 命令）
    perl -e 'alarm '"$((SECONDS_PER_GROUP + 60))"'; exec @ARGV' \
      sudo powermetrics --samplers cpu_power,gpu_power -i 5000 -n "$SPIKE_SAMPLES" \
      > "$RAW" 2>&1
    PM_RC=$?
    log "GROUP_POW_RC=$g rc=$PM_RC"

    PARSED="$(parse_raw "$RAW")"
    CPU_AVG="$(printf '%s\n' "$PARSED" | sed -n 's/^CPU_MW_AVG=//p')"
    GPU_AVG="$(printf '%s\n' "$PARSED" | sed -n 's/^GPU_MW_AVG=//p')"
    SAMPLES="$(printf '%s\n' "$PARSED" | sed -n 's/^CPU_SAMPLES=//p')"

    if [ "${SAMPLES:-0}" -eq 0 ]; then
      # 样本为 0 绝不记 0 mW —— 如实标 invalid
      INVALID="\"no_samples\""
      log "GROUP_INVALID=$g reason=no_samples"
    else
      log "GROUP_OK=$g cpu_mw_avg=$CPU_AVG gpu_mw_avg=$GPU_AVG samples=$SAMPLES"
    fi
  fi

  # 4) 收掉 spike
  cleanup

  [ "$FIRST" -eq 1 ] || printf ',\n' >> "$JSON"
  FIRST=0
  printf '  {"group": "%s", "mode": "%s", "seconds": %s, "cpu_mw_avg": %s, "gpu_mw_avg": %s, "samples": %s, "invalid": %s}' \
    "$g" "$g" "$SECONDS_PER_GROUP" "$CPU_AVG" "$GPU_AVG" "$SAMPLES" "$INVALID" >> "$JSON"
done

printf '\n]\n' >> "$JSON"

log "JSON_PATH=$JSON"
python3 -c "import json,sys; d=json.load(open(sys.argv[1])); assert len(d)==4, d" "$JSON" \
  && log "JSON_VALID=1 elements=4" \
  || { log "JSON_VALID=0"; exit 78; }
