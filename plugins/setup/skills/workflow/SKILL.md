---
name: workflow
description: 装上（或更新）通用 agent 工作流规范——注释规范、提交信息、分派子代理、交付前自检，外加五个通用子代理。默认装进当前项目，也可安装到用户级配置、对当前用户环境中的所有项目生效。用于"给这个项目配 agent 规范""装通用子代理""配一台新电脑""同步我的 agent 工作流""更新全局规则"等场景。
disable-model-invocation: true
---

# 安装 agent 工作流规范

一份规则正文（注释规范 / Git 提交信息 / 分派子代理 / 交付前自检）加五个通用子代理。

## 跨宿主约定

只执行当前宿主对应的分支。模板资源先用 `$PLUGIN_ROOT`，为空再用 `$CLAUDE_PLUGIN_ROOT`；
两者都为空时，先把 `SKILL_DIR` 设为**当前已加载的这个 `SKILL.md` 的绝对父目录**（不是项目工作目录），
再按相对路径定位。执行写入前先确定：

```bash
if [ -n "${PLUGIN_ROOT:-}" ]; then
  SETUP_ROOT="$PLUGIN_ROOT"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  SETUP_ROOT="$CLAUDE_PLUGIN_ROOT"
else
  SETUP_ROOT="${SKILL_DIR:?先将 SKILL_DIR 设为当前 SKILL.md 的绝对父目录}/../.."
fi
TEMPLATE_DIR="$SETUP_ROOT/skills/workflow/template"
RENDER_AGENT="$SETUP_ROOT/scripts/render-codex-agent.py"
RENDER_RULES="$SETUP_ROOT/scripts/render-workflow-rules.py"
```

## 选作用域

**默认装进当前项目**，随仓库提交。**整份装齐**，不要因为「用户级可能已经装过」而缩水。

用户明确说了「全局 / 用户级 / 所有项目 / 新电脑」，或当前目录不是 git 仓库时，
才走「用户级安装」——那一份只在当前用户环境生效，是个人偏好，不进任何仓库。

两层会同时加载，同名节以项目的为准，不必为此少装哪一层。

## Codex 项目安装（默认）

1. **追加规则节**：目标是项目根目录的 `AGENTS.md`，没有就新建；它是符号链接时写它指向的实际文件。
   **先看目标文件里有没有同名节**，有就转「已存在时」逐节比对，不要直接追加。

   ```bash
   "$RENDER_RULES" --host codex --scope project "$TEMPLATE_DIR/rules.md" >> AGENTS.md
   ```

   渲染结果的标题层级要和目标文件对齐。
2. **装子代理**：先确认每个目标 `.toml` 都不存在；已有同名文件就转「已存在时」，不要覆盖。
   再从 Markdown 唯一模板源组装 Codex agent。转换只提取 `name`、`description` 与完整正文，
   再按各代理职责写入 Codex 的 `model` 与 `model_reasoning_effort`；`code-reviewer` 额外设为只读沙箱。

   ```bash
   mkdir -p .codex/agents
   "$RENDER_AGENT" --output-dir .codex/agents "$TEMPLATE_DIR/agents/"*.md
   ```
3. **告知用户**：`AGENTS.md` 与 `.codex/agents/` 的改动要提交进版本库才随仓库生效；
   `.gitignore` 整体忽略了 `.codex/` 的项目要为 `.codex/agents/` 加例外，否则子代理提交不进去。
   `AGENTS.md` 在会话开始时读取，当前会话不会自动重读，下次会话生效。

## Codex 用户级安装

把规则正文追加到当前 Codex 用户级配置目录的 `AGENTS.md`，并从 Markdown 唯一模板源组装子代理到
该目录的 `agents/`。使用 `CODEX_HOME`；未设置时回退到 `$HOME/.codex`。

1. **写规则正文**：先计算用户级配置根目录：

   ```bash
   X=${CODEX_HOME:-$HOME/.codex}
   mkdir -p "$X"
   ```

   确认 `$X/AGENTS.md` 没有本模板的同名节后，再执行：

   ```bash
   X=${CODEX_HOME:-$HOME/.codex}
   "$RENDER_RULES" --host codex --scope user "$TEMPLATE_DIR/rules.md" >> "$X/AGENTS.md"
   ```

