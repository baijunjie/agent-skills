#!/bin/sh
# 在当前 clone 里启用回退闸门：sh .githooks/install.sh [<常驻守护的分支>...]
# 参数里的分支（通常是主分支）常驻受守护，给了参数就替换原有列表；各 worktree 分支记录的目标分支
# 另外自动受守护。每个 clone 执行一次，可重复执行；所有 worktree 共用公共 hooks 目录。
set -eu

root=$(git rev-parse --show-toplevel)
hooks="$(git rev-parse --git-common-dir)/hooks"

if [ -n "$(git config core.hooksPath || true)" ]; then
  echo "core.hooksPath 已设置为 $(git config core.hooksPath)，公共 hooks 目录不会生效；" \
       "请在那套 hook 体系里调用 sh .githooks/hook.sh <reference-transaction|pre-push> \"\$@\"。" >&2
  exit 1
fi

for branch in "$@"; do
  git rev-parse --verify -q "refs/heads/${branch}" >/dev/null || {
    echo "找不到分支 ${branch}。" >&2
    exit 1
  }
done

mkdir -p "${hooks}"
for name in reference-transaction pre-push; do
  target="${hooks}/${name}"
  if [ -e "${target}" ] && ! grep -q '^# revert-gate hook entry' "${target}"; then
    echo "${target} 已存在且不是闸门入口，未覆盖；请在其中调用 sh .githooks/hook.sh ${name} \"\$@\"。" >&2
    exit 1
  fi
  cp "${root}/.githooks/hook.sh" "${target}"
  chmod +x "${target}"
done

if [ $# -gt 0 ]; then
  git config --unset-all revert-gate.branch || true
  for branch in "$@"; do
    git config --add revert-gate.branch "${branch}"
  done
fi

fixed=$(git config --get-all revert-gate.branch || true)
if [ -z "${fixed}" ]; then
  echo "回退闸门已启用，但没有常驻守护的分支；用 sh .githooks/install.sh <主分支> 指定。" >&2
  exit 0
fi
echo "回退闸门已启用。常驻守护：$(echo ${fixed})；各 worktree 分支记录的目标分支另外受守护。"
for branch in ${fixed}; do
  git cat-file -e "refs/heads/${branch}:.githooks/revert-gate.py" 2>/dev/null ||
    echo "注意：${branch} 上还没有 .githooks/revert-gate.py，提交进去之后闸门才开始检查。" >&2
done
