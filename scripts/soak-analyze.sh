#!/usr/bin/env bash
# soak-analyze.sh —— 对 soak.log 做**线性拟合**，给 SC5 长跑一个数字化判词：
#
#   bash scripts/soak-analyze.sh <soak.log>
#
# 阈值全是写死的数字，改阈值 = 改这一行并留 git 历史（不许写进「显著」「明显」）。
# 判词四态，「数据不够」的三种形态（invalid / insufficient / fail-by-missing）
# 都不许被算成 pass —— 长跑最有价值的结论是「这次跑不算数」，而不是「看起来还行」。
#
# 判定序：insufficient → invalid → fail → pass。第一条命中的即判词，
# 后面的检查不再改写它（gap 序列判 fail 就是这个序被写错的表现）。

set -u
export LC_ALL=C

LOG="${1:-}"
if [ ! -f "$LOG" ]; then
  printf 'SOAK_VERDICT=invalid\n'
  printf 'SOAK_REASON=no_such_log\n'
  exit 1
fi

# 行格式是 soak-sampler.sh 的契约，两处漂移会让全部判据失明。
awk '
function med(a,   n, i, j, t) {
  n = 0
  for (i in a) n++
  for (i = 2; i <= n; i++) {          # 插入排序：样本数是小时级，n² 无所谓
    t = a[i]; j = i - 1
    while (j >= 1 && a[j] > t) { a[j+1] = a[j]; j-- }
    a[j+1] = t
  }
  if (n % 2) return a[(n+1)/2]
  return (a[n/2] + a[n/2+1]) / 2
}

{
  ts = rss = fd = crashes = sleeps = wakes = missing = ""
  for (i = 1; i <= NF; i++) {
    if ($i ~ /^ts=/)       ts       = substr($i, 4)
    else if ($i ~ /^rss=/)    rss      = substr($i, 5)
    else if ($i ~ /^fd=/)     fd       = substr($i, 4)
    else if ($i ~ /^crashes=/)  crashes  = substr($i, 9)
    else if ($i ~ /^sleeps=/)   sleeps   = substr($i, 8)
    else if ($i ~ /^wakes=/)    wakes    = substr($i, 7)
    else if ($i ~ /^missing=/)  missing  = substr($i, 9)
  }
  if (ts == "" || ts !~ /^[0-9]+$/) next
  n++
  T[n] = ts + 0
  R[n] = (rss ~ /^[0-9]+$/      ? rss + 0 : 0)
  F[n] = (fd ~ /^[0-9]+$/       ? fd + 0 : 0)
  if (n == 1) { firstR = R[1]; firstC = crashes; firstS = sleeps; firstW = wakes }
  lastR = R[n]; lastC = crashes; lastS = sleeps; lastW = wakes
  if (missing == "1") miss++
  if (crashes ~ /^[0-9]+$/ && n == 1) firstC = crashes + 0
  if (sleeps  ~ /^[0-9]+$/ && n == 1) firstS = sleeps + 0
  if (wakes   ~ /^[0-9]+$/ && n == 1) firstW = wakes + 0
}

END {
  if (n == 0) {
    print "SOAK_LINES=0"
    print "SOAK_VERDICT=insufficient"
    print "SOAK_REASON=no_parsable_lines"
    exit
  }

  hours = (T[n] - T[1]) / 3600
  printf "SOAK_LINES=%d\n", n
  printf "SOAK_HOURS=%.1f\n", hours

  # ---- 连续性：日志条目数 < 期望小时数 × 0.95 → 采样器自身不可信，结论作废 ----
  expected = int(hours + 0.0000001)
  if (expected < 1) expected = 1
  if (n < expected * 0.95) {
    printf "SOAK_CONTINUITY=gap(%d/%d)\n", n, expected
    cont_gap = 1
  } else {
    print "SOAK_CONTINUITY=ok"
  }

  printf "SOAK_MISSING=%d\n", miss + 0
  crash_delta = lastC - firstC
  sleep_delta = lastS - firstS
  wake_delta  = lastW - firstW
  printf "CRASH_DELTA=%d\n", crash_delta
  printf "SLEEPS_DELTA=%d\n", sleep_delta
  printf "WAKES_DELTA=%d\n", wake_delta

  # ---- 最小二乘斜率：(rss, fd) 对 ts。KB/s × 86400 / 1024 = MB/天 ----
  st = sr = sf = stt = str = stf = 0
  for (i = 1; i <= n; i++) {
    st += T[i]; sr += R[i]; sf += F[i]
    stt += T[i]*T[i]; str += T[i]*R[i]; stf += T[i]*F[i]
  }
  den = n*stt - st*st
  if (den == 0) { m_slope = 0; f_slope = 0 }
  else {
    m_slope = (n*str - st*sr) / den * 86400 / 1024
    f_slope = (n*stf - st*sf) / den * 86400
  }
  printf "MEM_SLOPE_MB_PER_DAY=%.2f\n", m_slope
  printf "FD_SLOPE_PER_DAY=%.2f\n", f_slope

  # ---- 漂移：首尾各 12 个样本的中位数之差（对单个抖动免疫，对单调上涨敏感）----
  h = 12; if (int(n/2) < h) h = int(n/2)
  if (h >= 1) {
    delete A; delete B
    for (i = 1; i <= h; i++) { A[i] = R[i]; B[i] = R[n-h+i] }
    m1 = med(A); m2 = med(B)
  } else { m1 = 0; m2 = 0 }
  drift = 0
  if (m1 > 0) drift = (m2 - m1) / m1 * 100
  printf "MEM_DRIFT_PCT=%+.1f\n", drift

  # ---- 判词 ----
  # invalid 必须最先判：缺口 >5% 说明采样器本身不可信，这份数据根本不是一份
  # 「样本不足」的短跑，而是「跑挂了却在假装跑」的 7 天。后者比前者严重得多。
  if (cont_gap) {
    verdict = "invalid"; reason = "continuity_gap"
  } else if (n < 24) {
    verdict = "insufficient"; reason = "under_24_samples"
  } else if (miss > 0) {
    verdict = "fail"; reason = "app_missing"
  } else if (crash_delta > 0) {
    verdict = "fail"; reason = "crashes"
  } else if (m_slope > 1.0) {
    verdict = "fail"; reason = "mem_growth"
  } else if (drift > 10 || drift < -10) {
    verdict = "fail"; reason = "mem_drift"
  } else if (f_slope > 24) {
    verdict = "fail"; reason = "fd_leak"
  } else {
    verdict = "pass"; reason = "all_within_threshold"
  }
  printf "SOAK_VERDICT=%s\n", verdict
  printf "SOAK_REASON=%s\n", reason
}
' "$LOG"
exit 0