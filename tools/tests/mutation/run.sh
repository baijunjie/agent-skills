#!/usr/bin/env bash
# 回退闸门的变异测试：把每处关键判据逐个改坏，确认指定的 gate 用例会 FAIL。
#   bash tools/tests/mutation/run.sh [-v] [<用例名>...]
# 不认 GATE_TEMPLATE_DIR：锚点钉死在仓库这份闸门的字面文本上，指向别处会逐条报「出现 0 次」。
#
# 它回答的是 gate 套件回答不了的问题：那些用例到底压没压在这段逻辑上。
# 判据改坏了而 gate 全绿，说明这段逻辑没有用例钉住——复核时靠人逐个试出来过两次，这里把它变成回归。
# 每条变异声明「替换哪段原文、期望哪些 gate 用例 FAIL」；原文不是恰好出现一次就报错，
# 免得闸门改写之后变异悄悄落空、这个套件变成永远全绿的摆设。
#
# 命名：teeth_<被改坏的判据>。新增或修改闸门判据时在这里补一条，见 tools/tests/README.md。

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)/lib/common.sh"

GATE_SRC=$REPO_ROOT/plugins/setup-git/scripts/githooks
GATE_SRC=$(cd "$GATE_SRC" && pwd -P)
[ -f "$GATE_SRC/revert-gate.py" ] || die "找不到闸门脚本：$GATE_SRC"
GATE_RUN=$REPO_ROOT/tools/tests/gate/run.sh
[ -f "$GATE_RUN" ] || die "找不到 gate 套件：$GATE_RUN"

SNAP_BEFORE=$(repo_snapshot)
make_tmp

# 按字节替换，原文出现次数不是 1 就报错。
cat >"$T/bin/mut" <<'EOF'
#!/usr/bin/env python3
import sys
from pathlib import Path

path, old, new = sys.argv[1:4]
p = Path(path)
s = p.read_bytes().decode("utf-8")
n = s.count(old)
if n != 1:
    sys.exit(f"mut: {path} 里「{old[:60]}」出现 {n} 次，期望 1 次")
p.write_bytes(s.replace(old, new).encode("utf-8"))
EOF
chmod +x "$T/bin/mut"

# 复制一份闸门到本用例目录，返回路径。
copy_gate() {
  local m=$CASE_DIR/githooks
  mkdir -p "$m"
  cp -p "$GATE_SRC/"* "$m/"
  echo "$m"
}

run_gate() { # run_gate <闸门目录> <gate 用例>...
  local dir=$1
  shift
  # 内层退回串行：外层已经在并行跑 teeth，再乘一层并发只会互相挤。
  try env GATE_TEMPLATE_DIR="$dir" TEST_JOBS=1 bash "$GATE_RUN" "$@"
}

# 期望 FAIL 的用例之外，每条变异还要跑一条期望 PASS 的对照：闸门被改成跑不起来时，
# 点名的 block_* 也会 FAIL，报错字串与「这段逻辑没人钉住」一模一样。
# 对照必须是条 block_*——闸门死了它会跟着 FAIL，假冒当场露馅；用 allow_* 做对照假冒不出来。
# 默认这条走的是内容判据的主路径，下面的变异都不碰它；碰它的变异要自己换一条对照。
CONTROL_CASE=block_update_ref_published

expect_cases_fail() { # expect_cases_fail <期望 FAIL 的用例>... -- <期望 PASS 的对照>...
  local c pass=0
  expect_nonzero "改坏判据后 gate 应当有用例 FAIL"
  # 子层自己的安全兜底失败不能被当成「变异生效」：那是别的问题。
  expect_not_out "FAIL safety" "子层报了安全违规"
  expect_not_out "FAIL repo_untouched" "子层报真实仓库被改动"
  for c in "$@"; do
    if [ "$c" = -- ]; then
      pass=1
      continue
    fi
    if [ "$pass" = 1 ]; then
      case $OUT in
        *"PASS $c "*) ;;
        *) fail "对照用例 $c 没有 PASS：闸门多半是被改成跑不起来了，这条变异说明不了问题" ;;
      esac
    else
      case $OUT in
        *"FAIL $c:"*) ;;
        *) fail "改坏判据后 $c 仍然 PASS：这段逻辑没有用例钉住" ;;
      esac
    fi
  done
}

