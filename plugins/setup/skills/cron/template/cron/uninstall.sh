#!/bin/sh
#
# 从当前用户的 crontab 中移除本项目的定时任务。
# 只删标记区块，crontab 里的其它内容原样保留。
#
#   sh scripts/cron/uninstall.sh
#
set -eu

. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/common.sh"

require_crontab

current=$(read_crontab)

case "$current" in
  *"$MARKER_START"*) ;;
  *)
    printf '未找到本项目的 crontab 区块（标记 %s），无需卸载\n' "$CRON_TAG"
    exit 0 ;;
esac

write_crontab "$(printf '%s\n' "$current" | strip_block)"

printf '已移除本项目的定时任务（crontab 标记 %s）\n' "$CRON_TAG"
printf '`crontab -l` 确认，`sh %s/install.sh` 重新安装\n' "$SCRIPT_DIR"
