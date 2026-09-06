#!/usr/bin/env bash
# PreToolUse(Bash) hook：git commit 前的收尾闸门，只做调度。
# 多个 PreToolUse hook 并行执行、多个 deny 如何合并未定义，所以全项目只注册这一个。
# 任何异常一律放行——这是提醒机制，不该成为提交的故障点。
set -uo pipefail

# 加条目的判据是「这类路径一旦存在会不会被 git 跟踪」，不是「本项目有没有」；
# 被 .gitignore 掉的进不了暂存区，不必列。
NON_SRC_PATTERN='^(docs/|\.claude/|\.github/)|^(README|LICENSE|CHANGELOG|AGENTS|CLAUDE)\.md$'

FRAG_DIR='.claude/hooks/wrapup.d'

command -v jq >/dev/null 2>&1 || exit 0
repo=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$repo" 2>/dev/null || exit 0

cmd=$(jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0
# settings.json 里的 if 过滤未必生效，脚本自己再确认一次命令类型。
case "$cmd" in *"git commit"*) ;; *) exit 0 ;; esac

staged=$(git diff --cached --name-only 2>/dev/null)
# `commit -a` 提交时会把已跟踪的改动一并带上，需算进来。
case "$cmd" in
  *" -a"* | *" --all"*) staged=$(printf '%s\n%s\n' "$staged" "$(git diff --name-only 2>/dev/null)") ;;
esac

src=$(printf '%s\n' "$staged" | grep -v '^$' | grep -vE "$NON_SRC_PATTERN" | sort -u)
[ -n "$src" ] || exit 0

# 片段契约：$1 是暂存文件清单的路径，要提醒就打到 stdout，否则什么都不打；文件名前缀即执行顺序。
list=$(mktemp) || exit 0
trap 'rm -f "$list"' EXIT
printf '%s\n' "$staged" >"$list"

reasons=''
spoke=''
for frag in "$FRAG_DIR"/*.sh; do
  [ -f "$frag" ] || continue
  out=$(bash "$frag" "$list" 2>/dev/null) || continue
  [ -n "$out" ] || continue
  reasons="$reasons
$out"
  spoke="$spoke $(basename "$frag")"
done
[ -n "$reasons" ] || exit 0

# sig 带上 spoke：补了其中一项之后，只就剩下的那项再问一次。
ack="$(git rev-parse --absolute-git-dir)/claude-wrapup-ack"
sig=$(printf '%s\n%s\n' "$src" "$spoke" | shasum | cut -d' ' -f1)
[ -f "$ack" ] && [ "$(cat "$ack" 2>/dev/null)" = "$sig" ] && exit 0
printf '%s' "$sig" >"$ack"

reason="本次提交含源码改动，收尾检查（同一批只拦一次，核对完直接重跑同一条 git commit）：
$reasons

多项都要做时按上面列出的顺序做。要落笔写文档 / 记忆的那几条换干净上下文来做，
有子代理机制就派子代理——除非该条自己说了由你做。"

jq -n --arg r "$reason" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
