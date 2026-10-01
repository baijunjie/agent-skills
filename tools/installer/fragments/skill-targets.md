## Claude Code 项目级安装（默认）

```bash
{{include: project-root}}
mkdir -p .claude/skills/{{name}}
cp "$TEMPLATE_DIR/{{name}}.md" .claude/skills/{{name}}/SKILL.md
```

**告知用户**：`.claude/skills/{{name}}/` 要提交进版本库才随仓库生效；
`.gitignore` 整体忽略了 `.claude/` 的项目要为它加例外。装好后可用 `/{{name}}` 调用，也会按描述自动触发；
如未生效，重启 Claude Code。

## Claude Code 用户级安装

装进**当前会话的用户级配置目录**，不要写死路径。

```bash
C=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
mkdir -p "$C/skills/{{name}}"
cp "$TEMPLATE_DIR/{{name}}.md" "$C/skills/{{name}}/SKILL.md"
```

**告知用户**：装到了哪个用户级配置目录要说清楚（用户可能开着多个）；如未生效，重启 Claude Code。

## Codex 项目级安装（默认）

```bash
{{include: project-root}}
mkdir -p .agents/skills/{{name}}
cp "$TEMPLATE_DIR/{{name}}.md" .agents/skills/{{name}}/SKILL.md
```

**告知用户**：`.agents/skills/{{name}}/` 要提交进版本库才随仓库生效；
`.gitignore` 整体忽略了 `.agents/` 的项目要为它加例外。开启新会话后生效。

## Codex 用户级安装

```bash
{{include: codex-user-skill-dir}}
D=$(codex_skill_dir {{name}}) || exit 1
mkdir -p "$D"
cp "$TEMPLATE_DIR/{{name}}.md" "$D/SKILL.md"
```

**告知用户**：说明实际写入的用户级配置目录；开启新会话后生效。
