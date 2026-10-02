---
name: plan
description: {{scope_lead}}agent-plan-write 与 agent-plan-exec 两个 skill，规定「把方案写成开发计划文档」和「按计划文档逐里程碑开发」的做法。{{scope_tail}}用于"给这个项目配开发计划流程""装 plan-write / plan-exec""更新项目里的开发计划 skill""全局装开发计划 skill"等场景。
disable-model-invocation: true
---

# 安装开发计划 skill

装出的 skill 靠 description 自动触发，本安装器不往指令文件写任何内容。

## 跨宿主约定

只执行当前宿主对应的分支。

{{include: host-conventions}}

{{include: scope-select}}

{{include: skill-priority}}

{{include: pre-write}}

本安装器另外要查的冲突：无。

## 通用步骤

1. **定目录**：只在项目级安装时做。开发计划文档目录项目已有约定的沿用；项目里查不到约定、而已装的旧 skill
   里写着目录的，那就是上次定下的，沿用它（见「重装」）；都没有则用默认的 `docs/plans/`。
   只确定目录，不改文件。
2. **写入 skill**：`agent-plan-write`、`agent-plan-exec` 两个都执行所在宿主安装节里的 `cp`，已有的整份覆盖。
3. **对齐目录**：只在项目级安装时做。目录与默认的 `docs/plans/` 不同时，改的是**项目里已写入的那两份** skill
   （不是 `$TEMPLATE_DIR` 里的模板），按顺序做：先把两份里「开发计划文档目录默认 `docs/plans/`，项目已有自己的约定时按项目的。」
   整句改成「本项目的开发计划文档目录是 `<实际目录>`。」；再把其余出现的 `docs/plans/` 改成实际目录，包括 frontmatter 的 `description`，其它路径不动。
4. **告知用户**：除各安装节列的外，说明重装时保留的只有项目级安装时填写的开发计划文档目录。

用户级安装不定目录、不对齐：开发计划文档目录是所在项目的，装出的 skill 在运行时按项目的约定找，
没有约定用默认的 `docs/plans/`。

## Claude Code 项目级安装（默认）

```bash
{{include: project-root}}
: "${TEMPLATE_DIR:?}"
mkdir -p .claude/skills/agent-plan-write .claude/skills/agent-plan-exec
cp "$TEMPLATE_DIR/agent-plan-write.md" .claude/skills/agent-plan-write/SKILL.md
cp "$TEMPLATE_DIR/agent-plan-exec.md" .claude/skills/agent-plan-exec/SKILL.md
```

**告知用户**：`.claude/skills/agent-plan-write/` 与 `.claude/skills/agent-plan-exec/` 要提交进版本库才随仓库生效；
`.gitignore` 整体忽略了 `.claude/` 的项目要为这两处加例外。
装好后可用 `/agent-plan-write`、`/agent-plan-exec` 调用，也会按描述自动触发；
如未生效，重启 Claude Code。

## Claude Code 用户级安装

装进**当前会话的用户级配置目录**，不要写死路径。

```bash
: "${TEMPLATE_DIR:?}"
C=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
mkdir -p "$C/skills/agent-plan-write" "$C/skills/agent-plan-exec"
cp "$TEMPLATE_DIR/agent-plan-write.md" "$C/skills/agent-plan-write/SKILL.md"
cp "$TEMPLATE_DIR/agent-plan-exec.md" "$C/skills/agent-plan-exec/SKILL.md"
```

**告知用户**：装到了哪个用户级配置目录要说清楚（用户可能开着多个）；开发计划文档目录由 skill 在各项目里
按项目约定判断。如未生效，重启 Claude Code。

## Codex 项目级安装（默认）

```bash
{{include: project-root}}
: "${TEMPLATE_DIR:?}"
mkdir -p .agents/skills/agent-plan-write .agents/skills/agent-plan-exec
cp "$TEMPLATE_DIR/agent-plan-write.md" .agents/skills/agent-plan-write/SKILL.md
cp "$TEMPLATE_DIR/agent-plan-exec.md" .agents/skills/agent-plan-exec/SKILL.md
```

**告知用户**：`.agents/skills/agent-plan-write/` 与 `.agents/skills/agent-plan-exec/` 要提交进版本库才随仓库生效；
`.gitignore` 整体忽略了 `.agents/` 的项目要为这两处加例外。
装好后可用 `$agent-plan-write`、`$agent-plan-exec` 调用，也会按描述自动触发；
开启新会话后生效。

## Codex 用户级安装

```bash
: "${TEMPLATE_DIR:?}"
D1="$HOME/.agents/skills/agent-plan-write"
D2="$HOME/.agents/skills/agent-plan-exec"
mkdir -p "$D1" "$D2"
cp "$TEMPLATE_DIR/agent-plan-write.md" "$D1/SKILL.md"
cp "$TEMPLATE_DIR/agent-plan-exec.md" "$D2/SKILL.md"
```

**告知用户**：说明实际写入的用户级配置目录；开发计划文档目录由 skill 在各项目里按项目约定判断。
开启新会话后生效。

{{include: reinstall}}

本安装器的定制值：

- 开发计划文档目录（项目级安装）：旧 skill 里「本项目的开发计划文档目录是 …」一句写的目录，没有这一句就是默认的 `docs/plans/`；
  由第 1 步按「项目约定 → 旧值 → 默认」重新确定，第 3 步填回。
- 用户级安装：无。

{{include: state-mismatch}}
