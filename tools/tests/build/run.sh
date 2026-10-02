#!/usr/bin/env bash
# 安装器构建 tools/installer/build.py 的变异测试。
#   bash tools/tests/build/run.sh [-v] [<用例名>...]
# 环境变量 BUILD_PY 可指向另一份 build.py（如故意删掉某项校验的副本），默认测仓库里的那份。
#
# 基础夹具是真实工作副本里 tools/installer/ 与 plugins/setup-*/ 的一份拷贝（build.py 只读写这两处）。
# 每个用例再复制出独立的副本 $W，施加一处破坏，在副本里运行 build.py：
#   bad_*    写模式与 --check 都报错退出（退出码 1）且输出含关键片段，写模式报错后生成物一个不变
#   allow_*  看似可疑、但按约定应放行的写法：写模式与 --check 都通过
#   check_*  --check 对生成物的比对
# 断言只看关键片段，不断言整句。

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)/lib/common.sh"

BUILD_PY_SRC=${BUILD_PY:-$REPO_ROOT/tools/installer/build.py}
[ -f "$BUILD_PY_SRC" ] || die "找不到 build.py：$BUILD_PY_SRC"
BUILD_PY_SRC=$(cd "$(dirname "$BUILD_PY_SRC")" && pwd -P)/$(basename "$BUILD_PY_SRC")

SNAP_BEFORE=$(repo_snapshot)
make_tmp

# ---------------------------------------------------------------------------
# 夹具与小工具

# 改文件的小工具，按字节读写（不做换行转换），改不到预期的位置就报错，免得破坏悄悄落空：
#   mut sub <文件> <原文> <新文> [<期望出现次数，默认 1>]   全部替换，原文出现次数须等于期望
#   mut append|prepend <文件> <文字>
#   mut crlf|cr <文件>                                      换行改成 CRLF / 单独的 CR
cat >"$T/bin/mut" <<'EOF'
#!/usr/bin/env python3
import sys
from pathlib import Path

op, path, *rest = sys.argv[1:]
p = Path(path)
s = p.read_bytes().decode("utf-8")
if op == "sub":
    old, new = rest[0], rest[1]
    want = int(rest[2]) if len(rest) > 2 else 1
    n = s.count(old)
    if n != want:
        sys.exit(f"mut: {path} 里「{old}」出现 {n} 次，期望 {want} 次")
    s = s.replace(old, new)
elif op == "append":
    s = s + rest[0]
elif op == "prepend":
    s = rest[0] + s
elif op == "crlf":
    s = s.replace("\n", "\r\n")
elif op == "cr":
    s = s.replace("\n", "\r")
else:
    sys.exit(f"mut: 未知操作 {op}")
p.write_bytes(s.encode("utf-8"))
EOF
chmod +x "$T/bin/mut"
mut() { "$T/bin/mut" "$@"; }

# 生成物（各安装器的 SKILL.md）的校验和清单，用于判断写模式有没有动过它们。
outputs_hash() {
  (cd "$1" && find plugins -path 'plugins/setup-*/skills/*/SKILL.md' -type f | LC_ALL=C sort | while IFS= read -r f; do
    printf '%s %s\n' "$(cksum <"$f")" "$f"
  done)
}

build_base() {
  local base=$T/base
  mkdir -p "$base/tools" "$base/plugins"
  cp -R "$REPO_ROOT/plugins/"setup-* "$base/plugins/"
  cp -R "$REPO_ROOT/tools/installer" "$base/tools/installer"
  cp "$BUILD_PY_SRC" "$base/tools/installer/build.py"
  BASE_HASH=$(outputs_hash "$base")
}

# 每个用例的副本：W 根目录，I 安装器目录，S 源文件，F 片段，P plugins，BPY 副本里的 build.py。
fixture() {
  W=$CASE_DIR/w
  cp -R "$T/base" "$W"
  I=$W/tools/installer
  S=$I/sources
  F=$I/fragments
  P=$W/plugins
  BPY=$I/build.py
}

build() { try run_at "$W" python3 tools/installer/build.py "$@"; }

# 写模式与 --check 都报错退出且输出含给定的全部片段；写模式报错后生成物一个不变。
expect_build_fails() {
  local s
  build
  expect_rc 1 "build.py"
  for s in "$@"; do expect_out "$s" "build.py"; done
  expect_eq "$(outputs_hash "$W")" "$BASE_HASH" "写模式报错后生成物应一个不变"
  build --check
  expect_rc 1 "build.py --check"
  for s in "$@"; do expect_out "$s" "build.py --check"; done
}

# 写模式与 --check 都通过。
expect_build_ok() {
  build
  expect_rc 0 "build.py"
  build --check
  expect_rc 0 "build.py --check"
}

# 一个用例一处破坏：bad <用例名> <函数体>，函数体里先破坏再 expect_build_fails。
# 用例体统一以 fixture 开头，这里省去重复。
bad() {
  register "$1"
  eval "case_$1() { fixture; $2; }"
}

openai_yaml() { printf '%b' "$1" >"$P/setup-agent/skills/plan/agents/openai.yaml"; }
CRON_TPL='$P/setup-tools/skills/cron/template/cron/tasks.conf'
WT_TPL='$P/setup-git/skills/worktree/template/git-worktree.md'
WT_RULES='$P/setup-git/skills/worktree/template/rules.md'
WF_TPL='$P/setup-agent/skills/workflow/template/workflow.md'

# ---------------------------------------------------------------------------
# 基线

register baseline_build_and_check
case_baseline_build_and_check() {
  fixture
  build
  expect_rc 0 "未破坏的副本写模式"
  expect_eq "$(outputs_hash "$W")" "$BASE_HASH" "工作副本的生成物应已是最新，重新生成后不变"
  build --check
  expect_rc 0 "未破坏的副本 --check"
  local n=0 f dir first name sources
  sources=$(find "$S" -name '*.md' | wc -l | tr -d ' ')
  while IFS= read -r f; do
    n=$((n + 1))
    dir=$(basename "$(dirname "$f")")
    first=$(head -n 1 "$f")
    expect_eq "$first" "---" "$f 的首行"
    name=$(awk 'NR > 1 && $0 == "---" { exit } NR > 1 && /^name: / { sub(/^name: /, ""); print }' "$f")
    expect_eq "$name" "$dir" "$f 的 name"
  done < <(find "$P" -path '*/setup-*/skills/*/SKILL.md' -type f)
  expect_eq "$n" "$sources" "生成物个数应等于源文件个数"
}

register check_usage
case_check_usage() {
  fixture
  build --nope
  expect_rc 2 "未知参数"
}

register check_stale_after_source_edit
case_check_stale_after_source_edit() {
  fixture
  mut sub "$S/agent-plan.md" "本安装器另外要查的冲突：无。" "本安装器另外要查的冲突：无（改过）。"
  build --check
  expect_rc 1 "源文件改过、生成物未重新生成"
  expect_out "生成物过期：plugins/setup-agent/skills/plan/SKILL.md"
  expect_not_out "生成物过期：plugins/setup-git"
  build
  expect_rc 0 "重新生成"
  build --check
  expect_rc 0 "重新生成后 --check"
}

