#!/usr/bin/env bash
# 回退闸门（plugins/setup-git/scripts/githooks/）的回归测试。
#   bash tools/tests/gate/run.sh [-v] [<用例名>...]
# 环境变量 GATE_TEMPLATE_DIR 可指向另一份 githooks 目录（如故意改坏的副本），默认测仓库里的那份。
#
# 每个用例从同一份基础夹具复制出独立的 bare remote 与两个 clone：
#   a —— 装了闸门的 clone，main 检出在这里；b —— 没装闸门的同事。
# main 已推送的历史：C0（f1=alpha、f2=gamma）→ G（闸门脚本）→ M1（f1 改成 beta）→ M2（f2 改成 delta）；
# 远端另有 develop 分支。内容判据要「删掉的行重现」才算撤销，所以靠它拦的用例里被撤销的提交都改写已有内容；
# 只增不删的形态（纯新增文件、只追加）靠切出点判据，那些用例要记 forkPoint（见 new_wt / new_pr）。
# 拦下的断言看退出码与关键提示片段，不断言整句；ref 有没有动另外核对。

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)/lib/common.sh"

GATE_SRC=${GATE_TEMPLATE_DIR:-$REPO_ROOT/plugins/setup-git/scripts/githooks}
GATE_SRC=$(cd "$GATE_SRC" && pwd -P)
[ -f "$GATE_SRC/revert-gate.py" ] || die "找不到闸门脚本：$GATE_SRC"

SNAP_BEFORE=$(repo_snapshot)
make_tmp

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

# rebase -i 的序列编辑器：把标题匹配 $DROP 的 pick 改成 drop。
cat >"$T/bin/drop-editor" <<'EOF'
#!/bin/sh
sed -e "/${DROP}\$/s/^pick/drop/" "$1" >"$1.tmp" && mv "$1.tmp" "$1"
EOF
chmod +x "$T/bin/drop-editor"

install_gate() { # install_gate <clone>：与真实安装流程相同，复制 githooks、写 branches、运行 install.sh
  mkdir -p "$1/.githooks"
  cp -p "$GATE_SRC/"* "$1/.githooks/"
  put "$1/.githooks/branches" "# 回退闸门的常驻守护分支，主分支在第一行" main
  run_at "$1" sh .githooks/install.sh
}

build_base() {
  local base=$T/base
  mkdir -p "$base"
  git -C "$base" init -q --bare -b main remote.git
  git -C "$base" clone -q remote.git a 2>/dev/null
  local a=$base/a
  put "$a/.gitignore" ".worktrees/"
  put "$a/README" "test repo"
  put "$a/f1" $(lines alpha 6)
  put "$a/f2" $(lines gamma 6)
  commit_all "$a" C0
  git -C "$a" push -q -u origin main
  install_gate "$a" >/dev/null
  commit_all "$a" "chore: add revert gate"
  put "$a/f1" $(lines beta 6)
  commit_all "$a" M1
  put "$a/f2" $(lines delta 6)
  commit_all "$a" M2
  git -C "$a" push -q origin main
  git -C "$a" push -q origin main:develop
  git -C "$base" clone -q remote.git b
}

# 每个用例的夹具：复制基础夹具并改回各自的远端地址。
fixture() {
  D=$CASE_DIR/repo
  cp -R "$T/base" "$D"
  A=$D/a
  B=$D/b
  R=$D/remote.git
  git -C "$A" remote set-url origin "$R"
  git -C "$B" remote set-url origin "$R"
}

# 在 a 里按规则建 worktree 分支：new_wt <短名> [<目标分支>]，路径写入 WT。
new_wt() {
  local target=${2:-main}
  WT=$A/.worktrees/$1
  git -C "$A" worktree add -q -b "feat/$1" "$WT" "$target"
  git -C "$A" config "branch.feat/$1.targetBranch" "$target"
  git -C "$A" config "branch.feat/$1.forkPoint" "$(sha "$A" "$target")"
}

# 在 a 里按 git-pr 流程建 PR 分支：new_pr <短名> [<目标分支>]，记下目标分支与切出点。
# 两个流程共用这两个键，所以与 new_wt 的差别只在于不建 worktree（主工作副本直接切过去）。
new_pr() {
  local target=${2:-main}
  git -C "$A" switch -q -c "feat/$1" "$target"
  git -C "$A" config "branch.feat/$1.targetBranch" "$target"
  git -C "$A" config "branch.feat/$1.forkPoint" "$(sha "$A" "$target")"
}

# b 推一个提交：b_push <文件> <提交信息> <行>...
b_push() {
  git -C "$B" pull -q --ff-only
  put "$B/$1" "${@:3}"
  commit_all "$B" "$2"
  git -C "$B" push -q origin main
}

# 闸门预检，与规则里的命令等价：从第一个常驻守护分支上取已提交的脚本执行。
precheck() { # precheck <clone> <目标分支> <分支>
  local dir=$1 b s
  b=$(git -C "$dir" config --get-all revert-gate.branch | head -n1) || true
  s=$(git -C "$dir" show "refs/heads/$b:.githooks/revert-gate.py" 2>/dev/null) || {
    echo "闸门未就绪" >&2
    return 1
  }
  run_at "$dir" python3 -I -c "$s" check "$2" "$3"
}

# PR 推送前的预检，与 git-pr skill 里的命令等价：脚本取自目标分支的远端跟踪分支。
precheck_pr() { # precheck_pr <clone> <远端跟踪 ref> <分支>
  local dir=$1 s
  s=$(git -C "$dir" show "$2:.githooks/revert-gate.py" 2>/dev/null) || {
    echo "闸门未就绪" >&2
    return 1
  }
  run_at "$dir" python3 -I -c "$s" check-pr "$2" "$3"
}

assert_ref() { # assert_ref <目录> <ref> <期望 sha> [说明]
  expect_eq "$(sha "$1" "$2")" "$3" "${4:-$2 的位置}"
}

assert_clean() {
  expect_eq "$(git -C "$1" status --porcelain --untracked-files=no)" "" "${2:-$1 的工作树与暂存区应干净}"
}

remote_main() { git -C "$R" rev-parse main; }

# 被闸门拦下：非零退出且输出里有闸门的标识，排除别的原因导致的失败。
expect_blocked() {
  expect_nonzero "$1"
  expect_out "[revert-gate]" "$1"
}

# 本地一层的撤销提示（压平那套）里的关键片段。
SQUASH_HINT='reset --soft $(git merge-base HEAD main)'

# ---------------------------------------------------------------------------
# 拦下

register block_wrong_squash
case_block_wrong_squash() {
  fixture
  new_wt x
  put "$WT/f3" $(lines feat 4)
  commit_all "$WT" "feat: f3"
  put "$A/f1" $(lines eps 6)
  commit_all "$A" M3
  git -C "$A" push -q
  # 错误压平：换到最新的 main 上提交，f1 的旧内容被当成改动带进来，撤销了 M3。
  git -C "$WT" reset -q --soft main
  git -C "$WT" commit -q -m "feat: squashed"
  local before
  before=$(sha "$A" main)
  try precheck "$A" main feat/x
  expect_rc 1 预检
  expect_out "$SQUASH_HINT" 预检
  try git -C "$A" merge --ff-only feat/x
  expect_blocked "merge --ff-only"
  expect_out "$SQUASH_HINT" "merge --ff-only"
  assert_ref "$A" main "$before"
  try git -C "$A" reset --merge
  expect_rc 0 "reset --merge 复原"
  assert_clean "$A"
}

register block_commit_on_main_revert
case_block_commit_on_main_revert() {
  fixture
  local before
  before=$(sha "$A" main)
  put "$A/f2" $(lines gamma 6)
  git -C "$A" add -A
  try git -C "$A" commit -m "chore: tweak"
  expect_blocked "main 上裸 commit 撤销 M2"
  expect_out "撤销了已有提交的改动"
  expect_out "Reverts: <sha>"
  assert_ref "$A" main "$before"
}

register block_merge_no_ff_revert
case_block_merge_no_ff_revert() {
  fixture
  new_wt x
  put "$WT/f2" $(lines gamma 6)
  put "$WT/f3" $(lines feat 4)
  commit_all "$WT" "feat: x"
  local before
  before=$(sha "$A" main)
  try git -C "$A" merge --no-ff -m "merge x" feat/x
  expect_blocked "merge --no-ff"
  expect_out "撤销了已有提交的改动"
  assert_ref "$A" main "$before"
}

register block_reset_hard_published
case_block_reset_hard_published() {
  fixture
  local before
  before=$(sha "$A" main)
  try git -C "$A" reset --hard HEAD~1
  expect_blocked "reset --hard 丢已发布提交"
  expect_out "已发布"
  expect_out "git reset --merge"
  assert_ref "$A" main "$before"
  try git -C "$A" reset --merge
  expect_rc 0 "git reset --merge 复原"
  assert_clean "$A" "按提示 git reset --merge 后应复原"
  expect_eq "$(git -C "$A" diff HEAD)" "" "复原后工作树应与 HEAD 一致"
}

