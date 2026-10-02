#!/usr/bin/env bash
# 安装器用到的脚本的测试：plugins/setup-agent/scripts/ 下的三个渲染脚本，
# 以及片段 tools/installer/fragments/project-root.md 里那行切到仓库根目录的 shell。
#   bash tools/tests/scripts/run.sh [-v] [<用例名>...]
# 环境变量 SCRIPTS_DIR 可指向另一份 scripts 目录（如故意改坏的副本），默认测仓库里的那份。
#
# 命名：codex_* 测 render-codex-agent.py，rules_* 测 render-subagent-rules.py，
# style_* 测 render-report-style.py，root_* 测 project-root。
# 渲染脚本报错须是「<脚本名>: <信息>」、退出码 1、不带 traceback；参数错误由 argparse 以退出码 2 拒绝。

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)/lib/common.sh"

SCRIPTS=${SCRIPTS_DIR:-$REPO_ROOT/plugins/setup-agent/scripts}
SCRIPTS=$(cd "$SCRIPTS" && pwd -P)
RCA=$SCRIPTS/render-codex-agent.py
RSR=$SCRIPTS/render-subagent-rules.py
RRS=$SCRIPTS/render-report-style.py
for f in "$RCA" "$RSR" "$RRS"; do [ -f "$f" ] || die "找不到渲染脚本：$f"; done
AGENT_SKILLS=$REPO_ROOT/plugins/setup-agent/skills
RULES_TPL=$AGENT_SKILLS/subagents/template/rules.md
STYLE_TPL=$AGENT_SKILLS/report-style/template/output-styles/concise-plus.md
# 片段开头可以有只给维护者看的说明块（首行恰为 <!--，到恰为 --> 的行为止，其后的一个空行一并去掉），
# 与 build.py 读片段时一样去掉，剩下的才是装进生成物的命令。
ROOT_CMD=$(awk 'NR == 1 && $0 == "<!--" { skip = 1; next } skip == 1 { if ($0 == "-->") skip = 2; next } skip == 2 && $0 == "" { skip = 0; next } { skip = 0; print }' \
  "$REPO_ROOT/tools/installer/fragments/project-root.md")

SNAP_BEFORE=$(repo_snapshot)
make_tmp

# ---------------------------------------------------------------------------
# 夹具与小工具

put() { # put <文件> <行>...
  mkdir -p "$(dirname "$1")"
  printf '%s\n' "${@:2}" >"$1"
}

