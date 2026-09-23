---
name: git-worktree
description: 给当前项目装上（或更新）git worktree 开发流程规则，按宿主写入 AGENTS.md 或 CLAUDE.md，让 .gitignore 忽略 worktree 目录，并装上拦截「合并时撤销目标分支已有改动」的回退闸门。用于"给这个项目配 worktree 流程""让 agent 在独立分支上开发""初始化 git worktree 规范"等场景。
disable-model-invocation: true
---

# 安装项目级 git worktree 流程规则

把「代码变更必须在独立 worktree + 独立分支上开发」这套流程写进当前项目的宿主指令文件，随仓库提交；
再装上回退闸门——worktree 合并回去的目标分支移动时按内容检查，拒绝改写已发布历史、以及撤销该分支已有改动的更新。

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
3. **确认主分支名**：从远端 HEAD 或分支列表确认，下一步装闸门时要把它设为常驻守护的分支。
4. **装回退闸门**：闸门依赖 git 2.28+ 与 `python3`，先确认两者：
   - 没有 `python3`：闸门和下面的手工预检都用不了。告诉用户，问是装 Python 还是不要闸门；不要闸门时
     把模板里「仓库装有回退闸门」那条规则换成人工核对——合并前逐个检查基点之后目标分支上的提交，
     确认它们的改动在待合并分支里都还在。
   - git 低于 2.28：照常复制并提交 `.githooks/`，只跳过 `install.sh`，并把那条规则改写成合并前
     必须执行下面的手工预检、退出码非 0 就不合并。
   - 都满足时：
     - 把 `$TEMPLATE_DIR/githooks/` 下的文件复制到项目根目录的 `.githooks/`，保留可执行位。
     - 在项目根目录执行 `sh .githooks/install.sh <主分支>`：参数里的分支常驻受守护；各 worktree 分支
       按规则记录的目标分支另外自动受守护，没记录的不受守护。
     - 它报 `core.hooksPath` 已设置或同名 hook 已存在时**停下来问用户**：项目已有别的 hook 体系（如 husky），
       要在那套体系的 `reference-transaction` 与 `pre-push` 里各调用一次
       `sh .githooks/hook.sh <reference-transaction|pre-push> "$@"`（原样转发 stdin），怎么接由用户定。
       有些体系（如 husky v9）不生成 `reference-transaction`，接不上时只剩 pre-push 一层，要告诉用户。

   手工预检命令（任何 worktree 里都能执行，和 hook 一样用常驻守护分支上已提交的那份脚本；取不到时报错）：

   ```bash
   s=$(git show "$(git config --get revert-gate.branch)":.githooks/revert-gate.py) && python3 -I -c "$s" check <目标分支> <分支>
   ```
5. **告知用户**：
   - 宿主指令文件、`.gitignore` 与 `.githooks/` 要提交进版本库才随仓库生效。指令文件在会话开始时读取，
     下次会话生效；闸门读的是常驻守护分支（通常是主分支）上已提交的脚本，提交进去之后才开始检查。
   - hook 本身不随仓库生效：其它 clone 各自执行一次 `sh .githooks/install.sh <主分支>`，
     同一 clone 的所有 worktree 共用，无需重复。
   - git 在每次 ref 更新的每个阶段都会启动一次 hook。不涉及本地分支的调用在 shell 里就放行了，但进程启动
     本身的开销省不掉：rebase 一长串提交会慢上几秒，一次 fetch 几千个新 tag 或分支可能多出一分钟以上。

## 已存在时

目标文件里已有 worktree 流程的说法时不要再追加一节：与模板逐条比对，补齐模板有而它没有的规则，
并将 worktree 目录对齐为 `.worktrees/`；保留项目自己加的内容和改过的分支名。
项目已有 `.githooks/` 时用模板覆盖其中的闸门文件，再执行一次 `install.sh`，它可重复执行。
要动的地方超过补充规则的范围时，先把打算怎么改告诉用户。

## 现状与预期不符时

要写入的路径不是普通文件时**停下来问用户**，不要照写。最常见的是软链：
`cat >>` 会写到它指向的地方，表面看不出异常。
