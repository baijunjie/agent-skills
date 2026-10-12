#!/usr/bin/env bash
# setup-tools:launchd 装出的 LaunchAgent 安装脚本（plugins/setup-tools/skills/launchd/template/launchd/）的测试。
#   bash tools/tests/launchd/run.sh [-v] [<用例名>...]
# 环境变量 LAUNCHD_TEMPLATE_DIR 可指向另一份 launchd 模板目录（如故意改坏的副本），默认测仓库里的那份。
#
# 绝不碰真实的 launchd 与 ~/Library/LaunchAgents：被测脚本一律经 env -i 运行，PATH 只含自建的 bin
# 目录——里面是必需工具的软链，外加一个只记录调用的假 launchctl；另一份 bin 不含 launchctl，测「没有
# launchctl 命令」。plist 目录每条用例各指向自己的 LAUNCHD_AGENT_DIR，HOME 也在临时根内。
# 两份 bin 建好后先核对：前者的 launchctl 是那个假脚本，后者没有 launchctl，任一不符整套不跑。
#
# 每个用例在自己的目录里放项目：<项目根>/scripts/launchd/ 下是模板的五个文件（即模板默认的深度），
# tasks.conf 界线行之后追加一个任务。

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)/lib/common.sh"

# LaunchAgent 只在 macOS 上成立：别的系统上 launchctl 与 plutil 都没有，整套跳过。
if [ "$(uname -s)" != Darwin ]; then
  echo "SKIP launchd: LaunchAgent 只在 macOS 上可测"
  exit 0
fi

LAUNCHD_SRC=${LAUNCHD_TEMPLATE_DIR:-$REPO_ROOT/plugins/setup-tools/skills/launchd/template/launchd}
LAUNCHD_SRC=$(cd "$LAUNCHD_SRC" && pwd -P)
for f in common.sh install.sh uninstall.sh status.sh tasks.conf; do
  [ -f "$LAUNCHD_SRC/$f" ] || die "找不到 launchd 模板文件：$LAUNCHD_SRC/$f"
done

SNAP_BEFORE=$(repo_snapshot)
make_tmp

# ---------------------------------------------------------------------------
# 自建 bin 与假 launchctl

BIN_NONE=$T/lbin-nolaunchctl
BIN_LC=$T/lbin
mkdir -p "$BIN_NONE" "$BIN_LC"
for tool in sh awk sed tr cksum cut find head wc basename dirname mkdir uname cat rm grep id sort tail mktemp mv plutil; do
  p=$(type -P "$tool") || die "找不到必需的工具：$tool"
  ln -s "$p" "$BIN_NONE/$tool"
  ln -s "$p" "$BIN_LC/$tool"
done
cat >"$BIN_LC/launchctl" <<'EOF'
#!/bin/sh
# 假 launchctl：已加载的标签存在 $FAKE_LOADED 文件里，每次调用记一行到 $FAKE_CALLS。
# 只支持 install.sh / uninstall.sh / status.sh 用到的 bootstrap、bootout、enable、list、print。
loaded=${FAKE_LOADED:?FAKE_LOADED 未设置}
printf '%s\n' "$*" >>"${FAKE_CALLS:?FAKE_CALLS 未设置}"
: >>"$loaded"
case "${1:-}" in
  bootstrap)
    [ -f "$3" ] || { echo "fake launchctl: 没有这个 plist $3" >&2; exit 1; }
    label=$(basename "$3" .plist)
    grep -qxF "$label" "$loaded" && { echo "fake launchctl: $label 已加载" >&2; exit 5; }
    printf '%s\n' "$label" >>"$loaded"
    ;;
  bootout)
    label=${2##*/}
    grep -qxF "$label" "$loaded" || { echo "fake launchctl: $label 没加载" >&2; exit 3; }
    grep -vxF "$label" "$loaded" >"$loaded.new" || true
    mv "$loaded.new" "$loaded"
    ;;
  enable) ;;
  list)
    while IFS= read -r l; do
      [ -n "$l" ] || continue
      printf -- '-\t0\t%s\n' "$l"
    done <"$loaded"
    ;;
  print)
    label=${2##*/}
    grep -qxF "$label" "$loaded" || exit 113
    printf '\truns = 3\n'
    ;;
  *) echo "fake launchctl: 不支持的参数 $*" >&2; exit 2 ;;
