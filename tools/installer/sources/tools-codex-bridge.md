---
name: codex-bridge
description: {{scope_lead}}供 Codex 读取 Claude 规范的 `claude` skill，让 Codex 开工前先盘点用户级与项目级的 CLAUDE.md、skills、agents、settings，并把兼容的工作流用于本次任务。{{scope_tail}}用于"让 Codex 也认 Claude 的规范""Codex 读不到我的 CLAUDE.md""配一台新电脑的 Codex""同步 Codex 侧配置"等场景。
disable-model-invocation: true
---

# 给 Codex 装上 Claude 规范预检 skill

装出的 skill 靠 description 自动触发，本安装器不往指令文件写任何内容。

## 跨宿主约定

无论在 Claude Code 还是 Codex 中运行，都装进 Codex 的用户级 skill 目录；不在当前项目写任何文件。

{{include: host-conventions}}

{{include: pre-write}}

本安装器另外要查的冲突：无。

## Codex 用户级安装

已有的同名文件直接覆盖，目录里别的文件不动。

```bash
: "${TEMPLATE_DIR:?}"
D="$HOME/.agents/skills/claude"
mkdir -p "$D/agents"
cp "$TEMPLATE_DIR/SKILL.template.md" "$D/SKILL.md"
cp "$TEMPLATE_DIR/agents/openai.yaml" "$D/agents/"
```

**告知用户**：

- 说明实际写入的用户级配置目录；Codex 开启新会话后生效，也可在 Codex 里用 `$claude` 显式触发。
- 装出的 skill 从 `CLAUDE_CONFIG_DIR` 读 Claude 的用户级配置，没设时读 `~/.claude`，而 Codex 的环境里通常没设这个变量。
  检查当前环境的 `CLAUDE_CONFIG_DIR`：已设置且不是 `~/.claude` 时，提示用户在启动 Codex 的环境里导出同一个值
  （如写进 shell 配置文件），否则读到的是 `~/.claude`；没设置时说明会读 `~/.claude`，Claude Code 用的是别的配置目录时同样要导出。

{{include: reinstall}}

本安装器的定制值：无。

{{include: state-mismatch}}
