---
name: report-style
description: 装上（或更新）Concise+ 回答规则，让 Claude Code 使用自定义 output style，Codex 把等价规则合并进 AGENTS.md。默认装进当前项目，也可安装到用户级配置。用于"agent 报告太啰嗦""让它少说废话只给结论""别顺着我说""配输出风格""装 output style"等场景。
disable-model-invocation: true
---

# 安装输出风格 Concise+

内置 `Concise` 的基础上补两类硬要求：**需要用户拍板的事项与没搞清楚的疑问**必须单独列出、
不许混在正文里；**不附和**——不先肯定再转折，分歧当分歧说。

## 跨宿主约定

只执行当前宿主对应的安装分支。

模板资源先用 `$PLUGIN_ROOT`，为空再用 `$CLAUDE_PLUGIN_ROOT`；两者都为空时，先把 `SKILL_DIR`
设为**当前已加载的这个 `SKILL.md` 的绝对父目录**（不是项目工作目录），再按相对路径定位。执行写入前先确定：

```bash
if [ -n "${PLUGIN_ROOT:-}" ]; then
  TEMPLATE_DIR="$PLUGIN_ROOT/skills/report-style/template"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  TEMPLATE_DIR="$CLAUDE_PLUGIN_ROOT/skills/report-style/template"
else
  TEMPLATE_DIR="${SKILL_DIR:?先将 SKILL_DIR 设为当前 SKILL.md 的绝对父目录}/template"
fi
```

## 选作用域

**默认装进当前项目**，随仓库提交。

用户明确说了「全局 / 用户级 / 所有项目 / 新电脑」，或当前目录不是 git 仓库时，
才走「用户级安装」——那一份对当前用户环境中的所有项目生效。

## Codex 安装

Codex 没有 Claude Code 的 output style 机制。把等价规则合并到指令文件，不创建
`.claude/output-styles/`，也不修改 `.claude/settings.json`。

### 项目安装（默认）

1. **追加规则节**：目标是项目根目录的 `AGENTS.md`，没有就新建；它是符号链接时写它指向的实际文件。
   先看有没有「输出风格：Concise+」节；有就转「已存在时」，不要重复追加。

   ```bash
   cat "$TEMPLATE_DIR/agents.md" >> AGENTS.md
   ```

2. **告知用户**：`AGENTS.md` 的改动要提交进版本库；当前会话不会自动重读，下次会话生效。

### 用户级安装

把同一规则追加到当前 Codex 用户级配置目录的 `AGENTS.md`。使用 `CODEX_HOME`；未设置时回退到
`$HOME/.codex`。先检查同名节，避免重复。

```bash
X=${CODEX_HOME:-$HOME/.codex}
mkdir -p "$X"
cat "$TEMPLATE_DIR/agents.md" >> "$X/AGENTS.md"
```

先确认 `$X/AGENTS.md` 没有「输出风格：Concise+」节再执行；说明实际写入的用户级配置目录。重启 Codex 后生效。

## Claude Code 项目安装（默认）

1. **写入风格文件**：

   ```bash
   mkdir -p .claude/output-styles
   cp -n "$TEMPLATE_DIR/output-styles/concise-plus.md" .claude/output-styles/
   ```

   目标已存在时 `cp -n` 会静默跳过，跳过了就转「已存在时」，不要当成装好了。
2. **启用**：在项目的 `.claude/settings.json` 里设 `"outputStyle": "Concise+"`。
   **不要让用户靠 `/output-style` 或 `/config` 菜单来启用**——那两个入口写的是
   `.claude/settings.local.json`，不进版本库，只在当前用户环境生效；要随仓库走得写进 `settings.json`。
3. **告知用户**：`.claude/output-styles/concise-plus.md` 与 `settings.json` 的改动要提交进版本库；
   `.gitignore` 整体忽略了 `.claude/` 的项目要为这两个文件加例外，否则改了也提交不进去。
   其余见「装完都要说的」。

## Claude Code 用户级安装

装进**当前会话的用户级配置目录**，对当前用户环境中的所有项目生效。这个目录由 Claude Code 的
`CLAUDE_CONFIG_DIR` 决定，没设就是 `~/.claude`；下面的命令用 `C` 指代它，不要写死路径。

1. **写入风格文件**：

   ```bash
   C=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
   mkdir -p "$C/output-styles"
   cp -n "$TEMPLATE_DIR/output-styles/concise-plus.md" "$C/output-styles/"
   ```

   已存在时 `cp -n` 会静默跳过，跳过了就转「已存在时」，不要当成装好了。
2. **启用**：在 `$C/settings.json` 里设 `"outputStyle": "Concise+"`。
   用户自己用 `/output-style Concise+` 或 `/config` 菜单切也行，但那两个入口写的是当前项目的
   `.claude/settings.local.json`，只对那个项目生效，**替代不了用户级的 `settings.json`**。
3. **告知用户**：装到了哪个用户级配置目录要说清楚（用户可能开着多个）；其余见「装完都要说的」。

## Claude Code 装完都要说的

- 风格文件在启动时读取，**重启 Claude Code 才生效**。
- 同一时刻只能启用一个 output style，启用它就用不了 `Explanatory` / `Learning`；
  想临时切回内置，用 `/output-style <名字>` 或 `/config` 的 Output style 一项。
- 用户级与项目里各有一份同名风格时，内容一致没有影响；不一致就告诉用户两份都在、
  内容差在哪，留哪份由他定。

## 已存在时

宿主目标已有同名规则或风格文件时不要覆盖：与对应模板逐条比对，补齐模板有而它没有的规则，保留当前用户环境或当前项目已有的补充内容。
不要修改已安装 plugin 内的模板。
要动的地方超过补充规则的范围时，先把打算怎么改告诉用户。

## 现状与预期不符时

要写入的路径不是普通文件 / 目录时**停下来问用户**，不要照写。最常见的是软链：
`cp` 会写到它指向的地方，而 `mkdir -p` 在软链上仍然静默成功，表面看不出异常。
