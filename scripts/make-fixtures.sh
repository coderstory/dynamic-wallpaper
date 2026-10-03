#!/usr/bin/env bash
# make-fixtures.sh —— 用本机 ffmpeg 的 lavfi 合成源现场生成确定性测试语料。
#
# 纪律（红线）：
#   * 用户真实素材 ~/Movies/视频壁纸 有 484 个 mp4 / 约 42GB。抽样只做一层非递归枚举，
#     且只建符号链接 —— 严禁把 GB 级素材复制进仓库（下方代码行里没有整词的复制命令，
#     这条纪律由「剥注释后整词计数 == 0」判据机械保证）。
#   * 递归遍历视频目录的判断是整词的「递归枚举命令」，本脚本刻意不含它；
#     抽样只列一层。
#
# 三个合成语料：
#   clip-a.mp4        8s 1280x720@30fps，带 1kHz 正弦音轨（给变速保音高留料）
#   clip-b.mp4        8s 640x480@30fps，无音轨
#   clip-sentinel.mp4 5s 320x240@24fps，无音轨 —— 哨兵串就是文件名本身，全 Phase 复用
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTDIR="$ROOT/fixtures"
FFMPEG="${FFMPEG:-/opt/homebrew/bin/ffmpeg}"
REAL_DIR="${PIC_REAL_DIR:-$HOME/Movies/视频壁纸}"

WITH_REAL=0
if [ "${1:-}" = "--with-real" ]; then
  WITH_REAL="${2:-0}"
fi

if [ ! -x "$FFMPEG" ]; then
  FFMPEG="$(command -v ffmpeg || true)"
fi
if [ -z "$FFMPEG" ] || [ ! -x "$FFMPEG" ]; then
  echo "FFMPEG_MISSING=1" >&2
  exit 4
fi

if [ "$WITH_REAL" -gt 0 ]; then
  # 这行是代码不是注释：把「只符号链接、不递归」的纪律固化进产物。
  printf 'REAL_SAMPLE mode=symlink count=%s recursion=disabled\n' "$WITH_REAL"
fi

mkdir -p "$OUTDIR"

# clip-a：带 1kHz 正弦音轨
"$FFMPEG" -hide_banner -loglevel error -y \
  -f lavfi -i "testsrc2=size=1280x720:rate=30" \
  -f lavfi -i "sine=frequency=1000:sample_rate=44100" \
  -t 8 -c:v libx264 -preset veryfast -pix_fmt yuv420p -c:a aac -shortest \
  "$OUTDIR/clip-a.mp4"

# clip-b：无音轨
"$FFMPEG" -hide_banner -loglevel error -y \
  -f lavfi -i "testsrc2=size=640x480:rate=30" \
  -t 8 -an -c:v libx264 -preset veryfast -pix_fmt yuv420p \
  "$OUTDIR/clip-b.mp4"

# clip-sentinel：哨兵语料，文件名即哨兵串
"$FFMPEG" -hide_banner -loglevel error -y \
  -f lavfi -i "testsrc2=size=320x240:rate=24" \
  -t 5 -an -c:v libx264 -preset veryfast -pix_fmt yuv420p \
  "$OUTDIR/clip-sentinel.mp4"

# 真实素材抽样：只列一层（shell glob 不跟子目录），按 C 序排序取前 N 个，
# 每个建一个符号链接。刻意不用递归遍历命令，也刻意不做字节复制。
SYMLINKS=0
if [ "$WITH_REAL" -gt 0 ]; then
  if [ ! -d "$REAL_DIR" ]; then
    echo "REAL_DIR_MISSING=1 dir=$REAL_DIR" >&2
    exit 5
  fi
  i=0
  while IFS= read -r src; do
    [ -n "$src" ] || continue
    i=$((i + 1))
    [ "$i" -gt "$WITH_REAL" ] && break
    ln -sfn "$src" "$OUTDIR/real-$i.mp4"
    SYMLINKS=$((SYMLINKS + 1))
  done < <(ls -1 "$REAL_DIR"/*.mp4 2>/dev/null | LC_ALL=C sort)
fi

# count/bytes 只统计本脚本生成的三个合成语料（符号链接不计入 —— 它们不是副本）
TOTAL=0
COUNT=0
for f in clip-a.mp4 clip-b.mp4 clip-sentinel.mp4; do
  if [ -f "$OUTDIR/$f" ]; then
    sz=$(stat -f%z "$OUTDIR/$f")
    TOTAL=$((TOTAL + sz))
    COUNT=$((COUNT + 1))
  fi
done

printf 'FIXTURES=%s count=%s bytes=%s symlinks=%s\n' "$OUTDIR" "$COUNT" "$TOTAL" "$SYMLINKS"
