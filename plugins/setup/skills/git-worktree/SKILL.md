---
name: git-worktree
description: 给当前项目装上（或更新）git worktree 开发流程规则，写进项目的 CLAUDE.md 并让 .gitignore 忽略 worktree 目录。用于"给这个项目配 worktree 流程""让 agent 在独立分支上开发""初始化 git worktree 规范"等场景。
disable-model-invocation: true
---

# 安装项目级 git worktree 流程规则

把「代码变更必须在独立 worktree + 独立分支上开发」这套流程写进当前项目的 `CLAUDE.md`，随仓库提交。

补充说明（可选）：

<task>
$ARGUMENTS
</task>

## 步骤

1. **追加规则节**：目标是项目根目录的 `CLAUDE.md`，没有就新建；它是符号链接时写它指向的实际文件。
   **先看目标文件里有没有 worktree 流程的说法**，有就转「已存在时」，不要执行下面的 `cat`——
   追加完再手工删是最该避免的。

   ```bash
   cat "$CLAUDE_PLUGIN_ROOT/skills/git-worktree/template/git-worktree.md" >> CLAUDE.md
   ```

   `$CLAUDE_PLUGIN_ROOT` 为空时用本 skill 目录下的 `template/git-worktree.md`。
   模板用 `#` 作节标题，目标文件若把 `#` 用作文档标题、`##` 分节，追加后要把层级降一级对齐。
2. **忽略 worktree 目录**：确认 `.gitignore` 已忽略 `.claude/worktrees/`，否则 worktree 里的文件会
   全部变成主工作副本的未跟踪文件。已整体忽略 `.claude/` 的项目不用再加。
3. **对齐主分支名**：从远端 HEAD 或分支列表确认主分支名，不是 `main` 时把文中的 `<主分支>` 换成实际名字。
4. **告知用户**：`CLAUDE.md` 与 `.gitignore` 的改动要提交进版本库才随仓库生效；
   `CLAUDE.md` 在会话开始时读取，当前会话不会自动重读，下次会话生效。

## 已存在时

目标文件里已有 worktree 流程的说法时不要再追加一节：与模板逐条比对，补齐模板有而它没有的规则，
保留项目自己加的内容和改过的路径、分支名。要动的地方超过补充规则的范围时，先把打算怎么改告诉用户。

## 现状与预期不符时

要写入的路径不是普通文件时**停下来问用户**，不要照写。最常见的是软链：
`cat >>` 会写到它指向的地方，表面看不出异常。
