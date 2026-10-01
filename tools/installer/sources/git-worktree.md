---
name: worktree
description: {{scope_lead}}git worktree 开发流程规则，按宿主写入 AGENTS.md 或 CLAUDE.md，让 .gitignore 忽略 worktree 目录，并装上拦截「合并时撤销目标分支已有改动」的回退闸门。{{scope_tail}}用于"给这个项目配 worktree 流程""让 agent 在独立分支上开发""初始化 git worktree 规范"等场景。
disable-model-invocation: true
---

# 安装项目级 git worktree 流程规则

把「代码变更必须在独立 worktree + 独立分支上开发」这套流程写进当前项目的宿主指令文件，随仓库提交；
再装上回退闸门——worktree 合并回去的目标分支移动时按内容检查，拒绝改写已发布历史、以及撤销该分支已有改动的更新。

## 跨宿主约定

只写入当前宿主对应的指令文件；两个宿主共用同一份规则模板和 `.worktrees/` 目录。

{{include: host-conventions}}

{{include: markers}}

{{include: pre-write}}

本安装器另外要查的冲突：

- 指令文件标记范围之外另有 worktree、独立分支开发或合并流程的说法。
- hook 入口：`git config core.hooksPath` 已设置，或 `$(git rev-parse --git-common-dir)/hooks/` 下已有不含
  `# revert-gate hook entry` 一行的 `reference-transaction` / `pre-push`。完全覆盖会让原来那套 hook 失效，询问时说明。
  入口里已调用 `.githooks/hook.sh` 的，按第 6 步「融入」那一行处理，不算冲突。

## 项目级安装

1. **写规则节**：Codex 的目标是项目根目录的 `AGENTS.md`，Claude Code 的目标是 `CLAUDE.md`；没有就新建。
   模板已带本安装器的标记。文件里已有这对标记时，先记下标记范围里回退闸门那条的原文（以「仓库装有回退闸门」
   或「仓库没有装回退闸门」开头，第 4 步要用，见「重装」）。写入前检查通过后，按「指令文件里的标记」写入下面
   `cat` 输出的内容。

   Codex 只执行这块：

   ```bash
   {{include: project-root}}
   : "${TEMPLATE_DIR:?}"
   cat "$TEMPLATE_DIR/git-worktree.md" >> AGENTS.md
   ```

   Claude Code 只执行这块：

   ```bash
   {{include: project-root}}
   : "${TEMPLATE_DIR:?}"
   cat "$TEMPLATE_DIR/git-worktree.md" >> CLAUDE.md
   ```

   模板用 `#` 作节标题，目标文件若把 `#` 用作文档标题、`##` 分节，写入后要把标记范围里的层级降一级对齐。
2. **忽略 worktree 目录**：确认 `.gitignore` 已忽略 `.worktrees/`，缺少就添加。
3. **确认主分支名**：主分支以项目现状为准，第 5 步把它设为常驻守护分支。已装过闸门的，先读出上次的常驻守护分支：
   以 `.githooks/branches` 为准（忽略空行与 `#` 开头的行），没有这个文件再读 `git config --get-all revert-gate.branch`。
   主分支与旧值的第一个不一致时告诉用户；旧值里主分支以外的分支是用户加的，第 5 步一并写回。
4. **按环境定闸门形态**：闸门的本地一层（reference-transaction）要 git 2.28+，push 一层与闸门预检只要 `python3`。
   先确认两者，按下表处理；表里的写法 B、C 见下方，替换后的原文就是重装时认写法的依据。

   | 环境 | `.githooks/` | `install.sh` | 规则节 |
   |---|---|---|---|
   | 有 `python3`、git 2.28+ | 用下面的命令复制到项目根目录的 `.githooks/`：保留可执行位，已有的同名文件直接覆盖，`.githooks/` 里别的文件不动 | 执行，见第 6 步 | 模板原文 |
   | 有 `python3`、git 低于 2.28 | 同上 | 照样执行，见第 6 步：pre-push 一层生效，本地 merge / commit / reset 一层不生效，告诉用户 | 写法 B |
   | 没有 `python3` | 第 1 步记下的原文是写法 C 时，说明用户上次选了不要闸门，沿用、不再问；否则问用户是装 Python 还是不要闸门。装 Python 的装好后按上两行处理；不要闸门的不复制，已有的 `.githooks/` 与 hook 入口也不删 | 不执行，跳过第 5、6 步 | 写法 C |

   ```bash
   {{include: project-root}}
   : "${TEMPLATE_DIR:?}"
   mkdir -p .githooks && cp -p "$TEMPLATE_DIR/githooks/"* .githooks/
   ```

   **写法 B**：两处替换，其余不动——
   - 「仓库装有回退闸门」那条里的「移动时，本地 merge / commit / reset 与 push 都会被自动检查」换成
     「被 push 时会被自动检查（本地 merge / commit / reset 不检查，合并前必须跑闸门预检）」。
   - 「本地合并前必须确认」那条里的「merge 被闸门拦下时主工作副本已被写成分支内容，要 `git reset --merge` 复原，所以先预检」
     换成「本地 merge 不受闸门检查，所以必须先预检」。

   **写法 C**：四处改动，其余不动——
   - 以「创建 worktree 前」开头的那条整条删掉。
   - 「仓库装有回退闸门」那条整条换成：

     ```markdown
     - 仓库没有装回退闸门，本地合并前要人工核对：逐个检查切出点之后目标分支上的提交，确认它们的改动在待合并分支里都还在；有改动不见了，说明压平或解冲突出了错，回分支重做。确要撤销某个提交，先问用户，同意后用 `git revert`，不要在目标分支上用 reset、amend 去掉提交。
     ```

   - 「本地合并前必须确认」那条里从「闸门预检通过」起到这条末尾为止（含其下的命令块与说明），换成
     「已按「仓库没有装回退闸门」那条人工核对过。」。
   - 以「项目改走 PR 合并时」开头的那条里的「重跑预检再合」换成「重新人工核对再合」。
