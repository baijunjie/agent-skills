---
name: pr
description: {{scope_lead}}提 PR 的 git-pr skill，连同推送时拦下撤销目标分支已有改动的回退闸门。{{scope_tail}}用于"装 git-pr skill""给项目配提 PR 的流程""统一 PR 提交方式"等场景。
disable-model-invocation: true
---

# 安装 git-pr skill

装两样东西：提 PR 的操作步骤 `git-pr` skill（压平、rebase、预检、推送、提 PR、清理），以及回退闸门——
推送记了目标分支（`branch.<分支>.targetBranch`，与 `setup-git:worktree` 共用这个键）的分支时按内容检查，
拒绝撤销目标分支已有改动的推送，目标分支也因此受守护。装出的 skill 靠 description 自动触发，本安装器不写指令文件。

只做项目级安装：默认的 PR 目标分支因项目而异，要在安装时写进 skill。当前目录不是 git 仓库时汇报并停下。
闸门脚本由 `setup-git` 下的 `pr` 与 `worktree` 两个安装器共用，装到项目的同一个 `.githooks/`。

## 跨宿主约定

只执行当前宿主对应的分支。

{{include: host-conventions}}

{{include: skill-priority-project}}

{{include: pre-write}}

本安装器另外要查的冲突：

{{include: gate-conflicts}}

## 确定默认的 PR 目标分支

模板里要填的只有 `{{pr_base_token}}` 一处：本项目默认的 PR 目标分支，由项目现状得出，依据不足时由用户选定，没有固定选项。
调用本安装器时直接给了分支就用它，不再探索。否则按下面的依据判断：

- 最近约 20 个已合并 PR 的目标分支：最直接的证据，多数提往同一分支时就是它；查不了就跳过。
- 项目文档（README、CONTRIBUTING、agent 指令文件等）里对提 PR 分支的约定。
- 远端的默认分支：它只说明仓库首页显示哪个分支，远端另有 `develop`、`pre-release`、`staging`
  之类持续接收合并的集成分支时，不能单凭它断定。

| 情况 | 做法 |
|---|---|
| 依据一致指向同一分支 | 直接采用，装完告知用户用的是哪个、依据是什么 |
| 只查到远端默认分支，且远端没有别的集成分支 | 采用默认分支，同样告知用户 |
| 依据互相矛盾，或只剩远端默认分支而远端还有别的集成分支 | 列出候选和各自的依据，问用户 |
| 什么都查不到 | 问用户 |

已装过的，先从旧 skill 里标着「（本项目默认的 PR 目标分支）」的那个分支读出上次定下的值（可能是用户选的）：
表里直接采用的两种情况以依据为准，与旧值不同要告知用户；要问用户的两种情况改为沿用旧值，不再问。

## 装回退闸门

闸门的 PR 一层在 `pre-push` 上，只要 `python3`；装出的 skill 会把目标分支记进 `targetBranch`，
目标分支因此受守护，本地 merge / commit / reset 动它时走 reference-transaction 那一层，要 git 2.28+。先确认两者：

| 环境 | 做法 |
|---|---|
| 有 `python3`、git 2.28+ | 执行复制闸门脚本的命令块，再按下表接 hook 入口 |
| 有 `python3`、git 低于 2.28 | 同上照做；本地 merge / commit / reset 那一层不生效，告知用户 |
| 没有 `python3` | 问用户是装 Python 还是不要闸门。装 Python 的装好后照上两行；不要闸门的两个命令块都不执行，已有的 `.githooks/` 与 hook 入口也不删——装出的 skill 自己会查闸门脚本在不在，不在就走人工核对，skill 正文不改写 |

复制闸门脚本（保留可执行位，已有的同名文件直接覆盖，`.githooks/` 里别的文件不动）：

```bash
{{include: project-root}}
: "${GATE_DIR:?}"
mkdir -p .githooks && cp -p "$GATE_DIR/"* .githooks/
```

接 hook 入口，按「写入前检查」里 hook 入口的冲突结果三选一：