register block_reset_mixed_published
case_block_reset_mixed_published() {
  fixture
  local before
  before=$(sha "$A" main)
  try git -C "$A" reset --mixed HEAD~1
  expect_blocked "reset --mixed 丢已发布提交"
  expect_out "已发布"
  expect_out '`--mixed` 用 `git reset` 复原'
  assert_ref "$A" main "$before"
  try git -C "$A" reset -q
  expect_rc 0 "git reset 复原"
  assert_clean "$A" "按提示 git reset 后应复原"
}

register block_amend_published
case_block_amend_published() {
  fixture
  local before
  before=$(sha "$A" main)
  try git -C "$A" commit --amend -m "M2 reworded"
  expect_blocked "amend 已发布提交"
  expect_out "已发布"
  assert_ref "$A" main "$before"
}

register block_reset_unpushed_only_on_main
case_block_reset_unpushed_only_on_main() {
  fixture
  put "$A/f1" $(lines eps 6)
  commit_all "$A" M3
  local before
  before=$(sha "$A" main)
  try git -C "$A" reset --hard origin/main
  expect_blocked "reset 到远端丢掉只在 main 上的未推送提交"
  expect_out "撤销了已有提交的改动"
  assert_ref "$A" main "$before"
}

# S7 / S7b 的公共部分：未推送提交 F 只靠已快进合并进 main 的 feat/x 持有。
_s7_setup() {
  fixture
  new_wt x
  put "$WT/f1" $(lines feat 6)
  commit_all "$WT" "feat: x"
  try precheck "$A" main feat/x
  expect_rc 0 "S7 预检"
  git -C "$A" merge -q --ff-only feat/x
}

register block_s7_reset_checked_out_main
case_block_s7_reset_checked_out_main() {
  _s7_setup
  local before
  before=$(sha "$A" main)
  try git -C "$A" reset --hard origin/main
  expect_blocked "main 被检出时 reset 回远端"
  expect_out "撤销了已有提交的改动"
  assert_ref "$A" main "$before"
}

register block_s7b_update_ref_other_worktree
case_block_s7b_update_ref_other_worktree() {
  _s7_setup
  local before
  before=$(sha "$A" main)
  try git -C "$WT" update-ref refs/heads/main "$(sha "$A" origin/main)"
  expect_blocked "在别的 worktree 里 update-ref 被检出的 main"
  assert_ref "$A" main "$before"
}

register block_update_ref_published
case_block_update_ref_published() {
  fixture
  local before
  before=$(sha "$A" main)
  try git -C "$A" update-ref refs/heads/main "$(sha "$A" HEAD~1)"
  expect_blocked "update-ref 绕过"
  expect_out "已发布"
  assert_ref "$A" main "$before"
}

register block_rebase_i_drop_unpushed
case_block_rebase_i_drop_unpushed() {
  fixture
  put "$A/f1" $(lines eps 6)
  commit_all "$A" M3
  put "$A/f4" $(lines four 4)
  commit_all "$A" M4
  local before
  before=$(sha "$A" main)
  export DROP=M3 GIT_SEQUENCE_EDITOR="$T/bin/drop-editor"
  try git -C "$A" rebase -i origin/main
  expect_blocked "rebase -i drop 掉改写已有内容的未推送提交"
  expect_out "撤销了已有提交的改动"
  try git -C "$A" rebase --abort
  expect_rc 0 "rebase --abort"
  assert_ref "$A" main "$before"
}

# 边界：非主分支（feat/a）被 feat/b 的 targetBranch 记着，也因此受守护。
register block_nested_wrong_squash
case_block_nested_wrong_squash() {
  fixture
  new_wt a
  local wa=$WT
  put "$wa/f2" $(lines a1 6)
  commit_all "$wa" A1
  WT=$A/.worktrees/b
  git -C "$A" worktree add -q -b feat/b "$WT" feat/a
  git -C "$A" config branch.feat/b.targetBranch feat/a
  git -C "$A" config branch.feat/b.forkPoint "$(sha "$A" feat/a)"
  local wb=$WT
  put "$wb/f3" $(lines b1 4)
  commit_all "$wb" B1
  put "$wa/f1" $(lines a2 6)
  commit_all "$wa" A2
  git -C "$wb" reset -q --soft feat/a
  git -C "$wb" commit -q -m "feat: b squashed"
  local before
  before=$(sha "$A" feat/a)
  try precheck "$A" feat/a feat/b
  expect_rc 1 "嵌套预检"
  expect_out 'merge-base HEAD feat/a'
  try git -C "$wa" merge --ff-only feat/b
  expect_blocked "嵌套 merge --ff-only"
  assert_ref "$A" feat/a "$before"
}

register block_prepush_revert_commit
case_block_prepush_revert_commit() {
  fixture
  local remote
  remote=$(remote_main)
  put "$A/f2" $(lines gamma 6)
  git -C "$A" add -A
  # 模拟本地一层没生效（例如 git 低于 2.28）：只跳过本地提交，推送照常过闸门。
  REVERT_GATE_SKIP=1 git -C "$A" commit -q -m "chore: tweak"
  try git -C "$A" push
  expect_blocked "推送撤销提交"
  expect_out "补一个提交"
  expect_eq "$(remote_main)" "$remote" "远端 main 不应变化"
}

register block_prepush_pr_revert
case_block_prepush_pr_revert() {
  fixture
  new_pr pr
  # 本地只改 f1 第 1 行，同事整段改写 f1；rebase 时只留本地一侧，同事那个提交就被撤销了。
  put "$A/f1" "local line 1" $(lines beta 6 | tail -n 5)
  commit_all "$A" "feat: local"
  b_push f1 "teammate: rewrite f1" $(lines remote 6)
  git -C "$A" fetch -q
  try git -C "$A" rebase origin/main
  expect_nonzero "rebase 应有冲突"
  git -C "$A" checkout --theirs f1
  git -C "$A" add f1
  try git -C "$A" rebase --continue
  expect_rc 0 "PR 分支移动不受守护分支那套检查"
  try git -C "$A" push -u origin feat/pr
  expect_blocked "推送撤销了目标分支改动的 PR 分支"
  expect_out "撤销了已有提交的改动"
  expect_out "git rebase origin/main"
  expect_eq "$(git -C "$R" rev-parse --verify -q refs/heads/feat/pr || true)" "" "远端不应有 feat/pr"
}

register block_prepush_pr_only_clone
case_block_prepush_pr_only_clone() {
  fresh_clone
  # 只装了 PR 流程的仓库：没有常驻守护分支，闸门脚本从 PR 目标分支上已提交的那份读。
  rm "$C/.githooks/branches"
  run_at "$C" sh .githooks/install.sh --pr-only >/dev/null
  git -C "$C" switch -q -c feat/pr main
  git -C "$C" config branch.feat/pr.targetBranch main
  put "$C/f2" $(lines gamma 6)
  commit_all "$C" "feat: local"
  try git -C "$C" push -u origin feat/pr
  expect_blocked "只装 PR 流程时推送撤销了目标分支改动的分支"
  expect_out "撤销了已有提交的改动"
}

register block_prepush_pr_remote_only_target
case_block_prepush_pr_remote_only_target() {
  fresh_clone
  rm "$C/.githooks/branches"
  run_at "$C" sh .githooks/install.sh --pr-only >/dev/null
  # 目标分支本地没有（develop 只在远端）：脚本与核对参照都取它的远端跟踪分支。
  git -C "$C" switch -q -c feat/pr origin/develop
  git -C "$C" config branch.feat/pr.targetBranch develop
  put "$C/f2" $(lines gamma 6)
  commit_all "$C" "feat: local"
  try git -C "$C" push -u origin feat/pr
  expect_blocked "目标分支只在远端时照样检查"
  expect_out "origin/develop"
}

register block_prepush_pr_fixed_script_wins
case_block_prepush_pr_fixed_script_wins() {
  fixture
  # 取闸门脚本时常驻守护分支优先：develop 上放一份失效的脚本，它既是 PR 目标分支、
  # 又在候选里排在 main 后面，不该被选中（否则哪个旧分支上的旧脚本就成了所有分支的规则）。
  git -C "$A" switch -q -c develop origin/develop
  put "$A/.githooks/revert-gate.py" "import sys" "sys.exit(0)"
  commit_all "$A" "chore: develop 上的闸门脚本失效"
  git -C "$A" switch -q main
  new_pr pr develop
  put "$A/f2" $(lines gamma 6)
  commit_all "$A" "feat: local"
  try git -C "$A" push -u origin feat/pr
  expect_blocked "脚本应取自常驻守护分支 main，而不是目标分支 develop"
  expect_out "撤销了已有提交的改动"
}

register block_prepush_pr_push_head
case_block_prepush_pr_push_head() {
  fixture
  new_pr pr
  # `git push origin HEAD` 的第一个字段是 HEAD 而不是分支 ref，按远端 ref 也要筛得中。
  put "$A/f2" $(lines gamma 6)
  commit_all "$A" "feat: local"
  try git -C "$A" push origin HEAD
  expect_blocked "push origin HEAD 不能绕过 PR 路径"
  expect_out "撤销了已有提交的改动"
  expect_eq "$(git -C "$R" rev-parse --verify -q refs/heads/feat/pr || true)" "" "远端不应有 feat/pr"
}

