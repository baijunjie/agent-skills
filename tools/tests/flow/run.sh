#!/usr/bin/env bash
# 流程脚本（plugins/setup-git/scripts/flow/）的回归测试。
#   bash tools/tests/flow/run.sh [-v] [<用例名>...]
# 环境变量 FLOW_TEMPLATE_DIR 可指向另一份 flow 目录（如故意改坏的副本），默认测仓库里的那份。
#
# 每条用例对系统里有的 sh、dash、bash 各登记一次（用例名带 _sh / _dash / _bash 后缀），
# 被测脚本用对应的 shell 执行：装出的 skill 写的是 `sh <脚本>`，sh 在不同系统上是不同的实现。
# 基础夹具：bare remote 与两个 clone——a 是自己，b 是同事。main 已推送：C0（f1、f2 各 6 行）。
# a 的 .gitignore 忽略 .worktrees/ 与 build/。

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)/lib/common.sh"

FLOW_SRC=${FLOW_TEMPLATE_DIR:-$REPO_ROOT/plugins/setup-git/scripts/flow}
FLOW_SRC=$(cd "$FLOW_SRC" && pwd -P)
[ -f "$FLOW_SRC/flow-lib.sh" ] || die "找不到流程脚本：$FLOW_SRC"

SNAP_BEFORE=$(repo_snapshot)
make_tmp
FLOW=$T/flow
cp -R "$FLOW_SRC" "$FLOW"

# ---------------------------------------------------------------------------
# 夹具与小工具

lines() { # lines <前缀> <个数>
  local i
  for i in $(seq 1 "$2"); do echo "${1}_line_$i"; done
}

put() { # put <文件> <行>...
  mkdir -p "$(dirname "$1")"
  printf '%s\n' "${@:2}" >"$1"
}

commit_all() { # commit_all <目录> <提交信息>
  git -C "$1" add -A
  git -C "$1" commit -q -m "$2"
}

sha() { git -C "$1" rev-parse "$2"; }

build_base() {
  local base=$T/base
  mkdir -p "$base"
  git -C "$base" init -q --bare -b main remote.git
  git -C "$base" clone -q remote.git a 2>/dev/null
  local a=$base/a
  put "$a/.gitignore" ".worktrees/" "build/"
  put "$a/f1" $(lines alpha 6)
  put "$a/f2" $(lines gamma 6)
  commit_all "$a" C0
  git -C "$a" push -q -u origin main
  git -C "$base" clone -q remote.git b
}

fixture() {
  D=$CASE_DIR/repo
  cp -R "$T/base" "$D"
  A=$D/a
  B=$D/b
  R=$D/remote.git
  git -C "$A" remote set-url origin "$R"
  git -C "$B" remote set-url origin "$R"
}

# 在 a 里建 worktree 分支：new_wt <短名> [<起点>]，路径写入 WT，记下目标分支 main 与切出点。
new_wt() {
  WT=$A/.worktrees/$1
  git -C "$A" worktree add -q -b "feat/$1" "$WT" "${2:-main}"
  git -C "$A" config "branch.feat/$1.targetBranch" main
  git -C "$A" config "branch.feat/$1.forkPoint" "$(sha "$A" "${2:-main}")"
}

# b 推一个提交到 main：b_push <文件> <提交信息> <行>...
b_push() {
  git -C "$B" pull -q --ff-only
  put "$B/$1" "${@:3}"
  commit_all "$B" "$2"
  git -C "$B" push -q origin main
}

# 在目录里用当前 shell 跑流程脚本：flow <目录> <脚本短名> [参数]...，结果进 OUT / RC。
flow() {
  local dir=$1 name=$2
  shift 2
  # LC_ALL=C：变量名后紧跟中文时，bash 在 C locale 下会把多字节字符读进变量名，要用 ${…} 隔开。
  try run_at "$dir" env LC_ALL=C "$FLOW_SH" "$FLOW/flow-$name.sh" "$@"
}

assert_ref() { # assert_ref <目录> <ref> <期望 sha> [说明]
  expect_eq "$(sha "$1" "$2")" "$3" "${4:-$2 的位置}"
}

msgfile() { # msgfile <行>...：写一份提交信息文件，路径写入 MSG
  MSG=$CASE_DIR/msg.$RANDOM
  printf '%s\n' "$@" >"$MSG"
}

# ---------------------------------------------------------------------------
# flow-record.sh

