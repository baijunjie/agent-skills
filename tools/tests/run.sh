#!/usr/bin/env bash
# 运行 tools/tests/ 下的全部测试套件（各子目录的 run.sh），任一失败整体退出码 1。
#   bash tools/tests/run.sh [-v]
# 套件之外再做一次真实仓库前后快照对比，与各套件自己的对比互相独立。

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib/common.sh"

SNAP_BEFORE=$(repo_snapshot)
make_tmp

failed=()
start=$SECONDS
for suite in "$TESTS_ROOT"/*/run.sh; do
  name=$(basename "$(dirname "$suite")")
  [ "$name" != lib ] || continue
  echo "== $name"
  if bash "$suite" "$@"; then
    :
  else
    failed+=("$name")
  fi
done

if compare_snapshots "$SNAP_BEFORE" "$(repo_snapshot)"; then
  echo "PASS repo_untouched"
else
  echo "FAIL repo_untouched: 真实仓库在运行前后不一致"
  failed+=(repo_untouched)
fi

echo "== ${#failed[@]} 个套件失败（$((SECONDS - start))s）${failed[*]:+：${failed[*]}}"
[ ${#failed[@]} = 0 ]