register block_prepush_pr_renamed_dest
case_block_prepush_pr_renamed_dest() {
  fixture
  new_pr pr
  # push <本地>:<另一个名字>：targetBranch 记在本地分支上，按本地 ref 认分支才查得到。
  put "$A/f2" $(lines gamma 6)
  commit_all "$A" "feat: local"
  try git -C "$A" push origin feat/pr:refs/heads/other
  expect_blocked "改名推送不能绕过 PR 路径"
  expect_eq "$(git -C "$R" rev-parse --verify -q refs/heads/other || true)" "" "远端不应有 other"
}

register block_prepush_pr_beyond_window
case_block_prepush_pr_beyond_window() {
  fixture
  new_pr pr
  # 被撤销的提交在切出点之后，但离目标分支尖端已有 60 个提交（多于 WINDOW=50）：
  # 只有 forkPoint 记下的切出点能把核对范围延伸到它。
  b_push f1 "teammate: rewrite f1" $(lines remote 6)
  git -C "$B" pull -q --ff-only
  local i
  for i in $(seq 1 60); do
    echo "log $i" >>"$B/f6"
    commit_all "$B" "teammate: log $i"
  done
  git -C "$B" push -q origin main
  put "$A/f3" $(lines feat 3)
  commit_all "$A" "feat: x"
  git -C "$A" fetch -q
  try git -C "$A" rebase origin/main
  expect_rc 0 "rebase 无冲突"
  put "$A/f1" $(lines beta 6)
  commit_all "$A" "chore: 退回 beta"
  try git -C "$A" push -u origin feat/pr
  expect_blocked "撤销切出点之后、WINDOW 之外的提交"
  expect_out "teammate: rewrite f1"
}

register block_prepush_pr_batch
case_block_prepush_pr_batch() {
  fixture
  new_pr clean
  put "$A/f3" $(lines feat 3)
  commit_all "$A" "feat: clean"
  new_pr dirty
  put "$A/f2" $(lines gamma 6)
  commit_all "$A" "feat: dirty"
  try git -C "$A" push origin feat/clean feat/dirty
  expect_blocked "一次推两个分支，其中一个撤销了改动"
  expect_eq "$(git -C "$R" rev-parse --verify -q refs/heads/feat/clean || true)" "" "整次推送应被拒，干净的那个也不进远端"
}

register block_prepush_pr_stacked_parent
case_block_prepush_pr_stacked_parent() {
  fixture
  # 边界：feat/parent 既记了目标分支 main、又因 feat/child 记着它而受守护。两套检查都要跑：它撤销了 main 上的改动照样拦得住。
  new_pr parent
  put "$A/f2" $(lines gamma 6)
  commit_all "$A" "feat: parent"
  # 子分支后建，这时父分支才成为受守护分支（它自己的提交早已存在）
  git -C "$A" config branch.feat/child.targetBranch feat/parent
  try git -C "$A" push -u origin feat/parent
  expect_blocked "受守护的同时也要走 PR 内容检查"
  expect_out "撤销了已有提交的改动"
  expect_out "origin/main"
}

register edge_prepush_pr_parent_without_remote
case_edge_prepush_pr_parent_without_remote() {
  fixture
  # 边界：目标分支只在本地、没有远端跟踪分支——那不是往远端提的目标，推送时不提示、不查。
  new_wt parent
  put "$WT/f3" $(lines feat 3)
  commit_all "$WT" "feat: parent"
  new_wt child feat/parent
  put "$WT/f2" $(lines gamma 6)
  commit_all "$WT" "feat: child"
  try git -C "$A" push -u origin feat/child
  expect_rc 0 "父分支没有远端跟踪分支时放行"
  expect_not_out "没查"
}

register block_prepush_pr_delete_fresh_file
case_block_prepush_pr_delete_fresh_file() {
  fixture
  new_pr pr
  # 同事新增一个文件；错误压平（reset 到远端尖端）把它删掉了。
  # 没有「重现的删行」可查，靠切出点那条结构判据认出来。
  b_push fresh "teammate: 新增 fresh" $(lines brand 4)
  git -C "$A" fetch -q
  put "$A/f3" $(lines mine 3)
  git -C "$A" add -A
  git -C "$A" reset -q --soft origin/main
  rm -f "$A/fresh"
  git -C "$A" add -A
  REVERT_GATE_SKIP=1 git -C "$A" commit -q -m "feat: 错误压平"
  try git -C "$A" push -u origin feat/pr
  expect_blocked "错误压平删掉了切出点之后新增的文件"
  expect_out "整份删掉"
  expect_out "teammate: 新增 fresh"
}

register block_prepush_pr_append_only_squash
case_block_prepush_pr_append_only_squash() {
  fixture
  new_pr pr
  # 目标分支上的文件只被追加过行（从不删行），错误压平把它整份删掉：
  # 行级判据没有「重现的删行」可查，靠切出点那条结构判据认出来。
  b_push plan.md "teammate: 新增计划文档" $(lines plan 3)
  git -C "$B" pull -q --ff-only
  put "$B/plan.md" $(lines plan 3) "step4" "step5" "step6"
  commit_all "$B" "teammate: 追加 step4-6"
  git -C "$B" push -q origin main
  git -C "$A" fetch -q
  put "$A/f3" $(lines mine 3)
  git -C "$A" add -A
  git -C "$A" reset -q --soft origin/main
  rm -f "$A/plan.md"
  git -C "$A" add -A
  REVERT_GATE_SKIP=1 git -C "$A" commit -q -m "feat: 错误压平"
  try git -C "$A" push -u origin feat/pr
  expect_blocked "只追加过的文件被错误压平删掉"
  expect_out "本分支自己没有碰过它"
}

register block_prepush_pr_delete_postfork_file
case_block_prepush_pr_delete_postfork_file() {
  fixture
  new_pr pr
  # 切出点之后队友新增的文件，作者 rebase 后有意删掉：按约定要显式声明，闸门先拦下。
  b_push fresh "teammate: 新增 fresh" $(lines brand 4)
  git -C "$A" fetch -q
  try git -C "$A" rebase origin/main
  expect_rc 0 "rebase"
  git -C "$A" rm -q fresh
  commit_all "$A" "chore: 删掉 fresh"
  try git -C "$A" push -u origin feat/pr
  expect_blocked "删掉切出点之后新增的文件"
  expect_out "Reverts:"
}

register edge_commit_delete_unrecorded
case_edge_commit_delete_unrecorded() {
  fixture
  # 没有切出点记录（直接在目标分支上提交，不是合并某个分支）：算不出切出点，这类误删拦不住。
  put "$A/fresh" $(lines brand 4)
  commit_all "$A" "feat: 新增 fresh"
  git -C "$A" push -q
  git -C "$A" rm -q fresh
  try git -C "$A" commit -q -m "chore: 删掉 fresh"
  expect_rc 0 "无切出点记录时拦不住（已知边界）"
}

register allow_delete_prefork_file
case_allow_delete_prefork_file() {
  fixture
  new_pr pr
  # 切出点就有的文件被作者删掉：分支自己的改动里有它，是正常清理（做完的计划文档那种），放行。
  # 切出点要严格落后于目标分支尖端，否则 authored 与 touched 来自同一对树、这条判据根本不执行。
  b_push f5 "teammate: f5" $(lines mate 3)
  git -C "$A" fetch -q
  try git -C "$A" rebase origin/main
  expect_rc 0 "rebase"
  git -C "$A" rm -q f2
  commit_all "$A" "chore: 删掉做完的计划文档"
  try git -C "$A" push -u origin feat/pr
  expect_rc 0 "删掉切出点之前就有的文件"
}

register allow_rename_fresh_file
case_allow_rename_fresh_file() {
  fixture
  new_pr pr
  b_push fresh "teammate: 新增 fresh" $(lines brand 4)
  git -C "$A" fetch -q
  try git -C "$A" rebase origin/main
  expect_rc 0 "rebase"
  git -C "$A" mv fresh fresh-renamed
  commit_all "$A" "refactor: 改名"
  try git -C "$A" push -u origin feat/pr
  expect_rc 0 "改名不算删除"
}

register allow_delete_postfork_file_reverts_trailer
case_allow_delete_postfork_file_reverts_trailer() {
  fixture
  new_pr pr
  b_push fresh "teammate: 新增 fresh" $(lines brand 4)
  git -C "$A" fetch -q
  try git -C "$A" rebase origin/main
  expect_rc 0 "rebase"
  local target
  target=$(sha "$A" origin/main)
  git -C "$A" rm -q fresh
  git -C "$A" commit -q -m "revert: 撤掉 fresh

Reverts: $target"
  try git -C "$A" push -u origin feat/pr
  expect_rc 0 "带 Reverts: 的有意删除"
}

register block_merge_target_behind_remote
case_block_merge_target_behind_remote() {
  fixture
  new_wt x
  # 目标分支落后远端时，结构判据要以远端尖端为参照照样生效：
  # 队友在远端新增了纯追加文件，分支错误压平（reset 到远端尖端）把它删掉了。
  b_push fresh "teammate: 新增 fresh" $(lines brand 4)
  git -C "$A" fetch -q
  put "$WT/f3" $(lines feat 3)
  commit_all "$WT" "feat: x"
  git -C "$WT" reset -q --soft origin/main
  rm -f "$WT/fresh"
  git -C "$WT" add -A
  git -C "$WT" commit -q -m "feat: 错误压平"
  local before
  before=$(sha "$A" main)
  try git -C "$A" merge --ff-only feat/x
  expect_blocked "目标分支落后远端时的错误压平"
  expect_out "fresh"
  assert_ref "$A" main "$before"
}