register check_generated_hand_edited
case_check_generated_hand_edited() {
  fixture
  mut append "$P/setup-agent/skills/plan/SKILL.md" $'\n手改的一行\n'
  build --check
  expect_rc 1 "手改生成物"
  expect_out "生成物过期：plugins/setup-agent/skills/plan/SKILL.md"
  build
  expect_rc 0 "重新生成"
  expect_eq "$(outputs_hash "$W")" "$BASE_HASH" "重新生成后应恢复原样"
}

register check_generated_crlf
case_check_generated_crlf() {
  fixture
  mut crlf "$P/setup-git/skills/commit/SKILL.md"
  build --check
  expect_rc 1 "生成物改成 CRLF"
  expect_out "生成物过期：plugins/setup-git/skills/commit/SKILL.md"
  build
  expect_rc 0 "重新生成"
  expect_eq "$(outputs_hash "$W")" "$BASE_HASH" "重新生成后应恢复成 LF"
}

register check_generated_missing
case_check_generated_missing() {
  fixture
  rm "$P/setup-tools/skills/cron/SKILL.md"
  build --check
  expect_rc 1 "生成物缺失"
  expect_out "生成物过期：plugins/setup-tools/skills/cron/SKILL.md"
  build
  expect_rc 0 "重新生成"
  expect_eq "$(outputs_hash "$W")" "$BASE_HASH" "重新生成后应补回"
}

register allow_source_crlf_and_cr
case_allow_source_crlf_and_cr() {
  fixture
  mut crlf "$S/agent-plan.md"
  mut crlf "$F/pre-write.md"
  mut cr "$S/git-commit.md"
  expect_build_ok
  expect_eq "$(outputs_hash "$W")" "$BASE_HASH" "源文件与片段的 CRLF / CR 应归一成 LF，生成物不变"
}

# 写模式先渲染并校验全部安装器：最后一个安装器出错时，前面那个本该更新的生成物也不能被写。
register bad_write_atomic_last_installer
case_bad_write_atomic_last_installer() {
  fixture
  local last
  last=$(python3 -c 'import ast, sys
tree = ast.parse(open(sys.argv[1], encoding="utf-8").read())
for node in tree.body:
    if isinstance(node, ast.Assign) and getattr(node.targets[0], "id", "") == "INSTALLERS":
        print(node.value.keys[-1].value)' "$BPY")
  expect_eq "$last" "tools-codex-bridge" "INSTALLERS 的最后一个安装器"
  mut sub "$S/agent-plan.md" "本安装器另外要查的冲突：无。" "本安装器另外要查的冲突：无（改过）。"
  mut append "$S/$last.md" $'\n{{undeclared_at_last}}\n'
  expect_build_fails "未声明的变量 undeclared_at_last"
  # 修好最后一个，同一份副本就能写出 plan 的新内容：证明上面没写是因为整批未通过，而不是改动本身不生效。
  mut sub "$S/$last.md" $'\n{{undeclared_at_last}}\n' ""
  build
  expect_rc 0 "修好后写模式"
  case $(cat "$P/setup-agent/skills/plan/SKILL.md") in
    *"无（改过）"*) ;;
    *) fail "修好后 plan 的生成物应写出改动" ;;
  esac
}

# ---------------------------------------------------------------------------
# 展开：片段、include、变量

bad bad_missing_fragment 'mut append "$S/agent-plan.md" $'"'"'\n{{include: no-such-fragment}}\n'"'"'
  expect_build_fails "片段不存在 no-such-fragment" "sources/agent-plan.md 第"'
bad bad_missing_fragment_nested 'mut append "$F/state-mismatch.md" $'"'"'\n{{include: no-such-fragment}}\n'"'"'
  expect_build_fails "片段不存在 no-such-fragment" "fragments/state-mismatch.md 第"'
bad bad_include_cycle_self 'mut append "$F/state-mismatch.md" $'"'"'\n{{include: state-mismatch}}\n'"'"'
  expect_build_fails "循环 include" "fragments/state-mismatch.md -> fragments/state-mismatch.md"'
bad bad_include_cycle_indirect 'mut append "$F/project-root.md" $'"'"'\n{{include: skill-priority}}\n'"'"'
  mut append "$F/skill-priority.md" $'"'"'\n{{include: project-root}}\n'"'"'
  expect_build_fails "循环 include"'
bad bad_undeclared_variable 'mut append "$S/agent-plan.md" $'"'"'\n{{no_such_var}}\n'"'"'
  expect_build_fails "未声明的变量 no_such_var" "sources/agent-plan.md 第"'
register bad_undeclared_variable_in_fragment
case_bad_undeclared_variable_in_fragment() {
  fixture
  mut append "$F/state-mismatch.md" $'\n{{no_such_var}}\n'
  # 报错的行号指回片段文件里的原始行（片段开头的说明块不进生成物，但行号照算）
  local line
  line=$(grep -n '{{no_such_var}}' "$F/state-mismatch.md" | cut -d: -f1)
  expect_build_fails "未声明的变量 no_such_var" "fragments/state-mismatch.md 第 $line 行" "引入"
}

register bad_fragment_header_unclosed
case_bad_fragment_header_unclosed() {
  fixture
  # 片段开头的说明块只认独占一行的 <!-- 与 -->
  python3 - "$F/skill-priority-project.md" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
lines = p.read_text(encoding="utf-8").split("\n")
if lines[0] == "<!--":
    lines = lines[lines.index("-->") + 1:]
p.write_text("\n".join(["<!--", "说明没有收尾 --> 不独占一行"] + lines), encoding="utf-8")
PY
  expect_build_fails "fragments/skill-priority-project.md 开头的说明块没有独占一行的 -->"
}

register allow_fragment_header_stripped
case_allow_fragment_header_stripped() {
  fixture
  # 给一个片段加上（或改写）开头的说明块，生成物不变；正文以带内容的 HTML 注释开头的不当说明块
  python3 - "$F/scope-select.md" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
lines = p.read_text(encoding="utf-8").split("\n")
if lines[0] == "<!--":
    lines = lines[lines.index("-->") + 1:]
    if lines and lines[0] == "":
        lines = lines[1:]
p.write_text("\n".join(["<!--", "测试加的说明，含 {{不是变量}} 与 {{include: no-such}}", "-->", ""] + lines), encoding="utf-8")
PY
  expect_build_ok
  expect_eq "$(outputs_hash "$W")" "$BASE_HASH" "说明块不进生成物"
}
bad bad_leftover_open_braces 'mut append "$S/agent-plan.md" $'"'"'\n写成 {{ 半截\n'"'"'
  expect_build_fails "残留 {{ 或 }}"'
bad bad_leftover_close_braces 'mut append "$S/agent-plan.md" $'"'"'\n写成 }} 半截\n'"'"'
  expect_build_fails "残留 {{ 或 }}"'
bad bad_leftover_malformed_variable 'mut append "$S/agent-plan.md" $'"'"'\n{{scope lead}}\n'"'"'
  expect_build_fails "残留 {{ 或 }}"'
bad bad_leftover_malformed_include 'mut append "$S/agent-plan.md" $'"'"'\n{{include: pre-write}} 后面有字\n'"'"'
  expect_build_fails "残留 {{ 或 }}"'