teeth() { # teeth <文件> <原文> <新文> -- <期望 FAIL 的 gate 用例>... [-- <对照用例>]
  local file=$1 old=$2 new=$3 dir control=$CONTROL_CASE expected=()
  shift 3
  [ "${1:-}" = -- ] || fail "teeth 的用例名前要有 --"
  shift
  while [ $# -gt 0 ] && [ "$1" != -- ]; do
    expected+=("$1")
    shift
  done
  [ ${#expected[@]} -gt 0 ] || fail "teeth 必须点名期望 FAIL 的 gate 用例，否则等于跑全套、什么都没钉住"
  [ "${1:-}" != -- ] || control=$2
  for c in "${expected[@]}" "$control"; do
    case " ${BASELINE_CASES[*]} " in
      *" $c "*) ;;
      *) fail "$c 不在 BASELINE_CASES 里：点名的用例要同时登记进去，否则没人验证它本来是绿的" ;;
    esac
  done
  dir=$(copy_gate)
  "$T/bin/mut" "$dir/$file" "$old" "$new"
  run_gate "$dir" "${expected[@]}" "$control"
  expect_cases_fail "${expected[@]}" -- "$control"
}

# ---------------------------------------------------------------------------

# 下面各条 teeth 点名到的全部 gate 用例（含对照）。teeth 会核对点名的用例都在这里，
# baseline_unmutated 用未改坏的副本把它们整批跑一遍——没验证过「本来是绿的」的用例，
# 将来因为别的原因变红时，对应的 teeth 会变成永远空转的 PASS。
BASELINE_CASES=(
  block_update_ref_published
  block_wrong_squash
  block_commit_min_lines_batch
  allow_commit_min_lines_below
  allow_commit_partial_restore
  allow_trivial_lines_not_counted
  block_prepush_pr_revert
  allow_push_after_new_worktree
  allow_rename_fresh_file
  allow_delete_postfork_file_reverts_trailer
  allow_reverts_trailer
  allow_git_revert
  allow_upstream_manual_revert_recover
  edge_prepush_pr_not_rebased
  edge_detach_branch_f_allowed
  block_merge_target_behind_remote
  block_prepush_target_behind_remote
  block_prepush_pr_append_only_squash
  block_prepush_pr_delete_fresh_file
  block_prepush_pr_rename_prefork_rewritten
  block_prepush_pr_beyond_window
  block_prepush_pr_push_head
  block_prepush_pr_renamed_dest
  block_prepush_pr_remote_only_target
  block_prepush_revert_commit
  block_force_push_rewrite
  block_force_push_remote_ahead
  block_s7_reset_checked_out_main
  block_reset_unpushed_only_on_main
  block_align_beyond_window
  block_commit_on_main_revert
  block_prepush_pr_fixed_script_wins
  allow_pr_prepare_on_target
  edge_hook_script_error_allows
  edge_prepush_pr_no_remote_target
  edge_prepush_pr_parent_without_remote
  check_pr_head_arg
  check_behind
  check_pr_not_rebased
  install_pr_only_keeps_branches
  install_pr_only_rejects_args
  install_existing_prepush_atomic
  install_from_branches_file
  install_typo_branch
  install_from_subdir
)

register baseline_unmutated
case_baseline_unmutated() {
  # 没改坏时这些用例必须全绿：否则下面每条变异的 FAIL 都说明不了问题。
  local dir
  dir=$(copy_gate)
  run_gate "$dir" "${BASELINE_CASES[@]}"
  expect_rc 0 "未改坏的副本"
}

register teeth_bases_skip_self
case_teeth_bases_skip_self() {
  teeth revert-gate.py '    bases = [b for b in bases if b != new]
' '' -- allow_push_after_new_worktree
}

register teeth_bases_on_tips
case_teeth_bases_on_tips() {
  teeth revert-gate.py '[old, *forks, *(f"{sha}^" for sha in published)],
                                               bases=forks)' \
    '[old, *forks, *(f"{sha}^" for sha in published)])' -- block_merge_target_behind_remote
}

register teeth_bases_on_prepush
case_teeth_bases_on_prepush() {
  teeth revert-gate.py 'ok = check_move(branch, remote, local, "pre-push",
                        forks=recorded_forks(b for b in branches_at(local) if b != branch)) and ok' \
    'ok = check_move(branch, remote, local, "pre-push") and ok' -- block_prepush_target_behind_remote
}

register teeth_bases_on_check_pr
case_teeth_bases_on_check_pr() {
  teeth revert-gate.py 'return 0 if check_pr(argv[3], argv[2], tip, new, "check-pr",
                                 bases=recorded_forks({argv[3], *branches_at(new)})) else 1' \
    'return 0 if check_pr(argv[3], argv[2], tip, new, "check-pr") else 1' -- check_pr_head_arg
}

