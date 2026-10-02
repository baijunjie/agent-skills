# shellcheck shell=bash
# 测试公共库：source 进各测试入口使用，不单独执行。
#
# 安全设计：测试只在自己 mktemp 出来的目录 T 里动 git，绝不能落到真实仓库（或任何别的仓库）上。
# - make_tmp 建 T 并隔离环境（HOME、全局 / 系统 git 配置、GIT_CEILING_DIRECTORIES），退出时只删 T。
# - git 被包装成函数：每次调用都必须带 `-C <目录>` 且目录在 T 之内，否则记下违规并退出。
# - 需要依赖当前目录执行的命令（install.sh、闸门脚本）只能经 run_at 在 T 内的目录里跑。
# - repo_snapshot 对真实仓库只做只读查询，用于前后对比「真实仓库没被动过」。
# 违规时除了退出当前（子）shell，还会写 $T/.violation，入口据此整体判失败——
# 命令替换里的 exit 只退出那一层，单靠退出码会被当成普通的失败结果。

set -euo pipefail

TESTS_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
REPO_ROOT=$(cd "$TESTS_ROOT/../.." && pwd -P)
ORIG_HOME=${HOME:-}
T=

die() {
  echo "[tests] $*" >&2
  exit 1
}

# 对真实仓库的只读快照。env -i 固定环境，使前后两次（隔离前后）结果可比；
# GIT_OPTIONAL_LOCKS=0 让 status 不回写索引。
repo_snapshot() {
  local run=(env -i PATH="$PATH" HOME="$ORIG_HOME" GIT_OPTIONAL_LOCKS=0 git -C "$REPO_ROOT")
  echo "HEAD $("${run[@]}" rev-parse HEAD)"
  echo "--- status"
  "${run[@]}" status --porcelain
  echo "--- refs"
  "${run[@]}" for-each-ref --format='%(objectname) %(refname)'
  echo "--- config"
  "${run[@]}" config --local --list
}

# 比较两份快照，不一致时打印差异并返回 1。
compare_snapshots() {
  if [ "$1" = "$2" ]; then
    return 0
  fi
  echo "[tests] 真实仓库 $REPO_ROOT 在运行前后不一致：" >&2
  diff <(printf '%s\n' "$1") <(printf '%s\n' "$2") >&2 || true
  return 1
}

_cleanup_tmp() {
  # 只删自己建的目录：T 必须是 make_tmp 记下的那个、且仍带着标记文件。
  if [ -n "${T:-}" ] && [ -n "${_T_OWNED:-}" ] && [ "$T" = "$_T_OWNED" ] && [ -f "$T/.tests-tmp-root" ]; then
    chmod -R u+w "$T" 2>/dev/null || true
    rm -rf "$T"
  fi
}

make_tmp() {
  local raw
  raw=$(mktemp -d "${TMPDIR:-/tmp}/agent-skills-tests.XXXXXX")
  # macOS 的 /var 是 /private/var 的软链，统一成物理路径，路径比较才可靠。
  T=$(cd "$raw" && pwd -P)
  [ -n "$T" ] && [ -d "$T" ] || die "临时目录创建失败"
  _T_OWNED=$T
  : >"$T/.tests-tmp-root"
  trap _cleanup_tmp EXIT
  trap 'exit 130' INT TERM

  mkdir -p "$T/home" "$T/bin"
  export HOME="$T/home"
  export GIT_CONFIG_GLOBAL="$T/gitconfig"
  export GIT_CONFIG_SYSTEM=/dev/null
  export GIT_CONFIG_NOSYSTEM=1
  # git 向上找仓库时不越过 T 的父目录，T 外即使有仓库也找不到。
  GIT_CEILING_DIRECTORIES=$(dirname "$T")
  export GIT_CEILING_DIRECTORIES
  export GIT_TERMINAL_PROMPT=0
  export GIT_EDITOR=true
  export GIT_MERGE_AUTOEDIT=no
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR REVERT_GATE_SKIP || true
  export GIT_AUTHOR_NAME=tester GIT_AUTHOR_EMAIL=tester@example.invalid
  export GIT_COMMITTER_NAME=tester GIT_COMMITTER_EMAIL=tester@example.invalid
  cat >"$GIT_CONFIG_GLOBAL" <<'EOF'
[user]
	name = tester
	email = tester@example.invalid
[init]
	defaultBranch = main
[commit]
	gpgsign = false
[advice]
	detachedHead = false
	skippedCherryPicks = false
[core]
	editor = true
	autocrlf = false
[pull]
	rebase = false
[push]
	default = simple
EOF
  # 离开调用者的当前目录：即使哪条命令漏了 -C，也只会落在 T 里。
  cd "$T"
}

_require_tmp() {
  [ -n "${T:-}" ] && [ -d "$T" ] && [ -f "$T/.tests-tmp-root" ] || {
    echo "[tests] 安全检查失败：临时根 T 未就绪" >&2
    exit 1
  }
}

_violation() {
  echo "[tests] 安全检查失败：$*" >&2
  [ -n "${T:-}" ] && [ -d "$T" ] && echo "$*" >>"$T/.violation"
  if [ -n "${CASE_DIR:-}" ] && [ -d "$CASE_DIR" ] && [ ! -f "$CASE_DIR/.reason" ]; then
    echo "安全检查失败：$*" >"$CASE_DIR/.reason"
  fi
  exit 1
}

