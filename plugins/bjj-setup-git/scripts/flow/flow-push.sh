#!/bin/sh
# 推送分支，推之前确认不会盖掉远端上别人的提交：
#   sh flow-push.sh <推送远端> <分支> <推送目标> [--force]
#
# 按远端上 <推送目标> 的状态处理（远端状态用 ls-remote 实时取，不靠上次 fetch）：
# - 远端没有这个分支：push -u。
# - 远端尖端是本地分支的祖先：普通推送。
# - 远端尖端不是本地的祖先，但被本地分支 reflog 里的某个位置包含（本地分支曾经含有它，通常是
#   自己推上去、后来压平或 rebase 改写掉的那份）：要改写已推送的历史。没给 --force 就停下，由 agent 确认分支自己独用、
#   问过用户后再带 --force；带了就用 --force-with-lease 钉住刚读到的远端尖端推送。
# - 都不是：远端有本地没有的提交（网页上采纳的建议、别人推的修复），停下、不推。
# reflog 过期（默认 90 天）后认不出自己推过的那份，按最后一种停下，交给人判断，不会误推。
# 推送被 hook 或远端拒绝时退出码 1，git 的输出原样留在 stderr。退出码见 flow-lib.sh。
set -eu
. "$(dirname "$0")/flow-lib.sh"

force=0
n=0
for a in "$@"; do
  case $a in
    --force) force=1 ;;
    -*) fatal "未知参数：$a" ;;
    *)
      n=$((n + 1))
      case $n in
        1) remote=$a ;;
        2) branch=$a ;;
        3) dst=$a ;;
      esac
      ;;
  esac
done
[ "$n" -eq 3 ] || fatal "用法：flow-push.sh <推送远端> <分支> <推送目标> [--force]"
in_repo
has_branch "$branch" || fatal "本地没有分支 $branch"
local_c=$(git rev-parse "refs/heads/$branch")
spec="refs/heads/$branch:refs/heads/$dst"

remote_c=$(remote_head "$remote" "$dst")
if [ -z "$remote_c" ]; then
  git push -u "$remote" "$spec" || stop "推送被拒绝（见上面的输出）"
  say "已推送到 $remote/${dst}（首次推送，已设上游）"
  exit 0
fi
if [ "$remote_c" = "$local_c" ]; then
  say "$remote/$dst 已是最新，不用推送"
  exit 0
fi
git fetch -q "$remote" "refs/heads/$dst" || fatal "fetch $remote $dst 失败"

if is_ancestor "$remote_c" "$local_c"; then
  git push "$remote" "$spec" || stop "推送被拒绝（见上面的输出）"
  say "已推送到 $remote/$dst"
  exit 0
fi

own=0
for pos in $(git reflog show --format=%H "refs/heads/$branch" 2>/dev/null); do
  if is_ancestor "$remote_c" "$pos"; then
    own=1
    break
  fi
done
if [ "$own" = 0 ]; then
  stop "$remote/$dst 上有本地没有的提交，不推送，免得盖掉它们：" \
    "$(git log --oneline "$local_c..$remote_c")"
fi
if [ "$force" = 0 ]; then
  stop "要改写已推送到 $remote/$dst 的历史：确认分支自己独用、用户同意强推后，带 --force 重跑"
fi
git push --force-with-lease="refs/heads/$dst:$remote_c" "$remote" "$spec" ||
  stop "推送被拒绝（见上面的输出）"
say "已强推到 $remote/${dst}（--force-with-lease，期望值 ${remote_c}）"
