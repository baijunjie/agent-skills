---
name: pr
description: {{scope_lead}}提交 PR 的 git-pr skill：压平本地提交、推送并向本项目约定的目标分支提 PR，建好后清理本地分支与 worktree。安装时确定本项目默认的 PR 目标分支并写进 skill，调用时仍可另行指定。{{scope_tail}}用于"装 git-pr skill""给项目配提 PR 的流程""统一 PR 提交方式"等场景。
disable-model-invocation: true
---

# 安装 git-pr skill

装出的 skill 靠 description 自动触发，本安装器不往指令文件写任何内容。

只做项目级安装：默认的 PR 目标分支因项目而异，要在安装时写进 skill，装进用户级就没法对所有项目都成立。
当前目录不是 git 仓库时停下来汇报。

## 跨宿主约定

只执行当前宿主对应的分支。

{{include: host-conventions}}

{{include: skill-priority-project}}

{{include: pre-write}}

本安装器另外要查的冲突：无。

## 确定默认的 PR 目标分支

模板里要填的只有 `{{pr_base_token}}` 一处：本项目默认的 PR 目标分支。值由项目现状得出，依据不足时由用户选定，没有固定选项。

调用本安装器时直接给了分支就用它，不再探索。否则按下面的依据判断：

- 最近约 20 个已合并 PR 的目标分支——最直接的证据，多数提往同一分支时就是它。
  查不了就跳过这条。
- 项目文档（README、CONTRIBUTING、agent 指令文件等）里对提 PR 分支的约定。
- 远端的默认分支。它只说明仓库首页显示哪个分支，远端另有 `develop`、`pre-release`、`staging`
  之类持续接收合并的集成分支时，不能单凭它断定。

| 情况 | 做法 |
|---|---|
| 依据一致指向同一分支 | 直接采用，装完告知用户用的是哪个、依据是什么 |
| 只查到远端默认分支，且远端没有别的集成分支 | 采用默认分支，同样告知用户 |
| 依据互相矛盾，或只剩远端默认分支而远端还有别的集成分支 | 列出候选和各自的依据，问用户 |
| 什么都查不到 | 问用户 |

已装过的，旧 skill 里「没指定就提到 `<分支>`」那句的分支是上次定下的，可能是用户选的，先读出来：
表里直接采用的两种情况以依据为准，与旧值不同要告知用户；要问用户的两种情况改为沿用旧值，不再问。

## 通用步骤

写入时把模板里的 `{{pr_base_token}}` 替换为确定的分支名：先设 `BASE=<分支名>`，分支名含 `&` 或 `|` 时先转义；
`BASE` 为空会让占位符被替换成空串、查不出残留，所以命令块开头先断言变量非空；写完确认已无残留占位符。
告知用户时，除各安装节列的外，说明重装时保留的只有默认目标分支。

## Claude Code 项目级安装

```bash
{{include: project-root}}
: "${TEMPLATE_DIR:?}" "${BASE:?}"
mkdir -p .claude/skills/git-pr
sed "s|{{pr_base_token}}|$BASE|g" "$TEMPLATE_DIR/git-pr.md" > .claude/skills/git-pr/SKILL.md
```

**告知用户**：`.claude/skills/git-pr/` 要提交进版本库才随仓库生效；
`.gitignore` 整体忽略了 `.claude/` 的项目要为它加例外。装好后可用 `/git-pr` 调用，也会按描述自动触发；
`/git-pr <分支>` 可临时提到别的分支。如未生效，重启 Claude Code。

## Codex 项目级安装

```bash
{{include: project-root}}
: "${TEMPLATE_DIR:?}" "${BASE:?}"
mkdir -p .agents/skills/git-pr
sed "s|{{pr_base_token}}|$BASE|g" "$TEMPLATE_DIR/git-pr.md" > .agents/skills/git-pr/SKILL.md
```

**告知用户**：`.agents/skills/git-pr/` 要提交进版本库才随仓库生效；
`.gitignore` 整体忽略了 `.agents/` 的项目要为它加例外。开启新会话后生效；`$git-pr <分支>` 可临时提到别的分支。

{{include: reinstall}}

本安装器的定制值：

- 默认的 PR 目标分支：旧 skill 里「没指定就提到 `<分支>`」那句的分支。在「确定默认的 PR 目标分支」一节读出、
  重新判断，写入时填进模板的 `{{pr_base_token}}`。

{{include: state-mismatch}}
