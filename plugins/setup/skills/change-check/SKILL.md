---
name: change-check
description: 装上（或更新）收尾时的改动检查：change-check skill 规定怎么派审查与处理意见，change-checker 子代理审本次改动，查缺失、逻辑错误与结构问题，只给意见不改文件。默认装进当前项目，也可安装到用户级配置、对当前用户环境中的所有项目生效。用于"给这个项目配代码审查""装 change-checker""改动检查加上项目自己的规范""更新审查规则"等场景。
disable-model-invocation: true
---

# 安装改动检查

装三样东西，缺一样都不完整：`change-check` skill（怎么派、意见怎么处理）、
`change-checker` 子代理（检查项与判断标准）、指令文件里的触发点（每次会话必读）。
三样都装齐就能独立工作，不依赖其它 setup。

## 跨宿主约定

只执行当前宿主对应的分支。模板资源先用 `$PLUGIN_ROOT`，为空再用 `$CLAUDE_PLUGIN_ROOT`；
两者都为空时，先把 `SKILL_DIR` 设为**当前已加载的这个 `SKILL.md` 的绝对父目录**（不是项目工作目录），
再按相对路径定位。执行写入前先确定：

```bash
if [ -n "${PLUGIN_ROOT:-}" ]; then
  SETUP_ROOT="$PLUGIN_ROOT"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  SETUP_ROOT="$CLAUDE_PLUGIN_ROOT"
else
  SETUP_ROOT="${SKILL_DIR:?先将 SKILL_DIR 设为当前 SKILL.md 的绝对父目录}/../.."
fi
TEMPLATE_DIR="$SETUP_ROOT/skills/change-check/template"
RENDER_AGENT="$SETUP_ROOT/scripts/render-codex-agent.py"
```

## 选作用域

**默认装进当前项目**，随仓库提交。用户明确说了「全局 / 用户级 / 所有项目 / 新电脑」，
或当前目录不是 git 仓库时，才装进用户级配置目录。

两层可以同时装：同名 skill 与子代理都以项目级为准，所以项目要定制时装一份项目级的，
不要去改用户级那份。

## 通用步骤

下面各宿主、各作用域的安装都按这四步走，区别只在目标路径，见后面各节。

1. **写入 skill**：先看目标 `SKILL.md` 在不在；已在就转「已存在时」，不要执行 `cp`——它会直接覆盖改过的那份。
2. **装子代理**：写入前发现同名文件就转「已存在时」，不要覆盖。Markdown 是唯一模板源，
   Codex 由共享脚本机械提取 `name`、`description` 与完整正文组装成 `.toml`，并写入 Codex 的
   模型、reasoning effort 与只读沙箱；不直接照搬 Claude Code 的 `model`、`effort`，也不改写正文。
3. **对齐项目**：只在项目安装时做。项目有审查时必须知道、与通用检查项不同的约定——编码规范文档在哪、
   哪类改动必须额外盯的风险点——就在装好的子代理「检查项」一节末尾加一张「本项目」表写进去
   （Codex 改 `.toml` 的 `developer_instructions`）。只写项目确实有的，没有就不加；
   已写在项目指令文件里的约定不要再抄一遍。
4. **挂触发点**：在目标指令文件里写明开发收尾时调用 `change-check` skill、**派 `change-checker` 子代理**做改动检查。
   只写触发时机——怎么派、意见怎么处理留在 skill 里，检查项留在子代理定义里，不要复制成第二份；
   什么算收尾由指令文件已有的规则或项目自己决定，不要另写一套。已有意思相同的说法就不再追加。

## Claude Code 项目安装（默认）

```bash
mkdir -p .claude/skills/change-check .claude/agents
cp "$TEMPLATE_DIR/change-check.md" .claude/skills/change-check/SKILL.md
cp -n "$TEMPLATE_DIR/agents/change-checker.md" .claude/agents/
```

`cp -n` 遇到同名文件会静默跳过，跳过了就转「已存在时」，不要当成装好了。
触发点写进项目根目录的 `CLAUDE.md`，它是符号链接时写它指向的实际文件。

**告知用户**：`.claude/skills/change-check/`、`.claude/agents/change-checker.md` 与 `CLAUDE.md` 的改动
要提交进版本库才随仓库生效；`.gitignore` 整体忽略了 `.claude/` 的项目要为这两处加例外。
装好后可用 `/change-check` 手动调用；`CLAUDE.md` 在会话开始时读取，下次会话生效。

## Claude Code 用户级安装

装进**当前会话的用户级配置目录**，由 `CLAUDE_CONFIG_DIR` 决定，没设就是 `~/.claude`；
下面用 `C` 指代它，不要写死路径。

```bash
C=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
mkdir -p "$C/skills/change-check" "$C/agents"
cp "$TEMPLATE_DIR/change-check.md" "$C/skills/change-check/SKILL.md"
cp -n "$TEMPLATE_DIR/agents/change-checker.md" "$C/agents/"
```

触发点写进 `$C/CLAUDE.md`。

**告知用户**：装到了哪个用户级配置目录要说清楚（用户可能开着多个）；重启 Claude Code 后生效。

## Codex 项目安装（默认）

```bash
mkdir -p .agents/skills/change-check .codex/agents
cp "$TEMPLATE_DIR/change-check.md" .agents/skills/change-check/SKILL.md
"$RENDER_AGENT" --output-dir .codex/agents "$TEMPLATE_DIR/agents/change-checker.md"
```

执行前先确认 `.codex/agents/change-checker.toml` 不存在。触发点写进项目根目录的 `AGENTS.md`，
它是符号链接时写它指向的实际文件。

**告知用户**：`.agents/skills/change-check/`、`.codex/agents/change-checker.toml` 与 `AGENTS.md` 的改动
要提交进版本库才随仓库生效；`.gitignore` 整体忽略了 `.codex/` 的项目要为 `.codex/agents/` 加例外。
开启新会话后生效。

## Codex 用户级安装

使用 `CODEX_HOME`；未设置时回退到 `$HOME/.codex`。`$HOME/.agents/skills/change-check` 已经有一份时
就地更新它，否则装到 `$X/skills/change-check`：

```bash
X=${CODEX_HOME:-$HOME/.codex}
if [ -d "$HOME/.agents/skills/change-check" ]; then
  D="$HOME/.agents/skills/change-check"
else
  D="$X/skills/change-check"
fi
mkdir -p "$D" "$X/agents"
cp "$TEMPLATE_DIR/change-check.md" "$D/SKILL.md"
"$RENDER_AGENT" --output-dir "$X/agents" "$TEMPLATE_DIR/agents/change-checker.md"
```

执行前先确认 `$X/agents/change-checker.toml` 不存在。触发点写进 `$X/AGENTS.md`。

**告知用户**：说明实际写入的用户级配置目录；重启 Codex 后生效。

## 已存在时

已有同名 skill 或子代理时不要覆盖：与模板逐节比对，补齐模板有而它没有的规则与检查项，
保留项目或用户自己加的内容。Codex 子代理与 Markdown 模板转换后的字段逐项比对，
不要另找或创建一份 TOML 模板。不要修改已安装 plugin 内的模板。
要动的地方超过补充规则的范围时，先把打算怎么改告诉用户。

## 现状与预期不符时

要写入的路径不是普通文件 / 目录时**停下来问用户**，不要照写。最常见的是软链：
`cp` 会写到它指向的地方，而 `mkdir -p` 在软链上仍然静默成功，表面看不出异常。