case_record_first() {
  fixture
  git -C "$A" branch feat/x
  flow "$A" record feat/x main main
  expect_rc 0
  expect_eq "$(git -C "$A" config branch.feat/x.targetBranch)" main
  expect_eq "$(git -C "$A" config branch.feat/x.forkPoint)" "$(sha "$A" main)"
}

case_record_keeps_fork() {
  fixture
  local c0
  c0=$(sha "$A" main)
  new_wt x
  put "$WT/f3" x
  commit_all "$WT" X
  flow "$A" record feat/x develop feat/x
  expect_rc 0
  expect_out "不改写"
  expect_eq "$(git -C "$A" config branch.feat/x.forkPoint)" "$c0" "forkPoint 被改写了"
  expect_eq "$(git -C "$A" config branch.feat/x.targetBranch)" develop "targetBranch 应每次都写"
}

case_record_rejects_remote_prefix() {
  fixture
  git -C "$A" branch feat/x
  flow "$A" record feat/x origin/main main
  expect_rc 2
  expect_out "不带远端前缀"
  try git -C "$A" config branch.feat/x.targetBranch
  expect_rc 1 "不应写入 targetBranch"
}

case_record_rejects_non_ancestor() {
  fixture
  git -C "$A" branch feat/x
  put "$A/f3" x
  commit_all "$A" later
  flow "$A" record feat/x main main
  expect_rc 2
  expect_out "不是分支 feat/x 的祖先"
  try git -C "$A" config branch.feat/x.forkPoint
  expect_rc 1 "不应写入 forkPoint"
  try git -C "$A" config branch.feat/x.targetBranch
  expect_rc 1 "报错时也不应写入 targetBranch"
}

# ---------------------------------------------------------------------------
# flow-squash.sh

# feat/x 上三个提交；切出后 main 又前进了一个提交（f2），压平必须仍在原基点上。
squash_scene() {
  fixture
  FORK=$(sha "$A" main)
  new_wt x
  put "$WT/f3" one
  commit_all "$WT" "wip 1"
  put "$WT/f3" one two
  commit_all "$WT" "wip 2"
  put "$WT/f1" $(lines alpha 6) extra
  commit_all "$WT" "wip 3"
  put "$A/f2" $(lines delta 6)
  commit_all "$A" "main moves"
  PRE=$(sha "$WT" HEAD)
}

case_squash_basic() {
  squash_scene
  msgfile "feat: add f3"
  flow "$WT" squash main "$MSG"
  expect_rc 0
  expect_out "$PRE"
  expect_eq "$(git -C "$WT" rev-list --count "$FORK..HEAD")" 1 "应压成一个提交"
  assert_ref "$WT" HEAD^ "$FORK" "父提交应是原基点"
  try git -C "$WT" diff --quiet "$PRE" HEAD
  expect_rc 0 "内容应与压前一致"
  expect_eq "$(git -C "$WT" log -1 --format=%s)" "feat: add f3"
}

case_squash_dirty() {
  squash_scene
  put "$WT/untracked" x
  msgfile "feat: add f3"
  flow "$WT" squash main "$MSG"
  expect_rc 1
  expect_out "工作树不干净"
  assert_ref "$WT" HEAD "$PRE"
}

case_squash_nothing() {
  fixture
  git -C "$A" switch -q -c feat/x
  msgfile "feat: nothing"
  flow "$A" squash main "$MSG"
  expect_rc 1
  expect_out "没有领先"
}

case_squash_merge_commit() {
  squash_scene
  git -C "$WT" merge -q --no-edit main
  local before
  before=$(sha "$WT" HEAD)
  msgfile "feat: add f3"
  flow "$WT" squash main "$MSG"
  expect_rc 1
  expect_out "merge 提交"
  assert_ref "$WT" HEAD "$before"
}

case_squash_reverts_kept() {
  squash_scene
  put "$WT/f4" y
  git -C "$WT" add -A
  git -C "$WT" commit -q -m "drop old thing" -m "Reverts: abcdef1234"
  local before
  before=$(sha "$WT" HEAD)
  msgfile "feat: add f3"
  flow "$WT" squash main "$MSG"
  expect_rc 1
  expect_out "Reverts: abcdef1234"
  assert_ref "$WT" HEAD "$before"
  msgfile "feat: add f3" "" "Reverts: abcdef1234"
  flow "$WT" squash main "$MSG"
  expect_rc 0
}