register block_prepush_target_behind_remote
case_block_prepush_target_behind_remote() {
  fixture
  new_wt x
  b_push fresh "teammate: 新增 fresh" $(lines brand 4)
  git -C "$A" fetch -q
  put "$WT/f3" $(lines feat 3)
  commit_all "$WT" "feat: x"
  git -C "$WT" reset -q --soft origin/main
  rm -f "$WT/fresh"
  git -C "$WT" add -A
  git -C "$WT" commit -q -m "feat: 错误压平"
  # 本地那层没拦住（如 git 低于 2.28）时，推送这层要接住
  REVERT_GATE_SKIP=1 git -C "$A" merge -q --ff-only feat/x
  local remote
  remote=$(remote_main)
  try git -C "$A" push
  expect_blocked "推送带着错误压平的目标分支"
  expect_out "fresh"
  expect_eq "$(remote_main)" "$remote" "远端 main 不应变化"
}

register block_prepush_pr_revive_deleted
case_block_prepush_pr_revive_deleted() {
  fixture
  new_pr pr
  # 目标分支删掉了一个文件，错误压平把它复活了。这形态两条判据都够得着：内容判据先报
  # （删掉的行全部重现），结构判据的「被复活」那一支因此只是兜底。
  git -C "$B" pull -q --ff-only
  git -C "$B" rm -q f2
  commit_all "$B" "teammate: 删掉 f2"
  git -C "$B" push -q origin main
  git -C "$A" fetch -q
  put "$A/f3" $(lines mine 3)
  git -C "$A" add -A
  git -C "$A" reset -q --soft origin/main
  git -C "$A" add -A
  REVERT_GATE_SKIP=1 git -C "$A" commit -q -m "feat: 错误压平"
  try git -C "$A" push -u origin feat/pr
  expect_blocked "错误压平复活了目标分支删掉的文件"
  expect_out "teammate: 删掉 f2"
}

register edge_prepush_pr_rename_rewrite
case_edge_prepush_pr_rename_rewrite() {
  fixture
  new_pr pr
  # 改名并整体改写内容（相似度低于 git 的改名阈值）：结构判据认不出是改名，会误拦（已知边界）。
  b_push fresh "teammate: 新增 fresh" $(lines brand 6)
  git -C "$A" fetch -q
  try git -C "$A" rebase origin/main
  expect_rc 0 "rebase"
  git -C "$A" mv fresh renamed
  put "$A/renamed" $(lines totally 6)
  commit_all "$A" "refactor: 改名并重写"
  try git -C "$A" push -u origin feat/pr
  expect_blocked "改名且大改写被误拦（已知边界）"
  expect_out "fresh"
}

register allow_push_after_new_worktree
case_allow_push_after_new_worktree() {
  fixture
  # 刚建出的分支正好指着目标分支尖端、它记的切出点就是那里：不能拿它当切出点，
  # 否则 authored 是空集，这次移动改过的每个文件都会被报成撤销。
  put "$A/f1" $(lines mine 6)
  commit_all "$A" "feat: 改 f1"
  new_wt y
  try git -C "$A" push
  expect_rc 0 "新建的 worktree 分支不该让目标分支的推送被拦"
}

register block_prepush_pr_rename_prefork_rewritten
case_block_prepush_pr_rename_prefork_rewritten() {
  fixture
  new_pr pr
  # 切出点就有的 f1 被队友整段改写；分支把切出点那版 f1 改名成 g1 后错误压平，
  # 队友的改写就这样没了。authored 认改名，旧路径仍是疑点，所以拦得住。
  b_push f1 "teammate: rewrite f1" $(lines remote 6)
  git -C "$A" fetch -q
  git -C "$A" mv f1 g1
  commit_all "$A" "refactor: 改名"
  git -C "$A" reset -q --soft origin/main
  git -C "$A" add -A
  REVERT_GATE_SKIP=1 git -C "$A" commit -q -m "feat: 错误压平"
  try git -C "$A" push -u origin feat/pr
  expect_blocked "改名掩盖了队友对旧路径的改写"
  expect_out "f1"
}

register edge_prepush_after_branch_deleted
case_edge_prepush_after_branch_deleted() {
  fixture
  new_wt x
  # 合并后按约定删掉 worktree 与分支，切出点记录随之消失：推送这一层的切出点判据
  # 从此拿不到参照，这类错误压平只能靠本地那一层在合并时拦（已知边界）。
  b_push fresh "teammate: 新增 fresh" $(lines brand 4)
  git -C "$A" fetch -q
  put "$WT/f3" $(lines feat 3)
  commit_all "$WT" "feat: x"
  git -C "$WT" reset -q --soft origin/main
  rm -f "$WT/fresh"
  git -C "$WT" add -A
  git -C "$WT" commit -q -m "feat: 错误压平"
  REVERT_GATE_SKIP=1 git -C "$A" merge -q --ff-only feat/x
  git -C "$A" worktree remove "$WT"
  git -C "$A" branch -D feat/x
  try git -C "$A" push
  expect_rc 0 "分支已删时推送层拿不到切出点（已知边界）"
}

register block_commit_min_lines_batch
case_block_commit_min_lines_batch() {
  fixture
  # 局部撤销那一支：被撤销的提交同时改了两个文件，只有一个被还原（另一个原样留着，
  # 所以整体撤销那一支不成立），靠「删掉的行成批重现」判定，正好 3 行，压在 MIN_LINES 上。
  put "$A/f7" $(lines keep 6) $(lines doomed 3)
  commit_all "$A" "feat: 建 f7"
  git -C "$A" push -q
  put "$A/f7" $(lines keep 6)
  put "$A/f9" $(lines other 3)
  commit_all "$A" "refactor: 删掉 doomed 三行、加 f9"
  git -C "$A" push -q
  local before
  before=$(sha "$A" main)
  put "$A/f7" $(lines keep 6) $(lines doomed 3) "local tail"
  git -C "$A" add -A
  try git -C "$A" commit -q -m "feat: local"
  expect_blocked "删掉的 3 行成批重现"
  expect_out "重现"
  assert_ref "$A" main "$before"
}

register allow_commit_min_lines_below
case_allow_commit_min_lines_below() {
  fixture
  # 同一形态，只重现 2 行：够不上 MIN_LINES，算正常改动，放行。
  put "$A/f7" $(lines keep 6) "doomed_line_1" "doomed_line_2"
  commit_all "$A" "feat: 建 f7"
  git -C "$A" push -q
  put "$A/f7" $(lines keep 6)
  put "$A/f9" $(lines other 3)
  commit_all "$A" "refactor: 删掉两行、加 f9"
  git -C "$A" push -q
  put "$A/f7" $(lines keep 6) "doomed_line_1" "doomed_line_2" "local tail"
  git -C "$A" add -A
  try git -C "$A" commit -q -m "feat: local"
  expect_rc 0 "重现行数够不上门槛时放行"
}

register allow_commit_partial_restore
case_allow_commit_partial_restore() {
  fixture
  # 目标分支上的提交整段改写了 6 行，之后的正常改动只碰回其中 1 行（1/6 < RATIO=0.5）：
  # 这是零星撞上，不算还原，放行。RATIO 调松就会把它误拦。
  put "$A/f7" $(lines old 6)
  commit_all "$A" "feat: 建 f7"
  git -C "$A" push -q
  put "$A/f7" $(lines new 6)
  commit_all "$A" "refactor: 改写 f7"
  git -C "$A" push -q
  put "$A/f7" "old_line_1" $(lines new 6 | tail -n 5) "local tail"
  git -C "$A" add -A
  try git -C "$A" commit -q -m "feat: local"
  expect_rc 0 "只碰回 1/6 行不算还原"
}

register allow_trivial_lines_not_counted
case_allow_trivial_lines_not_counted() {
  fixture
  # 只由括号、标点构成的行在任何文件里都大量重复，不计入判据：这类改动不该被当成还原。
  put "$A/f8" "{" "}" "(" ")" ";" "," "alpha" "beta"
  commit_all "$A" "feat: 建 f8"
  git -C "$A" push -q
  put "$A/f8" "alpha" "beta"
  commit_all "$A" "refactor: 去掉括号行"
  git -C "$A" push -q
  b_push f5 "teammate: f5" $(lines mate 3)
  git -C "$A" fetch -q
  put "$A/f8" "{" "}" "(" ")" ";" "," "alpha" "beta" "gamma"
  commit_all "$A" "feat: local"
  try git -C "$A" rebase 'main@{u}'
  expect_rc 0 "只由标点构成的行重现不算撤销"
}

