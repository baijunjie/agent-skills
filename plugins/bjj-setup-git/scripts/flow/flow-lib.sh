# shellcheck shell=sh
# 流程脚本（flow-*.sh）的公共函数，由各脚本 source，不单独执行。
#
# 流程脚本只做 git-pr / git-worktree 两个 skill 里步骤固定、做错了又不报错的机械操作，
# 判断与平台操作（查 PR、建 PR）留给 agent。约定：
# - 只依赖 POSIX sh 与 git，不依赖 python3。
# - 退出码：0 做完；1 停下交给 agent，stderr 第一行是 `[flow] <原因>`，现场与下一步见其后的输出
#   （多数情形什么都没动或已自动退回，例外在各脚本开头写明）；2 用法或环境错误，什么都没写。
# - 不加 --no-verify、不设 REVERT_GATE_SKIP：仓库的检查拦下了就照实报出来。

# stop <原因> [<补充行>...]：停下交给 agent，退出码 1。
stop() {
  printf '[flow] %s\n' "$1" >&2
  shift
  for line in "$@"; do
    [ -z "$line" ] || printf '%s\n' "$line" >&2
  done
  exit 1
}

# fatal <信息>：用法或环境错误，退出码 2。
fatal() {
  printf '[flow] %s\n' "$*" >&2
  exit 2
}

say() {
  printf '[flow] %s\n' "$*"
}

in_repo() {
  git rev-parse --git-dir >/dev/null 2>&1 || fatal "当前目录不在 git 仓库里"
}

commit_of() {
  git rev-parse --verify --quiet "$1^{commit}"
}

is_ancestor() {
  git merge-base --is-ancestor "$1" "$2"
}

has_branch() {
  git show-ref --verify --quiet "refs/heads/$1"
}

# 主工作副本（第一个 worktree）的路径。
main_worktree() {
  git worktree list --porcelain | sed -n '1s/^worktree //p'
}

# 分支所在的 worktree 路径：检出着它的，或正在 rebase 它的（rebase 途中 HEAD 是 detached，
# worktree 列表里看不出分支名）。都没有时输出为空。
worktree_of() {
  hit=$(git worktree list --porcelain | awk -v ref="refs/heads/$1" '
    /^worktree / { path = substr($0, 10) }
    $0 == "branch " ref { print path; exit }')
  if [ -n "$hit" ]; then
    printf '%s\n' "$hit"
    return 0
  fi
  git worktree list --porcelain | sed -n 's/^worktree //p' | while IFS= read -r path; do
    if (cd "$path" 2>/dev/null && for d in rebase-merge rebase-apply; do
      f=$(git rev-parse --git-path "$d/head-name") && [ -f "$f" ] && [ "$(cat "$f")" = "refs/heads/$1" ] && exit 0
    done; exit 1); then
      printf '%s\n' "$path"
      break
    fi
  done
}

# 某个工作副本里是否有没做完的 rebase / merge / cherry-pick。
# --git-path 给出的相对路径相对于那个工作副本，所以进去再判断。
in_progress() {
  (
    cd "$1" || exit 1
    for p in rebase-merge rebase-apply MERGE_HEAD CHERRY_PICK_HEAD; do
      [ ! -e "$(git rev-parse --git-path "$p")" ] || exit 0
    done
    exit 1
  )
}

# 远端上某个分支的当前提交，远端没有这个分支时输出为空；连不上远端时报 2。
remote_head() { # remote_head <远端> <分支>
  set +e
  out=$(git ls-remote --exit-code --heads "$1" "refs/heads/$2")
  rc=$?
  set -e
  case $rc in
    0) printf '%s\n' "$out" | awk 'NR == 1 { print $1 }' ;;
    2) ;;
    *) fatal "读不到远端 $1 上的分支 $2（git ls-remote 退出码 ${rc}）" ;;
  esac
}
