---
name: git-worktree
description: 给当前项目装上（或更新）git worktree 开发流程规则，按宿主写入 AGENTS.md 或 CLAUDE.md，并让 .gitignore 忽略 worktree 目录。用于"给这个项目配 worktree 流程""让 agent 在独立分支上开发""初始化 git worktree 规范"等场景。
disable-model-invocation: true
---

# 安装项目级 git worktree 流程规则

把「代码变更必须在独立 worktree + 独立分支上开发」这套流程写进当前项目的宿主指令文件，随仓库提交。

## 跨宿主约定

只写入当前宿主对应的指令文件；两个宿主共用同一份规则模板和 `.worktrees/` 目录。

模板资源先用 `$PLUGIN_ROOT`，为空再用 `$CLAUDE_PLUGIN_ROOT`；两者都为空时，先把 `SKILL_DIR`
设为**当前已加载的这个 `SKILL.md` 的绝对父目录**（不是项目工作目录），再按相对路径定位。执行追加前先确定：

```bash
if [ -n "${PLUGIN_ROOT:-}" ]; then
  TEMPLATE_DIR="$PLUGIN_ROOT/skills/git-worktree/template"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  TEMPLATE_DIR="$CLAUDE_PLUGIN_ROOT/skills/git-worktree/template"
else
  TEMPLATE_DIR="${SKILL_DIR:?先将 SKILL_DIR 设为当前 SKILL.md 的绝对父目录}/template"
fi
```

## 步骤

1. **追加规则节**：Codex 的目标是项目根目录的 `AGENTS.md`，Claude Code 的目标是 `CLAUDE.md`；没有就新建；它是符号链接时写它指向的实际文件。
   **先看目标文件里有没有 worktree 流程的说法**，有就转「已存在时」，不要执行下面的 `cat`——
   追加完再手工删是最该避免的。

   ```bash
   # Codex
   cat "$TEMPLATE_DIR/git-worktree.md" >> AGENTS.md

   # Claude Code
   cat "$TEMPLATE_DIR/git-worktree.md" >> CLAUDE.md
   ```

   模板用 `#` 作节标题，目标文件若把 `#` 用作文档标题、`##` 分节，追加后要把层级降一级对齐。
2. **忽略 worktree 目录**：确认 `.gitignore` 已忽略 `.worktrees/`，缺少就添加；否则 worktree
   里的文件会全部变成主工作副本的未跟踪文件。
3. **对齐主分支名**：从远端 HEAD 或分支列表确认主分支名，不是 `main` 时把文中的 `<主分支>` 换成实际名字。
4. **告知用户**：宿主指令文件与 `.gitignore` 的改动要提交进版本库才随仓库生效；
   它在会话开始时读取，当前会话不会自动重读，下次会话生效。

## 已存在时

目标文件里已有 worktree 流程的说法时不要再追加一节：与模板逐条比对，补齐模板有而它没有的规则，
并将 worktree 目录对齐为 `.worktrees/`；保留项目自己加的内容和改过的分支名。要动的地方超过补充规则的
范围时，先把打算怎么改告诉用户。

## 现状与预期不符时

要写入的路径不是普通文件时**停下来问用户**，不要照写。最常见的是软链：
`cat >>` 会写到它指向的地方，表面看不出异常。
