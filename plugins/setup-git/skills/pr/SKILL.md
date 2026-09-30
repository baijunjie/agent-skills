---
name: pr
description: 给当前项目装上（或更新）提交 PR 的 git-pr skill：压平本地提交、推送并向本项目约定的目标分支提 PR，建好后清理本地分支与 worktree。安装时确定本项目默认的 PR 目标分支并写进 skill，调用时仍可另行指定。用于"装 git-pr skill""给项目配提 PR 的流程""统一 PR 提交方式"等场景。
disable-model-invocation: true
---

# 安装 git-pr skill

只装 `git-pr` skill 本体，不装子代理，也不改指令文件。装好后就能独立工作。

只做项目级安装：默认的 PR 目标分支因项目而异，要在安装时写进 skill，装进用户级就没法对所有项目都成立。
当前目录不是 git 仓库时停下来告诉用户。

## 跨宿主约定

只执行当前宿主对应的分支。模板资源先用 `$PLUGIN_ROOT`，为空再用 `$CLAUDE_PLUGIN_ROOT`；
两者都为空时，先把 `SKILL_DIR` 设为**当前已加载的这个 `SKILL.md` 的绝对父目录**（不是项目工作目录），
再按相对路径定位。执行写入前先确定：

```bash
if [ -n "${PLUGIN_ROOT:-}" ]; then
  TEMPLATE_DIR="$PLUGIN_ROOT/skills/pr/template"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  TEMPLATE_DIR="$CLAUDE_PLUGIN_ROOT/skills/pr/template"
else
  TEMPLATE_DIR="${SKILL_DIR:?先将 SKILL_DIR 设为当前 SKILL.md 的绝对父目录}/template"
fi
```

## 确定默认的 PR 目标分支

用户调用时直接给了分支就用它，不再探索。否则按下面的依据判断：

- 最近约 20 个已合并 PR 的目标分支——最直接的证据，多数提往同一分支时就是它。
  用远端所在平台的 CLI 或 API 查（GitHub 用 `gh`），查不了就跳过这条。
- 项目文档（README、CONTRIBUTING、agent 指令文件等）里对提 PR 分支的约定。
- 远端的默认分支。它只说明仓库首页显示哪个分支，远端另有 `develop`、`pre-release`、`staging`
  之类持续接收合并的集成分支时，不能单凭它断定。

| 情况 | 做法 |
|---|---|
| 依据一致指向同一分支 | 直接采用，装完告诉用户用的是哪个、依据是什么 |
| 只查到远端默认分支，且远端没有别的集成分支 | 采用默认分支，同样告诉用户 |
| 依据互相矛盾，或只剩远端默认分支而远端还有别的集成分支 | 列出候选和各自的依据，问用户 |
| 什么都查不到 | 问用户 |

## 通用步骤

写入前先看目标 `SKILL.md` 在不在；已在就转「已存在时」，不要执行下面的写入——它会直接覆盖改过的那份。
写入时把模板里的 `{{PR_BASE}}` 替换为确定的分支名：先设 `BASE=<分支名>`，分支名含 `&` 或 `|` 时先转义；
写完确认已无残留占位符。

## Claude Code 安装

```bash
mkdir -p .claude/skills/git-pr
sed "s|{{PR_BASE}}|$BASE|g" "$TEMPLATE_DIR/git-pr.md" > .claude/skills/git-pr/SKILL.md
```

**告知用户**：`.claude/skills/git-pr/` 要提交进版本库才随仓库生效；
`.gitignore` 整体忽略了 `.claude/` 的项目要为它加例外。装好后可用 `/git-pr` 调用，也会按描述自动触发；
`/git-pr <分支>` 可临时提到别的分支。

## Codex 安装

```bash
mkdir -p .agents/skills/git-pr
sed "s|{{PR_BASE}}|$BASE|g" "$TEMPLATE_DIR/git-pr.md" > .agents/skills/git-pr/SKILL.md
```

**告知用户**：`.agents/skills/git-pr/` 要提交进版本库才随仓库生效。开启新会话后生效；
`$git-pr <分支>` 可临时提到别的分支。

## 已存在时

已有同名 skill 时不要覆盖：与模板逐节比对，补齐模板有而它没有的规则，
保留项目自己加的内容。默认目标分支沿用已装文件里记录的那个（补进的规则里的占位符也替换成它），
除非用户这次明确指定了新的。
不要修改已安装 plugin 内的模板。要动的地方超过补充规则的范围时，先把打算怎么改告诉用户。

## 现状与预期不符时

要写入的路径不是普通文件 / 目录时**停下来问用户**，不要照写。最常见的是软链：
重定向写入会写到它指向的地方，而 `mkdir -p` 在软链上仍然静默成功，表面看不出异常。
