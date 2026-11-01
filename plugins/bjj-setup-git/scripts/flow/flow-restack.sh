#!/bin/sh
# 目标分支 rebase 过（对齐远程时把本地未推送的提交垫到远程最新之上）之后，
# 把从它切出的分支逐个搬到新位置：sh flow-restack.sh <目标分支> <旧位置> [--allow-pushed <分支>]...
#
# <旧位置> 是目标分支 rebase 前的提交。从改写前那批提交上切出的分支里还是旧的那份，
# 直接 rebase 会把它们再搬一遍，所以只搬分支自己的提交：rebase --onto <目标分支> <旧位置>。
# - 找的是 branch.<分支>.targetBranch 等于 <目标分支> 的分支。
# - 要不要搬：分支与 <旧位置> 的 merge-base 不在新的目标分支上，说明它含有改写前的提交。
#   搬过的不再满足这一条，所以重跑会跳过它们。
# - 已推送过的分支（有上游、且上游不是目标分支的远端跟踪分支）搬了就要强推，不是独用的不该动：
#   遇到就停下，用户确认它独用后，用 --allow-pushed <分支> 点名放行（可给多个）。
# - 搬要在分支自己的 worktree 里做：没有 worktree、worktree 不干净、上次的 rebase 没做完都停下。
#   这几种与冲突都以退出码 1 停下，但不退回：已经搬完的保留，冲突时保留 rebase 现场；
#   解完冲突、rebase --continue 后重跑本脚本。
# - 搬完（含冲突解完后重跑时）把 forkPoint 更新成分支与目标分支的 merge-base：旧切出点指向
#   被改写的旧提交，留着会让合并前的核对把它们算进去。
# 退出码见 flow-lib.sh。
set -eu
. "$(dirname "$0")/flow-lib.sh"

usage="用法：flow-restack.sh <目标分支> <旧位置> [--allow-pushed <分支>]..."
[ $# -ge 2 ] || fatal "$usage"
target=$1
old_arg=$2
shift 2
allowed=" "
while [ $# -gt 0 ]; do
  [ "$1" = --allow-pushed ] && [ $# -ge 2 ] || fatal "$usage"
  allowed="$allowed$2 "
  shift 2
done
in_repo
has_branch "$target" || fatal "本地没有分支 $target"
new=$(git rev-parse "refs/heads/$target")
old=$(commit_of "$old_arg") || fatal "不是一个提交：$old_arg"

branches=$(git config --get-regexp '^branch\..*\.targetbranch$' |
  awk -v t="$target" '$2 == t { k = $1; sub(/^branch\./, "", k); sub(/\.[^.]*$/, "", k); print k }') || true
moved=
for b in $branches; do
  [ "$b" != "$target" ] && has_branch "$b" || continue
  mb=$(git merge-base "refs/heads/$b" "$old") || continue
  if ! is_ancestor "$mb" "$new"; then
    up=$(git for-each-ref --format='%(upstream)' "refs/heads/$b")
    case $up in
      "" | refs/remotes/*/"$target") ;;
      *)
        case $allowed in
          *" $b "*) ;;
          *) stop "分支 $b 已推送过（上游 ${up#refs/remotes/}），搬它要强推：确认它是自己独用的后，带 --allow-pushed $b 重跑" \
            "已搬完的：${moved:-无}" ;;
        esac
        ;;
    esac
    wt=$(worktree_of "$b")
    [ -n "$wt" ] || stop "分支 $b 含有改写前的提交，但没有检出在任何 worktree 里，没搬" \
      "已搬完的：${moved:-无}"
    [ -d "$wt" ] || stop "分支 $b 的 worktree（${wt}）目录已不存在，先 git worktree prune" "已搬完的：${moved:-无}"
    if in_progress "$wt"; then
      stop "分支 $b 的 worktree（${wt}）里有没做完的 rebase / merge，先处理完再重跑" "已搬完的：${moved:-无}"
    fi
    dirty=$(git -C "$wt" status --porcelain)
    [ -z "$dirty" ] || stop "分支 $b 的 worktree（${wt}）不干净，没搬" "$dirty" "已搬完的：${moved:-无}"
    git -C "$wt" rebase -q --onto "$new" "$old" ||
      stop "分支 $b 在 $wt 里 rebase 冲突：解完冲突、git rebase --continue 后重跑本脚本" \
        "已搬完的：${moved:-无}"
    moved="$moved $b"
  fi
  fork=$(git config --get "branch.$b.forkPoint") || fork=
  if [ -n "$fork" ] && ! is_ancestor "$fork" "$new"; then
    git config "branch.$b.forkPoint" "$(git merge-base "refs/heads/$b" "$new")"
  fi
done
say "已搬：${moved:-无}"