bad bad_leftover_in_fragment 'mut append "$F/state-mismatch.md" $'"'"'\n半截 }}\n'"'"'
  expect_build_fails "残留 {{ 或 }}" "fragments/state-mismatch.md 第"'
bad bad_injected_fragment_include 'mut append "$F/subagent-rule.md" $'"'"'\n{{include: project-root}}\n'"'"'
  expect_build_fails "经 fragment() 注入的片段不能 include" "fragments/subagent-rule.md"'
bad bad_injected_fragment_refs_injected 'mut sub "$BPY" "\"subagent_rule\": fragment(\"subagent-rule\", lead=\"\\n\")}," "\"subagent_rule\": fragment(\"subagent-rule\", lead=\"\\n\"), \"x_inj\": fragment(\"project-root\")}," 2
  mut append "$F/subagent-rule.md" "{{x_inj}}"
  expect_build_fails "经 fragment() 注入的片段不能引用另一个注入的变量 x_inj"'
bad bad_fragment_call_missing 'mut sub "$BPY" "fragment(\"subagent-rule\", lead=\"\\n\")" "fragment(\"no-such-fragment\", lead=\"\\n\")" 2
  expect_build_fails "变量引用的片段不存在 no-such-fragment"'
bad bad_fragment_call_lead_not_blank 'mut sub "$BPY" "fragment(\"subagent-rule\", lead=\"\\n\")" "fragment(\"subagent-rule\", lead=\"x\")" 2
  expect_build_fails "lead 只能是空白"'
bad bad_multiline_var_in_indented_line 'mut append "$S/agent-change-check.md" $'"'"'\n- 列表项\n  {{subagent_rule}}\n'"'"'
  expect_build_fails "缩进的行里不能引用多行的变量 subagent_rule"'
bad bad_multiline_extra_env_in_indented_line 'mut append "$S/agent-report-style.md" $'"'"'\n- 列表项\n  {{extra_env}}\n'"'"'
  expect_build_fails "缩进的行里不能引用多行的变量 extra_env"'
bad bad_orphan_fragment 'printf "没人用的片段\n" >"$F/unused-fragment.md"
  expect_build_fails "fragments/unused-fragment.md 没有被任何源文件 include"'

# ---------------------------------------------------------------------------
# INSTALLERS

bad bad_unreferenced_variable 'mut sub "$BPY" "\"agent-plan\": (\"project-user\", {})," "\"agent-plan\": (\"project-user\", {\"foo\": \"bar\"}),"
  expect_build_fails "INSTALLERS 声明的变量 foo 在展开后的正文里没有被引用"'
bad bad_unreferenced_default_variable 'mut sub "$BPY" "\"git-pr\": (\"project\", {" "\"git-pr\": (\"project\", {\"subagent_rule\": \"\", "
  expect_build_fails "git-pr: INSTALLERS 声明的变量 subagent_rule 在展开后的正文里没有被引用"'
bad bad_declared_derived_variable 'mut sub "$BPY" "\"agent-plan\": (\"project-user\", {})," "\"agent-plan\": (\"project-user\", {\"marker\": \"x\"}),"
  expect_build_fails "marker 由作用域或源文件名决定"'
bad bad_declared_scope_variable 'mut sub "$BPY" "\"agent-plan\": (\"project-user\", {})," "\"agent-plan\": (\"project-user\", {\"scope_tail\": \"x\"}),"
  expect_build_fails "scope_tail 由作用域或源文件名决定"'
bad bad_unknown_scope 'mut sub "$BPY" "\"agent-plan\": (\"project-user\", {})," "\"agent-plan\": (\"global\", {}),"
  expect_build_fails "未知作用域 global"'
for pair in "root=/" "trailing_slash=/cron/" "dotdot=/.." "dot_segment=/./cron" "dotdot_tail=/cron/.." "no_leading_slash=cron" "space=/cr on"; do
  bad "bad_template_sub_${pair%%=*}" "mut sub \"\$BPY\" '{\"template_sub\": \"/cron\"}' '{\"template_sub\": \"${pair#*=}\"}'
  expect_build_fails 'template_sub 须形如'"
done
bad bad_template_dir_missing 'mut sub "$BPY" "{\"template_sub\": \"/cron\"}" "{\"template_sub\": \"/no-such\"}"
  expect_build_fails "TEMPLATE_DIR 指向的目录不存在 plugins/setup-tools/skills/cron/template/no-such"'
bad bad_template_dir_removed 'rm -rf "$P/setup-tools/skills/cron/template/cron"
  expect_build_fails "TEMPLATE_DIR 指向的目录不存在"'
bad bad_skill_targets_template_missing 'rm "$P/setup-git/skills/commit/template/git-commit.md"
  expect_build_fails "include 了 skill-targets，模板 plugins/setup-git/skills/commit/template/git-commit.md 却不存在"'
bad bad_skill_template_name_renamed "mut sub \"$WT_TPL\" 'name: git-worktree' 'name: git-worktree-ops'
  expect_build_fails '模板 plugins/setup-git/skills/worktree/template/git-worktree.md 的 frontmatter name 是 git-worktree-ops' '没有装到 skills/git-worktree-ops 的命令'"
bad bad_skill_install_path_renamed 'mut sub "$S/agent-workflow.md" "skills/agent-workflow-edit" "skills/agent-workflow-edited" 6
  expect_build_fails "模板 plugins/setup-agent/skills/workflow/template/agent-workflow-edit.md 的 frontmatter name 是 agent-workflow-edit" "没有装到 skills/agent-workflow-edit 的命令"'
bad bad_skill_install_cmd_renamed 'mut sub "$S/git-worktree.md" "skills/git-worktree/SKILL.md" "skills/git-wt/SKILL.md" 2
  mut sub "$S/git-worktree.md" "mkdir -p .agents/skills/git-worktree" "mkdir -p .agents/skills/git-wt"
  mut sub "$S/git-worktree.md" "mkdir -p .claude/skills/git-worktree" "mkdir -p .claude/skills/git-wt"
  expect_build_fails "bash 代码块里却没有装到 skills/git-worktree 的命令"'
register bad_appended_template_missing
case_bad_appended_template_missing() {
  fixture
  mut sub "$S/git-worktree.md" 'rules.md" >> CLAUDE.md' 'no-such.md" >> CLAUDE.md'
  expect_build_fails "正文要追加的模板 plugins/setup-git/skills/worktree/template/no-such.md 不存在"
}

bad bad_instruction_template_no_leading_blank "tail -n +2 \"$WT_RULES\" >\"$WT_RULES.new\" && mv \"$WT_RULES.new\" \"$WT_RULES\"
  expect_build_fails '模板 plugins/setup-git/skills/worktree/template/rules.md 被整块追加进指令文件，首行必须是空行'"

# 子目录下的模板装到别处（子代理、输出风格），不按装出的 skill 查
register allow_subdir_template_name
case_allow_subdir_template_name() {
  fixture
  mkdir -p "$P/setup-git/skills/worktree/template/agents"
  printf -- '---\nname: never-installed\ndescription: x\n---\n' >"$P/setup-git/skills/worktree/template/agents/never-installed.md"
  expect_build_ok
}