esac
EOF
chmod +x "$BIN_LC/launchctl"
# 安全核对：有 launchctl 的那份解析到的是假脚本，另一份解析不到 launchctl。
[ "$(env -i PATH="$BIN_LC" "$BIN_LC/sh" -c 'command -v launchctl')" = "$BIN_LC/launchctl" ] \
  || die "安全检查失败：自建 bin 里的 launchctl 不是假脚本"
[ ! -L "$BIN_LC/launchctl" ] || die "安全检查失败：假 launchctl 不能是软链"
if env -i PATH="$BIN_NONE" "$BIN_NONE/sh" -c 'command -v launchctl' >/dev/null 2>&1; then
  die "安全检查失败：不含 launchctl 的 bin 里解析到了 launchctl"
fi

# ---------------------------------------------------------------------------
# 夹具与小工具

agent_dir() { echo "$CASE_DIR/LaunchAgents"; }
loaded_file() { echo "$CASE_DIR/loaded"; }
calls_file() { echo "$CASE_DIR/calls"; }

# 运行被测脚本：launchd_sh [--nolaunchctl] [--env K=V]... <脚本路径> [参数]...
# 环境只有 PATH、HOME、TMPDIR、LC_ALL（默认 C）、plist 目录与假 launchctl 的两个文件，外加 --env 给的变量。
launchd_sh() {
  local bin=$BIN_LC envs=()
  while [ $# -gt 0 ]; do
    case $1 in
      --nolaunchctl) bin=$BIN_NONE ;;
      --env) envs+=("$2"); shift ;;
      *) break ;;
    esac
    shift
  done
  mkdir -p "$(agent_dir)"
  run_at "$CASE_DIR" env -i PATH="$bin" HOME="$HOME" TMPDIR="$CASE_DIR" LC_ALL=C \
    LAUNCHD_AGENT_DIR="$(agent_dir)" FAKE_LOADED="$(loaded_file)" FAKE_CALLS="$(calls_file)" \
    ${envs[@]+"${envs[@]}"} "$bin/sh" "$@"
}

# 建项目：new_project <项目根> [<脚本目录，相对项目根，默认 scripts>]，脚本目录写入 LD。
new_project() {
  local root=$1 sub=${2:-scripts}
  LD=$root/$sub/launchd
  mkdir -p "$LD"
  cp "$LAUNCHD_SRC/"* "$LD/"
  printf '%s\n' "测试任务 | */5 * * * * | echo hi" >>"$LD/tasks.conf"
}

phys() { (cd "$1" && pwd -P); }

# 某个前缀下已装的 plist 个数。
plist_count() { # plist_count <前缀>
  local n
  n=$(find "$(agent_dir)" -maxdepth 1 -name "$1.*.plist" -type f 2>/dev/null | wc -l)
  echo "$((n))"
}

# 已装 plist 的标签，按字母序一行一个。
plist_labels() {
  find "$(agent_dir)" -maxdepth 1 -name '*.plist' -type f 2>/dev/null \
    | sed -e 's#.*/##' -e 's/\.plist$//' | sort
}

# 某个 plist 里记着的项目根。
plist_owner_of() { # plist_owner_of <标签>
  sed -n 's|.*project: \(.*\) -->.*|\1|p' "$(agent_dir)/$1.plist" | head -n 1
}

# 假 launchctl 认为已加载的标签，按字母序一行一个。
loaded_labels() { sort "$(loaded_file)" 2>/dev/null || true; }

# dry-run 首行里的标签前缀。
dry_run_prefix() { # dry_run_prefix [launchd_sh 的选项]... <install.sh>
  local out
  out=$(launchd_sh "$@" --dry-run) || return 1
  printf '%s\n' "$out" | sed -n '1s/^标签前缀: //p'
}

# ---------------------------------------------------------------------------
# dry-run 与参数

register launchd_dry_run_does_not_write
case_launchd_dry_run_does_not_write() {
  new_project "$CASE_DIR/my-app"
  local root
  root=$(phys "$CASE_DIR/my-app")
  try launchd_sh "$LD/install.sh" --dry-run
  expect_rc 0 "dry-run"
  expect_out "标签前缀: local.my-app"
  expect_out "--- $(agent_dir)/local.my-app.1-task.plist ---"
  expect_out "<key>Label</key><string>local.my-app.1-task</string>"
  expect_out "<key>StartInterval</key><integer>300</integer>"
  expect_out "<string>{ echo hi ; } &gt;&gt; \"$root/logs/launchd/launchd.log\" 2&gt;&amp;1</string>"
  expect_out "<key>WorkingDirectory</key><string>$root</string>"
  expect_eq "$(plist_count local.my-app)" 0 "dry-run 不写 plist"
  expect_eq "$(loaded_labels)" "" "dry-run 不加载"
  [ ! -e "$(calls_file)" ] || fail "dry-run 不应调用 launchctl"
  [ ! -e "$root/logs" ] || fail "dry-run 不应建日志目录"
}

