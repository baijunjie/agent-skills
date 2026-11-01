---
name: revert-gate
description: {{scope_lead}}回退闸门——受守护分支移动或推送时按内容检查，拦下改写已发布历史、撤销已有改动的更新。{{scope_tail}}用于"装回退闸门""防止合并时悄悄撤销别人的改动""给主分支加 hook 保护"等场景。
disable-model-invocation: true
---

# 安装项目级回退闸门

装两样东西，都只装进当前项目：随仓库提交的闸门脚本与常驻守护分支列表（`.githooks/` 下），以及各 clone 自己的 hook 入口。
受守护的分支（常驻守护分支，加上各分支 `branch.<分支>.targetBranch` 记下的目标分支）移动时，本地 merge / commit / reset
与 push 都会被检查，拒绝改写已发布的历史、以及撤销该分支已有改动的更新；记了 `targetBranch` 的分支自己被推送时，
按内容核对它相对目标分支远端尖端有没有撤销已有改动。

目标分支与切出点（`branch.<分支>.forkPoint`）由 `setup-git:pr`、`setup-git:worktree` 装出的流程脚本记录，本安装器只读不写；
没装那两个的仓库只守常驻守护分支，靠切出点的那条判据（撤销纯新增的提交、删掉只追加过的文件）不生效。
本安装器不写指令文件、不装 skill：被拦下时怎么复原、怎么处理写在闸门的拒绝信息里。当前目录不是 git 仓库时汇报并停下。

## 跨宿主约定

两个宿主装出的内容相同，下面的命令与宿主无关。

{{include: host-conventions}}

{{include: pre-write}}

本安装器另外要查的冲突：

- hook 入口：配置文件里设了 `core.hooksPath`（以 `env -u GIT_CONFIG_COUNT -u GIT_CONFIG_PARAMETERS git config core.hooksPath`
  有输出为准；`-c` 或环境变量 `GIT_CONFIG_COUNT` 临时给的不算），或 `$(git rev-parse --git-common-dir)/hooks/` 下已有不含
  `# revert-gate hook entry` 一行的 `reference-transaction` / `pre-push`。两个 hook 逐个判定。完全覆盖会让原来那套 hook 失效，询问时说明；
  `core.hooksPath` 不在本仓库自己的配置里（`git config --show-scope core.hooksPath` 不是 `local`）的，不提供完全覆盖，只能融入：
  改全局或系统配置会影响本机所有仓库；询问时说明融入的调用会写进本机所有仓库共用的 hook 文件。入口里已调用 `.githooks/hook.sh` 的，按第 5 步「融入」那一行处理，不算冲突；
  融入写在对方体系自己的文件里，本安装器重装时不碰，以后一直保留，不适用「写入前检查」里「融入只对这一次有效」的说法。
- `.githooks/` 下的 `revert-gate.py`、`hook.sh`、`install.sh`、`branches` 是本安装器装出的，已有的按装过处理；
  `.githooks/` 里别的文件（如 `setup-git:pr`、`setup-git:worktree` 装的 `flow-*.sh`）不碰。

## 项目级安装

1. **确认环境**：闸门脚本要 `python3`，本地 merge / commit / reset 那一层（reference-transaction）另要 git 2.28+。
   没有 `python3` 的，问用户是装 Python 还是不装闸门：不装闸门的不写任何文件，结束；装好 Python 的继续。
   git 低于 2.28 的照装，只有 push 那一层生效，告知用户。
2. **确认主分支名**：主分支取远端的默认分支（`git symbolic-ref --short refs/remotes/origin/HEAD` 去掉远端前缀，或远端仓库设置里的默认分支），
   定不下来的：已装过的沿用旧文件第一行，不问；首次安装问用户；不按当前检出的分支推断。第 4 步把它写成常驻守护分支。已装过的，从 `.githooks/branches`
   读出上次的常驻守护分支（忽略空行与 `#` 开头的行）：旧文件第一行就是上次的主分支，与这次定出的不一致时，
   按「重装」里由现状推导的定制值处理；其余行是用户加的，第 4 步一并写回。
