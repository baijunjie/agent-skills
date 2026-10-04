<!--
Claude Code / Codex × 项目级（默认）/ 用户级四个安装节，把 template/<name>/SKILL.template.md 装成同名 skill。
只装一个 skill 的 project-user 作用域源文件 include；setup-tools 的源文件不能用（装出的 skill 不带领域前缀）。
-->

## Claude Code 项目级安装（默认）

```bash
{{include: project-root}}
: "${TEMPLATE_DIR:?}"
mkdir -p .claude/skills/{{name}}
cp "$TEMPLATE_DIR/{{name}}/SKILL.template.md" .claude/skills/{{name}}/SKILL.md
```

**告知用户**：`.claude/skills/{{name}}/` 要提交进版本库才随仓库生效；
`.gitignore` 整体忽略了 `.claude/` 的项目要为它加例外。装好后可用 `/{{name}}` 调用，也会按描述自动触发；
如未生效，重启 Claude Code。

## Claude Code 用户级安装

装进**当前会话的用户级配置目录**，不要写死路径。

```bash
: "${TEMPLATE_DIR:?}"
C=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
mkdir -p "$C/skills/{{name}}"
cp "$TEMPLATE_DIR/{{name}}/SKILL.template.md" "$C/skills/{{name}}/SKILL.md"
```

**告知用户**：装到了哪个用户级配置目录要说清楚（用户可能开着多个）；如未生效，重启 Claude Code。

## Codex 项目级安装（默认）

```bash
{{include: project-root}}
: "${TEMPLATE_DIR:?}"
mkdir -p .agents/skills/{{name}}
cp "$TEMPLATE_DIR/{{name}}/SKILL.template.md" .agents/skills/{{name}}/SKILL.md
```

**告知用户**：`.agents/skills/{{name}}/` 要提交进版本库才随仓库生效；
`.gitignore` 整体忽略了 `.agents/` 的项目要为它加例外。开启新会话后生效。

## Codex 用户级安装

```bash
: "${TEMPLATE_DIR:?}"
D="$HOME/.agents/skills/{{name}}"
mkdir -p "$D"
cp "$TEMPLATE_DIR/{{name}}/SKILL.template.md" "$D/SKILL.md"
```

**告知用户**：说明实际写入的用户级配置目录；开启新会话后生效。
