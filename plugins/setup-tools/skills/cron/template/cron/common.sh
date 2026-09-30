#!/bin/sh
#
# install.sh / uninstall.sh 的公共部分：定位项目、计算 crontab 标记、读写 crontab。
#
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

# 脚本默认放在 <项目根>/scripts/cron/，上溯两级即项目根；
# 放在其它深度时把下面的默认值改掉。环境变量只用于临时覆盖，
# 靠它长期生效的话，以后每次 install / uninstall 都得带上同一组，漏一次就装到别处去了。
PROJECT_ROOT=${CRON_PROJECT_ROOT:-$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)}

TASKS_FILE=${CRON_TASKS_FILE:-$SCRIPT_DIR/tasks.conf}
LOG_DIR=${CRON_LOG_DIR:-$PROJECT_ROOT/logs/cron}

# 标记区块按项目名区分，同一份 crontab 里多个项目互不干扰。
# 不同路径下的同名项目会撞车，这时用 CRON_TAG 手动区分。
CRON_TAG=${CRON_TAG:-$(basename "$PROJECT_ROOT" | tr '[:lower:]' '[:upper:]' | sed 's/[^A-Z0-9]/_/g')}
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