5. **写常驻守护分支列表**：把常驻守护分支写进随仓库提交的 `.githooks/branches`（整个文件重写），每行一个分支，
   主分支放第一行——闸门预检取的是第一个；其后是第 3 步沿用的其它分支。文件开头写一行 `#` 注释，说明这是回退闸门的
   常驻守护分支、主分支在第一行，`sh .githooks/install.sh` 不带参数时从这里读。各 worktree 分支按规则记录的
   目标分支另外自动受守护，不写进来。
6. **接 hook 入口**：按「写入前检查」里 hook 入口的冲突结果，三种接法选一：

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

   有些体系（如 husky v9）不生成 `reference-transaction`，接不上时只剩 pre-push 一层，要告诉用户。
   不带参数的 `install.sh` 报 `core.hooksPath` 已设置或同名 hook 已存在，是事先漏查了这项冲突，先按「写入前检查」问用户。
7. **告知用户**：
   - 宿主指令文件、`.gitignore` 与 `.githooks/`（含 `branches`）要提交进版本库才随仓库生效。指令文件在会话开始时读取：
     Claude Code 重启后生效，Codex 开启新会话后生效；闸门读的是常驻守护分支（通常是主分支）上已提交的脚本，
     提交进去之后才开始检查。
   - hook 与常驻守护分支配置在各 clone 的 `.git/` 里，不随仓库生效：其它 clone 各自执行一次
     `sh .githooks/install.sh`（从 `.githooks/branches` 读常驻守护分支；融入了 husky 等体系、设了 `core.hooksPath` 的，
     hook 由那套体系接管，改为执行 `sh .githooks/install.sh --branches-only`），同一 clone 的所有 worktree 共用，
     无需重复；规则也要求 agent 创建 worktree 前发现没装就补装。改常驻守护分支时改 `.githooks/branches` 并提交，
     各 clone 重新执行一次同样的命令才生效。
   - 重装时保留的只有：常驻守护分支里主分支以外的分支，以及没有 `python3` 时选过的「不要闸门」（写法 C）。
   - 用了写法 B 或 C 的：这条规则随仓库对全队生效；其他成员的环境满足条件（有 `python3`、git 2.28+）时，
     请在那台机器上重装恢复原文。
   - 选了不要闸门、而仓库里原来装过闸门的：仓库里留着闸门脚本，但规则按人工核对写；没有 `python3` 时 hook
     直接放行，不影响合并，`.githooks/` 与 hook 入口可自行删除。
   - git 在每次 ref 更新的每个阶段都会启动一次 hook。不涉及本地分支的调用在 shell 里就放行了，但进程启动
     本身的开销省不掉：rebase 一长串提交会慢上几秒，一次 fetch 几千个新 tag 或分支可能多出一分钟以上。

{{include: reinstall}}

本安装器的定制值：

- 回退闸门那条规则的写法：三选一，由第 4 步的表按当前环境（有没有 `python3`、git 版本）重新确定——
  模板原文（默认）、写法 B、写法 C。第 1 步记下旧原文，只用来认出写法 C：它记着用户选了不要闸门，没有 `python3` 时沿用。
- 常驻守护分支（`.githooks/branches`，没有这个文件时读 git 配置 `revert-gate.branch`）：主分支由项目现状得出，
  其余分支是用户加的。第 3 步读出，主分支重新确认，其余沿用旧值，第 5、6 步写回。

{{include: state-mismatch}}
