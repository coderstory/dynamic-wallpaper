#!/usr/bin/env bash
# 构建串行化闸（用户拍板 2026-10-20）：XCBuild 增量库不抗并发写——多进程同时构建会
# 踩坏 .build/out 增量态，之后内容变更不再触发重编，产出「时间戳新、内容旧」的假产物。
# 用法：build.sh / install-app.sh 开头 `source scripts/build-guard.sh`。
# 注意：系统 bash 是 3.2，变量紧邻中文时必须写 ${var}，裸 $var 会把后续多字节吞进变量名。

# 判「holder 是否本进程的祖先」：install-app.sh 持锁后调 build.sh，子脚本必须放行。
is_ancestor() {
  local p=$$
  while [ "$p" -gt 1 ]; do
    p=$(ps -o ppid= -p "${p}" | tr -d ' ')
    [ -z "${p}" ] && return 1
    [ "${p}" = "$1" ] && return 0
  done
  return 1
}

mkdir -p .build
if ! mkdir .build/build.lock 2>/dev/null; then
  holder=$(cat .build/build.lock/pid 2>/dev/null || true)
  if [ -n "${holder}" ] && kill -0 "${holder}" 2>/dev/null; then
    if ! is_ancestor "${holder}"; then
      echo "错误：构建进行中（PID ${holder}）。构建已串行化——等它结束再试；AI 不得并行构建（会踩坏增量库产旧产物）。" >&2
      exit 1
    fi
    # 祖先持锁：本进程共用该锁，不重复上锁也不设 trap（锁归祖先管）。
    return 0 2>/dev/null || true
  fi
  rm -rf .build/build.lock   # 持锁者已死：清残锁重取
  mkdir .build/build.lock
fi
echo $$ > .build/build.lock/pid
trap 'rm -rf .build/build.lock' EXIT

# 不走本闸的裸 swift build（agent 直跑）也算并发：扫本仓路径的活跃构建进程。
if pgrep -f "swift-frontend.*dev/pic" >/dev/null 2>&1 || \
   pgrep -f "swift-build.*dev/pic"   >/dev/null 2>&1; then
  echo "错误：检测到外部构建进程正在编本仓（pgrep 命中）。构建已串行化——等它结束再试；AI 不得并行构建。" >&2
  exit 1
fi