register teeth_structural_suspects
case_teeth_structural_suspects() {
  teeth revert-gate.py '    suspects = [p for p in touched if p not in authored]' \
    '    suspects = []' -- block_prepush_pr_append_only_squash block_prepush_pr_delete_fresh_file
}

register teeth_authored_finds_renames
case_teeth_authored_finds_renames() {
  teeth revert-gate.py 'git("diff-tree", "-r", "--find-renames", "--name-only", "-z", base, new,' \
    'git("diff-tree", "-r", "--no-renames", "--name-only", "-z", base, new,' \
    -- block_prepush_pr_rename_prefork_rewritten
}

register teeth_rename_sources_exempt
case_teeth_rename_sources_exempt() {
  teeth revert-gate.py '    renamed = rename_sources(old, new)' '    renamed = set()' \
    -- allow_rename_fresh_file
}

register teeth_structural_reverts_trailer
case_teeth_structural_reverts_trailer() {
  teeth revert-gate.py '        sha, _, subject = out.partition(" ")
        if any(sha.startswith(a) for a in allowed):
            continue' \
    '        sha, _, subject = out.partition(" ")' -- allow_delete_postfork_file_reverts_trailer
}

register teeth_fork_point_window
case_teeth_fork_point_window() {
  teeth revert-gate.py 'f"branch.{name}.forkPoint"' 'f"branch.{name}.noSuchKey"' \
    -- block_prepush_pr_beyond_window
}

register teeth_not_rebased_skipped
case_teeth_not_rebased_skipped() {
  teeth revert-gate.py '    if not is_ancestor(tip, new):' '    if False:' \
    -- edge_prepush_pr_not_rebased
}

register teeth_hook_remote_ref_match
case_teeth_hook_remote_ref_match() {
  teeth hook.sh '      *"${nl}refs/heads/${branch} "*|*" refs/heads/${branch} "*) pr="${pr} ${name}" ;;' \
    '      *"${nl}refs/heads/${branch} "*) pr="${pr} ${name}" ;;' -- block_prepush_pr_push_head
}

register teeth_reverts_trailer_main
case_teeth_reverts_trailer_main() {
  # 主路径的 Reverts: / git revert 放行阀（结构判据里那处另有 teeth_structural_reverts_trailer）
  teeth revert-gate.py '    allowed = overridden(old, new)' '    allowed = []' \
    -- allow_reverts_trailer allow_git_revert allow_delete_postfork_file_reverts_trailer
}

register teeth_non_fast_forward
case_teeth_non_fast_forward() {
  # 对照换成走内容判据的那条：默认的 block_update_ref_published 靠的就是这条非快进判据，会跟着被打掉。
  teeth revert-gate.py '    if not is_ancestor(old, new):' '    if False:' \
    -- block_force_push_rewrite -- block_commit_on_main_revert
}

register teeth_remote_ahead
case_teeth_remote_ahead() {
  teeth revert-gate.py '        if not has_commit(remote):' '        if False:' \
    -- block_force_push_remote_ahead
}

register teeth_both_checks_on_prepush
case_teeth_both_checks_on_prepush() {
  # 受守护那套与 PR 那套必须都跑，不是二选一
  teeth revert-gate.py '        if branch not in guarded or is_null(remote):' \
    '        if True or branch not in guarded or is_null(remote):' \
    -- block_prepush_revert_commit block_prepush_target_behind_remote
}

register teeth_busy_branches_exception
case_teeth_busy_branches_exception() {
  teeth revert-gate.py '    if unpushed and local and branch not in busy_branches():' \
    '    if unpushed and local:' -- block_s7_reset_checked_out_main
}

register teeth_align_needs_no_stranded
case_teeth_align_needs_no_stranded() {
  # 与远端跟踪分支对齐只在「不丢下未推送提交」时才直接放行
  teeth revert-gate.py '    if local and not stranded and new in remote_tips(branch):' \
    '    if local and new in remote_tips(branch):' -- block_reset_unpushed_only_on_main
}

register teeth_tips_below
case_teeth_tips_below() {
  # 对齐远程时改以远端尖端为参照：去掉它，正常的恢复流程会被误拦
  teeth revert-gate.py '        tips = tips_below(branch, old, new)' '        tips = []' \
    -- allow_upstream_manual_revert_recover
}