register launchd_dry_run_lists_prefix_without_tasks
case_launchd_dry_run_lists_prefix_without_tasks() {
  new_project "$CASE_DIR/my-app"
  # 任务清单清空（只留模板注释）：首行仍要给出标签前缀，装之前才核对得了撞不撞车
  sed -n '/^#/p' "$LD/tasks.conf" >"$LD/tasks.new"
  mv "$LD/tasks.new" "$LD/tasks.conf"
  try launchd_sh "$LD/install.sh" --dry-run
  expect_rc 0 "空清单 dry-run"
  expect_out "标签前缀: local.my-app"
  expect_not_out "<plist"
  try launchd_sh "$LD/install.sh"
  expect_rc 0 "空清单安装"
  expect_out "已安装 0 个 LaunchAgent"
  expect_eq "$(plist_count local.my-app)" 0 "没有任务就没有 plist"
}

register launchd_without_launchctl_command
case_launchd_without_launchctl_command() {
  new_project "$CASE_DIR/my-app"
  try launchd_sh --nolaunchctl "$LD/install.sh" --dry-run
  expect_rc 0 "没有 launchctl 时 dry-run"
  expect_out "标签前缀: local.my-app"
  try launchd_sh --nolaunchctl "$LD/install.sh"
  expect_rc 1 "没有 launchctl 时 install"
  expect_out "找不到 launchctl 命令"
  try launchd_sh --nolaunchctl "$LD/uninstall.sh"
  expect_rc 1 "没有 launchctl 时 uninstall"
  expect_out "找不到 launchctl 命令"
  try launchd_sh --nolaunchctl "$LD/status.sh"
  expect_rc 1 "没有 launchctl 时 status"
  expect_out "找不到 launchctl 命令"
  expect_eq "$(plist_count local.my-app)" 0 "不应写出 plist"
  [ ! -e "$CASE_DIR/my-app/logs" ] || fail "报错时不应建日志目录"
}

register launchd_unknown_argument
case_launchd_unknown_argument() {
  new_project "$CASE_DIR/my-app"
  try launchd_sh "$LD/install.sh" --force
  expect_rc 1 "未知参数"
  expect_out "未知参数: --force"
  expect_eq "$(plist_count local.my-app)" 0 "不应写出 plist"
  try launchd_sh "$LD/status.sh" abc
  expect_rc 1 "status 的参数不是数字"
  expect_out "日志行数要是个非负整数: abc"
}

register launchd_missing_tasks_file
case_launchd_missing_tasks_file() {
  new_project "$CASE_DIR/my-app"
  rm "$LD/tasks.conf"
  try launchd_sh "$LD/install.sh"
  expect_rc 1 "tasks.conf 缺失"
  expect_out "找不到任务清单"
  expect_eq "$(plist_count local.my-app)" 0 "不应写出 plist"
}

# ---------------------------------------------------------------------------
# 安装、重装、卸载

register launchd_install_and_reinstall_idempotent
case_launchd_install_and_reinstall_idempotent() {
  new_project "$CASE_DIR/my-app"
  printf '%s\n' "第二个任务 | 0 3 * * * | echo second" >>"$LD/tasks.conf"
  try launchd_sh "$LD/install.sh"
  expect_rc 0 "首次安装"
  expect_out "已安装 2 个 LaunchAgent（标签前缀 local.my-app）"
  expect_eq "$(plist_count local.my-app)" 2 "首次安装后的 plist 数"
  local labels
  labels=$(plist_labels)
  expect_eq "$labels" "$(loaded_labels)" "装出的 plist 都已加载"
  [ -d "$CASE_DIR/my-app/logs/launchd" ] || fail "应建日志目录"
  try launchd_sh "$LD/install.sh"
  expect_rc 0 "重装"
  expect_out "已卸载旧的 2 个 LaunchAgent"
  expect_eq "$(plist_count local.my-app)" 2 "重装后 plist 不翻倍"
  expect_eq "$(plist_labels)" "$labels" "重装后标签不变"
  expect_eq "$(loaded_labels)" "$labels" "重装后仍全部加载"
}