# ---------------------------------------------------------------------------
# extra_env

register bad_extra_env_no_leading_newline
case_bad_extra_env_no_leading_newline() {
  fixture
  mut sub "$BPY" "RENDER_STYLE = '\\nRENDER_STYLE=" "RENDER_STYLE = 'RENDER_STYLE="
  expect_build_fails "extra_env 须以换行开头"
}

register bad_extra_env_unquoted
case_bad_extra_env_unquoted() {
  fixture
  mut sub "$BPY" 'RENDER_STYLE="$SETUP_ROOT/scripts/render-report-style.py"' 'RENDER_STYLE=$SETUP_ROOT/scripts/render-report-style.py'
  expect_build_fails "extra_env 里每一行都须是"
}

bad bad_extra_env_used_undefined 'mut sub "$BPY" "\"agent-report-style\": (\"project-user\", {\"extra_env\": RENDER_STYLE})," "\"agent-report-style\": (\"project-user\", {\"extra_env\": RENDER_AGENT}),"
  expect_build_fails "正文用到了 \$RENDER_STYLE"'
bad bad_extra_env_brace_use_undefined 'mut append "$S/agent-plan.md" $'"'"'\n```bash\necho "${RENDER_FOO:?}"\n```\n'"'"'
  expect_build_fails "正文用到了 \$RENDER_FOO"'
bad bad_extra_env_defined_unused 'mut sub "$BPY" "\"agent-plan\": (\"project-user\", {})," "\"agent-plan\": (\"project-user\", {\"extra_env\": RENDER_AGENT}),"
  expect_build_fails "extra_env 定义了 RENDER_AGENT，正文却没有用到"'

register allow_extra_env_brace_use
case_allow_extra_env_brace_use() {
  fixture
  mut sub "$BPY" '"agent-plan": ("project-user", {}),' '"agent-plan": ("project-user", {"extra_env": RENDER_AGENT}),'
  mut append "$S/agent-plan.md" $'\n```bash\necho "${RENDER_AGENT:?}"\n```\n'
  expect_build_ok
}

# ---------------------------------------------------------------------------
# 登记

bad bad_unregistered_source 'cp "$S/agent-plan.md" "$S/agent-extra.md"
  expect_build_fails "sources/agent-extra.md 没有在 INSTALLERS 里登记"'
bad bad_registered_source_missing 'rm "$S/git-pr.md"
  expect_build_fails "INSTALLERS 登记的 git-pr 没有源文件 sources/git-pr.md"'
bad bad_source_name_without_domain 'cp "$S/agent-plan.md" "$S/nodomain.md"
  mut sub "$BPY" "\"agent-plan\": (\"project-user\", {})," "\"agent-plan\": (\"project-user\", {}), \"nodomain\": (\"project\", {}),"
  expect_build_fails "nodomain: 源文件名须为 <领域>-<skill>"'
bad bad_registry_residual_dir 'mkdir -p "$P/setup-git/skills/old-skill/template" && : >"$P/setup-git/skills/old-skill/template/x.md"
  expect_build_fails "plugins/setup-git/skills/old-skill 没有对应的登记源文件"'
bad bad_registry_stray_file ': >"$P/setup-git/skills/notes.md"
  expect_build_fails "plugins/setup-git/skills/notes.md 散落在 skills/ 下"'

register allow_ds_store
case_allow_ds_store() {
  fixture
  : >"$P/setup-git/skills/.DS_Store"
  mkdir -p "$P/setup-agent/skills/.DS_Store"
  # template/ 里的 .DS_Store 不按模板查标记
  printf '<!-- setup-bogus\n' >"$P/setup-tools/skills/cron/template/.DS_Store"
  expect_build_ok
}

# ---------------------------------------------------------------------------
# frontmatter

bad bad_source_first_line_blank 'mut prepend "$S/agent-plan.md" $'"'"'\n'"'"'
  expect_build_fails "agent-plan: 源文件首行必须是 ---"'
bad bad_source_first_line_comment 'mut prepend "$S/agent-plan.md" $'"'"'<!-- 注释 -->\n'"'"'
  expect_build_fails "agent-plan: 源文件首行必须是 ---"'
bad bad_source_frontmatter_unclosed 'mut sub "$S/agent-plan.md" $'"'"'disable-model-invocation: true\n---\n'"'"' $'"'"'disable-model-invocation: true\n---x\n'"'"'
  expect_build_fails "源文件的 frontmatter 没有独占一行的结尾 ---"'
bad bad_source_dup_key_override 'mut sub "$S/agent-plan.md" $'"'"'disable-model-invocation: true\n'"'"' $'"'"'disable-model-invocation: true\ndisable-model-invocation: false\n'"'"'
  expect_build_fails "源文件的 frontmatter 里 disable-model-invocation 出现了 2 次"'
bad bad_source_dup_key_name 'mut sub "$S/agent-plan.md" $'"'"'name: plan\n'"'"' $'"'"'name: plan\nname: plan\n'"'"'
  expect_build_fails "源文件的 frontmatter 里 name 出现了 2 次"'
bad bad_generated_dup_key 'mut sub "$BPY" "\"agent-plan\": (\"project-user\", {})," "\"agent-plan\": (\"project-user\", {\"fm_extra\": \"name: other\"}),"
  mut sub "$S/agent-plan.md" $'"'"'disable-model-invocation: true\n'"'"' $'"'"'disable-model-invocation: true\n{{fm_extra}}\n'"'"'
  expect_build_fails "生成物的 frontmatter 里 name 出现了 2 次"'
bad bad_generated_name_mismatch 'mut sub "$S/agent-plan.md" $'"'"'name: plan\n'"'"' $'"'"'name: plans\n'"'"'
  expect_build_fails "frontmatter 的 name 须为所在目录名 plan"'
bad bad_description_missing 'mut sub "$S/agent-plan.md" "description: {{scope_lead}}" "summary: {{scope_lead}}"
  expect_build_fails "源文件缺少 description"'
bad bad_description_no_scope_lead 'mut sub "$S/agent-plan.md" "description: {{scope_lead}}" "description: 装上{{scope_lead}}"
  expect_build_fails "description 须以 {{scope_lead}} 开头并引用一次 {{scope_tail}}"'
bad bad_description_scope_tail_twice 'mut sub "$S/agent-plan.md" "{{scope_tail}}用于" "{{scope_tail}}{{scope_tail}}用于"
  expect_build_fails "引用一次 {{scope_tail}}"'
bad bad_description_scope_tail_missing 'mut sub "$S/agent-plan.md" "{{scope_tail}}用于" "用于"
  expect_build_fails "引用一次 {{scope_tail}}"'
bad bad_description_scope_tail_not_before_yongyu 'mut sub "$S/agent-plan.md" "{{scope_tail}}用于" "{{scope_tail}}适用于"
  expect_build_fails "{{scope_tail}} 须紧接末尾的「用于……等场景。」这一句"'
bad bad_description_not_ending_changjing 'mut sub "$S/agent-plan.md" $'"'"'"等场景。\ndisable-model-invocation'"'"' $'"'"'"等情形。\ndisable-model-invocation'"'"'
  expect_build_fails "{{scope_tail}} 须紧接末尾的「用于……等场景。」这一句"'
