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

## 附带资源

skill 需要携带脚本、模板等文件时，放在自己的目录下，用 `$CLAUDE_PLUGIN_ROOT/skills/<skill>/<file>` 引用——
plugin 安装后的实际路径不可预测，只有这个环境变量能定位。

附带的模板文件不要命名为 `SKILL.md`，避免与 skill 本体混淆。

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

## 安装与迭代

marketplace 名为 `bjj-agent-skills` 而非仓库名 `agent-skills`——后者是 Anthropic 保留名，只允许 `anthropics` 组织的 GitHub 源使用。

**必须用 GitHub 源安装**，不要用本地目录源：

```bash
claude plugin marketplace add baijunjie/agent-skills
claude plugin install <plugin>@bjj-agent-skills
```

GitHub 源会把仓库 clone 到 `plugins/marketplaces/bjj-agent-skills/`，运行时与本地工作副本无关。若改用 `claude plugin marketplace add <本地路径>`，marketplace 的 `installLocation` 会直接指向该路径，工作副本一旦移动或删除，所有 skill 都会报 `failed to load: cache-miss`——即使 plugin 内容已复制进 `plugins/cache/` 也救不回来。

### 发布改动

plugin 按 **git commit SHA** 缓存，改完 skill 只保存文件不生效，必须推到远端：

```bash
git commit -am "..."                             # 1. 提交
git push                                         # 2. 推送（GitHub 源只认远端）
claude plugin marketplace update                 # 3. 刷新 marketplace
claude plugin update <plugin>@bjj-agent-skills   # 4. 更新 plugin
# 5. 重启 Claude Code
```

若配置了多个 `CLAUDE_CONFIG_DIR`（如 `~/.claude` 与 `~/.claude-work`），每个都是独立的安装环境，第 3、4 步需要分别执行。

## 排查

```bash
claude plugin details <plugin>    # 查看已加载的 skill 清单与 token 开销
claude plugin marketplace list    # 确认 marketplace 已注册
```
