#!/bin/sh
#
# install.sh / uninstall.sh 的公共部分：定位项目、计算 crontab 标记、读写 crontab。
#
set -eu

# 都取物理路径：经软链访问同一项目时，标记与区块里记的项目根才不会随访问路径变。
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)

# 下面 PROJECT_ROOT、LOG_DIR、CRON_TAG 三个默认值按项目定，要长期生效就直接改默认值；
# 对应的环境变量（CRON_PROJECT_ROOT、CRON_LOG_DIR、CRON_TAG）只用于临时覆盖，靠它的话每次 install / uninstall 都得带上同一组。

# 项目根目录：默认取脚本目录上溯两级，对应脚本在 <项目根>/<一级目录>/cron/ 下；深度不同时改层级。
PROJECT_ROOT=${CRON_PROJECT_ROOT:-$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd -P)}

TASKS_FILE=${CRON_TASKS_FILE:-$SCRIPT_DIR/tasks.conf}

# 日志目录：默认 <项目根>/logs/cron；项目已有约定的日志目录时改成它。
LOG_DIR=${CRON_LOG_DIR:-$PROJECT_ROOT/logs/cron}

# crontab 区块标记：同一份 crontab 里多个项目靠它互不干扰。默认由项目根目录名归一化得出；
# 目录名含非 ASCII 字符（如中文名）或没有字母数字时改用项目根路径的 cksum——非 ASCII 字符按 locale
# 折算成的 `_` 个数不定，同一目录在不同终端会算出不同标记。cksum 随路径变，项目移动后旧区块会留在
# crontab 里，所以这种项目要把下面的默认值改成固定标记。不同路径的同名项目、归一化后相同的目录名
# （my-app 与 my_app）会撞车，install.sh / uninstall.sh 会报错退出，同样改成固定标记：
# CRON_TAG=${CRON_TAG:-MY_APP}。
default_tag() {
  _base=$(basename "$PROJECT_ROOT")
  if [ -z "$(printf '%s' "$_base" | LC_ALL=C tr -d '\000-\177')" ]; then
    _tag=$(printf '%s' "$_base" | LC_ALL=C tr '[:lower:]' '[:upper:]' | LC_ALL=C sed 's/[^A-Z0-9]/_/g')
    case "$_tag" in
      *[A-Z0-9]*) printf '%s' "$_tag"; return ;;
    esac
  fi
  printf 'P%s' "$(printf '%s' "$PROJECT_ROOT" | cksum | cut -d' ' -f1)"
}
CRON_TAG=${CRON_TAG:-$(default_tag)}
MARKER_START="# >>> CRON:$CRON_TAG >>>"
MARKER_END="# <<< CRON:$CRON_TAG <<<"

die() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

trim() {
  printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

require_crontab() {
  command -v crontab >/dev/null 2>&1 || die '找不到 crontab 命令'
}

read_crontab() {
  crontab -l 2>/dev/null || true
}

# 核对 crontab 内容 $1 里本标记的区块是不是本项目装的。strip_block 只认标记，撞车时会删掉别的项目的
# 区块，所以动 crontab 之前先调用。区块第二行记着装它的项目根目录：与当前不同、且那里仍有 cron/common.sh
# 就是撞车；那个目录已不存在或已没有 cron/common.sh 的，当作项目搬走了，区块由当前项目接管。
check_tag_owner() {
  _owner=$(printf '%s\n' "$1" | awk -v s="$MARKER_START" 'hit { print; exit } $0 == s { hit = 1 }')
  _owner=${_owner#'# '}
  if [ -z "$_owner" ] || [ "$_owner" = "$PROJECT_ROOT" ] || [ ! -d "$_owner" ]; then
    return 0
  fi
  # 区块里记的可能是经软链的路径，按物理路径再比一次。
  if [ "$(CDPATH= cd -- "$_owner" && pwd -P)" = "$(CDPATH= cd -- "$PROJECT_ROOT" 2>/dev/null && pwd -P)" ]; then
    return 0
  fi
  # 不限深度：脚本放得再深也得找到，否则会把仍在用的项目误判为已搬走、删掉它的区块。
  if [ -n "$(find "$_owner" \( -name node_modules -o -name .git \) -prune -o -path '*/cron/common.sh' -print 2>/dev/null | head -n 1)" ]; then
    die "标记 $CRON_TAG 已被 $_owner 使用，在 common.sh 里把 CRON_TAG 改成固定标记"
  fi
}

# 从标准输入剔除本项目的标记区块（含标记行本身）
strip_block() {
  awk -v s="$MARKER_START" -v e="$MARKER_END" '
    $0 == s { skip = 1; next }
    skip && $0 == e { skip = 0; next }
    !skip { print }
  '
}

# 用第一个参数整体替换 crontab；内容为空则删除整份 crontab
write_crontab() {
  if [ -z "$(printf '%s' "$1" | tr -d '[:space:]')" ]; then
    crontab -r 2>/dev/null || true
  else
    printf '%s\n' "$1" | crontab -
  fi
}
