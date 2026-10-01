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
{{include: codex-user-skill-dir}}
D=$(codex_skill_dir claude) || exit 1
: "${TEMPLATE_DIR:?}"
mkdir -p "$D/agents"
cp "$TEMPLATE_DIR/SKILL.template.md" "$D/SKILL.md"
cp "$TEMPLATE_DIR/agents/openai.yaml" "$D/agents/"
```

**告知用户**：说明实际写入的用户级配置目录；Codex 开启新会话后生效，也可在 Codex 里用 `$claude` 显式触发。

{{include: reinstall}}

本安装器的定制值：无。

{{include: state-mismatch}}
