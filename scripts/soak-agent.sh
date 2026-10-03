#!/usr/bin/env bash
# soak-agent.sh —— SC5 长跑的 LaunchAgent（com.local.pic.soak）装卸：
#
#   bash scripts/soak-agent.sh start [SOAK_DIR]
#   bash scripts/soak-agent.sh stop
#   bash scripts/soak-agent.sh status
#
# plist 只有四个键（Label / ProgramArguments / RunAtLoad / StartInterval）。
# 刻意**不用 KeepAlive**：配一次性脚本 = 跑完立刻被拉起 = 紧循环烤机；
# 逐时唤醒是 StartInterval 的职责，采样器真死了由「缺口 >5% 作废」兜住。
#
# 路径全部从脚本自身位置推导，plist 里没有任何用户输入 —— 常驻执行面被篡改就是
# 「任意命令每小时跑一次」，所以这个文件里唯一可变量只有可选的 SOAK_DIR。
#
# 只用 bootstrap/bootout。load/unload 是废弃写法，新版 launchd 上语义已变。
#
# start 的第二参数把 SOAK_DIR 写进 EnvironmentVariables：没有它，RunAtLoad 立刻跑
# 的那一次采样会落进默认目录（repo 的 evidence/soak/），把 7 天序列的第一行换成
# 一条不属于本次测试的样本。

set -u
export LC_ALL=C

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SAMPLER="$ROOT/scripts/soak-sampler.sh"
LABEL="com.local.pic.soak"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

# plutil 也要认它 —— plist 里出现未转义的 & 会让 bootstrap 静默失败。
xml_escape() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

write_plist() {
  mkdir -p "$(dirname "$PLIST")"
  {
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
    printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    printf '%s\n' '<plist version="1.0">'
    printf '%s\n' '<dict>'
    printf '  <key>Label</key><string>%s</string>\n' "$LABEL"
    printf '%s\n' '  <key>ProgramArguments</key>'
    printf '%s\n' '  <array>'
    printf '    <string>/bin/bash</string>\n'
    printf '    <string>%s</string>\n' "$(xml_escape "$SAMPLER")"
    printf '%s\n' '  </array>'
    if [ -n "${1:-}" ]; then
      printf '%s\n' '  <key>EnvironmentVariables</key>'
      printf '%s\n' '  <dict>'
      printf '    <key>SOAK_DIR</key><string>%s</string>\n' "$(xml_escape "$1")"
      printf '%s\n' '  </dict>'
    fi
    printf '%s\n' '  <key>RunAtLoad</key><true/>'
    printf '%s\n' '  <key>StartInterval</key><integer>3600</integer>'
    printf '%s\n' '</dict>'
    printf '%s\n' '</plist>'
  } > "$PLIST"
}

case "${1:-}" in
  start)
    write_plist "${2:-}"
    launchctl bootstrap "gui/$(id -u)" "$PLIST" || exit 1
    exit 0
    ;;
  stop)
    # bootout 是异步的：判据在 stop 之后必须 sleep 几拍再核对，不等就数会得出
    # 「加载态已清」而进程随后又被写回日志。
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    rm -f "$PLIST"
    exit 0
    ;;
  status)
    launchctl print "gui/$(id -u)/$LABEL"
    exit $?
    ;;
  *)
    printf 'usage: %s {start [SOAK_DIR]|stop|status}\n' "$(basename "$0")" >&2
    exit 2
    ;;
esac