---
name: report-style
description: 装上（或更新）自定义 output style「Concise+」，让 Claude Code 的回答只给结果、不复述过程，需要确认的事项与疑问必须显式列出，且不先肯定再转折。默认装进当前项目，也可装成本机用户级。用于"agent 报告太啰嗦""让它少说废话只给结论""别顺着我说""配输出风格""装 output style"等场景。
disable-model-invocation: true
---

# 安装输出风格 Concise+

内置 `Concise` 的基础上补两类硬要求：**需要用户拍板的事项与没搞清楚的疑问**必须单独列出、
不许混在正文里；**不附和**——不先肯定再转折，分歧当分歧说。

补充说明（可选）：

<task>
$ARGUMENTS
</task>

## 选作用域

**默认装进当前项目**，随仓库提交。

用户明确说了「全局 / 本机 / 用户级 / 所有项目 / 新电脑」，或当前目录不是 git 仓库时，
才走「用户级安装」——那一份只对这台机器上的自己生效。

## 项目安装（默认）

1. **写入风格文件**：

   ```bash
   mkdir -p .claude/output-styles
   cp -n "$CLAUDE_PLUGIN_ROOT/skills/report-style/template/output-styles/concise-plus.md" .claude/output-styles/
   ```

   `$CLAUDE_PLUGIN_ROOT` 为空时用本 skill 目录下的 `template/`。
   目标已存在时 `cp -n` 会静默跳过，跳过了就转「已存在时」，不要当成装好了。
2. **启用**：在项目的 `.claude/settings.json` 里设 `"outputStyle": "Concise+"`。
   **不要让用户靠 `/output-style` 或 `/config` 菜单来启用**——那两个入口写的是
   `.claude/settings.local.json`，不进版本库，只对当下这台机器生效；要随仓库走得写进 `settings.json`。
3. **告知用户**：`.claude/output-styles/concise-plus.md` 与 `settings.json` 的改动要提交进版本库；
   `.gitignore` 整体忽略了 `.claude/` 的项目要为这两个文件加例外，否则改了也提交不进去。
   其余见「装完都要说的」。

## 用户级安装

装进 Claude Code 的配置目录 `~/.claude`，对这台机器上的所有项目生效。

1. **写入风格文件**：

   ```bash
   mkdir -p ~/.claude/output-styles
   cp -n "$CLAUDE_PLUGIN_ROOT/skills/report-style/template/output-styles/concise-plus.md" ~/.claude/output-styles/
   ```

   `$CLAUDE_PLUGIN_ROOT` 为空时用本 skill 目录下的 `template/`。
   已存在时 `cp -n` 会静默跳过，跳过了就转「已存在时」，不要当成装好了。
2. **启用**：在 `~/.claude/settings.json` 里设 `"outputStyle": "Concise+"`。
   用户自己用 `/output-style Concise+` 或 `/config` 菜单切也行，但那两个入口写的是当前项目的
   `.claude/settings.local.json`，只对那个项目生效，**替代不了 `~/.claude/settings.json`**。
3. **告知用户**：见「装完都要说的」。

## 装完都要说的

- 风格文件在启动时读取，**重启 Claude Code 才生效**。
- 同一时刻只能启用一个 output style，启用它就用不了 `Explanatory` / `Learning`；
  想临时切回内置，用 `/output-style <名字>` 或 `/config` 的 Output style 一项。
- `~/.claude/` 与项目里各有一份同名风格时，内容一致没有影响；不一致就告诉用户两份都在、
  内容差在哪，留哪份由他定。

## 已存在时

已有的风格文件不要覆盖：与模板逐条比对，补齐模板有而它没有的规则，保留本机 / 本项目自己加的。
反过来，本机有而模板没有、且不是这台机器专属的内容，回写进模板。
要动的地方超过补充规则的范围时，先把打算怎么改告诉用户。

## 现状与预期不符时

要写入的路径不是普通文件 / 目录时**停下来问用户**，不要照写。最常见的是软链：
`cp` 会写到它指向的地方，而 `mkdir -p` 在软链上仍然静默成功，表面看不出异常。
