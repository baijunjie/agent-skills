#!/usr/bin/env bash
# 收尾闸门片段：本次改了源码却没动开发记忆时提醒一次。$1 是暂存文件清单。
MEMORY_DIR='docs/dev-memory'

grep -qE "^${MEMORY_DIR}/" "$1" 2>/dev/null && exit 0
echo '【开发记忆】暂存区里没有记忆改动。判断本次有没有值得沉淀的坑，「本次无需记录」也是有效结论。'