register launchd_install_updates_tasks
case_launchd_install_updates_tasks() {
  new_project "$CASE_DIR/my-app"
  printf '%s\n' "待删任务 | 0 3 * * * | echo second" >>"$LD/tasks.conf"
  try launchd_sh "$LD/install.sh"
  expect_rc 0 "首次安装"
  expect_eq "$(plist_count local.my-app)" 2 "两条任务"
  grep -vF "待删任务" "$LD/tasks.conf" >"$LD/tasks.new"
  mv "$LD/tasks.new" "$LD/tasks.conf"
  printf '%s\n' "新任务 | @daily | echo third" >>"$LD/tasks.conf"
  try launchd_sh "$LD/install.sh"
  expect_rc 0 "改清单后重装"
  expect_eq "$(plist_labels)" "local.my-app.1-task
local.my-app.2-task" "标签按新清单重编号"
  expect_eq "$(loaded_labels)" "$(plist_labels)" "加载的与装出的一致"
  grep -qF "echo third" "$(agent_dir)/local.my-app.2-task.plist" || fail "新任务应装上"
  grep -rqF "echo second" "$(agent_dir)" && fail "删掉的任务不应留在机器上"
  true
}

register launchd_uninstall_keeps_other_projects
case_launchd_uninstall_keeps_other_projects() {
  new_project "$CASE_DIR/alpha"
  local a=$LD
  new_project "$CASE_DIR/beta"
  local b=$LD
  try launchd_sh "$a/install.sh"
  expect_rc 0 "装 alpha"
  try launchd_sh "$b/install.sh"
  expect_rc 0 "装 beta"
  expect_eq "$(plist_count local.alpha)/$(plist_count local.beta)" 1/1 "两个项目各一个 plist"
  try launchd_sh "$a/uninstall.sh"
  expect_rc 0 "卸载 alpha"
  expect_out "已卸载 1 个 LaunchAgent（标签前缀 local.alpha）"
  expect_eq "$(plist_count local.alpha)/$(plist_count local.beta)" 0/1 "只删了 alpha 的"
  expect_eq "$(loaded_labels)" "local.beta.1-task" "beta 仍加载着"
  try launchd_sh "$a/uninstall.sh"
  expect_rc 0 "再卸载 alpha"
  expect_out "无需卸载"
  expect_eq "$(plist_count local.beta)" 1 "没有自己的 plist 时不动别人的"
}

# ---------------------------------------------------------------------------
# 前缀撞车与接管

# 撞车时 install、dry-run、uninstall 都报错退出 1，对方的 plist 不变。
expect_collision() { # expect_collision <install.sh 所在目录> <前缀> <对方项目根>
  local dir=$1 prefix=$2 owner=$3 before cmd
  before=$(plist_labels)
  for cmd in "install.sh" "install.sh --dry-run" "uninstall.sh"; do
    # shellcheck disable=SC2086
    try launchd_sh "$dir/"$cmd
    expect_rc 1 "撞车时 $cmd"
    expect_out "标签前缀 $prefix 已被 $owner 使用" "撞车时 $cmd"
    expect_eq "$(plist_labels)" "$before" "撞车时 $cmd 不动 plist"
  done
  expect_eq "$(plist_count "$prefix")" 1 "对方的 plist 仍在"
  expect_eq "$(plist_owner_of "$prefix.1-task")" "$owner" "plist 仍记着对方的项目根"
}

# 手写的 LaunchAgent 恰好用着同一前缀：install、dry-run、uninstall 都报错退出，那个 plist 一个字不动。
register launchd_foreign_plist_not_touched
case_launchd_foreign_plist_not_touched() {
  new_project "$CASE_DIR/my-app"
  mkdir -p "$(agent_dir)"
  cat >"$(agent_dir)/local.my-app.sync.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
  <key>Label</key><string>local.my-app.sync</string>
  <key>ProgramArguments</key><array><string>/bin/echo</string><string>mine</string></array>
  <key>StartInterval</key><integer>60</integer>
</dict></plist>
EOF
  local before cmd
  before=$(cksum <"$(agent_dir)/local.my-app.sync.plist")
  for cmd in "install.sh" "install.sh --dry-run" "uninstall.sh"; do
    # shellcheck disable=SC2086
    try launchd_sh "$LD/"$cmd
    expect_rc 1 "前缀被手写 plist 占着时 $cmd"
    expect_out "不是本安装器装的" "前缀被手写 plist 占着时 $cmd"
    expect_eq "$(cksum <"$(agent_dir)/local.my-app.sync.plist")" "$before" "$cmd 不应动手写的 plist"
  done
  expect_eq "$(plist_labels)" "local.my-app.sync" "没有装出自己的 plist"
  # 按报错改掉前缀后照常装，手写的那份仍在
  sed 's/^LABEL_PREFIX=\${LAUNCHD_LABEL_PREFIX:-\$(default_prefix)}$/LABEL_PREFIX=${LAUNCHD_LABEL_PREFIX:-local.my-app-tasks}/' \
    "$LD/common.sh" >"$LD/common.new"
  mv "$LD/common.new" "$LD/common.sh"
  grep -q 'local.my-app-tasks' "$LD/common.sh" || fail "没改到 common.sh 的 LABEL_PREFIX 默认值"
  try launchd_sh "$LD/install.sh"
  expect_rc 0 "改掉前缀后安装"
  expect_eq "$(plist_count local.my-app-tasks)" 1 "装出自己的 plist"
  expect_eq "$(cksum <"$(agent_dir)/local.my-app.sync.plist")" "$before" "手写的 plist 仍在"
}

