#!/bin/sh
# revert-gate hook entry —— 这一行是闸门入口的识别标志，改动时保留。
#
# 回退闸门的 hook 入口。用法：以 reference-transaction / pre-push 的名字放进 hooks 目录，
# 或由别的 hook 体系调用 `sh .githooks/hook.sh <reference-transaction|pre-push> "$@"`。
#
# 执行的是受守护分支上已提交的那份闸门脚本，而不是工作树里的文件：merge 先写工作树、最后才移动 ref，
# 读工作树就等于让待合并的分支自己决定闸门怎么判。常驻守护分支（通常是主分支）优先，
# 免得哪个旧分支上的旧脚本或改过的脚本成了所有分支的规则。没有常驻守护分支的仓库（只装了 PR 流程）
# 以被推分支记的目标分支为锚点：先取它的本地分支，没有再取它的远端跟踪分支，都是已发布的那份。
# reference-transaction 在每个 ref 事务的每个阶段都会调用，rebase、fetch、每次提交都会触发，
# 所以先在 shell 里筛到「动了受守护分支」才启动 Python。受守护分支 = 所有 branch.*.targetBranch
# 的值加 revert-gate.branch 的值；pre-push 另外筛「被推的分支自己记了 branch.*.targetBranch」。
# 找不到 python3 或脚本时放行——hook 失败会让所有 ref 更新都失败。

case "$1" in
  reference-transaction|pre-push) mode=$1; shift ;;
  *) mode=${0##*/} ;;
esac

# 能不启动任何进程就判掉的先判：非 prepared 阶段、不涉及本地分支的事务直接放行。
# 不读完 stdin 就退出没关系，git 对这个 hook 忽略 EPIPE。
if [ "$mode" = reference-transaction ] && [ "$1" != prepared ]; then
  exit 0
fi
input=$(cat)
case "$input" in
  *" refs/heads/"*) ;;
  *) exit 0 ;;
esac

nl='
'
config=$(git config --get-regexp '^(branch\..*\.targetbranch|revert-gate\.branch)$') || exit 0
fixed= hit= pr=
while IFS=' ' read -r key name; do
  [ -n "${name}" ] || continue
  [ "${key}" != revert-gate.branch ] || fixed="${fixed} ${name}"
  # 记了目标分支的开发分支（键里那段）被推时走 PR 那条路径。pre-push 的每行是
  # 「<源 refspec 原文> <本地 sha> <远端 ref> <远端 sha>」：第一个字段按行首匹配，但
  # `git push origin HEAD` 那里写的是 HEAD，所以也按第三个字段（远端 ref）匹配一次。
  # 这里只负责把它筛进来、把目标分支留作取脚本的候选，到底按哪个分支查由闸门脚本自己定。
  if [ "${mode}" = pre-push ] && [ "${key}" != revert-gate.branch ]; then
    branch=${key#branch.}
    branch=${branch%.targetbranch}
    case "${nl}${input}" in
      *"${nl}refs/heads/${branch} "*|*" refs/heads/${branch} "*) pr="${pr} ${name}" ;;
    esac
  fi
  # 值是目标分支，它自己受守护：这次事务动了它就要查。
  case "${input}${nl}" in
    *" refs/heads/${name}${nl}"*|*" refs/heads/${name} "*) hit="${hit} ${name}" ;;
  esac
done <<EOF_CONFIG
${config}
EOF_CONFIG
[ -n "${hit}${pr}" ] || exit 0

command -v python3 >/dev/null 2>&1 || exit 0
script=
for name in ${fixed} ${hit} ${pr}; do
  # 本地没有这个分支（如新 clone、只装了 PR 流程）时取它的远端跟踪分支，同样是已发布的那份。
  # 只认它配置的远端与 origin：按字母序挑「唯一一个同名的」会让别人的 fork 决定闸门脚本。
  remote=$(git config "branch.${name}.remote" 2>/dev/null)
  [ -n "${remote}" ] || remote=origin
  for ref in "refs/heads/${name}" "refs/remotes/${remote}/${name}" "refs/remotes/origin/${name}"; do
    script=$(git cat-file blob "${ref}:.githooks/revert-gate.py" 2>/dev/null) && break
  done
  [ -z "${script}" ] || break
done
[ -n "${script}" ] || exit 0
# -I：不把当前目录放进 sys.path、忽略 PYTHON* 环境变量，仓库根下的同名 .py 才遮不住标准库。
# 只有退出码 3 是闸门的拒绝，其它非零（脚本跑不起来、与本机 Python 不兼容）一律放行。
# 本文件装进各 clone 后不随仓库更新，脚本却取自仓库里的分支，所以退出码 3 这个约定不能改。
printf '%s\n' "$input" | python3 -I -c "$script" "$mode" "$@"
[ $? -ne 3 ] || exit 1
