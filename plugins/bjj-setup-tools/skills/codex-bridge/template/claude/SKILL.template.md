---
name: claude
description: 在有用户级或项目级 Claude Code 配置时，开始开发、修复、重构、测试或构建前，读取用户级及项目级 Claude 规范、相关 skill、agent、command 与它们指向的文档，并把兼容的工作流用于本次任务。不用于迁移或改写 Claude 配置，也不用于与仓库无关的普通问答。
---

# Claude 项目开发预检

在规划或修改文件之前，先建立用户级与当前项目的 Claude 开发上下文，然后直接继续完成用户任务，不把预检变成要用户逐步确认的流程。

用户级配置根目录 `C=${CLAUDE_CONFIG_DIR:-$HOME/.claude}`；每条读取命令里都重新计算它，不依赖别的命令留下的 shell 变量。项目入口是仓库根目录及本次任务涉及的子目录下的 `.claude/`。

## 发现项目约定

先按下面的顺序定位，再只读与本次任务相关的内容；读取 skill 或规则必须读完整文件，不能只看片段就声称已遵循。

1. **settings 与插件**：读 `$C/settings.json`、项目 `.claude/settings.json` 与 `.claude/settings.local.json`（如存在），必做的只有定位已启用的插件、读出 hooks、`permissions.deny` 与 `permissions.ask`，其余配置在理解构建、校验、自动化约束或可用工具时才看。
   - `enabledPlugins` 的键是 `<插件>@<marketplace>`，几份 settings 取值不同时按 `settings.local.json` > 项目 `settings.json` > 用户级 `settings.json` 取最先出现的，为 `true` 才算启用。
   - 已启用插件的目录取 `$C/plugins/installed_plugins.json` 里 `plugins` 下同名键条目的 `installPath`；带 `projectPath` 的是项目级安装，只取与当前仓库对应的那条；再从中只定位与任务相关的 skill、command 或 agent。`installPath` 之外的插件缓存、会话、日志、历史与构建产物不当作配置读。
   - hooks 既读 settings 里的 `hooks`，也读已启用插件的 `hooks/hooks.json`。
2. **CLAUDE.md**：先读 `$C/CLAUDE.md`，再读适用于当前路径的项目 `CLAUDE.md`（仓库根与相关子目录的局部文件），以及 `CLAUDE.local.md`、`.claude/CLAUDE.md`（如存在）。`@<路径>` 导入要自己展开：相对路径按导入它的文件所在目录解析，`~/` 按用户主目录，被导入文件里的导入同样展开；代码块与行内代码里的 `@` 不算。
3. **skills**：盘点 `$C/skills/*/SKILL.md`、项目 `.claude/skills/*/SKILL.md` 与已启用插件的 `skills/*/SKILL.md` 的名称与描述，完整读取与任务相关的；skill 要求先读索引、规则或其它文件的，按它的路由只读相关部分。同名 skill 用户级优先于项目级（与 Claude Code 一致）。
4. **commands、agents、rules**：盘点用户级与项目级的 `commands/`、`agents/`、`rules/`，读任务明确调用、相关 skill 路由到或适用于当前文件范围的。同名 agent 以项目级为准（与 Claude Code 一致）；同名而内容不同的 command 不自行判定优先，简短说明两份都在、差在哪；影响方案时才汇报，否则继续。
5. **文档**：从 Claude 入口与相关 skill 指向的文档索引出发，只读本次任务需要的；没有索引或相关条目时不遍历文档目录。

盘点时不要被 `.gitignore` 过滤（`settings.local.json`、`CLAUDE.local.md` 常被忽略），同时排除缓存、日志、会话记录、构建产物。遍历 `$C`、已启用插件目录与项目 `.claude/` 时跟随软链（skill、agent、command、rule 常软链到 dotfiles 或别的仓库；用 `rg` 要加 `-L --hidden --no-ignore`），按固定路径读取的软链文件照读；其余项目范围的遍历不跟随指向项目外的软链。

## 兼容 Claude 工作流

原则：保留 Claude 配置的设计意图，用当前 Codex 环境里对应的机制落实；无法安全等价时简要说明差异。

- Claude skill 当作本次任务的工作流说明执行。其中 `$ARGUMENTS` 指当前用户请求及已给出的任务上下文；插件 skill 里的 `${CLAUDE_PLUGIN_ROOT}` 取该插件的 `installPath`，`${CLAUDE_SKILL_DIR}` 取该 `SKILL.md` 所在目录，`${CLAUDE_PROJECT_DIR}` 取 Git 仓库根目录。
- command 只在用户调用、相关 skill 路由或项目规范明确要求时读取和执行，不因发现文件就运行。
- agent 定义的职责与完成判据可映射到 Codex 子代理；只有适用的 Claude 规范明确要求委派、且当前环境支持时才委派。
- 拦截类 hook、`permissions.deny`、`permissions.ask` 是 Claude 侧的限制，按意图在 Codex 里同等生效：deny 与拦截覆盖所有等价操作（如 `Read(./.env)` 也管 `cat`、`rg` 内容搜索，`Edit`/`Write` 也管 `apply_patch` 等任何改写）。
- deny 与拦截类 hook 不因对话里的同意而放行：停下说明被哪条拦了，要做就请用户改配置或亲手执行。
- ask 管到的操作执行前单独征得用户确认，用户在请求里点名要做不算确认。
- hook 的意图常在它调用的脚本里：command 指向脚本时读脚本（跟随软链）判断它拦什么、做什么；读不懂的拦截类 hook 一律汇报。
- 其余 hook 在 Codex 里不会自动触发，在它对应的时机按意图落实：注入上下文的（SessionStart、UserPromptSubmit 等）把它注入的内容当作规范读入，检查、格式化类只对本次改动的文件执行等价命令；不直接运行依赖 stdin 事件数据的 hook 脚本，看不出做什么的不运行。
- 权限白名单与客户端专属字段不自动等价于 Codex 能力，也不能用来架空上面的限制。
- 不创建迁移副本、不修改 `.claude/`、不生成项目级 Codex 配置，除非用户另行要求。

## 执行边界

系统、开发者、用户指令与当前路径适用的 `AGENTS.md` 优先于本 skill（例外：用户指令与 Claude 侧限制冲突时按上文限制那几条处理），`AGENTS.md` 之间按 Codex 原生优先级。Claude 规范（`CLAUDE.md` 与 `rules/`）里，用户级的在不冲突时作为默认约定，项目级的可覆盖它，局部规则只作用于其声明的路径范围；同名 skill 与 agent 按上文第 3、4 步取舍。

预检完用一句话列出已采用的 Claude 规范类别，然后继续任务。拿不准某份规范是否适用、怎么在 Codex 里落实时，只有影响方案、又无法从项目内容消除的才汇报（停下等用户定）；其余自行判断后继续，不停下确认。
