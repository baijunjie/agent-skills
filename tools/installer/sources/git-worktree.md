---
name: worktree
description: {{scope_lead}}git worktree 开发流程——指令文件里的约定、git-worktree skill 与回退闸门。{{scope_tail}}用于"给这个项目配 worktree 流程""让 agent 在独立分支上开发""初始化 worktree 规范"等场景。
disable-model-invocation: true
---

# 安装项目级 git worktree 流程

装三样东西，都只装进当前项目：指令文件里无条件生效的约定（哪些任务要开 worktree、创建与合并前先读 skill、
不绕过仓库的检查）、从创建分支到合回目标分支的操作步骤 `git-worktree` skill，
以及回退闸门——worktree 合并回去的目标分支移动时按内容检查，拒绝改写已发布历史、以及撤销该分支已有改动的更新。
指令文件只写这些约定并指向 `git-worktree` skill，操作细节只写在 skill 里，不回写进指令文件。

## 跨宿主约定

只写入当前宿主对应的指令文件与 skill 目录；两个宿主共用同一份模板和 `.worktrees/` 目录。

{{include: host-conventions}}

{{include: skill-priority-project}}

{{include: markers}}

{{include: pre-write}}

本安装器另外要查的冲突：

- 指令文件标记范围之外另有 worktree、独立分支开发或合并流程的说法。
{{include: gate-conflicts}}

## 项目级安装

1. **按环境定闸门形态**：闸门的本地一层（reference-transaction）要 git 2.28+，push 一层与闸门预检只要 `python3`。
   已装过 `git-worktree` skill 的（路径见第 3 步），先记下其中回退闸门那条的原文（以「仓库装有回退闸门」
   或「仓库没有装回退闸门」开头），重装时靠写法 C 的原文认出用户上次选了「不要闸门」。再确认两者，按下表处理：

   | 环境 | `.githooks/` | `install.sh` | skill 正文 |
   |---|---|---|---|
   | 有 `python3`、git 2.28+ | 用下面的命令复制到项目根目录的 `.githooks/`：保留可执行位，已有的同名文件直接覆盖，`.githooks/` 里别的文件不动 | 执行，见第 7 步 | 模板原文 |
   | 有 `python3`、git 低于 2.28 | 同上 | 照样执行，见第 7 步：pre-push 一层生效，本地 merge / commit / reset 一层不生效，告知用户 | 写法 B |
   | 没有 `python3` | 上面记下的原文是写法 C 时，说明用户上次选了不要闸门，沿用、不再问；否则问用户是装 Python 还是不要闸门。装 Python 的装好后按上两行处理；不要闸门的不复制，已有的 `.githooks/` 与 hook 入口也不删 | 选了不要闸门：不执行，跳过第 6、7 步；装了 Python 的按上两行 | 选了不要闸门：写法 C；装了 Python 的按上两行 |

   ```bash
   {{include: project-root}}
   : "${GATE_DIR:?}"
   mkdir -p .githooks && cp -p "$GATE_DIR/"* .githooks/
   ```

   写法 B、C 只按各自的表改第 3 步装出的 skill，指令文件那块与其余内容不动。「位置」指 skill 中以该文字开头的那一条，
   「原文」是那条里要换掉的文字（一字不差），「整条」指整条删掉。

   **写法 B**：

   | 位置 | 原文 | 改成 |
   |---|---|---|
   | 以「仓库装有回退闸门」开头的那条 | 「移动时，本地 merge / commit / reset 与 push 都会被自动检查」 | 「推送时会被自动检查（本地 merge / commit / reset 不检查，合并前必须跑闸门预检）」 |
   | 以「reset 被拦时」开头的那条 | 整条 | 删掉 |
   | 以「本地合并前必须确认」开头的那条 | 「merge 被闸门拦下时主工作副本已被写成分支内容，要 `git reset --merge` 复原，所以先预检」 | 「本地 merge 不受闸门检查，所以必须先预检」 |
   | 以「闸门报撤销了已有改动的」开头的那条 | 「对齐远程时 rebase 被拦的，`git rebase --abort` 后重新 rebase；」 | 删掉 |

   **写法 C**：

   | 位置 | 原文 | 改成 |
   |---|---|---|
   | 以「创建 worktree 前」开头的那条 | 整条 | 删掉 |
   | 以「补装之后按下面的顺序创建」开头的那条 | 「补装之后」 | 删掉 |
   | 从以「仓库装有回退闸门」开头的那条起，到以「确要撤销某个提交」开头的那条为止（共四条） | 这四条整体 | 表下代码块里的两条 |
   | 以「本地合并前必须确认」开头的那条 | 从「闸门预检通过」起到这条末尾为止（含其下的命令块与说明） | 「已按「仓库没有装回退闸门」那条人工核对过。」 |
   | 以「顺序：」开头的那条 | 「向用户确认 → 闸门预检 → `merge --ff-only`」 | 「向用户确认 → 人工核对 → `merge --ff-only`」 |
   | 以「本地合并在主工作副本里」开头的那条 | 「重跑预检再合」 | 「重新人工核对再合」 |
   | 以「再重跑预检」开头的那条 | 「再重跑预检、合并」 | 「再重新人工核对、合并」 |
   | 以「推送目标分支被拒」开头的那条 | 「（远端报非快进，或 pre-push 报远程有本地没有的提交）」 | 「（远端报非快进）」 |

   ```markdown
   - 仓库没有装回退闸门，本地合并前要人工核对：逐个检查切出点之后目标分支上的提交，确认它们的改动在待合并分支里都还在；有改动不见了，说明压平或解冲突出了错，回分支重做。
   - 确要撤销某个提交，先问用户，同意后在主工作副本里用 `git revert`，不要在目标分支上用 reset、amend 去掉已推送的提交。
   ```
