---
name: claude
description: 在有用户级或项目级 Claude Code 配置时，开始开发、修复、重构、测试或构建前，读取用户级及项目级 Claude 规范、相关 skill、agent、command 与它们指向的文档，并把兼容的工作流用于本次任务。不用于迁移或改写 Claude 配置，也不用于与仓库无关的普通问答。
---

# Claude 项目开发预检

在规划或修改文件之前，先建立用户级与当前项目的 Claude 开发上下文，然后直接继续完成用户任务。不要把预检变成要求用户逐步确认的流程。

用户级配置根目录由 `C=${CLAUDE_CONFIG_DIR:-$HOME/.claude}` 确定。下文的 `C` 只是该路径的记号；执行任何读取命令时都先在该命令中重新计算它，不依赖其它步骤残留的 shell 变量。

## 发现项目约定

1. 确定当前工作目录、Git 仓库根目录，以及本次任务实际涉及的子目录。用户级入口是 `C`；项目入口是仓库及相关子目录的 `.claude/`。不要沿软链接进入项目外部。
2. 读取 `$C/settings.json` 与项目 `.claude/settings.json`（以及 `.claude/settings.local.json`，如存在），必做的只有两件：定位已启用的插件，以及读出 hooks；其余配置仅在理解构建、校验、自动化约束或可用工具确有必要时再看。`enabledPlugins` 的键为 `<插件>@<marketplace>`，同一个键在几份 settings 里取值不同时，按 `settings.local.json` > 项目 `settings.json` > 用户级 `settings.json` 取最先出现的值，为 `true` 才算启用。按 `$C/plugins/installed_plugins.json` 里 `plugins` 下同名键的条目取 `installPath` 定位已启用插件的目录——带 `projectPath` 的是项目级安装，只取与当前仓库对应的那条；再从中只定位与任务相关的 skill、command 或 agent，不把 `installPath` 之外的插件缓存、会话、日志、历史或构建产物当作配置读取。hooks 既要读 settings 里的 `hooks`，也要读已启用插件自带的 `hooks/hooks.json`。
3. 先读取 `$C/CLAUDE.md`（如存在），再查找并读取适用于当前路径的项目 `CLAUDE.md`，包括仓库根目录与相关子目录中的局部文件，以及 `CLAUDE.local.md`、`.claude/CLAUDE.md`（如存在）。CLAUDE.md 中 `@<路径>` 形式的导入要自己展开读取：相对路径按导入它的文件所在目录解析，`~/` 开头的按用户主目录解析，被导入的文件里的导入同样展开；代码块与行内代码里的 `@` 不算导入。
4. 同时盘点 `$C/skills/*/SKILL.md`、项目 `.claude/skills/*/SKILL.md` 与已启用插件的 `skills/*/SKILL.md`（插件按第 2 步定位）的名称与描述。选择与本次任务相关的 skill，并完整读取其 `SKILL.md`；若其中要求先读索引、规则或其它文件，继续按它的路由只读取相关内容。两层有同名 skill 时与 Claude Code 一致（同名 skill 用户级优先于项目级）。
5. 盘点用户级与项目级的 `commands/`、`agents/`、`rules/`。读取任务明确调用、相关 skill 路由或适用于当前文件范围的内容。同名的 `agents/` 定义以项目级为准，与 Claude Code 一致；`commands/` 两层同名且内容不同时不要自行判定哪份优先，简短说明两份都在、差在哪，影响方案时再询问用户；`rules/` 按「执行边界」处理。
6. 从用户级或项目 Claude 入口、以及相关 skill 指向的文档索引开始，只读取本次任务需要的文档。没有索引或相关条目时，不要为了“完整”而遍历文档目录。

优先使用 `rg --files --hidden --no-ignore` 做盘点，并显式排除缓存、日志、会话记录、构建产物及项目外链接；插件缓存仅用于定位已启用插件的可复用工具链。读取 skill 或规则时必须读取完整文件，不能只看片段后声称已遵循。

## 兼容 Claude 工作流

- 把用户级、项目及插件的 Claude skill 作为本次任务的工作流说明执行，其中的 `$ARGUMENTS` 表示当前用户请求及已给出的任务上下文；插件 skill 中的 `${CLAUDE_PLUGIN_ROOT}` 取该插件的 `installPath`，`${CLAUDE_SKILL_DIR}` 取该 `SKILL.md` 所在目录，`${CLAUDE_PROJECT_DIR}` 取 Git 仓库根目录。
- Claude command 只在用户调用、相关 skill 路由或项目规范明确要求时读取和执行，不因发现文件就自动运行。
- Claude agent 定义表达的职责和完成判据可以映射到 Codex 子代理；只有适用的 Claude 规范（用户级或项目级）明确要求委派、且当前环境支持时才委派。
- Claude hooks（settings 与插件 `hooks/hooks.json` 中的）声明的质量门槛、格式化或检查命令应在适用时执行；不要假定 Claude hook 已在 Codex 中自动注册，也不要仅因读取配置就运行未知脚本。
- Claude 的权限白名单、工具名、模型名和客户端专属字段不自动等价于 Codex 能力。保留其设计意图，使用当前 Codex 环境中可用的对应机制；无法安全等价时简要说明差异。
- 这是读取并遵循现有工具链的预检，不创建迁移副本，不修改 `.claude/`，也不生成项目级 Codex 配置，除非用户另行要求。

## 执行边界

系统、开发者、用户指令以及当前路径适用的 `AGENTS.md` 优先于本 skill，`AGENTS.md` 之间按 Codex 原生优先级生效。这里的 Claude 规范只指 `CLAUDE.md` 与 `rules/` 这类指令文件：用户级的在不冲突时作为默认约定执行，项目级的可覆盖它，局部规则只作用于其声明的路径范围；同名 skill 与子代理按上文第 4、5 步取舍。

完成预检后，用一句简短进度说明列出已采用的 Claude 规范类别，然后继续任务。只有影响方案且无法从项目内容消除的歧义才询问用户。