# 分支自己提交又自己 revert 的，被撤销的提交不进目标分支，不要求保留声明。
case_squash_internal_revert() {
  squash_scene
  git -C "$WT" revert --no-edit HEAD >/dev/null
  msgfile "feat: add f3"
  flow "$WT" squash main "$MSG"
  expect_rc 0
}

# revert 了基点之前（已在目标分支上）的提交：声明必须保留。
case_squash_revert_base_commit() {
  fixture
  put "$A/f4" base-thing
  commit_all "$A" "base thing"
  local base
  base=$(sha "$A" main)
  new_wt x
  put "$WT/f3" one
  commit_all "$WT" "wip 1"
  git -C "$WT" revert --no-edit "$base" >/dev/null
  msgfile "feat: add f3"
  flow "$WT" squash main "$MSG"
  expect_rc 1
  expect_out "Reverts: $base"
  msgfile "feat: add f3" "" "Reverts: $base"
  flow "$WT" squash main "$MSG"
  expect_rc 0
}

case_squash_from_subdir() {
  squash_scene
  put "$WT/sub/keep" kept
  commit_all "$WT" "wip 4"
  msgfile "feat: add f3"
  flow "$WT/sub" squash main "$MSG"
  expect_rc 0
  assert_ref "$WT" HEAD^ "$FORK" "从子目录执行也应在原基点上压平"
}

case_squash_hook_rejects() {
  squash_scene
  local hooks
  hooks=$A/.git/hooks
  mkdir -p "$hooks"
  printf '#!/bin/sh\necho "rejected by hook" >&2\nexit 1\n' >"$hooks/commit-msg"
  chmod +x "$hooks/commit-msg"
  msgfile "feat: add f3"
  flow "$WT" squash main "$MSG"
  expect_rc 1
  expect_out "已退回压前提交"
  assert_ref "$WT" HEAD "$PRE"
  expect_eq "$(git -C "$WT" status --porcelain)" "" "退回后工作树应干净"
}

case_squash_check_ok() {
  squash_scene
  git -C "$WT" reset -q --soft "$FORK"
  git -C "$WT" reset -q
  git -C "$WT" add f3
  git -C "$WT" commit -q -m "feat: add f3"
  git -C "$WT" add f1
  git -C "$WT" commit -q -m "feat: extend f1"
  flow "$WT" squash --check main "$PRE"
  expect_rc 0
}

case_squash_check_wrong_base() {
  squash_scene
  git -C "$WT" reset -q --soft main
  git -C "$WT" commit -q -m "feat: squashed on the wrong base"
  flow "$WT" squash --check main "$PRE"
  expect_rc 1
  expect_out "基点变了"
}

case_squash_check_lost_change() {
  squash_scene
  git -C "$WT" reset -q --soft "$FORK"
  git -C "$WT" checkout -q "$FORK" -- f1
  git -C "$WT" commit -q -m "feat: add f3"
  flow "$WT" squash --check main "$PRE"
  expect_rc 1
  expect_out "内容与压前提交不一致"
}

# ---------------------------------------------------------------------------
# flow-push.sh

pr_branch() { # 在 a 的主工作副本里建 feat/x 并提交一个改动
  fixture
  git -C "$A" switch -q -c feat/x
  put "$A/f3" one
  commit_all "$A" "feat: one"
}

case_push_first() {
  pr_branch
  flow "$A" push origin feat/x feat/x
  expect_rc 0
  assert_ref "$R" refs/heads/feat/x "$(sha "$A" feat/x)"
  expect_eq "$(git -C "$A" rev-parse --abbrev-ref feat/x@{u})" origin/feat/x "应设好上游"
}

case_push_ff_and_uptodate() {
  pr_branch
  flow "$A" push origin feat/x feat/x
  put "$A/f3" one two
  commit_all "$A" "feat: two"
  flow "$A" push origin feat/x feat/x
  expect_rc 0
  assert_ref "$R" refs/heads/feat/x "$(sha "$A" feat/x)"
  flow "$A" push origin feat/x feat/x
  expect_rc 0
  expect_out "已是最新"
}