# 九个子代理模板，复制进 $T/agents 统一取用，免得测试改到仓库里的模板。
mkdir -p "$T/agents"
cp "$AGENT_SKILLS"/*/template/agents/*.md "$T/agents/"
AGENT_NAMES=$(cd "$T/agents" && ls *.md | sed 's/\.md$//' | tr '\n' ' ')

# 在 CASE_DIR 下建一个只含给定子代理的模板目录与输出目录：agents_fixture <名>...
agents_fixture() {
  SRC=$CASE_DIR/src
  OUTD=$CASE_DIR/out
  mkdir -p "$SRC" "$OUTD"
  local n
  for n in "$@"; do cp "$T/agents/$n.md" "$SRC/"; done
}

# 渲染脚本报错的统一格式：退出码 1、以脚本名开头、没有 traceback。
expect_script_error() { # expect_script_error <脚本名> <片段>...
  local prog=$1 s
  shift
  expect_rc 1 "$prog"
  expect_out "$prog: " "$prog"
  expect_not_out "Traceback" "$prog"
  for s in "$@"; do expect_out "$s" "$prog"; done
}

# 目录里所有文件（含隐藏文件、软链本身）的清单与内容校验和，用来断言「一个都没动」。
dir_state() {
  (cd "$1" && find . -mindepth 1 | LC_ALL=C sort | while IFS= read -r f; do
    if [ -L "$f" ]; then
      printf 'L %s -> %s\n' "$f" "$(readlink "$f")"
    elif [ -d "$f" ]; then
      printf 'D %s\n' "$f"
    else
      printf 'F %s %s %s\n' "$f" "$(cksum <"$f")" "$(stat -f '%Lp' "$f" 2>/dev/null || stat -c '%a' "$f")"
    fi
  done)
}

file_mode() { stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1"; }

# 带 monkeypatch 运行 render-codex-agent.py：patched <补丁 python 代码> <参数>...
# 补丁代码里 mod 是加载好的模块，可以替换 mod.os.replace 等；之后照常调用 main()。
patched() {
  local patch=$1
  shift
  # -B：加载模块时不在被测脚本旁边写 __pycache__（被测的可能是真实工作副本）
  python3 -B - "$RCA" "$patch" "$@" <<'EOF'
import importlib.util
import sys

path, patch = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("render_codex_agent", path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
exec(patch, {"mod": mod})
sys.argv = [path] + sys.argv[3:]
sys.exit(mod.main())
EOF
}

# ---------------------------------------------------------------------------
# render-codex-agent.py

register codex_render_all_templates
case_codex_render_all_templates() {
  agents_fixture $AGENT_NAMES
  # shellcheck disable=SC2086
  try python3 "$RCA" --output-dir "$OUTD" "$SRC"/*.md
  expect_rc 0 "渲染九个子代理"
  expect_eq "$(ls "$OUTD" | wc -l | tr -d ' ')" 9 "生成的 .toml 个数"
  try python3 - "$SRC" "$OUTD" <<'EOF'
import sys, tomllib
from pathlib import Path

src, out = Path(sys.argv[1]), Path(sys.argv[2])
for md in sorted(src.glob("*.md")):
    data = tomllib.loads((out / f"{md.stem}.toml").read_text(encoding="utf-8"))
    text = md.read_text(encoding="utf-8")
    lines = text.split("\n")
    closing = lines.index("---", 1)
    front = dict(l.split(":", 1) for l in lines[1:closing] if l.strip())
    body = "\n".join(lines[closing + 1:]).removeprefix("\n")
    assert data["name"] == md.stem, (md, data["name"])
    assert data["description"] == front["description"].strip(), md
    assert data["developer_instructions"] == body, f"{md}: developer_instructions 与模板正文不一致"
    assert data.get("model") and data.get("model_reasoning_effort"), f"{md}: 缺 model / model_reasoning_effort"
print("ok", len(list(src.glob("*.md"))))
EOF
  expect_rc 0 "tomllib 解析并与模板比对"
  expect_out "ok 9"
}

register codex_missing_args
case_codex_missing_args() {
  agents_fixture mechanical
  try python3 "$RCA"
  expect_rc 2 "不带参数"
  try python3 "$RCA" "$SRC/mechanical.md"
  expect_rc 2 "缺 --output-dir"
  try python3 "$RCA" --output-dir "$OUTD"
  expect_rc 2 "缺模板"
  expect_eq "$(ls -A "$OUTD")" "" "参数错误时不写文件"
}

register codex_template_missing
case_codex_template_missing() {
  agents_fixture mechanical
  try python3 "$RCA" --output-dir "$OUTD" "$SRC/mechanical.md" "$SRC/nope.md"
  expect_script_error render-codex-agent.py "nope.md"
  expect_eq "$(ls -A "$OUTD")" "" "模板缺失时一个都不写"
}

register codex_output_dir_missing
case_codex_output_dir_missing() {
  agents_fixture mechanical
  try python3 "$RCA" --output-dir "$CASE_DIR/no-such" "$SRC/mechanical.md"
  expect_script_error render-codex-agent.py "输出目录须是已存在的目录"
}

register codex_unknown_agent
case_codex_unknown_agent() {
  agents_fixture
  put "$SRC/stranger.md" --- "name: stranger" "description: 没有 Codex 配置" --- "" "正文"
  try python3 "$RCA" --output-dir "$OUTD" "$SRC/stranger.md"
  expect_script_error render-codex-agent.py "CODEX_AGENT_CONFIGURATION 里没有 stranger"
}

register codex_name_mismatch
case_codex_name_mismatch() {
  agents_fixture
  put "$SRC/mechanical.md" --- "name: implement" "description: 名字与文件名不符" --- "" "正文"
  try python3 "$RCA" --output-dir "$OUTD" "$SRC/mechanical.md"
  expect_script_error render-codex-agent.py "须与文件名 'mechanical' 一致"
}

register codex_non_utf8
case_codex_non_utf8() {
  agents_fixture
  printf -- '---\nname: mechanical\ndescription: \xff\xfe\n---\n' >"$SRC/mechanical.md"
  try python3 "$RCA" --output-dir "$OUTD" "$SRC/mechanical.md"
  expect_script_error render-codex-agent.py
  expect_eq "$(ls -A "$OUTD")" "" "非 UTF-8 时不写文件"
}

register codex_bad_frontmatter
case_codex_bad_frontmatter() {
  agents_fixture
  local pair
  for pair in \
    "第一行必须是 frontmatter 的 ---|name: mechanical" \
    "frontmatter 没有闭合的 ---|---|name: mechanical|description: x" \
    "frontmatter 缺少 description|---|name: mechanical|---" \
    "frontmatter 缺少 name|---|description: x|---" \
    "frontmatter 里有无法解析的行|---|name: mechanical|description: x|这一行没有冒号|---" \
    "frontmatter 缺少 name|---|name:|description: x|---"; do
    printf '%s\n' "${pair#*|}" | tr '|' '\n' >"$SRC/mechanical.md"
    try python3 "$RCA" --output-dir "$OUTD" "$SRC/mechanical.md"
    expect_script_error render-codex-agent.py "${pair%%|*}"
  done
  : >"$SRC/mechanical.md"
  try python3 "$RCA" --output-dir "$OUTD" "$SRC/mechanical.md"
  expect_script_error render-codex-agent.py "第一行必须是 frontmatter 的 ---"
  expect_eq "$(ls -A "$OUTD")" "" "坏 frontmatter 时不写文件"
}

register codex_instructions_with_triple_quotes
case_codex_instructions_with_triple_quotes() {
  agents_fixture
  put "$SRC/mechanical.md" --- "name: mechanical" 'description: 含 "引号" 与反斜杠 \ 的描述' --- "" "正文里有 ''' 三个单引号" '与 \n 反斜杠'
  try python3 "$RCA" --output-dir "$OUTD" "$SRC/mechanical.md"
  expect_rc 0 "正文含 '''"
  try python3 -c 'import sys, tomllib
d = tomllib.load(open(sys.argv[1], "rb"))
assert d["description"] == "含 \"引号\" 与反斜杠 \\ 的描述", d["description"]
assert d["developer_instructions"] == "正文里有 '"'''"' 三个单引号\n与 \\n 反斜杠\n", repr(d["developer_instructions"])' "$OUTD/mechanical.toml"
  expect_rc 0 "tomllib 解析结果与原文一致"
}

register codex_duplicate_stem
case_codex_duplicate_stem() {
  agents_fixture mechanical
  mkdir -p "$SRC/other"
  cp "$SRC/mechanical.md" "$SRC/other/"
  try python3 "$RCA" --output-dir "$OUTD" "$SRC/mechanical.md" "$SRC/other/mechanical.md"
  expect_script_error render-codex-agent.py "多个模板对应同一个输出文件名"
}

register codex_existing_target_rejected
case_codex_existing_target_rejected() {
  agents_fixture mechanical implement
  put "$OUTD/implement.toml" "旧内容"
  local before
  before=$(dir_state "$OUTD")
  try python3 "$RCA" --output-dir "$OUTD" "$SRC/mechanical.md" "$SRC/implement.md"
  expect_script_error render-codex-agent.py "目标已存在，拒绝覆盖" "implement.toml"
  expect_eq "$(dir_state "$OUTD")" "$before" "整批拒绝：没有新建 mechanical.toml，旧文件不变"
}

register codex_existing_symlink_rejected
case_codex_existing_symlink_rejected() {
  agents_fixture mechanical implement
  ln -s "$CASE_DIR/nowhere.toml" "$OUTD/implement.toml"
  local before
  before=$(dir_state "$OUTD")
  try python3 "$RCA" --output-dir "$OUTD" "$SRC/mechanical.md" "$SRC/implement.md"
  expect_script_error render-codex-agent.py "目标已存在，拒绝覆盖"
  expect_eq "$(dir_state "$OUTD")" "$before" "悬空软链也算已存在，整批拒绝"
  [ ! -e "$CASE_DIR/nowhere.toml" ] || fail "不应写穿悬空软链"
}

register codex_default_render_failure_writes_nothing
case_codex_default_render_failure_writes_nothing() {
  agents_fixture mechanical implement
  put "$SRC/implement.md" "坏模板"
  try python3 "$RCA" --output-dir "$OUTD" "$SRC/mechanical.md" "$SRC/implement.md"
  expect_script_error render-codex-agent.py "第一行必须是 frontmatter 的 ---"
  expect_eq "$(ls -A "$OUTD")" "" "第二个渲染失败时第一个也不写"
}

register codex_default_write_failure_cleanup
case_codex_default_write_failure_cleanup() {
  agents_fixture mechanical implement investigate
  try patched '
import pathlib
real = pathlib.Path.open
calls = []
def fake(self, mode="r", *a, **k):
    if mode == "x":
        calls.append(self)
        if len(calls) == 2:
            raise OSError("模拟写入失败")
    return real(self, mode, *a, **k)
pathlib.Path.open = fake
' --output-dir "$OUTD" "$SRC/mechanical.md" "$SRC/implement.md" "$SRC/investigate.md"
  expect_script_error render-codex-agent.py "模拟写入失败"
  expect_eq "$(ls -A "$OUTD")" "" "写到一半失败时删掉本次已建的文件"
}

register codex_replace_regular_keeps_mode
case_codex_replace_regular_keeps_mode() {
  agents_fixture mechanical implement
  put "$OUTD/mechanical.toml" "旧内容"
  chmod 640 "$OUTD/mechanical.toml"
  try python3 "$RCA" --replace --output-dir "$OUTD" "$SRC/mechanical.md" "$SRC/implement.md"
  expect_rc 0 "--replace 普通文件"
  expect_eq "$(file_mode "$OUTD/mechanical.toml")" 640 "替换后保留原权限"
  expect_eq "$(head -n 1 "$OUTD/mechanical.toml")" 'name = "mechanical"' "替换后的内容"
  expect_eq "$(file_mode "$OUTD/implement.toml")" "$(umask_mode)" "新建的文件按 umask 取权限"
  expect_eq "$(ls -A "$OUTD" | tr '\n' ' ')" "implement.toml mechanical.toml " "没有临时文件残留"
  # 与默认模式的输出逐字一致
  mkdir "$CASE_DIR/fresh"
  try python3 "$RCA" --output-dir "$CASE_DIR/fresh" "$SRC/mechanical.md"
  cmp -s "$CASE_DIR/fresh/mechanical.toml" "$OUTD/mechanical.toml" || fail "--replace 与默认模式的输出应一致"
}
umask_mode() { printf '%o\n' $((0666 & ~0$(umask))); }

register codex_replace_rejects_unsafe
case_codex_replace_rejects_unsafe() {
  agents_fixture mechanical implement
  local kind before
  for kind in symlink dangling directory; do
    rm -rf "$OUTD" "$CASE_DIR/real.toml"
    mkdir -p "$OUTD"
    put "$OUTD/mechanical.toml" "旧内容"
    case $kind in
      symlink) put "$CASE_DIR/real.toml" "链向的那份"; ln -s "$CASE_DIR/real.toml" "$OUTD/implement.toml" ;;
      dangling) ln -s "$CASE_DIR/real.toml" "$OUTD/implement.toml" ;;
      directory) mkdir "$OUTD/implement.toml" ;;
    esac
    before=$(dir_state "$CASE_DIR")
    try python3 "$RCA" --replace --output-dir "$OUTD" "$SRC/mechanical.md" "$SRC/implement.md"
    expect_script_error render-codex-agent.py "目标是软链或不是普通文件，拒绝替换"
    expect_eq "$(dir_state "$CASE_DIR")" "$before" "${kind}：整批拒绝，普通文件也不替换"
  done
}

register codex_replace_render_failure_atomic
case_codex_replace_render_failure_atomic() {
  agents_fixture mechanical implement investigate
  put "$SRC/implement.md" --- "name: implement" ---
  put "$OUTD/mechanical.toml" "旧 mechanical"
  put "$OUTD/implement.toml" "旧 implement"
  put "$OUTD/investigate.toml" "旧 investigate"
  local before
  before=$(dir_state "$OUTD")
  try python3 "$RCA" --replace --output-dir "$OUTD" "$SRC/mechanical.md" "$SRC/implement.md" "$SRC/investigate.md"
  expect_script_error render-codex-agent.py "frontmatter 缺少 description"
  expect_eq "$(dir_state "$OUTD")" "$before" "第二个渲染失败：第一个旧文件未被替换，且没有 .tmp 残留"
}

register codex_replace_tmp_write_failure
case_codex_replace_tmp_write_failure() {
  agents_fixture mechanical implement investigate
  put "$OUTD/mechanical.toml" "旧 mechanical"
  put "$OUTD/implement.toml" "旧 implement"
  local before
  before=$(dir_state "$OUTD")
  try patched '
real = mod.os.fdopen
calls = []
def fake(*a, **k):
    calls.append(1)
    if len(calls) == 2:
        raise OSError("模拟临时文件写入失败")
    return real(*a, **k)
mod.os.fdopen = fake
' --replace --output-dir "$OUTD" "$SRC/mechanical.md" "$SRC/implement.md" "$SRC/investigate.md"
  expect_script_error render-codex-agent.py "模拟临时文件写入失败"
  expect_eq "$(dir_state "$OUTD")" "$before" "写临时文件失败：目标一个都不动，临时文件全部删掉"
}

register codex_replace_rename_failure
case_codex_replace_rename_failure() {
  agents_fixture mechanical implement investigate
  put "$OUTD/mechanical.toml" "旧 mechanical"
  put "$OUTD/implement.toml" "旧 implement"
  put "$OUTD/investigate.toml" "旧 investigate"
  try patched '
real = mod.os.replace
calls = []
def fake(src, dst):
    calls.append(dst)
    if len(calls) == 2:
        raise OSError("模拟改名失败")
    return real(src, dst)
mod.os.replace = fake
' --replace --output-dir "$OUTD" "$SRC/mechanical.md" "$SRC/implement.md" "$SRC/investigate.md"
  expect_script_error render-codex-agent.py "模拟改名失败"
  expect_eq "$(head -n 1 "$OUTD/mechanical.toml")" 'name = "mechanical"' "已改名的第一个不回滚"
  expect_eq "$(cat "$OUTD/implement.toml")" "旧 implement" "改名失败的那个保持旧内容"
  expect_eq "$(cat "$OUTD/investigate.toml")" "旧 investigate" "其后的保持旧内容"
  expect_eq "$(ls -A "$OUTD" | tr '\n' ' ')" "implement.toml investigate.toml mechanical.toml " "未改名的临时文件已清理"
}

register codex_symlinked_output_dir_allowed
case_codex_symlinked_output_dir_allowed() {
  agents_fixture mechanical
  mkdir -p "$CASE_DIR/real-dir"
  rmdir "$OUTD"
  ln -s "$CASE_DIR/real-dir" "$OUTD"
  try python3 "$RCA" --output-dir "$OUTD" "$SRC/mechanical.md"
  expect_rc 0 "输出目录是软链（默认模式）"
  [ -f "$CASE_DIR/real-dir/mechanical.toml" ] && [ ! -L "$CASE_DIR/real-dir/mechanical.toml" ] || fail "应写进软链指向的目录"
  try python3 "$RCA" --replace --output-dir "$OUTD" "$SRC/mechanical.md"
  expect_rc 0 "输出目录是软链（--replace）"
  [ -L "$OUTD" ] || fail "输出目录的软链应保持不变"
  expect_eq "$(ls -A "$CASE_DIR/real-dir")" "mechanical.toml" "没有临时文件残留"
}

# ---------------------------------------------------------------------------
# render-subagent-rules.py

register rules_all_combinations
case_rules_all_combinations() {
  local host scope want other
  for host in claude codex; do
    case $host in
      claude) want="### Claude Code 模型配置"; other="### Codex 模型选择" ;;
      codex) want="### Codex 模型选择"; other="### Claude Code 模型配置" ;;
    esac
    for scope in project user; do
      try python3 "$RSR" --host "$host" --scope "$scope" "$RULES_TPL"
      expect_rc 0 "$host / $scope"
      printf '%s' "$OUT" >"$CASE_DIR/$host-$scope.md"
      expect_out "$want" "$host / $scope"
      expect_not_out "$other" "$host / $scope"
      expect_not_out "{{" "$host / $scope"
      expect_not_out "}}" "$host / $scope"
      if [ "$scope" = user ]; then
        expect_eq "$(head -n 1 "$CASE_DIR/$host-$scope.md")" "# 全局规则" "$host / user 的首行"
      else
        grep -qx '# 全局规则' "$CASE_DIR/$host-$scope.md" && fail "$host / project 不应含用户级标题「# 全局规则」"
        expect_not_out "与项目自己的指令文件冲突时，以项目的为准。" "$host / project"
      fi
    done
    # project 的输出就是 user 的输出去掉开头的用户级标题与首句
    try python3 -c 'import sys
u, p = (open(f, encoding="utf-8").read() for f in sys.argv[1:3])
head = "# 全局规则\n\n与项目自己的指令文件冲突时，以项目的为准。\n\n"
assert u.startswith(head) and u[len(head):] == p' "$CASE_DIR/$host-user.md" "$CASE_DIR/$host-project.md"
    expect_rc 0 "${host}：project = user 去掉用户级开头"
  done
}

register rules_missing_args
case_rules_missing_args() {
  try python3 "$RSR" --scope project "$RULES_TPL"
  expect_rc 2 "缺 --host"
  try python3 "$RSR" --host claude "$RULES_TPL"
  expect_rc 2 "缺 --scope"
  try python3 "$RSR" --host claude --scope project
  expect_rc 2 "缺模板"
  try python3 "$RSR" --host gemini --scope project "$RULES_TPL"
  expect_rc 2 "未知宿主"
  try python3 "$RSR" --host claude --scope global "$RULES_TPL"
  expect_rc 2 "未知作用域"
}

register rules_template_errors
case_rules_template_errors() {
  try python3 "$RSR" --host claude --scope user "$CASE_DIR/nope.md"
  expect_script_error render-subagent-rules.py "nope.md"
  sed 's/{{HOST_AGENT_CONFIGURATION}}//' "$RULES_TPL" >"$CASE_DIR/no-placeholder.md"
  try python3 "$RSR" --host claude --scope user "$CASE_DIR/no-placeholder.md"
  expect_script_error render-subagent-rules.py "须有且只有一个 {{HOST_AGENT_CONFIGURATION}} 占位符"
  { cat "$RULES_TPL"; echo "{{HOST_AGENT_CONFIGURATION}}"; } >"$CASE_DIR/two-placeholders.md"
  try python3 "$RSR" --host codex --scope project "$CASE_DIR/two-placeholders.md"
  expect_script_error render-subagent-rules.py "须有且只有一个"
  sed '1s/.*/# 规则/' "$RULES_TPL" >"$CASE_DIR/other-header.md"
  try python3 "$RSR" --host claude --scope project "$CASE_DIR/other-header.md"
  expect_script_error render-subagent-rules.py "开头的用户级标题与首句和渲染脚本里的不一致"
}

