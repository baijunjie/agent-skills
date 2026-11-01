#!/bin/sh
#
# 卸载本项目的 LaunchAgent，并删掉 ~/Library/LaunchAgents 下对应的 plist。
# 只动本前缀的 plist，别的项目的原样保留。
#
#   sh <本目录>/uninstall.sh
#
set -euf   # -f 关掉通配：cron 字段里的 * 必须按字面走词拆分，不能被当成文件名通配

. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/common.sh"

require_launchctl

if [ -z "$(installed_plists)" ]; then
  printf '未找到本项目的 LaunchAgent（标签前缀 %s），无需卸载\n' "$LABEL_PREFIX"
  exit 0
fi
check_prefix_owner

removed=$(remove_all)

printf '已卸载 %s 个 LaunchAgent（标签前缀 %s）\n' "$removed" "$LABEL_PREFIX"
printf '`sh %s/install.sh` 重新安装\n' "$SCRIPT_DIR"
