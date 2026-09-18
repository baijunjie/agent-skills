---
name: workflow
description: 装上（或更新）通用 agent 工作流规范——注释规范、提交信息、分派子代理、编码结束自检，外加五个通用子代理。默认装进当前项目，也可装成本机用户级、对这台机器上的所有项目生效。用于"给这个项目配 agent 规范""装通用子代理""配一台新电脑""同步我的 agent 工作流""更新全局规则"等场景。
disable-model-invocation: true
---

# 安装 agent 工作流规范

一份规则正文（注释规范 / Git 提交信息 / 分派子代理 / 编码结束自检）加五个通用子代理。

补充说明（可选）：

<task>
$ARGUMENTS
</task>

## 选作用域

**默认装进当前项目**，随仓库提交。**整份装齐**，不要因为「用户级可能已经装过」而缩水。

用户明确说了「全局 / 本机 / 用户级 / 所有项目 / 新电脑」，或当前目录不是 git 仓库时，
才走「用户级安装」——那一份只对这台机器上的自己生效，是个人偏好，不进任何仓库。

两层会同时加载，同名节以项目的为准，不必为此少装哪一层。

## 项目安装（默认）

1. **追加规则节**：目标是项目根目录的 `CLAUDE.md`，没有就新建；它是符号链接时写它指向的实际文件。
   **先看目标文件里有没有同名节**，有就转「已存在时」逐节比对，不要执行下面的 `cat`——
   追加完再手工删是最该避免的。

   ```bash
   cat "$CLAUDE_PLUGIN_ROOT/skills/workflow/template/rules.md" >> CLAUDE.md
   ```

   `$CLAUDE_PLUGIN_ROOT` 为空时用本 skill 目录下的 `template/rules.md`。
   追加后删掉模板顶部的 `# 全局规则` 标题和它下面那句「与项目自己的指令文件冲突时，以项目的为准」——
   这份现在就是项目自己的规则，那句话不成立。其余各节按目标文件的标题层级对齐。
2. **装子代理**：

   ```bash
   mkdir -p .claude/agents
   cp -n "$CLAUDE_PLUGIN_ROOT/skills/workflow/template/agents/"*.md .claude/agents/
   ```

   **装进项目的 `.claude/agents/`，不是用户级配置目录（默认 `~/.claude`）下的 `agents/`**；已有同名文件 `cp -n` 会静默跳过，
   跳过了就转「已存在时」，不要当成装好了。
   「编码结束自检」点名要派的 `code-reviewer` 就在这批里，不装它那条规则就落空。
3. **告知用户**：`CLAUDE.md` 与 `.claude/agents/` 的改动要提交进版本库才随仓库生效；
   `.gitignore` 整体忽略了 `.claude/` 的项目要为 `.claude/agents/` 加例外，否则子代理提交不进去。
   `CLAUDE.md` 在会话开始时读取，当前会话不会自动重读，下次会话生效。
   本机用户级也装过同一套时，两层都会加载，同名节以项目这份为准。

## 用户级安装

装进**当前会话的用户级配置目录**，对这台机器上的所有项目生效。这个目录由 Claude Code 的
`CLAUDE_CONFIG_DIR` 决定，没设就是 `~/.claude`；下面的命令用 `C` 指代它，不要写死路径。

1. **写规则正文**：

   ```bash
   C=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
   mkdir -p "$C"
   cat "$CLAUDE_PLUGIN_ROOT/skills/workflow/template/rules.md" >> "$C/CLAUDE.md"
   ```

   `$CLAUDE_PLUGIN_ROOT` 为空时用本 skill 目录下的 `template/rules.md`。
   文件里已有本模板的同名节时转「已存在时」，不要追加出第二份。
   这一份要**保留**模板顶部那句「与项目自己的指令文件冲突时，以项目的为准」——
   它就是用户级与项目级同时加载时优先级的依据，别顺手删掉。
2. **装子代理**：

   ```bash
   C=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
   mkdir -p "$C/agents"
   cp -n "$CLAUDE_PLUGIN_ROOT/skills/workflow/template/agents/"*.md "$C/agents/"
   ```

   已有同名文件 `cp -n` 会静默跳过，跳过了就转「已存在时」，不要当成装好了。
   **这一步与上一步各自独立**：规则正文已经有了、子代理没装，仍然要把这一步做完——
   「编码结束自检」点名要派的 `code-reviewer` 就在这批里。
3. **告知用户**：装到了哪个用户级配置目录要说清楚（用户可能开着多个）；以后改规则直接改那两处，
   但**要重启 Claude Code 才重新加载**。

## 已存在时

已有内容时不要覆盖：与 `template/rules.md`、`template/agents/` 逐节比对，补齐模板有而它没有的，保留本机 / 本项目自己加的。
反过来，本机有而模板没有、且不是这台机器专属的内容，回写进模板。
要动的地方超过补充规则的范围时，先把打算怎么改告诉用户。

## 现状与预期不符时

要写入的路径不是普通文件 / 目录时**停下来问用户**，不要照写。最常见的是软链：
`cat >>` 与 `cp` 会写到它指向的地方，而 `mkdir -p` 在软链上仍然静默成功，表面看不出异常。