2. **写指令文件**：Codex 的目标是项目根目录的 `AGENTS.md`，Claude Code 的目标是 `CLAUDE.md`；没有就新建。
   模板已带本安装器的标记，按「指令文件里的标记」写入下面 `cat` 输出的内容；这块与闸门形态无关，三种写法都写模板原文。

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

3. **装 `git-worktree` skill**：已有的整份覆盖；第 1 步定为写法 B 或 C 的，写入后按该写法改装出的这份，不改模板。

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
4. **忽略 worktree 目录**：确认 `.gitignore` 已忽略 `.worktrees/`，缺少就添加。
5. **确认主分支名**：主分支以项目现状为准，第 6 步把它设为常驻守护分支。已装过闸门的，先从 `.githooks/branches`
   读出上次的常驻守护分支（忽略空行与 `#` 开头的行）：主分支与旧值的第一个不一致时告知用户；
   旧值里主分支以外的分支是用户加的，第 6 步一并写回。
6. **写常驻守护分支列表**：整个重写随仓库提交的 `.githooks/branches`，每行一个分支，主分支放第一行（闸门预检取第一个），
   其后是第 5 步沿用的其它分支。文件开头写一行 `#` 注释，说明这是回退闸门的常驻守护分支、主分支在第一行，
   `sh .githooks/install.sh` 不带参数时从这里读。各 worktree 分支记录的目标分支另外自动受守护，不写进来。
7. **接 hook 入口**：按「写入前检查」里 hook 入口的冲突结果，三种接法选一：

   | 情况 | 做法 |
   |---|---|
   | 没有冲突 | 直接装：执行下面的命令（可重复执行），它按 `.githooks/branches` 写好本 clone 的常驻守护分支配置 |
   | 用户选完全覆盖 | 按询问时说给用户的改法撤掉原来那套入口（如 `git config --unset core.hooksPath`、移走原 hook 文件），再按直接装执行 |
   | 用户选融入，或入口里已调用 `.githooks/hook.sh` | 在那套体系（如 husky）的 `reference-transaction` 与 `pre-push` 里各调用一次 `sh .githooks/hook.sh <所在 hook 的名字> "$@"`（原样转发 stdin），怎么接由用户定；已调用的不重复接。然后执行 `sh .githooks/install.sh --branches-only`：只按 `.githooks/branches` 写本 clone 的常驻守护分支配置，不装 hook（不带这个参数会因同一原因报错退出） |

   直接装的命令：

   ```bash
   {{include: project-root}}
   sh .githooks/install.sh
   ```

   有些体系（如 husky v9）不生成 `reference-transaction`，接不上时只剩 pre-push 一层，要告知用户。
   不带参数的 `install.sh` 报 `core.hooksPath` 已设置或同名 hook 已存在，是事先漏查了这项冲突，先按「写入前检查」问用户。
8. **告知用户**：
   - 宿主指令文件、skill 目录（Claude Code 是 `.claude/skills/git-worktree/`，Codex 是 `.agents/skills/git-worktree/`）、
     `.gitignore` 与 `.githooks/`（含 `branches`）要提交进版本库才随仓库生效；`.gitignore` 整体忽略了 `.claude/`
     或 `.agents/` 的项目要为 skill 目录加例外。Claude Code 重启后生效，Codex 开启新会话后生效；
     闸门读的是常驻守护分支（通常是主分支）上已提交的脚本，提交进去之后才开始检查。
   - 操作步骤在 `git-worktree` skill 里，要改就改这个 skill，不要搬回指令文件——重装时指令文件那块会整份覆盖。
   - hook 与常驻守护分支配置在各 clone 的 `.git/` 里，不随仓库生效：其它 clone 各自执行一次 `sh .githooks/install.sh`
     （设了 `core.hooksPath`、hook 由 husky 等体系接管的改为 `sh .githooks/install.sh --branches-only`），
     同一 clone 的所有 worktree 共用；skill 也要求 agent 创建 worktree 前发现没装就补装。
     改常驻守护分支时改 `.githooks/branches` 并提交，各 clone 重新执行一次同样的命令才生效。
   - 重装时保留的只有：常驻守护分支里主分支以外的分支，以及没有 `python3` 时选过的「不要闸门」（写法 C）。
   - 用了写法 B 或 C 的：这份 skill 随仓库对全队生效；其他成员的环境满足条件（有 `python3`、git 2.28+）时，
     请在那台机器上重装恢复原文。
   - 选了不要闸门、而仓库里原来装过闸门的：仓库里留着闸门脚本，但 skill 按人工核对写；没有 `python3` 时 hook
     直接放行，不影响合并，`.githooks/` 与 hook 入口可自行删除。
   - git 每次 ref 更新的每个阶段都会启动一次 hook：rebase 一长串提交会慢上几秒，一次 fetch 几千个新 tag 或分支可能多出一分钟以上。

{{include: reinstall}}

本安装器的定制值：

- 回退闸门那条的写法：模板原文（默认）、写法 B、写法 C 三选一，由第 1 步按当前环境重新确定，第 3 步写入装出的 skill；
  旧原文在第 1 步读出，是写法 C 的，没有 `python3` 时沿用。指令文件那块没有定制值，每次整份重写。
- 常驻守护分支（`.githooks/branches`）：主分支由项目现状得出，
  其余分支是用户加的。第 5 步读出，主分支重新确认，其余沿用旧值，第 6、7 步写回。

{{include: state-mismatch}}
