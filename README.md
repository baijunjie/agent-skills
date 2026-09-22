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
claude plugin install git@bjj-agent-skills
claude plugin install setup@bjj-agent-skills
claude plugin install setup-user@bjj-agent-skills

# 3. 重启 Claude Code
```

> 不要用 `claude plugin marketplace add <本地路径>` 指向工作副本——那样 skill 会强依赖该目录，一旦移动或删除全部失效。详见 [AGENTS.md](AGENTS.md)。

### Claude Code 更新

```bash
claude plugin marketplace update
claude plugin update dev@bjj-agent-skills
claude plugin update create@bjj-agent-skills
claude plugin update git@bjj-agent-skills
claude plugin update setup@bjj-agent-skills
claude plugin update setup-user@bjj-agent-skills
```

维护者发布 plugin 内容改动时，需同步提升该 plugin 的三份 manifest 版本并 `git push`；具体要求见 [AGENTS.md](AGENTS.md)「发布改动」。

### Codex

```bash
# 1. 添加 marketplace（一次性）
codex plugin marketplace add baijunjie/agent-skills

# 2. 安装需要的 plugin（也可在 Codex CLI 的 /plugins 中安装）
codex plugin add dev@bjj-agent-skills
codex plugin add create@bjj-agent-skills
codex plugin add git@bjj-agent-skills
codex plugin add setup@bjj-agent-skills
codex plugin add setup-user@bjj-agent-skills

# 3. 开启新会话
```

`setup-user` 是用户级 scope 的双宿主 plugin；其中的 `codex-bridge` 目标宿主是 Codex，用于安装 Claude 配置预检能力。Codex plugin 不适用于 IDE extension；在 IDE 中可使用 `skill-installer` 或安装独立 skill。

### Codex 更新

```bash
# 1. 刷新 marketplace
codex plugin marketplace upgrade bjj-agent-skills

# 2. 对需要更新的 plugin 重新执行安装命令
codex plugin add dev@bjj-agent-skills
codex plugin add create@bjj-agent-skills
codex plugin add git@bjj-agent-skills
codex plugin add setup@bjj-agent-skills
codex plugin add setup-user@bjj-agent-skills

# 3. 开启新会话
```

## 可用 Skills

下表的 `plugin:skill` 是 skill 标识；显式调用时，Claude Code 使用 `/plugin:skill`，Codex 使用 `$plugin:skill`。

### `dev` — 开发流程

典型链路：`dev:discuss` → `dev:plan-write` → `dev:plan-exec` → `dev:optimize`。

Bug 链路：`dev:bug-report` → `dev:bug-fix`；口头描述的缺陷可以直接用 `dev:bug-fix`。

| Skill | 说明 | 触发方式 |
|-------|------|----------|
| `dev:discuss` | 问题讨论：只补上下文、给方案，不写代码 | 手动 |
| `dev:plan-write` | 编写开发计划文档：把讨论结论按里程碑拆分写进 `docs/plans/`，只写设计不写实现 | 手动 |
| `dev:plan-exec` | 按开发计划文档编号顺序执行开发，边做边勾 checkbox；里程碑收尾把内容固化进产品文档后删除计划文档 | 手动 |
| `dev:optimize` | 优化代码：复查逻辑遗漏、冗余代码、可优化点 | 手动 |
| `dev:todo` | 检查 TODO：逐条查证前提与阻塞，分成已过时 / 可以处理 / 还不能处理 / 无法判定列表，再问用户是否清理、是否开工 | 手动 |
| `dev:bug-report` | 创建 bug 工单：把缺陷整理成 `docs/bugs/` 下的规范工单，只写查证过的事实；工单一次性，修完即删 | 手动 |
| `dev:bug-fix` | 修复 bug：指定工单或自己挑一个，先复现再定位根因；只改代码不改产品文档，要改产品设计先问用户，验证通过即删工单 | 手动 |

### `create` — 创建规范

| Skill | 说明 | 触发方式 |
|-------|------|----------|
| `create:skill-authoring` | Skill 编写规范：只写 agent 推不出来的规则，自包含不引用代码，给判断标准而非操作脚本 | 手动 / 自动 |

### `git` — Git 规范

| Skill | 说明 | 触发方式 |
|-------|------|----------|
| `git:commit` | 按 Conventional Commits 规范生成提交 | 手动 / 自动 |
| `git:find-issues` | 在指定仓库中搜索相关 Issue 和 PR | 手动 / 自动 |

### `setup` — 初始化

一次性执行，把通用规范落地成**随仓库提交的项目配置**。
默认全都装进当前项目；`report-style` 与 `workflow` 另带「用户级安装」一节，
用户明确要求安装到当前用户环境时才走那条路。
**六个各自独立，装任意一个都能单独工作**——带子代理的那几个各装各的，谁都不依赖谁，
也不依赖 `setup-user`。

| Skill | 说明 | 触发方式 |
|-------|------|----------|
| `setup:cron` | 项目级 crontab 定时任务安装器：任务清单加安装 / 卸载脚本，改任务不用手写 crontab | 手动 |
| `setup:dev-memory` | 项目级 `dev-memory` skill 加 `memory-writer` 子代理：开工前读项目记忆，收尾时派它判断值不值得记 | 手动 |
| `setup:docs` | 项目级 `docs` skill 加 `doc-writer` 子代理：开工前读总索引、项目地图、产品文档三类正式文档建立上下文，收尾时派子代理维护 | 手动 |
| `setup:git-worktree` | 把「代码变更必须在独立 worktree + 独立分支上开发」这套流程写成项目规则，并让 worktree 目录不进版本库 | 手动 |
| `setup:report-style` | 输出规范 `Concise+`：Claude Code 使用自定义 output style，Codex 将等价规则写入 `AGENTS.md`；可选安装到用户级配置 | 手动 |
| `setup:workflow` | 通用规则（注释规范、提交信息、分派子代理、交付前自检）加五个通用子代理；可选安装到用户级配置 | 手动 |

### `setup-user` — 用户级初始化

只放**安装到当前用户配置、装进仓库没有意义**的事。
其余初始化 skill 一律在 `setup` 里；只给当前用户安装时，由它们各自的「用户级安装」一节负责。

| Skill | 说明 | 触发方式 |
|-------|------|----------|
| `setup-user:codex-bridge` | 给 Codex 装上读取 Claude 规范的 `claude` skill：开工前盘点用户级与项目级的 Claude 配置，照 Claude 这套工具链继续开发 | 手动 |

> **触发方式**说明：标「手动」的 skill 设置了 `disable-model-invocation: true`。进入 Codex marketplace 的 skill 会在 `agents/openai.yaml` 中映射为 `allow_implicit_invocation: false`；它们不会被模型自动触发——这类 skill 是流程编排或一次性初始化指令，自动触发会造成干扰。其余 skill 在语境相关时也会被自动调用。

## 仓库结构

```
.claude-plugin/marketplace.json     # Claude Code marketplace 定义，保留全部 plugin
.agents/plugins/marketplace.json     # Codex marketplace 定义，保留全部 plugin
plugins/<plugin>/                    # 同时分发到 Claude Code 与 Codex
├── plugin.json                       # Codex plugin 元信息
├── .codex-plugin/plugin.json         # Codex plugin 安装清单
├── .claude-plugin/plugin.json        # Claude Code plugin 元信息
└── skills/<skill>/SKILL.md           # skill 本体
```

新增 skill 的步骤见 [AGENTS.md](AGENTS.md)。
