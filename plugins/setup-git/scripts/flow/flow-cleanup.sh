#!/bin/sh
# 合并或提完 PR 后清理分支：先核对前提，满足了才删 worktree 与本地分支。
#   sh flow-cleanup.sh <分支> --merged-into <目标分支> [--ignored-ok]          worktree 流程，本地合并后
#   sh flow-cleanup.sh <分支> --pushed-to <推送远端>/<推送目标> [--ignored-ok]  PR 流程，PR 建好后
#
# 在主工作副本里执行（脚本自己切过去；调用方的当前目录若在要删的 worktree 里，之后要自己离开）。
# 1. 前提：--merged-into 要求分支已是目标分支的祖先；--pushed-to 要求本地分支与远端实时状态指向
#    同一提交，否则没推上去的改写会随 branch -D 丢掉。不满足就停下，什么都不删。
# 2. 分支有自己的 worktree：有未提交或未跟踪的文件就停下；有被忽略的文件时列出来停下，
#    除非带了 --ignored-ok（git worktree remove 会连它们一起删且不提示；哪些能重新生成由 agent 判断
#    或问用户）。然后 git worktree remove，不加 --force。
# 3. 分支检出在主工作副本里：切回 branch.<分支>.targetBranch（本地没有就由 git switch 从唯一的同名
#    远端分支建跟踪分支）；有未提交的改动、目标分支被别的 worktree 占用都停下。
# 4. git branch -D（branch.<分支>.* 的记录随之删掉）。它失败时以 1 停下，但前面删掉的 worktree、
#    切回的主工作副本不退回；处理好原因后重跑即可接着删。
# 退出码见 flow-lib.sh。
set -eu
. "$(dirname "$0")/flow-lib.sh"

usage="用法：flow-cleanup.sh <分支> --merged-into <目标分支> | --pushed-to <推送远端>/<推送目标> [--ignored-ok]"
[ $# -ge 3 ] || fatal "$usage"
branch=$1
mode=$2
ref=$3
shift 3
ignored_ok=0
case "${1:-}" in
  --ignored-ok) ignored_ok=1; shift ;;
  "") ;;
  *) fatal "$usage" ;;
esac
[ $# -eq 0 ] || fatal "$usage"
in_repo
main=$(main_worktree)
cd "$main" || fatal "进不了主工作副本：$main"

if ! has_branch "$branch"; then
  say "本地已没有分支 ${branch}，不用清理"
  exit 0
fi
case $mode in
  --merged-into)
    has_branch "$ref" || fatal "本地没有分支 $ref"
    is_ancestor "refs/heads/$branch" "refs/heads/$ref" || stop "分支 $branch 还没合进 ${ref}，不清理"
    ;;
  --pushed-to)
    remote=${ref%%/*}
    dst=${ref#*/}
    [ -n "$remote" ] && [ -n "$dst" ] && [ "$dst" != "$ref" ] || fatal "$usage"
    git remote | grep -Fqx -- "$remote" || fatal "没有远端 $remote"
    remote_c=$(remote_head "$remote" "$dst")
    [ -n "$remote_c" ] || stop "远端 $remote 上没有分支 ${dst}，不清理"
    [ "$remote_c" = "$(git rev-parse "refs/heads/$branch")" ] ||
      stop "本地 $branch 与 $remote/$dst 不在同一提交，不清理：没推上去的改动会随 branch -D 丢掉"
    ;;
  *) fatal "$usage" ;;
esac

wt=$(worktree_of "$branch")
if [ -n "$wt" ] && [ "$wt" != "$main" ]; then
  [ -d "$wt" ] || stop "worktree $wt 目录已不存在，先 git worktree prune 再重跑"
  if in_progress "$wt"; then
    stop "worktree $wt 里有没做完的 rebase / merge，不清理"
  fi
  dirty=$(git -C "$wt" status --porcelain)
  [ -z "$dirty" ] || stop "worktree $wt 里有未提交或未跟踪的文件，不清理" "$dirty"
  ignored=$(git -C "$wt" status --porcelain --ignored | sed -n 's/^!! //p')
  if [ -n "$ignored" ] && [ "$ignored_ok" = 0 ]; then
    stop "worktree $wt 里有被忽略的文件，git worktree remove 会连它们一起删：确认都能重新生成（或用户同意删）后带 --ignored-ok 重跑" "$ignored"
  fi
  git worktree remove "$wt" || stop "git worktree remove 失败（见上面的输出），没删分支"
  say "已删除 worktree $wt"
elif [ "$wt" = "$main" ]; then
  if in_progress "$main"; then
    stop "主工作副本里有没做完的 rebase / merge，不清理"
  fi
  target=$(git config --get "branch.$branch.targetBranch") || stop "分支 $branch 检出在主工作副本里，但读不到它的目标分支，不知道切回哪"
  dirty=$(git status --porcelain --untracked-files=no)
  [ -z "$dirty" ] || stop "主工作副本里有未提交的改动，没切回 $target" "$dirty"
  git switch -q "$target" || stop "切不回 ${target}（见上面的输出；被别的 worktree 占用时要用户处理），没删分支"
  say "主工作副本已切回 $target"
fi
git branch -q -D "$branch" || stop "git branch -D 失败（见上面的输出），分支 $branch 还在；前面的清理已做完、不退回，处理好后重跑"
say "已删除本地分支 $branch"