# ---------------------------------------------------------------------------
# render-report-style.py

register style_real_template
case_style_real_template() {
  try python3 "$RRS" "$STYLE_TPL"
  expect_rc 0 "渲染 concise-plus.md"
  printf '%s' "$OUT" >"$CASE_DIR/got.md"
  # 期望值另行推出：节标题取 frontmatter 的 name，空一行，正文（frontmatter 之后、去掉开头空行）里的 ATX 标题加两级。
  # 这份模板没有代码块，按行首 # 加两级即可；代码块的处理由 style_fences 覆盖。
  try python3 - "$STYLE_TPL" "$CASE_DIR/got.md" <<'EOF'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
lines = text.split("\n")
closing = lines.index("---", 1)
name = next(l.split(":", 1)[1].strip() for l in lines[1:closing] if l.startswith("name:"))
body = "\n".join(lines[closing + 1:]).lstrip("\n")
assert "```" not in body and "~~~" not in body, "模板里出现了代码块，改用 style_fences 的方式比对"
want = f"## 输出风格：{name}\n\n" + re.sub(r"^(#{1,6})(?=[ \t])", r"##\1", body, flags=re.M)
got = open(sys.argv[2], encoding="utf-8").read()
# $(...) 去掉了结尾换行，比较时一并去掉
assert got == want.rstrip("\n"), "输出与约定不一致"
assert got.startswith("## 输出风格：Concise+\n\n"), got[:40]
assert "\n### 只给结果\n" in got
EOF
  expect_rc 0 "与约定一致"
}

