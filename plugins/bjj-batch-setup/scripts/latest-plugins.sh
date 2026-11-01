#!/usr/bin/env bash
# 用法：latest-plugins.sh <plugin>...
# 在本 plugin 所在的缓存里找同一 marketplace 下的兄弟 plugin，每个输出一行「<plugin> <目录>」，目录取版本号最大的那份
# （缓存里可能残留旧版本）。有 plugin 找不到、或同一 plugin 下另有不是 x.y.z 的目录（宿主可能用 commit 名作版本，
# 那份才是启用的）时，照样输出找得到的，在 stderr 报出，以 1 退出。
set -u
[ "$#" -gt 0 ] || { echo "latest-plugins.sh: 至少给一个 plugin 名" >&2; exit 1; }
SELF=$(cd "$(dirname "$0")/.." && pwd -P) || exit 1
BASE=$(cd "$SELF/../.." && pwd -P) || exit 1
rc=0
for p in "$@"; do
  v=$(ls "$BASE/$p" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1)
  if [ -z "$v" ]; then
    echo "latest-plugins.sh: 找不到 plugin：$p" >&2
    rc=1
    continue
  fi
  other=$(ls "$BASE/$p" 2>/dev/null | grep -vE '^[0-9]+\.[0-9]+\.[0-9]+$' | tr '\n' ' ')
  if [ -n "$other" ]; then
    echo "latest-plugins.sh: $p 下另有非版本号目录：$other" >&2
    rc=1
  fi
  echo "$p $BASE/$p/$v"
done
exit "$rc"