case_push_rewrite_needs_force() {
  pr_branch
  flow "$A" push origin feat/x feat/x
  local pushed
  pushed=$(sha "$A" feat/x)
  git -C "$A" commit -q --amend -m "feat: one, reworded"
  flow "$A" push origin feat/x feat/x
  expect_rc 1
  expect_out "--force"
  assert_ref "$R" refs/heads/feat/x "$pushed" "没给 --force 不应推"
  flow "$A" push origin feat/x feat/x --force
  expect_rc 0
  assert_ref "$R" refs/heads/feat/x "$(sha "$A" feat/x)"
}

case_push_foreign_commits() {
  pr_branch
  flow "$A" push origin feat/x feat/x
  git -C "$B" fetch -q origin
  git -C "$B" switch -q -c feat/x origin/feat/x
  put "$B/f4" from-b
  commit_all "$B" "fix from b"
  git -C "$B" push -q origin feat/x
  local theirs
  theirs=$(sha "$B" feat/x)
  git -C "$A" commit -q --amend -m "feat: one, reworded"
  flow "$A" push origin feat/x feat/x --force
  expect_rc 1
  expect_out "有本地没有的提交"
  expect_out "fix from b"
  assert_ref "$R" refs/heads/feat/x "$theirs" "不应盖掉同事的提交"
}

case_push_diverged_without_rewrite() {
  pr_branch
  flow "$A" push origin feat/x feat/x
  git -C "$B" fetch -q origin
  git -C "$B" switch -q -c feat/x origin/feat/x
  put "$B/f4" from-b
  commit_all "$B" "fix from b"
  git -C "$B" push -q origin feat/x
  put "$A/f3" one two
  commit_all "$A" "feat: two"
  flow "$A" push origin feat/x feat/x
  expect_rc 1
  expect_out "有本地没有的提交"
}

case_push_rejected_by_hook() {
  pr_branch
  local hooks
  hooks=$A/.git/hooks
  mkdir -p "$hooks"
  printf '#!/bin/sh\necho "pre-push says no" >&2\nexit 1\n' >"$hooks/pre-push"
  chmod +x "$hooks/pre-push"
  flow "$A" push origin feat/x feat/x
  expect_rc 1
  expect_out "推送被拒绝"
  try git -C "$R" rev-parse --verify --quiet refs/heads/feat/x
  expect_nonzero "远端不应有这个分支"
}

case_push_bad_remote() {
  pr_branch
  flow "$A" push nosuchremote feat/x feat/x
  expect_rc 2
}

# ---------------------------------------------------------------------------
# flow-restack.sh

# a 的 main 上有一个未推送的提交 U；feat/x 从 U 切出、有自己的提交；feat/y 从已推送的 C0 切出。
# b 往 main 推了一个提交，a 把 main rebase 到远端最新（U 被改写成 U'），OLD 是 rebase 前的位置。
restack_scene() {
  fixture
  put "$A/f1" $(lines alpha 6) local-unpushed
  commit_all "$A" U
  new_wt y "$(sha "$A" main^)"
  put "$WT/fy" y
  commit_all "$WT" "feat y"
  WTY=$WT
  new_wt x
  put "$WT/fx" x
  commit_all "$WT" "feat x"
  WTX=$WT
  b_push f2 "from b" $(lines gamma 6) b-line
  git -C "$A" fetch -q origin
  OLD=$(sha "$A" main)
  git -C "$A" rebase -q origin/main
}

case_restack_moves() {
  restack_scene
  local ybefore
  ybefore=$(sha "$A" feat/y)
  flow "$A" restack main "$OLD"
  expect_rc 0
  expect_out "feat/x"
  try git -C "$A" merge-base --is-ancestor main feat/x
  expect_rc 0 "feat/x 应在新的 main 之上"
  expect_eq "$(git -C "$A" rev-list --count main..feat/x)" 1 "只应搬 feat/x 自己的提交"
  try git -C "$A" merge-base --is-ancestor "$OLD" feat/x
  expect_nonzero "feat/x 里不应还有改写前的 U"
  expect_eq "$(git -C "$A" config branch.feat/x.forkPoint)" "$(sha "$A" main)" "forkPoint 应更新"
  assert_ref "$A" feat/y "$ybefore" "feat/y 不含改写前的提交，不应动"
  flow "$A" restack main "$OLD"
  expect_rc 0
  expect_out "已搬：无"
}

case_restack_dirty() {
  restack_scene
  put "$WTX/scratch" x
  local before
  before=$(sha "$A" feat/x)
  flow "$A" restack main "$OLD"
  expect_rc 1
  expect_out "不干净"
  assert_ref "$A" feat/x "$before"
}

