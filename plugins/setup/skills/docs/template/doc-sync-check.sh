#!/usr/bin/env bash
# PreToolUse(Bash) hook：git commit 前确认三类项目文档是否需要同步（规则见 .claude/skills/docs/SKILL.md）。
# 暂存区有源码改动、却没有文档改动时 deny 一次；核对完文档重跑同一条命令即放行。
# 任何异常一律放行——这是提醒机制，不该成为提交的故障点。
set -uo pipefail

# 按项目实际情况调整：哪些路径算源码改动、哪些算文档改动。
SRC_PATTERN='^(src|lib|app)/'
DOC_PATTERN='^docs/'

command -v jq >/dev/null 2>&1 || exit 0
repo=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$repo" 2>/dev/null || exit 0

cmd=$(jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0
# settings.json 里的 if 过滤未必生效，脚本自己再确认一次命令类型。
case "$cmd" in *"git commit"*) ;; *) exit 0 ;; esac

# 待提交内容取暂存区；`commit -a` 会在提交时把已跟踪的改动一并带上，需算进来。
staged=$(git diff --cached --name-only 2>/dev/null)
case "$cmd" in
  *" -a"* | *" --all"*) staged=$(printf '%s\n%s\n' "$staged" "$(git diff --name-only 2>/dev/null)") ;;
esac

src=$(printf '%s\n' "$staged" | grep -E "$SRC_PATTERN" | sort -u)
[ -n "$src" ] || exit 0
printf '%s\n' "$staged" | grep -qE "$DOC_PATTERN" && exit 0

# 同一批源码改动只拦一次：核对后重跑同一条命令要能过去。
# 标记落在 .git/ 内（每个 worktree 各一份，天然不入库）。
ack="$(git rev-parse --absolute-git-dir)/claude-doc-sync-ack"
sig=$(printf '%s' "$src" | shasum | cut -d' ' -f1)
[ -f "$ack" ] && [ "$(cat "$ack" 2>/dev/null)" = "$sig" ] && exit 0
printf '%s' "$sig" >"$ack"

jq -n --arg r '本次提交含源码改动，但暂存区里没有文档改动。按 `docs` skill 的「文档同步」一节确认四点：
1. 产品行为 / 契约 / 交互有变 → 同步 docs/product/（已实现功能的权威描述）；
2. 本次落地的内容在 docs/development/ 有对应清单项 → 勾掉，里程碑完成则迁入 docs/product/ 并从开发文档删除；
3. 目录结构 / 模块职责 / 对外接口有变 → 同步 docs/README.md 与相关模块 README；
4. 纯内部实现细节、不让现有文档失真的改动 → 不必改文档。
确认完毕（补了文档、或判定不需要改）直接重跑同一条 git commit 即可，同一批暂存内容不会再拦第二次。' \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
