#!/usr/bin/env bash
# 回退闸门（plugins/setup-git/skills/worktree/template/githooks/）的回归测试。
#   bash tools/tests/gate/run.sh [-v] [<用例名>...]
# 环境变量 GATE_TEMPLATE_DIR 可指向另一份 githooks 目录（如故意改坏的副本），默认测仓库里的那份。
#
# 每个用例从同一份基础夹具复制出独立的 bare remote 与两个 clone：
#   a —— 装了闸门的 clone，main 检出在这里；b —— 没装闸门的同事。
# main 已推送的历史：C0（f1=alpha、f2=gamma）→ G（闸门脚本）→ M1（f1 改成 beta）→ M2（f2 改成 delta）；
# 远端另有 develop 分支。闸门对「只新增内容的提交被删掉」不算撤销，所以要被撤销的提交都改写已有内容。
# 拦下的断言看退出码与关键提示片段，不断言整句；ref 有没有动另外核对。

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)/lib/common.sh"

GATE_SRC=${GATE_TEMPLATE_DIR:-$REPO_ROOT/plugins/setup-git/skills/worktree/template/githooks}
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
  git -C "$A" config "branch.feat/$1.worktreeTarget" "$target"
  git -C "$A" config "branch.feat/$1.worktreeBase" "$(sha "$A" "$target")"
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

# 嵌套：feat/b 以 feat/a 为目标分支，feat/a 因此受守护。
register block_nested_wrong_squash
case_block_nested_wrong_squash() {
  fixture
  new_wt a
  local wa=$WT
  put "$wa/f2" $(lines a1 6)
  commit_all "$wa" A1
  WT=$A/.worktrees/b
  git -C "$A" worktree add -q -b feat/b "$WT" feat/a
  git -C "$A" config branch.feat/b.worktreeTarget feat/a
  git -C "$A" config branch.feat/b.worktreeBase "$(sha "$A" feat/a)"
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
  git -C "$A" config branch.feat/b.worktreeTarget feat/a
  git -C "$A" config branch.feat/b.worktreeBase "$(sha "$A" feat/a)"
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

# ---------------------------------------------------------------------------
# 预检结果

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
  printf '# 常驻守护分支\r\n\r\n  main  \r\n\tdevelop\r\n# tail\r\n' >"$C/.githooks/branches"
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
