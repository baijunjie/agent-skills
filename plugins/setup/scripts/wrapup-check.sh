#!/usr/bin/env bash
# PreToolUse(Bash) hook：git commit 前的收尾闸门。
# 本文件只做调度：确认这次提交有源码改动后，依次跑 .claude/hooks/wrapup.d/*.sh，
# 把它们各自要说的话合成一次 deny。每项收尾检查装一个片段进去，装了才参与。
# 多个 PreToolUse hook 并行执行、多个 deny 如何合并未定义，所以全项目只注册这一个 hook。
# 任何异常一律放行——这是提醒机制，不该成为提交的故障点。
set -uo pipefail

# 用排除法认源码：除了下面这些，暂存区里的其余改动都算。这样任何项目装上就能用，
# 补漏只是优化；反过来枚举源码目录，一旦漏了或忘了改，闸门就永远不触发且毫无迹象。
NON_SRC_PATTERN='^(docs/|\.claude/|\.github/|\.idea/)|^(README|LICENSE|CHANGELOG|AGENTS|CLAUDE)\.md$'

FRAG_DIR='.claude/hooks/wrapup.d'

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

src=$(printf '%s\n' "$staged" | grep -v '^$' | grep -vE "$NON_SRC_PATTERN" | sort -u)
[ -n "$src" ] || exit 0

# 片段契约：$1 是暂存文件清单的路径；要提醒就把话打到 stdout，不提醒就什么都不打。
# 文件名前缀决定顺序，也就是收尾时该按什么次序做。
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

# 同一批源码改动、同一组待答提醒只拦一次：核对后重跑同一条命令要能过去。
# 补了其中一项、另一项还没动时 spoke 会变，于是只就剩下的那项再问一次。
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