| 情况 | 做法 |
|---|---|
| 没有冲突 | 直接装：执行下面的命令（可重复执行） |
| 用户选完全覆盖 | 按询问时说给用户的改法撤掉原来那套入口（如 `git config --unset core.hooksPath`、移走原 hook 文件），再按直接装执行 |
| 用户选融入，或入口里已调用 `.githooks/hook.sh` | 在那套体系（如 husky）的 `pre-push` 里调用一次 `sh .githooks/hook.sh pre-push "$@"`（原样转发 stdin），怎么接由用户定；已调用的不重复接。不执行下面的命令——它会因同一原因报错退出 |

直接装的命令（`--pr-only` 只装 hook 入口，不写也不清常驻守护分支，那是 `setup-git:worktree` 的定制值）：

```bash
{{include: project-root}}
sh .githooks/install.sh --pr-only
```

命令报 `core.hooksPath` 已设置或同名 hook 已存在，是事先漏查了这项冲突，先按「写入前检查」问用户。

**告知用户**（选了「不要闸门」的只说第三条）：

- `.githooks/` 要提交进版本库才随仓库生效；闸门读的是目标分支上已提交的那份脚本，提交并推送之后才开始检查。
- hook 在各 clone 自己的 `.git/` 里、不随仓库生效：其它 clone 各自执行一次 `sh .githooks/install.sh --pr-only`
  （融入了 husky 等体系的改为按上表接进那套体系），同一 clone 的所有 worktree 共用；skill 也要求 agent 推送前发现没装就补装。
- 选了「不要闸门」的：装出的 skill 会走人工核对；这个选择没有载体，下次重装还会再问。
- git 每次 ref 更新的每个阶段都会启动一次 hook：rebase 一长串提交会慢上几秒，一次 fetch 几千个新 tag 或分支可能多出一分钟以上。

## 通用步骤

写入时把模板里的 `{{pr_base_token}}` 替换为确定的分支名：先设 `BASE=<分支名>`，分支名含 `&` 或 `|` 时先转义；
命令块开头断言 `BASE` 非空（为空会把占位符替换成空串、查不出残留），写完确认已无残留占位符。
告知用户时，除各安装节列的外，说明重装时只有默认目标分支会按项目现状重新确定（确定不了才沿用旧值），其余按模板覆盖。

## Claude Code 项目级安装

```bash
{{include: project-root}}
: "${TEMPLATE_DIR:?}" "${BASE:?}"
mkdir -p .claude/skills/git-pr
sed "s|{{pr_base_token}}|$BASE|g" "$TEMPLATE_DIR/git-pr/SKILL.template.md" > .claude/skills/git-pr/SKILL.md
```

**告知用户**：`.claude/skills/git-pr/` 要提交进版本库才随仓库生效；
`.gitignore` 整体忽略了 `.claude/` 的项目要为它加例外。装好后可用 `/git-pr` 调用，也会按描述自动触发；
`/git-pr <分支>` 可临时提到别的分支。如未生效，重启 Claude Code。

## Codex 项目级安装

```bash
{{include: project-root}}
: "${TEMPLATE_DIR:?}" "${BASE:?}"
mkdir -p .agents/skills/git-pr
sed "s|{{pr_base_token}}|$BASE|g" "$TEMPLATE_DIR/git-pr/SKILL.template.md" > .agents/skills/git-pr/SKILL.md
```

**告知用户**：`.agents/skills/git-pr/` 要提交进版本库才随仓库生效；
`.gitignore` 整体忽略了 `.agents/` 的项目要为它加例外。开启新会话后生效；`$git-pr <分支>` 可临时提到别的分支。

{{include: reinstall}}

本安装器的定制值：

- 默认的 PR 目标分支：旧 skill 里标着「（本项目默认的 PR 目标分支）」的那个分支。在「确定默认的 PR 目标分支」一节读出、
  重新判断，写入时填进模板的 `{{pr_base_token}}`。

{{include: state-mismatch}}