register block_force_push_rewrite
case_block_force_push_rewrite() {
  fixture
  local remote
  remote=$(remote_main)
  REVERT_GATE_SKIP=1 git -C "$A" reset -q --hard HEAD~1
  put "$A/f3" $(lines new 3)
  commit_all "$A" "feat: rewrite"
  try git -C "$A" push --force
  expect_blocked "强推改写已发布历史"
  expect_out "不要强推"
  expect_eq "$(remote_main)" "$remote" "远端 main 不应变化"
}

register block_force_push_remote_ahead
case_block_force_push_remote_ahead() {
  fixture
  b_push f5 "teammate: f5" $(lines mate 3)
  local remote
  remote=$(remote_main)
  put "$A/f3" $(lines mine 3)
  commit_all "$A" "feat: mine"
  try git -C "$A" push --force
  expect_blocked "远程有本地没有的提交时 push --force"
  expect_out "有本地没有的提交"
  expect_out "git fetch"
  expect_out 'git rebase main@{u}'
  expect_eq "$(remote_main)" "$remote" "远端 main 不应变化"
}

register block_align_checkout_theirs
case_block_align_checkout_theirs() {
  fixture
  # 本地只改第 1 行，远程整段改写；只留本地一侧，远程删掉的 beta 行就成批回来了。
  put "$A/f1" "local line 1" $(lines beta 6 | tail -n 5)
  commit_all "$A" "feat: local"
  b_push f1 "teammate: rewrite f1" $(lines remote 6)
  git -C "$A" fetch -q
  local before
  before=$(sha "$A" main)
  try git -C "$A" rebase 'main@{u}'
  expect_nonzero "rebase 应有冲突"
  git -C "$A" checkout --theirs f1
  git -C "$A" add f1
  try git -C "$A" rebase --continue
  expect_blocked "解冲突只留本地一侧，rebase 当场被拦"
  expect_out "撤销了已有提交的改动"
  expect_out "rebase --abort"
  try git -C "$A" rebase --abort
  expect_rc 0 "rebase --abort"
  assert_ref "$A" main "$before"
}

register block_align_split_revert
case_block_align_split_revert() {
  fixture
  # X 同时改 f1、f2 且已发布；上游手工撤了 f1 那部分，本地撤了 f2 那部分。
  put "$A/f1" $(lines x1 6)
  put "$A/f2" $(lines x2 6)
  commit_all "$A" X
  git -C "$A" push -q
  b_push f1 "teammate: undo f1" $(lines beta 6)
  put "$A/f2" $(lines delta 6)
  git -C "$A" add -A
  # 本地这个撤销提交模拟在没装闸门的环境里做的；对齐时闸门要把它拦下。
  REVERT_GATE_SKIP=1 git -C "$A" commit -q -m "chore: local undo f2"
  git -C "$A" fetch -q
  local before
  before=$(sha "$A" main)
  try git -C "$A" rebase 'main@{u}'
  expect_blocked "上游撤 f1、本地撤 f2"
  expect_out "撤销了已有提交的改动"
  git -C "$A" rebase --abort 2>/dev/null || true
  assert_ref "$A" main "$before"
}

register block_align_same_file_partial
case_block_align_same_file_partial() {
  fixture
  # t15：X 在同一个文件 f5 的两段里各改一处；上游撤前一段，本地撤后一段，两边不冲突。
  local pad
  pad=$(lines pad 8)
  put "$A/f5" $(lines a 6) $pad $(lines b 6)
  commit_all "$A" "feat: f5"
  put "$A/f5" $(lines A 6) $pad $(lines B 6)
  commit_all "$A" X
  git -C "$A" push -q
  b_push f5 "teammate: undo first half" $(lines a 6) $pad $(lines B 6)
  put "$A/f5" $(lines A 6) $pad $(lines b 6)
  git -C "$A" add -A
  REVERT_GATE_SKIP=1 git -C "$A" commit -q -m "chore: local undo second half"
  git -C "$A" fetch -q
  local before
  before=$(sha "$A" main)
  try git -C "$A" rebase 'main@{u}'
  expect_blocked "同一文件内上游撤一部分、本地撤另一部分"
  expect_out "撤销了已有提交的改动"
  git -C "$A" rebase --abort 2>/dev/null || true
  assert_ref "$A" main "$before"
}

register block_align_beyond_window
case_block_align_beyond_window() {
  fixture
  # 上游超前 60 个提交（多于 WINDOW=50），最后一个在 f1 末尾追加；本地也在 f1 末尾追加，冲突。
  # 解冲突时把 f1 写回 M1 之前的 alpha，撤销的 M1 离远端尖端已超过 WINDOW。
  git -C "$B" pull -q --ff-only
  local i
  for i in $(seq 1 59); do
    echo "log $i" >>"$B/f6"
    commit_all "$B" "teammate: log $i"
  done
  put "$B/f1" $(lines beta 6) "upstream tail"
  commit_all "$B" "teammate: f1 tail"
  git -C "$B" push -q origin main
  put "$A/f1" $(lines beta 6) "local tail"
  commit_all "$A" "feat: local tail"
  git -C "$A" fetch -q
  local before
  before=$(sha "$A" main)
  try git -C "$A" rebase 'main@{u}'
  expect_nonzero "rebase 应有冲突"
  put "$A/f1" $(lines alpha 6) "upstream tail" "local tail"
  git -C "$A" add f1
  try git -C "$A" rebase --continue
  expect_blocked "撤销 WINDOW 之外的已发布提交"
  expect_out "M1"
  git -C "$A" rebase --abort 2>/dev/null || true
  assert_ref "$A" main "$before"
}

# ---------------------------------------------------------------------------
# 放行

register allow_pr_flow
case_allow_pr_flow() {
  fixture
  put "$A/f1" $(lines eps 6)
  commit_all "$A" "wip 1"
  put "$A/f3" $(lines wip 3)
  commit_all "$A" "wip 2"
  try git -C "$A" switch -c feat/pr
  expect_rc 0 "switch -c"
  try git -C "$A" branch -f main origin/main
  expect_rc 0 "branch -f main origin/main"
  assert_ref "$A" main "$(sha "$A" origin/main)"
  git -C "$A" reset -q --soft "$(git -C "$A" merge-base HEAD main)"
  git -C "$A" commit -q -m "feat: pr"
  try git -C "$A" push -u origin feat/pr
  expect_rc 0 "push -u"
  git -C "$A" commit -q --amend -m "feat: pr (amended)"
  try git -C "$A" push --force-with-lease
  expect_rc 0 "amend 后 --force-with-lease"
  try git -C "$A" switch main
  expect_rc 0 "switch main"
  try git -C "$A" branch -D feat/pr
  expect_rc 0 "branch -D"
}

register allow_pr_prepare_on_target
case_allow_pr_prepare_on_target() {
  fixture
  # git-pr 第 1 步：本地提交攒在目标分支上，switch -c 承载它们、branch -f 把目标分支退回远端。
  # 记了 targetBranch 之后目标分支受守护，这个退回动作要照样放行。
  put "$A/f1" $(lines eps 6)
  commit_all "$A" "wip"
  try git -C "$A" switch -c feat/pr
  expect_rc 0 "switch -c"
  git -C "$A" config branch.feat/pr.targetBranch main
  git -C "$A" config branch.feat/pr.forkPoint "$(sha "$A" origin/main)"
  try git -C "$A" branch -f main origin/main
  expect_rc 0 "branch -f 把目标分支退回远端"
  assert_ref "$A" main "$(sha "$A" origin/main)"
}

register allow_prepush_pr_clean
case_allow_prepush_pr_clean() {
  fixture
  new_pr pr
  put "$A/f1" "local line 1" $(lines beta 6 | tail -n 5)
  commit_all "$A" "feat: local"
  b_push f1 "teammate: rewrite f1" $(lines remote 6)
  git -C "$A" fetch -q
  try git -C "$A" rebase origin/main
  expect_nonzero "rebase 应有冲突"
  # 如实解冲突：同事改写的 6 行都留着，自己那行并进去。
  put "$A/f1" "local line 1" $(lines remote 6 | tail -n 5)
  git -C "$A" add f1
  try git -C "$A" rebase --continue
  expect_rc 0 "rebase --continue"
  try git -C "$A" push -u origin feat/pr
  expect_rc 0 "合并双方后推送 PR 分支"
  # 压平后强推自己独用的 PR 分支是预期操作，不走「不许改写已发布历史」那条。
  put "$A/f3" $(lines extra 3)
  commit_all "$A" "feat: more"
  git -C "$A" reset -q --soft "$(git -C "$A" merge-base HEAD origin/main)"
  git -C "$A" commit -q -m "feat: squashed"
  try git -C "$A" push --force-with-lease
  expect_rc 0 "压平后强推"
}

register allow_prepush_pr_reverts_trailer
case_allow_prepush_pr_reverts_trailer() {
  fixture
  new_pr pr
  local target
  target=$(sha "$A" origin/main)
  put "$A/f2" $(lines gamma 6)
  commit_all "$A" "revert: 回到 gamma"
  # 先不带 trailer 推一次：确认这个撤销本来是拦得住的，放行是 trailer 起的作用
  try git -C "$A" push -u origin feat/pr
  expect_blocked "没写 Reverts: 的撤销"
  git -C "$A" commit -q --amend -m "revert: 回到 gamma

Reverts: $target"
  try git -C "$A" push -u origin feat/pr
  expect_rc 0 "带 Reverts: 的有意撤销"
}