bad bad_description_extra_sentence 'mut sub "$S/agent-plan.md" "{{scope_tail}}用于\"" "{{scope_tail}}用于测试。\""
  expect_build_fails "{{scope_tail}} 须紧接末尾的「用于……等场景。」这一句"'
bad bad_description_colon_space 'mut sub "$S/agent-plan.md" "{{scope_lead}}agent-plan-write 与" "{{scope_lead}}agent-plan-write: 与"
  expect_build_fails "生成物的 description 含「: 」「 #」"'
bad bad_description_space_hash 'mut sub "$S/agent-plan.md" "{{scope_lead}}agent-plan-write 与" "{{scope_lead}}agent-plan-write #与"
  expect_build_fails "生成物的 description 含「: 」「 #」"'
bad bad_description_yaml_indicator 'mut sub "$BPY" "\"装上（或更新）\"," "\"&装上（或更新）\","
  expect_build_fails "description 以 YAML 指示字符 & 开头"'
bad bad_disable_model_invocation_missing 'mut sub "$S/agent-plan.md" $'"'"'disable-model-invocation: true\n'"'"' ""
  expect_build_fails "源文件 frontmatter 须有 disable-model-invocation: true"'
bad bad_disable_model_invocation_false 'mut sub "$S/agent-plan.md" "disable-model-invocation: true" "disable-model-invocation: false"
  expect_build_fails "源文件 frontmatter 须有 disable-model-invocation: true"'
bad bad_disable_model_invocation_in_body 'mut sub "$S/agent-plan.md" $'"'"'disable-model-invocation: true\n---\n'"'"' $'"'"'---\ndisable-model-invocation: true\n'"'"'
  expect_build_fails "源文件 frontmatter 须有 disable-model-invocation: true"'
bad bad_openai_yaml_missing 'rm "$P/setup-agent/skills/plan/agents/openai.yaml"
  expect_build_fails "缺少 plugins/setup-agent/skills/plan/agents/openai.yaml"'
bad bad_openai_yaml_not_under_policy 'openai_yaml "interface:\n  display_name: \"x\"\n  allow_implicit_invocation: false\npolicy:\n  other: 1\n"
  expect_build_fails "须设 policy.allow_implicit_invocation: false"'
bad bad_openai_yaml_top_level 'openai_yaml "allow_implicit_invocation: false\n"
  expect_build_fails "须设 policy.allow_implicit_invocation: false"'
bad bad_openai_yaml_nested_deeper 'openai_yaml "policy:\n  other:\n    allow_implicit_invocation: false\n"
  expect_build_fails "须设 policy.allow_implicit_invocation: false"'
bad bad_openai_yaml_tab_indent 'openai_yaml "policy:\n\tallow_implicit_invocation: false\n"
  expect_build_fails "用制表符缩进"'
bad bad_openai_yaml_true 'openai_yaml "policy:\n  allow_implicit_invocation: true\n"
  expect_build_fails "须设 policy.allow_implicit_invocation: false"'
bad bad_openai_yaml_dup 'openai_yaml "policy:\n  allow_implicit_invocation: false\n  allow_implicit_invocation: true\n"
  expect_build_fails "allow_implicit_invocation 出现了不止一次"'

register allow_openai_yaml_comments_and_min_indent
case_allow_openai_yaml_comments_and_min_indent() {
  fixture
  # 直接子键按块内最小缩进认：第一行缩进更深时，后面那行仍是直接子键
  openai_yaml "# 注释\ninterface:\n  display_name: \"x\"\npolicy:  # 调用策略\n    deeper: 1\n\n  allow_implicit_invocation: false  # 只能显式调用\n"
  expect_build_ok
}

# ---------------------------------------------------------------------------
# 作用域与标题

bad bad_scope_project_has_user_section 'mut append "$S/git-pr.md" $'"'"'\n## Claude Code 用户级安装\n\n装进用户级。\n'"'"'
  expect_build_fails "作用域为 project，正文不得含用户级安装节"'
bad bad_scope_project_has_scope_select_heading 'mut append "$S/git-pr.md" $'"'"'\n## 选作用域\n\n默认装进项目。\n'"'"'
  expect_build_fails "作用域为 project，正文不得含「## 选作用域」"'
bad bad_scope_user_has_project_section 'mut append "$S/tools-codex-bridge.md" $'"'"'\n## Codex 项目级安装\n\n装进项目。\n'"'"'
  expect_build_fails "作用域为 user，正文不得含项目级安装节"'
bad bad_scope_project_user_missing_user 'mut sub "$S/agent-plan.md" "## Claude Code 用户级安装" "## Claude Code 另一种装法"
  mut sub "$S/agent-plan.md" "## Codex 用户级安装" "## Codex 另一种装法"
  expect_build_fails "作用域为 project-user，正文须含用户级安装节"'
bad bad_scope_project_user_missing_project 'mut sub "$S/agent-plan.md" "## Claude Code 项目级安装（默认）" "## Claude Code 装法一"
  mut sub "$S/agent-plan.md" "## Codex 项目级安装（默认）" "## Codex 装法一"
  expect_build_fails "作用域为 project-user，正文须含项目级安装节"'
bad bad_scope_project_missing_project 'mut sub "$S/git-pr.md" $'"'"'## Claude Code 项目级安装\n'"'"' $'"'"'## Claude Code 装法\n'"'"'
  mut sub "$S/git-pr.md" $'"'"'## Codex 项目级安装\n'"'"' $'"'"'## Codex 装法\n'"'"'
  expect_build_fails "作用域为 project，正文须含项目级安装节"'
bad bad_scope_user_missing_user 'mut sub "$S/tools-codex-bridge.md" "## Codex 用户级安装" "## Codex 装法"
  expect_build_fails "作用域为 user，正文须含用户级安装节"'
bad bad_scope_select_in_project 'mut sub "$S/git-pr.md" $'"'"'{{include: skill-priority-project}}\n'"'"' $'"'"'{{include: skill-priority-project}}\n\n{{include: scope-select}}\n'"'"'
  expect_build_fails "作用域为 project，不得 include scope-select"'
bad bad_scope_select_in_project_indented 'mut append "$S/git-pr.md" $'"'"'\n- 列表项\n\n  {{include: scope-select}}\n'"'"'
  expect_build_fails "作用域为 project，不得 include scope-select"'
bad bad_scope_select_in_user 'mut sub "$S/tools-codex-bridge.md" $'"'"'{{include: pre-write}}\n'"'"' $'"'"'{{include: scope-select}}\n\n{{include: pre-write}}\n'"'"'
  expect_build_fails "作用域为 user，不得 include scope-select"'
bad bad_scope_select_handwritten 'mut sub "$S/agent-plan.md" $'"'"'{{include: scope-select}}\n'"'"' $'"'"'## 选作用域\n\n默认装进当前项目。\n'"'"'
  expect_build_fails "作用域为 project-user，须 include scope-select"'