register teeth_upstream_ok
case_teeth_upstream_ok() {
  teeth revert-gate.py '            if not upstream_ok(argv[2]):
                return 1' '            if False:
                return 1' -- check_behind
}

register teeth_prepush_source_branch
case_teeth_prepush_source_branch() {
  teeth revert-gate.py '        source = parts[0][len("refs/heads/"):] if parts[0].startswith("refs/heads/") else branch' \
    '        source = branch' -- block_prepush_pr_renamed_dest
}

register teeth_hook_script_remote_fallback
case_teeth_hook_script_remote_fallback() {
  teeth hook.sh '  for ref in "refs/heads/${name}" "refs/remotes/${remote}/${name}" "refs/remotes/origin/${name}"; do' \
    '  for ref in "refs/heads/${name}"; do' -- block_prepush_pr_remote_only_target
}

register teeth_install_atomic
case_teeth_install_atomic() {
  teeth install.sh '    if [ -e "${target}" ] && ! grep -q '"'"'^# revert-gate hook entry'"'"' "${target}"; then' \
    '    if false; then' -- install_existing_prepush_atomic
}

register teeth_install_flags_exclusive
case_teeth_install_flags_exclusive() {
  teeth install.sh '[ "${hooks_too}${branches_too}" != 00 ] || {' '[ 1 = 1 ] || {' \
    -- install_pr_only_rejects_args
}

register teeth_min_lines
case_teeth_min_lines() {
  # 门槛调高 = 局部撤销那一支整个失效
  teeth revert-gate.py 'MIN_LINES = 3' 'MIN_LINES = 9999' -- block_commit_min_lines_batch
}

register teeth_min_lines_loose
case_teeth_min_lines_loose() {
  # 门槛调到 1 = 零星几行撞上也报，正常改动被误拦
  teeth revert-gate.py 'MIN_LINES = 3' 'MIN_LINES = 1' -- allow_commit_min_lines_below
}

register teeth_ratio_loose
case_teeth_ratio_loose() {
  teeth revert-gate.py 'RATIO = 0.5' 'RATIO = 0.0' -- allow_commit_partial_restore
}

register teeth_ratio_tight
case_teeth_ratio_tight() {
  teeth revert-gate.py 'RATIO = 0.5' 'RATIO = 0.99' -- block_prepush_pr_revert
}

register teeth_trivial_line
case_teeth_trivial_line() {
  teeth revert-gate.py 'TRIVIAL_LINE = re.compile(r"^[\s{}()\[\];,.:<>/*#-]*$")' \
    'TRIVIAL_LINE = re.compile(r"^$")' -- allow_trivial_lines_not_counted
}

register teeth_window
case_teeth_window() {
  teeth revert-gate.py 'WINDOW = 50' 'WINDOW = 1' -- block_align_beyond_window
}

register teeth_install_pr_only_keeps_branches
case_teeth_install_pr_only_keeps_branches() {
  teeth install.sh 'if [ "${branches_too}" = 0 ]; then' 'if false; then' \
    -- install_pr_only_keeps_branches
}

register teeth_align_tip_shortcut
case_teeth_align_tip_shortcut() {
  # 「对齐远端跟踪分支、又不丢下本地未推送提交就直接放行」这条早退本身：
  # 去掉它，git-pr 第 1 步的 `switch -c` + `branch -f` 退回远端会被内容判据误拦。
  teeth revert-gate.py '    if local and not stranded and new in remote_tips(branch):' \
    '    if False:' -- allow_pr_prepare_on_target edge_detach_branch_f_allowed
}

register teeth_hook_script_fixed_first
case_teeth_hook_script_fixed_first() {
  # 取闸门脚本的候选顺序：常驻守护分支优先，否则哪个旧分支上的旧脚本就成了所有分支的规则
  teeth hook.sh 'for name in ${fixed} ${hit} ${pr}; do' 'for name in ${pr} ${hit} ${fixed}; do' \
    -- block_prepush_pr_fixed_script_wins
}

register teeth_hook_hit_ref_space
case_teeth_hook_hit_ref_space() {
  # 受守护分支的两种匹配形态之一：pre-push 的每行里 ref 后面跟着空格
  teeth hook.sh '    *" refs/heads/${name}${nl}"*|*" refs/heads/${name} "*) hit="${hit} ${name}" ;;' \
    '    *" refs/heads/${name}${nl}"*) hit="${hit} ${name}" ;;' \
    -- block_prepush_revert_commit block_force_push_rewrite
}

