#!/usr/bin/env bash
# 电池供电信号证据采集。一条命令，无子命令：编译 throwaway driver（与产品源码一起编）→ 跑 4 秒，只观察不制造事件 → 全量 stdout 落 evidence/power-signals.log，末尾追加汇总行。
#
# 三条纪律：
#   ① 所有外部命令套 `alarm N 命令 …`（见 probe-common.sh）—— 本机没有 timeout 命令，权限弹窗或异常输入会挂死采集。
#   ② `export LC_ALL=C` —— UTF-8 locale 下脚本输出会按字节偏移丢 2 字节，之后任何 grep 都会中止整份文件，判据假红。
#   ③ 探针失败不中止脚本（不用 set -e）：失败原样写进日志，由人读日志判定。
#
# 本脚本**不复用** scripts/run-probe.sh。
# driver **一次合成事件都不制造**：拔电源跃迁需要**物理拔电源线**，本会话做不到（不做任何需要人在场的硬件操作），
# 就记 `unobservable` + 原因，不拿合成事件冒充。
#
# 三处判据的字面量比字面计划更严，不是更松 —— 改任何一个都会让证据与判据脱节：
#   ① `POWER_SOURCE_KEY` 打的是**实测键名** `Power Source State`，不是 `AC Power`（后者是取值 `kIOPSACPowerValue`，不是键）。
#   ② `POWER_SOURCE_VALUE` 打的是 **CFString 取值**（`AC Power` / `Battery Power` / `Off Line`），不是 `true|false` —— 该键的 Type 是 CFString。
#   ③ `POWER_TRANSITION` 的 `reason=` 写 `requires_physical_unplug`（本机确有内置电池），不写 `session_locked` —— 拔电源的可达性与屏幕锁不锁无关，写「锁屏」是错的归因。

set -u
export LC_ALL=C

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# 证据落点可重定向：test.sh 传 PIC_EVIDENCE_DIR 指向临时目录，避免跑一次门禁就把已入库的证据覆盖掉。
EV="${PIC_EVIDENCE_DIR:-$ROOT/.planning/phases/03-system-events/evidence}"
LOG="$EV/power-signals.log"
TMP="$(mktemp -d)"
BIN="$TMP/powerwatcher-driver"
OUT="$TMP/driver.out"

# driver + 产品源码一起编 —— 证据跑的是产品代码，不是探针里重写一遍的逻辑。
# SettingsStore.swift 也要编进来：driver 要读 `SettingsStore.Seed().pauseOnBattery`
# 那个**默认关闭**的值，用的不是探针里自己写的 false。
SRC="Sources/PicCore/System/PowerWatcher.swift \
     Sources/PicCore/State/SettingsStore.swift \
     .planning/spike/PowerWatcherDriver.swift"

. "$(dirname "$0")/probe-common.sh" || { echo "probe-common.sh 缺失，无法取 alarm()" >&2; exit 1; }

cleanup() { rm -rf "$TMP"; return 0; }
trap cleanup EXIT INT TERM

mkdir -p "$EV"

log() { printf '%s\n' "$*" >&2; }

if ! alarm 180 swiftc -parse-as-library -target arm64-apple-macosx15.0 -o "$BIN" $SRC > "$TMP/build.log" 2>&1; then
  log "PROBE_COMPILE_FAILED rc=1"
  grep -E 'error:' "$TMP/build.log" | head -5 >&2
  # 编译失败也要落日志：空文件会让后续判据静默通过，掩盖失败。
  : > "$LOG"
  echo "PROBE_COMPILE_RC=1" >> "$LOG"
  exit 1
fi

alarm 60 "$BIN" > "$OUT" 2>&1
DRIVER_RC=$?
echo "PROBE_DRIVER_RC=$DRIVER_RC" >> "$OUT"

cp "$OUT" "$LOG"

CALLBACK_LINE=$(grep -cE '^POWER_CALLBACKS_FIRED=[0-9]+$' "$LOG")
LINES=$(wc -l < "$LOG" | tr -d ' ')

# 末尾两行汇总：命中该行的**行数** + 日志行数。真实的回调次数写在上面一行（POWER_CALLBACKS_FIRED=），
# 两者是不同的两个数 —— 同一个数有两种读法会让证据假（同 display 重配置那个坑）。
echo "POWER_CALLBACK_FIRED_LINE_COUNT=$CALLBACK_LINE" >> "$LOG"
echo "POWER_LOG_LINES=$LINES" >> "$LOG"

log "PROBE_OK rc=$DRIVER_RC callback_line=$CALLBACK_LINE log=$LOG"
exit 0