register style_fences
case_style_fences() {
  put "$CASE_DIR/in.md" --- "name: 测试风格" "description: x" --- "" \
    "开头一段" "" "# 一级" "## 二级" " # 缩进一格" "   ## 缩进三格" "    # 缩进四格不是标题" "#没有空格不是标题" $'#\t制表符也算' "" \
    '```' "# 代码块里" '~~~' "# ~~~ 不收 \`\`\` 块" '```' "" \
    '~~~~' '```' "# 代码块里" '~~~' "# 短的 ~~~ 不收 ~~~~ 块" '~~~~' "" \
    '  ```bash' '  # 缩进的代码块里' '  ```' "" \
    '``` 不是' "# 这行在块里，因为上一行带了文字的 \`\`\` 只是开头" '```' "" \
    "# 结尾"
  put "$CASE_DIR/want.md" "## 输出风格：测试风格" "" \
    "开头一段" "" "### 一级" "#### 二级" " ### 缩进一格" "   #### 缩进三格" "    # 缩进四格不是标题" "#没有空格不是标题" $'###\t制表符也算' "" \
    '```' "# 代码块里" '~~~' "# ~~~ 不收 \`\`\` 块" '```' "" \
    '~~~~' '```' "# 代码块里" '~~~' "# 短的 ~~~ 不收 ~~~~ 块" '~~~~' "" \
    '  ```bash' '  # 缩进的代码块里' '  ```' "" \
    '``` 不是' "# 这行在块里，因为上一行带了文字的 \`\`\` 只是开头" '```' "" \
    "### 结尾"
  try python3 "$RRS" "$CASE_DIR/in.md"
  expect_rc 0 "带代码块的模板"
  python3 "$RRS" "$CASE_DIR/in.md" >"$CASE_DIR/got.md"
  diff "$CASE_DIR/want.md" "$CASE_DIR/got.md" >"$CASE_DIR/diff" || fail "输出与期望不符：$(tr '\n' '|' <"$CASE_DIR/diff")"
}

