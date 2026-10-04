# Agent Skills

个人 agent skills 集合，遵循 [Agent Skills](https://agentskills.io) 开放格式，同时以 Claude Code 与 Codex plugin marketplace 形式分发。

## 安装

### Claude Code

```bash
# 1. 添加 marketplace（一次性）
claude plugin marketplace add baijunjie/agent-skills

# 2. 安装需要的 plugin
claude plugin install dev@bjj-agent-skills
claude plugin install create@bjj-agent-skills
claude plugin install setup-agent@bjj-agent-skills
claude plugin install setup-git@bjj-agent-skills
claude plugin install setup-tools@bjj-agent-skills
claude plugin install setup-knowledge@bjj-agent-skills
claude plugin install batch-setup@bjj-agent-skills

# 3. 重启 Claude Code
```

> 必须用 GitHub 源安装，不要用 `claude plugin marketplace add <本地路径>`：本地源会让 marketplace 直接指向该目录，目录一旦移动或删除，所有 skill 都会报 `failed to load: cache-miss`。

### Codex

```bash
# 1. 添加 marketplace（一次性）
codex plugin marketplace add baijunjie/agent-skills

# 2. 安装需要的 plugin（也可在 Codex CLI 的 /plugins 中安装）
codex plugin add dev@bjj-agent-skills
codex plugin add create@bjj-agent-skills
codex plugin add setup-agent@bjj-agent-skills
codex plugin add setup-git@bjj-agent-skills
codex plugin add setup-tools@bjj-agent-skills
codex plugin add setup-knowledge@bjj-agent-skills
codex plugin add batch-setup@bjj-agent-skills

# 3. 开启新会话
```

Codex plugin 不适用于 IDE extension；在 IDE 中可使用 `skill-installer` 或安装独立 skill。

## 更新

### Claude Code

```bash
# 1. 刷新 marketplace
claude plugin marketplace update

# 2. 更新需要的 plugin
claude plugin update dev@bjj-agent-skills
claude plugin update create@bjj-agent-skills
claude plugin update setup-agent@bjj-agent-skills
claude plugin update setup-git@bjj-agent-skills
claude plugin update setup-tools@bjj-agent-skills
claude plugin update setup-knowledge@bjj-agent-skills
claude plugin update batch-setup@bjj-agent-skills

# 3. 重启 Claude Code
```

若为不同场景设置了多个 `CLAUDE_CONFIG_DIR`，每个都是独立的用户级安装环境，要对每个分别刷新 marketplace 和更新 plugin。

### Codex

```bash
# 1. 刷新 marketplace
codex plugin marketplace upgrade bjj-agent-skills

# 2. 对需要更新的 plugin 重新执行安装命令（也可在 Codex CLI 的 /plugins 中完成）
codex plugin add dev@bjj-agent-skills
codex plugin add create@bjj-agent-skills
codex plugin add setup-agent@bjj-agent-skills
codex plugin add setup-git@bjj-agent-skills
codex plugin add setup-tools@bjj-agent-skills
codex plugin add setup-knowledge@bjj-agent-skills
codex plugin add batch-setup@bjj-agent-skills

# 3. 开启新会话
```

### 已装进项目或用户级的内容

`setup-*` 安装器可重复运行：plugin 更新后，对已装过的项目（或用户级配置）再运行一次对应的安装器，就按新模板重装。
`plugin update` 只更新安装器本身，不会改动已装进项目或用户级的内容。
重装时，安装时填写的定制位置（如默认的 PR 目标分支、文档目录、项目专属的检查项）会保留（能从项目现状重新确定的按现状更新），装出的文件与指令文件标记范围内的其它手改会被覆盖。

## 可用 Skills

下表的 `plugin:skill` 是 skill 标识；显式调用时，Claude Code 使用 `/plugin:skill`，Codex 使用 `$plugin:skill`。

> **触发方式**：「手动」只能显式调用（Claude Code `/plugin:skill`，Codex `$plugin:skill`），不会被模型自动触发；「自动」在语境相关时也会被调用。
>
> **作用域**：「项目级」只装进当前项目、随仓库提交；「项目级（默认）+ 用户级」默认装进当前项目，明确要求时改装进用户级配置、对当前用户的所有项目生效；「用户级」只装进当前用户的配置。
>
> **说明**：只概括装什么、解决什么问题；安装器会改指令文件（`CLAUDE.md` / `AGENTS.md`）或装子代理的，说明里会点出，没点出的就不做这两件事。

### `dev` — 开发流程

典型链路：`dev:discuss` → `dev:optimize`。

| Skill | 说明 | 触发方式 |
|-------|------|----------|
| `dev:choose` | 选择式提问：需要用户决策的内容一律以选项提问 | 手动 |
| `dev:discuss` | 问题讨论：只补上下文、给方案，不写代码 | 手动 |
| `dev:optimize` | 优化代码：复查逻辑遗漏、冗余代码与可优化点 | 手动 |
| `dev:todo` | 逐条查证代码里的 TODO 是否过时、能否处理，再问用户是否清理、是否开工 | 手动 |

### `create` — 创建规范

| Skill | 说明 | 触发方式 |
|-------|------|----------|
| `create:skill-authoring` | Skill 编写规范：只写 agent 推不出来的规则，定原则与边界、细节交给 agent | 自动 |

### `setup-agent` — 安装 agent 的开发工作方式

把 agent 的开发工作方式（子代理分派、输出风格、项目工作流、改动检查、单元测试、项目文档、开发计划与 bug 工单）装进项目或用户级配置。
八个安装器各自独立安装；`workflow` 只编排已装进项目的专职 skill（`docs`、`unit-test`、`change-check` 装出的），宜最后装，增删这些 skill 后需重跑。

| Skill | 说明 | 作用域 | 触发方式 |
|-------|------|--------|----------|
| `setup-agent:bug` | 把缺陷记成只写事实的一次性工单，修复时先复现、定位根因再改 | 项目级（默认）+ 用户级 | 手动 |
| `setup-agent:change-check` | 交付前派子代理审查本次改动、只给意见不改文件；装 `change-checker` 子代理 | 项目级（默认）+ 用户级 | 手动 |
| `setup-agent:docs` | 开工前读、收尾时维护项目地图、产品文档与开发记忆，并规范代码注释；装三个文档写作子代理 | 项目级（默认）+ 用户级 | 手动 |
| `setup-agent:plan` | 把方案按里程碑写成开发计划文档并按序执行 | 项目级（默认）+ 用户级 | 手动 |
| `setup-agent:report-style` | 简洁的回答风格 `Concise+`，安装时选回答语言：Claude Code 装成输出风格，Codex 写进 `AGENTS.md` 并在 `config.toml` 开启提问工具 | 项目级（默认）+ 用户级 | 手动 |
| `setup-agent:subagents` | 把何时、如何分派子代理的规则写进指令文件，并装四个按难度分档的通用子代理 | 项目级（默认）+ 用户级 | 手动 |
| `setup-agent:unit-test` | 沿用项目现有的测试框架为改动补单元测试、只跑受影响的测试；装 `test-writer` 子代理 | 项目级 | 手动 |
| `setup-agent:workflow` | 在指令文件里写入「工作流」一节，按已装的专职 skill 编排开工前与交付前的步骤 | 项目级 | 手动 |

### `setup-git` — 安装 Git 规范与流程

把 Git 相关的规范与流程装进项目或用户级配置，四个安装器各自独立。

| Skill | 说明 | 作用域 | 触发方式 |
|-------|------|--------|----------|
| `setup-git:commit` | 按 Conventional Commits 规范生成提交 | 项目级（默认）+ 用户级 | 手动 |
| `setup-git:find-issues` | 在指定仓库中搜索与问题相关的 Issue 和 PR | 项目级（默认）+ 用户级 | 手动 |
| `setup-git:pr` | 压平本地提交、rebase 到最新目标分支、推送并提 PR，建好后清理本地分支与 worktree，并装上推送时拦下撤销目标分支改动的回退闸门 | 项目级 | 手动 |
| `setup-git:worktree` | 把「开发在独立 worktree 加独立分支上完成」写成项目规则，合并回目标分支的操作步骤装成 `git-worktree` skill，并装上拦截改写已发布历史、撤销已有改动的回退闸门 | 项目级 | 手动 |

### `setup-tools` — 安装开发辅助工具

装上开发辅助工具，两个安装器各自独立。

| Skill | 说明 | 作用域 | 触发方式 |
|-------|------|--------|----------|
| `setup-tools:codex-bridge` | 让 Codex 开工前读取 Claude 的用户级与项目级配置，照 Claude 那套工具链继续开发 | 用户级 | 手动 |
| `setup-tools:cron` | 用一份任务清单加安装 / 卸载脚本管理项目的 crontab 定时任务；指令文件里挂一行说明 | 项目级 | 手动 |

### `setup-knowledge` — 安装知识类规范

装上知识类规范 skill。

| Skill | 说明 | 作用域 | 触发方式 |
|-------|------|--------|----------|
| `setup-knowledge:i18n-copy` | 多语言 App 界面文案规范 | 项目级（默认）+ 用户级 | 手动 |

### `batch-setup` — 一键初始化项目

把几个安装器按固定顺序一次装完，不自己写文件；那些安装器禁止模型调用，所以读它们的 `SKILL.md` 照做，要求对应 plugin 已装。

| Skill | 说明 | 作用域 | 触发方式 |
|-------|------|--------|----------|
| `batch-setup:project-init` | 初始化项目：按序读取并执行 `setup-agent` 的 `subagents`、`docs`、`change-check`、`bug`、`plan`，`setup-git` 的 `worktree`、`pr`，最后 `setup-agent` 的 `workflow`，不含 `report-style` 与 `unit-test` | 项目级 | 手动 |

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
