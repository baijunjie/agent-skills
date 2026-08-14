# Agent Skills

个人 agent skills 集合，遵循 [Agent Skills](https://agentskills.io) 开放格式，以 [Claude Code plugin marketplace](https://docs.anthropic.com/en/docs/claude-code/plugin-marketplaces) 形式分发。

## 安装

```bash
# 1. 添加 marketplace（一次性）
claude plugin marketplace add baijunjie/agent-skills

# 2. 安装需要的 plugin
claude plugin install dev@bjj-agent-skills
claude plugin install git@bjj-agent-skills

# 3. 重启 Claude Code
```

> 不要用 `claude plugin marketplace add <本地路径>` 指向工作副本——那样 skill 会强依赖该目录，一旦移动或删除全部失效。详见 [AGENTS.md](AGENTS.md)。

### 更新

```bash
claude plugin marketplace update
claude plugin update dev@bjj-agent-skills
claude plugin update git@bjj-agent-skills
```

改动本仓库后需先 `git push`，更新才拉得到。

## 可用 Skills

### `dev` — 开发流程

典型链路：`/dev:discuss` → `/dev:docs` → `/dev:exec` → `/dev:optimize` → `/dev:memory`。

| Skill | 说明 | 触发方式 |
|-------|------|----------|
| `/dev:discuss` | 问题讨论：只补上下文、给方案，不写代码 | 手动 |
| `/dev:coding` | 编写代码：先补上下文再动手，任务多时调度子代理 | 手动 |
| `/dev:docs` | 文档输出：把讨论结论整理成开发文档（只写设计，不写实现） | 手动 |
| `/dev:exec` | 按开发文档编号顺序执行开发，完成即打 `✅` 标记 | 手动 |
| `/dev:optimize` | 优化代码：复查逻辑遗漏、冗余代码、可优化点 | 手动 |
| `/dev:memory` | 开发记忆：开工前读 `docs/dev-memory/`，收尾时沉淀经验 | 手动 / 自动 |

### `git` — Git 规范

| Skill | 说明 | 触发方式 |
|-------|------|----------|
| `/git:commit` | 按 Conventional Commits 规范生成提交 | 手动 / 自动 |
| `/git:find-issues` | 在指定仓库中搜索相关 Issue 和 PR | 手动 / 自动 |

> **触发方式**说明：标「手动」的 skill 设置了 `disable-model-invocation: true`，只能由你显式 `/xxx` 调用，不会被模型自动触发——这类 skill 是流程编排指令，自动触发会造成干扰。其余 skill 在语境相关时也会被自动调用。

## 仓库结构

```
.claude-plugin/marketplace.json     # marketplace 定义，列出所有 plugin
plugins/<plugin>/
├── .claude-plugin/plugin.json      # plugin 元信息
└── skills/<skill>/SKILL.md         # skill 本体
```

新增 skill 的步骤见 [AGENTS.md](AGENTS.md)。