register style_errors
case_style_errors() {
  put "$CASE_DIR/unclosed-fence.md" --- "name: x" --- "" "# 标题" '```' "# 块里"
  try python3 "$RRS" "$CASE_DIR/unclosed-fence.md"
  expect_script_error render-report-style.py "代码块围栏 \`\`\` 到结尾都没有闭合"
  put "$CASE_DIR/unclosed-tilde.md" --- "name: x" --- "" '~~~' '```'
  try python3 "$RRS" "$CASE_DIR/unclosed-tilde.md"
  expect_script_error render-report-style.py "代码块围栏 ~~~ 到结尾都没有闭合"
  put "$CASE_DIR/no-front.md" "# 标题" "正文"
  try python3 "$RRS" "$CASE_DIR/no-front.md"
  expect_script_error render-report-style.py "第一行必须是 frontmatter 的 ---"
  put "$CASE_DIR/unclosed-front.md" --- "name: x" "# 标题"
  try python3 "$RRS" "$CASE_DIR/unclosed-front.md"
  expect_script_error render-report-style.py "frontmatter 没有闭合的 ---"
  put "$CASE_DIR/no-name.md" --- "description: x" --- "正文"
  try python3 "$RRS" "$CASE_DIR/no-name.md"
  expect_script_error render-report-style.py "须有且只有一个非空的 name"
  put "$CASE_DIR/two-names.md" --- "name: a" "name: b" --- "正文"
  try python3 "$RRS" "$CASE_DIR/two-names.md"
  expect_script_error render-report-style.py "须有且只有一个非空的 name"
  put "$CASE_DIR/too-deep.md" --- "name: x" --- "##### 五级"
  try python3 "$RRS" "$CASE_DIR/too-deep.md"
  expect_script_error render-report-style.py "标题下移后超过六级"
  try python3 "$RRS" "$CASE_DIR/nope.md"
  expect_script_error render-report-style.py "nope.md"
  try python3 "$RRS"
  expect_rc 2 "缺模板参数"
}

