#!/usr/bin/env bash
# MANUAL ONLY —— 本脚本绝不挂 test.sh / swift test / 任何自动验证路径。
# 原因是一次 libvmaf 实测（n_threads=8）跑出过 779.9% CPU；挂在常规校验里等于每次校验烤一次机。
#
# 降载：-t 5 -threads 2，跑前先确认预期单核以上占用，随时 Ctrl-C。
# 抽样：真实目录只 ls 一层取前三个名字，禁止递归遍历（42GB/484 文件）。
set -u
export LC_ALL=C

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; return 0; }
trap cleanup EXIT INT TERM

alarm() { perl -e "alarm $1; exec @ARGV" "${@:2}"; }

echo "MANUAL ONLY — 本脚本绝不挂 test.sh / 任何自动验证路径（STATE.md ffmpeg 红线）"
echo "降载：-t 5 -threads 2；跑前确认：预期单核以上占用，可 Ctrl-C 中断"
echo ""

SRC_DIR="$HOME/Movies/视频壁纸"
FFMPEG="$(command -v ffmpeg || true)"
if [ -z "$FFMPEG" ]; then
  echo "BENCH_SKIP reason=ffmpeg-missing"
  exit 0
fi

# 一层抽样，不递归。
if [ ! -d "$SRC_DIR" ]; then
  echo "BENCH_SRC=missing"
  exit 0
fi
SAMPLES=()
while IFS= read -r name; do
  SAMPLES+=("$SRC_DIR/$name")
  [ "${#SAMPLES[@]}" -ge 3 ] && break
done < <(ls -1 "$SRC_DIR" | head -n 3)

if [ "${#SAMPLES[@]}" -eq 0 ]; then
  echo "BENCH_SRC=empty"
  exit 0
fi

# 核对项 ①：out_time_ms 是微秒（5 秒段收尾 ≈ 5000000）。只解码不编码，负载极低。
echo "--- 核对 out_time_ms 语义（-f null，解码即弃，不编码）---"
alarm 120 "$FFMPEG" -nostdin -ss 30 -t 5 -threads 2 -i "${SAMPLES[0]}" \
  -f null - -progress pipe:1 -nostats 2>/dev/null | grep '^out_time_ms=' | tail -1 \
  | sed 's/^/BENCH_PROGRESS_RAW /'
echo ""

# 阈值是行业经验值，不是本机实测结论 —— 人工复核后再采纳。采纳则改 Sources/PicCore/Transcode/TranscodeCommand.swift
# 的 baselineCRF / baselinePreset，并同 commit 更新 TranscodeCommandTests 测试 3。
SSIM_MIN=0.98
VMAF_MIN=95
CRFS="16 18 20"
PRESETS="medium slow"
RESULTS="$TMP/results.tsv"
: > "$RESULTS"

echo "--- 编码矩阵（每个样本 × 每档 CRF × 每 preset，5 秒段）---"
for src in "${SAMPLES[@]}"; do
  for crf in $CRFS; do
    for preset in $PRESETS; do
      out="$TMP/out_c${crf}_p${preset}.mp4"
      # argv 形状与 TranscodeCommand.arguments 同源 —— 参数族一致，bench 才有意义。
      start=$(date +%s)
      alarm 300 "$FFMPEG" -nostdin -y -ss 30 -t 5 -threads 2 -i "$src" \
        -map 0:v:0 -map 0:a:0? \
        -c:v libx264 -preset "$preset" -crf "$crf" -pix_fmt yuv420p \
        -c:a aac -b:a 192k -sn -dn "$out" >/dev/null 2>&1
      rc=$?
      end=$(date +%s)
      echo "BENCH_TIME crf=$crf preset=$preset seconds=$((end - start))"
      echo "BENCH_TIME_NOTE rosetta=x86_64-binary comparative-only"
      if [ "$rc" -ne 0 ] || [ ! -s "$out" ]; then
        echo "BENCH crf=$crf preset=$preset ssim=na vmaf=na size_kb=na (encode failed rc=$rc)"
        continue
      fi
      ssim=$(alarm 300 "$FFMPEG" -nostdin -ss 30 -t 5 -i "$src" -i "$out" \
        -lavfi "[0:v][1:v]ssim" -f null - 2>&1 | grep -o 'All:[0-9.]*' | tail -1 | cut -d: -f2)
      vmaf=$(alarm 300 "$FFMPEG" -nostdin -ss 30 -t 5 -i "$src" -i "$out" \
        -lavfi "[0:v][1:v]libvmaf" -f null - 2>&1 | grep -o 'VMAF score: [0-9.]*' | tail -1 | awk '{print $NF}')
      size_kb=$(( $(stat -f%z "$out") / 1024 ))
      echo "BENCH crf=$crf preset=$preset ssim=${ssim:-na} vmaf=${vmaf:-na} size_kb=$size_kb"
      printf '%s %s %s %s\n' "$crf" "$preset" "${ssim:-0}" "${vmaf:-0}" >> "$RESULTS"
    done
  done
done

# 采纳建议：达标档里取最大 CRF。同一档在多个样本上都达标才算该档可用。
echo "--- 达标档（ssim>=$SSIM_MIN vmaf>=$VMAF_MIN）---"
BEST="未定"
for crf in $CRFS; do
  for preset in $PRESETS; do
    rows=$(awk -v c="$crf" -v p="$preset" '$1==c && $2==p' "$RESULTS" | wc -l | tr -d ' ')
    [ "$rows" -eq 0 ] && continue
    hit=$(awk -v c="$crf" -v p="$preset" -v t1="$SSIM_MIN" -v t2="$VMAF_MIN" \
      '$1==c && $2==p && ($3+0 >= t1+0) && ($4+0 >= t2+0)' "$RESULTS" | wc -l | tr -d ' ')
    [ "$hit" -eq "$rows" ] || continue
    BEST="$crf@$preset"
    echo "  全样本达标：crf=$crf preset=$preset"
  done
done
echo "BENCH_RECOMMEND highest_crf_meeting ssim>=$SSIM_MIN vmaf>=$VMAF_MIN = $BEST"
echo "采纳则改 Sources/PicCore/Transcode/TranscodeCommand.swift 的 baselineCRF/baselinePreset 并同 commit 更新 TranscodeCommandTests 测试 3"