#!/bin/sh
# 在当前 clone 里启用回退闸门：sh .githooks/install.sh [--branches-only] [<常驻守护分支>...]
# 常驻守护分支（通常是主分支）写进本 clone 的 git 配置 revert-gate.branch，替换原有列表；各 worktree
# 分支记录的目标分支另外自动受守护。给了分支参数就用参数；不给就读随仓库提交的 .githooks/branches
# （每行一个分支，主分支在第一行，# 开头的行与空行忽略）。闸门运行时只读 git 配置、不读这个文件：
# 工作区里的文件会被待合并的分支改掉，不能让它影响闸门判定。
# --branches-only：只写常驻守护分支配置、不装 hook，用于 hook 由 husky 等体系接管
# （core.hooksPath 已设置、在那套体系里调用 .githooks/hook.sh）的 clone。
# 每个 clone 执行一次，可重复执行；所有 worktree 共用公共 hooks 目录。
set -eu

hooks_too=1
if [ "${1:-}" = --branches-only ]; then
  hooks_too=0
  shift
fi

root=$(git rev-parse --show-toplevel)
hooks="$(git rev-parse --git-common-dir)/hooks"
list="${root}/.githooks/branches"

if [ "${hooks_too}" = 1 ] && [ -n "$(git config core.hooksPath || true)" ]; then
  echo "core.hooksPath 已设置为 $(git config core.hooksPath)，公共 hooks 目录不会生效；请在那套 hook 体系里调用 sh .githooks/hook.sh <reference-transaction|pre-push> \"\$@\"，再执行 sh .githooks/install.sh --branches-only 写常驻守护分支。" >&2
  exit 1
fi

if [ $# -gt 0 ]; then
  from="参数"
else
  [ -f "${list}" ] || {
    echo "没有 ${list}，什么都没装；用 sh .githooks/install.sh <主分支> 指定常驻守护分支。" >&2
    exit 1
  }
  branches=$(sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e '/^#/d' -e '/^$/d' "${list}")
  [ -n "${branches}" ] || {
    echo "${list} 里没有分支，什么都没装。" >&2
    exit 1
  }
  set -f
  # shellcheck disable=SC2086 # 分支名不含空白，按行拆开即可
  set -- ${branches}
  set +f
  from="${list} "
fi

# 新 clone 里除默认分支外通常只有远端跟踪分支，只要求本地或某个远端有这个分支，用来挡住拼错的名字。
for branch in "$@"; do
  git rev-parse --verify -q "refs/heads/${branch}" >/dev/null ||
    [ -n "$(git for-each-ref --count=1 "refs/remotes/*/${branch}")" ] || {
    echo "${from}里的分支 ${branch} 在本地和远端都找不到，什么都没装。" >&2
    exit 1
  }
done

if [ "${hooks_too}" = 1 ]; then
  # 先查完再写：中途退出会留下装了一半的 hook 和没写的常驻守护分支。
  for name in reference-transaction pre-push; do
    target="${hooks}/${name}"
    if [ -e "${target}" ] && ! grep -q '^# revert-gate hook entry' "${target}"; then
      echo "${target} 已存在且不是闸门入口，什么都没装；请在其中调用 sh .githooks/hook.sh ${name} \"\$@\"。" >&2
      exit 1
    fi
  done

  mkdir -p "${hooks}"
  for name in reference-transaction pre-push; do
    target="${hooks}/${name}"
    cp "${root}/.githooks/hook.sh" "${target}"
    chmod +x "${target}"
  done
fi

git config --unset-all revert-gate.branch || true
for branch in "$@"; do
  git config --add revert-gate.branch "${branch}"
done

if [ "${hooks_too}" = 1 ]; then
  echo "回退闸门已启用。常驻守护：$*；各 worktree 分支记录的目标分支另外受守护。"
else
  echo "已写入常驻守护分支：$*（未装 hook，由现有 hook 体系调用 .githooks/hook.sh）。"
fi
# 闸门预检只从第一个常驻守护分支的本地分支读脚本，新 clone 里它可能只在远端。
first=$1
for branch in "$@"; do
  if ! git rev-parse --verify -q "refs/heads/${branch}" >/dev/null; then
    [ "${branch}" != "${first}" ] ||
      echo "注意：本 clone 没有本地分支 ${branch}，闸门预检要从它读脚本；先 git branch ${branch} <远端>/${branch} 建本地分支。" >&2
    continue
  fi
  git cat-file -e "refs/heads/${branch}:.githooks/revert-gate.py" 2>/dev/null ||
    echo "注意：${branch} 上还没有 .githooks/revert-gate.py，提交进去之后闸门才开始检查。" >&2
done