# ---------------------------------------------------------------------------
# project-root

# 系统里有的 shell 都测；没有的跳过并在用例输出里注明。
ROOT_SHELLS=()
for sh in bash zsh sh dash; do
  if command -v "$sh" >/dev/null 2>&1; then
    ROOT_SHELLS+=("$sh")
  else
    echo "[scripts] 跳过 project-root 在 $sh 下的测试：系统里没有 $sh" >&2
  fi
done

# 在 <目录> 下用每个 shell 执行片段里的命令，其后追加记录 pwd 与 touch 标记文件：
#   root_run <目录> <期望：根目录物理路径，或 fail>
root_run() {
  local dir=$1 want=$2 sh flag marker got
  for sh in "${ROOT_SHELLS[@]}"; do
    marker=$CASE_DIR/marker-$sh
    got=$CASE_DIR/pwd-$sh
    rm -f "$marker" "$got"
    flag=
    [ "$sh" != zsh ] || flag=-f
    try run_at "$dir" "$sh" $flag -c "$ROOT_CMD
pwd -P >\"$got\"
touch \"$marker\""
    if [ "$want" = fail ]; then
      expect_nonzero "${sh}：$dir"
      [ ! -e "$marker" ] || fail "${sh}：$dir 下片段失败后，后续命令不应执行"
    else
      expect_rc 0 "${sh}：$dir"
      [ -e "$marker" ] || fail "${sh}：$dir 下后续命令应执行"
      expect_eq "$(cat "$got")" "$want" "${sh}：$dir 下切到的目录"
    fi
  done
}