case_restack_conflict_resume() {
  restack_scene
  # feat/x 改了 b 也改过的那几行，搬的时候冲突。
  put "$WTX/f2" $(lines gamma 6) x-line
  commit_all "$WTX" "feat x touches f2"
  flow "$A" restack main "$OLD"
  expect_rc 1
  expect_out "rebase 冲突"
  put "$WTX/f2" $(lines gamma 6) b-line x-line
  git -C "$WTX" add f2
  GIT_EDITOR=true git -C "$WTX" rebase --continue >/dev/null
  flow "$A" restack main "$OLD"
  expect_rc 0
  expect_eq "$(git -C "$A" config branch.feat/x.forkPoint)" "$(sha "$A" main)" "续跑后 forkPoint 应更新"
  expect_eq "$(git -C "$A" rev-list --count main..feat/x)" 2
}

# 有与目标分支同名的 tag 时，必须搬到分支上而不是 tag 上。
case_restack_tag_same_name() {
  restack_scene
  git -C "$A" tag main "$(sha "$A" main~2)"
  flow "$A" restack main "$OLD"
  expect_rc 0
  expect_eq "$(git -C "$A" merge-base refs/heads/main feat/x)" "$(sha "$A" refs/heads/main)" "应搬到分支 main 上"
}

case_restack_missing_worktree_dir() {
  restack_scene
  rm -rf "$WTX"
  flow "$A" restack main "$OLD"
  expect_rc 1
  expect_out "worktree prune"
}

case_restack_pushed_branch() {
  restack_scene
  git -C "$WTX" push -q -u origin feat/x
  local before
  before=$(sha "$A" feat/x)
  flow "$A" restack main "$OLD"
  expect_rc 1
  expect_out "--allow-pushed feat/x"
  assert_ref "$A" feat/x "$before" "没放行不应搬"
  flow "$A" restack main "$OLD" --allow-pushed feat/x
  expect_rc 0
  try git -C "$A" merge-base --is-ancestor main feat/x
  expect_rc 0 "放行后应搬到新的 main 之上"
}

case_restack_no_worktree() {
  restack_scene
  git -C "$A" branch feat/z "$OLD"
  git -C "$A" config branch.feat/z.targetBranch main
  flow "$A" restack main "$OLD"
  expect_rc 1
  expect_out "没有检出在任何 worktree 里"
}

# 冲突后没解完就重跑：要报 rebase 没做完，而不是「没有检出」。
case_restack_rerun_mid_rebase() {
  restack_scene
  put "$WTX/f2" $(lines gamma 6) x-line
  commit_all "$WTX" "feat x touches f2"
  flow "$A" restack main "$OLD"
  expect_rc 1
  flow "$A" restack main "$OLD"
  expect_rc 1
  expect_out "没做完"
}

# ---------------------------------------------------------------------------
# flow-cleanup.sh

case_cleanup_merged_worktree() {
  fixture
  new_wt x
  put "$WT/f3" x
  commit_all "$WT" X
  git -C "$A" merge -q --ff-only feat/x
  flow "$WT" cleanup feat/x --merged-into main
  expect_rc 0
  [ ! -e "$WT" ] || fail "worktree 应已删除"
  try git -C "$A" rev-parse --verify --quiet refs/heads/feat/x
  expect_nonzero "分支应已删除"
  try git -C "$A" config --get branch.feat/x.forkPoint
  expect_nonzero "分支记录应随之删除"
}

case_cleanup_not_merged() {
  fixture
  new_wt x
  put "$WT/f3" x
  commit_all "$WT" X
  flow "$A" cleanup feat/x --merged-into main
  expect_rc 1
  expect_out "还没合进"
  [ -d "$WT" ] || fail "worktree 不应删"
}

case_cleanup_dirty_worktree() {
  fixture
  new_wt x
  put "$WT/scratch" x
  flow "$A" cleanup feat/x --merged-into main
  expect_rc 1
  expect_out "未提交或未跟踪"
  [ -d "$WT" ] || fail "worktree 不应删"
}

case_cleanup_ignored_files() {
  fixture
  new_wt x
  put "$WT/build/out.txt" generated
  flow "$A" cleanup feat/x --merged-into main
  expect_rc 1
  expect_out "build/"
  [ -d "$WT" ] || fail "没带 --ignored-ok 不应删"
  flow "$A" cleanup feat/x --merged-into main --ignored-ok
  expect_rc 0
  [ ! -e "$WT" ] || fail "worktree 应已删除"
}

