---
name: worktree
description: {{scope_lead}}git worktree 开发流程——指令文件里的约定与 git-worktree skill。{{scope_tail}}用于"给这个项目配 worktree 流程""让 agent 在独立分支上开发""初始化 worktree 规范"等场景。
disable-model-invocation: true
---

# 安装项目级 git worktree 流程

装两样东西，都只装进当前项目：指令文件里无条件生效的约定（哪些任务要开 worktree、创建与合并前先读 skill、
不绕过仓库的检查），以及从创建分支到合回目标分支的操作步骤 `git-worktree` skill 及它调用的流程脚本。
指令文件只写这些约定并指向 `git-worktree` skill，操作细节只写在 skill 里，不回写进指令文件。
要回退闸门的另装 `setup-git:revert-gate`。

## 跨宿主约定

只写入当前宿主对应的指令文件与 skill 目录；两个宿主共用同一份模板和 `.worktrees/` 目录。

{{include: host-conventions}}

{{include: skill-priority-project}}

{{include: markers}}

{{include: pre-write}}

本安装器另外要查的冲突：

- 指令文件标记范围之外另有 worktree、独立分支开发或合并流程的说法。
{{include: flow-scripts-shared}}

## 项目级安装

1. **写指令文件**：Codex 的目标是项目根目录的 `AGENTS.md`，Claude Code 的目标是 `CLAUDE.md`；没有就新建。
   模板已带本安装器的标记，按「指令文件里的标记」写入下面 `cat` 输出的内容。

   Codex 只执行这块：

   ```bash
   {{include: project-root}}
   : "${TEMPLATE_DIR:?}"
   cat "$TEMPLATE_DIR/INJECT.md" >> AGENTS.md
   ```

   Claude Code 只执行这块：

   ```bash
   {{include: project-root}}
   : "${TEMPLATE_DIR:?}"
   cat "$TEMPLATE_DIR/INJECT.md" >> CLAUDE.md
   ```

2. **装 `git-worktree` skill**：已有的整份覆盖。

   Codex 只执行这块：

   ```bash
   {{include: project-root}}
   : "${TEMPLATE_DIR:?}"
   mkdir -p .agents/skills/git-worktree
   cp "$TEMPLATE_DIR/git-worktree/SKILL.template.md" .agents/skills/git-worktree/SKILL.md
   ```

   Claude Code 只执行这块：

   ```bash
   {{include: project-root}}
   : "${TEMPLATE_DIR:?}"
   mkdir -p .claude/skills/git-worktree
   cp "$TEMPLATE_DIR/git-worktree/SKILL.template.md" .claude/skills/git-worktree/SKILL.md
   ```

   两个宿主都再装 skill 调用的流程脚本：`.githooks/` 下的 `flow-*.sh` 完成记录、压平、搬分支、推送、清理等机械操作，
   只依赖 sh 与 git。保留可执行位，已有的同名文件直接覆盖，`.githooks/` 里别的文件不动：

   ```bash
   {{include: project-root}}
   : "${FLOW_DIR:?}"
   mkdir -p .githooks && cp -p "$FLOW_DIR/"* .githooks/
   ```
3. **忽略 worktree 目录**：确认 `.gitignore` 已忽略 `.worktrees/`，缺少就添加。
4. **告知用户**：
   - 宿主指令文件、skill 目录（Claude Code 是 `.claude/skills/git-worktree/`，Codex 是 `.agents/skills/git-worktree/`）、
     `.gitignore` 与 `.githooks/` 下的流程脚本要提交进版本库才随仓库生效；`.gitignore` 整体忽略了 `.claude/`
     或 `.agents/` 的项目要为 skill 目录加例外。Claude Code 重启后生效，Codex 开启新会话后生效。
   - 操作步骤在 `git-worktree` skill 里，要改就改这个 skill，不要搬回指令文件——重装时指令文件那块会整份覆盖。
   - 要在合并时拦下压平、解冲突撤销了目标分支已有改动的，另装 `setup-git:revert-gate`。

{{include: reinstall}}

本安装器的定制值：无。指令文件那块与装出的 skill 每次整份重写。

{{include: state-mismatch}}
