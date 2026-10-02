#!/usr/bin/env bash
# plugin manifest 与 marketplace 的校验（check.py）的测试，并用它检查真实仓库的当前状态。
#   bash tools/tests/manifest/run.sh [-v] [<用例名>...]
# 环境变量 MANIFEST_CHECK 可指向另一份 check.py（如删掉某项校验的副本），默认测本目录的那份。
#
# 夹具：把真实仓库的 plugins/ 与两个 marketplace 复制进 T，提交并推到 T 里的 bare remote，
# 使 origin/main 等于复制时的状态（即「已发布」）；用例在夹具副本上施加改动后运行 check.py。
# 命名：baseline_* 未改动的副本，bad_* 应报 FAIL，allow_* 应通过，skip_* 应报 SKIP，repo_* 真实仓库。

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)/lib/common.sh"

CHECK=${MANIFEST_CHECK:-$TESTS_ROOT/manifest/check.py}
CHECK=$(cd "$(dirname "$CHECK")" && pwd -P)/$(basename "$CHECK")
[ -f "$CHECK" ] || die "找不到 check.py：$CHECK"

SNAP_BEFORE=$(repo_snapshot)
make_tmp

# ---------------------------------------------------------------------------
# 夹具与小工具

build_base() {
  local base=$T/base
  mkdir -p "$base/.claude-plugin" "$base/.agents/plugins"
  cp -R "$REPO_ROOT/plugins" "$base/plugins"
  find "$base/plugins" -name __pycache__ -type d -prune -exec rm -rf {} +
  cp "$REPO_ROOT/.claude-plugin/marketplace.json" "$base/.claude-plugin/"
  cp "$REPO_ROOT/.agents/plugins/marketplace.json" "$base/.agents/plugins/"
  git -C "$base" init -q
  git -C "$base" add -A
  git -C "$base" commit -q -m base
  git -C "$T" init -q --bare "$T/remote.git"
  git -C "$base" remote add origin "$T/remote.git"
  git -C "$base" push -q origin main
  git -C "$base" fetch -q origin
}
build_base

# 每个用例的副本 W（带 .git 与 origin/main），P 是其中的 plugins。
fixture() {
  W=$CASE_DIR/w
  cp -R "$T/base" "$W"
  P=$W/plugins
}

check() { try python3 -B "$CHECK" "$W"; }

# 应报 FAIL：退出码 1，输出含 `FAIL <项>` 与给定片段。
expect_check_fails() { # expect_check_fails <项> <片段>...
  local item=$1 s
  shift
  check
  expect_rc 1 "check.py"
  expect_out "FAIL $item" "check.py"
  for s in "$@"; do expect_out "$s" "check.py"; done
}

# 应通过：退出码 0，没有 FAIL。
expect_check_ok() {
  check
  expect_rc 0 "check.py"
  expect_not_out "FAIL" "check.py"
}

# 改 JSON：jset <文件> <python 表达式，d 为解析后的对象，就地修改>
jset() {
  python3 -B - "$1" "$2" <<'EOF'
import json, sys
path, expr = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as f:
    d = json.load(f)
exec(expr, {"d": d})
with open(path, "w", encoding="utf-8") as f:
    json.dump(d, f, ensure_ascii=False, indent=2)
    f.write("\n")
EOF
}

# 把一个 plugin 三份 manifest 的 version 都改成给定值：set_version <plugin> <version>
set_version() {
  local m
  for m in plugin.json .codex-plugin/plugin.json .claude-plugin/plugin.json; do
    jset "$P/$1/$m" "d['version'] = '$2'"
  done
}