bad bad_scope_select_twice 'mut sub "$S/agent-plan.md" $'"'"'{{include: scope-select}}\n'"'"' $'"'"'{{include: scope-select}}\n\n{{include: scope-select}}\n'"'"'
  expect_build_fails "scope-select 在展开结果里被 include 了 2 次"'
for pair in "user_config=## 用户级配置安装" "project_optional=## 项目级安装（可选）" "h3=### 项目级安装" "negated=## 不做项目级安装" \
  "indent1= ## Claude Code 用户级安装" "indent3=   ## Codex 项目级安装" "closing_hashes=## 项目级安装 ##"; do
  bad "bad_scope_heading_${pair%%=*}" "mut append \"\$S/agent-plan.md\" \$'\\n${pair#*=}\\n\\n正文。\\n'
  expect_build_fails '提到了项目级或用户级'"
done
bad bad_unclosed_fence_source 'mut append "$S/agent-plan.md" $'"'"'\n~~~\n## 某节\n```\n'"'"'
  expect_build_fails "源文件第" "代码块围栏 ~~~ 到结尾都没有闭合"'
bad bad_unclosed_fence_shorter_closer 'mut append "$S/agent-plan.md" $'"'"'\n````\n## 某节\n```\n'"'"'
  expect_build_fails "代码块围栏 \`\`\`\` 到结尾都没有闭合"'
bad bad_unclosed_fence_closer_with_text 'mut append "$S/agent-plan.md" $'"'"'\n```\n## 某节\n``` 不是结尾\n'"'"'
  expect_build_fails "代码块围栏 \`\`\` 到结尾都没有闭合"'
bad bad_unclosed_fence_generated 'mut append "$F/state-mismatch.md" $'"'"'\n\n```\n'"'"'
  expect_build_fails "生成物第" "代码块围栏 \`\`\` 到结尾都没有闭合"'
bad bad_dup_heading 'mut append "$S/agent-plan.md" $'"'"'\n## 通用步骤\n'"'"'
  expect_build_fails "代码块之外的二级标题 ## 通用步骤 出现了 2 次"'
bad bad_dup_heading_indented 'mut append "$S/agent-plan.md" $'"'"'\n  ## 通用步骤\n'"'"'
  expect_build_fails "代码块之外的二级标题 ## 通用步骤 出现了 2 次"'
bad bad_dup_heading_closing_hashes 'mut append "$S/agent-plan.md" $'"'"'\n## 通用步骤 ##\n'"'"'
  expect_build_fails "代码块之外的二级标题 ## 通用步骤 出现了 2 次"'
bad bad_dup_heading_from_fragment 'mut append "$F/state-mismatch.md" $'"'"'\n\n## 重装\n'"'"'
  expect_build_fails "代码块之外的二级标题 ## 重装 出现了 2 次"'

register allow_headings_not_checked
case_allow_headings_not_checked() {
  fixture
  # 缩进 4 格不是标题、#### 不参与作用域检查、代码块里的不是标题（~~~ 块里的 ``` 不收尾，```` 块要同样长的才收尾）
  mut append "$S/agent-plan.md" $'\n    ## 项目级安装（可选）\n\n#### 用户级配置安装\n\n```\n## 项目级安装（可选）\n## 通用步骤\n```\n\n~~~\n```\n## 用户级配置安装\n~~~\n\n````md\n```\n## 通用步骤\n````\n\n- 列表项\n\n  ```\n  ## 不做项目级安装\n  ```\n'
  expect_build_ok
}

# ---------------------------------------------------------------------------
# 片段放法

bad bad_required_include_missing 'mut sub "$S/agent-plan.md" "{{include: state-mismatch}}" ""
  expect_build_fails "agent-plan: 源文件须在顶层直接 include 一次 state-mismatch"'
bad bad_required_include_indented 'mut sub "$S/agent-plan.md" "{{include: state-mismatch}}" "  {{include: state-mismatch}}"
  expect_build_fails "源文件须在顶层直接 include 一次 state-mismatch"'
bad bad_required_include_twice 'mut sub "$S/agent-plan.md" "{{include: reinstall}}" $'"'"'{{include: reinstall}}\n\n本安装器的定制值：无。\n\n{{include: reinstall}}'"'"'
  expect_build_fails "源文件须在顶层直接 include 一次 reinstall"'
bad bad_dup_include_direct 'mut sub "$S/agent-plan.md" $'"'"'{{include: skill-priority}}\n'"'"' $'"'"'{{include: skill-priority}}\n\n{{include: skill-priority}}\n'"'"'
  expect_build_fails "skill-priority 在展开结果里被 include 了 2 次"'
bad bad_dup_include_indented 'mut append "$S/agent-plan.md" $'"'"'\n- 列表项\n\n  {{include: skill-priority}}\n'"'"'
  expect_build_fails "skill-priority 在展开结果里被 include 了 2 次"'
bad bad_dup_include_via_fragment 'mut append "$F/scope-select.md" $'"'"'\n\n{{include: skill-priority}}\n'"'"'
  expect_build_fails "skill-priority 在展开结果里被 include 了 2 次"'
bad bad_dup_include_fragment_call_and_direct 'mut sub "$S/agent-change-check.md" $'"'"'{{include: skill-priority}}\n'"'"' $'"'"'{{include: skill-priority}}\n\n{{include: subagent-rule}}\n'"'"'
  expect_build_fails "agent-change-check: subagent-rule 在展开结果里被 include 了 2 次"'
bad bad_tools_skill_targets 'mut sub "$S/tools-codex-bridge.md" "{{include: reinstall}}" $'"'"'{{include: skill-targets}}\n\n{{include: reinstall}}'"'"'
  expect_build_fails "setup-tools 装出的 skill 不带领域前缀，不能 include skill-targets"'
bad bad_host_conventions_wrong_section 'mut sub "$S/tools-cron.md" $'"'"'## 跨宿主约定\n'"'"' $'"'"'## 约定\n'"'"'
  expect_build_fails "host-conventions 须放在「## 跨宿主约定」之下，现在所在的节是 ## 约定"'
bad bad_host_conventions_heading_in_fence 'mut sub "$S/tools-cron.md" $'"'"'## 跨宿主约定\n'"'"' $'"'"'## 约定\n\n```\n## 跨宿主约定\n```\n'"'"'
  expect_build_fails "host-conventions 须放在「## 跨宿主约定」之下"'
bad bad_markers_after_pre_write 'mut sub "$S/tools-cron.md" $'"'"'{{include: markers}}\n\n{{include: pre-write}}\n'"'"' $'"'"'{{include: pre-write}}\n\n{{include: markers}}\n'"'"'
  expect_build_fails "markers 须放在 pre-write 之前"'
bad bad_pre_write_not_followed 'mut sub "$S/tools-cron.md" "本安装器另外要查的冲突：" "另外要查的冲突："
  expect_build_fails "pre-write 之后的第一段须以「本安装器另外要查的冲突：」开头"'
bad bad_reinstall_not_followed 'mut sub "$S/tools-cron.md" "本安装器的定制值：" "定制值："
  expect_build_fails "reinstall 之后的第一段须以「本安装器的定制值：」开头"'

# ---------------------------------------------------------------------------
# 标记