register teeth_hook_hit_ref_eol
case_teeth_hook_hit_ref_eol() {
  # 另一种形态：reference-transaction 的每行以 ref 结尾。对照换成走 pre-push 的那条——
  # 默认的 block_wrong_squash 正是这条变异要打掉的。
  teeth hook.sh '    *" refs/heads/${name}${nl}"*|*" refs/heads/${name} "*) hit="${hit} ${name}" ;;' \
    '    *" refs/heads/${name} "*) hit="${hit} ${name}" ;;' \
    -- block_wrong_squash block_commit_on_main_revert -- block_prepush_revert_commit
}

register teeth_hook_prepared_stage
case_teeth_hook_prepared_stage() {
  # reference-transaction 只在 prepared 阶段查：认错阶段名，本地那一层就整个失效。
  # 对照同样换成 pre-push 那条（这条变异只打掉 reference-transaction 一层）。
  teeth hook.sh '[ "$1" != prepared ]' '[ "$1" != committed ]' \
    -- block_wrong_squash block_commit_on_main_revert -- block_prepush_revert_commit
}

register teeth_hook_exit_code_contract
case_teeth_hook_exit_code_contract() {
  # 入口只把退出码 3 当作拒绝，别的非零（脚本跑不起来、与本机 Python 不兼容）一律放行。
  teeth hook.sh '[ $? -ne 3 ] || exit 1' '[ $? -eq 0 ] || exit 1' \
    -- edge_hook_script_error_allows
}

register teeth_prepush_pr_no_target
case_teeth_prepush_pr_no_target() {
  # PR 路径的第一条放行支路：被推的分支没记 targetBranch 就不走这套检查。
  # 对照换成 block_prepush_pr_revert——默认那条中途要成功推一次 main，会被这条变异打掉。
  teeth revert-gate.py '    if not target:
        return True' '    if not target:
        return False' -- allow_push_after_new_worktree -- block_prepush_pr_revert
}

register teeth_prepush_pr_unresolved_notice
case_teeth_prepush_pr_unresolved_notice() {
  # 第二条支路：目标分支的远端状态定不下时放行，但必须打一行「没查」，退出码 0 不能让人以为查过了。
  teeth revert-gate.py '        print(f"\n[revert-gate] 没查 {branch}：定不下 {target} 的远端状态——它有多个同名远端跟踪分支、"
              f"却没设上游，或上游不是远端分支。`git branch -u <远端>/{target} {target}` 设好上游后再推。\n",
              file=sys.stderr)
' '' -- edge_prepush_pr_no_remote_target
}

register teeth_prepush_pr_target_without_remote
case_teeth_prepush_pr_target_without_remote() {
  # 第三条支路：目标分支一个远端跟踪分支都没有（只在本地的目标分支）是「不查」而不是「查不了」，
  # 不打提示——每次推送都刷一行只会让人把它当噪声。
  teeth revert-gate.py '        if not remote_refs(target):' '        if False:' \
    -- edge_prepush_pr_parent_without_remote
}

register teeth_check_pr_not_rebased_notice
case_teeth_check_pr_not_rebased_notice() {
  # check-pr 预检遇上「还没 rebase 到最新目标分支」要提示并退出码 1，而不是像 pre-push 那样静默放行
  teeth revert-gate.py '        if mode == "check-pr":' '        if False:' \
    -- check_pr_not_rebased
}

register teeth_install_branches_trim_tail
case_teeth_install_branches_trim_tail() {
  # branches 的行尾空白要去掉，否则 CRLF 的文件里每个分支名都带着 \r
  teeth install.sh $'-e \'s/[[:space:]]*$//\' ' '' -- install_from_branches_file
}

register teeth_install_branches_trim_head
case_teeth_install_branches_trim_head() {
  # 行首空白要去掉，否则缩进过的注释行躲过 /^#/d，被当成分支名
  teeth install.sh $'-e \'s/^[[:space:]]*//\' ' '' -- install_from_branches_file
}

register teeth_install_branch_exists
case_teeth_install_branch_exists() {
  # 拼错的分支名要挡住：本地或某个远端得有这个分支
  teeth install.sh '    git rev-parse --verify -q "refs/heads/${branch}" >/dev/null ||' '    true ||' \
    -- install_typo_branch
}

register teeth_install_repo_root
case_teeth_install_repo_root() {
  # 仓库根要用 --show-toplevel 取，不能当成当前目录：从子目录执行照样要装得上
  teeth install.sh 'root=$(git rev-parse --show-toplevel)' 'root=$(pwd)' -- install_from_subdir
}

# ---------------------------------------------------------------------------

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
