#!/bin/sh
# 在原基点上压平当前分支，压完核对，出错自动退回。在分支自己的工作副本里执行：
#   sh flow-squash.sh <基准 ref> <提交信息文件>      把领先基准的提交压成一个
#   sh flow-squash.sh --check <基准 ref> <压前提交>  自己拆成多个提交后，只做核对
#
# 原基点是 `git merge-base HEAD <基准 ref>`。不能 reset 到基准的最新提交：基点换了而内容没合，
# 旧代码会被当成新改动压进去，悄悄撤销基点之后目标分支上的改动。
# 压平模式：
# 1. 前提：HEAD 在分支上、工作树干净（含未跟踪文件）、没有做到一半的 rebase / merge、
#    领先基准至少一个提交、其中没有 merge 提交。不满足就停下，什么都不动。
# 2. 原提交里声明的撤销（`Reverts: <sha>` 或 `This reverts commit <sha>`），提交信息文件里
#    少了哪条就停下：丢了就成了没声明的撤销，会被回退闸门拦下。被撤销的提交本身也在这次压平
#    范围里的（分支自己提交又自己撤销）不算，它不会进目标分支。
# 3. reset --soft 到原基点后按提交信息文件重新提交。压前提交由调用方自己记下（输出里也会打印），
#    脚本不另存，免得留下过期的记录。
# 4. 核对：新提交的父提交是原基点、与压前提交的内容一致。不满足（或提交本身失败，如被 commit-msg
#    hook 拒绝）就 reset --hard 回压前提交，退出码 1。
# 核对模式只做第 4 步的核对，判据改成「HEAD 与基准的 merge-base 仍是原基点」，失败时不自动退回。
# 退出码见 flow-lib.sh。
set -eu
. "$(dirname "$0")/flow-lib.sh"

check_only=0
if [ "${1:-}" = --check ]; then
  check_only=1
  shift
fi
[ $# -eq 2 ] || fatal "用法：flow-squash.sh <基准 ref> <提交信息文件> 或 flow-squash.sh --check <基准 ref> <压前提交>"
in_repo
base_c=$(commit_of "$1") || fatal "不是一个提交：$1"
branch=$(git symbolic-ref --quiet --short HEAD) || fatal "HEAD 不在分支上（detached），不压平"

if [ "$check_only" = 1 ]; then
  pre=$(commit_of "$2") || fatal "不是一个提交：$2"
  mb=$(git merge-base "$pre" "$base_c") || fatal "压前提交与 $1 没有共同祖先"
  if [ "$(git merge-base HEAD "$base_c")" != "$mb" ]; then
    stop "核对没通过：基点变了，HEAD 与 $1 的 merge-base 不再是原基点 $mb" \
      "退回压前提交重做：git reset --hard $pre"
  fi
  if [ -n "$(git rev-list --merges "$mb..HEAD")" ]; then
    stop "核对没通过：压出来的提交里有 merge 提交" "退回压前提交重做：git reset --hard $pre"
  fi
  if ! git diff --quiet "$pre" HEAD; then
    stop "核对没通过：内容与压前提交不一致" "$(git diff --stat "$pre" HEAD)" \
      "退回压前提交重做：git reset --hard $pre"
  fi
  say "核对通过"
  exit 0
fi

msg=$2
[ -f "$msg" ] && [ -s "$msg" ] || fatal "提交信息文件不存在或为空：$msg"
if in_progress .; then
  stop "有做到一半的 rebase / merge / cherry-pick，先处理完"
fi
dirty=$(git status --porcelain)
[ -z "$dirty" ] || stop "工作树不干净（含未跟踪文件），不压平：未提交的改动会被混进提交" "$dirty"
head=$(git rev-parse HEAD)
mb=$(git merge-base HEAD "$base_c") || fatal "当前分支与 $1 没有共同祖先"
[ "$(git rev-list --count "$mb..HEAD")" -gt 0 ] || stop "没有领先 $1 的提交，没东西可压"
[ -z "$(git rev-list --merges "$mb..HEAD")" ] ||
  stop "分支里有 merge 提交：压平会把合进来的别的分支的改动一起压进去，不压平"

declared=$(git log --format=%B "$mb..HEAD" |
  grep -Eio '^(reverts:[[:space:]]*|this reverts commit )[0-9a-f]{7,64}' |
  grep -Eio '[0-9a-f]{7,64}$' | tr 'A-F' 'a-f' | sort -u) || true
missing=
for sha in $declared; do
  if c=$(commit_of "$sha" 2>/dev/null) && is_ancestor "$c" HEAD && ! is_ancestor "$c" "$mb"; then
    continue
  fi
  grep -Eiq "^(reverts:[[:space:]]*|this reverts commit )$sha" "$msg" ||
    missing="$missing${missing:+
}Reverts: $sha"
done
[ -z "$missing" ] || stop "提交信息里少了原提交声明过的撤销，补上这几行再压：" "$missing"

git reset -q --soft "$mb" || stop "reset 被拒绝（见上面的输出），没有压平"

restore() {
  git reset -q --hard "$head"
  stop "$1，已退回压前提交 $head" "$2"
}
git commit -q -F "$msg" || restore "提交失败（见上面 git 的输出）" ""
[ "$(git rev-parse HEAD^)" = "$mb" ] || restore "核对没通过：新提交的父提交不是原基点 $mb" ""
git diff --quiet "$head" HEAD || restore "核对没通过：内容与压前提交不一致" ""
say "已压成一个提交 $(git rev-parse --short HEAD)，原基点 ${mb}，压前提交 $head"
