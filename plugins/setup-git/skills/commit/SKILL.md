---
name: commit
description: 装上（或更新）按 Conventional Commits 规范生成提交的 git-commit skill。默认装进当前项目，随仓库提交、团队共用，也可安装到用户级配置、对当前用户环境中的所有项目生效。用于"装 git-commit skill""给项目配提交规范""统一 commit message 格式""新电脑装提交规范"等场景。
disable-model-invocation: true
---

# 安装 git-commit skill

只装 `git-commit` skill 本体，不装子代理，也不改指令文件。装好后就能独立工作。

## 跨宿主约定

只执行当前宿主对应的分支。模板资源先用 `$PLUGIN_ROOT`，为空再用 `$CLAUDE_PLUGIN_ROOT`；
两者都为空时，先把 `SKILL_DIR` 设为**当前已加载的这个 `SKILL.md` 的绝对父目录**（不是项目工作目录），
再按相对路径定位。执行写入前先确定：

```bash
if [ -n "${PLUGIN_ROOT:-}" ]; then
  TEMPLATE_DIR="$PLUGIN_ROOT/skills/commit/template"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  TEMPLATE_DIR="$CLAUDE_PLUGIN_ROOT/skills/commit/template"
else
  TEMPLATE_DIR="${SKILL_DIR:?先将 SKILL_DIR 设为当前 SKILL.md 的绝对父目录}/template"
fi
```

## 选作用域

**默认装进当前项目**，随仓库提交，团队共用。用户明确说了「全局 / 用户级 / 所有项目 / 新电脑」，
或当前目录不是 git 仓库时，才装进用户级配置目录。

两层可以同时装：同名 skill 以项目级为准，所以项目要定制时装一份项目级的，
不要去改用户级那份。

## 通用步骤

写入前先看目标 `SKILL.md` 在不在；已在就转「已存在时」，不要执行 `cp`——它会直接覆盖改过的那份。
各宿主、各作用域的区别只在目标路径，见后面各节。

## Claude Code 项目安装（默认）

```bash
mkdir -p .claude/skills/git-commit
cp "$TEMPLATE_DIR/git-commit.md" .claude/skills/git-commit/SKILL.md
```

**告知用户**：`.claude/skills/git-commit/` 要提交进版本库才随仓库生效；
`.gitignore` 整体忽略了 `.claude/` 的项目要为它加例外。装好后可用 `/git-commit` 调用，也会按描述自动触发。

## Claude Code 用户级安装

装进**当前会话的用户级配置目录**，由 `CLAUDE_CONFIG_DIR` 决定，没设就是 `~/.claude`；
下面用 `C` 指代它，不要写死路径。

```bash
C=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
mkdir -p "$C/skills/git-commit"
cp "$TEMPLATE_DIR/git-commit.md" "$C/skills/git-commit/SKILL.md"
```

**告知用户**：装到了哪个用户级配置目录要说清楚（用户可能开着多个）；重启 Claude Code 后生效。

## Codex 项目安装（默认）

```bash
mkdir -p .agents/skills/git-commit
cp "$TEMPLATE_DIR/git-commit.md" .agents/skills/git-commit/SKILL.md
```

**告知用户**：`.agents/skills/git-commit/` 要提交进版本库才随仓库生效。开启新会话后生效。

## Codex 用户级安装

使用 `CODEX_HOME`；未设置时回退到 `$HOME/.codex`。`$HOME/.agents/skills/git-commit` 已经有一份时
就地更新它，否则装到 `$X/skills/git-commit`：

```bash
X=${CODEX_HOME:-$HOME/.codex}
if [ -d "$HOME/.agents/skills/git-commit" ]; then
  D="$HOME/.agents/skills/git-commit"
else
  D="$X/skills/git-commit"
fi
mkdir -p "$D"
cp "$TEMPLATE_DIR/git-commit.md" "$D/SKILL.md"
```

**告知用户**：说明实际写入的用户级配置目录；重启 Codex 后生效。

## 已存在时

已有同名 skill 时不要覆盖：与模板逐节比对，补齐模板有而它没有的规则，
保留项目或用户自己加的内容。不要修改已安装 plugin 内的模板。
要动的地方超过补充规则的范围时，先把打算怎么改告诉用户。

## 现状与预期不符时

要写入的路径不是普通文件 / 目录时**停下来问用户**，不要照写。最常见的是软链：
`cp` 会写到它指向的地方，而 `mkdir -p` 在软链上仍然静默成功，表面看不出异常。
