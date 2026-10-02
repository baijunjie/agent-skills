---
name: subagents
description: {{scope_lead}}分派子代理的规则与四个通用子代理（mechanical、implement、investigate、architect）。{{scope_tail}}用于"装通用子代理""配子代理分派规则""配一台新电脑""同步我的子代理规则"等场景。
disable-model-invocation: true
---

# 安装分派子代理规则与通用子代理

## 跨宿主约定

只执行当前宿主对应的分支。

{{include: host-conventions}}

{{include: scope-select}}

**整份装齐**，不要因为「用户级可能已经装过」而缩水。

{{include: subagent-rule}}

{{include: markers}}

{{include: pre-write}}

本安装器另外要查的冲突：

- 指令文件标记范围之外已有分派子代理的规则（什么时候派、派给谁、怎么交代）。
  标记之外只有「# 全局规则」标题、底下没有这类规则的不算冲突。
- 用户级、文件里还没有本安装器标记、且标记之外已有「# 全局规则」时：它不是文件里最后一个一级标题的
  （追加到末尾的规则会挂到别的标题下），按「现状与预期不符时」问用户。
- **这一项不按冲突问**：项目级安装时，当前宿主用户级指令文件里已有同类规则（分派子代理规则）的，不改它，告知用户两份都会生效、内容差在哪；用户级的是本安装器装的且内容一致时，只说一句两处都装了。

## 写入的规则内容

写入的是命令渲染出的内容，不要直接拷 `rules.md`（原文带用户级标题与 `{{host_agent_token}}` 占位符）。

用户级安装加 `--no-header` 渲染时，告知用户：这样渲染出的规则不含「与项目自己的指令文件冲突时，以项目的为准」这一句，
请用户确认已有的「# 全局规则」下有没有同样的约定。

## Claude Code 项目级安装（默认）

1. **写规则**：目标是项目根目录的 `CLAUDE.md`，没有就新建。

   ```bash
   {{include: project-root}}
   : "${RENDER_RULES:?}" "${TEMPLATE_DIR:?}"
   rules=$(python3 "$RENDER_RULES" --host claude --scope project "$TEMPLATE_DIR/rules.md") &&
     printf '\n<!-- {{marker}}:begin -->\n\n%s\n\n<!-- {{marker}}:end -->\n' "$rules" >> CLAUDE.md
   ```

2. **装子代理**：已有的整份覆盖。

   ```bash
   {{include: project-root}}
   : "${TEMPLATE_DIR:?}"
   mkdir -p .claude/agents
   cp "$TEMPLATE_DIR/agents/"*.md .claude/agents/
   ```

3. **告知用户**：`CLAUDE.md` 与 `.claude/agents/` 的改动要提交进版本库才随仓库生效；
   `.gitignore` 整体忽略了 `.claude/` 的项目要为 `.claude/agents/` 加例外，否则子代理提交不进去。
   `CLAUDE.md` 与子代理都在会话开始时读取，重启 Claude Code 后生效。

## Claude Code 用户级安装

装进**当前会话的用户级配置目录**，不要写死路径。

1. **写规则**：标记范围之外已有「# 全局规则」标题时加 `--no-header` 渲染——它不重复这个标题与首句，
   写出的规则直接挂到已有的那个标题下；下面的命令会自己判断：

   ```bash
   C=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
   F="$C/CLAUDE.md"
   : "${RENDER_RULES:?}" "${TEMPLATE_DIR:?}"
   mkdir -p "$C"
   NOHEAD=
   if [ -f "$F" ] && awk '/^<!-- {{marker}}:begin -->$/{s=1} !s{print} /^<!-- {{marker}}:end -->$/{s=0}' "$F" | grep -qx '# 全局规则'; then NOHEAD=--no-header; fi
   echo "渲染参数：${NOHEAD:-（无，带「# 全局规则」标题）}"
   rules=$(python3 "$RENDER_RULES" --host claude --scope user $NOHEAD "$TEMPLATE_DIR/rules.md") &&
     printf '\n<!-- {{marker}}:begin -->\n\n%s\n\n<!-- {{marker}}:end -->\n' "$rules" >> "$F"
   ```

2. **装子代理**：已有的整份覆盖。

   ```bash
   C=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
   : "${TEMPLATE_DIR:?}"
   mkdir -p "$C/agents"
   cp "$TEMPLATE_DIR/agents/"*.md "$C/agents/"
   ```

3. **告知用户**：装到了哪个用户级配置目录要说清楚（用户可能开着多个）；规则与子代理都在会话开始时读取，
   重启 Claude Code 后生效。

## Codex 项目级安装（默认）

1. **写规则**：目标是项目根目录的 `AGENTS.md`，没有就新建。

   ```bash
   {{include: project-root}}
   : "${RENDER_RULES:?}" "${TEMPLATE_DIR:?}"
   rules=$(python3 "$RENDER_RULES" --host codex --scope project "$TEMPLATE_DIR/rules.md") &&
     printf '\n<!-- {{marker}}:begin -->\n\n%s\n\n<!-- {{marker}}:end -->\n' "$rules" >> AGENTS.md
   ```

2. **装子代理**：用渲染脚本的 `--replace` 替换与模板同名的旧 `.toml`（只动这几个），目标是软链时它会整批拒绝写入：

   ```bash
   {{include: project-root}}
   : "${RENDER_AGENT:?}" "${TEMPLATE_DIR:?}"
   mkdir -p .codex/agents
   python3 "$RENDER_AGENT" --replace --output-dir .codex/agents "$TEMPLATE_DIR/agents/"*.md
   ```

3. **告知用户**：`AGENTS.md` 与 `.codex/agents/` 的改动要提交进版本库才随仓库生效；
   `.gitignore` 整体忽略了 `.codex/` 的项目要为 `.codex/agents/` 加例外，否则子代理提交不进去。
   开启新会话后生效。

## Codex 用户级安装

1. **写规则**：标记范围之外已有「# 全局规则」标题时加 `--no-header` 渲染——它不重复这个标题与首句，
   写出的规则直接挂到已有的那个标题下；下面的命令会自己判断：

   ```bash
   X=${CODEX_HOME:-$HOME/.codex}
   F="$X/AGENTS.md"
   : "${RENDER_RULES:?}" "${TEMPLATE_DIR:?}"
   mkdir -p "$X"
   NOHEAD=
   if [ -f "$F" ] && awk '/^<!-- {{marker}}:begin -->$/{s=1} !s{print} /^<!-- {{marker}}:end -->$/{s=0}' "$F" | grep -qx '# 全局规则'; then NOHEAD=--no-header; fi
   echo "渲染参数：${NOHEAD:-（无，带「# 全局规则」标题）}"
   rules=$(python3 "$RENDER_RULES" --host codex --scope user $NOHEAD "$TEMPLATE_DIR/rules.md") &&
     printf '\n<!-- {{marker}}:begin -->\n\n%s\n\n<!-- {{marker}}:end -->\n' "$rules" >> "$F"
   ```

2. **装子代理**：与项目级相同，用 `--replace` 替换与模板同名的旧 `.toml`：

   ```bash
   X=${CODEX_HOME:-$HOME/.codex}
   : "${RENDER_AGENT:?}" "${TEMPLATE_DIR:?}"
   mkdir -p "$X/agents"
   python3 "$RENDER_AGENT" --replace --output-dir "$X/agents" "$TEMPLATE_DIR/agents/"*.md
   ```

3. **告知用户**：说明实际写入的用户级配置目录；开启新会话后生效。

{{include: reinstall}}

本安装器的定制值：无。

{{include: state-mismatch}}
