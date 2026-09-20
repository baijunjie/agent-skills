---
name: codex-bridge
description: 在当前用户环境给 Codex 装上（或更新）读取 Claude 规范的 `claude` skill，让 Codex 开工前先盘点用户级与项目级的 CLAUDE.md、skills、agents、settings，并把兼容的工作流用于本次任务。用于"让 Codex 也认 Claude 的规范""Codex 读不到我的 CLAUDE.md""配一台新电脑的 Codex""同步 Codex 侧配置"等场景。
disable-model-invocation: true
---

# 给 Codex 装上 Claude 规范预检 skill

Codex 原生只认 `AGENTS.md`，读不到 Claude 那套 `skills/` `agents/` `settings.json`。
装上这个 skill，Codex 开工前会按 Claude 的配置层级把规范读齐，照 Claude 这套工具链继续开发。

## 步骤

1. **先定装在哪**：用 `X=${CODEX_HOME:-$HOME/.codex}` 确定 Codex 的用户级配置根目录。
   `$HOME/.agents/skills/claude` 已经有一份就就地更新它，否则安装到 `$X/skills/claude`。
   **别两处各放一份同名 skill。**
2. **装进去**：

   ```bash
   X=${CODEX_HOME:-$HOME/.codex}
   if [ -d "$HOME/.agents/skills/claude" ]; then
     D="$HOME/.agents/skills/claude"
   else
     D="$X/skills/claude"
   fi
   if [ -n "${PLUGIN_ROOT:-}" ]; then
     T="$PLUGIN_ROOT/skills/codex-bridge/template/claude"
   elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
     T="$CLAUDE_PLUGIN_ROOT/skills/codex-bridge/template/claude"
   else
     T="${SKILL_DIR:?先将 SKILL_DIR 设为当前 SKILL.md 的绝对父目录}/template/claude"
   fi
   mkdir -p "$D/agents"
   cp -n "$T/SKILL.template.md" "$D/SKILL.md"
   cp -n "$T/agents/openai.yaml" "$D/agents/"
   ```

   `PLUGIN_ROOT` 与 `CLAUDE_PLUGIN_ROOT` 都为空时，从当前 `SKILL.md` 所在目录定位 `template/`。
   已存在的文件 `cp -n` 会静默跳过，跳过了就转「已存在时」，不要当成装好了。
3. **告知用户**：重启 Codex 才加载；在 Codex 里用 `$claude` 显式触发，也会按它的 description
   自动命中。

## 已存在时

已装的 `SKILL.md` 不要覆盖：与 `template/` 逐节比对，补齐模板有而它没有的，保留当前用户环境已有的补充内容。
不要修改已安装 plugin 内的 `template/`。
要动的地方超过补充规则的范围时，先把打算怎么改告诉用户。

## 现状与预期不符时

要写入的路径不是普通目录时**停下来问用户**，不要照写。最常见的是软链：
`cp` 会写到它指向的地方，而 `mkdir -p` 在软链上仍然静默成功，表面看不出异常。