new_repo() { # new_repo <目录>：建一个有一个提交的仓库
  mkdir -p "$1"
  git -C "$1" init -q
  put "$1/a/b/file" x
  git -C "$1" add -A
  git -C "$1" commit -q -m init
}

phys() { (cd "$1" && pwd -P); }

register root_shells_available
case_root_shells_available() {
  echo "测试的 shell：${ROOT_SHELLS[*]}"
  [ ${#ROOT_SHELLS[@]} -gt 0 ] || fail "一个可用的 shell 都没有"
  case " ${ROOT_SHELLS[*]} " in *" bash "*) ;; *) fail "至少要有 bash" ;; esac
  expect_eq "$(printf '%s\n' "$ROOT_CMD" | wc -l | tr -d ' ')" 1 "project-root 片段应只有一行"
}

register root_not_in_repo
case_root_not_in_repo() {
  mkdir -p "$CASE_DIR/plain/sub"
  root_run "$CASE_DIR/plain/sub" fail
}

register root_repo_root_and_subdir
case_root_repo_root_and_subdir() {
  new_repo "$CASE_DIR/r"
  root_run "$CASE_DIR/r" "$(phys "$CASE_DIR/r")"
  root_run "$CASE_DIR/r/a/b" "$(phys "$CASE_DIR/r")"
}

register root_path_with_spaces
case_root_path_with_spaces() {
  new_repo "$CASE_DIR/with space/my repo"
  root_run "$CASE_DIR/with space/my repo/a" "$(phys "$CASE_DIR/with space/my repo")"
}

register root_linked_worktree
case_root_linked_worktree() {
  new_repo "$CASE_DIR/r"
  git -C "$CASE_DIR/r" worktree add -q -b wt "$CASE_DIR/r/.worktrees/x"
  root_run "$CASE_DIR/r/.worktrees/x/a/b" "$(phys "$CASE_DIR/r/.worktrees/x")"
  root_run "$CASE_DIR/r/.worktrees/x" "$(phys "$CASE_DIR/r/.worktrees/x")"
}

register root_bare_repo
case_root_bare_repo() {
  mkdir -p "$CASE_DIR/bare.git"
  git -C "$CASE_DIR/bare.git" init -q --bare
  root_run "$CASE_DIR/bare.git" fail
  root_run "$CASE_DIR/bare.git/refs" fail
}

register root_inside_git_dir
case_root_inside_git_dir() {
  new_repo "$CASE_DIR/r"
  root_run "$CASE_DIR/r/.git" fail
  root_run "$CASE_DIR/r/.git/refs" fail
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