# 分支已合进 main，但它的 worktree 里停着一个 rebase（工作树干净）：不能删。
case_cleanup_mid_rebase() {
  fixture
  new_wt x
  put "$WT/f3" x
  commit_all "$WT" X
  git -C "$A" merge -q --ff-only feat/x
  try git -C "$WT" rebase -q -i --exec false HEAD~1
  expect_nonzero "夹具：rebase 应停住"
  flow "$A" cleanup feat/x --merged-into main
  expect_rc 1
  expect_out "没做完的 rebase"
  [ -d "$WT" ] || fail "worktree 不应删"
  try git -C "$A" rev-parse --verify --quiet refs/heads/feat/x
  expect_rc 0 "分支不应删"
}

case_cleanup_main_copy_mid_rebase() {
  pr_branch
  git -C "$A" config branch.feat/x.targetBranch main
  git -C "$A" push -q origin feat/x
  try git -C "$A" rebase -q -i --exec false HEAD~1
  expect_nonzero "夹具：rebase 应停住"
  git -C "$A" update-ref refs/heads/feat/x "$(sha "$R" refs/heads/feat/x)"
  flow "$A" cleanup feat/x --pushed-to origin/feat/x
  expect_rc 1
  expect_out "没做完的 rebase"
}

case_cleanup_missing_worktree_dir() {
  fixture
  new_wt x
  git -C "$A" merge -q --ff-only feat/x
  rm -rf "$WT"
  flow "$A" cleanup feat/x --merged-into main
  expect_rc 1
  expect_out "worktree prune"
}

case_cleanup_pushed_linked_worktree() {
  fixture
  new_wt x
  put "$WT/f3" x
  commit_all "$WT" X
  git -C "$WT" push -q origin feat/x
  flow "$WT" cleanup feat/x --pushed-to origin/feat/x
  expect_rc 0
  [ ! -e "$WT" ] || fail "worktree 应已删除"
  expect_eq "$(git -C "$A" symbolic-ref --short HEAD)" main "主工作副本不应被切走"
}

case_cleanup_pushed_main_copy() {
  pr_branch
  git -C "$A" config branch.feat/x.targetBranch main
  git -C "$A" push -q origin feat/x
  flow "$A" cleanup feat/x --pushed-to origin/feat/x
  expect_rc 0
  expect_eq "$(git -C "$A" symbolic-ref --short HEAD)" main "应切回目标分支"
  try git -C "$A" rev-parse --verify --quiet refs/heads/feat/x
  expect_nonzero "分支应已删除"
}

case_cleanup_pushed_mismatch() {
  pr_branch
  git -C "$A" config branch.feat/x.targetBranch main
  git -C "$A" push -q origin feat/x
  put "$A/f3" one two
  commit_all "$A" "not pushed"
  flow "$A" cleanup feat/x --pushed-to origin/feat/x
  expect_rc 1
  expect_out "不在同一提交"
  expect_eq "$(git -C "$A" symbolic-ref --short HEAD)" feat/x
}

case_cleanup_target_busy() {
  pr_branch
  git -C "$A" config branch.feat/x.targetBranch main
  git -C "$A" push -q origin feat/x
  git -C "$A" worktree add -q "$A/.worktrees/m" main
  flow "$A" cleanup feat/x --pushed-to origin/feat/x
  expect_rc 1
  expect_out "切不回 main"
  try git -C "$A" rev-parse --verify --quiet refs/heads/feat/x
  expect_rc 0 "分支不应删"
}

# ---------------------------------------------------------------------------

FLOW_SHELLS=()
for s in sh dash bash; do
  command -v "$s" >/dev/null 2>&1 && FLOW_SHELLS+=("$s")
done
[ ${#FLOW_SHELLS[@]} -gt 0 ] || die "一个可用的 shell 都没有"

for base_case in $(declare -F | awk '{ print $3 }' | sed -n 's/^case_//p'); do
  for s in "${FLOW_SHELLS[@]}"; do
    eval "case_${base_case}_$s() { FLOW_SH=$s; case_$base_case; }"
    register "${base_case}_$s"
  done
done

build_base
run_cases "$@" || rc=$?
compare_snapshots "$SNAP_BEFORE" "$(repo_snapshot)" || rc=1
exit "${rc:-0}"