register allow_prepush_pr_delete
case_allow_prepush_pr_delete() {
  fixture
  new_pr pr
  put "$A/f3" $(lines feat 3)
  commit_all "$A" "feat: x"
  try git -C "$A" push -u origin feat/pr
  expect_rc 0 "推送"
  try git -C "$A" push origin :feat/pr
  expect_rc 0 "删除远端分支不受 PR 路径影响"
  expect_eq "$(git -C "$R" rev-parse --verify -q refs/heads/feat/pr || true)" "" "远端分支应已删除"
}

register allow_correct_squash_flow
case_allow_correct_squash_flow() {
  fixture
  new_wt x
  put "$WT/f3" $(lines feat 4)
  commit_all "$WT" "wip 1"
  put "$WT/f3" $(lines feat 5)
  commit_all "$WT" "wip 2"
  put "$A/f1" $(lines eps 6)
  commit_all "$A" M3
  git -C "$A" push -q
  git -C "$WT" reset -q --soft "$(git -C "$WT" merge-base HEAD main)"
  git -C "$WT" commit -q -m "feat: x"
  try git -C "$WT" rebase main
  expect_rc 0 "rebase main"
  try precheck "$A" main feat/x
  expect_rc 0 预检
  try git -C "$A" merge --ff-only feat/x
  expect_rc 0 "merge --ff-only"
  try git -C "$A" push
  expect_rc 0 推送
  expect_eq "$(remote_main)" "$(sha "$A" feat/x)" "远端 main"
  try git -C "$A" worktree remove "$WT"
  expect_rc 0 "worktree remove"
  try git -C "$A" branch -D feat/x
  expect_rc 0 "branch -D"
}

register allow_reverts_trailer
case_allow_reverts_trailer() {
  fixture
  local m2
  m2=$(sha "$A" main)
  put "$A/f2" $(lines gamma 6)
  git -C "$A" add -A
  try git -C "$A" commit -q -m "chore: undo M2" -m "Reverts: $m2"
  expect_rc 0 "带 Reverts: 的撤销提交"
  try git -C "$A" push
  expect_rc 0 推送
}

register allow_git_revert
case_allow_git_revert() {
  fixture
  try git -C "$A" revert --no-edit HEAD
  expect_rc 0 "git revert"
  try git -C "$A" push
  expect_rc 0 推送
}

register allow_batch_push_recover
case_allow_batch_push_recover() {
  fixture
  # 两个特性分支先后快进合入 main 并删除，第三个从合并后的 main 切出、还没合。
  new_wt one
  put "$WT/f1" "one line 1" $(lines beta 6 | tail -n 5)
  commit_all "$WT" "feat: one"
  try precheck "$A" main feat/one
  expect_rc 0 "预检 one"
  git -C "$A" merge -q --ff-only feat/one
  git -C "$A" worktree remove "$WT"
  git -C "$A" branch -q -D feat/one
  new_wt two
  put "$WT/f3" $(lines two 3)
  commit_all "$WT" "feat: two"
  try precheck "$A" main feat/two
  expect_rc 0 "预检 two"
  git -C "$A" merge -q --ff-only feat/two
  git -C "$A" worktree remove "$WT"
  git -C "$A" branch -q -D feat/two
  new_wt three
  local w3=$WT
  put "$w3/f4" $(lines three 3)
  commit_all "$w3" "feat: three"
  # 队友改了 f1 的第 2 行，与 one 改的第 1 行相邻，rebase 时冲突。
  b_push f1 "teammate: f1" "beta_line_1" "mate line 2" $(lines beta 6 | tail -n 4)
  try git -C "$A" push
  expect_nonzero "推送应被拒"
  git -C "$A" fetch -q
  local old
  old=$(sha "$A" main)
  try git -C "$A" rebase 'main@{u}'
  expect_nonzero "rebase 应有冲突"
  put "$A/f1" "one line 1" "mate line 2" $(lines beta 6 | tail -n 4)
  git -C "$A" add f1
  try git -C "$A" rebase --continue
  expect_rc 0 "合并双方后 rebase --continue"
  expect_eq "$(sha "$A" 'main@{1}')" "$old" "rebase 完成后 main@{1} 应是旧位置"
  try git -C "$w3" rebase --onto main "$old"
  expect_rc 0 "rebase --onto"
  try precheck "$A" main feat/three
  expect_rc 0 "预检 three"
  try git -C "$A" merge --ff-only feat/three
  expect_rc 0 "merge three"
  try git -C "$A" push
  expect_rc 0 推送
  expect_eq "$(remote_main)" "$(sha "$A" main)" "远端 main"
}

register allow_upstream_manual_revert_recover
case_allow_upstream_manual_revert_recover() {
  fixture
  b_push f2 "teammate: undo f2 by hand" $(lines gamma 6)
  put "$A/f3" $(lines mine 3)
  commit_all "$A" "feat: mine"
  try git -C "$A" push
  expect_nonzero "推送应被拒"
  git -C "$A" fetch -q
  try git -C "$A" rebase 'main@{u}'
  expect_rc 0 "上游手工撤销后 rebase main@{u}"
  try git -C "$A" push
  expect_rc 0 推送
}

register allow_align_ff_behind
case_allow_align_ff_behind() {
  fixture
  b_push f1 "teammate: f1" $(lines mate 6)
  git -C "$A" fetch -q
  try git -C "$A" merge --ff-only 'main@{u}'
  expect_rc 0 "落后时快进"
  assert_ref "$A" main "$(remote_main)"
}

register allow_align_rebase_no_conflict
case_allow_align_rebase_no_conflict() {
  fixture
  put "$A/f1" "mine line 1" $(lines beta 6 | tail -n 5)
  commit_all "$A" "feat: mine"
  b_push f1 "teammate: f1 tail" $(lines beta 6 | head -n 5) "mate line 6"
  git -C "$A" fetch -q
  try git -C "$A" rebase 'main@{u}'
  expect_rc 0 "同文件不冲突的 rebase"
  try git -C "$A" push
  expect_rc 0 推送
}

register allow_nested_after_child_merged
case_allow_nested_after_child_merged() {
  fixture
  new_wt a
  local wa=$WT
  put "$wa/f3" $(lines a1 3)
  commit_all "$wa" "wip a1"
  WT=$A/.worktrees/b
  git -C "$A" worktree add -q -b feat/b "$WT" feat/a
  git -C "$A" config branch.feat/b.targetBranch feat/a
  git -C "$A" config branch.feat/b.forkPoint "$(sha "$A" feat/a)"
  local wb=$WT
  put "$wb/f4" $(lines b1 3)
  commit_all "$wb" "wip b1"
  try precheck "$A" feat/a feat/b
  expect_rc 0 "嵌套预检"
  try git -C "$wa" merge --ff-only feat/b
  expect_rc 0 "子分支合回"
  git -C "$A" worktree remove "$wb"
  git -C "$A" branch -q -D feat/b
  put "$A/f1" $(lines eps 6)
  commit_all "$A" M3
  git -C "$wa" reset -q --soft "$(git -C "$wa" merge-base HEAD main)"
  try git -C "$wa" commit -m "feat: a"
  expect_rc 0 "子分支删除后压平"
  try git -C "$wa" rebase main
  expect_rc 0 "rebase main"
  try precheck "$A" main feat/a
  expect_rc 0 预检
  try git -C "$A" merge --ff-only feat/a
  expect_rc 0 合并
}

# ---------------------------------------------------------------------------
# 已知边界：断言当前行为，行为变化时这里会失败，提醒同步更新闸门文档里的「已知边界」。

register edge_detach_branch_f_allowed
case_edge_detach_branch_f_allowed() {
  # 已知边界：先 switch --detach 再 branch -f，特性分支仍持有那些提交，与合法流程形态相同，放行。
  _s7_setup
  git -C "$A" switch -q --detach
  try git -C "$A" branch -f main origin/main
  expect_rc 0 "switch --detach + branch -f（已知边界：放行）"
  assert_ref "$A" main "$(sha "$A" origin/main)"
}

register edge_drop_pure_addition_reset
case_edge_drop_pure_addition_reset() {
  # 已知边界：只新增内容的未推送提交被丢下不算撤销。
  fixture
  put "$A/f4" $(lines four 4)
  commit_all "$A" "docs: plan"
  try git -C "$A" reset -q --hard origin/main
  expect_rc 0 "reset --hard 丢掉纯新增提交（已知边界：放行）"
  assert_ref "$A" main "$(sha "$A" origin/main)"
}

register edge_drop_pure_addition_rebase_i
case_edge_drop_pure_addition_rebase_i() {
  # 已知边界：同上，rebase -i drop。
  fixture
  put "$A/f4" $(lines four 4)
  commit_all "$A" P1
  put "$A/f5" $(lines five 4)
  commit_all "$A" P2
  export DROP=P1 GIT_SEQUENCE_EDITOR="$T/bin/drop-editor"
  try git -C "$A" rebase -i origin/main
  expect_rc 0 "rebase -i drop 纯新增提交（已知边界：放行）"
  [ ! -e "$A/f4" ] || fail "f4 应已被 drop"
}