3. **复制闸门脚本**：模板里只有 `revert-gate.py`、`hook.sh`、`install.sh` 三个文件，不含 `branches`。保留可执行位，已有的同名文件直接覆盖，`.githooks/` 里别的文件不动：

   ```bash
   {{include: project-root}}
   : "${TEMPLATE_DIR:?}"
   mkdir -p .githooks && cp -p "$TEMPLATE_DIR/"* .githooks/
   ```
4. **写常驻守护分支列表**：整个重写随仓库提交的 `.githooks/branches`，每行一个分支，主分支放第一行，
   其后是第 2 步沿用的其它分支。文件开头写一行 `#` 注释，说明这是回退闸门的常驻守护分支、主分支在第一行，
   `sh .githooks/install.sh` 不带参数时从这里读。各分支记录的目标分支另外自动受守护，不写进来。
5. **接 hook 入口**：按「写入前检查」里 hook 入口的冲突结果，三种接法选一：

   | 情况 | 做法 |
   |---|---|
   | 没有冲突 | 直接装：执行下面的命令（可重复执行），它按 `.githooks/branches` 写好本 clone 的常驻守护分支配置 |
   | 用户选完全覆盖 | 按询问时说给用户的改法撤掉原来那套入口（如 `git config --unset core.hooksPath`、移走原 hook 文件），再按直接装执行 |
   | 用户选融入，或入口里已调用 `.githooks/hook.sh` | 在那套体系（如 husky）的 `reference-transaction` 与 `pre-push` 里各调用一次 `[ ! -f .githooks/hook.sh ] || sh .githooks/hook.sh <所在 hook 的名字> "$@"`（原样转发 stdin；还没有 `.githooks/` 的分支或 worktree 里跳过，不然 reference-transaction 失败会让所有 ref 更新失败，代价是在那些地方两层检查都不生效，询问时说明），怎么接由用户定；已调用的不重复接。然后执行 `sh .githooks/install.sh --branches-only`：只按 `.githooks/branches` 写本 clone 的常驻守护分支配置，不装 hook（不带这个参数会因同一原因报错退出） |

   直接装的命令：

   ```bash
   {{include: project-root}}
   sh .githooks/install.sh
   ```

   有些体系（如 husky v9）不生成 `reference-transaction`，接不上时只剩 pre-push 一层，要告知用户。
   不带参数的 `install.sh` 报 `core.hooksPath` 已设置或同名 hook 已存在，是事先漏查了这项冲突，先按「写入前检查」问用户。
6. **告知用户**：
   - `.githooks/`（含 `branches`）要提交进版本库才随仓库生效；闸门读的是受守护分支上已提交的那份脚本
     （常驻守护分支优先），提交并合进主分支之后才开始检查。
   - hook 与常驻守护分支配置在各 clone 的 `.git/` 里，不随仓库生效：其它 clone 各自执行一次 `sh .githooks/install.sh`
     （hook 由 husky 等体系接管的改为按第 5 步接进那套体系，再执行 `sh .githooks/install.sh --branches-only`），
     同一 clone 的所有 worktree 共用；`setup-git:pr`、`setup-git:worktree` 的流程脚本记录目标分支时，发现本 clone 没装会提示。
     改常驻守护分支时改 `.githooks/branches` 并提交，各 clone 重新执行一次同样的命令才生效。
   - 被拦下时的复原与处理写在拒绝信息里；确属有意撤销的，用 `git revert`，或在撤销它的提交信息里为每个被撤销的提交加一行 `Reverts: <sha>`。
     `git push --no-verify` 跳过 pre-push 一层，`REVERT_GATE_SKIP=1` 整体跳过，只供人确认过的场合使用。
   - git 每次 ref 更新的每个阶段都会启动一次 hook：rebase 一长串提交会慢上几秒，一次 fetch 几千个新 tag 或分支可能多出一分钟以上。

{{include: reinstall}}

本安装器的定制值：

- 常驻守护分支（`.githooks/branches`）：第一行的主分支由项目现状推导，比对时与第 2 步这次定出的不一致算有变更；
  其余行是用户加的，比对时不算。第 2 步读出，主分支重新确认，其余沿用旧值，第 4、5 步写回。

{{include: state-mismatch}}