2. **装子代理**：先确认每个目标 `.toml` 都不存在；已有同名文件就转「已存在时」，不要覆盖。再执行：

   ```bash
   X=${CODEX_HOME:-$HOME/.codex}
   mkdir -p "$X/agents"
   "$RENDER_AGENT" --output-dir "$X/agents" "$TEMPLATE_DIR/agents/"*.md
   ```

   转换规则与项目安装相同。
3. **告知用户**：说明实际写入的用户级配置目录；重启 Codex 后重新加载。
   这两步各自独立，规则正文已经有了、子代理没装时，仍要完成第 2 步。

## Claude Code 项目安装（默认）

1. **追加规则节**：目标是项目根目录的 `CLAUDE.md`，没有就新建；它是符号链接时写它指向的实际文件。
   **先看目标文件里有没有同名节**，有就转「已存在时」逐节比对，不要执行下面的 `cat`——
   追加完再手工删是最该避免的。

   ```bash
   "$RENDER_RULES" --host claude --scope project "$TEMPLATE_DIR/rules.md" >> CLAUDE.md
   ```

   渲染器会去掉只适用于用户级安装的 `# 全局规则` 标题和优先级说明；其余各节按目标文件的标题层级对齐。
2. **装子代理**：

   ```bash
   mkdir -p .claude/agents
   cp -n "$TEMPLATE_DIR/agents/"*.md .claude/agents/
   ```

   **装进项目的 `.claude/agents/`，不是用户级配置目录（默认 `~/.claude`）下的 `agents/`**；已有同名文件 `cp -n` 会静默跳过，
   跳过了就转「已存在时」，不要当成装好了。
   「交付前自检」点名要派的 `code-reviewer` 就在这批里，不装它那条规则就落空。
3. **告知用户**：`CLAUDE.md` 与 `.claude/agents/` 的改动要提交进版本库才随仓库生效；
   `.gitignore` 整体忽略了 `.claude/` 的项目要为 `.claude/agents/` 加例外，否则子代理提交不进去。
   `CLAUDE.md` 在会话开始时读取，当前会话不会自动重读，下次会话生效。
   用户级配置也装过同一套时，两层都会加载，同名节以项目这份为准。

## Claude Code 用户级安装

装进**当前会话的用户级配置目录**，对当前用户环境中的所有项目生效。这个目录由 Claude Code 的
`CLAUDE_CONFIG_DIR` 决定，没设就是 `~/.claude`；下面的命令用 `C` 指代它，不要写死路径。

1. **写规则正文**：

   ```bash
   C=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
   mkdir -p "$C"
   "$RENDER_RULES" --host claude --scope user "$TEMPLATE_DIR/rules.md" >> "$C/CLAUDE.md"
   ```

   文件里已有本模板的同名节时转「已存在时」，不要追加出第二份。
   用户级渲染会保留「与项目自己的指令文件冲突时，以项目的为准」作为两层同时加载时的优先级依据。
2. **装子代理**：

   ```bash
   C=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
   mkdir -p "$C/agents"
   cp -n "$TEMPLATE_DIR/agents/"*.md "$C/agents/"
   ```

   已有同名文件 `cp -n` 会静默跳过，跳过了就转「已存在时」，不要当成装好了。
   **这一步与上一步各自独立**：规则正文已经有了、子代理没装，仍然要把这一步做完——
   「交付前自检」点名要派的 `code-reviewer` 就在这批里。
3. **告知用户**：装到了哪个用户级配置目录要说清楚（用户可能开着多个）；以后改规则直接改那两处，
   但**要重启 Claude Code 才重新加载**。

## 已存在时

已有内容时不要覆盖：先为当前宿主与作用域渲染共享规则模板，再与规则和代理模板逐节比对，
补齐模板有而它没有的，保留当前用户环境或当前项目已有的补充内容。
Codex 子代理与 Markdown 模板转换后的字段逐项比对，不要另找或创建一份 TOML 模板。
不要修改已安装 plugin 内的模板。
要动的地方超过补充规则的范围时，先把打算怎么改告诉用户。

## 现状与预期不符时

要写入的路径不是普通文件 / 目录时**停下来问用户**，不要照写。最常见的是软链：
`cat >>` 与 `cp` 会写到它指向的地方，而 `mkdir -p` 在软链上仍然静默成功，表面看不出异常。