register edge_push_no_verify_bypass
case_edge_push_no_verify_bypass() {
  # 已知边界：--no-verify 跳过 pre-push，闸门拦不住，只能靠规则禁止。
  fixture
  put "$A/f2" $(lines gamma 6)
  git -C "$A" add -A
  REVERT_GATE_SKIP=1 git -C "$A" commit -q -m "chore: tweak"
  try git -C "$A" push --no-verify
  expect_rc 0 "push --no-verify（已知边界：能绕过）"
  expect_eq "$(remote_main)" "$(sha "$A" main)" "远端 main"
}

register edge_hook_script_error_allows
case_edge_hook_script_error_allows() {
  fixture
  # 已知边界：hook 模式下闸门脚本跑不起来（这里是语法错）时放行，宁可漏检一次，
  # 也不能让它卡死所有 ref 更新——入口只把退出码 3 当作拒绝，别的非零一律放行。
  put "$A/.githooks/revert-gate.py" "def ("
  commit_all "$A" "chore: 弄坏闸门脚本"
  local before
  before=$(sha "$A" main)
  put "$A/f2" $(lines gamma 6)
  git -C "$A" add -A
  try git -C "$A" commit -m "chore: tweak"
  expect_rc 0 "脚本跑不起来时放行（已知边界）"
  expect_eq "$(sha "$A" 'main^')" "$before" "main 应已前进"
}

register edge_prepush_pr_not_rebased
case_edge_prepush_pr_not_rebased() {
  fixture
  new_pr pr
  # 分支撤销了目标分支上的 M2，但还没 rebase 到最新的目标分支：已知边界，推送不查。
  put "$A/f2" $(lines gamma 6)
  commit_all "$A" "feat: local"
  b_push f5 "teammate: f5" $(lines mate 3)
  git -C "$A" fetch -q
  try git -C "$A" push -u origin feat/pr
  expect_rc 0 "没 rebase 到最新目标分支时不查（已知边界）"
}

register edge_prepush_pr_no_config
case_edge_prepush_pr_no_config() {
  fixture
  # 没记 targetBranch 的分支（没走 git-pr 流程手工建的）不查：已知边界。
  git -C "$A" switch -q -c feat/manual main
  put "$A/f2" $(lines gamma 6)
  commit_all "$A" "feat: manual"
  try git -C "$A" push -u origin feat/manual
  expect_rc 0 "没记 targetBranch 时不查（已知边界）"
}

register edge_prepush_pr_no_remote_target
case_edge_prepush_pr_no_remote_target() {
  fixture
  new_pr pr
  # 目标分支的远端跟踪分支不止一个、本地分支也退回去：取不到远端状态，只打一行「没查」就放行。
  git -C "$A" remote add fork "$R"
  git -C "$A" fetch -q fork
  git -C "$A" branch -q -D main
  put "$A/f2" $(lines gamma 6)
  commit_all "$A" "feat: local"
  try git -C "$A" push -u origin feat/pr
  expect_rc 0 "取不到目标分支的远端状态时放行（已知边界）"
  expect_out "没查"
}

register edge_prepush_pr_unguarded_target
case_edge_prepush_pr_unguarded_target() {
  fresh_clone
  # 只装了 PR 流程、还没有任何分支记过 targetBranch：没有受守护分支，直推目标分支不查（已知边界）。
  rm "$C/.githooks/branches"
  run_at "$C" sh .githooks/install.sh --pr-only >/dev/null
  put "$C/f2" $(lines gamma 6)
  commit_all "$C" "chore: 退回 gamma"
  try git -C "$C" push origin main
  expect_rc 0 "没有受守护分支时直推目标分支不查（已知边界）"
}

# ---------------------------------------------------------------------------
# 预检结果

register check_pr_revert
case_check_pr_revert() {
  fixture
  new_pr pr
  put "$A/f2" $(lines gamma 6)
  commit_all "$A" "feat: local"
  try precheck_pr "$A" origin/main feat/pr
  expect_rc 1 "撤销了目标分支上的提交"
  expect_out "撤销了已有提交的改动"
  expect_out "origin/main"
}

register check_pr_not_rebased
case_check_pr_not_rebased() {
  fixture
  new_pr pr
  put "$A/f3" $(lines feat 3)
  commit_all "$A" "feat: x"
  b_push f5 "teammate: f5" $(lines mate 3)
  git -C "$A" fetch -q
  try precheck_pr "$A" origin/main feat/pr
  expect_rc 1 "还没 rebase 到最新目标分支"
  expect_out "还没 rebase"
  expect_out "git rebase origin/main"
}

register check_pr_ok
case_check_pr_ok() {
  fixture
  new_pr pr
  put "$A/f3" $(lines feat 3)
  commit_all "$A" "feat: x"
  try precheck_pr "$A" origin/main feat/pr
  expect_rc 0 "压平后已 rebase、没撤销东西"
}

register check_pr_local_ref_arg
case_check_pr_local_ref_arg() {
  fixture
  new_pr pr
  try precheck_pr "$A" main feat/pr
  expect_rc 2 "目标分支写成本地分支"
  expect_out "不是远端跟踪分支"
}

register check_pr_error
case_check_pr_error() {
  fixture
  new_pr pr
  try precheck_pr "$A" origin/main feat/nope
  expect_rc 2 "分支不存在时检查出错"
  expect_out "检查出错"
}

register check_squash_append_only
case_check_squash_append_only() {
  fixture
  new_wt x
  # 合并前预检也要能查出结构判据的命中（纯追加文件被错误压平删掉）。
  b_push fresh "teammate: 新增 fresh" $(lines brand 4)
  git -C "$A" fetch -q
  git -C "$A" merge -q --ff-only 'main@{u}'
  put "$WT/f3" $(lines feat 3)
  commit_all "$WT" "feat: x"
  git -C "$WT" reset -q --soft main
  rm -f "$WT/fresh"
  git -C "$WT" add -A
  git -C "$WT" commit -q -m "feat: 错误压平"
  try precheck "$A" main feat/x
  expect_rc 1 "预检查出结构判据的命中"
  expect_out "fresh"
}

register check_pr_head_arg
case_check_pr_head_arg() {
  fixture
  new_pr pr
  b_push fresh "teammate: 新增 fresh" $(lines brand 4)
  git -C "$A" fetch -q
  put "$A/f3" $(lines mine 3)
  git -C "$A" add -A
  git -C "$A" reset -q --soft origin/main
  rm -f "$A/fresh"
  git -C "$A" add -A
  REVERT_GATE_SKIP=1 git -C "$A" commit -q -m "feat: 错误压平"
  # 分支参数写成 HEAD 时也要取到切出点，否则结构判据静默不跑
  try precheck_pr "$A" origin/main HEAD
  expect_rc 1 "分支参数写成 HEAD"
  expect_out "fresh"
}

register check_usage_nonzero
case_check_usage_nonzero() {
  fixture
  local s
  s=$(git -C "$A" show "origin/main:.githooks/revert-gate.py")
  # 未知子命令、无参数、预检缺参数都要非零：返回 0 会让调用方把「没跑起来」读成「通过」
  try run_at "$A" python3 -I -c "$s" no-such-subcommand
  expect_rc 2 "未知子命令"
  expect_out "用法不对"
  try run_at "$A" python3 -I -c "$s"
  expect_rc 2 "无参数"
  try run_at "$A" python3 -I -c "$s" check-pr origin/main
  expect_rc 2 "check-pr 缺参数"
}

register check_behind
case_check_behind() {
  fixture
  new_wt x
  put "$WT/f3" $(lines feat 3)
  commit_all "$WT" "feat: x"
  b_push f5 "teammate: f5" $(lines mate 3)
  git -C "$A" fetch -q
  try precheck "$A" main feat/x
  expect_rc 1 "落后"
  expect_out "落后"
  expect_out "git fetch"
  expect_out 'merge --ff-only main@{u}'
}

register check_diverged
case_check_diverged() {
  fixture
  put "$A/f4" $(lines mine 3)
  commit_all "$A" "feat: mine"
  new_wt x
  put "$WT/f3" $(lines feat 3)
  commit_all "$WT" "feat: x"
  b_push f5 "teammate: f5" $(lines mate 3)
  git -C "$A" fetch -q
  try precheck "$A" main feat/x
  expect_rc 1 "分叉"
  expect_out "分叉"
  expect_out 'git rebase main@{u}'
}

register check_ahead_only
case_check_ahead_only() {
  fixture
  put "$A/f4" $(lines mine 3)
  commit_all "$A" "feat: mine"
  new_wt x
  put "$WT/f3" $(lines feat 3)
  commit_all "$WT" "feat: x"
  try precheck "$A" main feat/x
  expect_rc 0 "仅领先"
}

register check_no_upstream_unique_behind
case_check_no_upstream_unique_behind() {
  fixture
  git -C "$A" branch --unset-upstream main
  new_wt x
  put "$WT/f3" $(lines feat 3)
  commit_all "$WT" "feat: x"
  b_push f5 "teammate: f5" $(lines mate 3)
  git -C "$A" fetch -q origin
  try precheck "$A" main feat/x
  expect_rc 1 "无上游、远端唯一同名分支且落后"
  expect_out "origin/main"
}

