---
name: change-check
description: {{scope_lead}}收尾时的改动检查：agent-change-check skill 规定怎么派审查与处理意见，change-checker 子代理审本次改动，查缺失、逻辑错误与结构问题，只给意见不改文件。{{scope_tail}}用于"给这个项目配代码审查""装 change-checker""改动检查加上项目自己的规范""更新审查规则"等场景。
disable-model-invocation: true
---

# 安装改动检查

装两样东西：`agent-change-check` skill（怎么派、意见怎么处理）与 `change-checker` 子代理（检查项与判断标准）。
装出的 skill 靠 description 自动触发，本安装器不往指令文件写任何内容。

## 跨宿主约定

只执行当前宿主对应的分支。

{{include: host-conventions}}

{{include: scope-select}}

{{include: skill-priority}}

{{include: pre-write}}

本安装器另外要查的冲突：无。

## 通用步骤

1. **写入 skill**：执行所在宿主安装节里的 `cp`，已有的整份覆盖。
2. **装子代理**：已有的同名文件整份替换；Codex 用渲染脚本的 `--replace` 替换同名旧 `.toml`，目标是软链时它会
   整批拒绝写入。项目级安装时，旧子代理「检查项」一节里有「本项目」表的，先把它读出来再替换
   （见「重装」；Codex 在旧 `.toml` 的 `developer_instructions` 里）。
3. **对齐项目**：只在项目级安装时做。项目有审查时必须知道、与通用检查项不同的约定——编码规范文档在哪、
   哪类改动必须额外盯的风险点——就在装好的子代理「检查项」一节加一张「本项目」表写进去
   （Codex 改 `.toml` 的 `developer_instructions`）。插入点固定在「代码以外的文件不套……两张表」那句之后、
   「## 敢于重组」之前，与前后各空一行。表的格式：

   ```markdown
   **本项目**

   | 检查 | 是则 | 出处 |
   |------|------|------|
   | <项目特有的检查，如「违反 docs/coding-style.md」「改了数据库迁移却没同步 schema 文档」> | <建议怎么改> | <规范文档的路径 + 章节标题原文；用户口头交代的写「用户交代」> |
   ```

   一行一条，内容来自项目里的规范文档或用户交代；只写项目确实有的，一条都没有就不加这张表。
   已写在项目指令文件里的约定不要再抄一遍。
4. **告知用户**：除各安装节列的外，说明重装时保留的只有项目级安装时填写的「本项目」表，
   项目特有的审查约定请写进这张表。

## Claude Code 项目级安装（默认）

```bash
{{include: project-root}}
mkdir -p .claude/skills/agent-change-check .claude/agents
cp "$TEMPLATE_DIR/agent-change-check.md" .claude/skills/agent-change-check/SKILL.md
cp "$TEMPLATE_DIR/agents/change-checker.md" .claude/agents/
```

**告知用户**：`.claude/skills/agent-change-check/` 与 `.claude/agents/change-checker.md`
要提交进版本库才随仓库生效；`.gitignore` 整体忽略了 `.claude/` 的项目要为这两处加例外。
装好后可用 `/agent-change-check` 调用，也会按描述自动触发；重启 Claude Code 后生效。

## Claude Code 用户级安装

装进**当前会话的用户级配置目录**，不要写死路径。

```bash
C=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
mkdir -p "$C/skills/agent-change-check" "$C/agents"
cp "$TEMPLATE_DIR/agent-change-check.md" "$C/skills/agent-change-check/SKILL.md"
cp "$TEMPLATE_DIR/agents/change-checker.md" "$C/agents/"
```

**告知用户**：装到了哪个用户级配置目录要说清楚（用户可能开着多个）；重启 Claude Code 后生效。

## Codex 项目级安装（默认）

```bash
{{include: project-root}}
: "${RENDER_AGENT:?}" "${TEMPLATE_DIR:?}"
mkdir -p .agents/skills/agent-change-check .codex/agents
cp "$TEMPLATE_DIR/agent-change-check.md" .agents/skills/agent-change-check/SKILL.md
python3 "$RENDER_AGENT" --replace --output-dir .codex/agents "$TEMPLATE_DIR/agents/change-checker.md"
```

**告知用户**：`.agents/skills/agent-change-check/` 与 `.codex/agents/change-checker.toml`
要提交进版本库才随仓库生效；`.gitignore` 整体忽略了 `.agents/` 或 `.codex/` 的项目要为这两处加例外。
装好后可用 `$agent-change-check` 调用，也会按描述自动触发；开启新会话后生效。

## Codex 用户级安装

```bash
{{include: codex-user-skill-dir}}
D=$(codex_skill_dir agent-change-check) || exit 1
: "${RENDER_AGENT:?}" "${TEMPLATE_DIR:?}"
mkdir -p "$D" "$X/agents"
cp "$TEMPLATE_DIR/agent-change-check.md" "$D/SKILL.md"
python3 "$RENDER_AGENT" --replace --output-dir "$X/agents" "$TEMPLATE_DIR/agents/change-checker.md"
```

**告知用户**：说明实际写入的用户级配置目录；开启新会话后生效。

{{include: reinstall}}

本安装器的定制值：

- 子代理「检查项」一节里的「本项目」表（项目级安装）：第 2 步替换前读出，第 3 步对照项目重新核对——
  出处是规范文档的，文档还在、约定还成立的沿用，已不存在的去掉；出处为「用户交代」的原样沿用。
- 用户级安装：无。

{{include: state-mismatch}}