register launchd_collision_same_name_other_path
case_launchd_collision_same_name_other_path() {
  new_project "$CASE_DIR/p1/my-app"
  local a=$LD
  new_project "$CASE_DIR/p2/my-app"
  try launchd_sh "$a/install.sh"
  expect_rc 0 "装 p1/my-app"
  expect_collision "$LD" local.my-app "$(phys "$CASE_DIR/p1/my-app")"
}

register launchd_collision_fixed_prefix_resolves
case_launchd_collision_fixed_prefix_resolves() {
  new_project "$CASE_DIR/p1/my-app"
  local a=$LD
  new_project "$CASE_DIR/p2/my-app"
  try launchd_sh "$a/install.sh"
  expect_rc 0 "装 p1/my-app"
  # 按 common.sh 的说明改成固定前缀后不再撞车
  sed 's/^LABEL_PREFIX=\${LAUNCHD_LABEL_PREFIX:-\$(default_prefix)}$/LABEL_PREFIX=${LAUNCHD_LABEL_PREFIX:-local.my-app-two}/' \
    "$LD/common.sh" >"$LD/common.new"
  mv "$LD/common.new" "$LD/common.sh"
  grep -q 'local.my-app-two' "$LD/common.sh" || fail "没改到 common.sh 的 LABEL_PREFIX 默认值"
  try launchd_sh "$LD/install.sh"
  expect_rc 0 "改成固定前缀后安装"
  expect_eq "$(plist_count local.my-app)/$(plist_count local.my-app-two)" 1/1 "两个项目各一个 plist"
}

register launchd_moved_project_takes_over
case_launchd_moved_project_takes_over() {
  new_project "$CASE_DIR/old/my-app"
  try launchd_sh "$LD/install.sh"
  expect_rc 0 "在旧位置安装"
  mkdir -p "$CASE_DIR/new"
  mv "$CASE_DIR/old/my-app" "$CASE_DIR/new/my-app"
  try launchd_sh "$CASE_DIR/new/my-app/scripts/launchd/install.sh"
  expect_rc 0 "搬走后在新位置安装"
  expect_eq "$(plist_count local.my-app)" 1 "只剩一个 plist"
  expect_eq "$(plist_owner_of local.my-app.1-task)" "$(phys "$CASE_DIR/new/my-app")" "plist 记着新位置"
}

register launchd_owner_scan_skips_node_modules
case_launchd_owner_scan_skips_node_modules() {
  new_project "$CASE_DIR/old/my-app"
  try launchd_sh "$LD/install.sh"
  expect_rc 0 "在旧位置安装"
  # 旧项目只剩 node_modules 里的一份 launchd/common.sh（依赖包带的），不算仍在用
  mkdir -p "$CASE_DIR/old/my-app/node_modules/pkg/launchd"
  mv "$CASE_DIR/old/my-app/scripts/launchd/common.sh" "$CASE_DIR/old/my-app/node_modules/pkg/launchd/"
  rm -rf "$CASE_DIR/old/my-app/scripts"
  new_project "$CASE_DIR/new/my-app"
  try launchd_sh "$LD/install.sh"
  expect_rc 0 "node_modules 里的 common.sh 不算"
  expect_eq "$(plist_owner_of local.my-app.1-task)" "$(phys "$CASE_DIR/new/my-app")" "plist 由新位置接管"
}

