# Agent Skills

个人 agent skills 仓库。以 Claude Code 与 Codex plugin marketplace 形式分发，skill 本身遵循 [Agent Skills 规范](https://agentskills.io/specification)，以便被其它支持该标准的工具复用。

## 结构

```
.claude-plugin/marketplace.json     # Claude Code marketplace 定义，列出所有 plugin
.agents/plugins/marketplace.json    # Codex marketplace 定义，列出所有 plugin
docs/                                # 面向维护者，不随 plugin 分发
├── decisions.md                      # 已定决策与不变量
├── checklist.md                      # 检查清单，怎么用见「什么时候读什么」的总则
├── authoring.md                      # 新增 skill 与 plugin、frontmatter、参数传递、附带资源与共享模板
├── installers.md                     # 安装器的命名与归属、生成、源文件契约
└── release.md                        # 分发与发布、版本规则
tools/installer/                     # 安装器 SKILL.md 的生成机制，不随 plugin 分发
├── build.py                          # 生成与校验脚本，INSTALLERS 在这里登记
├── sources/<领域>-<skill>.md         # 安装器源文件
└── fragments/<片段名>.md             # 安装器公共片段
tools/tests/                         # 仓库级回归测试，不随 plugin 分发
plugins/<plugin>/                    # 每个 plugin 都同时分发到 Claude Code 与 Codex
├── plugin.json                       # Codex plugin 元信息
├── .codex-plugin/plugin.json         # Codex plugin 安装清单
├── .claude-plugin/plugin.json        # Claude Code plugin 元信息
├── scripts/                          # 同一 plugin 内多个 skill 共用的资源（可选）
└── skills/<skill>/
    ├── SKILL.md                      # skill 本体；setup-* 下的由 tools/installer 生成
    ├── agents/openai.yaml            # Codex 的调用策略与 UI（可选）
    └── template/                     # 安装器要装出去的模板，按装出后的目录形态放（可选）
```

Plugin 名即调用前缀：`plugins/dev/skills/discuss/SKILL.md` 在 Claude Code 中对应 `/dev:discuss`，在 Codex 中对应 `$dev:discuss`。

## 硬规则

违反了会造成不可逆的损失，或者不报错、难发现。

- 不在真实仓库里做 git 实验、不动真实 crontab；具体约束见 `tools/tests/README.md`「安全设计」的「实验与危险命令」。
- 已推送的提交不 amend、不强推，对它的整改另起提交：改写已推送的历史会让别处的 clone 与 marketplace 快照对不上。
- `setup-*` 下的安装器 `SKILL.md` 由 `tools/installer/build.py` 从源文件 `sources/<领域>-<skill>.md` 与公共片段 `fragments/*.md` 生成，生成物提交进仓库，**不得手改**。怎么生成与校验见 `docs/installers.md`「生成」。
- 指令文件（`CLAUDE.md` / `AGENTS.md`）里开工前与交付前的工作流只写在「工作流」一节，只由 `setup-agent:workflow` 写入；其它安装器与装出的 skill 不得自己往指令文件里写工作流内容。

## 什么时候读什么

总则：改本仓库任何文件前先读 `docs/checklist.md`，动手时对照；交付前、复核时由子代理按它审查。

| 什么时候 | 读什么 |
|---|---|
| 实现或复核任何改动前；要动的东西可能是已定议题 | `docs/decisions.md`（已定决策、不变量与已知边界及其理由以它为准，怎么对照见 `docs/checklist.md`「动手前」） |
| 要跑实验、测试或任何会改 git / crontab 状态的命令前 | `tools/tests/README.md`「安全设计」的「实验与危险命令」 |
| 新增 skill（运行时 skill 或安装器）：写 SKILL.md、在 `README.md` 表格补行、在 `.claude/settings.json` 的 `permissions.allow` 登记、建 `agents/openai.yaml` | `docs/authoring.md`「新增 skill」；安装器另读 `docs/installers.md` |
| 新增 plugin，或改 plugin 的 `description`、`.codex-plugin/plugin.json` 的 `interface` 文案、两个 marketplace 的 `plugins` 数组 | `docs/authoring.md`「新增 plugin」 |
| 新增安装器或改它在 `INSTALLERS` 里的 `scope`（要同步 manifest 与 marketplace 的作用域摘要、`README.md` 的作用域列与安装器个数） | `docs/authoring.md`「新增 skill」「新增 plugin」、`docs/installers.md`「命名与归属」 |
| 改 `README.md` 的 skill 索引表、`.claude/settings.json` 的 `permissions.allow` | `docs/authoring.md`「新增 skill」 |
| 写或改 SKILL.md 的 frontmatter | `docs/authoring.md`「Frontmatter」 |
| skill 要接收调用参数 | `docs/authoring.md`「参数传递」 |
| skill 引用自己附带的脚本、模板；多个 skill 共用资源；改 Agent / 子代理模板、输出风格模板，或新增、改 `plugins/setup-agent/scripts/` 下的渲染脚本 | `docs/authoring.md`「附带资源与共享模板」 |
| 给安装器或装出的 skill 定名、定归属的 plugin、定作用域 | `docs/installers.md`「命名与归属」 |
| 写或改安装器源文件（`tools/installer/sources/`）、片段（`tools/installer/fragments/`）、`build.py` 的 `INSTALLERS`、安装器的 `template/` 或 `agents/openai.yaml` | `docs/installers.md`「生成」「源文件契约」 |
| 改 `build.py` 的校验 | `docs/installers.md`「源文件契约」、`docs/checklist.md`「改动后」、`tools/tests/README.md` |
| 改闸门（`plugins/setup-git/scripts/githooks/`）、cron 模板、渲染脚本或 `project-root` 片段；新增、选跑测试用例或套件 | `tools/tests/README.md`、`docs/checklist.md`「改动后」 |
| 升 manifest 的 `version`、发布、推送，或推送后更新已装的 plugin | `docs/release.md`「发布」 |
| 安装或调试本仓库的 plugin、改 marketplace 名 | `docs/release.md`「分发」 |
| 复核本仓库的改动 | 整份 `docs/checklist.md` |
| 整改复核意见 | `docs/checklist.md`「复核」 |