bad bad_source_literal_marker 'mut append "$S/tools-cron.md" $'"'"'\n<!-- setup-tools:cron:begin -->\n'"'"'
  expect_build_fails "源文件第" "手写了 setup 标记"'
bad bad_source_loose_marker 'mut append "$S/agent-plan.md" $'"'"'\n<!--setup_x:y:begin-->\n'"'"'
  expect_build_fails "手写了 setup 标记"'
bad bad_generated_malformed_marker 'mut append "$F/markers.md" $'"'"'\n  <!-- setup-agent:subagents:BEGIN -->\n'"'"'
  expect_build_fails "生成物第" "setup 标记格式不对"'
bad bad_generated_marker_wrong_name 'mut append "$F/markers.md" $'"'"'\n  <!-- setup-git:commit:begin -->\n'"'"'
  expect_build_fails "生成物里的标记 setup-git:commit 与本安装器的标记名 setup-agent:subagents 不一致"'
bad bad_template_marker_unpaired "mut append \"$CRON_TPL\" \$'\\n<!-- setup-tools:cron:begin -->\\n'
  expect_build_fails 'tasks.conf 里的标记须为 begin、end 各一个且 begin 在前'"
bad bad_template_marker_reversed "mut append \"$CRON_TPL\" \$'\\n<!-- setup-tools:cron:end -->\\n<!-- setup-tools:cron:begin -->\\n'
  expect_build_fails '标记须为 begin、end 各一个且 begin 在前，现在依次是 end、begin'"
bad bad_template_marker_two_pairs "mut append \"$WT_RULES\" \$'\\n<!-- setup-git:worktree:begin -->\\n<!-- setup-git:worktree:end -->\\n'
  expect_build_fails 'rules.md 里的标记须为 begin、end 各一个'"
bad bad_template_marker_wrong_name "mut append \"$CRON_TPL\" \$'\\n<!-- setup-tools:other:begin -->\\n<!-- setup-tools:other:end -->\\n'
  expect_build_fails '标记 setup-tools:other 与本安装器的标记名 setup-tools:cron 不一致'"
for pair in "no_space=<!--setup-tools:cron:begin-->" "underscore=<!-- setup_tools:cron:begin -->" "uppercase=<!-- SETUP-tools:cron:begin -->" \
  "colon=<!-- setup:tools:cron:begin -->" "typo=<!-- setup-tools:cron:begn -->" "double_space=<!--  setup-tools:cron:begin -->"; do
  bad "bad_template_marker_malformed_${pair%%=*}" "mut append \"$CRON_TPL\" \$'\\n${pair#*=}\\n'
  expect_build_fails 'tasks.conf 第' 'setup 标记格式不对'"
done
bad bad_markers_missing_source_marker 'mut sub "$S/tools-cron.md" $'"'"'{{include: markers}}\n\n'"'"' ""
  expect_build_fails "tools-cron: 源文件或 template/ 里有本安装器的标记，源文件却没有 include markers"'
bad bad_markers_missing_template_marker 'mut sub "$S/git-worktree.md" $'"'"'{{include: markers}}\n\n'"'"' ""
  expect_build_fails "git-worktree: 源文件或 template/ 里有本安装器的标记，源文件却没有 include markers"'
bad bad_markers_without_writing 'mut sub "$S/agent-plan.md" "{{include: pre-write}}" $'"'"'{{include: markers}}\n\n{{include: pre-write}}'"'"'
  expect_build_fails "agent-plan: include 了 markers，但源文件正文没有引用 {{marker}}"'

register allow_template_marker_pair_new_file
case_allow_template_marker_pair_new_file() {
  fixture
  printf '<!-- setup-tools:cron:begin -->\n说明\n<!-- setup-tools:cron:end -->\n' >"$P/setup-tools/skills/cron/template/cron/notes.md"
  expect_build_ok
}

# 标记范围内最浅的标题须是一级

bad bad_marked_heading_level_demoted "mut sub \"$WF_TPL\" '# 工作流' '## 工作流'
  expect_build_fails '标记范围里最浅的标题是 2 级' '顶层节标题须用 #'"
bad bad_marked_heading_level_rules_demoted "mut sub \"$WT_RULES\" '# 开发流程：Git Worktree' '## 开发流程：Git Worktree'
  expect_build_fails '标记范围里最浅的标题是 2 级'"

register bad_marked_heading_level_only_fenced_top
case_bad_marked_heading_level_only_fenced_top() {
  fixture
  # 代码块里的 # 不是标题：范围里真正最浅的标题是 `## 小节`，照样要报错
  printf '<!-- setup-tools:cron:begin -->\n\n```\n# 代码块里不是标题\n```\n\n## 小节\n\n<!-- setup-tools:cron:end -->\n' \
    >"$P/setup-tools/skills/cron/template/cron/notes.md"
  expect_build_fails "标记范围里最浅的标题是 2 级"
}

register allow_marked_heading_level_with_subsections
case_allow_marked_heading_level_with_subsections() {
  fixture
  printf '<!-- setup-tools:cron:begin -->\n\n# 顶层\n\n## 小节\n\n### 更深\n\n<!-- setup-tools:cron:end -->\n' \
    >"$P/setup-tools/skills/cron/template/cron/notes.md"
  expect_build_ok
}

# ---------------------------------------------------------------------------
# 步骤引用

bad bad_step_ref_out_of_range 'mut append "$S/tools-cron.md" $'"'"'\n见第 10 步。\n'"'"'
  expect_build_fails "引用了「第 10 步」，正文编号列表最大只到第 9 步"'
bad bad_step_ref_range 'mut append "$S/tools-cron.md" $'"'"'\n见第 2–10 步。\n'"'"'
  expect_build_fails "引用了「第 2–10 步」"'
bad bad_step_ref_list 'mut append "$S/tools-cron.md" $'"'"'\n见第 3、10 步。\n'"'"'
  expect_build_fails "引用了「第 3、10 步」"'
bad bad_step_ref_fenced_list_not_counted 'mut append "$S/tools-cron.md" $'"'"'\n```\n10. 代码块里的编号不算步骤\n```\n\n见第10步。\n'"'"'
  expect_build_fails "引用了「第10步」"'

register allow_step_ref_in_range
case_allow_step_ref_in_range() {
  fixture
  mut append "$S/tools-cron.md" $'\n见第 9 步、第 1–9 步、第 2、9 步。\n'
  expect_build_ok
}

# ---------------------------------------------------------------------------
# 命令块：TEMPLATE_DIR 守卫与 Codex 用户级 skill 位置

register bad_template_dir_unguarded
case_bad_template_dir_unguarded() {
  fixture
  mut append "$S/agent-plan.md" $'\n```bash\nmkdir -p x\ncp "$TEMPLATE_DIR/x.md" x/\n```\n'
  expect_build_fails "bash 代码块在第" "用到 \$TEMPLATE_DIR 之前没有"
}

register bad_template_dir_guard_after_use
case_bad_template_dir_guard_after_use() {
  fixture
  mut append "$S/agent-plan.md" $'\n```bash\ncp "${TEMPLATE_DIR}/x.md" x/\n: "${TEMPLATE_DIR:?}"\n```\n'
  expect_build_fails "bash 代码块在第" "守卫"
}

