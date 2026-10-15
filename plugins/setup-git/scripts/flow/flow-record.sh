#!/bin/sh
# 记下分支的目标分支与切出点：sh flow-record.sh <分支> <目标分支> <切出点提交>
#
# - branch.<分支>.targetBranch 每次都写；值是分支名，不带远端前缀（main，不是 origin/main）。
# - branch.<分支>.forkPoint 已有就不改写：rebase 之后切出点再也算不出来，覆盖掉就找不回了。
#   没有才写传入的提交（存成提交号）。切出点怎么算由调用方定，它必须是分支的祖先。
# 两个键由 git-pr 与 git-worktree 共用，回退闸门也读它们。退出码见 flow-lib.sh。
set -eu
. "$(dirname "$0")/flow-lib.sh"

[ $# -eq 3 ] || fatal "用法：flow-record.sh <分支> <目标分支> <切出点提交>"
branch=$1
target=$2
fork=$3
in_repo
has_branch "$branch" || fatal "本地没有分支 $branch"
[ -n "$target" ] || fatal "目标分支不能为空"
for remote in $(git remote); do
  case $target in
    "$remote"/*) fatal "目标分支要写分支名、不带远端前缀：$target" ;;
  esac
done

# 先校验完再写：报错时两个键都不动。
if old=$(git config --get "branch.$branch.forkPoint"); then
  fork_c=
else
  fork_c=$(commit_of "$fork") || fatal "不是一个提交：$fork"
  is_ancestor "$fork_c" "refs/heads/$branch" || fatal "切出点 $fork 不是分支 $branch 的祖先"
fi

git config "branch.$branch.targetBranch" "$target"
say "目标分支：$target"
if [ -z "$fork_c" ]; then
  say "切出点已记录为 ${old}，不改写"
else
  git config "branch.$branch.forkPoint" "$fork_c"
  say "切出点：$fork_c"
fi
