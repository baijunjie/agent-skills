# Agent Skills

个人 agent skills 仓库。以 Claude Code 与 Codex plugin marketplace 形式分发，skill 本身遵循 [Agent Skills 规范](https://agentskills.io/specification)，以便被其它支持该标准的工具复用。

## 结构

```
.claude-plugin/marketplace.json     # Claude Code marketplace 定义，列出所有 plugin
.agents/plugins/marketplace.json    # Codex marketplace 定义，列出所有 plugin
plugins/<plugin>/                    # 同时分发到 Claude Code 与 Codex
├── plugin.json                       # Codex plugin 元信息
├── .codex-plugin/plugin.json         # Codex plugin 安装清单
├── .claude-plugin/plugin.json        # Claude Code plugin 元信息
└── skills/<skill>/SKILL.md           # skill 本体
```

Plugin 名即调用前缀：`plugins/dev/skills/coding/SKILL.md` 在 Claude Code 中对应 `/dev:coding`，在 Codex 中对应 `$dev:coding`。

## 新增 Skill

1. 创建 `plugins/<plugin>/skills/<skill-name>/SKILL.md` 并写好 YAML frontmatter
2. 在 `README.md` 的可用 Skills 表格中补一行
3. 在 `.claude/settings.json` 的 `permissions.allow` 中加入 `Skill(<plugin>:<skill-name>)`
4. 对分发到 Codex 且禁止隐式调用的 skill，创建 `agents/openai.yaml` 并设 `policy.allow_implicit_invocation: false`

新增 plugin 时，创建 `plugins/<plugin>/plugin.json`、`plugins/<plugin>/.codex-plugin/plugin.json` 与 `plugins/<plugin>/.claude-plugin/plugin.json`，并分别在 `.agents/plugins/marketplace.json` 与 `.claude-plugin/marketplace.json` 的 `plugins` 数组中登记。`setup-user` 是当前用户级（非系统全局级）配置，但同样是双宿主 plugin；具体 skill 是否创建 `agents/openai.yaml`，取决于它是否分发到 Codex，以及是否需要 Codex UI 或调用策略。

plugin 名表达安装作用域或能力组；宿主适用性由具体 skill 的描述与实现分支决定。不要因某个 skill（如 `codex-bridge`）只配置某一目标宿主，就把整个 plugin 排除出另一 marketplace。

## 附带资源

skill 需要携带脚本、模板等文件时，放在自己的目录下，用 `${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}/skills/<skill>/<file>` 引用——
plugin 安装后的实际路径不可预测，优先使用 Codex 提供的 `PLUGIN_ROOT`，并回退到 Claude Code 的 `CLAUDE_PLUGIN_ROOT`。

**同一 plugin 内多个 skill 共用的资源放 plugin 级 `scripts/`**（`${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}/scripts/<file>`），
不要让一个 skill 去引另一个 skill 的 `template/`——那样两者就绑死了，单独装其中一个会读到不属于它的路径。
plugin 根目录下的任意文件都会随安装一并分发。

附带的模板文件不要命名为 `SKILL.md`，避免与 skill 本体混淆。

## Frontmatter

YAML frontmatter 必须位于文件最开头，`---` 是第一行，前面不能有注释或空行。

必填：

- `name` — kebab-case，与所在目录名一致
- `description` — 说明做什么、什么时候用，包含触发关键词；模型靠它决定是否自动调用

常用可选项：

- `disable-model-invocation: true` — 禁止模型自动调用；Claude Code 中只能由用户显式 `/plugin:skill` 触发。分发到 Codex 的 skill 对应 `$plugin:skill`，并在 `agents/openai.yaml` 映射为 `allow_implicit_invocation: false`。流程编排类 skill（如 `discuss`、`optimize`）应加上，否则会被误触发
- `model` — 覆盖模型档位（`sonnet` / `opus` / `haiku`）
- `allowed-tools` — 限制可用工具；不确定时不要加，避免过度约束

### Agent 模板

Agent 模板的共享指令正文只维护一份，禁止另建重复的宿主版本。Claude 模板的模型配置由 Claude Markdown frontmatter 明确定义；Codex 模板的模型与 reasoning effort 由 `plugins/setup/scripts/render-codex-agent.py` 集中映射和生成，两者不要求使用相同的模型名称。新增 agent 时必须同时补齐 Codex 的 model 与 model_reasoning_effort 映射。renderer 从共享模板提取 `name`、`description` 和完整正文生成 Codex 所需的 `developer_instructions`，宿主专属配置只在各自的配置源中维护。

Workflow 规则同样只维护一份共享模板；宿主和安装作用域的差异由 `plugins/setup/scripts/render-workflow-rules.py` 集中生成，禁止另建宿主摘要版或作用域副本。

## 参数传递

跨宿主 skill 直接以当前用户请求为输入，不要在正文中放 `$ARGUMENTS`：Claude Code 在正文没有参数占位符时，
会把调用参数自动追加为 `ARGUMENTS: <value>`；Codex 的调用参数本来就在当前用户请求中。

只有明确仅面向 Claude Code、且必须把参数插入正文特定位置或按位置拆分时，才使用 `$ARGUMENTS`、
`$ARGUMENTS[N]` 或 `$N`。具体替换规则见 [Claude Code Skills「Pass arguments to skills」](https://code.claude.com/docs/en/skills#pass-arguments-to-skills)。

## 安装与迭代

### Claude Code

marketplace 名为 `bjj-agent-skills` 而非仓库名 `agent-skills`——后者是 Anthropic 保留名，只允许 `anthropics` 组织的 GitHub 源使用。

**必须用 GitHub 源安装**，不要用本地目录源：

```bash
claude plugin marketplace add baijunjie/agent-skills
claude plugin install <plugin>@bjj-agent-skills
```

GitHub 源会把仓库 clone 到 `plugins/marketplaces/bjj-agent-skills/`，运行时与仓库工作副本无关。若改用 `claude plugin marketplace add <本地路径>`，marketplace 的 `installLocation` 会直接指向该路径，工作副本一旦移动或删除，所有 skill 都会报 `failed to load: cache-miss`——即使 plugin 内容已复制进 `plugins/cache/` 也救不回来。

### Codex

沿用同一 marketplace 名 `bjj-agent-skills`，以保持选择器一致。

```bash
codex plugin marketplace add baijunjie/agent-skills
codex plugin add <plugin>@bjj-agent-skills
# 开启新会话
```

也可在 Codex CLI 的 `/plugins` 中安装。Codex plugin 不适用于 IDE extension；IDE 应使用 `skill-installer` 或独立 skill。

### 发布改动

Plugin 按 git commit SHA 缓存；仅修改工作副本不会发布。先提交并推送改动：

```bash
git add <changed-files>
git commit -m "..."
git push
```

#### Claude Code

```bash
claude plugin marketplace update
claude plugin update <plugin>@bjj-agent-skills
# 重启 Claude Code
```

若为不同场景设置了多个 `CLAUDE_CONFIG_DIR`，每个都是独立的用户级安装环境；对每个环境分别刷新 marketplace 和更新 plugin。

#### Codex

```bash
codex plugin marketplace upgrade bjj-agent-skills
codex plugin add <plugin>@bjj-agent-skills
# 开启新会话
```

`codex plugin add` 会重新安装指定 plugin；也可在 Codex CLI 的 `/plugins` 中完成刷新和安装。

## 排查

### Claude Code

```bash
claude plugin details <plugin>    # 查看已加载的 skill 清单与 token 开销
claude plugin marketplace list    # 确认 marketplace 已注册
```

### Codex

```bash
codex plugin marketplace list     # 确认 Codex marketplace 已注册
codex plugin list                 # 查看已安装的 plugin
```