register bad_template_dir_guard_in_comment
case_bad_template_dir_guard_in_comment() {
  fixture
  mut append "$S/agent-plan.md" $'\n```bash\n: "${C:-1}" # "${TEMPLATE_DIR:?}"\ncp "$TEMPLATE_DIR/x.md" x/\n```\n'
  expect_build_fails "bash 代码块在第" "守卫"
}

register bad_template_dir_unguarded_in_fragment
case_bad_template_dir_unguarded_in_fragment() {
  fixture
  # skill-targets 的 Codex 用户级块去掉守卫：报错指向 include 了它的每个安装器之一
  mut sub "$F/skill-targets.md" $': "${TEMPLATE_DIR:?}"\nD=' 'D='
  expect_build_fails "bash 代码块在第" "守卫"
}

register allow_template_dir_guard_forms
case_allow_template_dir_guard_forms() {
  fixture
  # 守卫可与别的变量合写一行、放进列表项里的缩进块；非 bash 块与正文里提到的 $TEMPLATE_DIR 不查；
  # 每个块各自守卫，前一块的守卫不算到后一块，但未用到的块不需要
  mut append "$S/agent-plan.md" $'\n正文里提到 `$TEMPLATE_DIR/x.md`。\n\n```text\ncp "$TEMPLATE_DIR/x.md" y\n```\n\n- 列表项\n\n  ```bash\n  C=1\n  : "${C:?}" "${TEMPLATE_DIR:?请先定义}" # 行尾注释\n  cp "$TEMPLATE_DIR/x.md" y\n  ```\n\n```bash\necho 没用到\n```\n'
  expect_build_ok
}

for pair in 'x=$X/skills/agent-plan' 'x_brace=${X}/skills/agent-plan' 'codex_home=${CODEX_HOME:-$HOME/.codex}/skills/agent-plan' \
  'codex_home_plain=$CODEX_HOME/skills/agent-plan' 'x_guard=${X:?}/skills/agent-plan' 'x_quoted="$X"/skills/agent-plan' \
  'codex_home_guard=${CODEX_HOME:?}/skills/agent-plan' 'x_nocolon=${X?}/skills/agent-plan' 'x_assign=${X:=a}/skills/agent-plan' 'home_quoted="$HOME/.codex"/skills/agent-plan' 'tilde=~/.codex/skills/agent-plan' 'home=$HOME/.codex/skills/agent-plan'; do
  bad "bad_codex_skill_dir_${pair%%=*}" "mut append \"\$S/agent-plan.md\" \$'\\n\`${pair#*=}\`\\n'
  expect_build_fails 'Codex 用户级 skill 固定装到'"
done

register allow_codex_paths
case_allow_codex_paths() {
  fixture
  # 项目级 .agents/skills、用户级 $HOME/.agents/skills、$X/agents 与 .codex/agents 都合法
  mut append "$S/agent-plan.md" $'\n`.agents/skills/x`、`$HOME/.agents/skills/x`、`$X/agents`、`.codex/agents`、`~/.codex/AGENTS.md`、`$X/skillset`\n'
  expect_build_ok
}

# ---------------------------------------------------------------------------
# 文案

bad bad_banned_word_source 'mut append "$S/agent-plan.md" $'"'"'\n装完告诉用户。\n'"'"'
  expect_build_fails "sources/agent-plan.md 第" "用了「告诉用户」"'
bad bad_banned_word_fragment 'mut append "$F/state-mismatch.md" $'"'"'\n出错时告诉用户。\n'"'"'
  expect_build_fails "fragments/state-mismatch.md 第" "用了「告诉用户」"'

# ---------------------------------------------------------------------------
# 替换表（git-worktree 的写法 B / C）

bad bad_replacement_original_changed "mut sub \"$WT_TPL\" '与 push 都会被自动检查' '与 push 都会被检查'
  expect_build_fails '原文「移动时，本地 merge / commit / reset 与 push 都会被自动检查」' '出现了 0 次'"
bad bad_replacement_original_duplicated "mut append \"$WT_TPL\" \$'\\n移动时，本地 merge / commit / reset 与 push 都会被自动检查\\n'
  expect_build_fails '原文「移动时，本地 merge / commit / reset 与 push 都会被自动检查」' '出现了 2 次'"
bad bad_replacement_anchor_changed "mut sub \"$WT_TPL\" '- reset 被拦时，' '- 若 reset 被拦时，'
  expect_build_fails '位置「reset 被拦时」' '有 0 个列表项以它开头'"
bad bad_replacement_anchor_duplicated "mut append \"$WT_TPL\" \$'\\n- reset 被拦时的另一条\\n'
  expect_build_fails '位置「reset 被拦时」' '有 2 个列表项以它开头'"
bad bad_replacement_range_anchor_changed "mut sub \"$WT_TPL\" '- 确要撤销某个提交' '- 要撤销某个提交'
  expect_build_fails '位置「确要撤销某个提交」' '有 0 个列表项以它开头'"
bad bad_replacement_range_count "mut sub \"$WT_TPL\" '- reset 被拦时，' \$'- 插进来的一条\\n- reset 被拦时，'
  expect_build_fails '写的是「共四条」' '却有 5 条同级列表项'"
bad bad_replacement_range_reversed 'mut sub "$S/git-worktree.md" "从以「仓库装有回退闸门」开头的那条起，到以「确要撤销某个提交」开头的那条为止" "从以「确要撤销某个提交」开头的那条起，到以「仓库装有回退闸门」开头的那条为止"
  expect_build_fails "位置「仓库装有回退闸门」" "不在「确要撤销某个提交」那一条之后"'
bad bad_replacement_original_outside_item 'mut sub "$S/git-worktree.md" "| 以「reset 被拦时」开头的那条 | 整条 | 删掉 |" "| 以「reset 被拦时」开头的那条 | 「移动时，本地 merge / commit / reset 与 push 都会被自动检查」 | 删掉 |"
  expect_build_fails "不在以「reset 被拦时」开头的那一项里"'
bad bad_replacement_row_columns 'mut sub "$S/git-worktree.md" "| 以「reset 被拦时」开头的那条 | 整条 | 删掉 |" "| 以「reset 被拦时」开头的那条 | 整条 | 删掉 | 多一列 |"
  expect_build_fails "替换表行须有 位置 / 原文 / 改成 三列"'
bad bad_replacement_position_unquoted 'mut sub "$S/git-worktree.md" "| 以「reset 被拦时」开头的那条 | 整条 | 删掉 |" "| reset 被拦时那条 | 整条 | 删掉 |"
  expect_build_fails "替换表的「位置」须用「」写出所在列表项的开头"'
bad bad_replacement_template_missing "rm \"$WT_TPL\"
  expect_build_fails '正文有替换表，替换的模板 plugins/setup-git/skills/worktree/template/git-worktree.md 却不存在'"

register allow_replacement_table_in_fence
case_allow_replacement_table_in_fence() {
  fixture
  mut append "$S/agent-plan.md" $'\n```markdown\n| 位置 | 原文 | 改成 |\n|---|---|---|\n| 以「不存在」开头的那条 | 「不存在」 | 删掉 |\n```\n'
  expect_build_ok
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
