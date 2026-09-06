#!/usr/bin/env bash
# 收尾闸门片段：按开发进行到哪一步，提醒该做的那一件。$1 是暂存文件清单。
#   本次没动开发文档、而它还有未勾项 → 催去勾（写代码的人自己做）
#   动过开发文档、还有未勾项         → 开发中，不出声
#   动过开发文档、已经全勾完         → 收尾了，催整理产品文档 / 项目地图 / 索引
DOC_PATTERN='^docs/product/|^docs/project-map\.md$|README\.md$'
DEV_DIR='docs/development'

staged=$(cat "$1" 2>/dev/null)
# 先把开发文档摘出去再判 DOC_PATTERN：主题目录里也有 README.md，不剔除会被当成模块文档。
outside=$(printf '%s\n' "$staged" | grep -vE "^${DEV_DIR}/")
printf '%s\n' "$outside" | grep -qE "$DOC_PATTERN" && exit 0

if [ -d "$DEV_DIR" ]; then
  touched=$(printf '%s\n' "$staged" | grep -E "^${DEV_DIR}/.*\.md$")
  if [ -z "$touched" ]; then
    # 没有未勾项就没什么可勾的，别问。
    grep -rqE '^[[:space:]]*[-*] \[ \]' "$DEV_DIR" 2>/dev/null || exit 0
    echo '【开发文档】本次改了源码，但开发文档一个字没动。有条目落成就去勾掉，顺手把做不完的移出去。
这一条自己做，不要派子代理；本次不属于任何开发主题、或还没有条目落成，跳过即可。'
    exit 0
  fi
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    grep -qE '^[[:space:]]*[-*] \[ \]' "$f" && exit 0
  done <<INNER
$touched
INNER
fi

echo '【文档同步】本次看着像里程碑收尾，但暂存区里没有产品文档 / 项目地图 / 索引的改动。
按 `docs` skill 的「里程碑收尾」一节确认，判定不必改也是有效结论。'