register check_no_upstream_multiple
case_check_no_upstream_multiple() {
  fixture
  git -C "$D" clone -q --bare remote.git other.git
  git -C "$A" remote add other "$D/other.git"
  git -C "$A" fetch -q other
  git -C "$A" branch --unset-upstream main
  new_wt x
  put "$WT/f3" $(lines feat 3)
  commit_all "$WT" "feat: x"
  try precheck "$A" main feat/x
  expect_rc 1 "无上游、远端多个同名分支"
  expect_out "多个同名分支"
}

register check_no_upstream_no_remote
case_check_no_upstream_no_remote() {
  fixture
  git -C "$A" branch -q dev main
  try precheck "$A" dev main
  expect_rc 0 "无上游、远端无同名分支"
}

register check_not_ready_then_installed
case_check_not_ready_then_installed() {
  fixture
  git -C "$D" clone -q remote.git c
  local c=$D/c
  git -C "$c" branch -q feat/x main
  try precheck "$c" main feat/x
  expect_rc 1 "新 clone 未就绪"
  expect_out "闸门未就绪"
  try run_at "$c" sh .githooks/install.sh
  expect_rc 0 install.sh
  try precheck "$c" main feat/x
  expect_rc 0 "装好后预检"
}

register check_gate_error
case_check_gate_error() {
  # 让闸门自身出错：要检查的分支不存在，rev-parse 失败走出错分支。
  fixture
  try precheck "$A" main no-such-branch
  expect_rc 2 "闸门自身出错"
  expect_out "检查出错"
}

# ---------------------------------------------------------------------------
# install.sh

# 新 clone（主分支上已有闸门脚本），未执行过 install.sh。
fresh_clone() {
  fixture
  git -C "$D" clone -q remote.git c
  C=$D/c
  HOOKS=$C/.git/hooks
}

expect_installed() {
  [ -x "$HOOKS/reference-transaction" ] && [ -x "$HOOKS/pre-push" ] || fail "hook 入口没装上"
  grep -q '^# revert-gate hook entry' "$HOOKS/pre-push" || fail "pre-push 不是闸门入口"
}

expect_nothing_written() {
  [ ! -e "$HOOKS/reference-transaction" ] || fail "不应写 reference-transaction"
  [ ! -e "$HOOKS/pre-push" ] || fail "不应写 pre-push"
  expect_eq "$(git -C "$C" config --get-all revert-gate.branch || true)" "" "revert-gate.branch 不应写入"
}

gate_branches() { git -C "$C" config --get-all revert-gate.branch | tr '\n' ' '; }

register install_with_args
case_install_with_args() {
  fresh_clone
  try run_at "$C" sh .githooks/install.sh main
  expect_rc 0 "带参数安装"
  expect_out "回退闸门已启用"
  expect_installed
  expect_eq "$(gate_branches)" "main " revert-gate.branch
}

register install_from_branches_file
case_install_from_branches_file() {
  fresh_clone
  printf '# 常驻守护分支\r\n\r\n  main  \r\n\tdevelop\r\n   # 缩进的注释\r\n# tail\r\n' >"$C/.githooks/branches"
  try run_at "$C" sh .githooks/install.sh
  expect_rc 0 "读 branches 安装（注释、空行、缩进、CRLF）"
  expect_installed
  expect_eq "$(gate_branches)" "main develop " revert-gate.branch
}

register install_branches_only
case_install_branches_only() {
  fresh_clone
  try run_at "$C" sh .githooks/install.sh --branches-only main
  expect_rc 0 "--branches-only 带参数"
  expect_out "未装 hook"
  [ ! -e "$HOOKS/pre-push" ] && [ ! -e "$HOOKS/reference-transaction" ] || fail "--branches-only 不应装 hook"
  expect_eq "$(gate_branches)" "main " revert-gate.branch
  git -C "$C" config --unset-all revert-gate.branch
  try run_at "$C" sh .githooks/install.sh --branches-only
  expect_rc 0 "--branches-only 不带参数"
  [ ! -e "$HOOKS/pre-push" ] || fail "--branches-only 不应装 hook"
  expect_eq "$(gate_branches)" "main " revert-gate.branch
}

register install_pr_only
case_install_pr_only() {
  fresh_clone
  # 只装了 PR 流程的仓库：没有 branches，照样装上 hook 入口，不写常驻守护分支。
  rm "$C/.githooks/branches"
  try run_at "$C" sh .githooks/install.sh --pr-only
  expect_rc 0 "--pr-only"
  expect_out "没写常驻守护分支"
  expect_installed
  expect_eq "$(git -C "$C" config --get-all revert-gate.branch || true)" "" "revert-gate.branch 不应写入"
}

register install_pr_only_keeps_branches
case_install_pr_only_keeps_branches() {
  fresh_clone
  try run_at "$C" sh .githooks/install.sh develop main
  expect_rc 0 "先按 worktree 流程装"
  try run_at "$C" sh .githooks/install.sh --pr-only
  expect_rc 0 "再按 PR 流程装"
  expect_installed
  expect_eq "$(gate_branches)" "develop main " "--pr-only 不应动原有的常驻守护分支"
}

register install_pr_only_rejects_args
case_install_pr_only_rejects_args() {
  fresh_clone
  try run_at "$C" sh .githooks/install.sh --pr-only main
  expect_rc 1 "--pr-only 带分支参数"
  expect_out "不接分支参数"
  expect_nothing_written
  try run_at "$C" sh .githooks/install.sh --pr-only --branches-only
  expect_rc 1 "两个参数一起给"
  expect_out "互斥"
  expect_nothing_written
}

register install_pr_only_hookspath
case_install_pr_only_hookspath() {
  fresh_clone
  git -C "$C" config core.hooksPath .husky
  try run_at "$C" sh .githooks/install.sh --pr-only
  expect_rc 1 "--pr-only 遇上 core.hooksPath"
  expect_out "core.hooksPath"
  expect_nothing_written
}

register install_missing_or_empty_branches
case_install_missing_or_empty_branches() {
  fresh_clone
  rm "$C/.githooks/branches"
  try run_at "$C" sh .githooks/install.sh
  expect_rc 1 "缺 branches"
  expect_nothing_written
  printf '# only comment\n\n   \n' >"$C/.githooks/branches"
  try run_at "$C" sh .githooks/install.sh
  expect_rc 1 "branches 为空"
  expect_nothing_written
}

register install_typo_branch
case_install_typo_branch() {
  fresh_clone
  try run_at "$C" sh .githooks/install.sh mian
  expect_rc 1 "分支名拼错"
  expect_out "mian"
  expect_nothing_written
}

register install_existing_prepush_atomic
case_install_existing_prepush_atomic() {
  fresh_clone
  mkdir -p "$HOOKS"
  printf '#!/bin/sh\necho custom hook\n' >"$HOOKS/pre-push"
  chmod +x "$HOOKS/pre-push"
  local orig
  orig=$(cat "$HOOKS/pre-push")
  try run_at "$C" sh .githooks/install.sh
  expect_rc 1 "已有非闸门 pre-push"
  expect_eq "$(cat "$HOOKS/pre-push")" "$orig" "原 pre-push 不应被覆盖"
  [ ! -e "$HOOKS/reference-transaction" ] || fail "reference-transaction 不应装上（应原子失败）"
  expect_eq "$(git -C "$C" config --get-all revert-gate.branch || true)" "" "revert-gate.branch 不应写入"
}

register install_hookspath_set
case_install_hookspath_set() {
  fresh_clone
  git -C "$C" config core.hooksPath .husky
  try run_at "$C" sh .githooks/install.sh
  expect_rc 1 "core.hooksPath 已设置、不带 --branches-only"
  expect_out "core.hooksPath"
  expect_nothing_written
  try run_at "$C" sh .githooks/install.sh --branches-only
  expect_rc 0 "core.hooksPath 已设置、带 --branches-only"
  [ ! -e "$HOOKS/pre-push" ] && [ ! -e "$C/.husky/pre-push" ] || fail "--branches-only 不应装 hook"
  expect_eq "$(gate_branches)" "main " revert-gate.branch
}

register install_from_subdir
case_install_from_subdir() {
  fresh_clone
  mkdir -p "$C/sub/dir"
  try run_at "$C/sub/dir" sh ../../.githooks/install.sh
  expect_rc 0 "在子目录执行"
  expect_installed
  expect_eq "$(gate_branches)" "main " revert-gate.branch
}

register install_remote_only_branch
case_install_remote_only_branch() {
  fresh_clone
  try run_at "$C" sh .githooks/install.sh develop main
  expect_rc 0 "develop 只在远程"
  expect_out "git branch develop"
  expect_installed
  expect_eq "$(gate_branches)" "develop main " revert-gate.branch
}

# ---------------------------------------------------------------------------

build_base >"$T/base.log" 2>&1 || {
  cat "$T/base.log" >&2
  die "基础夹具构建失败"
}

set +e
run_cases "$@"
rc=$?
set -e

if compare_snapshots "$SNAP_BEFORE" "$(repo_snapshot)"; then
  echo "PASS repo_untouched"
else
  echo "FAIL repo_untouched: 真实仓库在运行前后不一致"
  rc=1
fi
exit "$rc"