register launchd_deep_project_not_mistaken_as_moved
case_launchd_deep_project_not_mistaken_as_moved() {
  # 脚本放在项目根下第 6 层：按 common.sh 的说明把 PROJECT_ROOT 默认值的上溯层级改深
  new_project "$CASE_DIR/deep/my-app" "l1/l2/l3/l4/l5"
  local a=$LD
  sed 's#\$SCRIPT_DIR/\.\./\.\.#$SCRIPT_DIR/../../../../../..#' "$a/common.sh" >"$a/common.new"
  mv "$a/common.new" "$a/common.sh"
  grep -qF '$SCRIPT_DIR/../../../../../..' "$a/common.sh" || fail "没改到 PROJECT_ROOT 的上溯层级"
  try launchd_sh "$a/install.sh"
  expect_rc 0 "装深层项目"
  expect_eq "$(plist_owner_of local.my-app.1-task)" "$(phys "$CASE_DIR/deep/my-app")" "深层项目的项目根"
  new_project "$CASE_DIR/other/my-app"
  expect_collision "$LD" local.my-app "$(phys "$CASE_DIR/deep/my-app")"
}

# ---------------------------------------------------------------------------
# 前缀的计算

register launchd_prefix_ascii_names
case_launchd_prefix_ascii_names() {
  local pair name want got
  for pair in "my-app=local.my-app" "My.App2=local.my-app2" "a b=local.a-b" "x_9=local.x-9"; do
    name=${pair%%=*}
    want=${pair#*=}
    new_project "$CASE_DIR/$name"
    got=$(dry_run_prefix "$LD/install.sh")
    expect_eq "$got" "$want" "目录名 $name 的前缀"
  done
}

register launchd_prefix_non_ascii_locale_independent
case_launchd_prefix_non_ascii_locale_independent() {
  local name root want c utf8 zh
  for name in "项目" "项目2" "my项目" "---" "café"; do
    new_project "$CASE_DIR/$name"
    root=$(phys "$CASE_DIR/$name")
    want=local.p$(printf '%s' "$root" | cksum | cut -d' ' -f1)
    c=$(dry_run_prefix "$LD/install.sh")
    utf8=$(dry_run_prefix --env LC_ALL=en_US.UTF-8 "$LD/install.sh")
    zh=$(dry_run_prefix --env LC_ALL=zh_CN.UTF-8 "$LD/install.sh")
    expect_eq "$c" "$want" "目录名 $name 在 C locale 下的前缀"
    expect_eq "$utf8" "$want" "目录名 $name 在 en_US.UTF-8 下的前缀"
    expect_eq "$zh" "$want" "目录名 $name 在 zh_CN.UTF-8 下的前缀"
  done
  # 按一种 locale 装、另一种 locale 重装与卸载，仍是同一批 plist
  new_project "$CASE_DIR/中文项目"
  try launchd_sh "$LD/install.sh"
  expect_rc 0 "C locale 安装"
  local labels
  labels=$(plist_labels)
  try launchd_sh --env LC_ALL=en_US.UTF-8 "$LD/install.sh"
  expect_rc 0 "UTF-8 locale 重装"
  expect_eq "$(plist_labels)" "$labels" "两种 locale 下是同一批 plist"
  try launchd_sh --env LC_ALL=zh_CN.UTF-8 "$LD/uninstall.sh"
  expect_rc 0 "另一种 locale 卸载"
  expect_eq "$(plist_labels)" "" "卸载后应不剩 plist"
}

register launchd_symlinked_path_same_prefix
case_launchd_symlinked_path_same_prefix() {
  new_project "$CASE_DIR/real/my-app"
  ln -s "$CASE_DIR/real" "$CASE_DIR/link"
  local via_link=$CASE_DIR/link/my-app/scripts/launchd real
  real=$(phys "$CASE_DIR/real/my-app")
  try launchd_sh "$via_link/install.sh"
  expect_rc 0 "经软链安装"
  expect_eq "$(plist_owner_of local.my-app.1-task)" "$real" "plist 记的是物理路径"
  try launchd_sh "$LD/install.sh"
  expect_rc 0 "经真实路径重装"
  expect_eq "$(plist_count local.my-app)" 1 "同一批 plist"
  try launchd_sh "$via_link/uninstall.sh"
  expect_rc 0 "经软链卸载"
  expect_eq "$(plist_labels)" "" "卸载后应不剩 plist"
}

# ---------------------------------------------------------------------------
# cron 表达式 → plist 的时间键

register launchd_schedule_mapping
case_launchd_schedule_mapping() {
  new_project "$CASE_DIR/my-app"
  sed -n '/^#/p' "$LAUNCHD_SRC/tasks.conf" >"$LD/tasks.conf"
  cat >>"$LD/tasks.conf" <<'EOF'
minute | * * * * * | echo a
ten | */10 * * * * | echo b
halves | 0,30 * * * * | echo c
weekdays | 15 9 * * 1-5 | echo d
daily | @daily | echo e
hourly | @hourly | echo f
reboot | @reboot | echo g
EOF
  try launchd_sh "$LD/install.sh"
  expect_rc 0 "安装"
  expect_eq "$(plist_labels)" "local.my-app.1-minute
local.my-app.2-ten
local.my-app.3-halves
local.my-app.4-weekdays
local.my-app.5-daily
local.my-app.6-hourly
local.my-app.7-reboot" "标签按序号与名称 slug 生成"
  keys() { grep -c "$2" "$(agent_dir)/local.my-app.$1.plist" | tr -d " "; }
  has() { grep -qF "$2" "$(agent_dir)/local.my-app.$1.plist" || fail "$1 的 plist 里应有：$2"; }
  # 「每 N 分钟」装成 StartInterval，其余装成 StartCalendarInterval
  has 1-minute "<key>StartInterval</key><integer>60</integer>"
  has 2-ten "<key>StartInterval</key><integer>600</integer>"
  has 3-halves "<key>StartCalendarInterval</key>"
  expect_eq "$(keys 3-halves '<key>Minute</key>')" 2 "0,30 应有两条日历条目"
  expect_eq "$(keys 4-weekdays '<key>Weekday</key>')" 5 "1-5 应展开成五条"
  has 4-weekdays "<key>Hour</key><integer>9</integer>"
  has 4-weekdays "<key>Minute</key><integer>15</integer>"
  # @daily 等于 0 0 * * *：日历式，一条条目，只有 Minute 与 Hour
  has 5-daily "<key>Minute</key><integer>0</integer>"
  has 5-daily "<key>Hour</key><integer>0</integer>"
  expect_eq "$(keys 5-daily '<key>Weekday</key>')" 0 "@daily 不该限定星期"
  has 6-hourly "<key>StartInterval</key><integer>3600</integer>"
  has 7-reboot "<key>RunAtLoad</key><true/>"
  # 日和星期都没限定的日历任务：status 按日历条目数报
  try launchd_sh "$LD/status.sh" 0
  expect_rc 0 "status"
  expect_out "  触发    日历式，1 个时刻"
  expect_out "  触发    日历式，2 个时刻"
  expect_out "  触发    日历式，5 个时刻"
}

register launchd_schedule_errors
case_launchd_schedule_errors() {
  new_project "$CASE_DIR/my-app"
  cp "$LD/tasks.conf" "$CASE_DIR/tasks.orig"
  bad() { # bad <任务行> <期望的报错片段>
    { cat "$CASE_DIR/tasks.orig"; printf '%s\n' "$1"; } >"$LD/tasks.conf"
    try launchd_sh "$LD/install.sh" --dry-run
    expect_rc 1 "清单行：$1"
    expect_out "$2" "清单行：$1"
  }
  bad "日和星期 | 0 3 5 * 1 | echo x" "同时限定了日和星期"
  bad "缺命令 | 0 1 * * *" "任务「缺命令」缺少命令"
  bad "四个字段 | 0 1 * * | echo x" "cron 表达式不是 5 个字段"
  bad "没有分隔符的一行" "缺少命令"
  bad "坏快捷 | @weekdays | echo x" "快捷写法 @weekdays 不支持"
  bad "坏分钟 | 61 * * * * | echo x" "分钟字段解析不了"
  bad "坏星期 | 0 0 * * 9 | echo x" "星期字段解析不了"
  bad "太多时刻 | 0-59 0-23 * * * | echo x" "展开出超过 200 个时刻"
  bad "坏偏移 | * * * * * +abc | echo x" "偏移不是秒数"
  expect_eq "$(plist_count local.my-app)" 0 "清单有错时不应写出 plist"
}

register launchd_offsets_and_pipes
case_launchd_offsets_and_pipes() {
  new_project "$CASE_DIR/my-app"
  sed -n '/^#/p' "$LAUNCHD_SRC/tasks.conf" >"$LD/tasks.conf"
  printf '%s\n' "高频巡检 | * * * * * +0,20 | node poll.js | tee -a out.log" >>"$LD/tasks.conf"
  printf '%s\n' "# 停用的任务 | * * * * * | echo disabled" >>"$LD/tasks.conf"
  printf '%s\n' "尖括号 | 0 1 * * * | echo a && echo '<b>' > out.txt" >>"$LD/tasks.conf"
  try launchd_sh "$LD/install.sh"
  expect_rc 0 "安装"
  expect_eq "$(plist_labels)" "local.my-app.1-task-s0
local.my-app.1-task-s20
local.my-app.2-task" "两个偏移各一个 plist，停用的不算"
  grep -qF "<string>{ node poll.js | tee -a out.log ; } &gt;&gt;" "$(agent_dir)/local.my-app.1-task-s0.plist" \
    || fail "命令里的管道应原样写进 plist"
  grep -qF "<string>sleep 20 &amp;&amp; { node poll.js" "$(agent_dir)/local.my-app.1-task-s20.plist" \
    || fail "偏移应写成 sleep"
  grep -qF "echo '&lt;b&gt;'" "$(agent_dir)/local.my-app.2-task.plist" || fail "命令里的尖括号应转义"
  grep -rqF "echo disabled" "$(agent_dir)" && fail "注释掉的任务不应装上"
  # 生成的 plist 都合法
  local p
  for p in "$(agent_dir)"/*.plist; do
    plutil -lint "$p" >/dev/null || fail "plist 不合法：$p"
  done
}

register launchd_tasks_conf_boundary
case_launchd_tasks_conf_boundary() {
  new_project "$CASE_DIR/my-app"
  # 界线行之前已启用的任务行（用户直接把示例改成了启用）与界线行之后的内容都要读到
  python3 - "$LD/tasks.conf" <<'EOF'
import sys
from pathlib import Path
p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8")
boundary = "# ---- 本项目的任务写在这一行之后 ----\n"
assert s.count(boundary) == 1, "tasks.conf 的界线行变了"
before, after = s.split(boundary)
before = before.replace("# 每日备份      | 0 3 * * *            | ./scripts/backup.sh --retention 7",
                        "每日备份      | 0 3 * * *            | ./scripts/backup.sh --retention 7")
assert "\n每日备份 " in before, "示例行变了"
after = "\n".join(["", "   ", "后面的任务 | @daily | echo after", "末行无换行 | 0 1 * * * | echo last"])
p.write_text(before + boundary + after, encoding="utf-8")
EOF
  try launchd_sh "$LD/install.sh"
  expect_rc 0 "安装"
  expect_out "  - 每日备份  (0 3 * * *)"
  expect_out "  - 后面的任务  (@daily)"
  expect_out "  - 末行无换行  (0 1 * * *)"
  expect_out "已安装 3 个 LaunchAgent"
  expect_not_out "同步数据"
  grep -qF "echo last" "$(agent_dir)/local.my-app.3-task.plist" || fail "末行没有换行也要读到"
}

# ---------------------------------------------------------------------------
# status

register launchd_status_reports_state
case_launchd_status_reports_state() {
  new_project "$CASE_DIR/my-app"
  printf '%s\n' "每天备份 | 0 3 * * * | echo backup" >>"$LD/tasks.conf"
  try launchd_sh "$LD/status.sh"
  expect_rc 0 "还没装时的 status"
  expect_out "没有装任何任务（标签前缀 local.my-app）"
  try launchd_sh "$LD/install.sh"
  expect_rc 0 "安装"
  try launchd_sh "$LD/status.sh"
  expect_rc 0 "装完后的 status"
  expect_out "定时任务状态（标签前缀 local.my-app）"
  expect_out "测试任务（*/5 * * * *）"
  expect_out "  标签    local.my-app.1-task"
  expect_out "  触发    每 300 秒"
  expect_out "  命令    echo hi"
  expect_out "  加载    是，此刻没在跑，上次退出码 0，累计跑过 3 次"
  expect_out "每天备份（0 3 * * *）"
  expect_out "  触发    日历式，1 个时刻"
  expect_out "还没有这个文件"
  # 日志存在时给出末尾几行；0 行则不看日志
  mkdir -p "$CASE_DIR/my-app/logs/launchd"
  printf 'l1\nl2\nl3\n' >"$CASE_DIR/my-app/logs/launchd/launchd.log"
  try launchd_sh "$LD/status.sh" 2
  expect_rc 0 "带行数的 status"
  expect_out "（最后 2 行）"
  expect_out "  l3"
  expect_not_out "  l1"
  try launchd_sh "$LD/status.sh" 0
  expect_rc 0 "status 0"
  expect_not_out "日志 "
  # plist 在但没加载
  : >"$(loaded_file)"
  try launchd_sh "$LD/status.sh" 0
  expect_rc 0 "没加载时的 status"
  expect_out "加载    否 —— plist 在但没加载，跑一次 install.sh"
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
