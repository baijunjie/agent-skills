---
name: plugin-update
description: 把本机 Claude Code 与 Codex 里装的 bjj-agent-skills plugin 更新到最新版：先刷新 marketplace，再逐个更新已装的 plugin。用于"更新 bjj-agent-skills""bjj-agent-skills 发了新版，更新本地 plugin""把 Claude 和 Codex 的插件都更新一下"等场景。
---

# 更新 bjj-agent-skills plugin

两个宿主各做一遍，各宿主的命令如下：

| 宿主 | 刷新 marketplace | 列出已装的 | 更新一个 plugin |
|---|---|---|---|
| Claude Code | `claude plugin marketplace update bjj-agent-skills` | `claude plugin list --json` 里 `id` 以 `@bjj-agent-skills` 结尾的 | `claude plugin update <plugin>@bjj-agent-skills --scope <它的 scope> --json` |
| Codex | `codex plugin marketplace upgrade bjj-agent-skills` | `codex plugin list --marketplace bjj-agent-skills --json` 的 `installed` 数组 | `codex plugin add <plugin>@bjj-agent-skills`（对已装的就是升级） |

- 顺序：先列出已装的并记下版本，再刷新 marketplace，再更新；刷新会改变列出的结果，不刷新时更新命令又会认为已是最新，所以刷新失败的宿主整个跳过、不跑更新。
- 更新前后的版本都以已装副本为准：Claude Code 取 list 的结果；Codex 取 `${CODEX_HOME:-$HOME/.codex}/plugins/cache/bjj-agent-skills/<plugin>/` 下版本号最大的目录，list 里的版本可能来自 marketplace 快照。
- 只更新已装的 bjj-agent-skills plugin，不增删、不改装任何 plugin；新版里已没有的列进跳过。
- 已停用（`enabled` 为假）的 plugin 不更新，列进跳过：更新命令可能顺带把它重新启用。
- Claude Code 的 `user` scope 直接更新；`project`、`local` scope 的只在能确认装在当前项目时更新，确认不了的列给用户；`managed` 不动。
- 更新要求确认命令或授权时，跳过这个 plugin，把要确认的内容（Claude Code 的命令原文与 sha256）交给用户定；不要代为接受，任何时候都不要用 `-y`。Claude Code 下用户看过这条命令的原文与 sha256 后明确同意，才用 `--accept-command <sha256>` 重跑。
- 某个 plugin 或某个宿主失败、跳过不影响其它。
- 拿不准就汇报。

## 收尾

在最终回复里按宿主列出每个 plugin 更新前后的版本，以及跳过的宿主、plugin 与原因；再告知用户：

- 有版本变了的：新版本要重启 Claude Code、开新的 Codex 会话后才生效。
- 有 `setup-*` 版本变了的：已装进用户级或项目级的 skill 与子代理不会随之更新，要在新会话里用 `batch-setup:user-reinstall` / `batch-setup:project-reinstall` 按新模板重装，本次不做。
- 只更新了当前环境的配置目录（`CLAUDE_CONFIG_DIR`、`CODEX_HOME` 指向的那份）；还有别的配置目录的，要在那个环境里再跑一次。
