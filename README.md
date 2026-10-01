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

### `dev` — 开发流程

典型链路：`dev:discuss` → `dev:optimize`。

| Skill | 说明 | 触发方式 |
|-------|------|----------|
| `dev:discuss` | 问题讨论：只补上下文、给方案，不写代码 | 手动 |
| `dev:optimize` | 优化代码：复查逻辑遗漏、冗余代码、可优化点 | 手动 |
| `dev:todo` | 检查 TODO：逐条查证前提与阻塞，分成已过时 / 可以处理 / 还不能处理 / 无法判定列表，再问用户是否清理、是否开工 | 手动 |

### `create` — 创建规范

| Skill | 说明 | 触发方式 |
|-------|------|----------|
| `create:skill-authoring` | Skill 编写规范：只写 agent 推不出来的规则，自包含不引用代码，给判断标准而非操作脚本 | 自动 |

### `setup-agent` — 安装 agent 的开发工作方式

把 agent 的开发工作方式（子代理分派、输出风格、项目工作流、改动检查、单元测试、项目文档、开发计划与 bug 工单）装进项目或用户级配置。
八个安装器各自独立安装；`workflow` 只编排已装进项目的专职 skill（`docs`、`unit-test`、`change-check` 装出的），宜最后装，增删这些 skill 后需重跑。

| Skill | 说明 | 作用域 | 触发方式 |
|-------|------|--------|----------|
| `setup-agent:bug` | 安装 `agent-bug-report` 与 `agent-bug-fix` skill：把缺陷记成 `docs/bugs/` 下只写事实的一次性工单；修复时先复现、定位根因，只改代码不改产品文档，验证通过即删工单。装出的 skill 会被自动触发，不装子代理、不挂指令文件 | 项目级（默认）+ 用户级 | 手动 |
| `setup-agent:change-check` | 安装 `agent-change-check` skill 加 `change-checker` 子代理：派子代理审查本次改动，只给意见不改文件；项目级安装时可补本项目的检查项，不挂指令文件 | 项目级（默认）+ 用户级 | 手动 |
| `setup-agent:docs` | 安装 `agent-docs` skill 加 `map-writer`、`product-writer`、`memory-writer` 子代理：开工前读总索引、项目地图与相关的产品文档、开发记忆，收尾时按需派子代理维护、主 agent 更新总索引，并规定代码注释怎么写、能引用哪些文档；不挂指令文件 | 项目级（默认）+ 用户级 | 手动 |
| `setup-agent:plan` | 安装 `agent-plan-write` 与 `agent-plan-exec` skill：把讨论定下的方案按里程碑写成 `docs/plans/` 下的开发计划文档，并按编号顺序执行、边做边勾，里程碑收尾固化进产品文档。装出的 skill 会被自动触发，不装子代理、不挂指令文件 | 项目级（默认）+ 用户级 | 手动 |
| `setup-agent:report-style` | 输出风格 `Concise+`，不装 skill：Claude Code 使用自定义 output style，Codex 将等价规则写入 `AGENTS.md` | 项目级（默认）+ 用户级 | 手动 |
| `setup-agent:subagents` | 安装分派子代理的规则（何时派、怎么交代、按难度选档）加 `mechanical`、`implement`、`investigate`、`architect` 四个通用子代理；规则写进指令文件，不装 skill | 项目级（默认）+ 用户级 | 手动 |
| `setup-agent:unit-test` | 安装 `agent-unit-test` skill 加 `test-writer` 子代理：沿用项目的单元测试框架（没有就问用户并协助安装），测试默认放独立目录，为改动文件补测试、只跑受影响的测试；不挂指令文件 | 项目级 | 手动 |
| `setup-agent:workflow` | 在项目指令文件里写入「工作流」一节：按已装进项目的 `agent-docs`、`agent-unit-test`、`agent-change-check` 写明开工前先了解项目上下文、交付前按补单元测试、静态检查、改动检查、文档更新的顺序自检，没装的步骤不写；并装上规范以后怎么改这一节的 skill。不装子代理 | 项目级 | 手动 |

### `setup-git` — 安装 Git 规范与流程

把 Git 相关的规范与流程装进项目或用户级配置，四个安装器各自独立。

| Skill | 说明 | 作用域 | 触发方式 |
|-------|------|--------|----------|
| `setup-git:commit` | 安装 `git-commit` skill：按 Conventional Commits 规范生成提交 | 项目级（默认）+ 用户级 | 手动 |
| `setup-git:find-issues` | 安装 `git-find-issues` skill：在指定仓库中搜索相关 Issue 和 PR | 项目级（默认）+ 用户级 | 手动 |
| `setup-git:pr` | 安装 `git-pr` skill：压平本地提交、推送并提 PR，建好后清理本地分支与 worktree；安装时确定默认的 PR 目标分支（查不到就问用户），调用时可另行指定 | 项目级 | 手动 |
| `setup-git:worktree` | 把「代码变更必须在独立 worktree + 独立分支上开发」这套流程写进指令文件，让 worktree 目录不进版本库，并装上拦截「合并时撤销目标分支已有改动」的回退闸门；常驻守护分支列表 `.githooks/branches` 随仓库提交；本地合并前先对齐远程目标分支 | 项目级 | 手动 |

### `setup-tools` — 安装开发辅助工具

装上开发辅助工具，两个安装器各自独立。

| Skill | 说明 | 作用域 | 触发方式 |
|-------|------|--------|----------|
| `setup-tools:codex-bridge` | 给 Codex 装上读取 Claude 规范的 `claude` skill：开工前盘点用户级与项目级的 Claude 配置，照 Claude 这套工具链继续开发 | 用户级 | 手动 |
| `setup-tools:cron` | 项目级 crontab 定时任务安装器：任务清单加安装 / 卸载脚本，改任务不用手写 crontab；指令文件里挂一行怎么改任务的说明 | 项目级 | 手动 |

### `setup-knowledge` — 安装知识类规范

装上知识类规范 skill。

| Skill | 说明 | 作用域 | 触发方式 |
|-------|------|--------|----------|
| `setup-knowledge:i18n-copy` | 安装 `knowledge-i18n-copy` skill：多语言 App 界面文案规范（各语言语体、破坏性操作与确认框、进行态、报错、括号空格、iOS / Android / Web 大小写、术语统一与多端同步）；项目级安装时在末尾补「本项目」一节（语种、资源位置、术语表等） | 项目级（默认）+ 用户级 | 手动 |

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
