# 分发与发布

本仓库 plugin 的分发方式与发布时的版本规则；面向要安装、调试、升版本或推送本仓库 plugin 的维护者与 agent，什么时候读见 AGENTS.md「什么时候读什么」。

## 分发

安装、更新与排查命令见 `README.md`。marketplace 名为 `bjj-agent-skills` 而非仓库名 `agent-skills`（后者是 Anthropic 保留名），Codex 沿用同一名字。开发调试本仓库时同样用 GitHub 源装 plugin，不要用本地目录源直接加载工作副本，原因见 `README.md`「安装」。

## 发布

发布 plugin 内容改动时，先同步提升该 plugin 三个 manifest（`plugin.json`、`.codex-plugin/plugin.json`、`.claude-plugin/plugin.json`）的 `version`，再提交推送；改 `tools/installer/` 后，生成物有变化的每个 plugin 都要升。两个宿主都以递增且三处一致的版本作为新版本边界（Claude Code 的 `plugin update` 版本不变就认为已是最新），不依赖 Codex 重装覆盖同版本内容的行为。

- 版本以已发布版本（`origin/main` 上的 `version`）为基准，相对它的连续改动只升一次；破坏性变更或新增能力升 minor，只改内容升 patch。未发布前已升过 patch、后续改动需要 minor 的，改成相对已发布版本升 minor。
- 已推送的提交怎么处理见 AGENTS.md「硬规则」。
- 推送后按 `README.md`「更新」一节刷新 marketplace 并更新 plugin，再用「排查」一节的命令确认加载的是新版本。
