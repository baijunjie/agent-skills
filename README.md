# Agent Skills

个人 agent skills 集合，遵循 [Agent Skills](https://agentskills.io) 开放格式，以 [Claude Code plugin marketplace](https://docs.anthropic.com/en/docs/claude-code/plugin-marketplaces) 形式分发。

## 安装

```bash
# 1. 添加 marketplace（一次性）
claude plugin marketplace add baijunjie/agent-skills

# 2. 安装需要的 plugin
claude plugin install dev@bjj-agent-skills
claude plugin install git@bjj-agent-skills
claude plugin install ai@bjj-agent-skills
claude plugin install setup@bjj-agent-skills
claude plugin install global-setup@bjj-agent-skills

# 3. 重启 Claude Code
```

> 不要用 `claude plugin marketplace add <本地路径>` 指向工作副本——那样 skill 会强依赖该目录，一旦移动或删除全部失效。详见 [AGENTS.md](AGENTS.md)。

### 更新

```bash
claude plugin marketplace update
claude plugin update dev@bjj-agent-skills
claude plugin update git@bjj-agent-skills
claude plugin update ai@bjj-agent-skills
claude plugin update setup@bjj-agent-skills
claude plugin update global-setup@bjj-agent-skills
```

改动本仓库后需先 `git push`，更新才拉得到。

## 可用 Skills

### `dev` — 开发流程

典型链路：`/dev:discuss` → `/dev:docs` → `/dev:exec` → `/dev:optimize`。

| Skill | 说明 | 触发方式 |
|-------|------|----------|
| `/dev:discuss` | 问题讨论：只补上下文、给方案，不写代码 | 手动 |
| `/dev:coding` | 编写代码：先补上下文再动手，任务多时调度子代理 | 手动 |
| `/dev:docs` | 文档输出：把讨论结论整理成开发文档（按里程碑拆分，只写设计不写实现） | 手动 |
| `/dev:exec` | 按开发文档编号顺序执行开发，边做边勾 checkbox；里程碑收尾把内容固化进产品文档后删除开发文档 | 手动 |
| `/dev:optimize` | 优化代码：复查逻辑遗漏、冗余代码、可优化点 | 手动 |

### `ai` — AI agent 规范

| Skill | 说明 | 触发方式 |
|-------|------|----------|
| `/ai:skill-authoring` | Skill 编写规范：只写 agent 推不出来的规则，自包含不引用代码，给判断标准而非操作脚本 | 手动 / 自动 |

### `git` — Git 规范

| Skill | 说明 | 触发方式 |
|-------|------|----------|
| `/git:commit` | 按 Conventional Commits 规范生成提交 | 手动 / 自动 |
| `/git:find-issues` | 在指定仓库中搜索相关 Issue 和 PR | 手动 / 自动 |

### `setup` — 项目级初始化

一次性执行，把通用规范落地成**项目自己的**、随仓库提交的配置。
**三个各自独立，装任意一个都能单独工作**——`docs` 与 `dev-memory` 把各自的收尾子代理
装进项目的 `.claude/agents/` 并随仓库提交，谁都不依赖谁，也不依赖 `global-setup`。

| Skill | 说明 | 触发方式 |
|-------|------|----------|
| `/setup:dev-memory` | 项目级 `dev-memory` skill + `memory-writer` 子代理：开工前读 `docs/dev-memory/`，收尾时派它判断值不值得记 | 手动 |
| `/setup:docs` | 项目级 `docs` skill + `doc-writer` 子代理：开工前读总索引、项目地图、产品文档三类正式文档建立上下文，收尾时派子代理维护 | 手动 |
| `/setup:git-worktree` | 把「代码变更必须在独立 worktree + 独立分支上开发」的流程写进项目的 `CLAUDE.md` / `AGENTS.md`，并让 `.gitignore` 忽略 worktree 目录 | 手动 |

### `global-setup` — 本机级初始化

一次性执行，装的是**跨项目、跨工具**共用的配置，落在 `~/` 下、不进任何仓库。
与 `setup` 分成两个 plugin 就是为了让作用域一眼可辨：**`/setup:` 写仓库，`/global-setup:` 写 home**。

| Skill | 说明 | 触发方式 |
|-------|------|----------|
| `/global-setup:report-style` | 自定义 output style `Concise+`（内置 `Concise` + 「要用户拍板的事项与疑问必须显式列出」+ 「不附和：不先肯定再转折」），真身同样放 `~/.config/agents/`，软链进各 Claude 配置目录。Claude Code 专属 | 手动 |
| `/global-setup:workflow` | 全局规则真身 `~/.config/agents/`（注释规范、提交信息、收尾自检 + 四个跨项目通用的子代理），软链进 Claude Code 与 Codex 的配置目录；换电脑重跑一次即复原 | 手动 |

> **触发方式**说明：标「手动」的 skill 设置了 `disable-model-invocation: true`，只能由你显式 `/xxx` 调用，不会被模型自动触发——这类 skill 是流程编排或一次性初始化指令，自动触发会造成干扰。其余 skill 在语境相关时也会被自动调用。

## 仓库结构

```
.claude-plugin/marketplace.json     # marketplace 定义，列出所有 plugin
plugins/<plugin>/
├── .claude-plugin/plugin.json      # plugin 元信息
└── skills/<skill>/SKILL.md         # skill 本体
```

新增 skill 的步骤见 [AGENTS.md](AGENTS.md)。