# 目录（物理路径）在 T 之内则返回 0。
_inside_tmp() {
  local d
  d=$(cd "$1" 2>/dev/null && pwd -P) || return 1
  case "$d/" in
    "$T"/*) return 0 ;;
  esac
  return 1
}

# 断言当前目录在 T 之内。
in_tmp() {
  _require_tmp
  _inside_tmp "$PWD" || _violation "当前目录 $PWD 不在临时根 $T 之下"
}

# 所有测试里的 git 调用都经过这里，见文件说明。
git() {
  _require_tmp
  [ "${1:-}" = -C ] && [ -n "${2:-}" ] || _violation "git 调用必须带 -C <目录>：git $*"
  _inside_tmp "$2" || _violation "git -C 的目录不在临时根之下：$2"
  in_tmp
  command git "$@"
}

# 在 T 内的目录里执行命令（子 shell，不改调用者的当前目录）。
run_at() {
  local dir=$1
  shift
  _inside_tmp "$dir" || _violation "run_at 的目录不在临时根之下：$dir"
  (cd "$dir" && in_tmp && "$@")
}

# ---------------------------------------------------------------------------
# 用例框架
#
# 测试入口用 `register <名字>` 按运行顺序登记用例，用例体是函数 `case_<名字>`，
# 最后调用 `run_cases "$@"`（支持 `-v` 与按名选跑）。每个用例在独立子 shell 里以 set -e 运行，
# 输出写进自己的日志；用 fail 给出失败原因，意外出错时记下出错的命令。

CASES=()
OUT=
RC=0
CASE=
CASE_DIR=
VERBOSE=0

register() {
  CASES+=("$1")
}

fail() {
  echo "$*" >"$CASE_DIR/.reason"
  echo "[FAIL] $*"
  exit 1
}

_on_err() {
  # 只在 errexit 生效时记：try 里关了 errexit，那里的非零退出码是被测结果，不算出错。
  case $- in *e*) ;; *) return 0 ;; esac
  [ -f "$CASE_DIR/.reason" ] || echo "意外出错（第 $1 行）：$2" >"$CASE_DIR/.reason"
}

# 执行命令，把合并后的输出存进 OUT、退出码存进 RC，不因失败中止用例。
try() {
  echo "\$ $*"
  set +e
  OUT=$("$@" 2>&1)
  RC=$?
  set -e
  [ -z "$OUT" ] || printf '%s\n' "$OUT"
  echo "[rc=$RC]"
}

expect_rc() {
  [ "$RC" = "$1" ] || fail "${2:-最近一条命令}：期望退出码 $1，实际 $RC"
}

expect_nonzero() {
  [ "$RC" != 0 ] || fail "${1:-最近一条命令}：期望被拒（非零退出码），实际放行"
}

expect_out() {
  case $OUT in
    *"$1"*) ;;
    *) fail "${2:-最近一条命令}：输出里没有「$1」" ;;
  esac
}

expect_not_out() {
  case $OUT in
    *"$1"*) fail "${2:-最近一条命令}：输出里不应有「$1」" ;;
  esac
}

expect_eq() {
  [ "$1" = "$2" ] || fail "${3:-值不符}：期望 $2，实际 $1"
}

_run_one() {
  local name=$1 start rc reason
  CASE=$name
  CASE_DIR=$T/cases/$name
  mkdir -p "$CASE_DIR"
  start=$SECONDS
  set +e
  (
    set -eE
    trap '_on_err "$LINENO" "$BASH_COMMAND"' ERR
    "case_$name"
  ) >"$CASE_DIR.log" 2>&1
  rc=$?
  set -e
  if [ "$rc" = 0 ] && [ ! -f "$CASE_DIR/.reason" ]; then
    echo "PASS $name ($((SECONDS - start))s)"
    _PASSED=$((_PASSED + 1))
  else
    reason=$(cat "$CASE_DIR/.reason" 2>/dev/null || echo "退出码 $rc")
    echo "FAIL $name: $reason"
    _FAILED+=("$name")
    [ "$VERBOSE" = 1 ] || sed -e 's/^/    | /' "$CASE_DIR.log" | tail -n 25
  fi
  if [ "$VERBOSE" = 1 ]; then
    sed -e 's/^/    | /' "$CASE_DIR.log"
  fi
}

run_cases() {
  local selected=() name known start
  while [ $# -gt 0 ]; do
    case $1 in
      -v) VERBOSE=1 ;;
      -*) die "未知参数：$1" ;;
      *) selected+=("$1") ;;
    esac
    shift
  done
  [ ${#selected[@]} -gt 0 ] || selected=("${CASES[@]}")
  for name in "${selected[@]}"; do
    known=0
    for c in "${CASES[@]}"; do [ "$c" = "$name" ] && known=1; done
    [ "$known" = 1 ] || die "没有这个用例：$name"
  done
  _PASSED=0
  _FAILED=()
  start=$SECONDS
  for name in "${selected[@]}"; do
    _run_one "$name"
  done
  if [ -f "$T/.violation" ]; then
    echo "FAIL safety: 有命令试图在临时根之外执行 git：$(tr '\n' ';' <"$T/.violation")"
    _FAILED+=(safety)
  fi
  echo "-- ${_PASSED} passed, ${#_FAILED[@]} failed ($((SECONDS - start))s)"
  [ ${#_FAILED[@]} = 0 ]
}