# 一个 plugin 已发布的 version（夹具里 origin/main 上的）。
base_version() { python3 -B -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$T/base/plugins/$1/plugin.json"; }

# 版本号运算：bump <版本> patch|minor|major [<步数>]
bump() {
  python3 -B - "$@" <<'EOF'
import sys
v, part = sys.argv[1], sys.argv[2]
n = int(sys.argv[3]) if len(sys.argv) > 3 else 1
ma, mi, pa = map(int, v.split("."))
print({"patch": f"{ma}.{mi}.{pa + n}", "minor": f"{ma}.{mi + n}.0", "major": f"{ma + n}.0.0"}[part])
EOF
}

# 改 dev 的一个已跟踪文件（内容变化）。
touch_content() { echo "changed" >>"$P/dev/skills/discuss/SKILL.md"; }

# 一个用例一处改动：bad <用例名> <函数体>，体前自动 fixture。
bad() {
  register "$1"
  eval "case_$1() { fixture; $2; }"
}

# ---------------------------------------------------------------------------
# 基线

register baseline_clean
case_baseline_clean() {
  fixture
  expect_check_ok
  expect_out "ok version dev: 内容未变"
  expect_not_out "SKIP"
}

# 可重复运行：连跑两次输出相同，且 check.py 不改副本的 git 状态与文件。
register baseline_repeatable
case_baseline_repeatable() {
  fixture
  local before first
  before=$(git -C "$W" status --porcelain; git -C "$W" for-each-ref; find "$W" -path "$W/.git" -prune -o -type f -print | LC_ALL=C sort)
  check
  first=$OUT
  check
  expect_eq "$OUT" "$first" "两次运行的输出"
  expect_eq "$(git -C "$W" status --porcelain; git -C "$W" for-each-ref; find "$W" -path "$W/.git" -prune -o -type f -print | LC_ALL=C sort)" \
    "$before" "check.py 运行后副本状态"
}

# ---------------------------------------------------------------------------
# 三份 manifest 一致

bad bad_description_mismatch 'jset "$P/dev/.codex-plugin/plugin.json" "d[\"description\"] += \"！\""
  expect_check_fails "manifest dev" "description 不一致"'

bad bad_version_mismatch 'jset "$P/dev/.claude-plugin/plugin.json" "d[\"version\"] = \"9.9.9\""
  expect_check_fails "manifest dev" "version 不一致"'

bad bad_manifest_missing 'rm "$P/create/.codex-plugin/plugin.json"
  expect_check_fails "manifest create" "缺 .codex-plugin/plugin.json"'

bad bad_manifest_unparsable 'printf "{\n" >"$P/create/plugin.json"
  expect_check_fails "manifest create" "plugin.json 无法解析"'

# ---------------------------------------------------------------------------
# marketplace 登记

bad bad_claude_marketplace_missing 'jset "$W/.claude-plugin/marketplace.json" "d[\"plugins\"] = [p for p in d[\"plugins\"] if p[\"name\"] != \"setup-tools\"]"
  expect_check_fails "marketplace .claude-plugin/marketplace.json" "漏登记：setup-tools"'

bad bad_codex_marketplace_missing 'jset "$W/.agents/plugins/marketplace.json" "d[\"plugins\"] = [p for p in d[\"plugins\"] if p[\"name\"] != \"dev\"]"
  expect_check_fails "marketplace .agents/plugins/marketplace.json" "漏登记：dev"'

bad bad_marketplace_unregistered_plugin 'cp -R "$P/create" "$P/extra"
  expect_check_fails "marketplace .claude-plugin/marketplace.json" "漏登记：extra"
  expect_out "FAIL marketplace .agents/plugins/marketplace.json"'

bad bad_marketplace_extra_entry 'jset "$W/.agents/plugins/marketplace.json" "d[\"plugins\"].append(dict(d[\"plugins\"][0], name=\"ghost\", source={\"source\": \"local\", \"path\": \"./plugins/ghost\"}))"
  expect_check_fails "marketplace .agents/plugins/marketplace.json" "plugins/ 下没有的：ghost"'

bad bad_marketplace_duplicate 'jset "$W/.claude-plugin/marketplace.json" "d[\"plugins\"].append(d[\"plugins\"][0])"
  expect_check_fails "marketplace .claude-plugin/marketplace.json" "重复登记"'

bad bad_marketplace_wrong_source 'jset "$W/.claude-plugin/marketplace.json" "d[\"plugins\"][0][\"source\"] = \"./plugins/elsewhere\""
  expect_check_fails "marketplace .claude-plugin/marketplace.json" "source"'

bad bad_claude_marketplace_description 'jset "$W/.claude-plugin/marketplace.json" "[p.update(description=p[\"description\"] + \"。\") for p in d[\"plugins\"] if p[\"name\"] == \"create\"]"
  expect_check_fails "marketplace .claude-plugin/marketplace.json description" "create 的 description 与 manifest 不一致"'

# ---------------------------------------------------------------------------
# interface

bad bad_interface_missing 'jset "$P/setup-git/.codex-plugin/plugin.json" "del d[\"interface\"]"
  expect_check_fails "interface setup-git" "没有 interface"'

bad bad_interface_empty_text 'jset "$P/setup-git/.codex-plugin/plugin.json" "d[\"interface\"][\"longDescription\"] = \" \""
  expect_check_fails "interface setup-git" "longDescription"'

# ---------------------------------------------------------------------------
# 版本只升一次（相对 origin/main）

bad bad_content_changed_not_bumped 'touch_content
  expect_check_fails "version dev" "没有升"'

bad bad_untracked_file_not_bumped 'echo new >"$P/dev/skills/discuss/extra.md"
  expect_check_fails "version dev" "没有升"'

bad bad_bumped_twice 'touch_content
  set_version dev "$(bump "$(base_version dev)" patch 2)"
  expect_check_fails "version dev" "不是恰好升一级"'

bad bad_minor_without_patch_reset 'touch_content
  set_version dev "$(bump "$(base_version dev)" minor | sed "s/\\.0\$/.1/")"
  expect_check_fails "version dev" "不是恰好升一级"'

bad bad_major_without_reset 'touch_content
  set_version dev "$(bump "$(base_version dev)" major | sed "s/\\.0\\.0\$/.1.0/")"
  expect_check_fails "version dev" "不是恰好升一级"'

bad bad_downgrade 'touch_content
  set_version dev 0.0.1
  expect_check_fails "version dev" "不是恰好升一级"'

bad bad_bumped_without_change 'set_version dev "$(bump "$(base_version dev)" patch)"
  expect_check_fails "version dev" "没有变化"'

bad bad_manifest_field_changed_not_bumped 'jset "$P/dev/.codex-plugin/plugin.json" "d[\"interface\"][\"shortDescription\"] += \"！\""
  expect_check_fails "version dev" "没有升"'

bad bad_version_not_semver 'touch_content
  set_version dev "v1"
  expect_check_fails "version dev" "不是 X.Y.Z"'

bad allow_patch_bump 'touch_content
  set_version dev "$(bump "$(base_version dev)" patch)"
  expect_check_ok
  expect_out "ok version dev: $(base_version dev) → $(bump "$(base_version dev)" patch)"'

bad allow_minor_bump 'touch_content
  set_version dev "$(bump "$(base_version dev)" minor)"
  expect_check_ok'

bad allow_major_bump 'touch_content
  set_version dev "$(bump "$(base_version dev)" major)"
  expect_check_ok'

# 已提交但未推送的改动同样算内容变化。
register allow_committed_unpushed_bump
case_allow_committed_unpushed_bump() {
  fixture
  touch_content
  git -C "$W" commit -q -am "change dev"
  check
  expect_rc 1 "提交后仍未升版本"
  expect_out "FAIL version dev"
  set_version dev "$(bump "$(base_version dev)" patch)"
  git -C "$W" commit -q -am "bump dev"
  expect_check_ok
}

# origin/main 上没有的 plugin 视为未发布，不比版本，但其余项照查。
bad allow_new_plugin 'cp -R "$P/create" "$P/fresh"
  for m in plugin.json .codex-plugin/plugin.json .claude-plugin/plugin.json; do jset "$P/fresh/$m" "d[\"name\"] = \"fresh\""; done
  jset "$W/.claude-plugin/marketplace.json" "d[\"plugins\"].append(dict(d[\"plugins\"][1], name=\"fresh\", source=\"./plugins/fresh\"))"
  jset "$W/.agents/plugins/marketplace.json" "d[\"plugins\"].append(dict(d[\"plugins\"][1], name=\"fresh\", source={\"source\": \"local\", \"path\": \"./plugins/fresh\"}))"
  expect_check_ok
  expect_out "ok version fresh: origin/main 上没有"'

register skip_no_origin_main
case_skip_no_origin_main() {
  fixture
  git -C "$W" remote remove origin
  touch_content # 没有基准时即使内容变了没升也不报
  expect_check_ok
  expect_out "SKIP version: 本地没有 origin/main"
  expect_out "ok manifest dev"
}

register skip_not_a_repo
case_skip_not_a_repo() {
  fixture
  rm -rf "$W/.git"
  expect_check_ok
  expect_out "SKIP version"
}

# ---------------------------------------------------------------------------
# 真实仓库的当前状态（check.py 对它只做只读 git 查询；SKIP 时在套件末尾打印出来）

register repo_current_state
case_repo_current_state() {
  try python3 -B "$CHECK" "$REPO_ROOT"
  expect_rc 0 "真实仓库的 manifest 校验"
  case $OUT in
    *SKIP*) printf '%s\n' "$OUT" | grep '^SKIP' | sed 's/^/SKIP repo_current_state: /' >>"$T/.skips" ;;
  esac
}

# ---------------------------------------------------------------------------

set +e
run_cases "$@"
rc=$?
set -e
[ ! -f "$T/.skips" ] || cat "$T/.skips"

if compare_snapshots "$SNAP_BEFORE" "$(repo_snapshot)"; then
  echo "PASS repo_untouched"
else
  echo "FAIL repo_untouched: 真实仓库在运行前后不一致"
  rc=1
fi
exit "$rc"
