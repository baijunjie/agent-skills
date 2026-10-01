---
name: bug
description: {{scope_lead}}agent-bug-report 与 agent-bug-fix 两个 skill，规定「把缺陷记成 bug 工单」和「复现、定位根因后只改代码修复」的做法。{{scope_tail}}用于"给这个项目配 bug 工单流程""装 bug-report / bug-fix""更新项目里的 bug 处理 skill""全局装 bug 工单 skill"等场景。
disable-model-invocation: true
---

# 安装 bug 工单 skill

装出的 skill 靠 description 自动触发，本安装器不往指令文件写任何内容。

## 跨宿主约定

只执行当前宿主对应的分支。

{{include: host-conventions}}

{{include: scope-select}}

{{include: skill-priority}}

{{include: pre-write}}

本安装器另外要查的冲突：无。

## 通用步骤

1. **定目录**：只在项目级安装时做。bug 工单目录项目已有约定的沿用；项目里查不到约定、而已装的旧 skill
   里写着目录的，那就是上次定下的，沿用它（见「重装」）；都没有则用默认的 `docs/bugs/`。
   只确定目录，不改文件。
2. **写入 skill**：`agent-bug-report`、`agent-bug-fix` 两个都执行所在宿主安装节里的 `cp`，已有的整份覆盖。
3. **对齐目录**：只在项目级安装时做。目录与默认的 `docs/bugs/` 不同时，把**项目里已写入的那两份** skill
   （不是 `$TEMPLATE_DIR` 里的模板）中的 `docs/bugs/` 全部改成实际目录，包括 frontmatter 的 `description`，其它路径不动；
   两份里「工单目录默认 `docs/bugs/`，项目已有自己的约定时按项目的。」这一句随之整句改成「本项目的工单目录是 `<实际目录>`。」。
4. **告知用户**：除各安装节列的外，说明重装时保留的只有项目级安装时填写的 bug 工单目录。

用户级安装不定目录、不对齐：bug 工单目录是所在项目的，装出的 skill 在运行时按项目的约定找，
没有约定用默认的 `docs/bugs/`。

## Claude Code 项目级安装（默认）

```bash
{{include: project-root}}
mkdir -p .claude/skills/agent-bug-report .claude/skills/agent-bug-fix
cp "$TEMPLATE_DIR/agent-bug-report.md" .claude/skills/agent-bug-report/SKILL.md
cp "$TEMPLATE_DIR/agent-bug-fix.md" .claude/skills/agent-bug-fix/SKILL.md
```

**告知用户**：`.claude/skills/agent-bug-report/` 与 `.claude/skills/agent-bug-fix/` 要提交进版本库才随仓库生效；
`.gitignore` 整体忽略了 `.claude/` 的项目要为这两处加例外。
装好后可用 `/agent-bug-report`、`/agent-bug-fix` 调用，也会按描述自动触发；
如未生效，重启 Claude Code。

## Claude Code 用户级安装

装进**当前会话的用户级配置目录**，不要写死路径。

```bash
C=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
mkdir -p "$C/skills/agent-bug-report" "$C/skills/agent-bug-fix"
cp "$TEMPLATE_DIR/agent-bug-report.md" "$C/skills/agent-bug-report/SKILL.md"
cp "$TEMPLATE_DIR/agent-bug-fix.md" "$C/skills/agent-bug-fix/SKILL.md"
```

**告知用户**：装到了哪个用户级配置目录要说清楚（用户可能开着多个）；bug 工单目录由 skill 在各项目里
按项目约定判断。如未生效，重启 Claude Code。

## Codex 项目级安装（默认）

```bash
{{include: project-root}}
mkdir -p .agents/skills/agent-bug-report .agents/skills/agent-bug-fix
cp "$TEMPLATE_DIR/agent-bug-report.md" .agents/skills/agent-bug-report/SKILL.md
cp "$TEMPLATE_DIR/agent-bug-fix.md" .agents/skills/agent-bug-fix/SKILL.md
```

**告知用户**：`.agents/skills/agent-bug-report/` 与 `.agents/skills/agent-bug-fix/` 要提交进版本库才随仓库生效；
`.gitignore` 整体忽略了 `.agents/` 的项目要为这两处加例外。
装好后可用 `$agent-bug-report`、`$agent-bug-fix` 调用，也会按描述自动触发；
开启新会话后生效。

## Codex 用户级安装

```bash
{{include: codex-user-skill-dir}}
D1=$(codex_skill_dir agent-bug-report) || exit 1
D2=$(codex_skill_dir agent-bug-fix) || exit 1
mkdir -p "$D1" "$D2"
cp "$TEMPLATE_DIR/agent-bug-report.md" "$D1/SKILL.md"
cp "$TEMPLATE_DIR/agent-bug-fix.md" "$D2/SKILL.md"
```

**告知用户**：说明实际写入的用户级配置目录；bug 工单目录由 skill 在各项目里按项目约定判断。
开启新会话后生效。

{{include: reinstall}}

本安装器的定制值：

- bug 工单目录（项目级安装）：旧 skill 里「本项目的工单目录是 …」一句写的目录，没有这一句就是默认的 `docs/bugs/`；
  由第 1 步按「项目约定 → 旧值 → 默认」重新确定，第 3 步填回。
- 用户级安装：无。

{{include: state-mismatch}}
