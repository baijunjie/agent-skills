# Agent Skills

个人 agent skills 仓库。以 Claude Code plugin marketplace 形式分发，skill 本身遵循 [Agent Skills 规范](https://agentskills.io/specification)，以便被其它支持该标准的工具复用。

## 结构

```
.claude-plugin/marketplace.json     # marketplace 定义，列出所有 plugin
plugins/<plugin>/
├── .claude-plugin/plugin.json      # plugin 元信息
└── skills/<skill>/SKILL.md         # skill 本体
```

Plugin 名即调用前缀：`plugins/dev/skills/coding/SKILL.md` 对应 `/dev:coding`。

## 新增 Skill

1. 创建 `plugins/<plugin>/skills/<skill-name>/SKILL.md` 并写好 YAML frontmatter
2. 在 `README.md` 的可用 Skills 表格中补一行
3. 在 `.claude/settings.json` 的 `permissions.allow` 中加入 `Skill(<plugin>:<skill-name>)`

新增 plugin 时还需创建 `plugins/<plugin>/.claude-plugin/plugin.json`，并在 `.claude-plugin/marketplace.json` 的 `plugins` 数组中登记。

## Frontmatter

YAML frontmatter 必须位于文件最开头，`---` 是第一行，前面不能有注释或空行。

必填：

- `name` — kebab-case，与所在目录名一致
- `description` — 说明做什么、什么时候用，包含触发关键词；模型靠它决定是否自动调用

常用可选项：

- `disable-model-invocation: true` — 禁止模型自动调用，只能由用户显式 `/xxx` 触发。流程编排类 skill（如 `discuss`、`optimize`）应加上，否则会被误触发
- `model` — 覆盖模型档位（`sonnet` / `opus` / `haiku`）
- `allowed-tools` — 限制可用工具；不确定时不要加，避免过度约束

## 参数传递

SKILL.md 中的 `$ARGUMENTS` 会被替换为用户调用时传入的参数。用 XML 标签包裹以界定边界：

```markdown
<task>
$ARGUMENTS
</task>
```

不要用 `---` 分隔线包裹参数——它与 frontmatter 语法冲突。

## 本地验证

```bash
claude plugin marketplace add ~/Documents/GitHub/agent-skills
claude plugin install <plugin>@bjj-agent-skills
```

改动后重启 Claude Code 才会生效。
